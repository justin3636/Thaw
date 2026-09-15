import CoreGraphics
import Foundation
import Testing
@testable import Thaw

@MainActor
struct MenuBarItemOrderTests {
    @Test func editorDropsHonorEndSlotsAndCrossSectionTargets() {
        #expect(MenuBarItemOrder.editorDropOrder(
            actual: ["codex", "hammerspoon", "passwords"], source: "hammerspoon", target: "passwords", after: true
        ) == ["codex", "passwords", "hammerspoon"])
        #expect(MenuBarItemOrder.editorDropOrder(
            actual: ["dockdoor", "hotspot", "dropbox"], source: "walyro", target: "dropbox", after: false
        ) == ["dockdoor", "hotspot", "walyro", "dropbox"])
        #expect(MenuBarItemOrder.editorDropOrder(
            actual: [String](), source: "walyro", target: "divider", after: false
        ) == ["walyro"])
    }

    @Test func successfulManualDropUpdatesRanksWithoutChangingOtherSections() {
        var order = MenuBarItemOrder(ranks: ["codex": 70, "hammerspoon": 90, "passwords": 140, "tv": 180])
        order.adoptOrder(["codex", "passwords", "hammerspoon"])
        #expect(order.sorted(["codex", "hammerspoon", "passwords"]) == ["codex", "passwords", "hammerspoon"])
        #expect(order.ranks["tv"] == 180)
        order.ranks["hammerspoon"] = 70
        order.adoptOrder(["hammerspoon", "codex", "passwords"])
        #expect(order.sorted(["passwords", "codex", "hammerspoon"]) == ["hammerspoon", "codex", "passwords"])
    }

    @Test func roomListenerIsOrderedByMovingNeighborsLeft() throws {
        var actual = ["room", "codex", "hammerspoon", "teams", "walyro", "battery", "passwords"]
        let desired = ["codex", "hammerspoon", "teams", "walyro", "battery", "room", "passwords"]
        var moved = [String]()
        for _ in 0..<5 {
            let step = try #require(MenuBarItemOrder.leftwardInsertions(actual: actual, desired: desired).first)
            #expect(step.source != "room")
            let source = try #require(actual.firstIndex(of: step.source))
            let target = try #require(actual.firstIndex(of: step.target))
            #expect(source > target)
            #expect(target == 0)
            actual.insert(actual.remove(at: source), at: target)
            moved.append(step.source)
        }
        #expect(actual == desired)
        #expect(moved == ["battery", "walyro", "teams", "hammerspoon", "codex"])
        #expect(MenuBarItemOrder.leftwardInsertions(actual: actual, desired: desired).isEmpty)
    }

    @Test func leftwardRepairsConvergeForEveryFiveItemPermutation() throws {
        func permutations(_ items: [Int]) -> [[Int]] {
            guard !items.isEmpty else { return [[]] }
            return items.flatMap { first in
                permutations(items.filter { $0 != first }).map { [first] + $0 }
            }
        }
        let desired = [0, 1, 2, 3, 4]
        for initial in permutations(desired) {
            var actual = initial
            for _ in 0..<desired.count - 1 where actual != desired {
                let step = try #require(MenuBarItemOrder.leftwardInsertions(actual: actual, desired: desired).first)
                let source = try #require(actual.firstIndex(of: step.source))
                let target = try #require(actual.firstIndex(of: step.target))
                #expect(source > target)
                #expect(target == 0)
                actual.insert(actual.remove(at: source), at: target)
            }
            #expect(actual == desired)
        }
    }

    @Test func orderingWaitsForResolvedIdentities() {
        let manager = MenuBarItemManager()
        let known = MenuBarItem.fixture(tag: .appItem(bundleID: "com.example.known", title: "Item"), windowID: 1)
        let provisionalTag = MenuBarItemTag(namespace: .controlCenter, title: "JW.AC")
        let provisional = MenuBarItem.fixture(tag: provisionalTag, windowID: 2, sourcePID: nil)
        manager.itemOrder = MenuBarItemOrder(enabled: true, ranks: [known.tag.tagIdentifier: 20, provisional.tag.tagIdentifier: 10])
        #expect(manager.orderedItems([known, provisional]).map(\.windowID) == [1, 2])
        let resolved = MenuBarItem.fixture(tag: provisionalTag, windowID: 2, sourcePID: 1234)
        #expect(manager.orderedItems([known, resolved]).map(\.windowID) == [2, 1])
    }

    @Test func triggerOverridesDoNotChangeBaseline() {
        let order = MenuBarItemOrder(ranks: ["a": 10, "b": 20, "c": 30])
        #expect(order.sorted(["a", "b", "c"], overrides: ["c": 15]) == ["a", "c", "b"])
        #expect(order.sorted(["c", "a", "b"]) == ["a", "b", "c"])
    }

    @Test func iconConstraintWinsOverTriggerOverride() {
        let icon = MenuBarItemTag.visibleControlItem.tagIdentifier
        var order = MenuBarItemOrder(ranks: ["a": 10, icon: 20])
        #expect(order.sorted(["a", icon], overrides: ["a": -100]) == [icon, "a"])
        order.iconPosition = .right
        #expect(order.sorted([icon, "a"]) == ["a", icon])
    }

    @Test func tiesAndUnknownItemsKeepTheirRelativeOrder() {
        let order = MenuBarItemOrder(ranks: ["a": 10, "b": 10])
        #expect(order.sorted(["x", "b", "a", "y"]) == ["b", "a", "x", "y"])
    }

    @Test func triggerOrderRoundTrips() throws {
        let trigger = MenuBarItemTrigger(revealOrderOverride: 15, hideOrderOverride: 70)
        let data = try JSONEncoder().encode(trigger)
        let restored = try JSONDecoder().decode(MenuBarItemTrigger.self, from: data)
        #expect(restored.revealOrderOverride == 15)
        #expect(restored.hideOrderOverride == 70)
        var old = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "revealOrderOverride")
        old.removeValue(forKey: "hideOrderOverride")
        let legacy = try JSONDecoder().decode(MenuBarItemTrigger.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.revealOrderOverride == nil)
        #expect(legacy.hideOrderOverride == nil)
    }

    @Test func retriesBackOffAndRemainBounded() {
        #expect([1, 2, 3, 4, 5, 6, 100].map { MenuBarItemTriggersManager.retryDelay(failureCount: $0) } == [1, 2, 4, 8, 16, 30, 30])
    }

    @Test func iconHashesIgnoreTransparentFramingAndRejectEmptyCaptures() throws {
        func icon(height: Int, offset: Int, draw: Bool = true) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: 72, height: height,
                bitsPerComponent: 8, bytesPerRow: 72 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            if draw {
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 20, y: offset, width: 12, height: 22))
                context.setFillColor(CGColor(gray: 0.4, alpha: 1))
                context.fill(CGRect(x: 32, y: offset + 4, width: 14, height: 10))
            }
            return try #require(context.makeImage())
        }
        let visible = try icon(height: 78, offset: 20)
        let hidden = try icon(height: 62, offset: 12)
        #expect(ImageHashing.averageHash(visible) == ImageHashing.averageHash(hidden))
        #expect(ImageHashing.exactHash(visible) == ImageHashing.exactHash(hidden))
        #expect(ImageHashing.averageHash(try icon(height: 78, offset: 0, draw: false)) == nil)
    }

    @Test func parkedItemMayRetainOnScreenFlag() {
        let displays = [MenuBarItemManager.MoveDisplayGeometry(id: 1, bounds: CGRect(x: 0, y: 0, width: 1710, height: 1112))]
        #expect(MenuBarItemManager.moveEndpointDisposition(
            bounds: CGRect(x: -9151, y: 0, width: 36, height: 39), isOnScreen: true,
            selectedDisplayID: 1, displays: displays, parkedLaneYRange: 0...39,
            controlDividerX: 1426) == .parked)
        let bounds = CGRect(x: -3590, y: 0, width: 5016, height: 39)
        let divider = MenuBarItem.fixture(tag: .hiddenControlItem, windowID: 123, bounds: bounds, isOnScreen: false)
        #expect(MenuBarItemManager.MoveDestination.leftOfItem(divider).targetPoint(in: bounds, on: displays[0].bounds) == CGPoint(x: -3591, y: 19.5))
    }

    @Test func wideDividerUsesVisibleEdge() {
        let displays = [MenuBarItemManager.MoveDisplayGeometry(id: 1, bounds: CGRect(x: 0, y: 0, width: 1710, height: 1112))]
        let bounds = CGRect(x: -3923, y: 0, width: 5016, height: 24)
        #expect(MenuBarItemManager.moveEndpointDisposition(bounds: bounds, isOnScreen: true,
            selectedDisplayID: 1, displays: displays, parkedLaneYRange: 0...24,
            controlDividerX: 1093, isSectionDivider: true) == .parked)
        #expect(MenuBarItemManager.moveEndpointDisposition(bounds: bounds, isOnScreen: true,
            selectedDisplayID: 1, displays: displays, parkedLaneYRange: 0...24,
            controlDividerX: 1093) == .invalid)
    }
}
