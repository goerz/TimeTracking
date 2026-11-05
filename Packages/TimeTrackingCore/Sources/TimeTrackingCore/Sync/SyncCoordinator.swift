// SyncCoordinator: the delegate side of the sync engine in the app process
// (data_and_sync.md §3.1). It drains the outbox into the engine's
// pending changes, builds the batches from the store's rows, and applies
// what the engine reports, through the store calls StoreSynchronizer uses.

import Foundation
import os

/// Runs sync for one store in the app process. Without a usable engine
/// (no iCloud entitlement, no container) it logs the error, reports it as
/// the status, and the store keeps working locally.
public actor SyncCoordinator {
    /// The `sync_state` key of the engine's serialized state.
    public static let engineStateKey = "syncEngineState"
    /// Records per batch (CloudKit accepts 400 per request).
    public static let batchLimit = 300

    public let store: TimeStore
    private let factory: any SyncEngineFactory
    var engine: (any SyncEngineDriving)?
    public internal(set) var status: SyncStatus = .idle
    private var changeTask: Task<Void, Never>?
    /// Pending changes added since the last explicit send.
    private var unsent = 0
    /// Per record name, the ref and outbox sequence its last batch was built at.
    var inFlight: [String: (ref: SyncRecordRef, sequence: Int64)] = [:]
    var liveStateHandler: (@Sendable (LiveStateSyncEvent) async -> Void)?
    var appliedHandler: (@Sendable () async -> Void)?
    var confirmSwitch: @Sendable () async -> Bool = { true }
    static let logger = Logging.logger(category: "Sync")

    public init(store: TimeStore, factory: any SyncEngineFactory) {
        self.store = store
        self.factory = factory
    }

    /// Whether an engine runs.
    public var isRunning: Bool {
        engine != nil
    }

    /// Receives confirmed and applied `LiveState` records (`WidgetPushSender`).
    @preconcurrency
    public func onLiveState(_ handler: @escaping @Sendable (LiveStateSyncEvent) async -> Void) {
        liveStateHandler = handler
    }

    /// Runs after every applied fetch (iOS: reload the widget timelines).
    @preconcurrency
    public func onApplied(_ handler: @escaping @Sendable () async -> Void) {
        appliedHandler = handler
    }

    /// Asks the user before a switch to another iCloud account empties the store.
    @preconcurrency
    public func onAccountSwitch(confirm: @escaping @Sendable () async -> Bool) {
        confirmSwitch = confirm
    }

    // MARK: Lifecycle

    /// Creates the engine from the saved state, queues the zone on a first
    /// run, drains the outbox, and follows the store's changes. A failure
    /// leaves the coordinator stopped with status `error`. Tests pass
    /// `observingStore: false` and call `storeChanged(_:)` themselves.
    public func start(observingStore: Bool = true) async {
        guard engine == nil else {
            return
        }
        do {
            let state = try await store.syncState(Self.engineStateKey)
            let created = try await factory.makeEngine(for: self, state: state)
            engine = created
            if state == nil {
                await created.addZone()
            }
        } catch {
            Self.logger.error("Sync is unavailable, working locally: \(String(describing: error), privacy: .public)")
            switch error as? SyncTransportError {
            case .noAccount:
                setStatus(.noAccount)
            case .notEntitled:
                setStatus(.error(SyncTransportError.notEntitled.localizedDescription))
            default:
                setStatus(.error(Self.unavailableText))
            }
            return
        }
        if observingStore {
            observeStore()
        }
        _ = await drain()
    }

    public func stop() {
        changeTask?.cancel()
        changeTask = nil
        engine = nil
    }

    private func observeStore() {
        let stream = store.changes
        changeTask = Task { [weak self] in
            for await change in stream {
                await self?.storeChanged(change)
            }
        }
    }

    /// A store change: drain the outbox; a running-entry or `LiveState`
    /// change is sent at once.
    public func storeChanged(_ change: StoreChange) async {
        switch change {
        case .sync, .adjusted, .runningChangedElsewhere:
            return
        case .entries, .structure, .settings, .health:
            unsent += await drain()
        case .runningEntry, .liveState:
            unsent += await drain()
            if unsent > 0 {
                unsent = 0
                await sendNow()
            }
        }
    }

    /// Adds every queued outbox record to the engine's pending changes;
    /// returns how many were new.
    @discardableResult
    public func drain() async -> Int {
        guard let engine else {
            return 0
        }
        do {
            let pending = try await store.pendingChanges(limit: 100_000)
            let changes = pending.records.map { SyncPendingChange.save($0.ref) } + pending.deletions.map { .delete($0) }
            return await engine.addPending(changes)
        } catch {
            Self.logger.error("Draining the outbox failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// Sends the pending changes now.
    public func sendNow() async {
        guard let engine else {
            return
        }
        do {
            try await engine.sendChanges()
        } catch {
            report(error)
        }
    }

    /// Fetches the server's changes now (the iOS widget buttons, refresh tasks).
    public func fetchNow() async {
        guard let engine else {
            return
        }
        do {
            try await engine.fetchChanges()
        } catch {
            report(error)
        }
    }

    /// The iCloud line after sync could not start.
    static let unavailableText = "iCloud is not available. Entries stay on this device."

    func report(_ error: any Error) {
        let transport = (error as? SyncTransportError) ?? .other(String(describing: error))
        switch transport {
        case .networkUnavailable:
            setStatus(.waitingForNetwork)
        case .noAccount:
            setStatus(.noAccount)
        case .zoneNotFound, .notEntitled, .other:
            Self.logger.error("Sync failed: \(String(describing: error), privacy: .public)")
            setStatus(.error(transport.localizedDescription))
        }
    }

    func setStatus(_ new: SyncStatus) {
        guard new != status else {
            return
        }
        status = new
        store.publish(new)
    }
}
