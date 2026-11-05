// SimulatedSyncEngine: CKSyncEngine's contract over InMemoryTransport, so
// SyncCoordinator runs in tests without CloudKit (data_and_sync.md §3.3).

import Foundation
import Synchronization
import TimeTrackingCore

/// Holds pending changes like `CKSyncEngine.State`, asks the coordinator for
/// batches, sends them, and reports what the server said.
final class SimulatedSyncEngine: SyncEngineDriving {
    private struct State {
        var pending: [SyncPendingChange] = []
        var zonePending = false
        var token: Data?
        var batches: [SyncBatch] = []
    }

    let transport: InMemoryTransport
    let coordinator: SyncCoordinator
    private let state = Mutex(State())

    init(transport: InMemoryTransport, coordinator: SyncCoordinator, token: Data?) {
        self.transport = transport
        self.coordinator = coordinator
        state.withLock { $0.token = token }
    }

    /// Every batch the coordinator built.
    var batches: [SyncBatch] {
        state.withLock { $0.batches }
    }

    var pending: [SyncPendingChange] {
        state.withLock { $0.pending }
    }

    func addPending(_ changes: [SyncPendingChange]) -> Int {
        state.withLock { state in
            let new = changes.filter { !state.pending.contains($0) }
            state.pending += new
            return new.count
        }
    }

    func removePending(_ changes: [SyncPendingChange]) {
        state.withLock { $0.pending.removeAll { changes.contains($0) } }
    }

    func addZone() {
        state.withLock { $0.zonePending = true }
    }

    func sendChanges() async throws {
        if state.withLock({ $0.zonePending }) {
            try await transport.createZone()
            state.withLock { $0.zonePending = false }
        }
        for _ in 0 ..< 20 {
            let pending = pending
            guard !pending.isEmpty, let batch = await coordinator.nextBatch(pending) else {
                return
            }
            state.withLock { $0.batches.append(batch) }
            removePending(batch.dropped)
            guard !batch.isEmpty else {
                continue
            }
            let results = try await transport.send(saving: batch.records, deleting: batch.deletions)
            var outcome = SyncSendOutcome()
            for result in results {
                switch result {
                case let .saved(record):
                    outcome.saved.append(record)
                    removePending([.save(record.ref)])
                case let .deleted(ref):
                    outcome.deletedNames.append(ref.name)
                    removePending([.delete(ref)])
                case .conflict, .unknownItem, .zoneNotFound, .retry:
                    outcome.failures.append(result)
                }
            }
            await coordinator.didSend(outcome)
        }
    }

    func fetchChanges() async throws {
        for _ in 0 ..< 20 {
            let result: SyncFetchResult
            do {
                result = try await transport.fetchChanges(since: state.withLock { $0.token })
            } catch SyncTransportError.zoneNotFound {
                state.withLock { $0.token = nil }
                await coordinator.zoneDeleted()
                return
            }
            await coordinator.didFetch(result.records, deletions: result.deletions)
            state.withLock { $0.token = result.token }
            await coordinator.stateChanged(result.token ?? Data())
            guard result.moreComing else {
                return
            }
        }
    }
}

/// Makes simulated engines on one in-memory server and remembers them.
final class SimulatedEngineFactory: SyncEngineFactory {
    let server: InMemorySyncServer
    let device: String
    private let made = Mutex<SimulatedSyncEngine?>(nil)

    init(server: InMemorySyncServer, device: String) {
        self.server = server
        self.device = device
    }

    var engine: SimulatedSyncEngine? {
        made.withLock { $0 }
    }

    func makeEngine(for coordinator: SyncCoordinator, state: Data?) -> any SyncEngineDriving {
        let engine = SimulatedSyncEngine(transport: server.transport(for: device), coordinator: coordinator, token: state)
        made.withLock { $0 = engine }
        return engine
    }
}

/// A factory that cannot make an engine (no entitlement, no container).
struct UnavailableEngineFactory: SyncEngineFactory {
    func makeEngine(for _: SyncCoordinator, state _: Data?) throws -> any SyncEngineDriving {
        throw SyncTransportError.other("This build is not entitled to iCloud.")
    }
}
