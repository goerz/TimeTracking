// LiveStatePublisher fed current.json files (data_and_sync.md §4.2, §9 item 34).

import Foundation
import Testing
import TimeTrackingCore

/// A store, a publisher at a manual clock, and current.json texts in Europe/Berlin.
private struct PublisherRig {
    let test: TestStore
    let publisher: LiveStatePublisher

    init() async throws {
        self.test = try await TestStore(now: "2024-03-14T10:00:00")
        self.publisher = LiveStatePublisher(store: test.store, deviceID: test.deviceID, deviceName: "MacBook", clock: test.clock)
    }

    /// Feeds one `current.json` text with the foreground in workspace
    /// `~/Code/<workspace>`; returns whether the publisher wrote.
    func feed(
        workspace: String,
        presence: String = "active",
        since: String = "2024-03-14T09:50:00",
        lastTick: String,
        knowledge: String = "off"
    ) async throws -> Bool {
        let item = #"{"a":"WezTerm","i":"com.github.wez.wezterm","ss":"draft","l":"~/Code/\#(workspace)","c":"nvim","#
            + #""ws":"~/Code/\#(workspace)"}"#
        let text = """
        {"format":1,"block":{"s":"2024-03-14T09:50:00+01:00","e":"2024-03-14T10:00:00+01:00","f":[{"d":"MacBook","t":600,\
        \(item.dropFirst())]},"foreground":\(item),\
        "presence":{"state":"\(presence)","since":"\(since)+01:00"},"health":{"last_tick":"\(lastTick)+01:00","version":"1.0","sources":[\
        {"id":"terminal","name":"Terminal","status":"active","reason":""},\
        {"id":"knowledge","name":"Knowledge store","status":"\(knowledge)","reason":""}]}}
        """
        return try await publisher.update(TrackerState.parse(Data(text.utf8)))
    }

    /// This Mac's entry in the store's `LiveState`.
    func published() async throws -> LiveState.MacActivity? {
        try await test.store.liveState().activity[test.deviceID.rawValue]
    }

    func advance(_ seconds: TimeInterval) {
        test.clock.advance(by: seconds)
    }
}

struct LiveStatePublisherTests {
    @Test("DATA-34 presence and health write at once; foreground at most every 30 s with the latest values; last_tick alone never")
    func publishingRules() async throws {
        let rig = try await PublisherRig()
        #expect(try await rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:00"))
        let first = try #require(try await rig.published())
        #expect(first.device == "MacBook")
        #expect(first.foreground?.workspace == "~/Code/a")
        #expect(first.groupKey == "~/Code/a")
        #expect(first.presence == "active")
        #expect(first.agentRunning)
        #expect(first.health == ["knowledge"])
        #expect(first.updatedAt == rig.test.clock.now)

        // Only last_tick advances: nothing is written.
        rig.advance(10)
        let outbox = try await rig.test.store.outboxCount()
        #expect(try await !rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:10"))
        #expect(try await rig.test.store.outboxCount() == outbox)

        // Primary changes inside the window wait for its end, then the latest is written.
        rig.advance(5)
        #expect(try await !rig.feed(workspace: "b", lastTick: "2024-03-14T10:00:15"))
        #expect(await rig.publisher.nextDue == rig.test.clock.now + 15)
        rig.advance(5)
        #expect(try await !rig.feed(workspace: "c", lastTick: "2024-03-14T10:00:20"))
        #expect(try await rig.published()?.groupKey == "~/Code/a")
        rig.advance(10)
        #expect(try await rig.feed(workspace: "c", lastTick: "2024-03-14T10:00:30"))
        #expect(try await rig.published()?.groupKey == "~/Code/c")
        #expect(try await rig.published()?.updatedAt == rig.test.clock.now)

        // Presence and health changes are written at once, inside the window too.
        rig.advance(5)
        #expect(try await rig.feed(workspace: "d", presence: "idle", since: "2024-03-14T10:00:33", lastTick: "2024-03-14T10:00:35"))
        #expect(try await rig.published()?.presence == "idle")
        #expect(try await rig.published()?.groupKey == "~/Code/d")
        rig.advance(5)
        #expect(try await rig.feed(workspace: "d", presence: "idle", lastTick: "2024-03-14T10:00:40", knowledge: "active"))
        #expect(try await rig.published()?.health.isEmpty == true)
    }

    @Test("DATA-34 agentRunning turns false within 30 seconds after last_tick turns 2 minutes old")
    func agentStops() async throws {
        let rig = try await PublisherRig()
        #expect(try await rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:00"))
        rig.advance(119)
        #expect(try await !rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:00"))
        #expect(try await rig.published()?.agentRunning == true)
        rig.advance(30)
        #expect(try await rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:00"))
        #expect(try await rig.published()?.agentRunning == false)
        #expect(try await !rig.feed(workspace: "a", lastTick: "2024-03-14T10:00:00"))

        // Without current.json the entry stays, not running.
        #expect(try await !rig.publisher.update(nil))
        #expect(try await rig.published()?.agentRunning == false)
    }
}
