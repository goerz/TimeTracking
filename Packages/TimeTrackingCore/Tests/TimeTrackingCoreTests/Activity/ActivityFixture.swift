// Helpers for the Activity tests (spec_data_and_sync.md §6): activity
// folders in a temporary folder, fixed instants, and file writes.

import Foundation
import TimeTrackingCore

extension TemporaryFolder {
    /// Activity folders `shared/` and `local/` inside this folder.
    var folders: ActivityFolders {
        ActivityFolders(
            shared: url.appending(path: "shared", directoryHint: .isDirectory),
            local: url.appending(path: "local", directoryHint: .isDirectory)
        )
    }
}

enum ActivityFixture {
    static let newYork = TestTime.newYork

    /// An instant from an RFC 3339 string.
    static func instant(_ text: String) throws -> Date {
        try TestTime.instant(text)
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
