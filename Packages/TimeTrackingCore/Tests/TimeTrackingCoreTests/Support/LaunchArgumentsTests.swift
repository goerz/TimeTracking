// Tests for LaunchArguments (spec_architecture.md §2.5).

import Foundation
import Testing
import TimeTrackingCore

struct LaunchArgumentsTests {
    @Test func parsesTheAppArguments() {
        let parsed = LaunchArguments(
            arguments: [
                "/path/App",
                "-UITesting",
                "YES",
                "-Fixture",
                "small",
                "-NSDocumentRevisionsDebugMode",
                "YES",
                "-ResetState",
                "true",
            ],
            environment: [:]
        )
        #expect(parsed.uiTesting)
        #expect(parsed.fixture == "small")
        #expect(parsed.resetState)
        #expect(!parsed.unregister)
    }

    @Test func noArgumentsMeansDefaults() {
        #expect(LaunchArguments(arguments: [], environment: [:]) == LaunchArguments())
        #expect(LaunchArguments(arguments: ["/path/App", "-UITesting", "NO"], environment: [:]) == LaunchArguments())
    }

    @Test func parsesTheAgentFlags() {
        let base = URL(filePath: "/tmp/work/", directoryHint: .isDirectory)
        let parsed = LaunchArguments(
            arguments: ["agent", "--record", "out", "--replay", "/abs/day.jsonl", "--unregister"],
            environment: [:],
            currentDirectory: base
        )
        #expect(parsed.recordFolder?.path == "/tmp/work/out")
        #expect(parsed.replayFile?.path == "/abs/day.jsonl")
        #expect(parsed.unregister)
    }

    @Test func readsTheEnvironment() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let parsed = LaunchArguments(
            arguments: ["timetracking"],
            environment: ["TIMETRACKING_STORE": "/tmp/s.sqlite", "TIMETRACKING_NOW": "2024-03-14T10:00:00"],
            timeZone: zone
        )
        #expect(parsed.storePath == "/tmp/s.sqlite")
        #expect(parsed.fixedNow == ManualClock.fixtureNow(in: zone))
        #expect(parsed.clock(honorFixedNow: true).now == ManualClock.fixtureNow(in: zone))
        #expect(parsed.clock(honorFixedNow: false) is SystemClock)
    }

    @Test(arguments: [
        ("2024-03-14T09:00:00Z", 1_710_406_800.0),
        ("2024-03-14T10:00:00+01:00", 1_710_406_800.0),
        ("2024-03-14T10:00", 1_710_406_800.0),
    ])
    func parsesInstants(text: String, expected: TimeInterval) throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(LaunchArguments.parseInstant(text, timeZone: zone) == Date(timeIntervalSince1970: expected))
    }

    @Test func rejectsMalformedInstants() {
        #expect(LaunchArguments.parseInstant("yesterday") == nil)
        #expect(LaunchArguments(arguments: [], environment: ["TIMETRACKING_NOW": "soon"]).fixedNow == nil)
    }
}
