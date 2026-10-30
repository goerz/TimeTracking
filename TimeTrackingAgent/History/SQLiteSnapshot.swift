// SQLiteSnapshot: a copy of a live SQLite database with its WAL
// (spec_activity_tracking.md §3.2, §3.3).

import Foundation

/// Copies another app's SQLite database so it can be read without locking
/// or disturbing the live one.
nonisolated enum SQLiteSnapshot {
    /// Copies the database at `path`, with its `-wal` and `-shm` files when
    /// present, to `target`, creating the folder that holds it.
    static func copy(path: String, to target: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(atPath: path, toPath: target.path)
        for suffix in ["-wal", "-shm"] where manager.fileExists(atPath: path + suffix) {
            try manager.copyItem(atPath: path + suffix, toPath: target.path + suffix)
        }
    }
}
