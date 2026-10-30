// TemporaryFolder: fresh folders for tests (spec_architecture.md §3.3).

import Foundation

/// Creates empty folders in the temporary directory; the caller removes them.
enum TemporaryFolder {
    /// A new folder `<prefix>-<UUID>`.
    static func make(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
