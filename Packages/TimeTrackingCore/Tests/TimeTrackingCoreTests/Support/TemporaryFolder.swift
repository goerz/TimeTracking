// Temporary folders for the tests (spec_architecture.md §3.3). Tests never
// touch the real containers.

import Foundation

/// A fresh folder under the temporary directory.
struct TemporaryFolder {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackingCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Runs `body` with a temporary folder that is removed afterwards.
func withTemporaryFolder<Value>(_ body: (TemporaryFolder) async throws -> Value) async throws -> Value {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    return try await body(folder)
}
