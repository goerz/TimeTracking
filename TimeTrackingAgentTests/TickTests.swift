// The local activity loop's tick and the agent's step queue
// (activity_tracking.md §2.4, §2.7, §5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TickTests {
    @Test("TRK-1 with no events, a 10 minute run inserts exactly 20 live Samples, one every 30 seconds")
    func tenMinutes() async throws {
        let harness = try AgentHarness()
        await harness.run(for: 600)
        // The run's last drain, at 10:10:00, already takes the next ten minutes' first Sample.
        let firstTen = harness.samples.filter { $0.time < harness.time(600) }
        #expect(firstTen.count == 20)
        #expect(firstTen.map(\.time) == stride(from: 0, to: 600, by: 30).map { harness.time($0) })
        #expect(firstTen.allSatisfy { $0.source == .live && $0.deviceID == AgentHarness.macID })
        #expect(harness.samples.count == 21)
    }

    @Test("TRK-2 lock, sleep, wake, a user switch, an app switch, and a tracker-event line each take a Sample at once, timed at the event")
    func eventsTakeASample() async throws {
        let between: TimeInterval = 287
        struct Trigger {
            var name: String
            var run: @MainActor (AgentHarness) async -> Void
            var check: @MainActor (Sample) -> Bool
        }
        let triggers = [
            Trigger(name: "lock", run: { await $0.event(.lock) }, check: { $0.state == .locked }),
            Trigger(name: "sleep", run: { await $0.event(.sleep) }, check: { $0.state == .asleep }),
            Trigger(name: "user switch", run: { await $0.event(.userSwitch) }, check: { $0.state == .otherUser }),
            Trigger(
                name: "app switch",
                run: { harness in
                    harness.frontmost("com.apple.mail", name: "Mail", title: "Inbox")
                    await harness.tick()
                },
                check: { $0.foreground?.app == "Mail" }
            ),
            Trigger(
                name: "tracker-event",
                run: { harness in
                    _ = await harness.agent.handle(line: "tmux after-select-pane")
                    await harness.drain()
                },
                check: { $0.state == .active }
            ),
        ]
        for trigger in triggers {
            let name = trigger.name
            let harness = try AgentHarness()
            harness.textEdit()
            await harness.run(for: 270)
            harness.clock.set(harness.time(between))
            await trigger.run(harness)
            let sample = try #require(harness.latest, "\(name)")
            #expect(sample.time == harness.time(between), "\(name)")
            #expect(trigger.check(sample), "\(name)")
            #expect(harness.liveSamples().count == 11, "\(name)")
        }

        // A wake after a sleep takes its own Sample, attentive again.
        let harness = try AgentHarness()
        harness.textEdit()
        await harness.run(for: 270)
        harness.clock.set(harness.time(between))
        await harness.event(.sleep)
        harness.clock.set(harness.time(between + 4))
        await harness.event(.wake)
        #expect(harness.latest?.time == harness.time(between + 4))
        #expect(harness.latest?.state == .active)
        #expect(harness.latest?.foreground?.app == "TextEdit")
    }

    @Test("TRK-2 a tracker-event line through the socket is answered at once and its Sample is taken well within a second")
    func socketLineTakesASample() async throws {
        let harness = try AgentHarness()
        await harness.tick()
        let url = harness.root.appending(path: "Group/tracker.sock", directoryHint: .notDirectory)
        let server = SocketServer(url: url) { [harness] line in await harness.agent.handle(line: line) }
        try server.start()
        defer { server.stop() }
        // The fastest of three round trips must be quick, so one delayed by
        // a loaded machine does not fail the test.
        let clock = ContinuousClock()
        var latencies: [Duration] = []
        for attempt in 1 ... 3 {
            harness.advance(7)
            let started = clock.now
            let reply = await Task.detached { TrackerSocketClient(socketURL: url, timeout: 5).send(line: "agent Stop") }.value
            await harness.drain()
            latencies.append(clock.now - started)
            #expect(reply == .success)
            #expect(harness.samples.count == 1 + attempt)
            #expect(harness.latest?.time == harness.time(TimeInterval(7 * attempt)))
        }
        #expect(try #require(latencies.min()) < .seconds(1), "\(latencies)")
    }

    @Test("TRK-42 two tick requests arriving while a step waits for ps start one tick, after that step; no two steps run at once")
    func requestsDuringAStepShareOneTick() async throws {
        let harness = try AgentHarness()
        harness.textEdit()
        var log: [String] = []
        var calls = 0
        let (gate, open) = AsyncStream<Void>.makeStream()
        harness.commands.beforeAnswer = {
            calls += 1
            let call = calls
            log.append("ps \(call) starts")
            if call == 1 {
                for await _ in gate {
                    break
                }
            }
            log.append("ps \(call) ends")
        }
        let queue = harness.agent.queue
        queue.requestTick()
        let first = Task { await queue.drain() }
        while log.isEmpty {
            await Task.yield()
        }
        // An app switch and a hook ask for ticks, and a request is queued, while the tick waits for `ps`.
        queue.requestTick()
        queue.requestTick()
        queue.enqueue("probe") { log.append("step") }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        #expect(log == ["ps 1 starts"])
        open.yield()
        await first.value
        #expect(log == ["ps 1 starts", "ps 1 ends", "ps 2 starts", "ps 2 ends", "step"])
        #expect(harness.liveSamples().count == 2)
    }

    @Test("TRK-61 while the rebuild loop works through a month of changed dates, ticks keep health.last_tick younger than 90 seconds")
    func ticksDuringARebuildBacklog() async throws {
        let harness = try AgentHarness()
        try harness.startedOn("2024-02-01")
        let rules = harness.agent.rules
        // Twenty minutes in TextEdit on each of the 30 dates before today.
        var samples: [Sample] = []
        for daysBack in 1 ... 30 {
            let start = harness.time(TimeInterval(-daysBack * 86_400))
            samples += stride(from: 0, to: 1200, by: 30).map { offset in
                Sample(
                    time: start + offset,
                    deviceID: AgentHarness.macID,
                    source: .live,
                    state: .active,
                    foreground: ActivityItem(app: "TextEdit", appID: "com.apple.TextEdit", window: "Notes")
                )
            }
        }
        try harness.agent.store.insert(samples, rules: rules)
        #expect(try harness.agent.store.meta(.changedDays)?.count ?? 0 >= 30)

        // Every read of the clock takes 2 seconds, so each pass takes time.
        harness.stepping.step = 2
        await harness.drain()
        harness.stepping.step = 0

        #expect(try harness.agent.store.meta(.changedDays)?.isEmpty ?? true)
        #expect(harness.agent.choice.log.days().count >= 30)
        let ticks = harness.liveSamples().map(\.time)
        #expect(ticks.count >= 5, "the backlog took \(harness.clock.now.timeIntervalSince(harness.time(0))) s")
        let gaps = zip(ticks.dropFirst(), ticks).map { $0.timeIntervalSince($1) }
        #expect(gaps.allSatisfy { $0 < 90 }, "\(gaps)")
        let lastTick = try #require(harness.currentState?.health.lastTick)
        #expect(harness.clock.now.timeIntervalSince(lastTick) < 90)
    }
}
