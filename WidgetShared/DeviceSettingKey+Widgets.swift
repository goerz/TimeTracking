// The device settings the iOS app writes and its widgets read
// (spec_ios.md §2.8, §2.9, §3.4).

import TimeTrackingCore

extension DeviceSettingKey where Value == Pomodoro {
    /// The persisted Pomodoro (spec_ios.md §2.8 item 1); widgets end their
    /// timeline at its phase end.
    static var pomodoroState: Self {
        Self("pomodoro.state", default: Pomodoro())
    }
}

extension DeviceSettingKey where Value == PinnedTaskMode {
    /// "Task on pinned buttons" (spec_ios.md §2.9).
    static var pinnedTaskMode: Self {
        Self("widgets.pinnedTaskMode", default: .latest)
    }
}
