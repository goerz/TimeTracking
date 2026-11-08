// The foreground walk of a pass: idle and state closes, splits, the
// longest block, and held blocks (activity_tracking.md §2.7 step 3).

import Foundation
import Testing
@testable import TimeTrackingCore

struct BlockFormerTests {
    private static let myApp = ActivityFixture.terminal("MyApp")
    private static let paper = ActivityFixture.terminal("Paper", session: "paper:draft.1")

    @Test("TRK-21 a block closes after idle_close without an attentive Sample at the end of its credited time; shorter gaps earn nothing")
    func idleClose() {
        var short = SampleTimeline()
        short.work("09:00", "09:20", Self.myApp)
        short.away("09:20", "09:24")
        short.work("09:24", "09:44", Self.myApp)
        short.away("09:44", "10:00")
        let one = short.pass().blocks
        #expect(one.map(\.span) == ["09:00–09:44"])
        #expect(one.first?.activeSeconds == 40 * 60)
        #expect(one.first?.endReason == .idle)

        var long = SampleTimeline()
        long.work("09:00", "09:20", Self.myApp)
        long.away("09:20", "09:26")
        long.work("09:26", "09:46", Self.myApp)
        long.away("09:46", "10:00")
        let two = long.pass().blocks
        #expect(two.map(\.span) == ["09:00–09:20", "09:26–09:46"])
        #expect(two.map(\.endReason) == [.idle, .idle])
    }

    @Test(
        "TRK-22 a lock without other devices' use closes the block; a stopped agent gives stopped; sleep after a move to the iPhone, idle"
    )
    func stateEndings() {
        var locked = SampleTimeline()
        locked.work("09:00", "09:15", Self.myApp)
        locked.away("09:15", "09:17", .locked)
        locked.work("09:17", "09:30", Self.myApp)
        locked.away("09:30", "10:00")
        let blocks = locked.pass().blocks
        #expect(blocks.map(\.span) == ["09:00–09:15", "09:17–09:30"])
        #expect(blocks.map(\.endReason) == [.locked, .idle])

        var stopped = SampleTimeline()
        stopped.work("09:00", "09:15", Self.myApp)
        stopped.work("10:00", "10:20", Self.myApp)
        stopped.away("10:20", "10:30")
        #expect(stopped.pass().blocks.map(\.endReason) == [.stopped, .idle])

        var moved = SampleTimeline()
        moved.work("09:00", "09:15", Self.myApp)
        moved.once("09:15:30", state: .asleep)
        moved.device(SampleTimeline.iPhone, "09:15:30", "09:20", ActivityFixture.app("Social", appID: "screenTime"))
        let block = moved.pass().blocks
        #expect(block.map(\.span) == ["09:00–09:20"])
        #expect(block.first?.endReason == .idle)
    }

    @Test("TRK-23 15 minutes in one workspace then 15 in another split at the change; alternating every 2 minutes for 40 never splits")
    func splits() {
        var moving = SampleTimeline()
        moving.work("09:00", "09:15", Self.myApp)
        moving.work("09:15", "09:30", Self.paper)
        moving.away("09:30", "10:00")
        let blocks = moving.pass().blocks
        #expect(blocks.map(\.span) == ["09:00–09:15", "09:15–09:30"])
        #expect(blocks.map(\.endReason) == [.split, .idle])

        var alternating = SampleTimeline()
        for minute in stride(from: 0, to: 40, by: 2) {
            let item = minute.isMultiple(of: 4) ? Self.myApp : Self.paper
            alternating.work(String(format: "09:%02d", minute), String(format: "09:%02d", minute + 2), item)
        }
        alternating.away("09:40", "10:00")
        #expect(alternating.pass().blocks.map(\.span) == ["09:00–09:40"])
    }

    @Test(
        "TRK-24 at max_block a block is cut at the best change point of its last 30 minutes, else there; a passive one at max_passive_block"
    )
    func longestBlock() {
        var single = SampleTimeline()
        single.work("09:00", "10:40", Self.myApp)
        single.away("10:40", "11:00")
        let plain = single.pass().blocks
        #expect(plain.map(\.span) == ["09:00–10:30", "10:30–10:40"])
        #expect(plain.first?.endReason == .maxLength)

        // One minute of Paper at 10:15 changes the workspace twice, far too
        // little to split; at 90 minutes the cut takes the larger distance, 10:15.
        var mixed = SampleTimeline()
        mixed.work("09:00", "10:15", Self.myApp)
        mixed.work("10:15", "10:16", Self.paper)
        mixed.work("10:16", "10:40", Self.myApp)
        mixed.away("10:40", "11:00")
        let cut = mixed.pass().blocks
        #expect(cut.map(\.span) == ["09:00–10:15", "10:15–10:40"])
        #expect(cut.first?.endReason == .maxLength)

        var watching = SampleTimeline()
        watching.add("09:00", "11:00", state: .passive, ActivityFixture.app("Zoom", appID: "us.zoom.xos"))
        watching.away("11:00", "11:20")
        #expect(watching.pass().blocks.map(\.span) == ["09:00–11:00"])
    }

    @Test("TRK-25 4 active, 6 idle, 8 active give one block; 20 active, 7 idle, 4 active merge into 31 minutes; 4 alone gives no block")
    func heldBlocks() {
        var reopened = SampleTimeline()
        reopened.work("09:00", "09:04", Self.myApp)
        reopened.away("09:04", "09:10")
        reopened.work("09:10", "09:18", Self.myApp)
        reopened.away("09:18", "09:40")
        #expect(reopened.pass().blocks.map(\.span) == ["09:00–09:18"])

        var merged = SampleTimeline()
        merged.work("09:00", "09:20", Self.myApp)
        merged.away("09:20", "09:27")
        merged.work("09:27", "09:31", Self.myApp)
        merged.away("09:31", "10:00")
        let blocks = merged.pass().blocks
        #expect(blocks.map(\.span) == ["09:00–09:31"])
        #expect(blocks.first?.activeSeconds == 24 * 60)

        var alone = SampleTimeline()
        alone.work("09:00", "09:04", Self.myApp)
        alone.away("09:04", "09:40")
        #expect(alone.pass().blocks.isEmpty)
    }
}
