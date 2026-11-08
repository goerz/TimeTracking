// The competition across devices and background blocks of a pass
// (activity_tracking.md §2.7 steps 2 and 3).

import Foundation
import Testing
@testable import TimeTrackingCore

struct BlockFormerDeviceTests {
    private static let myApp = ActivityFixture.terminal("MyApp")
    private static let social = ActivityItem(app: "Social", appID: "screenTime", workspace: "Social")
    private static let everything = ActivityItem(app: "iPhone", appID: ActivityItem.everythingAppID, workspace: "iPhone")
    private static let goodnotes = ActivityItem(app: "Goodnotes", appID: "intent", workspace: "Goodnotes")
    private static let job = ActivityItem(
        app: "tmux", appID: "tmux", session: "paper:build.0", location: "~/Code/MyApp", command: "make test", workspace: "~/Code/MyApp"
    )

    @Test("TRK-27 a block runs from the Mac to the iPhone and back; iPhone use during Mac attention is background; ranks decide overlaps")
    func devicesShareOneStream() throws {
        var away = SampleTimeline()
        away.work("09:00", "09:15", Self.myApp)
        away.away("09:15", "09:20:10", .locked, background: [ActivityFixture.agent])
        away.device(SampleTimeline.iPhone, "09:15:10", "09:20:10", Self.social)
        away.work("09:20:10", "09:35:10", Self.myApp)
        away.away("09:35:10", "10:00")
        let block = try #require(away.pass().blocks.first)
        #expect(away.pass().blocks.count == 1)
        #expect(block.seconds(on: "MacBook") == 30 * 60)
        #expect(block.seconds(on: "iPhone") == 5 * 60)
        #expect(block.background.contains { $0.item == ActivityFixture.agent && $0.device == "MacBook" })

        var glance = SampleTimeline()
        glance.work("09:00", "09:30", Self.myApp)
        glance.device(SampleTimeline.iPhone, "09:10", "09:15", Self.social)
        glance.away("09:30", "10:00")
        let attention = try #require(glance.pass().blocks.first)
        #expect(attention.activeSeconds == 30 * 60 && attention.seconds(on: "iPhone") == 0)
        #expect(attention.background.contains { $0.device == "iPhone" && $0.item == Self.social && $0.seconds == 5 * 60 })

        var ranks = SampleTimeline()
        ranks.device(SampleTimeline.iPhone, "09:00", "09:20", Self.everything)
        ranks.device(SampleTimeline.iPad, "09:05", "09:15", Self.goodnotes, source: .intent)
        let shared = try #require(ranks.pass().blocks.first)
        #expect(shared.seconds(on: "iPad") == 10 * 60)
        #expect(shared.seconds(on: "iPhone") == 10 * 60)

        var once = SampleTimeline()
        once.device(SampleTimeline.iPhone, "09:00", "09:12", Self.social)
        once.device(SampleTimeline.iPhone, "09:00", "09:12", Self.everything)
        let counted = try #require(once.pass().blocks.first)
        #expect(counted.foreground.map(\.item) == [Self.social] && counted.activeSeconds == 12 * 60)
        #expect(counted.background.isEmpty)

        var focus = SampleTimeline()
        focus.device(SampleTimeline.iPhone, "09:00", "09:20", Self.social)
        focus.add("09:05", "09:15", device: SampleTimeline.iPhone, source: .focus, state: .paused)
        #expect(focus.pass().blocks.map(\.span) == ["09:00–09:20"])

        var synced = SampleTimeline()
        synced.work("09:00", "09:20", Self.myApp)
        synced.away("09:20", "09:40")
        synced.device(
            "remote",
            "09:10",
            "09:25",
            ActivityFixture.page("https://arxiv.org/abs/2401.1", workspace: "arxiv.org"),
            source: .safariHistory
        )
        let filled = try #require(synced.pass().blocks.first)
        #expect(filled.seconds(on: "MacBook") == 20 * 60 && filled.seconds(on: "remote") == 5 * 60)
    }

    @Test("TRK-28 a busy agent while away forms a background block after the foreground block; short items and empty blocks are dropped")
    func backgroundBlocks() {
        var work = SampleTimeline()
        work.work("09:00", "09:20", Self.myApp, background: [ActivityFixture.agent])
        work.away("09:20", "10:00", background: [ActivityFixture.agent, Self.job])
        work.away("10:00", "10:20")
        let blocks = work.pass().blocks
        #expect(blocks.map(\.span) == ["09:00–09:20", "09:20–10:00"])
        #expect(blocks[0].background.first?.seconds == 20 * 60)
        #expect(blocks[1].isBackgroundBlock && blocks[1].background.map(\.item) == [ActivityFixture.agent, Self.job])

        var short = SampleTimeline()
        short.work("09:00", "09:20", Self.myApp)
        short.away("09:20", "09:24", background: [Self.job])
        short.away("09:24", "09:40", background: [ActivityFixture.agent])
        short.away("09:40", "10:00")
        let kept = short.pass().blocks
        // The block starts where the item it keeps starts.
        #expect(kept.map(\.span) == ["09:00–09:20", "09:24–09:40"])
        #expect(kept[1].background.map(\.item) == [ActivityFixture.agent])

        var empty = SampleTimeline()
        empty.work("09:00", "09:20", Self.myApp)
        empty.away("09:20", "09:24", background: [Self.job])
        empty.away("09:24", "10:00")
        #expect(empty.pass().blocks.map(\.span) == ["09:00–09:20"])
    }

    @Test(
        "TRK-63 a background block ends idle after idle_close, split at a foreground block, at max_background_block; not at a glance"
    )
    func backgroundEndings() {
        var gap = SampleTimeline()
        gap.away("09:00", "09:20", background: [ActivityFixture.agent])
        gap.away("09:20", "09:26")
        gap.away("09:26", "09:40", background: [ActivityFixture.agent])
        gap.away("09:40", "10:00")
        let idle = gap.pass().blocks
        #expect(idle.map(\.span) == ["09:00–09:20", "09:26–09:40"])
        #expect(idle.map(\.endReason) == [.idle, .idle])

        var attention = SampleTimeline()
        attention.away("09:00", "09:30", background: [ActivityFixture.agent])
        attention.work("09:30", "09:50", Self.myApp)
        attention.away("09:50", "10:10")
        let split = attention.pass().blocks
        #expect(split.map(\.span) == ["09:00–09:30", "09:30–09:50"])
        #expect(split.first?.endReason == .split)

        var long = SampleTimeline()
        long.away("09:00", "12:10", background: [ActivityFixture.agent])
        long.away("12:10", "12:30")
        let cut = long.pass().blocks
        #expect(cut.map(\.span) == ["09:00–12:00", "12:00–12:10"])
        #expect(cut.first?.endReason == .maxLength)

        var glance = SampleTimeline()
        glance.away("09:00", "09:30", background: [ActivityFixture.agent])
        glance.work("09:30", "09:31", Self.myApp, background: [ActivityFixture.agent])
        glance.away("09:31", "10:00", background: [ActivityFixture.agent])
        glance.away("10:00", "10:20")
        #expect(glance.pass().blocks.map(\.span) == ["09:00–10:00"])
    }
}
