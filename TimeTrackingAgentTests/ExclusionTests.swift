// Exclusions applied before anything is written (activity_tracking.md
// §2.1 principle 5, §7.2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct ExclusionTests {
    /// Runs five minutes, closes the block with a lock, and returns everything written.
    private func output(_ harness: AgentHarness) async -> String {
        await harness.run(for: 300)
        harness.engine.handle(.lock, at: harness.clock.now)
        return harness.allOutput
    }

    private func safari(_ harness: AgentHarness, url: String, title: String) {
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value("normal\n\(url)\n\(title)")
        harness.history.safari = [
            (HistoryVisit(time: harness.time(0), browser: "safari", url: url, title: title), 0),
            (HistoryVisit(time: harness.time(100), browser: "safari", url: url, title: title), 0),
        ]
        harness.history.chromium = [HistoryVisit(time: harness.time(120), browser: "chrome", url: url, title: title)]
    }

    @Test("TRK-8 exclude_paths hides documents, Finder folders, cwds, and modified files under the path")
    func excludePaths() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_paths = [\"~/Documents/Medical\"]\n")
        harness.frontmost(
            "com.apple.Preview",
            name: "Preview",
            title: "scan.pdf",
            document: "file:///Users/alex/Documents/Medical/scan.pdf"
        )
        harness.engine.fileChanges.record(
            path: "/Users/alex/Documents/Medical/scan.pdf",
            at: harness.time(10),
            context: harness.engine.resolveContext()
        )
        let text = await output(harness)
        #expect(!text.contains("Medical"))
        #expect(!text.contains("scan.pdf"))
        #expect(harness.blocks.first?.items.first?.subject == "(private)")
        #expect(harness.blocks.first?.groupKey == "private")

        let finder = try AgentHarness(settings: "[privacy]\nexclude_paths = [\"~/Documents/Medical\"]\n")
        finder.frontmost("com.apple.finder", name: "Finder", title: "Medical")
        finder.scripts.results["com.apple.finder"] = .value("/Users/alex/Documents/Medical/")
        let finderText = await output(finder)
        #expect(!finderText.contains("Medical"))

        let terminal = try AgentHarness(settings: "[privacy]\nexclude_paths = [\"~/Documents/Code\"]\n")
        terminal.loadTerminalFixtures()
        terminal.frontmost("net.kovidgoyal.kitty", name: "kitty", pid: 800, title: "kitty")
        terminal.processes.cwd = [812: "/Users/alex/Documents/Code/parser"]
        terminal.processes.ttyInput = ["ttys021": terminal.time(-5)]
        let terminalText = await output(terminal)
        #expect(!terminalText.contains("Code/parser"))
    }

    @Test("TRK-8 exclude_keywords hides paths with a component starting with the keyword")
    func excludeKeywords() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_keywords = [\"sparsebundle\"]\n")
        harness.frontmost(
            "com.apple.TextEdit",
            name: "TextEdit",
            title: "x.txt",
            document: "/Users/alex/Documents/sparsebundle-archive/x.txt"
        )
        let text = await output(harness)
        #expect(!text.lowercased().contains("sparsebundle"))
        #expect(!text.contains("x.txt"))
    }

    @Test("TRK-8 exclude_tmux_sessions records tmux:(private) without window, cwd, or file")
    func excludeTmuxSessions() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_tmux_sessions = [\"paper\"]\n")
        harness.loadTerminalFixtures()
        harness.wezterm()
        let text = await output(harness)
        #expect(harness.samples().first?.primary?.context == "tmux:(private)")
        for secret in ["paper", "draft", "2026_Noise", "notes.tex"] {
            #expect(!text.contains(secret), "\(secret)")
        }
    }

    @Test("TRK-8 private_agent_paths keep only an agent session's name and status")
    func privateAgentPaths() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        let home = AgentHarness.fixture("claude/712.json").replacing("/Users/alex/Documents/Code/parser", with: "/Users/alex")
        harness.files.contents[AgentHarness.home + "/.claude/sessions/712.json"] = Data(home.utf8)
        harness.frontmost("net.kovidgoyal.kitty", name: "kitty", pid: 800, title: "kitty")
        let table = AgentHarness.fixture("ps/terminals.txt") + "  813   811 ttys021  S+   claude\n"
        harness.commands.set(ProcessTable.command, table.replacing("  812   811 ttys021  S+   /opt/homebrew/bin/nvim\n", with: ""))
        harness.files.folders[AgentHarness.home + "/.claude/sessions"] = ["813.json"]
        harness.files
            .contents[AgentHarness.home + "/.claude/sessions/813.json"] = Data(home.replacing("\"pid\":712", with: "\"pid\":813").utf8)
        harness.processes.alive = [813]
        harness.processes.cwd = [813: "/Users/alex"]
        harness.processes.ttyInput = ["ttys021": harness.time(-5)]
        let sample = await harness.engine.tick()
        #expect(sample.primary?.subject == "refactor-parser")
        #expect(sample.primary?.detail == "claude refactor-parser")
        #expect(sample.secondaries.contains { $0.context == "claude" && $0.subject == "refactor-parser" })
    }

    @Test("TRK-8 name_only_apps record the app name only")
    func nameOnlyApps() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.1password.1password", name: "1Password", title: "Bank login")
        let text = await output(harness)
        #expect(harness.samples().first?.primary == SampleItem(
            context: "1password",
            subject: "",
            groupKey: "1password",
            app: "com.1password.1password"
        ))
        #expect(!text.contains("Bank login"))
    }

    @Test("TRK-8 exclude_apps records nothing: the time is a gap, also in the Knowledge backfill")
    func excludeApps() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_apps = [\"com.apple.Notes\"]\n")
        harness.frontmost("com.apple.Notes", name: "Notes", title: "Diary")
        harness.knowledge.result = .data(
            apps: [KnowledgeAppInterval(start: harness.time(-3 * 3600), end: harness.time(-2 * 3600), bundleID: "com.apple.Notes")],
            web: [],
            displayOff: []
        )
        let text = await output(harness)
        #expect(harness.samples().allSatisfy { $0.primary == nil })
        #expect(harness.blocks.isEmpty)
        #expect(!text.contains("Diary"))
        #expect(!text.contains("com.apple.Notes"))
        #expect(!text.contains("notes"))
    }

    @Test("TRK-8 private_domains keep only the domain everywhere, also in the detail log's visits")
    func privateDomains() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nprivate_domains = [\"bank.example\"]\n")
        safari(harness, url: "https://www.bank.example/accounts/123", title: "Checking account")
        let text = await output(harness)
        #expect(harness.blocks.first?.items.first?.subject == "bank.example")
        #expect(!text.contains("accounts"))
        #expect(!text.contains("Checking account"))
        #expect(harness.details.first?.urls.allSatisfy { $0.url == "https://www.bank.example" } == true)
    }

    @Test("TRK-8 exclude_domains record <browser> (private) and no detail-log visits")
    func excludeDomains() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_domains = [\"health.example\"]\n")
        safari(harness, url: "https://portal.health.example/results", title: "Lab results")
        let text = await output(harness)
        #expect(harness.blocks.first?.items.first?.subject == "(private)")
        #expect(!text.contains("health.example"))
        #expect(!text.contains("Lab results"))
        #expect(harness.details.first?.urls.isEmpty == true)
    }

    @Test("TRK-8 exclude_title_keywords drop the title")
    func excludeTitleKeywords() async throws {
        let harness = try AgentHarness(settings: "[privacy]\nexclude_title_keywords = [\"confidential\"]\n")
        harness.frontmost("com.apple.TextEdit", name: "TextEdit", title: "Confidential plan")
        let text = await output(harness)
        #expect(!text.lowercased().contains("confidential"))
        #expect(harness.blocks.first?.items.first?.subject.isEmpty == true)
    }
}
