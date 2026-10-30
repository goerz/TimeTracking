// FileChangeLog: files modified under the watched roots, for the detail log
// (spec_activity_tracking.md §3.4, §7.2).

import Foundation
import TimeTrackingCore

/// The modified files of the last hours, exclusions applied on entry.
struct FileChangeLog {
    /// How long changes are kept for blocks still open.
    static let retention: TimeInterval = 4 * 3600

    private(set) var changes: [ActivityFileChange] = []

    /// Records a modified file unless it is under a `prune_names` folder or excluded.
    mutating func record(path: String, at time: Date, context: ResolveContext) {
        let components = path.split(separator: "/").map(String.init)
        let pruned = Set(context.settings.files.pruneNames)
        guard !components.contains(where: pruned.contains), !context.exclusions.excludesPath(path),
              !(components.last?.hasPrefix(".") ?? true)
        else {
            return
        }
        let tilde = context.tilde(path)
        if let last = changes.last, last.path == tilde, time.timeIntervalSince(last.time) < 5 {
            return
        }
        changes.append(ActivityFileChange(time: time, path: tilde))
        let cutoff = time.addingTimeInterval(-Self.retention)
        if let first = changes.first, first.time < cutoff {
            changes.removeAll { $0.time < cutoff }
        }
    }

    /// The changes in `[from, to]`, each path once at its last time.
    func changes(from: Date, to: Date) -> [ActivityFileChange] {
        var latest: [String: ActivityFileChange] = [:]
        for change in changes where change.time >= from && change.time <= to {
            latest[change.path] = change
        }
        return latest.values.sorted { ($0.time, $0.path) < ($1.time, $1.path) }
    }

    /// The most recently modified file below `folder` (a `~` path or an
    /// absolute one) since `since`.
    func recentFile(under folder: String, since: Date, context: ResolveContext) -> String? {
        let base = context.tilde(folder)
        guard !base.isEmpty else {
            return nil
        }
        return changes.last { $0.time >= since && $0.path.hasPrefix(base + "/") }?.path
    }

    /// Forgets everything (settings changes, `forget-day`).
    mutating func removeAll(from: Date, to: Date) {
        changes.removeAll { $0.time >= from && $0.time < to }
    }
}
