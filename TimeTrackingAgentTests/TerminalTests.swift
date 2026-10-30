// Terminal sources against the recorded fixtures of Fixtures/Agent/
// (spec_activity_tracking.md §2.2, §3.1).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TerminalTests {
    @Test("TRK-3 without a terminal adapter the fallback picks the tty with the most recent input and terminal reports fallback")
    func processTreeFallback() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.frontmost("net.kovidgoyal.kitty", name: "kitty", pid: 800, title: "kitty")
        harness.processes.cwd = [801: "/Users/alex/Documents/Papers/2026_Noise", 812: "/Users/alex/Documents/Code/parser"]
        harness.processes.arguments = [812: ["nvim", "src/main.rs"]]
        harness.files.existing.insert("/Users/alex/Documents/Code/parser/.git")
        harness.processes.ttyInput = ["ttys020": harness.time(-600), "ttys021": harness.time(-10)]
        let editing = try #require(await harness.engine.tick().primary)
        #expect(editing == SampleItem(
            context: "kitty",
            subject: "~/Documents/Code/parser",
            detail: "nvim main.rs",
            groupKey: "~/Documents/Code/parser",
            app: "net.kovidgoyal.kitty"
        ))
        #expect(harness.health("terminal")?.status == .fallback)
        #expect(harness.health("terminal")?.reason.isEmpty == false)

        harness.processes.ttyInput = ["ttys020": harness.time(-5), "ttys021": harness.time(-600)]
        harness.advance(30)
        let shell = try #require(await harness.engine.tick().primary)
        #expect(shell.subject == "~/Documents/Papers/2026_Noise")
        #expect(shell.detail.isEmpty)
        #expect(shell.groupKey == "~/Documents/Papers")
    }

    @Test("TRK-3 with the WezTerm adapter the focused pane's tmux session gives the item and terminal is active")
    func weztermAdapter() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.wezterm()
        let sample = await harness.engine.tick()
        #expect(sample.primary?.context == "tmux:paper")
        #expect(sample.tmuxTarget == "paper:0.0")
        #expect(harness.health("terminal")?.status == .active)
        #expect(harness.health("tmux")?.status == .active)
        // Secondaries: the busy agent session and the lab client with input 20 s ago; make runs in another pane.
        let background = sample.secondaries.map { "\($0.context) \($0.subject) \($0.detail)" }
        #expect(background.contains("claude refactor-parser "))
        #expect(background.contains("tmux:lab ~/Documents/Notebooks/qsl "))
        #expect(background.contains("tmux:tools ~/Documents/Code/parser make"))
        #expect(!background.contains { $0.hasPrefix("tmux:paper") })
    }

    @Test("TRK-4 a matching pane title yields a file only while the pane's command is that editor")
    func titleNeedsEditor() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.wezterm()
        let editing = try #require(await harness.engine.tick().primary)
        #expect(editing == SampleItem(
            context: "tmux:paper",
            subject: "draft",
            detail: "nvim notes.tex",
            groupKey: "tmux:paper",
            app: "com.github.wez.wezterm"
        ))
        #expect(harness.health("editor")?.status == .active)

        let stale = AgentHarness.fixture("tmux/list-panes.txt").replacing("1\tnvim\t/Users", with: "1\tzsh\t/Users")
        harness.commands.set(
            ["/opt/homebrew/bin/tmux", "-S", "/private/tmp/tmux-501/default", "list-panes", "-a", "-F", TmuxSnapshot.paneFormat],
            stale
        )
        harness.advance(30)
        let shell = try #require(await harness.engine.tick().primary)
        #expect(shell.detail.isEmpty)
        #expect(harness.sampleLines().last?.contains("notes.tex") == false)
    }

    @Test("TRK-5 an editor RPC silent for 200 ms falls through to arguments, then cwd, within 100 ms plus the timeout")
    func silentRPC() async throws {
        let harness = try AgentHarness(editorRPC: NeovimRPCClient())
        harness.loadTerminalFixtures()
        harness.wezterm()
        let untitled = AgentHarness.fixture("tmux/list-panes.txt").replacing(
            "\tnvim /Users/alex/Documents/Papers/2026_Noise/notes.tex",
            with: "\tnvim"
        )
        harness.commands.set(
            ["/opt/homebrew/bin/tmux", "-S", "/private/tmp/tmux-501/default", "list-panes", "-a", "-F", TmuxSnapshot.paneFormat],
            untitled
        )
        let folder = harness.root.appending(path: "nvim.alex", directoryHint: .isDirectory)
        let socket = folder.appending(path: "abc123/nvim.703.0", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        let silent = try UnixSocket.listen(at: socket)
        defer { close(silent) }
        harness.files.folders[folder.path] = ["abc123"]
        harness.files.existing.insert(socket.path)
        harness.processes.arguments = [702: ["nvim", "results.tex"]]

        let clock = ContinuousClock()
        let started = clock.now
        let fromArguments = try #require(await harness.engine.tick().primary)
        let elapsed = clock.now - started
        #expect(fromArguments.detail == "nvim results.tex")
        #expect(elapsed >= .milliseconds(190))
        #expect(elapsed < .milliseconds(300))
        #expect(harness.health("editor")?.status == .fallback)

        harness.processes.arguments = [:]
        harness.advance(30)
        let fromCwd = try #require(await harness.engine.tick().primary)
        #expect(fromCwd.detail == "nvim")
        #expect(fromCwd.subject == "draft")
    }

    @Test("TRK-6 a localhost:<port> tab gets the item and group key of the pane that registered the port")
    func notebookPort() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        let lab = AgentHarness.fixture("wezterm/list.json").replacing("/dev/ttys001", with: "/dev/ttys003")
        harness.commands.set(["/opt/homebrew/bin/wezterm", "cli", "list", "--format", "json"], lab)
        harness.commands.set(
            [PortRegistry.lsof, "-nP", "-a", "-p", "731,732", "-iTCP", "-sTCP:LISTEN", "-Fn"],
            AgentHarness.fixture("lsof/julia-listen.txt")
        )
        harness.wezterm()
        let pane = try #require(await harness.engine.tick().primary)
        #expect(pane.context == "tmux:lab")
        #expect(pane.groupKey == "tmux:lab")
        #expect(pane.detail == "julia")

        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-notebook.txt"))
        harness.advance(30)
        let tab = await harness.engine.tick()
        #expect(tab.primary == pane)
    }
}
