// DeviceEvent: a raw activity event of an iPhone or iPad
// (data_and_sync.md §6, activity_tracking.md §6.2, ios.md §9.1).

public import Foundation

/// A labeled event the iOS app collects and the Mac agent turns into Samples.
public struct DeviceEvent: Sendable, Hashable, Codable {
    /// The mechanism that produced the event.
    public enum Source: String, Sendable, Hashable, CaseIterable {
        /// Screen Time threshold minutes of a labeled set.
        case screenTime
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
        case deviceID, time, source, label, kind, payload, sequence, utcOffset, deviceName
    }

    public var deviceID: String
    public var time: Date
    public var source: Source
    public var label: String
    /// The event kind of the tracker spec, e.g. `minute` or `on`.
    public var kind: String
    /// Optional JSON text with source-specific fields.
    public var payload: String?
    /// Distinguishes events of one device; the staging file assigns it,
    /// increasing with every append.
    public var sequence: Int
    /// Seconds east of UTC of the device clock when the event happened.
    public var utcOffset: Int?
    /// The device's name, stamped by the app's flush (the extensions do not
    /// know it); the Mac names the device's BlockItems with the latest one.
    public var deviceName: String?

    public init(
        deviceID: String,
        time: Date,
        source: Source,
        label: String,
        kind: String,
        payload: String? = nil,
        sequence: Int = 0,
        utcOffset: Int? = nil,
        deviceName: String? = nil
    ) {
        self.deviceID = deviceID
        self.time = time
        self.source = source
        self.label = label
        self.kind = kind
        self.payload = payload
        self.sequence = sequence
        self.utcOffset = utcOffset
        self.deviceName = deviceName
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
        self.utcOffset = try container.decodeIfPresent(Int.self, forKey: .utcOffset)
        self.deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
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
        try container.encodeIfPresent(utcOffset, forKey: .utcOffset)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
    }

    // MARK: Payload

    /// The integer `key` of the payload object.
    public func payloadInt(_ key: String) -> Int? {
        payloadValue(key) as? Int
    }

    /// The boolean `key` of the payload object, `fallback` when absent.
    public func payloadBool(_ key: String, default fallback: Bool) -> Bool {
        (payloadValue(key) as? Bool) ?? fallback
    }

    private func payloadValue(_ key: String) -> Any? {
        guard let payload, let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            return nil
        }
        return object[key]
    }

    /// Payload JSON text with sorted keys, or `nil` for no fields.
    public static func payloadText(_ fields: [String: any Sendable]) -> String? {
        guard !fields.isEmpty, let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DeviceEvent {
    /// The record names of the events before `date` to keep: each device's
    /// last one of each source (and label, for automations, which overlap),
    /// which still tells what was on (activity_tracking.md §2.5).
    public static func kept(of events: [Self], before date: Date) -> Set<String> {
        var last: [String: Self] = [:]
        for event in events where event.time < date {
            let key = [event.deviceID, event.source.rawValue, event.source == .intent ? event.label : ""].joined(separator: "\u{1F}")
            if let current = last[key], (current.time, current.sequence) >= (event.time, event.sequence) {
                continue
            }
            last[key] = event
        }
        return Set(last.values.map(\.recordName))
    }
}

/// A source is encoded as its raw value, the case name (`screenTime`).
extension DeviceEvent.Source: Codable {}
