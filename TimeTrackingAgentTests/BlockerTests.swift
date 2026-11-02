// The Blocker: closing, splitting, and summarizing blocks
// (spec_activity_tracking.md §2.6, §2.7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct BlockerTests {
    let zone = AgentHarness.zone
    var start: Date {
        ManualClock.fixtureNow(in: zone)
    }

    static func item(_ key: String) -> SampleItem {
        SampleItem(context: key, subject: "subject \(key)", groupKey: key, app: "app.\(key)")
    }

    /// Samples every 30 s: each part is a key (`nil` for idle) and a duration.
    static func stream(
        _ parts: [(String?, TimeInterval)],
        from start: Date,
        state: TrackerPresenceState = .active
    ) -> [Sample] {
        var time = start
        var result: [Sample] = []
        for (key, duration) in parts {
            let end = time.addingTimeInterval(duration)
            while time < end {
                if let key {
                    result.append(Sample(time: time, state: state, primary: item(key)))
                } else {
                    result.append(Sample(time: time, state: .idle))
                }
                time = time.addingTimeInterval(30)
            }
        }
        return result
    }

    func run(_ samples: [Sample], settings: TrackerBlockSettings = TrackerBlockSettings(), flush: Bool = true) -> [ClosedBlock] {
        var blocker = Blocker(settings: settings, timeZone: zone, device: "macbook")
        var closed = samples.flatMap { blocker.add($0) }
        if flush {
            closed += blocker.flush()
        }
        return closed
    }

    @Test("TRK-9 a block closes at its last active sample after idle_close; shorter idle gaps are not counted")
    func idleClose() {
        let samples = Self.stream([("a", 600), (nil, 180), ("a", 300), (nil, 390)], from: start)
        var blocker = Blocker(settings: TrackerBlockSettings(), timeZone: zone, device: "macbook")
        var closedAt: Date?
        var closed: [ClosedBlock] = []
        for sample in samples {
            let result = blocker.add(sample)
            if !result.isEmpty, closedAt == nil {
                closedAt = sample.time
            }
            closed += result
        }
        let block = try? #require(closed.first?.block)
        #expect(closed.count == 1)
        #expect(block?.start == start)
        #expect(block?.end == start.addingTimeInterval(1050))
        #expect(block?.activeSeconds == 840)
        #expect(closedAt == start.addingTimeInterval(1350))
    }

    @Test("TRK-11 a block open at midnight ends at 00:00:00 and no block of any src spans two dates")
    func midnight() throws {
        let evening = try #require(ActivityTimestamp.date("2024-03-14T23:50:00", timeZone: zone))
        let midnight = try #require(ActivityTimestamp.date("2024-03-15T00:00:00", timeZone: zone))
        for source in [ActivitySource.live, .knowledge, .device] {
            var blocker = Blocker(settings: TrackerBlockSettings(), timeZone: zone, device: "macbook", source: source)
            let samples = Self.stream([("a", 1260)], from: evening)
            let closed = samples.flatMap { blocker.add($0) } + blocker.flush()
            #expect(closed.count == 2)
            #expect(closed.first?.block.end == midnight)
            #expect(closed.first?.block.activeSeconds == 600)
            #expect(closed.last?.block.start == midnight.addingTimeInterval(0))
            for block in closed.map(\.block) {
                let last = block.end.addingTimeInterval(block.end > block.start ? -1 : 0)
                #expect(ActivityTimestamp.day(block.start, timeZone: zone) == ActivityTimestamp.day(last, timeZone: zone))
                #expect(block.source == source)
            }
        }
    }

    @Test("TRK-12 15 minutes on one key then 15 on another split at the change; alternating every 2 minutes never splits")
    func splitTest() {
        let change = start.addingTimeInterval(900)
        let split = run(Self.stream([("a", 900), ("b", 900)], from: start), flush: false)
        #expect(split.count == 1)
        let end = split.first?.block.end ?? .distantPast
        #expect(abs(end.timeIntervalSince(change)) <= 30)
        #expect(split.first?.block.groupKey == "a")

        var parts: [(String?, TimeInterval)] = []
        for index in 0 ..< 20 {
            parts.append((index.isMultiple(of: 2) ? "a" : "b", 120))
        }
        #expect(run(Self.stream(parts, from: start), flush: false).isEmpty)
    }

    @Test(
        "TRK-13 max_block closes at the best change point of the last 30 minutes, else at the tick; passive ones run to max_passive_block"
    )
    func maxBlock() {
        let single = run(Self.stream([("a", 5500)], from: start), flush: false)
        #expect(single.count == 1)
        #expect(single.first?.block.end == start.addingTimeInterval(5400))

        let mixed = run(Self.stream([("a", 4500), ("b", 300), ("a", 900)], from: start), flush: false)
        #expect(mixed.count == 1)
        #expect(mixed.first?.block.end == start.addingTimeInterval(4500))

        let passive = run(Self.stream([("a", 3 * 3600 + 60)], from: start, state: .passive), flush: false)
        #expect(passive.count == 1)
        #expect(passive.first?.block.end == start.addingTimeInterval(3 * 3600))
    }

    @Test("TRK-39 a short block continues into attention within its merge window")
    func shortBlockContinues() {
        let closed = run(Self.stream([("a", 240), (nil, 360), ("b", 480)], from: start))
        #expect(closed.count == 1)
        #expect(closed.first?.block.start == start)
        #expect(closed.first?.block.end == start.addingTimeInterval(1050))
        #expect(closed.first?.block.activeSeconds == 660)
        #expect(closed.first?.replacesPrevious == false)
    }

    @Test("TRK-39 a short block after the window merges into the previous block, which it replaces")
    func shortBlockMergesBack() {
        let parts: [(String?, TimeInterval)] = [("a", 1200), (nil, 420), ("b", 240), (nil, 900)]
        for flush in [false, true] {
            let closed = run(Self.stream(parts, from: start), flush: flush)
            #expect(closed.count == 2)
            #expect(closed.first?.block.end == start.addingTimeInterval(1170))
            let merged = closed.last
            #expect(merged?.replacesPrevious == true)
            #expect(merged?.block.id == closed.first?.block.id)
            #expect(merged?.block.end == start.addingTimeInterval(1830))
            #expect(merged?.block.activeSeconds == 1380)
            #expect(Set(merged?.detailItems.map(\.context) ?? []) == ["a", "b"])
            let resolved = ClosedBlock.resolved(closed)
            #expect(resolved.count == 1)
            #expect(resolved.first?.block == merged?.block)
            #expect(resolved.first?.replacesPrevious == false)
        }
    }

    @Test("TRK-39 a short block without a neighbor in its window is dropped")
    func shortBlockDropped() {
        #expect(run(Self.stream([("a", 240)], from: start)).isEmpty)
        #expect(run(Self.stream([("a", 240), (nil, 900)], from: start), flush: false).isEmpty)
        // 20 minutes, 10 away, 4 minutes: the gap exceeds idle_close plus the short block.
        let closed = run(Self.stream([("a", 1200), (nil, 600), ("b", 240), (nil, 900)], from: start))
        #expect(closed.count == 1)
        #expect(closed.first?.block.end == start.addingTimeInterval(1170))
        // Merging must not exceed max_block.
        let long = run(Self.stream([("a", 5300), (nil, 420), ("b", 240), (nil, 900)], from: start))
        #expect(long.map(\.replacesPrevious) == [false])
    }

    @Test("TRK-39 a short block is never merged across midnight")
    func shortBlockMidnight() throws {
        let evening = try #require(ActivityTimestamp.date("2024-03-14T23:30:00", timeZone: zone))
        let midnight = try #require(ActivityTimestamp.date("2024-03-15T00:00:00", timeZone: zone))
        // 20 minutes, 6 away, 3 before midnight, then activity right after it.
        let closed = run(Self.stream([("a", 1200), (nil, 360), ("b", 180), (nil, 60), ("c", 900)], from: evening))
        #expect(closed.map(\.block.start) == [evening, evening, midnight])
        #expect(closed.map(\.replacesPrevious) == [false, true, false])
        for block in closed.map(\.block) {
            #expect(block.end <= midnight || block.start >= midnight)
        }
        // A short block right after midnight does not reach back.
        let late = run(Self.stream([("a", 1500), (nil, 180), ("b", 240)], from: evening))
        #expect(late.count == 1)
        #expect(late.first?.block.end ?? .distantFuture <= midnight)
    }

    @Test("TRK-14 summaries merge, drop, keep, order, cap, and append background per 2.7; a never exceeds e minus s")
    func summary() throws {
        func segment(_ minute: Int, _ seconds: Int, _ key: String, _ subject: String, _ detail: String) -> Blocker.Segment {
            Blocker.Segment(
                start: start.addingTimeInterval(TimeInterval(minute * 60)),
                seconds: seconds,
                item: SampleItem(context: key, subject: subject, detail: detail, groupKey: key, app: key),
                passive: false
            )
        }
        let segments = [
            segment(0, 300, "tmux:paper", "draft", "nvim a.tex"),
            segment(5, 300, "tmux:paper", "draft", "nvim b.tex"),
            segment(10, 300, "tmux:paper", "draft", "nvim c.tex"),
            segment(15, 300, "tmux:paper", "draft", "nvim d.tex"),
            segment(20, 50, "mail", "Inbox", ""),
            segment(21, 200, "safari", "github.com/owner/repo", "pull/1"),
            segment(25, 190, "notes", "List", ""),
            segment(29, 70, "chat", "Team", "general"),
        ]
        let background = [
            Blocker.Segment(
                start: start,
                seconds: 400,
                item: SampleItem(context: "claude", subject: "refactor", groupKey: "claude", app: "claude"),
                passive: false
            ),
            Blocker.Segment(
                start: start,
                seconds: 200,
                item: SampleItem(context: "tmux:tools", subject: "x", groupKey: "tmux:tools", app: "tmux"),
                passive: false
            ),
        ]
        var settings = TrackerBlockSettings()
        settings.summaryMinShare = 0.1
        let summary = BlockSummary(segments: segments, background: background, settings: settings)
        #expect(summary.activeSeconds == 1710)
        #expect(summary.detailItems.count == 8)
        #expect(summary.items.map(\.context) == ["tmux:paper", "safari", "notes"])
        #expect(summary.items.first?.detail == "nvim (4 files)")
        #expect(summary.items.first?.seconds == 1200)
        #expect(summary.background.map(\.context) == ["claude"])
        #expect(summary.groupKey == "tmux:paper")
        #expect(summary.groupShare == 0.7)
        settings.summaryLines = 2
        #expect(BlockSummary(segments: segments, background: [], settings: settings).items.count == 2)

        let fixture = AgentHarness.fixtureURL("samples/2024-03-14.jsonl")
        let produced = try Replay.blockLog(samplesText: String(contentsOf: fixture, encoding: .utf8), settings: .defaults)
        for block in BlockLogFile(data: Data(produced.utf8)).blocks {
            #expect(TimeInterval(block.activeSeconds) <= block.end.timeIntervalSince(block.start))
            #expect(block.activeSeconds >= block.items.reduce(0) { $0 + $1.seconds })
        }
    }
}
