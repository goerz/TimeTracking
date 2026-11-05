// Tests of the iPhone's import from Apple Health (ios.md §7 item 6).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

/// Fixed samples and a record of the authorization requests.
private final class FakeHealth: HealthAccess, HealthSampleReading {
    let night: DateInterval
    let run: DateInterval
    private let requests = Mutex<[Set<HealthPeriod.Kind>]>([])

    init(night: DateInterval, run: DateInterval) {
        self.night = night
        self.run = run
    }

    var asked: [Set<HealthPeriod.Kind>] {
        requests.withLock { $0 }
    }

    var source: any HealthSampleReading {
        self
    }

    func authorize(_ kinds: Set<HealthPeriod.Kind>) {
        requests.withLock { $0.append(kinds) }
    }

    func sleepSamples(in interval: DateInterval) -> (asleep: [DateInterval], inBed: [DateInterval]) {
        ([night].filter { $0.intersects(interval) }, [])
    }

    func workouts(in interval: DateInterval) -> [HealthPeriodDraft] {
        [run].filter { $0.intersects(interval) }.map { HealthPeriodDraft($0, activity: "running", distance: 7000) }
    }
}

@MainActor
struct HealthImportTests {
    @Test("IOS-40 with Sleep on, the iPhone asks for sleep access at the foreground and imports; a refresh imports without asking")
    func importOnForeground() async throws {
        let phone = try await TestPhone()
        let health = try FakeHealth(
            night: DateInterval(start: phone.date("2024-03-13T23:00"), end: phone.date("2024-03-14T06:30")),
            run: DateInterval(start: phone.date("2024-03-13T18:00"), end: phone.date("2024-03-13T18:40"))
        )
        phone.model.health = health
        let week = try DateInterval(start: phone.date("2024-03-08T00:00"), end: phone.date("2024-03-15T00:00"))
        // Both off: nothing is asked or imported.
        await phone.model.foreground()
        #expect(health.asked.isEmpty)
        #expect(try await phone.store.healthPeriods(in: week).isEmpty)
        // Sleep turned on elsewhere: the next foreground asks and imports.
        try await phone.store.set(.calendarShowSleep, true)
        await phone.model.foreground()
        #expect(health.asked == [[.sleep]])
        #expect(try await phone.store.healthPeriods(in: week).map(\.kind) == [.sleep])
        #expect(phone.settings.device[HealthImport.importedThrough(.sleep)] == phone.clock.now.timeIntervalSince1970)
        // Workouts turned on here: asks for both, imports the workout.
        await phone.model.setHealth(.workout, true)
        #expect(health.asked.last == [.sleep, .workout])
        #expect(try await phone.store.healthPeriods(in: week).map(\.kind) == [.workout, .sleep])
        // The refresh task never shows the sheet.
        await phone.model.refreshTask()
        #expect(health.asked.count == 2)
    }

    @Test("IOS-41 an import records the synced status with the device name and kinds read, hourly unless the kinds change")
    func recordsStatus() async throws {
        let phone = try await TestPhone()
        let health = try FakeHealth(
            night: DateInterval(start: phone.date("2024-03-13T23:00"), end: phone.date("2024-03-14T06:30")),
            run: DateInterval(start: phone.date("2024-03-13T18:00"), end: phone.date("2024-03-13T18:40"))
        )
        phone.model.health = health
        phone.settings.deviceName = "Test Phone"
        #expect(try await phone.store.value(.calendarHealthImport) == nil)
        await phone.model.setHealth(.sleep, true)
        let first = try await phone.store.value(.calendarHealthImport)
        #expect(first == HealthImportStatus(device: "Test Phone", date: phone.clock.now, kinds: [.sleep]))
        // Within the hour, the same kinds: not rewritten.
        phone.clock.advance(by: 600)
        await phone.model.refreshTask()
        #expect(try await phone.store.value(.calendarHealthImport) == first)
        // A new kind rewrites at once; an hour later, the time moves.
        await phone.model.setHealth(.workout, true)
        #expect(try await phone.store.value(.calendarHealthImport)?.kinds == [.sleep, .workout])
        phone.clock.advance(by: 3600)
        await phone.model.refreshTask()
        #expect(try await phone.store.value(.calendarHealthImport)?.date == phone.clock.now)
    }
}
