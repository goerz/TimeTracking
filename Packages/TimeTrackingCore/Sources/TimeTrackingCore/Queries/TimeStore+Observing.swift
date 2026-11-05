// Observation (data_and_sync.md §7.4).

import Foundation

extension TimeStore: StoreObserving {
    /// A new stream of changes; each access is one subscriber. Same-process
    /// changes arrive after commit; other processes' arrive as `.entries([])`,
    /// `.runningEntry`, and `.structure`.
    public nonisolated var changes: AsyncStream<StoreChange> {
        broadcaster.stream()
    }

    /// The latest adjustments, newest last (a ring of 100).
    public func recentAdjustments(limit: Int) -> [EntryAdjustment] {
        Array(adjustmentRing.suffix(limit))
    }

    /// Reports a sync status change to observers (used by the sync driver).
    public nonisolated func publish(_ status: SyncStatus) {
        broadcaster.yield(.sync(status))
    }
}
