// Synced and device setting keys (data_and_sync.md §1.6).

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

    /// The Calendar's snapping: 1, 5, 10, or 15 (calendar.md §6).
    public static var calendarSnapMinutes: Self {
        Self("calendar.snapMinutes", default: 5)
    }

    /// The hour of the local clock at which the app's days start, 0 to 23
    /// (data_and_sync.md §8). Only display and reports follow it.
    public static var startOfDayHour: Self {
        Self("day.startHour", default: 0)
    }

    /// The values the setting allows (timer.md §5.2): 1 to 180
    /// focus minutes, 1 to 60 break minutes, hours 0 to 23; any value for
    /// other keys.
    public var range: ClosedRange<Int> {
        switch self {
        case .pomodoroFocusMinutes: 1 ... 180
        case .pomodoroBreakMinutes: 1 ... 60
        case .startOfDayHour: 0 ... 23
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
    /// App to hue index; merges as a union, the smaller index winning.
    public static var activityAppColors: Self {
        Self("activity.appColors", default: [:])
    }
}

extension SyncedSettingKey<[CalendarChoice]> {
    /// The external calendars the Calendar shows, as (account, calendar)
    /// titles, which name the same calendar on every device (calendar.md §4.3, §6).
    public static var calendarShownCalendars: Self {
        Self("calendar.shownCalendars", default: [])
    }
}

extension SyncedSettingKey<Bool> {
    /// Sleep from Apple Health as lines in the Calendar's Activity column
    /// (calendar.md §3.1, §6); the iPhone imports while it is on.
    public static var calendarShowSleep: Self {
        Self("calendar.showSleep", default: false)
    }

    /// Workouts from Apple Health, likewise.
    public static var calendarShowWorkouts: Self {
        Self("calendar.showWorkouts", default: false)
    }
}

extension SyncedSettingKey<AreaID?> {
    /// The area whose reports count sleep, as the project "Sleep"
    /// (reports.md §1.1); nil counts it nowhere.
    public static var calendarSleepAreaID: Self {
        Self("calendar.sleepAreaID", default: nil)
    }

    /// The area whose reports count workouts, as the project "Workouts".
    public static var calendarWorkoutAreaID: Self {
        Self("calendar.workoutAreaID", default: nil)
    }
}

extension SyncedSettingKey<String?> {
    public static var timeBlockCalendarID: Self {
        Self("calendar.timeBlockCalendarID", default: nil)
    }

    /// The time-block calendar's title, which finds it on a device whose
    /// identifier differs (calendar.md §4.1); nil means "Time Blocks".
    public static var timeBlockCalendarTitle: Self {
        Self("calendar.timeBlockCalendarTitle", default: nil)
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
