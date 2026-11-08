// SharedFolderChoice: whether the agent can write the iCloud Drive container
// (activity_tracking.md §4.1).

import Foundation
import TimeTrackingCore

/// Where the agent writes `blocks/` and reads `settings.toml`, and what the
/// `shared_folder` source reports.
nonisolated struct SharedFolderChoice: Hashable {
    /// The folder holding `blocks/` and `settings.toml`.
    var activityFolder: URL
    var status: TrackerSourceStatus
    var reason: String
    /// The shared `blocks/`, which holds `owner` also while the agent
    /// writes the local folder (§4.1).
    var ownerLog: BlockLogFolder

    /// `blocks/`, the date files; coordinated writes when it is iCloud Drive's.
    var log: BlockLogFolder {
        BlockLogFolder(url: activityFolder.appending(path: "blocks", directoryHint: .isDirectory), isUbiquitous: status == .active)
    }

    var settingsURL: URL {
        activityFolder.appending(path: "settings.toml", directoryHint: .notDirectory)
    }

    /// Writes and removes a probe file in the shared folder; without iCloud
    /// Drive or write access, the local folder takes its place.
    static func choose(folders: ActivityFolders, canWrite: (URL) -> Bool = Self.canWrite) -> Self {
        let ownerLog = BlockLogFolder(url: folders.sharedBlocks, isUbiquitous: !folders.isFallback)
        if folders.isFallback {
            // `off`, not `fallback`: `fallback` means the Mac app's copy (§4.1).
            return Self(
                activityFolder: folders.local,
                status: .off,
                reason: "iCloud Drive is off; activity stays on this Mac",
                ownerLog: ownerLog
            )
        }
        if canWrite(folders.shared) {
            return Self(activityFolder: folders.shared, status: .active, reason: "", ownerLog: ownerLog)
        }
        return Self(activityFolder: folders.local, status: .fallback, reason: ActivityFolderMirror.fallbackReason, ownerLog: ownerLog)
    }

    /// Whether the agent may write `ownerLog`'s owner file.
    var canClaim: Bool {
        status != .fallback
    }

    /// Whether a file can be created in `folder`.
    static func canWrite(_ folder: URL) -> Bool {
        let probe = folder.appending(path: ".write-check-\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }
}
