// ActivityDeviceTime: a device's share of a block (spec_data_and_sync.md §6,
// spec_activity_tracking.md §2.8, §4.2).

/// The active seconds a block spent on one device.
///
/// In the logs it is the array `[device, seconds]`; `isRecordingMac` comes
/// from the header's `dev`, the Mac that wrote the file.
public struct ActivityDeviceTime: Sendable, Hashable, Codable {
    /// The device name, or `remote` for unattributed synced Safari history.
    public var name: String
    public var seconds: Int
    /// Whether `name` is the Mac that recorded the block.
    public var isRecordingMac: Bool

    /// The name of unattributed synced Safari history (§6.1).
    public static let remote = "remote"

    public init(name: String, seconds: Int, isRecordingMac: Bool = false) {
        self.name = name
        self.seconds = seconds
        self.isRecordingMac = isRecordingMac
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.name = try container.decode(String.self)
        self.seconds = try container.decode(Int.self)
        self.isRecordingMac = false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(name)
        try container.encode(seconds)
    }

    /// Whether the time was spent on an iPhone or iPad with the iOS app.
    public var isIOSDevice: Bool {
        !isRecordingMac && name != Self.remote
    }
}
