// SampleStore: the raw samples in `samples.sqlite` (spec_activity_tracking.md
// §4.1: one row per tick, kept 90 days, never leaves the Mac).

import Foundation
import GRDB

/// The agent's sample database (GRDB, WAL), with a small key-value table
/// for the agent's own bookkeeping (event sources seen, backfill watermarks).
final class SampleStore {
    /// How long samples are kept.
    static let retention: TimeInterval = 90 * 86_400

    let database: any DatabaseWriter

    /// A row: the sample with the offset its line was written at.
    struct Row: Hashable {
        var id: Int64
        var sample: Sample
        var utcOffset: Int
    }

    /// Opens `url`, or an in-memory database for `nil`.
    init(url: URL?) throws {
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.database = try DatabasePool(path: url.path)
        } else {
            self.database = try DatabaseQueue()
        }
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.execute(sql: """
            CREATE TABLE sample (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                time REAL NOT NULL,
                utc_offset INTEGER NOT NULL,
                line TEXT NOT NULL
            );
            CREATE INDEX sample_time ON sample(time);
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)
        }
        migrator.registerMigration("v2") { database in
            try database.execute(sql: """
            CREATE TABLE device_event (
                name TEXT PRIMARY KEY,
                device TEXT NOT NULL,
                day TEXT NOT NULL,
                time REAL NOT NULL,
                utc_offset INTEGER NOT NULL,
                line TEXT NOT NULL
            );
            CREATE INDEX device_event_day ON device_event(device, day);
            CREATE INDEX device_event_time ON device_event(time);
            """)
        }
        try migrator.migrate(database)
    }

    func insert(_ sample: Sample, utcOffset: Int) throws {
        try database.write { database in
            try database.execute(
                sql: "INSERT INTO sample (time, utc_offset, line) VALUES (?, ?, ?)",
                arguments: [sample.time.timeIntervalSince1970, utcOffset, SampleCodec.line(sample, utcOffset: utcOffset)]
            )
        }
    }

    /// The samples in `[from, to)`, oldest first.
    func rows(from: Date, to: Date) throws -> [Row] {
        try database.read { database in
            try GRDB.Row.fetchAll(
                database,
                sql: "SELECT id, utc_offset, line FROM sample WHERE time >= ? AND time < ? ORDER BY time, id",
                arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]
            ).compactMap { row in
                let offset: Int = row["utc_offset"]
                let line: String = row["line"]
                return SampleCodec.sample(line, utcOffset: offset).map { Row(id: row["id"], sample: $0, utcOffset: offset) }
            }
        }
    }

    /// Every sample, oldest first.
    func allRows() throws -> [Row] {
        try rows(from: .distantPast, to: .distantFuture)
    }

    /// The raw line texts in `[from, to)` (tests check them byte for byte).
    func lines(from: Date = .distantPast, to: Date = .distantFuture) throws -> [String] {
        try database.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT line FROM sample WHERE time >= ? AND time < ? ORDER BY time, id",
                arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]
            )
        }
    }

    /// Replaces the line of row `id`.
    func update(_ id: Int64, with sample: Sample, utcOffset: Int) throws {
        try database.write { database in
            try database.execute(
                sql: "UPDATE sample SET line = ? WHERE id = ?",
                arguments: [SampleCodec.line(sample, utcOffset: utcOffset), id]
            )
        }
    }

    /// Deletes the samples in `[from, to)`.
    func delete(from: Date, to: Date) throws {
        try database.write { database in
            try database.execute(
                sql: "DELETE FROM sample WHERE time >= ? AND time < ?",
                arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]
            )
        }
    }

    /// Deletes samples older than `date`.
    func purge(before date: Date) throws {
        try delete(from: .distantPast, to: date)
    }

    /// The sample times in `[from, to)`, for finding when the agent was down.
    func times(from: Date, to: Date) throws -> [Date] {
        try database.read { database in
            try Double.fetchAll(
                database,
                sql: "SELECT time FROM sample WHERE time >= ? AND time < ? ORDER BY time",
                arguments: [from.timeIntervalSince1970, to.timeIntervalSince1970]
            )
        }.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Bookkeeping

    func value(_ key: String) throws -> String? {
        try database.read { database in try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }

    func setValue(_ value: String, for key: String) throws {
        try database.write { database in
            try database.execute(sql: "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", arguments: [key, value])
        }
    }

    func date(_ key: String) throws -> Date? {
        try value(key).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    }

    func setDate(_ date: Date, for key: String) throws {
        try setValue(String(date.timeIntervalSince1970), for: key)
    }
}
