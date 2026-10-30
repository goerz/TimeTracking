// StoreSynchronizer: drains the outbox through a transport and applies
// fetched changes (spec_data_and_sync.md §3.1). It drives the in-memory
// transport in tests and `-UITesting`; the CKSyncEngine coordinator (step 5)
// uses the same store calls.

import Foundation

/// One device's sync loop over a `SyncTransport`.
public actor StoreSynchronizer {
    public let store: TimeStore
    public let transport: any SyncTransport
    public private(set) var status: SyncStatus = .idle
    static let tokenKey = "serverChangeToken"

    public init(store: TimeStore, transport: any SyncTransport) {
        self.store = store
        self.transport = transport
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
            let results = try await transport.send(saving: pending.records, deleting: pending.deletions)
            var saved: [SyncRecord] = []
            var unknown: [SyncRecordRef] = []
            var zoneMissing = false
            for result in results {
                switch result {
                case let .saved(record):
                    saved.append(record)
                case .deleted:
                    break
                case let .conflict(server):
                    try await store.resolveConflict(server: server)
                case let .unknownItem(ref):
                    unknown.append(ref)
                case .zoneNotFound:
                    zoneMissing = true
                }
            }
            try await store.confirmSent(pending, saved: saved)
            if !unknown.isEmpty {
                try await store.requeueWithoutSystemFields(unknown)
            }
            if zoneMissing {
                try await recreateZone()
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
                continue
            }
            if !result.records.isEmpty || !result.deletions.isEmpty {
                try await store.applyFetched(result.records, deletions: result.deletions)
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
