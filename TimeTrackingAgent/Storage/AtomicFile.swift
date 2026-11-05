// AtomicFile: replacing a file by writing a temporary file and renaming it
// (activity_tracking.md §4.4, §7.3).

import Foundation

/// Writes whole files so that readers see either the old or the new content.
nonisolated enum AtomicFile {
    /// Writes `data` to a temporary file next to `url` and renames it over `url`.
    static func write(_ data: Data, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            try data.write(to: temporary)
            guard rename(temporary.path, url.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
