// The rebuild loop over changed dates: order, frozen dates, midnight,
// settling, and the date files (activity_tracking.md §2.7, §4.1).

import Foundation
import Testing
@testable import TimeTrackingCore

struct RebuildLoopTests {
    private static let myApp = ActivityFixture.terminal("MyApp")
    private static let paper = ActivityFixture.terminal("Paper", session: "paper:draft.1")

    @Test("TRK-20 the loop takes the oldest changed date first and today last, and skips a frozen date")
    func order() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.day = "2024-03-12"
        timeline.work("09:00", "09:30", Self.myApp)
        try rig.insert(timeline)
        timeline.day = "2024-03-14"
        timeline.work("09:00", "09:30", Self.myApp)
        try rig.insert(timeline)
        try rig.store.setMeta(.changedDays, rig.changedDays().union([rig.day("2024-03-10")]))
        try rig.store.setMeta(.cutoffDay, rig.day("2024-03-11"))
        let results = try rig.run(now: timeline.time("12:00"))
        let days = results.compactMap { result -> String? in
            switch result {
            case let .formed(day, _, _): "\(day)"
            case let .frozen(day): "frozen \(day)"
            case .waiting, .failed: nil
            }
        }
        #expect(days.first == "frozen 2024-03-10")
        #expect(days.last == "2024-03-14")
        #expect(days.firstIndex(of: "2024-03-12") ?? 9 < days.firstIndex(of: "2024-03-14") ?? 0)
    }

    @Test(
        "TRK-26 a block from 23:30 to 00:40 is whole in its start date's file; open past midnight it rebuilds its date; then the next date"
    )
    func blockPastMidnight() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.work("23:30", "+00:40", Self.myApp)
        timeline.away("+00:40", "+00:50")
        timeline.work("+00:50", "+01:10", Self.paper)
        timeline.away("+01:10", "+01:30")

        try rig.insert(timeline, until: "+00:20")
        let open = try rig.run(now: timeline.time("+00:20"))
        #expect(RebuildRig.open(in: open)?.span == "23:30–00:20")
        #expect(rig.blocks("2024-03-15").isEmpty)
        #expect(try rig.store.meta(.dayEnds)?[rig.day("2024-03-14")] == .unsettled)

        try rig.insert(timeline)
        try rig.run(now: timeline.time("+02:00"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["23:30–00:40"])
        #expect(rig.blocks("2024-03-15").map(\.span) == ["00:50–01:10"])
    }

    @Test(
        "TRK-62 a short block at 00:03 merges into one that ended at 23:58, also across late iPhone Samples; a 15-minute one starts a date"
    )
    func shortBlockAfterMidnight() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.work("23:30", "23:58", Self.myApp)
        timeline.away("23:58", "+00:03")
        timeline.work("+00:03", "+00:07", Self.myApp)
        timeline.away("+00:07", "+00:40")
        try rig.insert(timeline)
        try rig.run(now: timeline.time("+01:00"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["23:30–00:07"])
        #expect(rig.blocks("2024-03-15").isEmpty)

        var phone = SampleTimeline()
        phone.device(SampleTimeline.iPhone, "23:58", "+00:03", ActivityItem(app: "Social", appID: "screenTime", workspace: "Social"))
        try rig.insert(phone)
        try rig.run(now: timeline.time("+02:00"))
        let merged = rig.blocks("2024-03-14")
        #expect(merged.map(\.span) == ["23:30–00:07"])
        #expect(merged.first?.seconds(on: "iPhone") == 5 * 60)
        #expect(rig.blocks("2024-03-15").isEmpty)

        let separate = try RebuildRig()
        var long = SampleTimeline()
        long.work("23:30", "23:58", Self.myApp)
        long.away("23:58", "+00:03")
        long.work("+00:03", "+00:18", Self.myApp)
        long.away("+00:18", "+00:40")
        try separate.insert(long)
        try separate.run(now: long.time("+01:00"))
        #expect(separate.blocks("2024-03-14").map(\.span) == ["23:30–23:58"])
        #expect(separate.blocks("2024-03-15").map(\.span) == ["00:03–00:18"])
    }

    @Test(
        "TRK-66 work to 22:00, sleep 23:00 to 08:00, work: the first pass after waking settles the evening; the morning is in the next file"
    )
    func overnightSleep() throws {
        let rig = try RebuildRig()
        var evening = SampleTimeline()
        evening.work("21:00", "22:00", Self.myApp)
        evening.away("22:00", "23:00")
        evening.once("23:00", state: .asleep)
        try rig.insert(evening)
        try rig.run(now: evening.time("23:00:10"))
        #expect(try rig.store.meta(.dayEnds)?[rig.day("2024-03-14")] == .unsettled)

        var morning = SampleTimeline()
        morning.day = "2024-03-15"
        morning.work("08:00", "09:00", Self.paper)
        morning.away("09:00", "09:20")
        try rig.insert(morning)
        try rig.run(now: morning.time("09:30"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["21:00–22:00"])
        #expect(rig.blocks("2024-03-15").map(\.span) == ["08:00–09:00"])

        let replay = try RebuildRig()
        try replay.insert(evening)
        try replay.insert(morning)
        try replay.run(now: .distantFuture)
        #expect(replay.blocks("2024-03-14").map(\.span) == ["21:00–22:00"])
        #expect(replay.blocks("2024-03-15").map(\.span) == ["08:00–09:00"])
    }

    @Test("TRK-30 a rebuild that forms the same blocks leaves the date file untouched")
    func unchangedFile() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.work("09:00", "09:30", Self.myApp)
        timeline.away("09:30", "10:00")
        try rig.insert(timeline)
        try rig.run(now: timeline.time("12:00"))
        try rig.store.mark([rig.day("2024-03-14")], rules: rig.rules)
        let again = try rig.run(now: timeline.time("12:05"))
        #expect(again.contains(.formed(day: rig.day("2024-03-14"), written: .unchanged, current: .set(nil))))
    }

    @Test("TRK-31 TRK-60 a date file present only as a placeholder is not written; once it arrives the date is rebuilt")
    func placeholder() throws {
        let rig = try RebuildRig()
        let day = rig.day("2024-03-14")
        try FileManager.default.createDirectory(at: rig.log.url, withIntermediateDirectories: true)
        let placeholder = ActivityFile.placeholderURL(for: rig.log.fileURL(for: day))
        try Data("stub".utf8).write(to: placeholder)
        var timeline = SampleTimeline()
        timeline.work("09:00", "09:30", Self.myApp)
        timeline.away("09:30", "10:00")
        try rig.insert(timeline)
        let first = try rig.run(now: timeline.time("12:00"))
        #expect(first.contains { result in
            if case .formed(_, .pendingDownload, _) = result {
                true
            } else {
                false
            }
        })
        #expect(rig.blocks("2024-03-14").isEmpty)
        #expect(try rig.loop.recheckPlaceholders().isEmpty)

        try FileManager.default.removeItem(at: placeholder)
        #expect(try rig.loop.recheckPlaceholders() == [day])
        try rig.run(now: timeline.time("12:05"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["09:00–09:30"])
    }

    @Test("TRK-68 a date's 00:00 stays at the offset it was first marked with, so a zone change moves no block to another file")
    func fixedBoundaries() throws {
        let rig = try RebuildRig()
        var timeline = SampleTimeline()
        timeline.work("23:30", "23:55", Self.myApp)
        timeline.away("23:55", "+00:30")
        try rig.insert(timeline)
        try rig.run(now: timeline.time("+01:00"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["23:30–23:55"])

        // In Chicago, an hour west, 23:30 New York time is still the 14th,
        // but 00:10 New York time would be the 14th too; the stored offset keeps the old line.
        rig.zone = try #require(TimeZone(identifier: "America/Chicago"))
        var late = SampleTimeline()
        late.work("+00:10", "+00:30", Self.paper)
        late.away("+00:30", "+01:00")
        try rig.insert(late)
        try rig.run(now: timeline.time("+03:00"))
        #expect(rig.blocks("2024-03-14").map(\.span) == ["23:30–23:55"])
        #expect(rig.blocks("2024-03-15").map(\.span) == ["00:10–00:30"])
        #expect(try rig.store.meta(.dayOffsets)?[rig.day("2024-03-15")] == -4 * 3600)
    }
}
