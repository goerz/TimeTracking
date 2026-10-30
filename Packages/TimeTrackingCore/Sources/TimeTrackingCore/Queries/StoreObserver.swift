// StoreObserver: store changes as observable state for views (spec_data_and_sync.md §7.4).

import Foundation
import Observation

/// Turns a store's change stream into observable counters and values.
///
/// Views read a revision in their body or `task(id:)` and re-query the
/// store when it changes; `runningEntry`, `syncStatus`, and
/// `pendingAdjustments` are kept directly. Changes from other processes
/// bump every revision.
@preconcurrency
@MainActor
@Observable
public final class StoreObserver {
    /// Bumped by every change.
    public private(set) var revision = 0
    public private(set) var entriesRevision = 0
    public private(set) var structureRevision = 0
    public private(set) var settingsRevision = 0
    public private(set) var runningEntry: TimeEntry?
    public private(set) var syncStatus: SyncStatus = .idle
    /// `.adjusted` events not yet shown; the view clears them with `takeAdjustments()`.
    public private(set) var pendingAdjustments: [EntryAdjustment] = []

    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    /// Starts following `store` (stops following a previous one) and loads
    /// the running entry.
    public func observe(_ store: any StoreObserving & TimeStoreReading) {
        task?.cancel()
        let stream = store.changes
        task = Task { [weak self] in
            self?.runningEntry = try? await store.runningEntry()
            await self?.consume(stream)
        }
    }

    /// Applies every change of `stream` until it ends.
    public func consume(_ stream: AsyncStream<StoreChange>) async {
        for await change in stream {
            apply(change)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Applies one change; public for previews and tests of views.
    public func apply(_ change: StoreChange) {
        revision += 1
        switch change {
        case .entries:
            entriesRevision += 1
        case let .runningEntry(entry):
            runningEntry = entry
        case .structure:
            structureRevision += 1
        case .settings:
            settingsRevision += 1
        case .liveState:
            break
        case let .sync(status):
            syncStatus = status
        case let .adjusted(adjustments):
            pendingAdjustments += adjustments
        }
    }

    /// Returns and clears the pending adjustments.
    public func takeAdjustments() -> [EntryAdjustment] {
        defer { pendingAdjustments = [] }
        return pendingAdjustments
    }
}
