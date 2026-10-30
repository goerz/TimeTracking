// StoreSynchronizer: drains the outbox through a transport and applies
// fetched changes (spec_data_and_sync.md §3.1). It drives the in-memory
// transport in tests and `-UITesting`; the CKSyncEngine coordinator
// (`SyncCoordinator`) uses the same store calls.

import Foundation

/// One device's sync loop over a `SyncTransport`.
public actor StoreSynchronizer {
    public let store: TimeStore
    public let transport: any SyncTransport
    public private(set) var status: SyncStatus = .idle
    private var liveStateHandler: (@Sendable (LiveStateSyncEvent) async -> Void)?
    static let tokenKey = "serverChangeToken"

    public init(store: TimeStore, transport: any SyncTransport) {
        self.store = store
        self.transport = transport
    }

    /// Receives the confirmed and applied `LiveState` records (the widget pushes).
    @preconcurrency
    public func onLiveState(_ handler: @escaping @Sendable (LiveStateSyncEvent) async -> Void) {
        liveStateHandler = handler
    }

    /// Sends pending changes, then fetches. Without network the status
    /// becomes `waitingForNetwork` and nothing throws.
    public func sync() async throws {
        do {
            try await send()
            try await fetch()
            setStatus(.idle)
        } catch SyncTransportError.networkUnavailable {
            setStatus(.waitingForNetwork)
        } catch SyncTransportError.noAccount {
            setStatus(.noAccount)
        }
    }

    /// Sends the outbox until it is empty.
    public func send() async throws {
        for _ in 0 ..< 20 {
            let pending = try await store.pendingChanges()
            guard !pending.isEmpty else {
                return
            }
            setStatus(.sending(pending.records.count + pending.deletions.count))
            let results = try await SendResults(transport.send(saving: pending.records, deleting: pending.deletions))
            for server in results.conflicts {
                try await store.resolveConflict(server: server)
            }
            let event = try await store.confirmSent(pending, saved: results.saved)
            if !results.unknown.isEmpty {
                try await store.requeueWithoutSystemFields(results.unknown)
            }
            if !results.retry.isEmpty {
                try await store.requeue(results.retry)
            }
            if results.zoneMissing {
                try await recreateZone()
            }
            if let event {
                await liveStateHandler?(event)
            }
        }
    }

    /// Fetches and applies changes until none are coming.
    public func fetch() async throws {
        setStatus(.fetching)
        for _ in 0 ..< 100 {
            let token = try await store.syncState(Self.tokenKey)
            let result: SyncFetchResult
            do {
                result = try await transport.fetchChanges(since: token)
            } catch SyncTransportError.zoneNotFound {
                try await recreateZone()
                try await send()
                continue
            }
            if !result.records.isEmpty || !result.deletions.isEmpty,
               let event = try await store.applyFetched(result.records, deletions: result.deletions)
            {
                await liveStateHandler?(event)
            }
            try await store.setSyncState(Self.tokenKey, result.token)
            guard result.moreComing else {
                return
            }
        }
    }

    private func recreateZone() async throws {
        try await transport.createZone()
        try await store.setSyncState(Self.tokenKey, nil)
        try await store.requeueAll()
    }

    private func setStatus(_ status: SyncStatus) {
        guard status != self.status else {
            return
        }
        self.status = status
        store.publish(status)
    }
}

/// The per-record results of one send, sorted by what follows from them.
struct SendResults {
    var saved: [SyncRecord] = []
    var conflicts: [SyncRecord] = []
    var unknown: [SyncRecordRef] = []
    var retry: [SyncRecordRef] = []
    var zoneMissing = false

    init(_ results: [SyncSaveResult]) {
        for result in results {
            switch result {
            case let .saved(record): saved.append(record)
            case .deleted: break
            case let .conflict(server): conflicts.append(server)
            case let .unknownItem(ref): unknown.append(ref)
            case let .retry(ref): retry.append(ref)
            case .zoneNotFound: self.zoneMissing = true
            }
        }
    }
}
