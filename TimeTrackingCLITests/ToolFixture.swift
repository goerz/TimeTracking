// ToolFixture: a synthetic store for the tool tests, built from a JSON
// export (spec_automation.md §9): "now" is 2026-10-29T10:00:00 in
// Europe/Berlin, a Thursday.

import Foundation
import SQLite3
import Testing

/// A temporary store loaded from the fixture document, and the tool run
/// against it with `TIMETRACKING_STORE`, `TIMETRACKING_NOW`, and `TZ`.
struct ToolFixture {
    static let zone = "Europe/Berlin"
    static let now = "2026-10-29T10:00:00"

    let folder: URL
    var store: URL {
        folder.appending(path: "store.sqlite")
    }

    /// A store with the fixture imported; `running` adds the entry that
    /// has run for 1812 seconds at "now".
    init(running: Bool = true) throws {
        self.folder = FileManager.default.temporaryDirectory.appending(path: "tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "fixture.json")
        try JSONSerialization.data(withJSONObject: Self.document(running: running)).write(to: file)
        let result = try run(["import", file.path, "--include-settings"])
        #expect(result.status == 0, "import failed: \(result.standardError)")
    }

    /// An empty folder without a store.
    init(empty _: Void) throws {
        self.folder = FileManager.default.temporaryDirectory.appending(path: "tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var environment: [String: String] {
        ["TIMETRACKING_STORE": store.path, "TIMETRACKING_NOW": Self.now, "TZ": Self.zone, "NO_COLOR": "1"]
    }

    func run(_ arguments: [String], environment extra: [String: String] = [:]) throws -> ToolResult {
        try ToolProcess.run("timetracking", arguments, environment: environment.merging(extra) { $1 })
    }

    /// Writes `text` to a file in the folder and returns its path.
    func write(_ text: String, named name: String) throws -> String {
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: SQLite

    /// The single integer `sql` returns, read with SQLite directly.
    func count(_ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(store.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw FixtureError.sqlite
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw FixtureError.sqlite
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// The store file's modification time.
    var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: store.path))?[.modificationDate] as? Date
    }

    enum FixtureError: Error {
        case sqlite
    }
}

/// Another process's write transaction: holds the store's write lock from
/// creation until `commit()`.
final class WriteLock {
    private var database: OpaquePointer?

    init(_ store: URL) throws {
        guard sqlite3_open_v2(store.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK
        else {
            sqlite3_close(database)
            throw ToolFixture.FixtureError.sqlite
        }
    }

    deinit {
        commit()
    }

    func commit() {
        guard let database else {
            return
        }
        sqlite3_exec(database, "COMMIT", nil, nil, nil)
        sqlite3_close(database)
        self.database = nil
    }
}

extension ToolFixture {
    // MARK: The document

    static let university = "c1000000-0000-4000-8000-000000000001"
    static let personal = "c1000000-0000-4000-8000-000000000002"
    static let side = "c1000000-0000-4000-8000-000000000003"
    static let universityGeneral = "a1000000-0000-4000-8000-000000000001"
    static let research = "a1000000-0000-4000-8000-000000000002"
    static let teaching = "a1000000-0000-4000-8000-000000000003"
    static let personalGeneral = "a1000000-0000-4000-8000-000000000004"
    static let sideGeneral = "a1000000-0000-4000-8000-000000000005"
    static let garden = "a1000000-0000-4000-8000-000000000006"
    static let noisePaper = "b1000000-0000-4000-8000-000000000001"
    static let oldPaper = "b1000000-0000-4000-8000-000000000002"
    static let universityAdmin = "b1000000-0000-4000-8000-000000000003"
    static let grading = "b1000000-0000-4000-8000-000000000004"
    static let sideAdmin = "b1000000-0000-4000-8000-000000000005"
    static let emile = "b1000000-0000-4000-8000-000000000006"
    static let runningEntry = "e1000000-0000-4000-8000-000000000099"
    static let device = "d1000000-0000-4000-8000-000000000001"

    /// The UTC timestamp of a Berlin wall-clock time.
    static func utc(_ local: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.dateFormat = local.count > 16 ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd'T'HH:mm"
        let date = formatter.date(from: local) ?? .distantPast
        return date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC") ?? .gmt))
    }

    static let created = "2026-01-05T08:00:00Z"

    static func client(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "name": name, "createdAt": created]
    }

    static func area(_ id: String, client: String, _ name: String, color: String, general: Bool = false, order: Int = 1) -> [String: Any] {
        [
            "id": id, "clientID": client, "name": name, "general": general, "color": color, "sortOrder": general ? 0 : order,
            "retired": false, "createdAt": created,
        ]
    }

    static func project(_ id: String, area: String, _ name: String, archived: Bool = false) -> [String: Any] {
        [
            "id": id, "areaID": area, "name": name, "archived": archived,
            "archivedAt": archived ? "2026-06-01T08:00:00Z" as Any : NSNull(), "createdAt": created,
        ]
    }

    static func entry(_ number: Int, project: String?, _ task: String, _ start: String, _ end: String?) -> [String: Any] {
        [
            "id": String(format: "e1000000-0000-4000-8000-%012d", number), "projectID": project ?? NSNull(), "task": task,
            "start": utc(start), "end": end.map(utc) ?? NSNull(), "timeZone": zone, "deviceID": device, "splitRootID": NSNull(),
        ]
    }

    /// The id of fixture entry `number`.
    static func entryID(_ number: Int) -> String {
        String(format: "e1000000-0000-4000-8000-%012d", number)
    }

    static func document(running: Bool) -> [String: Any] {
        var entries: [[String: Any]] = [
            entry(1, project: noisePaper, "Draft intro", "2026-10-20T09:00", "2026-10-20T11:00"),
            entry(2, project: universityAdmin, "Email", "2026-10-21T13:00", "2026-10-21T14:30"),
            entry(3, project: nil, "Misc", "2026-10-23T10:00", "2026-10-23T10:30"),
            entry(4, project: noisePaper, "Clarify noise model", "2026-10-28T09:00", "2026-10-28T10:00"),
            entry(5, project: grading, "Grade \"quiz\", part 2", "2026-10-29T08:00", "2026-10-29T09:00"),
            entry(6, project: oldPaper, "Old work", "2026-10-27T15:00", "2026-10-27T16:00"),
        ]
        if running {
            var item = entry(99, project: noisePaper, "Review", "2026-10-29T09:29:48", nil)
            item["id"] = runningEntry
            entries.append(item)
        }
        return [
            "format": 1,
            "generatedAt": "2026-10-29T09:00:00Z",
            "storeID": "f1000000-0000-4000-8000-000000000001",
            "clients": [client(university, "University"), client(personal, "Personal"), client(side, "Side business")],
            "areas": [
                area(universityGeneral, client: university, "University", color: "#6C757D", general: true),
                area(research, client: university, "Research", color: "#0A9396", order: 1),
                area(teaching, client: university, "Teaching", color: "#EE9B00", order: 2),
                area(personalGeneral, client: personal, "Personal", color: "#6C757D", general: true),
                area(garden, client: personal, "Garden", color: "#2A9D8F", order: 1),
                area(sideGeneral, client: side, "Side business", color: "#AE2012", general: true),
            ],
            "projects": [
                project(noisePaper, area: research, "Noise paper"),
                project(oldPaper, area: research, "Old paper", archived: true),
                project(universityAdmin, area: teaching, "Admin"),
                project(grading, area: teaching, "Grading"),
                project(sideAdmin, area: sideGeneral, "Admin"),
                project(emile, area: personalGeneral, "Émile notes"),
            ],
            "entries": entries,
            "settings": ["pomodoro.focusMinutes": 25],
            "devices": [["id": device, "name": "Test Mac", "platform": "mac"]],
        ]
    }
}
