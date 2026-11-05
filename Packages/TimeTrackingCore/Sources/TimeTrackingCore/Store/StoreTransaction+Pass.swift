// The invariant pass (spec_data_and_sync.md §3.3).

import Foundation
import GRDB

extension StoreTransaction {
    /// Reduces several running entries to one: ordered by start, then id,
    /// the last keeps running and each other one ends at the next start, or
    /// is removed when that start equals its own. A pure function of the
    /// store; a second run changes nothing.
    func runInvariantPass() throws {
        let running = try runningEntries()
        for (entry, next) in zip(running, running.dropFirst()) {
            if entry.start >= next.start {
                var removed = entry
                removed.deletedAt = now
                try write(removed)
                record(.removedByLaterStart, before: entry, after: removed, causingEntry: next.id, causingDevice: next.deviceID)
            } else {
                var stopped = entry
                stopped.end = next.start
                try write(stopped)
                record(.stoppedByLaterStart, before: entry, after: stopped, causingEntry: next.id, causingDevice: next.deviceID)
            }
        }
    }
}
