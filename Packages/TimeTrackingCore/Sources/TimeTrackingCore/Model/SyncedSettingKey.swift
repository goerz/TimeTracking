// Synced and device setting keys (spec_data_and_sync.md §1.6).

/// A synced setting: a `setting` record whose value is JSON. Other specs
/// declare their keys in constrained extensions, as below.
public struct SyncedSettingKey<Value: Codable & Sendable & Equatable>: Sendable, Hashable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// A device setting in the App Group's `UserDefaults` suite. The same shape
/// as `SyncedSettingKey`, but a separate type, so a device key cannot be
/// passed to `TimeStore.set`.
public struct DeviceSettingKey<Value: Codable & Sendable & Equatable>: Sendable, Hashable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension SyncedSettingKey<Int> {
    public static var pomodoroFocusMinutes: Self {
        Self("pomodoro.focusMinutes", default: 25)
    }

    public static var pomodoroBreakMinutes: Self {
        Self("pomodoro.breakMinutes", default: 5)
    }

    /// The values the setting allows (spec_timer.md §5.2): 1 to 180
    /// focus minutes, 1 to 60 break minutes; any value for other keys.
    public var range: ClosedRange<Int> {
        switch self {
        case .pomodoroFocusMinutes: 1 ... 180
        case .pomodoroBreakMinutes: 1 ... 60
        default: Int.min ... Int.max
        }
    }

    /// `value` moved into `range`.
    public func clamped(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension SyncedSettingKey<[ProjectID]> {
    public static var pinnedProjectIDs: Self {
        Self("pinnedProjectIDs", default: [])
    }
}

extension SyncedSettingKey<[String: Int]> {
    /// Context to hue index; merges as a union, the smaller index winning.
    public static var activityContextColors: Self {
        Self("activity.contextColors", default: [:])
    }
}

extension SyncedSettingKey<String?> {
    public static var timeBlockCalendarID: Self {
        Self("calendar.timeBlockCalendarID", default: nil)
    }
}

extension DeviceSettingKey<Bool> {
    public static var pomodoroSounds: Self {
        Self("pomodoro.sounds", default: true)
    }
}

extension DeviceSettingKey<Int> {
    public static var idleThresholdMinutes: Self {
        Self("idle.thresholdMinutes", default: 10)
    }
}
