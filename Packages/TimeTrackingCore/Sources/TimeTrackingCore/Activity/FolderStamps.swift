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
            for name in Self.monthFileNames(in: folder) {
                let url = folder.appending(path: name, directoryHint: .notDirectory)
                found[url.path] = FileStamp(url: url)
            }
        }
        self.months = found
    }

    /// The `YYYY-MM.jsonl` files of `folder`, sorted.
    static func monthFileNames(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isMonthFileName).sorted()
    }

    private static func isMonthFileName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard bytes.count == 13, name.hasSuffix(".jsonl"), bytes[4] == UInt8(ascii: "-") else {
            return false
        }
        return [0, 1, 2, 3, 5, 6].allSatisfy { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(bytes[$0]) }
    }
}
