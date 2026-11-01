// AppSettings: the Mac app's device settings as observable state
// (spec_timer.md §6.2, §7, §8; spec_menubar.md §6).

import Foundation
import Observation
import TimeTrackingCore

/// Device settings the views bind to. Every change is written through at
/// once ("Changes apply immediately").
@Observable
final class AppSettings {
    @ObservationIgnored let device: DeviceSettings

    var timerPinned: Bool {
        didSet { device[.timerPinned] = timerPinned }
    }

    var showTimerAtLogin: Bool {
        didSet { device[.showTimerAtLogin] = showTimerAtLogin }
    }

    var menuBarShowTimer: Bool {
        didSet { device[.menuBarShowTimer] = menuBarShowTimer }
    }

    var menuBarShowSeconds: Bool {
        didSet { device[.menuBarShowSeconds] = menuBarShowSeconds }
    }

    var menuBarShowProject: Bool {
        didSet { device[.menuBarShowProject] = menuBarShowProject }
    }

    var menuBarPomodoroDisplay: MenuBarPomodoroDisplay {
        didSet { device[.menuBarPomodoroDisplay] = menuBarPomodoroDisplay }
    }

    var showDockIcon: Bool {
        didSet { device[.showDockIcon] = showDockIcon }
    }

    var pomodoroSounds: Bool {
        didSet { device[.pomodoroSounds] = pomodoroSounds }
    }

    var idle: IdleSettings {
        didSet {
            device[.idleDetect] = idle.detectIdle
            device[.idleThresholdMinutes] = idle.thresholdMinutes
            device[.idleOnLockOrSleep] = idle.onLockOrSleep
            device[.idleStopOnShutdown] = idle.stopOnShutdown
        }
    }

    var reminders: ReminderSchedule {
        didSet { device[.reminders] = reminders }
    }

    var focusOnStart: Bool {
        didSet { device[.focusOnStart] = focusOnStart }
    }

    var focusOnStop: Bool {
        didSet { device[.focusOnStop] = focusOnStop }
    }

    var trackerOnboardingPrompted: Bool {
        didSet { device[.trackerOnboardingPrompted] = trackerOnboardingPrompted }
    }

    init(device: DeviceSettings) {
        self.device = device
        self.timerPinned = device[.timerPinned]
        self.showTimerAtLogin = device[.showTimerAtLogin]
        self.menuBarShowTimer = device[.menuBarShowTimer]
        self.menuBarShowSeconds = device[.menuBarShowSeconds]
        self.menuBarShowProject = device[.menuBarShowProject]
        self.menuBarPomodoroDisplay = device[.menuBarPomodoroDisplay]
        self.showDockIcon = device[.showDockIcon]
        self.pomodoroSounds = device[.pomodoroSounds]
        self.idle = IdleSettings(
            detectIdle: device[.idleDetect],
            thresholdMinutes: device[.idleThresholdMinutes],
            onLockOrSleep: device[.idleOnLockOrSleep],
            stopOnShutdown: device[.idleStopOnShutdown]
        )
        self.reminders = device[.reminders]
        self.focusOnStart = device[.focusOnStart]
        self.focusOnStop = device[.focusOnStop]
        self.trackerOnboardingPrompted = device[.trackerOnboardingPrompted]
    }

    /// Device settings in a fresh, private suite (tests and previews).
    static func ephemeral() -> AppSettings {
        let name = "TimeTrackingTests." + UUID().uuidString
        return AppSettings(device: DeviceSettings(defaults: UserDefaults(suiteName: name) ?? .standard))
    }
}
