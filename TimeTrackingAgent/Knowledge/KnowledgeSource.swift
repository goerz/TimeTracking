// KnowledgeSource: the macOS Knowledge store, read from a copy
// (spec_activity_tracking.md §3.2, phase 5).

import Foundation
import GRDB
import os
import TimeTrackingCore

/// An app interval of `/app/usage`.
nonisolated struct KnowledgeAppInterval: Hashable, Sendable {
    var start: Date
    var end: Date
    var bundleID: String
}

/// A Safari dwell interval of `/app/webUsage`.
nonisolated struct KnowledgeWebInterval: Hashable, Sendable {
    var start: Date
    var end: Date
    var url: String
}

/// What one read of the Knowledge store gives.
nonisolated enum KnowledgeRead: Hashable, Sendable {
    case data(apps: [KnowledgeAppInterval], web: [KnowledgeWebInterval], displayOff: [DateInterval])
    /// The store cannot be used; the reason goes to health.
    case unavailable(String)
}

/// Reads the Knowledge store.
protocol KnowledgeSource {
    func read(from: Date, to: Date) -> KnowledgeRead
}

/// Reads `knowledgeC.db` (and its WAL) through a copy in a temporary
/// folder, after checking that the schema is the expected one.
struct KnowledgeStoreReader: KnowledgeSource {
    static let requiredObjectColumns: Set = ["ZSTREAMNAME", "ZSTARTDATE", "ZENDDATE", "ZVALUESTRING", "ZSTRUCTUREDMETADATA"]
    static let webURLColumn = "Z_DKDIGITALHEALTHMETADATAKEY__WEBPAGEURL"

    /// The live database, e.g. `~/Library/Application Support/Knowledge/knowledgeC.db`.
    var databasePath: String

    static func defaultPath(home: String) -> String {
        home + "/Library/Application Support/Knowledge/knowledgeC.db"
    }

    func read(from: Date, to: Date) -> KnowledgeRead {
        let manager = FileManager.default
        guard manager.fileExists(atPath: databasePath) else {
            return .unavailable("macOS app usage history was not found")
        }
        let folder = manager.temporaryDirectory.appending(path: "knowledge-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: folder) }
        let copy = folder.appending(path: "knowledgeC.db", directoryHint: .notDirectory)
        do {
            try SQLiteSnapshot.copy(path: databasePath, to: copy)
        } catch {
            return .unavailable("Full Disk Access is off; macOS app usage history can't be read")
        }
        do {
            let queue = try DatabaseQueue(path: copy.path)
            return try queue.read { database in try Self.query(database, from: from, to: to) }
        } catch {
            Logging.logger(category: "Agent").error("Knowledge store: \(error.localizedDescription, privacy: .public)")
            return .unavailable("macOS app usage history can't be read")
        }
    }

    /// The reason for a Knowledge store whose schema is not the expected
    /// one; the details go to the log.
    static let unexpectedSchemaReason = "macOS changed how it stores app usage; this version can't read it"

    /// Checks the schema and reads the three streams.
    static func query(_ database: Database, from: Date, to: Date) throws -> KnowledgeRead { // swiftlint:disable:this cyclomatic_complexity
        guard try database.tableExists("ZOBJECT") else {
            Logging.logger(category: "Agent").error("Unexpected Knowledge store schema: no ZOBJECT table")
            return .unavailable(unexpectedSchemaReason)
        }
        let objectColumns = try Set(database.columns(in: "ZOBJECT").map { $0.name.uppercased() })
        guard requiredObjectColumns.isSubset(of: objectColumns) else {
            let missing = requiredObjectColumns.subtracting(objectColumns).sorted().joined(separator: ", ")
            Logging.logger(category: "Agent").error("Unexpected Knowledge store schema: ZOBJECT lacks \(missing, privacy: .public)")
            return .unavailable(unexpectedSchemaReason)
        }
        var hasWeb = false
        if try database.tableExists("ZSTRUCTUREDMETADATA") {
            hasWeb = try database.columns(in: "ZSTRUCTUREDMETADATA").contains { $0.name.uppercased() == webURLColumn }
        }
        let urlColumn = hasWeb ? "m.\(webURLColumn)" : "NULL"
        let flagColumn = objectColumns.contains("ZVALUEINTEGER") ? "o.ZVALUEINTEGER" : "NULL"
        let join = hasWeb ? "LEFT JOIN ZSTRUCTUREDMETADATA m ON o.ZSTRUCTUREDMETADATA = m.Z_PK" : ""
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT o.ZSTREAMNAME AS stream, o.ZSTARTDATE AS start, o.ZENDDATE AS end, o.ZVALUESTRING AS value,
                   \(flagColumn) AS flag, \(urlColumn) AS url
            FROM ZOBJECT o \(join)
            WHERE o.ZSTREAMNAME IN ('/app/usage', '/app/webUsage', '/display/isBacklit')
              AND o.ZENDDATE >= ? AND o.ZSTARTDATE <= ?
            ORDER BY o.ZSTARTDATE
            """,
            arguments: [from.timeIntervalSinceReferenceDate, to.timeIntervalSinceReferenceDate]
        )
        var apps: [KnowledgeAppInterval] = []
        var web: [KnowledgeWebInterval] = []
        var displayOff: [DateInterval] = []
        for row in rows {
            guard let stream: String = row["stream"], let startValue: Double = row["start"], let endValue: Double = row["end"],
                  endValue >= startValue
            else {
                continue
            }
            let start = Date(timeIntervalSinceReferenceDate: startValue)
            let end = Date(timeIntervalSinceReferenceDate: endValue)
            let value: String? = row["value"]
            switch stream {
            case "/app/usage":
                if let value, !value.isEmpty {
                    apps.append(KnowledgeAppInterval(start: start, end: end, bundleID: value))
                }
            case "/app/webUsage":
                if let url: String = row["url"], !url.isEmpty {
                    web.append(KnowledgeWebInterval(start: start, end: end, url: url))
                }
            default:
                // `/display/isBacklit` with value 0 is a display-off interval.
                let flag: Int? = row["flag"]
                if flag == 0 {
                    displayOff.append(DateInterval(start: start, end: end))
                }
            }
        }
        return .data(apps: apps, web: web, displayOff: displayOff)
    }
}
