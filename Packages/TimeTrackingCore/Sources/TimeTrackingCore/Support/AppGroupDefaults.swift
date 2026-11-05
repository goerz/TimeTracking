// AppGroupDefaults: the App Group's `UserDefaults` suite, held by the
// device settings and the shared-state wrappers (architecture.md §1.5,
// data_and_sync.md §1.6).

import Foundation

/// A `UserDefaults` suite that can cross concurrency domains.
struct AppGroupDefaults: @unchecked Sendable {
    /// UserDefaults is thread-safe; the macOS 27 SDK does not mark it `Sendable`.
    let defaults: UserDefaults
    /// The lock file for read-modify-write sequences across the processes
    /// sharing the suite; `nil` for a suite without a group container.
    let lockURL: URL?

    init(defaults: UserDefaults, lockURL: URL? = nil) {
        self.defaults = defaults
        self.lockURL = lockURL
    }

    /// The App Group suite of `identity`, or the standard defaults.
    init(identity: AppIdentity?) {
        self.defaults = identity.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
        self.lockURL = identity.flatMap { identity in
            identity.groupContainerURL.map { group in
                identity.supportDirectory(in: group).appending(path: "defaults.lock", directoryHint: .notDirectory)
            }
        }
    }

    /// Runs `body` while holding an exclusive `flock` on the lock file, so a
    /// read-modify-write of values another process also changes (the app
    /// and its extensions) never interleaves with theirs. Values are read
    /// fresh inside. Without a lock file `body` runs as is.
    func withExclusiveAccess<Value>(_ body: () throws -> Value) rethrows -> Value {
        guard let lockURL else {
            return try body()
        }
        try? FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            return try body()
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            return try body()
        }
        defer { flock(descriptor, LOCK_UN) }
        // Picks up what another process wrote before it released the lock.
        defaults.synchronize()
        let value = try body()
        defaults.synchronize()
        return value
    }
}
