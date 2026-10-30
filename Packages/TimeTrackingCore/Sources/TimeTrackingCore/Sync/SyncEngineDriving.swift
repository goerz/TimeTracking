// The engine side of SyncCoordinator: CKSyncEngine in the apps, a simulation
// in tests (spec_data_and_sync.md §3.1).

public import Foundation

/// A record change waiting in the engine.
public enum SyncPendingChange: Hashable, Sendable {
    case save(SyncRecordRef)
    case delete(SyncRecordRef)

    public var ref: SyncRecordRef {
        switch self {
        case let .save(ref), let .delete(ref): ref
        }
    }
}

/// One batch for the engine to send.
public struct SyncBatch: Sendable, Hashable {
    public var records: [SyncRecord]
    public var deletions: [SyncRecordRef]
    /// All or nothing within the zone: set when the batch saves `LiveState`.
    public var atomic: Bool
    /// Pending saves whose rows no longer exist; the engine forgets them
    /// (the outbox holds their deletion).
    public var dropped: [SyncPendingChange]

    public var isEmpty: Bool {
        records.isEmpty && deletions.isEmpty
    }
}

/// What the server answered to one batch.
public struct SyncSendOutcome: Sendable, Hashable {
    public var saved: [SyncRecord]
    /// Names of the deleted records (the engine reports ids without types).
    public var deletedNames: [String]
    /// Per-record failures: `.conflict`, `.unknownItem`, `.zoneNotFound`, or `.retry`.
    public var failures: [SyncSaveResult]

    public init(saved: [SyncRecord] = [], deletedNames: [String] = [], failures: [SyncSaveResult] = []) {
        self.saved = saved
        self.deletedNames = deletedNames
        self.failures = failures
    }
}

/// An iCloud account change the engine reports.
public enum SyncAccountChange: Hashable, Sendable {
    case signIn
    case signOut
    case switchAccounts
}

/// The calls `SyncCoordinator` makes on its engine.
public protocol SyncEngineDriving: AnyObject, Sendable {
    /// Adds pending changes the engine does not hold yet; returns how many were new.
    func addPending(_ changes: [SyncPendingChange]) async -> Int
    /// Forgets pending changes.
    func removePending(_ changes: [SyncPendingChange]) async
    /// Queues the creation of zone `TimeTracking`.
    func addZone() async
    func sendChanges() async throws
    func fetchChanges() async throws
}

/// Creates the engine of a coordinator from its saved state.
public protocol SyncEngineFactory: Sendable {
    func makeEngine(for coordinator: SyncCoordinator, state: Data?) async throws -> any SyncEngineDriving
}
