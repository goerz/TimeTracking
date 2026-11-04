// ICloudFile: whether an iCloud Drive file is on this Mac in full
// (spec_activity_tracking.md §4.1).

import Foundation

/// iCloud Drive may keep only a placeholder for a file (evicted to save
/// space, or not yet downloaded from another Mac): `.<name>.icloud` next to
/// it, or a file whose download status is not current. Reading such a file
/// sees nothing, and writing it would replace the real content, so the
/// agent asks for the download and leaves the file alone until it is here.
nonisolated enum ICloudFile {
    /// Whether `url` stands for a file not on this Mac in full; asks for
    /// its download when so.
    static func isPending(_ url: URL) -> Bool {
        let manager = FileManager.default
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud", directoryHint: .notDirectory)
        var pending = manager.fileExists(atPath: placeholder.path)
        if !pending, manager.fileExists(atPath: url.path),
           let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        {
            pending = status != .current
        }
        if pending {
            try? manager.startDownloadingUbiquitousItem(at: url)
        }
        return pending
    }

    /// The error for a write left for later because `url` is pending.
    static func pendingError(_ url: URL) -> ActivityFileError {
        ActivityFileError.notDownloaded(url.lastPathComponent)
    }
}

/// A log file the agent cannot write yet.
nonisolated enum ActivityFileError: LocalizedError, Equatable {
    case notDownloaded(String)

    var errorDescription: String? {
        switch self {
        case let .notDownloaded(name): "\(name) is not downloaded from iCloud Drive yet"
        }
    }
}
