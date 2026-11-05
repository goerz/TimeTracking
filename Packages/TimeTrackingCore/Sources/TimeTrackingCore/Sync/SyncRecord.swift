// SyncRecord: a transport-neutral record of zone `TimeTracking` (data_and_sync.md §3.1, §3.2).

public import Foundation

/// A field value. Booleans travel as 0/1 integers, as in CloudKit.
public enum SyncValue: Hashable, Sendable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case date(Date)

    public var string: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var int: Int64? {
        if case let .int(value) = self {
            return value
        }
        return nil
    }

    public var double: Double? {
        switch self {
        case let .double(value): value
        case let .int(value): Double(value)
        default: nil
        }
    }

    public var date: Date? {
        if case let .date(value) = self {
            return value
        }
        return nil
    }
}

/// A record as the transports see it: type, name, camelCase fields of
/// spec §1 (references as `String` UUIDs; absent fields are `nil`), and the
/// opaque system fields the transport returned last (CloudKit's archived
/// system fields, or the in-memory change tag).
public struct SyncRecord: Hashable, Sendable, Codable {
    public var ref: SyncRecordRef
    public var fields: [String: SyncValue]
    public var systemFields: Data?

    public init(ref: SyncRecordRef, fields: [String: SyncValue], systemFields: Data? = nil) {
        self.ref = ref
        self.fields = fields
        self.systemFields = systemFields
    }

    public subscript(field: String) -> SyncValue? {
        get { fields[field] }
        set { fields[field] = newValue }
    }

    /// `modifiedAt` in milliseconds; 0 when absent.
    public var modifiedMillis: Int64 {
        fields["modifiedAt"]?.date.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0
    }

    /// Whether the record is a tombstone.
    public var isDeleted: Bool {
        fields["deletedAt"] != nil
    }

    /// The order of conflict resolution (spec §3.2): the later `modifiedAt`
    /// wins; on a tie the greater record name, then `deviceID`, then the
    /// canonical field text, so every device picks the same copy.
    public func wins(over other: Self) -> Bool {
        let mine = (modifiedMillis, ref.name, fields["deviceID"]?.string ?? "", canonicalFields)
        let theirs = (other.modifiedMillis, other.ref.name, other.fields["deviceID"]?.string ?? "", other.canonicalFields)
        return mine > theirs
    }

    /// The fields as sorted `key=value` text.
    public var canonicalFields: String {
        fields.keys.sorted().map { key in
            let value = switch fields[key] {
            case let .string(text): "s:\(text)"
            case let .int(number): "i:\(number)"
            case let .double(number): "d:\(number)"
            case let .date(date): "t:\(date.timeIntervalSince1970)"
            case nil: ""
            }
            return "\(key)=\(value)"
        }.joined(separator: "\n")
    }
}
