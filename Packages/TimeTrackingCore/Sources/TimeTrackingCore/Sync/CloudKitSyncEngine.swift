// CloudKitSyncEngine: CKSyncEngine with automatic sync and a database
// subscription, delegating to SyncCoordinator (data_and_sync.md §3.1).

public import CloudKit
public import Foundation
import os
import Synchronization

/// The factory of the app's engine for `iCloud.<APP_ID>`.
public struct CloudKitSyncEngineFactory: SyncEngineFactory {
    public let containerIdentifier: String

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    /// Fails with `SyncTransportError.notEntitled` when the process lacks the
    /// container's entitlement (ad-hoc builds), before CloudKit is touched.
    public func makeEngine(for coordinator: SyncCoordinator, state: Data?) async throws -> any SyncEngineDriving {
        guard CloudKitAvailability.check(containerIdentifier: containerIdentifier) else {
            throw SyncTransportError.notEntitled
        }
        let container = CKContainer(identifier: containerIdentifier)
        switch try await container.accountStatus() {
        case .available:
            break
        case .noAccount:
            throw SyncTransportError.noAccount
        default:
            throw SyncTransportError.other("The iCloud account is not available.")
        }
        return CloudKitSyncEngine(database: container.privateCloudDatabase, coordinator: coordinator, state: state)
    }
}

/// Bridges `CKSyncEngine` events and batches to `SyncCoordinator` in
/// terms of `SyncRecord`.
public final class CloudKitSyncEngine: CKSyncEngineDelegate, SyncEngineDriving {
    private let coordinator: SyncCoordinator
    private let zoneID = CloudKitRecords.zoneID()
    private let engine = Mutex<CKSyncEngine?>(nil)
    private static let logger = Logging.logger(category: "Sync")

    public init(database: CKDatabase, coordinator: SyncCoordinator, state: Data?) {
        self.coordinator = coordinator
        let serialization = state.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: self)
        configuration.automaticallySync = true
        let created = CKSyncEngine(configuration)
        engine.withLock { $0 = created }
    }

    private var syncEngine: CKSyncEngine? {
        engine.withLock { $0 }
    }

    // MARK: SyncEngineDriving

    public func addPending(_ changes: [SyncPendingChange]) -> Int {
        guard let syncEngine else {
            return 0
        }
        let known = Set(syncEngine.state.pendingRecordZoneChanges)
        let new = changes.map(ckChange).filter { !known.contains($0) }
        if !new.isEmpty {
            syncEngine.state.add(pendingRecordZoneChanges: new)
        }
        return new.count
    }

    public func removePending(_ changes: [SyncPendingChange]) {
        syncEngine?.state.remove(pendingRecordZoneChanges: changes.map(ckChange))
    }

    public func addZone() {
        syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }

    public func sendChanges() async throws {
        do {
            try await syncEngine?.sendChanges()
        } catch {
            throw CloudKitTransport.transportError(error)
        }
    }

    public func fetchChanges() async throws {
        do {
            try await syncEngine?.fetchChanges()
        } catch {
            throw CloudKitTransport.transportError(error)
        }
    }

    private func ckChange(_ change: SyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        switch change {
        case let .save(ref): .saveRecord(CloudKitRecords.recordID(ref, zoneID: zoneID))
        case let .delete(ref): .deleteRecord(CloudKitRecords.recordID(ref, zoneID: zoneID))
        }
    }

    // MARK: CKSyncEngineDelegate

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        var changes: [SyncPendingChange] = []
        var unknown: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            switch change {
            case let .saveRecord(id) where id.zoneID == zoneID:
                if let ref = await coordinator.pendingRef(named: id.recordName) {
                    changes.append(.save(ref))
                } else {
                    unknown.append(change)
                }
            case let .deleteRecord(id) where id.zoneID == zoneID:
                if let ref = await coordinator.pendingRef(named: id.recordName) {
                    changes.append(.delete(ref))
                } else {
                    unknown.append(change)
                }
            default:
                unknown.append(change)
            }
        }
        if !unknown.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: unknown)
        }
        guard let batch = await coordinator.nextBatch(changes) else {
            return nil
        }
        if !batch.dropped.isEmpty {
            syncEngine.state.remove(pendingRecordZoneChanges: batch.dropped.map(ckChange))
        }
        guard !batch.isEmpty else {
            return nil
        }
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: batch.records.map { CloudKitRecords.record($0, zoneID: zoneID) },
            recordIDsToDelete: batch.deletions.map { CloudKitRecords.recordID($0, zoneID: zoneID) },
            atomicByZone: batch.atomic
        )
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                await coordinator.stateChanged(data)
            }
        case let .accountChange(change):
            await accountChanged(change.changeType)
        case let .fetchedDatabaseChanges(changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                await coordinator.zoneDeleted()
            }
        case let .fetchedRecordZoneChanges(changes):
            await fetched(changes)
        case let .sentRecordZoneChanges(sent):
            await coordinator.didSend(outcome(of: sent))
        case let .sentDatabaseChanges(sent):
            for failure in sent.failedZoneSaves {
                Self.logger.error("Saving the zone failed: \(failure.error.localizedDescription, privacy: .public)")
            }
        default:
            await progress(event, pending: syncEngine.state.pendingRecordZoneChanges.count)
        }
    }

    private func accountChanged(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn: await coordinator.accountChanged(.signIn)
        case .signOut: await coordinator.accountChanged(.signOut)
        case .switchAccounts: await coordinator.accountChanged(.switchAccounts)
        @unknown default: break
        }
    }

    private func fetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        let records = changes.modifications.map(\.record).filter { $0.recordID.zoneID == zoneID }
            .compactMap(CloudKitRecords.syncRecord)
        let deletions = changes.deletions.filter { $0.recordID.zoneID == zoneID }
            .compactMap { CloudKitRecords.ref($0.recordID, type: $0.recordType) }
        await coordinator.didFetch(records, deletions: deletions)
    }

    private func progress(_ event: CKSyncEngine.Event, pending: Int) async {
        switch event {
        case .willSendChanges:
            await coordinator.engineStatus(.sending(pending))
        case .willFetchChanges:
            await coordinator.engineStatus(.fetching)
        case .didSendChanges, .didFetchChanges:
            await coordinator.engineStatus(.idle)
        default:
            break
        }
    }

    private func outcome(of sent: CKSyncEngine.Event.SentRecordZoneChanges) -> SyncSendOutcome {
        var outcome = SyncSendOutcome(
            saved: sent.savedRecords.compactMap(CloudKitRecords.syncRecord),
            deletedNames: sent.deletedRecordIDs.map(\.recordName)
        )
        for failure in sent.failedRecordSaves {
            guard let ref = CloudKitRecords.ref(failure.record.recordID, type: failure.record.recordType) else {
                continue
            }
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord.flatMap(CloudKitRecords.syncRecord) {
                    outcome.failures.append(.conflict(server: server))
                } else {
                    outcome.failures.append(.retry(ref))
                }
            case .unknownItem:
                outcome.failures.append(.unknownItem(ref))
            case .zoneNotFound, .userDeletedZone:
                outcome.failures.append(.zoneNotFound(ref))
            default:
                Self.logger.notice("Save of \(ref.description, privacy: .public) will be retried: \(failure.error.code.rawValue)")
                outcome.failures.append(.retry(ref))
            }
        }
        for (id, error) in sent.failedRecordDeletes where error.code == .unknownItem {
            outcome.deletedNames.append(id.recordName)
        }
        return outcome
    }
}
