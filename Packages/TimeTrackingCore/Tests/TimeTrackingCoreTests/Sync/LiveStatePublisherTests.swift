// LiveStatePublisher fed current.json files (spec_data_and_sync.md §4.2, §9 item 34).

import Foundation
import Testing
import TimeTrackingCore

/// A store, a publisher at a manual clock, and current.json texts in Europe/Berlin.
private struct PublisherRig {
    let test: TestStore
    let publisher: LiveStatePublisher

    init() async throws {
        self.test = try await TestStore(now: "2024-03-14T10:00:00")
        self.publisher = LiveStatePublisher(store: test.store, deviceID: test.deviceID, clock: test.clock)
    }

    /// Feeds one `current.json` text; returns whether the publisher wrote.
    func feed(
        primary: String,
        presence: String = "active",
        since: String = "2024-03-14T09:50:00",
        lastTick: String,
        knowledge: String = "off"
    ) async throws -> Bool {
        let text = """
        {"format":1,"dev":"macbook","block":{"s":"2024-03-14T09:50:00","a":600,"dev":[["macbook",600]],"rec":0,\
        "g":"tmux:\(primary)","gs":0.8,\
        "items":[["tmux:\(primary)","draft","nvim",600,"macbook"]],"bg":[]},"primary":["tmux:\(primary)","draft","nvim"],\
        "presence":{"state":"\(presence)","since":"\(since)"},"health":{"last_tick":"\(lastTick)","version":"1.0","sources":[\
        {"id":"terminal","name":"Terminal","status":"active","reason":""},\
        {"id":"knowledge","name":"Knowledge store","status":"\(knowledge)","reason":""}]}}
        """
        return try await publisher.update(TrackerState.parse(Data(text.utf8), timeZone: test.zone))
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
    @Test("DATA-34 presence and health write at once; primary at most every 30 s with the latest values; last_tick alone never")
    func publishingRules() async throws {
        let rig = try await PublisherRig()
        #expect(try await rig.feed(primary: "a", lastTick: "2024-03-14T10:00:00"))
        let first = try #require(try await rig.published())
        #expect(first.device == "macbook")
        #expect(first.primary == TrackerPrimaryItem(context: "tmux:a", subject: "draft", detail: "nvim"))
        #expect(first.groupKey == "tmux:a")
        #expect(first.presence == "active")
        #expect(first.agentRunning)
        #expect(first.health == ["knowledge"])
        #expect(first.updatedAt == rig.test.clock.now)

        // Only last_tick advances: nothing is written.
        rig.advance(10)
        let outbox = try await rig.test.store.outboxCount()
        #expect(try await !rig.feed(primary: "a", lastTick: "2024-03-14T10:00:10"))
        #expect(try await rig.test.store.outboxCount() == outbox)

        // Primary changes inside the window wait for its end, then the latest is written.
        rig.advance(5)
        #expect(try await !rig.feed(primary: "b", lastTick: "2024-03-14T10:00:15"))
        #expect(await rig.publisher.nextDue == rig.test.clock.now + 15)
        rig.advance(5)
        #expect(try await !rig.feed(primary: "c", lastTick: "2024-03-14T10:00:20"))
        #expect(try await rig.published()?.groupKey == "tmux:a")
        rig.advance(10)
        #expect(try await rig.feed(primary: "c", lastTick: "2024-03-14T10:00:30"))
        #expect(try await rig.published()?.groupKey == "tmux:c")
        #expect(try await rig.published()?.updatedAt == rig.test.clock.now)

        // Presence and health changes are written at once, inside the window too.
        rig.advance(5)
        #expect(try await rig.feed(primary: "d", presence: "idle", since: "2024-03-14T10:00:33", lastTick: "2024-03-14T10:00:35"))
        #expect(try await rig.published()?.presence == "idle")
        #expect(try await rig.published()?.groupKey == "tmux:d")
        rig.advance(5)
        #expect(try await rig.feed(primary: "d", presence: "idle", lastTick: "2024-03-14T10:00:40", knowledge: "active"))
        #expect(try await rig.published()?.health.isEmpty == true)
    }

    @Test("DATA-34 agentRunning turns false within 30 seconds after last_tick turns 2 minutes old")
    func agentStops() async throws {
        let rig = try await PublisherRig()
        #expect(try await rig.feed(primary: "a", lastTick: "2024-03-14T10:00:00"))
        rig.advance(119)
        #expect(try await !rig.feed(primary: "a", lastTick: "2024-03-14T10:00:00"))
        #expect(try await rig.published()?.agentRunning == true)
        rig.advance(30)
        #expect(try await rig.feed(primary: "a", lastTick: "2024-03-14T10:00:00"))
        #expect(try await rig.published()?.agentRunning == false)
        #expect(try await !rig.feed(primary: "a", lastTick: "2024-03-14T10:00:00"))

        // Without current.json the entry stays, not running.
        #expect(try await !rig.publisher.update(nil))
        #expect(try await rig.published()?.agentRunning == false)
    }
}
