// The invariant pass (spec_data_and_sync.md §3.3).

import Foundation
import GRDB

extension StoreTransaction {
    /// Runs the pass: split every live entry of this transaction and every
    /// running entry that crosses a midnight, then reduce several running
    /// entries to one. A pure function of the store and `now`; a second run
    /// changes nothing. Only rows written by the library can cross a
    /// midnight, so the entries changed in this transaction and the running
    /// ones are the only candidates.
    func runInvariantPass() throws {
        try splitRunningEntries()
        for id in changedEntryIDs.sorted() {
            if let entry = try entry(id), entry.end != nil {
                try splitAcrossMidnights(entry)
            }
        }
        try reduceRunningEntries()
    }

    /// Splits running entries whose interval up to `now` contains a midnight.
    func splitRunningEntries() throws {
        for entry in try runningEntries() {
            try splitAcrossMidnights(entry)
        }
    }

    /// The earliest start of the live entries of the chain `root`.
    func chainStart(root: EntryID) throws -> Date? {
        try StoreQueries.chainStart(root: root, in: database)
    }

    /// Several running entries: ordered by chain start, then root id, the
    /// last keeps running; each other chain loses its entries starting at or
    /// after the next chain start T and the one running or ending after T
    /// ends at T.
    private func reduceRunningEntries() throws {
        let running = try runningEntries()
        guard running.count > 1 else {
            return
        }
        var chains: [RunningChain] = []
        for entry in running {
            let start = try chainStart(root: entry.rootID) ?? entry.start
            if let index = chains.firstIndex(where: { $0.root == entry.rootID }) {
                // Two running pieces of one chain: the later one continues.
                let (earlier, later) = chains[index].entry.start <= entry.start
                    ? (chains[index].entry, entry) : (entry, chains[index].entry)
                try stop(earlier, at: later.start, because: later)
                chains[index].entry = later
            } else {
                chains.append(RunningChain(root: entry.rootID, start: start, entry: entry))
            }
        }
        chains.sort { ($0.start, $0.root) < ($1.start, $1.root) }
        for (current, next) in zip(chains, chains.dropFirst()) {
            for member in try chainEntries(root: current.root) {
                if member.start >= next.start {
                    var removed = member
                    removed.deletedAt = now
                    try write(removed)
                    record(
                        .removedByLaterStart,
                        before: member,
                        after: removed,
                        causingEntry: next.entry.id,
                        causingDevice: next.entry.deviceID
                    )
                } else if member.end.map({ $0 > next.start }) ?? true {
                    try stop(member, at: next.start, because: next.entry)
                }
            }
        }
    }

    private func stop(_ entry: TimeEntry, at end: Date, because cause: TimeEntry) throws {
        var stopped = entry
        stopped.end = max(end, entry.start)
        try write(stopped)
        record(.stoppedByLaterStart, before: entry, after: stopped, causingEntry: cause.id, causingDevice: cause.deviceID)
    }
}

/// A chain with a running entry, for the reduction.
private struct RunningChain {
    var root: EntryID
    var start: Date
    var entry: TimeEntry
}
