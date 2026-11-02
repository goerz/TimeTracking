// Tests for TrackerState, the parsed current.json (spec_activity_tracking.md §4.4).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityTrackerStateTests {
    private static let example = """
    {"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00","a":1080,"dev":[["macbook",1080]],"rec":0,"g":"tmux:paper","gs":0.71,\
    "items":[["tmux:paper","draft","nvim (3 files)",1080,"macbook"]],"bg":[]},"primary":["tmux:paper","draft","nvim notes.tex"],\
    "presence":{"state":"active","since":"2026-10-28T09:10:00","last_input":"2026-10-28T09:44:27"},\
    "health":{"last_tick":"2026-10-28T09:44:30","version":"1.0 (42)","sources":[\
    {"id":"terminal","name":"Terminal","status":"active","reason":""},\
    {"id":"knowledge","name":"Knowledge store","status":"off","reason":"Full Disk Access not granted"}]}}
    """

    @Test func parsesTheSpecExampleInTheGivenZone() throws {
        let state = try TrackerState.parse(Data(Self.example.utf8), timeZone: ActivityFixture.newYork)
        #expect(state.device == "macbook")
        #expect(try state.openBlock?.start == (ActivityFixture.instant("2026-10-28T13:10:00Z")))
        #expect(state.primary == TrackerPrimaryItem(context: "tmux:paper", subject: "draft", detail: "nvim notes.tex"))
        #expect(state.presence.state == .active)
        #expect(try state.presence.lastInput == (ActivityFixture.instant("2026-10-28T13:44:27Z")))
        #expect(try state.health.lastTick == (ActivityFixture.instant("2026-10-28T13:44:30Z")))
        #expect(state.health.sources.map(\.status) == [.active, .off])
        #expect(state.health.sources.last?.reason == "Full Disk Access not granted")
    }

    @Test func anIdleStateHasNoBlockOrPrimary() throws {
        let text = """
        {"format":1,"dev":"macbook","block":null,"primary":null,"presence":{"state":"other_user","since":"2026-10-28T09:10:00"},\
        "health":{"last_tick":"2026-10-28T09:44:30Z","version":"1.0","sources":[]}}
        """
        let state = try TrackerState.parse(Data(text.utf8), timeZone: ActivityFixture.newYork)
        #expect(state.openBlock == nil)
        #expect(state.primary == nil)
        #expect(state.presence.state == .otherUser)
        #expect(try state.health.lastTick == (ActivityFixture.instant("2026-10-28T09:44:30Z")))
        #expect(state.activityBlock(timeZone: ActivityFixture.newYork) == nil)
    }

    @Test func theJSONTextRoundTrips() throws {
        let state = try TrackerState.parse(Data(Self.example.utf8), timeZone: ActivityFixture.newYork)
        let text = state.jsonText(timeZone: ActivityFixture.newYork)
        #expect(text.hasPrefix(#"{"format":1,"dev":"macbook","block":{"s":"2026-10-28T09:10:00""#))
        #expect(try TrackerState.parse(Data(text.utf8), timeZone: ActivityFixture.newYork) == state)
    }

    @Test func theTrackerRunsWhileTheLastTickIsYoungerThanTwoMinutesAndIsDelayedFrom90Seconds() throws {
        let state = try TrackerState.parse(Data(Self.example.utf8), timeZone: ActivityFixture.newYork)
        let tick = state.health.lastTick
        #expect(state.isRunning(at: tick))
        #expect(!state.isDelayed(at: tick + 89))
        #expect(state.isRunning(at: tick + 90))
        #expect(state.isDelayed(at: tick + 90))
        #expect(state.isRunning(at: tick + 119.9))
        #expect(!state.isRunning(at: tick + 120))
        #expect(!state.isDelayed(at: tick + 120))
    }

    @Test func aMalformedFileIsAnError() {
        #expect(throws: ActivityError.self) {
            try TrackerState.parse(Data("{\"format\":1}".utf8), timeZone: ActivityFixture.newYork)
        }
    }
}
