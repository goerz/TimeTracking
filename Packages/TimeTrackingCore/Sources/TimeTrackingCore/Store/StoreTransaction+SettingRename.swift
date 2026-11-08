// The rename of the start of day's key from `day.midnightHour` to
// `day.startHour` (data_and_sync.md §8).

import Foundation
import GRDB

extension StoreTransaction {
    /// The start of day's key before the rename.
    static let legacyStartOfDayKey = "day.midnightHour"

    /// Moves a live `day.midnightHour` record to `day.startHour` when no live
    /// `day.startHour` exists, and tombstones the old record either way.
    /// `TimeStore` runs this in every write, so it runs when the store opens
    /// and on each record sync brings from a device with an older app.
    ///
    /// The new record keeps the old one's `modified_at`, so a start of day
    /// chosen later on another device wins over it and two devices moving
    /// the same record write equal rows. The tombstone is one millisecond
    /// later than the record it replaces, likewise the same on every device.
    /// Running it again changes nothing.
    func renameLegacySettings() throws {
        guard let old = try Row.fetchOne(
            database,
            sql: "SELECT value, modified_at FROM setting WHERE key = ? AND deleted_at IS NULL",
            arguments: [Self.legacyStartOfDayKey]
        ) else {
            return
        }
        let value: String = old["value"]
        let stamp: Int64 = old["modified_at"]
        let key = SyncedSettingKey<Int>.startOfDayHour.name
        let current = try Row.fetchOne(database, sql: "SELECT modified_at, deleted_at FROM setting WHERE key = ?", arguments: [key])
        let currentModified: Int64? = current?["modified_at"]
        let currentDeleted: Int64? = current?["deleted_at"]
        if current == nil || currentDeleted != nil {
            // Later than a tombstone of the new key, so the value does not lose to it.
            let modified = max(stamp, (currentModified ?? stamp - 1) + 1)
            try database.execute(
                sql: """
                INSERT INTO setting (key, value, modified_at, deleted_at) VALUES (?, ?, ?, NULL)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value, modified_at = excluded.modified_at, deleted_at = NULL
                """,
                arguments: [key, value, modified]
            )
            markChanged(SyncRecordRef(.setting, key))
        }
        try database.execute(
            sql: "UPDATE setting SET modified_at = ?, deleted_at = ? WHERE key = ?",
            arguments: [stamp + 1, (stamp + 1) / 1000, Self.legacyStartOfDayKey]
        )
        markChanged(SyncRecordRef(.setting, Self.legacyStartOfDayKey))
    }
}
