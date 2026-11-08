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
/// (the 5-minute fetch of activity_tracking.md §2.5). `purge` reads the
/// whole zone and deletes the records older than the date except the
/// last of each device and source (`DeviceEvent.kept(of:before:)`); the
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

    /// The events added since `token` and the token after them. A record
    /// that fails to load fails the fetch, so the token doesn't move past
    /// it; an expired token starts over from the beginning, which stores
    /// nothing twice (events are keyed by record name).
    public func events(since token: ChangeToken?) async throws -> DeviceEventBatch {
        let start = token.flatMap { CloudKitRecords.unarchiveToken($0.data) }
        var page: Page
        do {
            do {
                page = try await changes(since: start)
            } catch let error as CKError where error.code == .changeTokenExpired {
                page = try await changes(since: nil)
            }
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // No iOS device has flushed yet.
            return DeviceEventBatch(events: [], token: token ?? ChangeToken(data: Data()))
        } catch {
            throw CloudKitTransport.transportError(error)
        }
        let data = page.token.flatMap(CloudKitRecords.archive) ?? token?.data ?? Data()
        return DeviceEventBatch(
            events: page.events.sorted { ($0.time, $0.sequence) < ($1.time, $1.sequence) },
            token: ChangeToken(data: data),
            unreadable: page.unreadable.count
        )
    }

    /// What the change feed holds since a token.
    private struct Page {
        var events: [DeviceEvent] = []
        /// Device event records that don't decode, with their time.
        var unreadable: [(id: CKRecord.ID, time: Date?)] = []
        var token: CKServerChangeToken?
    }

    /// Every page of changes since `token`, and the token after the last.
    private func changes(since token: CKServerChangeToken?) async throws -> Page {
        var page = Page(token: token)
        while true {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: page.token)
            for result in changes.modificationResultsByID.values {
                let record = try result.get().record
                if let event = CloudKitDeviceEvents.event(record) {
                    page.events.append(event)
                } else if record.recordType == CloudKitDeviceEvents.recordType {
                    page.unreadable.append((record.recordID, (record["time"] as? Date) ?? record.creationDate))
                }
            }
            page.token = changes.changeToken
            if !changes.moreComing {
                return page
            }
        }
    }

    /// Deletes the events older than `date` except each device's and
    /// source's last, and the device event records older than `date` that
    /// this version can't read, which no Mac will convert.
    public func purge(before date: Date) async throws {
        let page: Page
        do {
            page = try await changes(since: nil)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return
        } catch {
            throw CloudKitTransport.transportError(error)
        }
        let kept = DeviceEvent.kept(of: page.events, before: date)
        let old = page.events.filter { $0.time < date && !kept.contains($0.recordName) }
            .map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
            + page.unreadable.filter { ($0.time ?? .distantFuture) < date }.map(\.id)
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
