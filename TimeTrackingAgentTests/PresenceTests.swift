// Presence: the state of each live Sample, current.json's presence and
// liveness, settings applied from the next tick, and the Accessibility
// fallback (activity_tracking.md §3.4, §3.5, §4.4, §7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct PresenceTests {
    /// The Sample of a tick 30 seconds on with `reading`.
    private func sample(_ harness: AgentHarness, _ reading: PresenceReading) async throws -> Sample {
        harness.advance(30)
        harness.presence.reading = reading
        return try #require(await harness.tick())
    }

    @Test("TRK-3 states follow 3.4: idle_after, passive apps and domains up to passive_limit, never audio-only apps, display off is idle")
    func statesFollowPresence() async throws {
        let harness = try AgentHarness(settings: "[presence]\npassive_apps = [\"com.spotify.client\"]\n")
        harness.textEdit()
        let active = try await sample(harness, PresenceReading(idleSeconds: 119))
        #expect(active.state == .active)
        #expect(active.foreground?.app == "TextEdit")
        let idle = try await sample(harness, PresenceReading(idleSeconds: 121))
        #expect(idle.state == .idle)

        harness.frontmost("us.zoom.xos", name: "zoom.us", title: "Weekly sync")
        let meeting = try await sample(harness, PresenceReading(idleSeconds: 600))
        #expect(meeting.state == .passive)
        #expect(meeting.foreground?.window == "Weekly sync")
        #expect(try await sample(harness, PresenceReading(idleSeconds: 3 * 3600 - 1)).state == .passive)
        #expect(try await sample(harness, PresenceReading(idleSeconds: 3 * 3600 + 1)).state == .idle)
        #expect(try await sample(harness, PresenceReading(idleSeconds: 600, displayAsleep: true)).state == .idle)

        harness.safari("https://www.youtube.com/watch?v=1", title: "Talk")
        #expect(try await sample(harness, PresenceReading(idleSeconds: 600)).state == .passive)
        harness.safari("https://github.com/owner/repo", title: "Repo")
        #expect(try await sample(harness, PresenceReading(idleSeconds: 600)).state == .idle)

        // Listed in passive_apps, Spotify is still audio only.
        harness.frontmost("com.spotify.client", name: "Spotify", title: "Album")
        #expect(try await sample(harness, PresenceReading(idleSeconds: 600)).state == .idle)

        harness.textEdit()
        #expect(try await sample(harness, PresenceReading(idleSeconds: 5, displayAsleep: true)).state == .idle)
        #expect(try await sample(harness, PresenceReading(idleSeconds: 5, locked: true)).state == .locked)
        #expect(try await sample(harness, PresenceReading(idleSeconds: 5, otherUserOnConsole: true)).state == .otherUser)
        harness.advance(30)
        await harness.event(.sleep)
        #expect(harness.latest?.state == .asleep)

        let notAttentive = harness.liveSamples().filter { $0.state != .active && $0.state != .passive }
        #expect(notAttentive.count == 9)
        #expect(notAttentive.allSatisfy { $0.foreground == nil })
        #expect(harness.liveSamples().filter { $0.state == .active || $0.state == .passive }.allSatisfy { $0.foreground != nil })
    }

    @Test("TRK-32 after a lock notification 29 seconds before a tick, presence.since is the notification time")
    func lockSince() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 60)
        let lock = harness.time(61)
        harness.clock.set(lock)
        harness.agent.taker.handle(.lock, at: lock)
        harness.clock.set(harness.time(90))
        harness.presence.reading = PresenceReading(idleSeconds: 29, locked: true)
        await harness.drain()
        let state = try #require(harness.currentState)
        #expect(state.health.lastTick == harness.time(90))
        #expect(state.presence.state == .locked)
        #expect(abs(state.presence.since.timeIntervalSince(lock)) <= 1)
        #expect(harness.latest?.time == harness.time(90))
    }

    @Test("TRK-33 after the agent is killed, readers report it delayed at 90 seconds and not running at 2 minutes after its last tick")
    func livenessFromCurrentJSON() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 60)
        // The agent stops here: nothing writes current.json any more.
        let reader = FileActivityStore(folders: harness.folders, homeDirectory: AgentHarness.home)
        let state = try #require(await reader.currentState())
        let last = state.health.lastTick
        #expect(last == harness.time(60))
        func liveness(_ age: TimeInterval) -> TrackerLiveness {
            TrackerLiveness(registration: .enabled, state: state, now: last + age)
        }
        #expect(liveness(89) == .running(lastTick: last))
        #expect(liveness(90) == .delayed(lastTick: last))
        #expect(liveness(119) == .delayed(lastTick: last))
        #expect(liveness(120) == .notRunning(lastTick: last))
        #expect(TrackerLiveness(registration: .enabled, state: nil, now: last) == .notRunning(lastTick: nil))
    }

    @Test("TRK-38 changing idle_after changes the next Sample's state without a restart")
    func settingsApplyAtTheNextTick() async throws {
        let harness = try AgentHarness(settings: "[presence]\nidle_after = \"2m\"\n")
        harness.textEdit()
        let before = try await sample(harness, PresenceReading(idleSeconds: 90))
        #expect(before.state == .active)
        try harness.writeSettings("[presence]\nidle_after = \"60s\"\n")
        let after = try await sample(harness, PresenceReading(idleSeconds: 90))
        #expect(after.state == .idle)
        #expect(harness.agent.settings.presence.idleAfter == 60)
    }

    @Test("TRK-39 without Accessibility, Samples carry the app and appID only and window reports fallback")
    func withoutAccessibility() async throws {
        let harness = try AgentHarness()
        harness.focus.isTrusted = false
        harness.frontmost("com.apple.Preview", name: "Preview", title: "Secret.pdf", document: "/Users/alex/Documents/Secret.pdf")
        await harness.workThenLock(for: 720)
        let sample = try #require(harness.liveSamples().first)
        #expect(sample.foreground == ActivityItem(app: "Preview", appID: "com.apple.Preview"))
        let window = try #require(harness.health(.window))
        #expect(window.status == .fallback)
        #expect(window.reason == "Accessibility is off; only app names are recorded")
        #expect(harness.blocks(AgentHarness.today).count == 1)
        #expect(!harness.allOutput.contains("Secret"))
    }
}
