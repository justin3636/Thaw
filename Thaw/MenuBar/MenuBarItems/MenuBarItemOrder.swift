import Foundation

/// Durable order is independent of the section a trigger currently owns.
nonisolated struct MenuBarItemOrder: Codable, Equatable {
    enum IconPosition: String, Codable, CaseIterable {
        case left, right, ordered
    }

    var enabled = false
    var ranks: [String: Int] = [:]
    var iconPosition: IconPosition = .left

    func sorted(_ identifiers: [String], overrides: [String: Int] = [:]) -> [String] {
        let icon = MenuBarItemTag.visibleControlItem.tagIdentifier
        return identifiers.enumerated().sorted { lhs, rhs in
            if iconPosition != .ordered, lhs.element == icon || rhs.element == icon {
                return iconPosition == .left ? lhs.element == icon : rhs.element == icon
            }
            let a = overrides[lhs.element] ?? ranks[lhs.element] ?? Int.max
            let b = overrides[rhs.element] ?? ranks[rhs.element] ?? Int.max
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}
