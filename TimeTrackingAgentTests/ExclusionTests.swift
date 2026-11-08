// Exclusions through every entry point of Samples: live Samples, app
// usage, and DeviceEvents, into the Samples, the date files, and
// current.json (activity_tracking.md §2.1 principle 4, §4.1, §7.2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct ExclusionTests {
    /// A setting of §7.2, what the agent sees, and what must never be written.
    struct Case {
        var name: String
        var settings: String
        var setup: @MainActor (AgentHarness) -> Void
        var forbidden: [String]
        var formsBlock = true
    }

    static let cases: [Case] = [
        Case(
            name: "exclude_paths",
            settings: "[privacy]\nexclude_paths = [\"~/Documents/Medical\"]\n",
            setup: { harness in
                harness.frontmost(
                    "com.apple.Preview",
                    name: "Preview",
                    title: "scan.pdf",
                    document: "/Users/alex/Documents/Medical/scan.pdf"
                )
            },
            forbidden: ["Medical", "scan.pdf"]
        ),
        Case(
            name: "exclude_keywords",
            settings: "[privacy]\nexclude_keywords = [\"sparsebundle\"]\n",
            setup: { $0.textEdit("x.txt", document: "/Users/alex/Documents/sparsebundle-archive/x.txt") },
            forbidden: ["sparsebundle", "x.txt"]
        ),
        Case(
            name: "exclude_tmux_sessions",
            settings: "[privacy]\nexclude_tmux_sessions = [\"paper\"]\n",
            setup: { harness in
                harness.loadTerminalFixtures()
                harness.focusWezTermPane(1)
            },
            forbidden: ["paper:", "draft", "2026_Noise", "notes.tex"]
        ),
        Case(
            name: "name_only_apps",
            settings: "",
            setup: { $0.frontmost("com.1password.1password", name: "1Password", title: "Bank login") },
            forbidden: ["Bank login"]
        ),
        Case(
            name: "exclude_apps",
            settings: "[privacy]\nexclude_apps = [\"com.apple.Notes\"]\n",
            setup: { $0.frontmost("com.apple.Notes", name: "Notes", title: "Diary") },
            forbidden: ["Diary", "com.apple.Notes"],
            formsBlock: false
        ),
        Case(
            name: "private_domains",
            settings: "[privacy]\nprivate_domains = [\"bank.example\"]\n",
            setup: { $0.safari("https://www.bank.example/accounts/123", title: "Checking account") },
            forbidden: ["accounts", "Checking account"]
        ),
        Case(
            name: "exclude_domains",
            settings: "[privacy]\nexclude_domains = [\"health.example\"]\n",
            setup: { $0.safari("https://portal.health.example/results", title: "Lab results") },
            forbidden: ["health.example", "Lab results"]
        ),
        Case(
            name: "exclude_title_keywords",
            settings: "[privacy]\nexclude_title_keywords = [\"confidential\"]\n",
            setup: { $0.textEdit("Confidential plan") },
            forbidden: ["onfidential"]
        ),
    ]

    @Test("TRK-11 each setting of 7.2 leaves no excluded path, domain, session, or title in the live Samples, date files, or current.json")
    func liveSamples() async throws {
        for test in Self.cases {
            let harness = try AgentHarness(settings: test.settings)
            test.setup(harness)
            await harness.run(for: 690)
            let current = harness.currentStateText
            await harness.lockAndWait()
            let output = harness.allOutput + current
            for secret in test.forbidden {
                #expect(!output.contains(secret), "\(test.name): \(secret)")
            }
            #expect(harness.blocks(AgentHarness.today).count == (test.formsBlock ? 1 : 0), "\(test.name)")
        }
    }

    @Test(
        "TRK-11 private_agent_paths keeps only the app, appID, and session of a coding agent in that folder, in front and in the background"
    )
    func privateAgentPaths() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nprivate_agent_paths = [\"~/Documents/Code/parser\"]\n")
        harness.loadTerminalFixtures()
        harness.focusWezTermPane(0)
        await harness.run(for: 690)
        let current = try #require(harness.currentState)
        await harness.lockAndWait()
        let foreground = ActivityItem(app: "WezTerm", appID: "com.github.wez.wezterm", session: "refactor-parser")
        let agent = ActivityItem(app: "Claude Code", appID: "claude", session: "refactor-parser")
        let attentive = harness.liveSamples().filter(\.isAttentive)
        #expect(!attentive.isEmpty)
        #expect(attentive.allSatisfy { $0.foreground == foreground })
        #expect(harness.liveSamples().allSatisfy { $0.background.filter { $0.app == "Claude Code" } == [agent] })
        #expect(current.foreground == foreground)
        let block = try #require(harness.blocks(AgentHarness.today).first)
        #expect(block.foreground.map(\.item) == [foreground])
        #expect(block.background.filter { $0.item.app == "Claude Code" }.map(\.item) == [agent])
    }

    @Test("TRK-11 exclude_apps applies to the Samples rebuilt from app usage")
    func appUsage() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_apps = [\"com.apple.Notes\"]\n")
        harness.textEdit()
        await harness.run(for: 300)
        harness.knowledge.result = .data(
            apps: [
                KnowledgeAppInterval(start: harness.time(1200), end: harness.time(2400), bundleID: "com.apple.Notes"),
                KnowledgeAppInterval(start: harness.time(2700), end: harness.time(3900), bundleID: "com.apple.mail"),
            ],
            web: [],
            displayOff: []
        )
        harness.clock.set(harness.time(7200))
        try harness.restart()
        await harness.drain()
        try harness.agent.fillGaps()
        await harness.drain()
        let usage = harness.samples.filter { $0.source == .appUsage }
        // Notes' time is a gap: its Samples have no Item.
        #expect(usage.contains { $0.foreground?.appID == "com.apple.mail" })
        #expect(usage.allSatisfy { $0.foreground == nil || $0.foreground?.appID == "com.apple.mail" })
        #expect(!harness.allOutput.contains("com.apple.Notes"))
        #expect(harness.blocks(AgentHarness.today).count == 1)
    }

    @Test("TRK-11 exclude_domains and private_domains apply to the Samples converted from DeviceEvents")
    func deviceEvents() async throws {
        let harness =
            try AgentHarness(settings: "[privacy]\nexclude_domains = [\"health.example\"]\nprivate_domains = [\"bank.example\"]\n")
        let server = InMemoryDeviceEventServer()
        harness.agent.deviceEvents = server.source
        func tabs(_ label: String, from start: String) -> [DeviceEvent] {
            (0 ... 12).map { minute in
                DeviceEvent(
                    deviceID: DeviceTests.phone,
                    time: AgentHarness.instant(start) + TimeInterval(60 * minute),
                    source: .webext,
                    label: label,
                    kind: "tab",
                    sequence: minute,
                    utcOffset: AgentHarness.zone.secondsFromGMT(for: harness.time(0)),
                    deviceName: "iPhone"
                )
            }
        }
        try await server.upload(
            tabs("portal.health.example/results", from: "2024-03-14T08:00:00") + tabs(
                "www.bank.example/accounts/123",
                from: "2024-03-14T08:30:00"
            )
        )
        await harness.agent.fetchDeviceEvents()
        await harness.drain()
        let phone = harness.samples.filter { $0.deviceID == DeviceTests.phone }
        #expect(Set(phone.compactMap(\.foreground?.location)) == ["(private)", "https://bank.example"])
        #expect(harness.blocks(AgentHarness.today).count == 2)
        for secret in ["health.example", "accounts"] {
            #expect(!harness.allOutput.contains(secret), "\(secret)")
        }
    }
}
