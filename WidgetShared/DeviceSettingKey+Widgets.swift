// The device settings the iOS app writes and its widgets read
// (ios.md §2.8, §2.9, §3.4).

import TimeTrackingCore

extension DeviceSettingKey where Value == Pomodoro {
    /// The persisted Pomodoro (ios.md §2.8 item 1); widgets end their
    /// timeline at its phase end.
    nonisolated static var pomodoroState: Self {
        Self("pomodoro.state", default: Pomodoro())
    }
}

extension DeviceSettingKey where Value == PinnedTaskMode {
    /// "Task on pinned buttons" (ios.md §2.9).
    nonisolated static var pinnedTaskMode: Self {
        Self("widgets.pinnedTaskMode", default: .latest)
    }
}
