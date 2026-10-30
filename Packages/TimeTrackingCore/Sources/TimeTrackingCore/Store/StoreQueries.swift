// StoreQueries: the lookups shared by the read side (`TimeStore`) and the
// write side (`StoreTransaction`) of the store (spec_data_and_sync.md §2.1, §7).

import Foundation
import GRDB

/// Lookups on an open database connection. `TimeStore` calls them inside
/// `read { }`, `StoreTransaction` with its own connection, so both sides
/// read chains, tombstones, and settings the same way.
enum StoreQueries {
    /// An entry by id; a tombstone only with `includeDeleted`.
    static func entry(_ id: EntryID, includeDeleted: Bool, in database: Database) throws -> TimeEntry? {
        let sql = "SELECT * FROM time_entry WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(TimeEntry.init(row:))
    }

    /// The live entries of the chain `root`, by start.
    static func chainEntries(root: EntryID, in database: Database) throws -> [TimeEntry] {
        try Row.fetchAll(
            database,
            sql: "SELECT * FROM time_entry WHERE deleted_at IS NULL AND (id = ? OR split_root_id = ?) ORDER BY start, id",
            arguments: [root.rawValue, root.rawValue]
        ).map(TimeEntry.init(row:))
    }

    /// The earliest start of the live entries of the chain `root`.
    static func chainStart(root: EntryID, in database: Database) throws -> Date? {
        try Int64.fetchOne(
            database,
            sql: "SELECT MIN(start) FROM time_entry WHERE deleted_at IS NULL AND (id = ? OR split_root_id = ?)",
            arguments: [root.rawValue, root.rawValue]
        ).map { Time.date($0) }
    }

    /// A project by id; a tombstone only with `includeDeleted`.
    static func project(_ id: ProjectID, includeDeleted: Bool, in database: Database) throws -> Project? {
        let sql = "SELECT * FROM project WHERE id = ?" + (includeDeleted ? "" : " AND deleted_at IS NULL")
        return try Row.fetchOne(database, sql: sql, arguments: [id.rawValue]).map(Project.init(row:))
    }

    /// The value of a synced setting, or its default when it is missing,
    /// deleted, or does not decode.
    static func settingValue<T>(_ key: SyncedSettingKey<T>, in database: Database) throws -> T {
        guard let json = try String.fetchOne(
            database,
            sql: "SELECT value FROM setting WHERE key = ? AND deleted_at IS NULL",
            arguments: [key.name]
        ) else {
            return key.defaultValue
        }
        return (try? JSONDecoder().decode(T.self, from: Data(json.utf8))) ?? key.defaultValue
    }
}
