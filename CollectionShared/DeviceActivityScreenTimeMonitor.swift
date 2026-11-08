// DeviceActivityScreenTimeMonitor: Screen Time's registrations through
// DeviceActivityCenter, shared by the app and the monitor extension
// (ios.md §9.2). Cannot run in the simulator or in tests; the logic
// is the library's ScreenTimeController.

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TimeTrackingCore

/// Registers each set as a repeating midnight-to-midnight
/// `DeviceActivitySchedule` named by the set id, with one
/// `DeviceActivityEvent` per threshold over the set's selection
/// ("Everything" has none, so it includes all activity).
nonisolated struct DeviceActivityScreenTimeMonitor: ScreenTimeMonitoring {
    static var schedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
    }

    func startMonitoring(_ registration: ScreenTimeRegistration, for set: ScreenTimeSet) throws {
        let selection = set.selection.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for spec in registration.events {
            events[DeviceActivityEvent.Name(spec.name)] = DeviceActivityEvent(
                applications: set.isEverything ? [] : selection?.applicationTokens ?? [],
                categories: set.isEverything ? [] : selection?.categoryTokens ?? [],
                webDomains: set.isEverything ? [] : selection?.webDomainTokens ?? [],
                threshold: Self.threshold(spec.minutes),
                includesPastActivity: spec.includesPastActivity
            )
        }
        try DeviceActivityCenter().startMonitoring(DeviceActivityName(registration.setID), during: Self.schedule, events: events)
    }

    /// `minutes` as hours and minutes.
    static func threshold(_ minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    func stopMonitoring(_ setIDs: [String]) {
        DeviceActivityCenter().stopMonitoring(setIDs.map { DeviceActivityName($0) })
    }

    /// The measurement of the event cap (phase 7): registers growing
    /// counts of "Everything" events under a probe name and keeps the
    /// largest count `startMonitoring` accepts.
    static func measureCap() -> Int {
        let probe = DeviceActivityName("cap-probe")
        let center = DeviceActivityCenter()
        defer { center.stopMonitoring([probe]) }
        return ScreenTimePlan.measureCap { count in
            var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
            for index in 1 ... count {
                events[DeviceActivityEvent.Name("probe.\(index)")] = DeviceActivityEvent(
                    threshold: threshold(index),
                    includesPastActivity: false
                )
            }
            try center.startMonitoring(probe, during: schedule, events: events)
        }
    }
}
