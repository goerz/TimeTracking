// The Apple Health import's write: replacing the sleep or workout periods
// from a time on (data_and_sync.md §1.9, §7.1).

public import Foundation
import GRDB

extension StoreTransaction {
    /// Makes the live `kind` periods starting at or after `start` equal
    /// `intervals`, without activity or distance; see the draft form.
    @discardableResult
    public func replaceHealthPeriods(_ kind: HealthPeriod.Kind, from start: Date, with intervals: [DateInterval]) throws -> Int {
        try replaceHealthPeriods(kind, from: start, with: intervals.map { HealthPeriodDraft($0) })
    }

    /// Makes the live `kind` periods starting at or after `start` equal
    /// `drafts` (those starting earlier are ignored): a period with the
    /// same start and end keeps its record, updated when its activity or
    /// distance differs; the others become tombstones, and the new ones
    /// are created. Returns the number of records changed.
    @discardableResult
    public func replaceHealthPeriods(_ kind: HealthPeriod.Kind, from start: Date, with drafts: [HealthPeriodDraft]) throws -> Int {
        struct Key: Hashable {
            var start: Int64
            var end: Int64
        }
        let existing = try Row.fetchAll(
            database,
            sql: "SELECT * FROM health_period WHERE kind = ? AND start >= ? AND deleted_at IS NULL",
            arguments: [kind.rawValue, Time.seconds(start)]
        ).map(HealthPeriod.init(row:))
        var wanted: [Key: HealthPeriodDraft] = [:]
        for draft in drafts where draft.interval.start >= start {
            wanted[Key(start: Time.seconds(draft.interval.start), end: Time.seconds(draft.interval.end))] = draft
        }
        var kept: Set<Key> = []
        var changed = 0
        for period in existing {
            let key = Key(start: Time.seconds(period.start), end: Time.seconds(period.end))
            var updated = period
            if let draft = wanted[key], !kept.contains(key) {
                kept.insert(key)
                updated.activity = draft.activity
                updated.distance = draft.distance
            } else {
                updated.deletedAt = now
            }
            if updated != period {
                try write(updated)
                changed += 1
            }
        }
        for (key, draft) in wanted.sorted(by: { $0.key.start < $1.key.start }) where !kept.contains(key) {
            try write(HealthPeriod(
                kind: kind,
                start: Time.date(key.start),
                end: Time.date(key.end),
                activity: draft.activity,
                distance: draft.distance,
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
