// InstanceLock: one tracker agent per user (activity_tracking.md §5).

import Foundation

/// An exclusive `flock` on `agent.lock` in the agent folder, held for the
/// life of the process. A second agent (a stale copy, a build started by
/// hand) finds it taken and exits, so two agents never write the same logs.
nonisolated enum InstanceLock {
    /// Takes the lock at `url` without waiting; `false` when another
    /// process holds it or the lock file can't be opened, since an agent
    /// that can't tell whether it is alone must not write. The descriptor
    /// stays open on success.
    static func acquire(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            return false
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        return true
    }
}
