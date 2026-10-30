// DeviceEvent: a raw activity event of an iPhone or iPad
// (spec_data_and_sync.md §6, spec_activity_tracking.md §6.2).

public import Foundation

/// A labeled event the iOS app collects and the Mac agent merges into
/// blocks with `src` `device`.
public struct DeviceEvent: Sendable, Hashable, Codable {
    /// The mechanism that produced the event.
    public enum Source: String, Sendable, Hashable, Codable, CaseIterable {
        /// DeviceActivity threshold minutes of a labeled set.
        case ladder
        /// A Focus filter turning on or off.
        case focus
        /// The "Log activity event" App Intent.
        case intent
        /// The Safari Web Extension's tab activations and URL changes.
        case webext
        /// The iOS app's foreground transitions.
        case app
    }

    enum CodingKeys: String, CodingKey {
        case deviceID, time, source, label, kind, payload, sequence
    }

    public var deviceID: String
    public var time: Date
    public var source: Source
    public var label: String
    /// The event kind of the tracker spec, e.g. a threshold or on/off.
    public var kind: String
    /// Optional JSON text with source-specific fields.
    public var payload: String?
    /// Distinguishes events of one device in the same millisecond.
    public var sequence: Int

    public init(
        deviceID: String,
        time: Date,
        source: Source,
        label: String,
        kind: String,
        payload: String? = nil,
        sequence: Int = 0
    ) {
        self.deviceID = deviceID
        self.time = time
        self.source = source
        self.label = label
        self.kind = kind
        self.payload = payload
        self.sequence = sequence
    }

    /// The time in whole milliseconds since 1970.
    public var milliseconds: Int64 {
        Int64((time.timeIntervalSince1970 * 1000).rounded())
    }

    /// `<deviceID>-<time in ms>-<sequence>`, so a resumed flush never duplicates.
    public var recordName: String {
        "\(deviceID)-\(milliseconds)-\(sequence)"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
        let stamp = try container.decode(Int64.self, forKey: .time)
        self.time = Date(timeIntervalSince1970: TimeInterval(stamp) / 1000)
        self.source = try container.decode(Source.self, forKey: .source)
        self.label = try container.decode(String.self, forKey: .label)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.payload = try container.decodeIfPresent(String.self, forKey: .payload)
        self.sequence = try container.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
    }

    /// Encodes `time` as milliseconds since 1970.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(milliseconds, forKey: .time)
        try container.encode(source, forKey: .source)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encode(sequence, forKey: .sequence)
    }
}
