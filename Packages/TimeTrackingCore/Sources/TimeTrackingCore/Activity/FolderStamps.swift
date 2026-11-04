// FolderStamps: modification stamps of the activity files, for change
// detection (spec_data_and_sync.md §6).

import Foundation

/// The modification date and size of a file.
struct FileStamp: Hashable {
    var modified: Date?
    var size: Int

    /// The stamp of `url`, or `nil` when there is no file.
    init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        self.modified = attributes[.modificationDate] as? Date
        self.size = attributes[.size] as? Int ?? 0
    }
}

/// The stamps of `current.json`, `settings.toml`, and every month file.
struct FolderStamps: Hashable {
    var state: FileStamp?
    var settings: FileStamp?
    /// Month-file stamps by path.
    var months: [String: FileStamp]

    init(folders: ActivityFolders) {
        self.state = FileStamp(url: folders.currentStateURL)
        self.settings = FileStamp(url: folders.settingsURL)
        var found: [String: FileStamp] = [:]
        for folder in folders.blockFolders {
            for url in BlockLogFolder.monthFiles(in: folder) {
                found[url.path] = FileStamp(url: url)
            }
        }
        self.months = found
    }
}
