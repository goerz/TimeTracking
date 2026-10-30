// Helpers for the Activity tests (spec_data_and_sync.md §6): temporary
// folders and fixed instants. Tests never touch the real containers.

import Foundation
import TimeTrackingCore

/// A fresh folder under the temporary directory.
struct TemporaryFolder {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackingCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Activity folders `shared/` and `local/` inside this folder.
    var folders: ActivityFolders {
        ActivityFolders(
            shared: url.appending(path: "shared", directoryHint: .isDirectory),
            local: url.appending(path: "local", directoryHint: .isDirectory)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Runs `body` with a temporary folder that is removed afterwards.
func withTemporaryFolder<Value>(_ body: (TemporaryFolder) async throws -> Value) async throws -> Value {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    return try await body(folder)
}

enum ActivityFixture {
    static let newYork = TimeZone(identifier: "America/New_York") ?? .gmt

    /// An instant from an RFC 3339 string.
    static func instant(_ text: String) throws -> Date {
        try Date(text, strategy: .iso8601)
    }

    /// Writes `text` to `url`, creating folders, and sets the modification
    /// date so change detection never depends on timestamp resolution.
    static func write(_ text: String, to url: URL, modified: Date) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    /// Appends `text` to the existing file `url`.
    static func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    /// A block of `device` from `start` to `end` (RFC 3339) with one item per entry of `items`.
    static func block(
        start: String,
        end: String,
        items: [ActivityItem],
        device: String = "macbook",
        utcOffset: Int = -4 * 3600,
        groupKey: String? = nil
    ) throws -> ActivityBlock {
        let total = items.reduce(0) { $0 + $1.seconds }
        return try ActivityBlock(
            start: instant(start),
            end: instant(end),
            activeSeconds: total,
            device: device,
            groupKey: groupKey ?? items.first?.context ?? "",
            groupShare: 1,
            items: items,
            utcOffset: utcOffset
        )
    }
}
