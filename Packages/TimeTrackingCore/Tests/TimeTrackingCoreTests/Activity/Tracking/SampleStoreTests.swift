// The Sample table's two writes, deleted ranges, and the daily drop
// (activity_tracking.md §2.4, §2.6, §4.1).

import Foundation
import Testing
@testable import TimeTrackingCore

struct SampleStoreTests {
    private static let myApp = ActivityFixture.terminal("MyApp")

    @Test(
        "TRK-13 insert drops the Samples inside a deleted range and marks the dates of the others; replace with an equal list marks nothing"
    )
    func insertAndReplace() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.work("09:00", "09:10", Self.myApp)
        try rig.store.deleteRange(
            DateInterval(start: timeline.time("09:00"), end: timeline.time("09:05")),
            now: timeline.time("12:00"),
            rules: rig.rules
        )
        try rig.store.setMeta(.changedDays, [])
        let marked = try rig.store.insert(timeline.sorted, rules: rig.rules)
        #expect(marked == [rig.day("2024-03-14")])
        let stored = try rig.store.samples(SampleSelection(range: DateInterval(
            start: timeline.time("00:00"),
            end: timeline.time("+00:00")
        )))
        #expect(stored.count == 10)
        #expect(stored.allSatisfy { $0.time >= timeline.time("09:05") })

        try rig.store.setMeta(.changedDays, [])
        let selection = SampleSelection(
            range: DateInterval(start: timeline.time("09:05"), end: timeline.time("09:10")),
            deviceID: SampleTimeline.mac
        )
        #expect(try rig.store.replace(selection, with: stored, rules: rig.rules) == nil)
        #expect(try rig.changedDays().isEmpty)
        // A new Sample outside the selection is not kept.
        var outside = stored
        outside.append(Sample(
            time: timeline.time("10:00"),
            deviceID: SampleTimeline.mac,
            source: .live,
            state: .active,
            foreground: Self.myApp
        ))
        #expect(try rig.store.replace(selection, with: outside, rules: rig.rules) == nil)
    }

    @Test(
        "TRK-16 TRK-69 a daily drop moves the cutoff one day, after the changed dates before it; frozen dates take no Sample, mark nothing"
    )
    func dailyDrop() throws {
        let rig = try RebuildRig()
        let first = rig.day("2024-01-01")
        try rig.store.recordFirstStart(today: first)
        var old = SampleTimeline()
        old.day = "2024-01-01"
        old.work("09:00", "09:30", Self.myApp)
        try rig.store.insert(old.sorted, rules: rig.rules)
        let today = rig.day("2024-04-15")
        #expect(try rig.store.dropOldSamples(today: today, rules: rig.rules) == nil)
        try rig.run(now: old.time("12:00"))
        #expect(try rig.store.dropOldSamples(today: today, rules: rig.rules) == rig.day("2024-01-02"))
        #expect(try rig.store.meta(.cutoffDay) == rig.day("2024-01-02"))
        #expect(try rig.changedDays().isEmpty)
        #expect(try rig.store.samples(SampleSelection(range: DateInterval(start: .distantPast, end: .distantFuture))).isEmpty)
        #expect(rig.blocks("2024-01-01").map(\.span) == ["09:00–09:30"])
        // A late Sample on the frozen date is not stored.
        #expect(try rig.store.insert(old.sorted, rules: rig.rules).isEmpty)
        // One day per drop, never past today − 90 days.
        #expect(try rig.store.dropOldSamples(today: today, rules: rig.rules) == rig.day("2024-01-03"))
        #expect(try rig.store.dropOldSamples(today: rig.day("2024-01-05"), rules: rig.rules) == nil)
    }

    @Test("TRK-70 a deleted range ends at the time of the request at the latest")
    func deletedRangeEndsNow() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        try rig.store.deleteRange(
            DateInterval(start: timeline.time("00:00"), end: timeline.time("+00:00")),
            now: timeline.time("10:00"),
            rules: rig.rules
        )
        timeline.work("09:00", "09:10", Self.myApp)
        timeline.work("10:00", "10:10", Self.myApp)
        try rig.store.insert(timeline.sorted, rules: rig.rules)
        let stored = try rig.store.samples(SampleSelection(range: DateInterval(start: .distantPast, end: .distantFuture)))
        #expect(stored.count == 20)
        #expect(stored.allSatisfy { $0.time >= timeline.time("10:00") })
    }
}
