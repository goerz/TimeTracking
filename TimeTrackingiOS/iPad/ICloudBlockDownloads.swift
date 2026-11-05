// ICloudBlockDownloads: asks iCloud Drive for the block log's month files
// on the iPad, which `FileActivityStore` reads only once downloaded
// (data_and_sync.md §6; activity.md §5;
// activity_tracking.md §4.1).

import Foundation
import TimeTrackingCore

/// Downloads of `Activity/blocks/` in the ubiquity container.
nonisolated enum ICloudBlockDownloads {
    /// Starts the download of every month file of `folder` and its per-Mac
    /// subfolders not yet local and answers whether `month` (`YYYY-MM`) is
    /// local and current in at least one of them and pending in none.
    static func request(folder: URL, month: String) -> Bool {
        var found = false
        var pending = false
        for subfolder in [folder] + BlockLogFolder.macFolders(in: folder) {
            for url in monthFiles(in: subfolder) {
                let current = isCurrent(url)
                if !current {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
                if url.lastPathComponent == "\(month).jsonl" {
                    found = found || current
                    pending = pending || !current
                }
            }
        }
        return found && !pending
    }

    /// The month files of `folder`, downloaded or not: a file not yet
    /// downloaded may show as `.<name>.icloud`.
    private static func monthFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            let real = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
            return real.hasSuffix(".jsonl") ? folder.appending(path: real, directoryHint: .notDirectory) : nil
        }
    }

    private static func isCurrent(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values?.ubiquitousItemDownloadingStatus else {
            return true
        }
        return status == .current
    }
}
