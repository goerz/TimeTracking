// Synced and device setting keys (spec_data_and_sync.md §1.6).

public import Foundation

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

/// A device setting in the App Group's `UserDefaults` suite.
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

/// The names of synced settings with a field-level merge.
public enum SettingMerge {
    /// The key of `activity.contextColors`.
    public static let contextColorsKey = "activity.contextColors"

    /// The union of two context color maps; the smaller index wins for a
    /// context assigned differently.
    public static func mergeContextColors(_ lhs: [String: Int], _ rhs: [String: Int]) -> [String: Int] {
        lhs.merging(rhs) { min($0, $1) }
    }

    /// The hue index for a new context: the one used by the fewest
    /// contexts, the lowest on ties.
    public static func hueIndex(forNewContextIn colors: [String: Int], hueCount: Int) -> Int {
        var counts = Array(repeating: 0, count: max(hueCount, 1))
        for index in colors.values where counts.indices.contains(index) {
            counts[index] += 1
        }
        let fewest = counts.min() ?? 0
        return counts.firstIndex(of: fewest) ?? 0
    }
}

/// Device settings: the App Group's `UserDefaults` suite, values as JSON.
public struct DeviceSettings: @unchecked Sendable {
    /// UserDefaults is thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The App Group suite of `identity`, or the standard defaults.
    public init(identity: AppIdentity?) {
        self.defaults = identity.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
    }

    public subscript<Value>(key: DeviceSettingKey<Value>) -> Value {
        get {
            guard let data = defaults.data(forKey: key.name),
                  let value = try? JSONDecoder().decode(Value.self, from: data)
            else {
                return key.defaultValue
            }
            return value
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key.name)
        }
    }

    /// The `deviceID` device setting, created on first use.
    public var deviceID: DeviceID {
        if let string = defaults.string(forKey: "deviceID"), let id = DeviceID(string) {
            return id
        }
        let id = DeviceID()
        defaults.set(id.rawValue, forKey: "deviceID")
        return id
    }
}
