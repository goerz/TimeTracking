// CloudKitRecords: SyncRecord to and from CKRecord, field for field
// (spec_data_and_sync.md §3.1).

public import CloudKit
import Foundation

/// The mapping between transport-neutral records and CloudKit records of
/// zone `TimeTracking`. Field names are the camelCase names of §1;
/// booleans are integers; system fields are the archived CKRecord system
/// fields.
public enum CloudKitRecords {
    /// The zone of every record type except `DeviceEvent`.
    public static let zoneName = "TimeTracking"

    public static func zoneID(_ name: String = zoneName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
    }

    /// Every field each record type has ever had, so a field absent from a
    /// `SyncRecord` (an `end` removed, a `deletedAt` cleared) is cleared on
    /// the server too.
    static let fieldNames: [SyncRecordType: [String]] = [
        .client: ["name", "createdAt", "modifiedAt", "deletedAt"],
        .area: ["clientID", "name", "general", "color", "sortOrder", "retired", "createdAt", "modifiedAt", "deletedAt"],
        .project: ["areaID", "name", "archived", "archivedAt", "createdAt", "modifiedAt", "deletedAt"],
        .timeEntry: [
            "projectID", "task", "start", "end", "timeZone", "deviceID", "splitRootID", "createdAt", "modifiedAt", "deletedAt",
        ],
        .setting: ["value", "modifiedAt", "deletedAt"],
        .device: ["name", "platform", "lastSeenAt", "widgetPushToken", "createdAt", "modifiedAt"],
        .suggestionFeedback: [
            "recordedAt", "queryStart", "queryEnd", "queryItems", "source", "blockStart", "blockDevice", "proposedProjectID",
            "proposedTask", "confidence", "outcome", "chosenProjectID", "chosenTask", "entryID", "createdAt", "modifiedAt",
            "deletedAt",
        ],
        .liveState: ["running", "changedAt", "activity"],
    ]

    public static func recordID(_ ref: SyncRecordRef, zoneID: CKRecordZone.ID = zoneID()) -> CKRecord.ID {
        CKRecord.ID(recordName: ref.name, zoneID: zoneID)
    }

    /// The CKRecord to save: the archived system fields when known (so the
    /// server can detect conflicts), else a new record, with every field set.
    public static func record(_ record: SyncRecord, zoneID: CKRecordZone.ID = zoneID()) -> CKRecord {
        let id = recordID(record.ref, zoneID: zoneID)
        var result = CKRecord(recordType: record.ref.type.rawValue, recordID: id)
        if let data = record.systemFields, let restored = unarchive(data), restored.recordID == id {
            result = restored
        }
        for key in Set(fieldNames[record.ref.type] ?? []).union(record.fields.keys).sorted() {
            result[key] = value(record.fields[key])
        }
        return result
    }

    /// The `SyncRecord` of a fetched or saved CKRecord, or `nil` for a
    /// record type this library does not know.
    public static func syncRecord(_ record: CKRecord) -> SyncRecord? {
        guard let ref = ref(record.recordID, type: record.recordType) else {
            return nil
        }
        var fields: [String: SyncValue] = [:]
        for key in record.allKeys() {
            if let value = syncValue(record[key]) {
                fields[key] = value
            }
        }
        return SyncRecord(ref: ref, fields: fields, systemFields: archive(record))
    }

    public static func ref(_ id: CKRecord.ID, type: CKRecord.RecordType) -> SyncRecordRef? {
        SyncRecordType(rawValue: type).map { SyncRecordRef($0, id.recordName) }
    }

    /// The record's system fields, archived with secure coding.
    public static func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else {
            return nil
        }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    public static func archive(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    public static func unarchiveToken(_ data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func value(_ value: SyncValue?) -> (any CKRecordValueProtocol)? {
        switch value {
        case let .string(text): text
        case let .int(number): number
        case let .double(number): number
        case let .date(date): date
        case nil: nil
        }
    }

    private static func syncValue(_ value: (any CKRecordValueProtocol)?) -> SyncValue? {
        switch value {
        case let text as String:
            .string(text)
        case let date as Date:
            .date(date)
        // CloudKit returns numbers as NSNumber; only it tells an Int64
        // field from a Double one holding a whole number.
        // swiftlint:disable:next legacy_objc_type
        case let number as NSNumber:
            if CFNumberIsFloatType(number) {
                .double(number.doubleValue)
            } else {
                .int(number.int64Value)
            }
        default:
            nil
        }
    }
}
