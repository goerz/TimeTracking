// SQLiteSnapshot: a copy of a live SQLite database with its WAL
// (activity_tracking.md §3.2, §3.3).

import Foundation

/// Copies another app's SQLite database so it can be read without locking
/// or disturbing the live one.
nonisolated enum SQLiteSnapshot {
    /// How often a copy is tried before the last one is kept as it is.
    static let attempts = 3

    /// Copies the database at `path`, with its `-wal` and `-shm` files when
    /// present, to `target`, creating the folder that holds it. The owner
    /// may checkpoint or write between the files: when any source file's
    /// size or modification date changed during the copy, the copy is
    /// thrown away and made again, up to `attempts` times.
    static func copy(
        path: String,
        to target: URL,
        copyFile: (String, String) throws -> Void = { try FileManager.default.copyItem(atPath: $0, toPath: $1) }
    ) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        for attempt in 1 ... attempts {
            let before = stamps(path)
            remove(target)
            try copyFile(path, target.path)
            for suffix in ["-wal", "-shm"] where manager.fileExists(atPath: path + suffix) {
                try copyFile(path + suffix, target.path + suffix)
            }
            if stamps(path) == before || attempt == attempts {
                return
            }
        }
    }

    /// The size and modification date of the database and its WAL.
    private static func stamps(_ path: String) -> [String] {
        ["", "-wal"].map { suffix in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path + suffix) else {
                return "-"
            }
            let size = attributes[.size] as? Int ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return "\(size) \(modified)"
        }
    }

    private static func remove(_ target: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: target.path + suffix)
        }
    }
}
