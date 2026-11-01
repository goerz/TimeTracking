// Tests of the Apple Health periods: merging, the import, and sync
// (spec_data_and_sync.md §1.9; §9 items 50 and 51).

import Foundation
import Testing
import TimeTrackingCore

/// Fixed samples in place of HealthKit.
private struct FixedSamples: HealthSampleReading {
    var asleep: [DateInterval] = []
    var inBed: [DateInterval] = []
    var workoutIntervals: [DateInterval] = []

    func sleepSamples(in interval: DateInterval) -> (asleep: [DateInterval], inBed: [DateInterval]) {
        (asleep.filter { $0.intersects(interval) }, inBed.filter { $0.intersects(interval) })
    }

    func workouts(in interval: DateInterval) -> [DateInterval] {
        workoutIntervals.filter { $0.intersects(interval) }
    }
}

struct HealthPeriodTests {
    private static func span(_ test: TestStore, _ start: String, _ end: String) throws -> DateInterval {
        try DateInterval(start: test.date(start), end: test.date(end))
    }

    @Test(
        "DATA-50 replacing health periods keeps an unchanged one's record, tombstones the rest, ignores earlier ones; the periods sync"
    )
    func replaceAndSync() async throws {
        let net = try await Network()
        let (phone, mac) = (net.peers[0], net.peers[1])
        let test = phone.test
        let night = try Self.span(test, "2024-03-12T23:10", "2024-03-13T06:40")
        let run = try Self.span(test, "2024-03-13T18:00", "2024-03-13T18:45")
        try await phone.store.replaceHealthPeriods(.sleep, from: test.date("2024-03-10T00:00"), with: [night])
        try await phone.store.replaceHealthPeriods(.workout, from: test.date("2024-03-10T00:00"), with: [run])
        let day = try Self.span(test, "2024-03-10T00:00", "2024-03-14T10:00")
        let first = try await phone.store.healthPeriods(in: day)
        #expect(first.map(\.kind) == [.sleep, .workout])
        // A later import: the night is unchanged, a nap is new, an earlier
        // night outside the range is ignored.
        let nap = try Self.span(test, "2024-03-13T14:00", "2024-03-13T14:40")
        let earlier = try Self.span(test, "2024-03-09T23:00", "2024-03-10T07:00")
        let changed = try await phone.store.replaceHealthPeriods(.sleep, from: test.date("2024-03-10T00:00"), with: [earlier, night, nap])
        #expect(changed == 1)
        let second = try await phone.store.healthPeriods(in: day)
        #expect(second.first { $0.kind == .sleep }?.id == first[0].id)
        #expect(second.map(\.interval) == [night, nap, run])
        // The night shifts: its old record becomes a tombstone.
        let shifted = try Self.span(test, "2024-03-12T23:30", "2024-03-13T06:40")
        #expect(try await phone.store.replaceHealthPeriods(.sleep, from: test.date("2024-03-10T00:00"), with: [shifted, nap]) == 2)
        try await net.converge()
        let synced = try await mac.store.healthPeriods(in: day)
        #expect(synced.map(\.interval) == [shifted, nap, run])
        #expect(synced.map(\.kind) == [.sleep, .sleep, .workout])
        #expect(try await mac.store.outboxCount() == 0)
    }

    @Test("DATA-51 sleep joins stages across short wakes, an in-bed night without asleep samples counts, and the import window")
    func sleepAndImport() async throws {
        let test = try await TestStore()
        // Core, deep, and REM with a 20 minute wake, then a 2 hour wake.
        let asleep = try [
            Self.span(test, "2024-03-13T23:00", "2024-03-14T01:00"),
            Self.span(test, "2024-03-14T00:30", "2024-03-14T02:00"),
            Self.span(test, "2024-03-14T02:20", "2024-03-14T04:00"),
            Self.span(test, "2024-03-14T06:00", "2024-03-14T07:00"),
        ]
        let inBed = try [
            Self.span(test, "2024-03-13T22:40", "2024-03-14T07:10"),
            Self.span(test, "2024-03-12T23:00", "2024-03-13T06:00"),
        ]
        #expect(try HealthPeriod.sleep(asleep: asleep, inBed: inBed) == [
            Self.span(test, "2024-03-12T23:00", "2024-03-13T06:00"),
            Self.span(test, "2024-03-13T23:00", "2024-03-14T04:00"),
            Self.span(test, "2024-03-14T06:00", "2024-03-14T07:00"),
        ])
        // Two sources recording one workout merge.
        let source = try FixedSamples(asleep: asleep, inBed: inBed, workoutIntervals: [
            Self.span(test, "2024-03-13T18:00", "2024-03-13T18:45"),
            Self.span(test, "2024-03-13T18:02", "2024-03-13T18:50"),
        ])
        let now = test.clock.now
        #expect(try HealthImport.from(importedThrough: nil, now: now) == test.date("2024-01-14T10:00"))
        #expect(try HealthImport.from(importedThrough: test.date("2024-03-13T08:00"), now: now) == test.date("2024-03-10T08:00"))
        try await HealthImport.run(.workout, source: source, store: test.store, importedThrough: nil, now: now)
        try await HealthImport.run(.sleep, source: source, store: test.store, importedThrough: nil, now: now)
        let periods = try await test.store.healthPeriods(in: Self.span(test, "2024-03-01T00:00", "2024-03-15T00:00"))
        #expect(try periods.filter { $0.kind == .workout }.map(\.interval) == [Self.span(test, "2024-03-13T18:00", "2024-03-13T18:50")])
        #expect(periods.count(where: { $0.kind == .sleep }) == 3)
        // Running again changes nothing.
        #expect(try await HealthImport.run(.sleep, source: source, store: test.store, importedThrough: now, now: now) == 0)
    }
}
