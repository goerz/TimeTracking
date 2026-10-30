// CloudKitTransport: the private database zone `TimeTracking` of
// `iCloud.<APP_ID>` as a SyncTransport (spec_data_and_sync.md §3.1, §3.3).

public import CloudKit
public import Foundation

/// Saves, deletes, and fetches through `CKDatabase` without the sync engine:
/// used by the integration tests and `LiveStateReader`. The app's sync runs
/// through `SyncCoordinator` and `CKSyncEngine`, which share the record
/// mapping (`CloudKitRecords`).
public struct CloudKitTransport: SyncTransport, LiveStateFetching {
    public let database: CKDatabase
    public let zoneID: CKRecordZone.ID

    /// The private database of `containerIdentifier`. Check
    /// `CloudKitAvailability.check(containerIdentifier:)` first: CloudKit
    /// stops a process that lacks the container's entitlement.
    public init(containerIdentifier: String, zoneName: String = CloudKitRecords.zoneName) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        self.zoneID = CloudKitRecords.zoneID(zoneName)
    }

    public init(database: CKDatabase, zoneID: CKRecordZone.ID = CloudKitRecords.zoneID()) {
        self.database = database
        self.zoneID = zoneID
    }

    /// Saves with `ifServerRecordUnchanged`; a batch containing `LiveState`
    /// is atomic (§3.1 item 2).
    public func send(saving records: [SyncRecord], deleting refs: [SyncRecordRef]) async throws -> [SyncSaveResult] {
        let atomic = records.contains { $0.ref.type == .liveState }
        let saveResults: [CKRecord.ID: Result<CKRecord, any Error>]
        let deleteResults: [CKRecord.ID: Result<Void, any Error>]
        do {
            (saveResults, deleteResults) = try await database.modifyRecords(
                saving: records.map { CloudKitRecords.record($0, zoneID: zoneID) },
                deleting: refs.map { CloudKitRecords.recordID($0, zoneID: zoneID) },
                savePolicy: .ifServerRecordUnchanged,
                atomically: atomic
            )
        } catch {
            throw Self.transportError(error)
        }
        var results: [SyncSaveResult] = []
        for record in records {
            switch saveResults[CloudKitRecords.recordID(record.ref, zoneID: zoneID)] {
            case let .success(saved):
                results.append(CloudKitRecords.syncRecord(saved).map { .saved($0) } ?? .retry(record.ref))
            case let .failure(error):
                try results.append(Self.saveResult(record.ref, error))
            case nil:
                results.append(.retry(record.ref))
            }
        }
        for ref in refs {
            switch deleteResults[CloudKitRecords.recordID(ref, zoneID: zoneID)] {
            case .success, nil:
                results.append(.deleted(ref))
            case let .failure(error):
                let code = (error as? CKError)?.code
                try results.append(code == .unknownItem ? .deleted(ref) : Self.saveResult(ref, error))
            }
        }
        return results
    }

    public func fetchChanges(since token: Data?) async throws -> SyncFetchResult {
        do {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token.flatMap(CloudKitRecords.unarchiveToken))
            let records = changes.modificationResultsByID.values.compactMap { result -> SyncRecord? in
                guard case let .success(modification) = result else {
                    return nil
                }
                return CloudKitRecords.syncRecord(modification.record)
            }.sorted { $0.ref.description < $1.ref.description }
            let deletions = changes.deletions.compactMap { CloudKitRecords.ref($0.recordID, type: $0.recordType) }
            return SyncFetchResult(
                records: records,
                deletions: deletions,
                token: CloudKitRecords.archive(changes.changeToken),
                moreComing: changes.moreComing
            )
        } catch {
            throw Self.transportError(error)
        }
    }

    public func createZone() async throws {
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch {
            throw Self.transportError(error)
        }
    }

    /// Deletes the zone with every record (integration tests).
    public func deleteZone() async throws {
        do {
            _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        } catch {
            throw Self.transportError(error)
        }
    }

    /// One record, or `nil` when the server has none.
    public func fetch(_ ref: SyncRecordRef) async throws -> SyncRecord? {
        do {
            return try await CloudKitRecords.syncRecord(database.record(for: CloudKitRecords.recordID(ref, zoneID: zoneID)))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw Self.transportError(error)
        }
    }

    private static func saveResult(_ ref: SyncRecordRef, _ error: any Error) throws -> SyncSaveResult {
        guard let error = error as? CKError else {
            throw SyncTransportError.other(error.localizedDescription)
        }
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord.flatMap(CloudKitRecords.syncRecord) else {
                return .retry(ref)
            }
            return .conflict(server: server)
        case .unknownItem:
            return .unknownItem(ref)
        case .zoneNotFound, .userDeletedZone:
            return .zoneNotFound(ref)
        case .batchRequestFailed, .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .retry(ref)
        default:
            throw transportError(error)
        }
    }

    /// The transport error of a CloudKit error.
    public static func transportError(_ error: any Error) -> SyncTransportError {
        guard let error = error as? CKError else {
            return .other(error.localizedDescription)
        }
        switch error.code {
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .networkUnavailable
        case .notAuthenticated:
            return .noAccount
        case .zoneNotFound, .userDeletedZone:
            return .zoneNotFound
        default:
            return .other(error.localizedDescription)
        }
    }
}
