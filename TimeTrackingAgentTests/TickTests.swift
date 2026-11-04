// Ticks requested by several sources at once (spec_activity_tracking.md §5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TickTests {
    @Test("TRK-47 ticks never overlap: requests during a tick share one follow-up tick, which samples after it")
    func ticksRunOneAtATime() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Notes")
        let before = harness.samples().count
        let (gate, open) = AsyncStream<Void>.makeStream()
        var held = 0
        harness.commands.beforeAnswer = {
            held += 1
            if held == 1 {
                for await _ in gate {
                    break
                }
            }
        }
        // The loop's tick waits inside `ps`; a socket event and an app
        // activation ask for ticks meanwhile.
        let first = Task { await harness.engine.tick() }
        while held == 0 {
            await Task.yield()
        }
        harness.advance(5)
        let second = Task { await harness.engine.tick() }
        let third = Task { await harness.engine.tick() }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(held == 1)
        open.yield()
        let samples = await [first.value, second.value, third.value]
        #expect(harness.samples().count == before + 2)
        #expect(samples[1].time == samples[2].time)
        #expect(samples[1].time >= samples[0].time)
    }
}
