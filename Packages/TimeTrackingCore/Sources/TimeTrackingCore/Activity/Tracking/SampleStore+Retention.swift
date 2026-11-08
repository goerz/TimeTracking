// SampleStore+Retention: the agent's first start and the daily drop of old
// Samples (activity_tracking.md §2.4, §4.1).

import Foundation
import GRDB

extension SampleStore {
    /// How long Samples are kept.
    public static let retentionDays = 90

    /// Records `today` as the date of the agent's first start, and as the
    /// cutoff date, unless a first start is already recorded. Dates before
    /// it are frozen, so a block log from another Mac stays as it is.
    public func recordFirstStart(today: TrackingDay) throws {
        try database.write { database in
            guard try database.meta(.firstStartDay) == nil else {
                return
            }
            try database.setMeta(.firstStartDay, today)
            try database.setMeta(.cutoffDay, today)
        }
    }

    /// The daily drop: moves the cutoff date one day toward today − 90 days,
    /// never before the first start, and only once the rebuild loop took
    /// every changed, placeholder, and pending remote date before the new
    /// cutoff; then deletes the Samples
    /// and deleted ranges before it. One day per drop, so a clock far ahead
    /// can't delete every Sample at once. Marks no date: those dates are
    /// frozen now. Returns the new cutoff, or `nil` when it stays.
    @discardableResult
    public func dropOldSamples(today: TrackingDay, rules: SampleRules) throws -> TrackingDay? {
        try database.write { database in
            guard let first = try database.meta(.firstStartDay) else {
                return nil
            }
            let current = try database.meta(.cutoffDay) ?? first
            guard current < max(today.adding(days: -Self.retentionDays), first) else {
                return nil
            }
            let next = current.adding(days: 1)
            // A date still waiting for a pass, a download, or a remote redo
            // would be frozen before its last rebuild.
            let changed: [TrackingDay] = try Array(database.meta(.changedDays) ?? [])
            let placeholders: [TrackingDay] = try Array(database.meta(.placeholderDays) ?? [])
            let remote: [TrackingDay] = try (database.meta(.pendingRemoteDays) ?? []).map(\.day)
            guard !(changed + placeholders + remote).contains(where: { $0 < next }) else {
                return nil
            }
            let boundaries = try Self.boundaries(rules, in: database)
            let start = boundaries.start(of: next)
            try Self.delete(SampleSelection(range: DateInterval(start: .distantPast, end: start)), in: database)
            try database.setMeta(.deletedRanges, (database.meta(.deletedRanges) ?? []).filter { $0.end > start })
            // The date before the cutoff keeps its offset and end: the next pass reads them.
            try database.setMeta(.dayOffsets, boundaries.offsets.filter { $0.key >= current })
            try database.setMeta(.dayEnds, (database.meta(.dayEnds) ?? [:]).filter { $0.key >= current })
            try database.setMeta(.cutoffDay, next)
            return next
        }
    }
}
