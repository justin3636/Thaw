import Foundation

/// Durable order is independent of the section a trigger currently owns.
nonisolated struct MenuBarItemOrder: Codable, Equatable {
    enum IconPosition: String, Codable, CaseIterable {
        case left, right, ordered
    }

    var enabled = false
    var ranks: [String: Int] = [:]
    var iconPosition: IconPosition = .left

    /// Parked drops reliably prepend to the section, even when an interior
    /// anchor was requested. Grow the desired suffix in relative order by
    /// prepending its next predecessor to the actual leftmost item. Each
    /// successful step extends that suffix, finishing in at most n - 1 moves.
    static func leftwardInsertions<ID: Hashable>(
        actual: [ID], desired: [ID]
    ) -> [(source: ID, target: ID)] {
        guard let first = actual.first else { return [] }
        var suffixStart = actual.count
        for identifier in desired.reversed() {
            guard let index = actual.firstIndex(of: identifier) else { return [] }
            if index > suffixStart {
                return [(source: identifier, target: first)]
            }
            suffixStart = index
        }
        return []
    }

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
