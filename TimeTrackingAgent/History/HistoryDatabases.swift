// HistoryDatabases: Safari's History.db and CloudTabs.db and Chromium's
// History files, read from copies (activity_tracking.md §3.3, §6.1).

// The seams answer nil for "cannot read", which differs from an empty answer.
// swiftlint:disable discouraged_optional_collection discouraged_optional_boolean

import Foundation
import GRDB

/// Reads browser histories from copies refreshed when the live file changes
/// (at most every 10 seconds). Paths are injectable for tests.
final class HistoryDatabases: BrowserHistory {
    static let refreshInterval: TimeInterval = 10
    /// Chromium counts microseconds since 1601-01-01.
    static let chromiumEpochOffset: TimeInterval = 11_644_473_600

    let safariPath: String
    let cloudTabsPaths: [String]
    /// Context and `History` file of each Chromium profile.
    let chromiumProfiles: () -> [(context: String, path: String)]
    private var copies: [String: DatabaseCopy] = [:]
    private let folder: URL

    init(safariPath: String, cloudTabsPaths: [String], chromiumProfiles: @escaping () -> [(context: String, path: String)]) {
        self.safariPath = safariPath
        self.cloudTabsPaths = cloudTabsPaths
        self.chromiumProfiles = chromiumProfiles
        self.folder = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// The live paths of `home`.
    static func live(home: String) -> HistoryDatabases {
        HistoryDatabases(
            safariPath: home + "/Library/Safari/History.db",
            cloudTabsPaths: [
                home + "/Library/Containers/com.apple.Safari/Data/Library/Safari/CloudTabs.db",
                home + "/Library/Safari/CloudTabs.db",
            ]
        ) {
            var result: [(String, String)] = []
            for (context, relative) in BrowserApp.chromiumProfileRoots {
                let root = home + "/" + relative
                for profile in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] {
                    let path = root + "/" + profile + "/History"
                    if FileManager.default.fileExists(atPath: path) {
                        result.append((context, path))
                    }
                }
            }
            return result
        }
    }

    var canReadSafari: Bool {
        FileManager.default.isReadableFile(atPath: safariPath) && FileHandle(forReadingAtPath: safariPath) != nil
    }

    func safariVisits(from: Date, to: Date, origin: Int) -> [HistoryVisit]? {
        query(safariPath) { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT v.visit_time AS time, i.url AS url, COALESCE(v.title, '') AS title
                FROM history_visits v JOIN history_items i ON v.history_item = i.id
                WHERE v.visit_time >= ? AND v.visit_time <= ? AND v.origin = ?
                ORDER BY v.visit_time
                """,
                arguments: [from.timeIntervalSinceReferenceDate, to.timeIntervalSinceReferenceDate, origin]
            ).map { row in
                HistoryVisit(
                    time: Date(timeIntervalSinceReferenceDate: row["time"]),
                    browser: "safari",
                    url: row["url"],
                    title: row["title"]
                )
            }
        }
    }

    func hasSafariVisit(url: String, since: Date) -> Bool? {
        query(safariPath) { database in
            try Bool.fetchOne(
                database,
                sql: """
                SELECT 1 FROM history_visits v JOIN history_items i ON v.history_item = i.id
                WHERE i.url = ? AND v.visit_time >= ? AND v.origin = 0 LIMIT 1
                """,
                arguments: [url, since.timeIntervalSinceReferenceDate]
            ) ?? false
        }
    }

    func chromiumVisits(from: Date, to: Date) -> [HistoryVisit] {
        var result: [HistoryVisit] = []
        for profile in chromiumProfiles() {
            let visits = query(profile.path) { database in
                try Row.fetchAll(
                    database,
                    sql: """
                    SELECT v.visit_time AS time, u.url AS url, COALESCE(u.title, '') AS title
                    FROM visits v JOIN urls u ON v.url = u.id
                    WHERE v.visit_time >= ? AND v.visit_time <= ? ORDER BY v.visit_time
                    """,
                    arguments: [Self.chromiumTime(from), Self.chromiumTime(to)]
                ).map { row in
                    let micro: Int64 = row["time"]
                    let time = Date(timeIntervalSince1970: TimeInterval(micro) / 1_000_000 - Self.chromiumEpochOffset)
                    return HistoryVisit(time: time, browser: profile.context, url: row["url"], title: row["title"])
                }
            }
            result += visits ?? []
        }
        return result.sorted { $0.time < $1.time }
    }

    func cloudTabs() -> [CloudTabDevice]? {
        guard let path = cloudTabsPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return nil
        }
        return query(path) { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT d.device_name AS name, t.url AS url FROM cloud_tabs t
                JOIN cloud_tab_devices d ON t.device_uuid = d.device_uuid
                """
            )
            var devices: [String: Set<String>] = [:]
            for row in rows {
                let name: String = row["name"]
                let url: String = row["url"]
                devices[name, default: []].insert(url)
            }
            return devices.map { CloudTabDevice(name: $0.key, urls: $0.value) }.sorted { $0.name < $1.name }
        }
    }

    static func chromiumTime(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + chromiumEpochOffset) * 1_000_000)
    }

    // MARK: Copies

    /// Runs `body` on a fresh enough copy of `path`; `nil` if it cannot be copied or read.
    private func query<T>(_ path: String, _ body: (Database) throws -> T) -> T? {
        guard let copy = copy(of: path), let queue = try? DatabaseQueue(path: copy.path) else {
            return nil
        }
        return try? queue.read(body)
    }

    private func copy(of path: String) -> URL? {
        let manager = FileManager.default
        let now = ProcessInfo.processInfo.systemUptime
        let source = [path, path + "-wal"].compactMap { (try? manager.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
        if let cached = copies[path], cached.source == source || now - cached.checked < Self.refreshInterval {
            return cached.copy
        }
        let target = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory).appending(
            path: "db.sqlite",
            directoryHint: .notDirectory
        )
        do {
            try SQLiteSnapshot.copy(path: path, to: target)
        } catch {
            return nil
        }
        if let old = copies[path] {
            try? manager.removeItem(at: old.copy.deletingLastPathComponent())
        }
        copies[path] = DatabaseCopy(copy: target, source: source, checked: now)
        return target
    }
}

// swiftlint:enable discouraged_optional_collection discouraged_optional_boolean

/// A copy of a history database and when it was made.
private struct DatabaseCopy {
    var copy: URL
    /// The live file's modification date at copy time.
    var source: Date?
    /// System uptime at copy time.
    var checked: TimeInterval
}
