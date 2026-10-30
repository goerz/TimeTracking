// PhoneSettings: the iOS app's device settings as observable state
// (spec_ios.md §2.8, §2.9, §8, §11).

import Foundation
import Observation
import TimeTrackingCore

extension DeviceSettingKey where Value == Bool {
    static var pomodoroSounds: Self {
        Self("pomodoro.sounds", default: true)
    }

    /// Whether the device name and first sync are done (spec_ios.md §11).
    static var onboarded: Self {
        Self("onboarded", default: false)
    }

    /// Whether the Siri tip on the Timer screen was dismissed (spec_ios.md §6.2).
    static var siriTipDismissed: Self {
        Self("siriTipDismissed", default: false)
    }
}

extension DeviceSettingKey where Value == Bool {
    /// The long-running reminder: on by default on the iPhone, off on the iPad.
    static func longRunningEnabled(isPad: Bool) -> Self {
        Self("longRunning.enabled", default: !isPad)
    }
}

extension DeviceSettingKey where Value == Int {
    static var longRunningHours: Self {
        Self("longRunning.hours", default: 4)
    }
}

extension DeviceSettingKey where Value == String {
    /// This device's name for its `Device` record.
    static var deviceName: Self {
        Self("deviceName", default: "")
    }
}

extension DeviceSettingKey where Value == [String] {
    /// Entries badged by an adjustment until their sheet opens (spec_ios.md §7 item 3).
    static var badgedEntries: Self {
        Self("badgedEntries", default: [])
    }
}

/// Device settings the views bind to; every change is written through.
@Observable
final class PhoneSettings {
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored let isPad: Bool

    var pomodoroSounds: Bool {
        didSet { device[.pomodoroSounds] = pomodoroSounds }
    }

    /// Long-running reminder: on by default on the iPhone, off on the iPad.
    var longRunningEnabled: Bool {
        didSet { device[.longRunningEnabled(isPad: isPad)] = longRunningEnabled }
    }

    /// 1 to 12 hours.
    var longRunningHours: Int {
        didSet { device[.longRunningHours] = min(max(longRunningHours, 1), 12) }
    }

    var pinnedTaskMode: PinnedTaskMode {
        didSet { device[.pinnedTaskMode] = pinnedTaskMode }
    }

    var deviceName: String {
        didSet { device[.deviceName] = deviceName }
    }

    var siriTipDismissed: Bool {
        didSet { device[.siriTipDismissed] = siriTipDismissed }
    }

    var onboarded: Bool {
        didSet { device[.onboarded] = onboarded }
    }

    init(device: DeviceSettings, isPad: Bool) {
        self.device = device
        self.isPad = isPad
        self.pomodoroSounds = device[.pomodoroSounds]
        self.longRunningEnabled = device[.longRunningEnabled(isPad: isPad)]
        self.longRunningHours = device[.longRunningHours]
        self.pinnedTaskMode = device[.pinnedTaskMode]
        self.deviceName = device[.deviceName]
        self.siriTipDismissed = device[.siriTipDismissed]
        self.onboarded = device[.onboarded]
    }

    /// Device settings in a fresh, private suite (tests and previews).
    static func ephemeral(isPad: Bool = false) -> PhoneSettings {
        let name = "TimeTrackingiOSTests." + UUID().uuidString
        return PhoneSettings(device: DeviceSettings(defaults: UserDefaults(suiteName: name) ?? .standard), isPad: isPad)
    }
}
