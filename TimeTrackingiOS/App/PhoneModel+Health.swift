// The iPhone's import of sleep and workouts from Apple Health while the
// synced Calendar settings ask for them (spec_ios.md §7 item 6).

import Foundation
import os
import TimeTrackingCore

extension PhoneModel {
    /// The synced settings that start an import when they change.
    static let healthSettingNames: Set<String> = [
        SyncedSettingKey<Bool>.calendarShowSleep.name,
        SyncedSettingKey<Bool>.calendarShowWorkouts.name,
    ]

    /// The kinds the synced settings turn on.
    func healthKinds() async -> Set<HealthPeriod.Kind> {
        var kinds: Set<HealthPeriod.Kind> = []
        if await (try? store.value(.calendarShowSleep)) == true {
            kinds.insert(.sleep)
        }
        if await (try? store.value(.calendarShowWorkouts)) == true {
            kinds.insert(.workout)
        }
        return kinds
    }

    /// Imports each kind the settings turn on, asking for access first when
    /// `interactive`, then sends. A failed kind (a locked device's
    /// protected data) keeps its periods and its last import time.
    func importHealth(interactive: Bool) async {
        guard let health else {
            return
        }
        let kinds = await healthKinds()
        guard !kinds.isEmpty else {
            return
        }
        if interactive {
            await health.authorize(kinds)
        }
        var changed = 0
        for kind in HealthPeriod.Kind.allCases where kinds.contains(kind) {
            let key = HealthImport.importedThrough(kind)
            let stamp = settings.device[key]
            let now = clock.now
            do {
                changed += try await HealthImport.run(
                    kind,
                    source: health.source,
                    store: store,
                    importedThrough: stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil,
                    now: now
                )
                settings.device[key] = now.timeIntervalSince1970
            } catch {
                let reason = String(describing: error)
                Logging.logger(category: "Health").error("Import of \(kind.rawValue, privacy: .public): \(reason, privacy: .public)")
            }
        }
        if changed > 0 {
            await sync?.sendNow()
        }
    }

    /// The iPhone Settings' Health toggles: writes the synced setting and,
    /// when turned on, asks for access and imports.
    func setHealth(_ kind: HealthPeriod.Kind, _ isOn: Bool) async {
        do {
            switch kind {
            case .sleep: try await store.set(.calendarShowSleep, isOn)
            case .workout: try await store.set(.calendarShowWorkouts, isOn)
            }
        } catch {
            Logging.logger(category: "Health").error("Setting: \(String(describing: error), privacy: .public)")
        }
        if isOn {
            await importHealth(interactive: true)
        }
    }
}
