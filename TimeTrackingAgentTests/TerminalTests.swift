// The terminal source against the recorded fixtures of Fixtures/Agent/:
// the focused pane, editors, coding agents, background work, and remote
// shells (activity_tracking.md §2.3, §3.1, §3.5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct TerminalTests {
    @Test("TRK-4 without a terminal adapter, the fallback picks the tty with the most recent input and terminal reports fallback")
    func processTreeFallback() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.frontmost("net.kovidgoyal.kitty", name: "kitty", pid: 800, title: "kitty")
        harness.processes.cwd = [801: "/Users/alex/Documents/Papers/2026_Noise", 812: "/Users/alex/Documents/Code/parser"]
        harness.processes.arguments = [812: ["nvim", "src/main.rs"]]
        harness.files.existing.insert("/Users/alex/Documents/Code/parser/.git")
        harness.processes.ttyInput = ["ttys020": harness.time(-600), "ttys021": harness.time(-10)]
        let editing = try #require(await harness.tick()?.foreground)
        #expect(editing == ActivityItem(
            app: "kitty",
            appID: "net.kovidgoyal.kitty",
            window: "kitty",
            location: "~/Documents/Code/parser",
            documents: ["~/Documents/Code/parser/src/main.rs"],
            command: "nvim src/main.rs",
            workspace: "~/Documents/Code/parser"
        ))
        let terminal = try #require(harness.health(.terminal))
        #expect(terminal.status == .fallback)
        #expect(terminal.reason == "kitty can't report its front tab; the tab is guessed from recent activity")

        harness.processes.ttyInput = ["ttys020": harness.time(25), "ttys021": harness.time(-600)]
        harness.advance(30)
        let shell = try #require(await harness.tick()?.foreground)
        #expect(shell.location == "~/Documents/Papers/2026_Noise")
        #expect(shell.command == "zsh")
        #expect(shell.documents.isEmpty)
    }

    @Test("TRK-5 a matching pane title yields a document only while the pane's command is that editor")
    func titleNeedsTheEditor() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.wezterm()
        let editing = try #require(await harness.tick()?.foreground)
        #expect(editing.session == "paper:0.0")
        #expect(editing.command == "nvim")
        #expect(editing.documents == ["~/Documents/Papers/2026_Noise/notes.tex"])
        #expect(harness.health(.editor)?.status == .active)

        // Neovim quit; the shell left the title as it was.
        let table = AgentHarness.fixture("ps/terminals.txt")
            .replacing("  702   701 ttys010  S+   nvim\n", with: "")
            .replacing("  703   702 ttys010  S+   nvim\n", with: "")
        harness.commands.set(ProcessTable.command, table)
        harness.editTmuxPanes([("1\tnvim\t/Users", "1\tzsh\t/Users")])
        harness.advance(30)
        let shell = try #require(await harness.tick()?.foreground)
        #expect(shell.command == "zsh")
        #expect(shell.documents.isEmpty)
        #expect(harness.sampleText.split(separator: "\n").last?.contains("notes.tex") == false)
    }

    @Test("TRK-6 an editor RPC silent for 200 ms falls through to the process arguments within 100 ms plus the timeout")
    func silentRPC() async throws {
        let harness = try AgentHarness(editorRPC: NeovimRPCClient())
        harness.loadTerminalFixtures()
        harness.wezterm()
        harness.editTmuxPanes([("\tnvim /Users/alex/Documents/Papers/2026_Noise/notes.tex", "\tnvim")])
        let folder = harness.root.appending(path: "nvim.alex", directoryHint: .isDirectory)
        let socket = folder.appending(path: "abc123/nvim.703.0", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        let silent = try UnixSocket.listen(at: socket)
        defer { close(silent) }
        harness.files.folders[folder.path] = ["abc123"]
        harness.files.existing.insert(socket.path)
        harness.processes.arguments = [702: ["nvim", "results.tex"]]

        // Every tick waits out the 200 ms timeout before falling through. A
        // loaded machine can delay any one tick, so the 100 ms margin must
        // hold for the fastest of three.
        #expect(TerminalObserver.rpcTimeout == 0.2)
        let clock = ContinuousClock()
        var elapsed: [Duration] = []
        for attempt in 0 ..< 3 {
            if attempt > 0 {
                // A silent socket is asked again after the backoff.
                harness.advance(TerminalObserver.silentBackoff)
            }
            let started = clock.now
            let item = try #require(await harness.tick()?.foreground)
            elapsed.append(clock.now - started)
            #expect(item.documents == ["~/Documents/Papers/2026_Noise/results.tex"])
        }
        #expect(elapsed.allSatisfy { $0 >= .milliseconds(190) }, "\(elapsed)")
        #expect(try #require(elapsed.min()) < .milliseconds(300), "\(elapsed)")
        #expect(harness.health(.editor)?.status == .fallback)
    }

    @Test("TRK-7 a Claude Code session inside tmux gives its title as the session; a tmux pane without one gives session:window.pane")
    func sessions() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.focusWezTermPane(0)
        let agent = try #require(await harness.tick()?.foreground)
        #expect(agent.session == "refactor-parser")
        #expect(agent.location == "~/Documents/Code/parser")
        #expect(agent.command == "claude")

        harness.focusWezTermPane(1)
        harness.advance(1)
        let pane = try #require(await harness.tick()?.foreground)
        #expect(pane.session == "paper:0.0")
        #expect(harness.health(.terminal)?.status == .active)
        #expect(harness.health(.tmux)?.status == .active)
    }

    @Test(
        "TRK-10 idle, locked, and otherUser Samples list busy agents, tmux sessions with recent input, and jobs; asleep ones none"
    )
    func backgroundItems() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        harness.textEdit()
        let readings = [
            PresenceReading(idleSeconds: 600),
            PresenceReading(idleSeconds: 5, locked: true),
            PresenceReading(idleSeconds: 5, otherUserOnConsole: true),
        ]
        for reading in readings {
            harness.presence.reading = reading
            let sample = try #require(await harness.tick())
            #expect(sample.foreground == nil)
            // `tools` had its last input 5 minutes ago; its `make` pane is a job.
            #expect(Set(sample.background.map { "\($0.app) \($0.session)" }) == [
                "Claude Code refactor-parser", "tmux paper:0.0", "tmux lab:0.0", "tmux tools:1.0",
            ], "\(sample.state)")
            let agent = try #require(sample.background.first { $0.app == "Claude Code" })
            #expect(agent == ActivityItem(
                app: "Claude Code",
                appID: "claude",
                session: "refactor-parser",
                location: "~/Documents/Code/parser",
                command: "claude",
                workspace: "~/Documents/Code/parser"
            ))
        }
        #expect(harness.liveSamples().map(\.state) == [.idle, .locked, .otherUser])

        harness.presence.reading = PresenceReading()
        await harness.event(.sleep)
        #expect(harness.latest?.state == .asleep)
        #expect(harness.latest?.background.isEmpty == true)
    }

    @Test(
        "TRK-56 with the remote shell snippet installed, an ssh session's Samples carry the host, folder, remote tmux session, and command"
    )
    func remoteShell() async throws {
        let harness = try AgentHarness()
        harness.loadTerminalFixtures()
        let table = AgentHarness.fixture("ps/terminals.txt") + "  900   500 ttys030  Ss   -zsh\n  901   900 ttys030  S+   ssh\n"
        harness.commands.set(ProcessTable.command, table)
        harness.commands.set(AgentHarness.weztermListCommand, """
        [{"pane_id":1,"tty_name":"/dev/ttys030","title":"job:1.0 julia run.jl","cwd":"file://hpc/scratch/run7","is_active":true}]
        """)
        harness.processes.arguments = [901: ["ssh", "hpc"]]
        harness.frontmost("com.github.wez.wezterm", name: "WezTerm", pid: 500, title: "hpc")
        let item = try #require(await harness.tick()?.foreground)
        #expect(item == ActivityItem(
            app: "WezTerm",
            appID: "com.github.wez.wezterm",
            window: "hpc",
            host: "hpc",
            session: "job:1.0",
            location: "/scratch/run7",
            command: "julia run.jl",
            workspace: "hpc:/scratch/run7"
        ))
        #expect(harness.health(.remoteShell)?.status == .active)
    }
}
