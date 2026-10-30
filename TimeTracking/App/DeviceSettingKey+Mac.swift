// The Mac app's device settings (spec_timer_window.md §1, §6.2, §7, §8;
// spec_menubar.md §6).

import Foundation
import TimeTrackingCore

extension DeviceSettingKey where Value == Bool {
    static var timerPinned: Self {
        Self("timerPinned", default: false)
    }

    static var showTimerAtLogin: Self {
        Self("showTimerAtLogin", default: false)
    }

    static var menuBarShowTimer: Self {
        Self("menuBar.showTimer", default: true)
    }

    static var menuBarShowSeconds: Self {
        Self("menuBar.showSeconds", default: false)
    }

    static var menuBarShowProject: Self {
        Self("menuBar.showProject", default: false)
    }

    static var showDockIcon: Self {
        Self("showDockIcon", default: true)
    }

    static var idleDetect: Self {
        Self("idle.detect", default: true)
    }

    static var idleStopOnShutdown: Self {
        Self("idle.stopOnShutdown", default: true)
    }

    static var focusOnStart: Self {
        Self("shortcuts.focusOnStart", default: false)
    }

    static var focusOnStop: Self {
        Self("shortcuts.focusOnStop", default: false)
    }

    static var trackerOnboardingPrompted: Self {
        Self("trackerOnboardingPrompted", default: false)
    }
}

extension DeviceSettingKey where Value == IdleLockBehavior {
    static var idleOnLockOrSleep: Self {
        Self("idle.onLockOrSleep", default: .ask)
    }
}

extension DeviceSettingKey where Value == ReminderSchedule {
    static var reminders: Self {
        Self("reminders", default: ReminderSchedule())
    }
}

extension DeviceSettingKey where Value == StoredFrame? {
    static var timerFullFrame: Self {
        Self("timerFullFrame", default: nil)
    }

    static var timerCompactFrame: Self {
        Self("timerCompactFrame", default: nil)
    }

    /// The frame at quit, restored at launch (it carries the mode).
    static var timerFrame: Self {
        Self("timerFrame", default: nil)
    }
}
