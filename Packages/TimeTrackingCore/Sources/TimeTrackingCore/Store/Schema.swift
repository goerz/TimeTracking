// Schema: the documented SQLite schema and its migrations (spec_data_and_sync.md §2.1).

import Foundation
import GRDB

/// The store's schema. Migrations run forward on open and only add; a
/// newer `meta.schema_version` than `version` is refused.
enum Schema {
    /// The schema version this library writes.
    static let version = 1

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            for statement in version1 {
                try database.execute(sql: statement)
            }
        }
        return migrator
    }

    /// Migrates `writer` and checks the version; creates `meta` on a new file.
    static func prepare(_ writer: any DatabaseWriter, storeID: UUID = UUID()) throws {
        let found = try writer.read { database -> Int? in
            guard try database.tableExists("meta") else {
                return nil
            }
            return try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'schema_version'").flatMap { Int($0) }
        }
        if let found, found > version {
            throw StoreError.newerSchema(version: found)
        }
        let current = try writer.read { database in
            try migrator.hasCompletedMigrations(database)
                && String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'store_id'") != nil
        }
        // An up-to-date file is left untouched, so read-mostly openers
        // (a dry-run import) do not take the write lock for nothing.
        guard !current else {
            return
        }
        try migrator.migrate(writer)
        try writer.write { database in
            try database.execute(
                sql: "INSERT OR IGNORE INTO meta (key, value) VALUES ('schema_version', ?), ('store_id', ?)",
                arguments: [String(version), storeID.uuidString.lowercased()]
            )
        }
    }

    /// Checks the version of a read-only store without migrating.
    static func check(_ reader: any DatabaseReader) throws {
        let found = try reader.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'schema_version'").flatMap { Int($0) }
        }
        if let found, found > version {
            throw StoreError.newerSchema(version: found)
        }
    }

    private static let bookkeeping = "created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB"

    private static let version1: [String] = [
        "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
        "CREATE TABLE client (id TEXT PRIMARY KEY, name TEXT NOT NULL, \(bookkeeping))",
        """
        CREATE TABLE area (id TEXT PRIMARY KEY, client_id TEXT NOT NULL, name TEXT NOT NULL,
          general INTEGER NOT NULL DEFAULT 0, color TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0, retired INTEGER NOT NULL DEFAULT 0, \(bookkeeping))
        """,
        """
        CREATE TABLE project (id TEXT PRIMARY KEY, area_id TEXT NOT NULL, name TEXT NOT NULL,
          archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER, \(bookkeeping))
        """,
        """
        CREATE TABLE time_entry (id TEXT PRIMARY KEY, project_id TEXT, task TEXT NOT NULL DEFAULT '',
          task_key TEXT NOT NULL DEFAULT '', start INTEGER NOT NULL, "end" INTEGER, day TEXT NOT NULL,
          time_zone TEXT NOT NULL, device_id TEXT NOT NULL, split_root_id TEXT, \(bookkeeping))
        """,
        """
        CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL,
          modified_at INTEGER NOT NULL, deleted_at INTEGER, ck_system_fields BLOB)
        """,
        """
        CREATE TABLE device (id TEXT PRIMARY KEY, name TEXT NOT NULL, platform TEXT NOT NULL,
          last_seen_at INTEGER NOT NULL, widget_push_token TEXT,
          created_at INTEGER NOT NULL, modified_at INTEGER NOT NULL, ck_system_fields BLOB)
        """,
        """
        CREATE TABLE live_state (id INTEGER PRIMARY KEY CHECK (id = 1),
          running TEXT, changed_at INTEGER, activity TEXT NOT NULL DEFAULT '{}', ck_system_fields BLOB)
        """,
        """
        CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, record_type TEXT NOT NULL,
          record_id TEXT NOT NULL, queued_at INTEGER NOT NULL)
        """,
        "CREATE TABLE sync_state (key TEXT PRIMARY KEY, value BLOB NOT NULL)",
        // Private: ids hard-deleted after the retention period, so `restore`
        // can report `retentionExpired`.
        "CREATE TABLE purged_record (record_id TEXT PRIMARY KEY, record_type TEXT NOT NULL, purged_at INTEGER NOT NULL)",
        "CREATE INDEX time_entry_live_start ON time_entry (start) WHERE deleted_at IS NULL",
        "CREATE INDEX time_entry_live_day ON time_entry (day) WHERE deleted_at IS NULL",
        "CREATE INDEX time_entry_running ON time_entry (id) WHERE deleted_at IS NULL AND \"end\" IS NULL",
        "CREATE INDEX time_entry_live_task ON time_entry (project_id, task_key, start) WHERE deleted_at IS NULL",
        "CREATE INDEX time_entry_split_root ON time_entry (split_root_id) WHERE split_root_id IS NOT NULL",
        """
        CREATE VIEW entries AS
          SELECT e.id, e.start, e."end", e."end" - e.start AS seconds, e.day, e.task,
                 p.id AS project_id, p.name AS project, a.id AS area_id, a.name AS area, a.color,
                 c.id AS client_id, c.name AS client, e.device_id, e.time_zone
          FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
               LEFT JOIN area a ON a.id = p.area_id LEFT JOIN client c ON c.id = a.client_id
          WHERE e.deleted_at IS NULL
        """,
    ]
}
