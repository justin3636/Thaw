import Foundation

extension MenuBarItemManager {
    func loadItemOrder() {
        if let data = Defaults.store.data(forKey: "MenuBarItemManager.itemOrder"),
           let stored = try? JSONDecoder().decode(MenuBarItemOrder.self, from: data) {
            itemOrder = stored
        }
        // Preserve the existing relative order on migration. Ranks have gaps
        // so a trigger can insert an item between two existing items.
        var next = (itemOrder.ranks.values.max() ?? 0) + 10
        for section in ["visible", "hidden", "alwaysHidden"] {
            for identifier in savedSectionOrder[section] ?? [] where itemOrder.ranks[identifier] == nil {
                itemOrder.ranks[identifier] = next
                next += 10
            }
        }
        savedSectionOrder = orderedSections(savedSectionOrder)
    }

    func registerObservedItemOrder() {
        var next = (itemOrder.ranks.values.max() ?? 0) + 10
        var changed = false
        for item in itemCache.managedItems where item.sourcePID != nil && itemOrder.ranks[item.tag.tagIdentifier] == nil {
            itemOrder.ranks[item.tag.tagIdentifier] = next
            next += 10
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(itemOrder) {
            Defaults.store.set(data, forKey: "MenuBarItemManager.itemOrder")
        }
    }

    func persistItemOrder() {
        orderFailures.removeAll()
        if let data = try? JSONEncoder().encode(itemOrder) {
            Defaults.store.set(data, forKey: "MenuBarItemManager.itemOrder")
        }
        savedSectionOrder = orderedSections(savedSectionOrder)
        persistSavedSectionOrder()
        scheduleOrderEnforcement()
    }

    func orderedSections(_ sections: [String: [String]]) -> [String: [String]] {
        guard itemOrder.enabled else { return sections }
        return sections.mapValues { itemOrder.sorted($0) }
    }

    func orderedItems(_ items: [MenuBarItem]) -> [MenuBarItem] {
        // Hosted items temporarily inherit Control Center's identity while
        // source resolution is pending. Sorting those names would move the
        // section once at startup and again when the real names arrive.
        guard itemOrder.enabled, !items.contains(where: \.hasProvisionalIdentity) else { return items }
        let indices = Dictionary(itemOrder.sorted(
            items.map(\.tag.tagIdentifier), overrides: triggerOrderOverrides
        ).enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        // macOS fixes Clock/Control Center at the right edge. Keep those
        // slots in their observed order instead of dragging across them.
        return items.filter(\.isMovable).sorted {
            indices[$0.tag.tagIdentifier, default: 0] < indices[$1.tag.tagIdentifier, default: 0]
        } + items.filter { !$0.isMovable }
    }

    /// Order-only repair never changes section membership. Triggers remain
    /// the sole owner of their items' reveal/hide decisions.
    func scheduleOrderEnforcement() {
        guard itemOrder.enabled, orderEnforcementTask == nil, appState != nil else { return }
        orderEnforcementTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }
            var moved = false
            defer {
                self.orderEnforcementTask = nil
                if moved { self.scheduleOrderEnforcement() }
            }
            guard !Task.isCancelled, !self.isResettingLayout,
                  !self.isRestoringItemOrder, !self.isApplyingProfileLayout,
                  !self.isBulkApplyInProgress, self.temporarilyShownItemContexts.isEmpty,
                  self.appState?.settings.triggers.pendingMoveReveal.isEmpty == true,
                  self.itemOrder.enabled else { return }
            // Bound each pass; subsequent cache changes continue repairs.
            for section in MenuBarSection.Name.allCases {
                let actual = self.itemCache[section]
                let desired = self.orderedItems(actual)
                guard actual.map(\.windowID) != desired.map(\.windowID) else { continue }
                let insertions = MenuBarItemOrder.leftwardInsertions(
                    actual: actual.map(\.windowID), desired: desired.map(\.windowID)
                )
                for insertion in insertions {
                    guard let item = actual.first(where: { $0.windowID == insertion.source }), item.isMovable,
                          let next = actual.first(where: { $0.windowID == insertion.target }) else { continue }
                    let identifier = item.tag.tagIdentifier
                    if let failure = self.orderFailures[identifier], Date() < failure.retryAfter { continue }
                    do {
                        try await self.move(item: item, to: .leftOfItem(next), on: self.itemCache.displayID,
                            options: .init(requiredInputPause: .milliseconds(100), inputPauseTimeout: .milliseconds(500),
                                           maxMoveAttempts: 1, hideCursorAcrossAttempts: false,
                                           shouldBegin: { [weak self] in
                                               self?.itemOrder.enabled == true &&
                                               self?.isApplyingProfileLayout == false &&
                                               self?.isBulkApplyInProgress == false &&
                                               self?.appState?.settings.triggers.pendingMoveReveal.isEmpty == true &&
                                               item.liveBounds == item.bounds && next.liveBounds == next.bounds
                                           }))
                        self.orderFailures[identifier] = nil
                        moved = true
                        await self.cacheItemsRegardless(skipRecentMoveCheck: true)
                    } catch EventError.moveSuperseded, EventError.inputPauseTimedOut {
                        await self.cacheItemsRegardless(skipRecentMoveCheck: true)
                    } catch {
                        // A refused automatic drag is not a reason to keep
                        // taking the user's pointer. Editing the order clears
                        // this latch explicitly in persistItemOrder().
                        self.orderFailures[identifier] = (1, .distantFuture)
                        Self.diagLog.debug("Order repair deferred: \(error)")
                        await self.cacheItemsRegardless(skipRecentMoveCheck: true)
                    }
                    return
                }
            }
        }
    }
}
