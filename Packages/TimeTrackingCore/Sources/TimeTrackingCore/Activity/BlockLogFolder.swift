// BlockLogFolder: the month files of a `blocks/` folder, one subfolder per
// Mac (activity_tracking.md §4.1).

public import Foundation

/// Lists the month files of a `blocks/` folder.
///
/// Each Mac writes only `blocks/<mac>/YYYY-MM.jsonl`, so no two Macs ever
/// rewrite the same file. Month files directly in `blocks/` come from
/// before that layout; readers still read them, and each Mac's agent moves
/// its own lines out of them when it starts.
public enum BlockLogFolder {
    /// The month files of `folder`: those directly in it first, then those
    /// of each subfolder, each group sorted by path.
    public static func monthFiles(in folder: URL) -> [URL] {
        var result = monthFiles(directlyIn: folder)
        for subfolder in macFolders(in: folder) {
            result += monthFiles(directlyIn: subfolder)
        }
        return result
    }

    /// The `YYYY-MM.jsonl` files directly in `folder`, sorted.
    public static func monthFiles(directlyIn folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isMonthFileName).sorted().map { name in
            folder.appending(path: name, directoryHint: .notDirectory)
        }
    }

    /// The visible subfolders of `folder`, one per Mac, sorted.
    public static func macFolders(in folder: URL) -> [URL] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
            let url = folder.appending(path: name, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
        }
    }

    /// The month (`YYYY-MM`) of a month file's URL.
    public static func month(of url: URL) -> String {
        String(url.lastPathComponent.prefix(7))
    }

    /// Whether `name` has the form `YYYY-MM.jsonl`.
    public static func isMonthFileName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        guard bytes.count == 13, name.hasSuffix(".jsonl"), bytes[4] == UInt8(ascii: "-") else {
            return false
        }
        return [0, 1, 2, 3, 5, 6].allSatisfy { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(bytes[$0]) }
    }
}
