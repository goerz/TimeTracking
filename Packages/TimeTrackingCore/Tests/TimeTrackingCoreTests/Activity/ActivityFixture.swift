// Helpers for the Activity tests (data_and_sync.md §6, activity_tracking.md
// §2.2): activity folders in a temporary folder, fixed instants, file
// writes, and Items and blocks with synthetic values.

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

    // MARK: Items and blocks

    /// Neovim in a terminal, in the workspace `~/Code/<workspace>`.
    static func terminal(_ workspace: String = "MyApp", session: String = "refactor-parser") -> ActivityItem {
        ActivityItem(
            app: "WezTerm",
            appID: "com.github.wez.wezterm",
            window: "Research",
            session: session,
            location: "~/Code/\(workspace)",
            command: "nvim",
            workspace: "~/Code/\(workspace)"
        )
    }

    /// A web page in Safari.
    static func page(_ url: String, workspace: String) -> ActivityItem {
        ActivityItem(app: "Safari", appID: "com.apple.Safari", window: "Page", location: url, workspace: workspace)
    }

    /// A plain app, its own workspace.
    static func app(_ name: String, appID: String = "") -> ActivityItem {
        ActivityItem(app: name, appID: appID.isEmpty ? "com.example.\(name.lowercased())" : appID)
    }

    /// A busy coding agent in the background.
    static let agent = ActivityItem(
        app: "Claude Code",
        appID: "claude",
        session: "refactor-parser",
        location: "~/Code/MyApp",
        command: "claude --resume",
        workspace: "~/Code/MyApp"
    )

    /// A closed block in New York time (`-04:00` in March 2024) from `start`
    /// to `end` (`HH:MM` on `day`) with `items` on `device`.
    static func block(
        _ day: String = "2024-03-14",
        _ start: String,
        _ end: String,
        _ items: [(ActivityItem, Int)],
        device: String = "MacBook",
        background: [(ActivityItem, Int)] = [],
        reason: ActivityEndReason? = .idle,
        reconstructed: Int = 0
    ) throws -> ActivityBlock {
        try ActivityBlock(
            start: instant("\(day)T\(start):00-04:00"),
            end: instant("\(day)T\(end):00-04:00"),
            utcOffset: -4 * 3600,
            endReason: reason,
            reconstructedSeconds: reconstructed,
            foreground: items.map { ActivityBlockItem(device: device, seconds: $0.1, item: $0.0) },
            background: background.map { ActivityBlockItem(device: device, seconds: $0.1, item: $0.0) }
        )
    }
}
