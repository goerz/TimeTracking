// Device: one record per device that runs the app (spec_data_and_sync.md §1.8).

public import Foundation

/// The platform of a device record.
public enum DevicePlatform: String, Codable, Sendable, CaseIterable {
    case mac
    case iphone
    case ipad
}

/// A device. Never deleted automatically.
public struct Device: Identifiable, Hashable, Sendable {
    /// The `deviceID` device setting.
    public var id: DeviceID
    public var name: String
    public var platform: DevicePlatform
    /// Updated at most hourly while the app runs.
    public var lastSeenAt: Date
    /// iPhone and iPad: the widget extension's WidgetKit push token, hex.
    public var widgetPushToken: String?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: DeviceID,
        name: String,
        platform: DevicePlatform,
        lastSeenAt: Date,
        widgetPushToken: String? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.widgetPushToken = widgetPushToken
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
