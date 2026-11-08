// ICloudBlockDownloads: asks iCloud Drive for today's date file on the iPad,
// which `FileActivityStore` reads only once downloaded (data_and_sync.md §6;
// activity.md §5; activity_tracking.md §4.1).

import Foundation
import TimeTrackingCore

/// Today's file of `Activity/blocks/` in the ubiquity container. Other
/// dates download when a section reads them: a read of a file not yet here
/// asks for it.
nonisolated enum ICloudBlockDownloads {
    /// Starts the download of the file of `day` if it isn't local and
    /// current, and answers whether it is.
    static func request(folder: URL, day: TrackingDay) -> Bool {
        let file = BlockLogFolder(url: folder, isUbiquitous: true).fileURL(for: day)
        // `isPendingDownload` asks for the download of a file that isn't here.
        return !ActivityFile.isPendingDownload(file) && FileManager.default.fileExists(atPath: file.path)
    }
}
