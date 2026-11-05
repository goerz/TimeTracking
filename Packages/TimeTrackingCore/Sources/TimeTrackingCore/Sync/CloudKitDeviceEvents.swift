// CloudKitDeviceEvents: DeviceEvent records in the zone `ActivityEvents` of
// the private database: the iOS flush uploads them, the Mac agent reads and
// purges them (data_and_sync.md §3.1, §6; ios.md §9.6).

public import CloudKit
public import Foundation

/// The mapping between `DeviceEvent` and its CloudKit record.
public enum CloudKitDeviceEvents {
    public static let zoneName = "ActivityEvents"
    public static let recordType = "DeviceEvent"
    /// The most records one modify request may carry.
    public static let batchSize = 400

    public static func zoneID() -> CKRecordZone.ID {
        CloudKitRecords.zoneID(zoneName)
    }

    /// The record of `event`, named `<deviceID>-<time in ms>-<sequence>`.
    public static func record(_ event: DeviceEvent, zoneID: CKRecordZone.ID = zoneID()) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: event.recordName, zoneID: zoneID))
        record["deviceID"] = event.deviceID
        record["time"] = event.time
        record["source"] = event.source.rawValue
        record["label"] = event.label
        record["kind"] = event.kind
        record["payload"] = event.payload
        record["sequence"] = event.sequence
        record["utcOffset"] = event.utcOffset
        record["deviceName"] = event.deviceName
        return record
    }

    /// The event of a fetched record, or `nil` for another type or a record
    /// missing a required field.
    public static func event(_ record: CKRecord) -> DeviceEvent? {
        guard record.recordType == recordType,
              let deviceID = record["deviceID"] as? String,
              let time = record["time"] as? Date,
              let source = (record["source"] as? String).flatMap(DeviceEvent.Source.init(rawValue:)),
              let label = record["label"] as? String,
              let kind = record["kind"] as? String
        else {
            return nil
        }
        return DeviceEvent(
            deviceID: deviceID,
            time: time,
            source: source,
            label: label,
            kind: kind,
            payload: record["payload"] as? String,
            sequence: (record["sequence"] as? Int) ?? 0,
            utcOffset: record["utcOffset"] as? Int,
            deviceName: record["deviceName"] as? String
        )
    }
}

/// The iOS app's uploader for `DeviceEventStagingFile.flush()`: saves every
/// event (overwriting, so a resent batch is harmless), creating the zone
/// when it is missing. It returns only when CloudKit saved every record.
public struct CloudKitDeviceEventUploader: Sendable {
    public let database: CKDatabase
    public let zoneID: CKRecordZone.ID

    public init(containerIdentifier: String) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        self.zoneID = CloudKitDeviceEvents.zoneID()
    }

    public func upload(_ events: [DeviceEvent]) async throws {
        for start in stride(from: 0, to: events.count, by: CloudKitDeviceEvents.batchSize) {
            let batch = Array(events[start ..< min(start + CloudKitDeviceEvents.batchSize, events.count)])
            do {
                try await save(batch)
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                try await createZone()
                try await save(batch)
            }
        }
    }

    private func save(_ batch: [DeviceEvent]) async throws {
        let records = batch.map { CloudKitDeviceEvents.record($0, zoneID: zoneID) }
        let (results, _) = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
        for result in results.values {
            if case let .failure(error) = result {
                throw error
            }
        }
    }

    private func createZone() async throws {
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
    }
}

/// The Mac agent's `DeviceEventSource` over the zone's change feed.
///
/// There is no push subscription: `changes` fires every `pollInterval`
/// (the 5-minute fallback of activity_tracking.md §2.3). `purge`
/// reads the whole zone and deletes the records older than the date; the
/// agent calls it once a day.
public struct CloudKitDeviceEventSource: DeviceEventSource {
    public let database: CKDatabase
    public let zoneID: CKRecordZone.ID
    public let pollInterval: TimeInterval

    public init(containerIdentifier: String, pollInterval: TimeInterval = 300) {
        self.database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        self.zoneID = CloudKitDeviceEvents.zoneID()
        self.pollInterval = pollInterval
    }

    public func events(since token: ChangeToken?) async throws -> ([DeviceEvent], ChangeToken) {
        var events: [DeviceEvent] = []
        var current = token.flatMap { CloudKitRecords.unarchiveToken($0.data) }
        do {
            while true {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: current)
                for result in changes.modificationResultsByID.values {
                    if case let .success(modification) = result, let event = CloudKitDeviceEvents.event(modification.record) {
                        events.append(event)
                    }
                }
                current = changes.changeToken
                if !changes.moreComing {
                    break
                }
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // No iOS device has flushed yet.
            return ([], token ?? ChangeToken(data: Data()))
        } catch {
            throw CloudKitTransport.transportError(error)
        }
        let data = current.flatMap(CloudKitRecords.archive) ?? token?.data ?? Data()
        return (events.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) }, ChangeToken(data: data))
    }

    public func purge(before date: Date) async throws {
        let (events, _) = try await events(since: nil)
        let old = events.filter { $0.time < date }.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
        for start in stride(from: 0, to: old.count, by: CloudKitDeviceEvents.batchSize) {
            let batch = Array(old[start ..< min(start + CloudKitDeviceEvents.batchSize, old.count)])
            do {
                _ = try await database.modifyRecords(saving: [], deleting: batch)
            } catch {
                throw CloudKitTransport.transportError(error)
            }
        }
    }

    public var changes: AsyncStream<Void> {
        let interval = pollInterval
        return AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval))
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
