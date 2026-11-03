// Background work: background items while the user is away, assigned to
// blocks and background stretches (spec_activity_tracking.md §2.3, §2.7,
// TRK-41, TRK-42).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct BackgroundWorkTests {
    static let mac = AgentHarness.device
    static let agent = SampleItem(context: "claude", subject: "refactor-parser", groupKey: "claude", app: "claude")
    static let work = SampleItem(context: "textedit", subject: "Notes", groupKey: "textedit", app: "com.apple.TextEdit")

    static func time(_ seconds: TimeInterval) -> Date {
        ManualClock.fixtureNow(in: AgentHarness.zone).addingTimeInterval(seconds)
    }

    /// Samples every 30 seconds over `[from, to)`: attentive on `work` or
    /// idle, with the coding agent busy when `busy`.
    static func samples(_ from: TimeInterval, _ to: TimeInterval, attentive: Bool, busy: Bool = true) -> [Sample] {
        stride(from: from, to: to, by: 30).map { seconds in
            Sample(
                time: time(seconds),
                state: attentive ? .active : .idle,
                primary: attentive ? work : nil,
                secondaries: busy ? [agent] : []
            )
        }
    }

    static func run(_ samples: [Sample], flush: Bool = true, until: Date? = nil) -> Timeline.Result {
        Timeline.run(
            TimelineInputs(mac: samples),
            settings: TrackerBlockSettings(),
            timeZone: AgentHarness.zone,
            mac: mac,
            flush: flush,
            until: until
        ).result
    }

    static func describe(_ items: [ActivityItem]) -> [String] {
        items.map { "\($0.context) \($0.subject) \($0.seconds)" }
    }

    @Test("TRK-41 a sample without attention records the busy coding agent as a background item")
    func awaySampleKeepsBackground() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.presence.reading = PresenceReading(idleSeconds: 600)
        let idle = await harness.engine.tick()
        #expect(idle.state == .idle)
        #expect(idle.primary == nil)
        #expect(idle.secondaries.contains { $0.context == "claude" && $0.subject == "refactor-parser" })
        harness.presence.reading = PresenceReading(locked: true)
        harness.advance(30)
        let locked = await harness.engine.tick()
        #expect(locked.state == .locked)
        #expect(locked.secondaries.contains { $0.context == "claude" })
    }

    @Test("TRK-42 background work after a block forms a background stretch from the block's end")
    func stretchAfterBlock() {
        let result = Self.run(Self.samples(0, 1200, attentive: true) + Self.samples(1200, 3600, attentive: false))
        let block = try? #require(result.closed.first?.block)
        #expect(result.closed.count == 1)
        #expect(block?.end == Self.time(1170))
        #expect(Self.describe(block?.background ?? []) == ["claude refactor-parser 1170"])
        #expect(result.closed.first?.contexts["claude"] == "claude")
        let stretch = try? #require(result.stretches.first?.stretch)
        #expect(result.stretches.count == 1)
        #expect(stretch?.start == Self.time(1170))
        #expect(stretch?.end == Self.time(3570))
        #expect(Self.describe(stretch?.items ?? []) == ["claude refactor-parser 2400"])
        #expect(stretch?.items.first?.device == Self.mac)
        #expect(result.stretches.first?.contexts == ["claude": "claude"])
    }

    @Test("TRK-42 background time during an absorbed idle gap counts for the block")
    func absorbedGapCounts() {
        let samples = Self.samples(0, 600, attentive: true) + Self.samples(600, 780, attentive: false)
            + Self.samples(780, 1380, attentive: true)
        let result = Self.run(samples)
        #expect(result.closed.count == 1)
        #expect(result.stretches.isEmpty)
        // 1350 s from the first sample to the last attentive one, all of it background.
        #expect(Self.describe(result.closed.first?.block.background ?? []) == ["claude refactor-parser 1350"])
        #expect(result.closed.first?.block.activeSeconds == 1140)
    }

    @Test("TRK-42 an item under 5 minutes forms no stretch; a gap of idle_close separates stretches")
    func stretchThresholds() {
        let short = Self.run(Self.samples(0, 240, attentive: false))
        #expect(short.closed.isEmpty)
        #expect(short.stretches.isEmpty)
        // The last sample before a gap credits up to 60 seconds, so the first run ends at 630.
        let split = Self.run(Self.samples(0, 600, attentive: false) + Self.samples(960, 1560, attentive: false))
        #expect(split.stretches.map { Self.describe($0.stretch.items) } == [["claude refactor-parser 630"], ["claude refactor-parser 570"]])
        let joined = Self.run(Self.samples(0, 600, attentive: false) + Self.samples(840, 1500, attentive: false))
        #expect(joined.stretches.count == 1)
    }

    @Test("TRK-42 a stretch still growing is not recorded, and none spans midnight or a block")
    func openStretchesAndBoundaries() {
        let away = Self.samples(0, 1200, attentive: false)
        #expect(Self.run(away, flush: false, until: Self.time(1230)).stretches.isEmpty)
        #expect(Self.run(away, flush: false, until: Self.time(1600)).stretches.count == 1)

        let around = Self.samples(0, 600, attentive: false) + Self.samples(600, 1500, attentive: true)
            + Self.samples(1500, 2100, attentive: false)
        let result = Self.run(around)
        #expect(result.stretches.count == 2)
        let block = try? #require(result.closed.first?.block)
        for stretch in result.stretches.map(\.stretch) {
            #expect(stretch.end <= (block?.start ?? .distantPast) || stretch.start >= (block?.end ?? .distantFuture))
        }

        let midnight = ActivityTimestamp.nextMidnight(after: Self.time(0), timeZone: AgentHarness.zone)
        let offset = midnight.timeIntervalSince(Self.time(0))
        let night = Self.run(Self.samples(offset - 600, offset + 600, attentive: false))
        #expect(night.stretches.count == 2)
        #expect(night.stretches.allSatisfy { $0.stretch.end <= midnight || $0.stretch.start >= midnight })
    }
}
