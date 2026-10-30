// SharedFolderChoice: whether the agent can write the iCloud Drive container
// (spec_activity_tracking.md §4.1, phase 1).

import Foundation
import TimeTrackingCore

/// Where the agent writes `blocks/` and reads `settings.toml`, and what the
/// `shared_folder` source reports.
nonisolated struct SharedFolderChoice: Hashable {
    /// The folder holding `blocks/` and `settings.toml`.
    var activityFolder: URL
    var status: TrackerSourceStatus
    var reason: String

    var blocksFolder: URL {
        activityFolder.appending(path: "blocks", directoryHint: .isDirectory)
    }

    var settingsURL: URL {
        activityFolder.appending(path: "settings.toml", directoryHint: .notDirectory)
    }

    /// Writes and removes a probe file in the shared folder; without iCloud
    /// Drive or write access, the local folder takes its place.
    static func choose(folders: ActivityFolders, canWrite: (URL) -> Bool = Self.canWrite) -> Self {
        if folders.isFallback {
            // `off`, not `fallback`: `fallback` means the Mac app's copy (§4.1).
            return Self(activityFolder: folders.local, status: .off, reason: "iCloud Drive is off; activity stays on this Mac")
        }
        if canWrite(folders.shared) {
            return Self(activityFolder: folders.shared, status: .active, reason: "")
        }
        return Self(activityFolder: folders.local, status: .fallback, reason: ActivityFolderMirror.fallbackReason)
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
