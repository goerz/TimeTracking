// The tick and presence (spec_activity_tracking.md §2.1, §2.4 step 1, §2.5,
// §3.4, §4.4, §7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct PresenceTests {
    @Test("TRK-1 with no events a 10 minute run writes exactly 20 samples")
    func tenMinutesTwentySamples() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 600)
        #expect(harness.samples().count == 20)
        let times = harness.samples().map(\.time)
        #expect(times.first == harness.time(0))
        #expect(times.last == harness.time(570))
    }

    @Test("TRK-2 idle verdicts follow idle_after, passive apps and domains, passive_limit, and audio-only apps")
    func idleVerdicts() {
        let settings = TrackerPresenceSettings()
        let now = ManualClock.fixtureNow()
        var tracker = PresenceTracker(start: now)
        func verdict(_ reading: PresenceReading, passive: Bool = false) -> TrackerPresenceState {
            tracker.update(reading: reading, now: now, passiveCandidate: passive, settings: settings)
        }
        #expect(verdict(PresenceReading(idleSeconds: 119)) == .active)
        #expect(verdict(PresenceReading(idleSeconds: 121)) == .idle)
        #expect(verdict(PresenceReading(idleSeconds: 121), passive: true) == .passive)
        #expect(verdict(PresenceReading(idleSeconds: 3 * 3600 - 1), passive: true) == .passive)
        #expect(verdict(PresenceReading(idleSeconds: 3 * 3600 + 1), passive: true) == .idle)
        #expect(verdict(PresenceReading(idleSeconds: 5, displayAsleep: true), passive: true) == .idle)
        #expect(verdict(PresenceReading(idleSeconds: 5, locked: true)) == .locked)
        #expect(verdict(PresenceReading(idleSeconds: 5, otherUserOnConsole: true)) == .otherUser)
        #expect(PresenceTracker.isPassive(bundleID: "us.zoom.xos", domain: nil, settings: settings))
        #expect(PresenceTracker.isPassive(bundleID: "com.apple.ScreenSharing", domain: nil, settings: settings))
        #expect(PresenceTracker.isPassive(bundleID: "com.apple.Safari", domain: "www.youtube.com", settings: settings))
        #expect(!PresenceTracker.isPassive(bundleID: "com.apple.Safari", domain: "github.com", settings: settings))
        var listing = settings
        listing.passiveApps.append("com.spotify.client")
        #expect(!PresenceTracker.isPassive(bundleID: "com.spotify.client", domain: nil, settings: listing))
        #expect(!PresenceTracker.isPassive(bundleID: "com.apple.Music", domain: nil, settings: listing))
    }

    @Test("TRK-2 a passive meeting app keeps the samples passive without input; a plain app goes idle")
    func passiveSamples() async throws {
        let harness = try AgentHarness()
        harness.frontmost("us.zoom.xos", name: "zoom.us", title: "Weekly sync")
        harness.presence.reading = PresenceReading(idleSeconds: 600)
        #expect(await harness.engine.tick().state == .passive)
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        let sample = await harness.engine.tick()
        #expect(sample.state == .idle)
        #expect(sample.primary == nil)
    }

    @Test("TRK-10 lock, sleep, display sleep, and a user switch close the block at the event time")
    func eventsCloseBlocks() async throws {
        for event in [PresenceEvent.lock, .sleep, .displaySleep, .userSwitch] {
            let harness = try AgentHarness()
            await harness.run(for: 300)
            let eventTime = harness.time(287)
            harness.clock.set(eventTime)
            harness.engine.handle(event, at: eventTime)
            let blocks = harness.blocks
            #expect(blocks.count == 1, "\(event)")
            #expect(blocks.first?.end == eventTime, "\(event)")
            #expect(blocks.first?.activeSeconds == 287, "\(event)")
        }
    }

    @Test("TRK-18 after a lock notification 29 s before a tick, presence.since is the notification time")
    func lockSince() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 60)
        let lockTime = harness.time(61)
        harness.clock.set(lockTime)
        harness.engine.handle(.lock, at: lockTime)
        harness.clock.set(harness.time(90))
        harness.presence.reading = PresenceReading(idleSeconds: 29, locked: true)
        await harness.engine.tick()
        let state = try #require(harness.currentState)
        #expect(state.presence.state == .locked)
        #expect(abs(state.presence.since.timeIntervalSince(lockTime)) <= 1)
        #expect(state.health.lastTick == harness.time(90))
    }

    @Test("TRK-23 changing idle_after changes the next sample's verdict without a restart")
    func settingsReload() async throws {
        let harness = try AgentHarness(settings: "[presence]\nidle_after = \"2m\"\n")
        harness.presence.reading = PresenceReading(idleSeconds: 90)
        #expect(await harness.engine.tick().state == .active)
        let url = harness.folders.shared.appending(path: "settings.toml", directoryHint: .notDirectory)
        try "[presence]\nidle_after = \"1m\"\n".write(to: url, atomically: true, encoding: .utf8)
        harness.advance(30)
        #expect(await harness.engine.tick().state == .idle)
        #expect(harness.engine.settings.presence.idleAfter == 60)
    }

    @Test("TRK-25 without Accessibility samples carry the app name only and window reports fallback")
    func noAccessibility() async throws {
        let harness = try AgentHarness()
        harness.focus.isTrusted = false
        harness.frontmost("com.apple.Preview", name: "Preview", title: "Secret.pdf", document: "/Users/alex/Documents/Secret.pdf")
        let sample = await harness.engine.tick()
        #expect(sample.primary == SampleItem(context: "preview", subject: "", groupKey: "preview", app: "com.apple.Preview"))
        #expect(sample.title.isEmpty)
        #expect(harness.health("window")?.status == .fallback)
        #expect(!harness.allOutput.contains("Secret"))
    }
}
