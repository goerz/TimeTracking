// The Apple Health import's write: replacing the sleep or workout periods
// from a time on (spec_data_and_sync.md §1.9, §7.1).

public import Foundation
import GRDB

extension StoreTransaction {
    /// Makes the live `kind` periods starting at or after `start` equal
    /// `intervals` (those starting earlier are ignored): a period with the
    /// same start and end keeps its record, the others become tombstones,
    /// and the new ones are created. Returns the number of records changed.
    @discardableResult
    public func replaceHealthPeriods(_ kind: HealthPeriod.Kind, from start: Date, with intervals: [DateInterval]) throws -> Int {
        struct Key: Hashable {
            var start: Int64
            var end: Int64
        }
        let existing = try Row.fetchAll(
            database,
            sql: "SELECT * FROM health_period WHERE kind = ? AND start >= ? AND deleted_at IS NULL",
            arguments: [kind.rawValue, Time.seconds(start)]
        ).map(HealthPeriod.init(row:))
        let wanted = Set(intervals.filter { $0.start >= start }.map { interval in
            Key(start: Time.seconds(interval.start), end: Time.seconds(interval.end))
        })
        let kept = Set(existing.map { Key(start: Time.seconds($0.start), end: Time.seconds($0.end)) })
        var changed = 0
        for period in existing where !wanted.contains(Key(start: Time.seconds(period.start), end: Time.seconds(period.end))) {
            var tombstone = period
            tombstone.deletedAt = now
            try write(tombstone)
            changed += 1
        }
        for key in wanted.subtracting(kept).sorted(by: { $0.start < $1.start }) {
            try write(HealthPeriod(
                kind: kind,
                start: Time.date(key.start),
                end: Time.date(key.end),
                createdAt: now,
                modifiedAt: modifiedAt
            ))
            changed += 1
        }
        return changed
    }

    private func write(_ period: HealthPeriod) throws {
        var period = period
        period.modifiedAt = modifiedAt
        try period.save(database)
        markChanged(SyncRecordRef(.healthPeriod, period.id.rawValue))
    }
}
