// SyncTransport: the server side of sync, CloudKit or in memory (spec_data_and_sync.md §3.1, §3.3).

public import Foundation

/// The outcome of saving or deleting one record.
public enum SyncSaveResult: Hashable, Sendable {
    /// Saved; the record carries the server's new system fields.
    case saved(SyncRecord)
    case deleted(SyncRecordRef)
    /// `serverRecordChanged`: the server holds a newer copy.
    case conflict(server: SyncRecord)
    /// `unknownItem`: the record's system fields name a record the server lacks.
    case unknownItem(SyncRecordRef)
    /// `zoneNotFound`.
    case zoneNotFound(SyncRecordRef)
    /// Not saved because another record of an atomic batch failed, or a
    /// transient error; sent again unchanged.
    case retry(SyncRecordRef)
}

/// The changes since a token.
public struct SyncFetchResult: Hashable, Sendable {
    public var records: [SyncRecord]
    public var deletions: [SyncRecordRef]
    /// The token for the next fetch.
    public var token: Data?
    public var moreComing: Bool

    public init(records: [SyncRecord], deletions: [SyncRecordRef], token: Data?, moreComing: Bool = false) {
        self.records = records
        self.deletions = deletions
        self.token = token
        self.moreComing = moreComing
    }
}

/// Transport failures that are not per-record.
public enum SyncTransportError: Error, Hashable, Sendable, LocalizedError {
    case networkUnavailable
    case noAccount
    case zoneNotFound
    case other(String)

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable: "The network is unavailable."
        case .noAccount: "No iCloud account."
        case .zoneNotFound: "The zone does not exist."
        case let .other(message): message
        }
    }
}

/// The private database zone `TimeTracking` as the sync engine sees it.
/// Implemented by `CloudKitTransport` and `InMemoryTransport`.
public protocol SyncTransport: Sendable {
    /// Saves and deletes records; one result per record and deletion.
    func send(saving records: [SyncRecord], deleting refs: [SyncRecordRef]) async throws -> [SyncSaveResult]
    /// The changes since `token` (everything for `nil`).
    func fetchChanges(since token: Data?) async throws -> SyncFetchResult
    /// Creates the zone after `zoneNotFound`.
    func createZone() async throws
}
