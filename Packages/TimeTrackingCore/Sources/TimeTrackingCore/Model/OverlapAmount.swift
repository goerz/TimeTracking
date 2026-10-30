// OverlapAmount: how much other entries overlap one entry, for the
// Calendar card's warning (spec_planner_calendar.md §2.6).

public import Foundation

/// An entry overlapping another one by `seconds`.
public struct OverlapAmount: Sendable, Hashable {
    public var id: EntryID
    public var seconds: TimeInterval

    public init(id: EntryID, seconds: TimeInterval) {
        self.id = id
        self.seconds = seconds
    }

    /// The entries of `others` other than `id` that overlap `interval` by
    /// more than zero, in their order; touching intervals do not overlap.
    public static func amounts(
        overlapping interval: DateInterval,
        of id: EntryID,
        among others: [(EntryID, DateInterval)]
    ) -> [Self] {
        others.compactMap { other, otherInterval in
            guard other != id, let overlap = otherInterval.intersection(with: interval), overlap.duration > 0 else {
                return nil
            }
            return Self(id: other, seconds: overlap.duration)
        }
    }
}
