// TemporaryFolder: a fresh folder for one test, removed with its contents
// when the last reference to it goes away (architecture.md §3).

import Foundation

/// A new, empty `<prefix>-<UUID>` folder in the temporary directory.
final class TemporaryFolder: Sendable {
    let url: URL

    init(_ prefix: String) throws {
        self.url = FileManager.default.temporaryDirectory.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
