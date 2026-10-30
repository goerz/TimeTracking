// ICloudBlockDownloads: asks iCloud Drive for the block log's month files
// on the iPad, which `FileActivityStore` reads only once downloaded
// (spec_data_and_sync.md §6; spec_planner_activity.md §5).

import Foundation

/// Downloads of `Activity/blocks/` in the ubiquity container.
nonisolated enum ICloudBlockDownloads {
    /// Starts the download of every month file of `folder` not yet local
    /// and answers whether `month` (`YYYY-MM`) is local and current.
    static func request(folder: URL, month: String) -> Bool {
        let files = FileManager.default
        let names = (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            // A file not yet downloaded may show as `.<name>.icloud`.
            let real = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
            guard real.hasSuffix(".jsonl") else {
                continue
            }
            let url = folder.appending(path: real, directoryHint: .notDirectory)
            if !isCurrent(url) {
                try? files.startDownloadingUbiquitousItem(at: url)
            }
        }
        return isCurrent(folder.appending(path: "\(month).jsonl", directoryHint: .notDirectory))
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
