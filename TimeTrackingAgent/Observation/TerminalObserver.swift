// TerminalObserver: the Item of a frontmost terminal's focused pane
// (activity_tracking.md §2.3, §3.1, §7.2).

import Foundation
import TimeTrackingCore

/// What the front app gives at one tick.
nonisolated struct FrontObservation: Hashable, Sendable {
    /// The foreground Item without its workspace; `nil` for an excluded app.
    var item: ActivityItem?
    var bundleID: String
    /// A browser tab's domain, for `passive_domains`.
    var domain: String?
    /// The tmux target of the focused pane, which background Items skip.
    var paneTarget = ""
    var health: [SourceReport] = []
}

/// Finds the focused pane (a terminal adapter, else the tty with the most
/// recent input) and describes it: tmux's session and pane, the foreground
/// program's command line and folder, an editor's file, a coding agent's
/// session, or a remote shell's host.
@MainActor
final class TerminalObserver {
    /// The editor RPC timeout of §3.1.
    static let rpcTimeout = 0.2
    /// How often RPC cross-checks a working pane title, per pane.
    static let crossCheckInterval: TimeInterval = 600
    /// How long a silent RPC socket is skipped.
    static let silentBackoff: TimeInterval = 60

    let environment: AgentEnvironment
    let paths: HomePaths
    /// Notebook servers' ports and folders (§2.3 rule 3).
    var ports = PortRegistry()
    var lastCrossCheck: [String: Date] = [:]
    var silentSockets: [String: Date] = [:]
    /// When a remote shell last reported its folder (OSC 7 with a host).
    var lastRemoteReport: Date?

    init(environment: AgentEnvironment) {
        self.environment = environment
        self.paths = HomePaths(home: environment.homeDirectory)
    }

    /// The focused pane's Item, `app` a terminal whose front window is `title`.
    func observe(
        app: FrontApp,
        title: String,
        snapshot: TerminalSnapshot,
        settings: TrackerSettings,
        exclusions: ExclusionRules
    ) async -> FrontObservation {
        var observation = FrontObservation(bundleID: app.bundleID)
        let plain = ActivityItem(app: app.name, appID: app.bundleID, window: title)
        let adapter = TerminalApp.known[app.bundleID]?.adapter
        var located = await adapterPane(adapter)
        if located != nil {
            observation.health.append(SourceReport(.terminal, .active))
        } else {
            located = fallbackPane(below: app.pid, snapshot: snapshot)
            let cause = adapter == nil ? "\(app.name) can't report its front tab" : "\(app.name) didn't answer"
            observation.health.append(SourceReport(.terminal, .fallback, cause + "; the tab is guessed from recent activity"))
        }
        let tmuxRuns = snapshot.tmuxExecutable != nil && !snapshot.tmux.servers.isEmpty
        observation.health.append(tmuxRuns ? SourceReport(.tmux, .active) : SourceReport(.tmux, .fallback, "tmux is not running"))
        guard let located, let pane = PaneFacts(located: located, snapshot: snapshot, processes: environment.processes) else {
            observation.item = plain
            return observation
        }
        if let session = pane.tmuxSession, exclusions.excludesTmuxSession(session) {
            observation.item = ActivityItem(
                app: app.name,
                appID: app.bundleID,
                session: Redactor.marker,
                workspace: ActivityItem.privateWorkspace
            )
            observation.paneTarget = pane.tmuxTarget ?? ""
            return observation
        }
        var item = plain
        item.session = pane.tmuxTarget ?? ""
        item.location = paths.tilde(pane.cwd)
        item.command = commandLine(pane.program)
        let program = pane.program.map { Self.programName($0.name) } ?? ""
        if TerminalPrograms.editors.contains(program) {
            let (file, health) = await editorFile(pane, program: program, snapshot: snapshot, settings: settings)
            item.documents = file.map { [paths.tilde($0)] } ?? []
            observation.health += health
        } else if let agent = snapshot.session(inTreeOf: pane.shellPID) {
            if exclusions.isPrivateAgentPath(agent.cwd) {
                item = ActivityItem(app: app.name, appID: app.bundleID, session: agent.name)
            } else if !agent.name.isEmpty {
                item.session = agent.name
            }
        } else if TerminalPrograms.isInterpreter(program) {
            await registerPorts(of: pane, snapshot: snapshot)
        } else if program == "ssh" {
            applyRemoteShell(located: located, pane: pane, to: &item)
        }
        observation.item = item
        observation.paneTarget = pane.tmuxTarget ?? ""
        return observation
    }

    // MARK: Locating the pane

    /// The focused pane from the terminal's adapter, or `nil`.
    private func adapterPane(_ adapter: TerminalAdapterKind?) async -> LocatedPane? {
        switch adapter {
        case .wezterm:
            guard let executable = TerminalApp.weztermExecutables.first(where: { environment.files.exists($0) }),
                  let clientsText = await environment.commands.run([executable, "cli", "list-clients", "--format", "json"]),
                  let listText = await environment.commands.run([executable, "cli", "list", "--format", "json"])
            else {
                return nil
            }
            return WezTermAdapter.focused(clients: clientsText, panes: listText, localHosts: environment.localHostNames)
        case .iterm:
            return scriptPane(TerminalApp.itermScript)
        case .terminal:
            return scriptPane(TerminalApp.terminalScript)
        case nil:
            return nil
        }
    }

    private func scriptPane(_ script: String) -> LocatedPane? {
        guard case let .value(tty) = environment.scripts.run(script), !tty.isEmpty else {
            return nil
        }
        return LocatedPane(tty: tty)
    }

    /// The tty below the terminal's process with the most recent input:
    /// tmux's `client_activity`, else the tty's access time.
    func fallbackPane(below pid: Int32, snapshot: TerminalSnapshot) -> LocatedPane? {
        snapshot.processes.terminals(below: pid)
            .map { tty in (tty, snapshot.tmux.client(onTTY: tty)?.activity ?? environment.processes.lastInput(onTTY: tty) ?? .distantPast) }
            .max { $0.1 < $1.1 }
            .map { LocatedPane(tty: $0.0) }
    }

    // MARK: Refinements

    /// The listening ports of an interpreter's pane, looked up at most every minute.
    private func registerPorts(of pane: PaneFacts, snapshot: TerminalSnapshot) async {
        if ports.needsScan(paneOf: pane.shellPID, now: environment.clock.now),
           let found = await PortRegistry.listeningPorts(paneOf: pane.shellPID, snapshot: snapshot, commands: environment.commands)
        {
            ports.setPorts(found, paneOf: pane.shellPID)
        }
        ports.remember(pane.cwd, forPaneOf: pane.shellPID)
    }

    /// An ssh pane: the host and folder of an OSC 7 report, and the remote
    /// tmux session and command of a `set-titles` window title
    /// (`<session>:<window>.<pane> <command>`).
    private func applyRemoteShell(located: LocatedPane, pane: PaneFacts, to item: inout ActivityItem) {
        if !located.cwdHost.isEmpty {
            item.host = located.cwdHost
            item.location = located.cwd ?? ""
            lastRemoteReport = environment.clock.now
        } else {
            item.host = Self.sshHost(item.command)
            item.location = ""
        }
        if let remote = Self.remoteTitle(pane.title.isEmpty ? (located.title ?? "") : pane.title) {
            item.session = remote.session
            item.command = remote.command
        }
    }

    /// The host argument of an `ssh` command line, without the user.
    static func sshHost(_ command: String) -> String {
        let words = command.split(separator: " ").dropFirst()
        var skipNext = false
        for word in words {
            if skipNext {
                skipNext = false
                continue
            }
            if word.hasPrefix("-") {
                skipNext = word.count == 2 && "bcDEeFIiJLlmOopQRSWw".contains(word.last ?? " ")
                continue
            }
            return String(word.split(separator: "@").last ?? word)
        }
        return ""
    }

    /// The session and command of a remote tmux title, `job:1.0 julia run.jl`.
    static func remoteTitle(_ title: String) -> (session: String, command: String)? {
        let parts = title.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, ExclusionRules.tmuxSessionName(String(parts[0])) != nil else {
            return nil
        }
        return (String(parts[0]), String(parts[1]))
    }

    /// The process's command line as the shell history would show it:
    /// the program's name, then its arguments.
    func commandLine(_ process: ProcessEntry?) -> String {
        guard let process else {
            return ""
        }
        guard let arguments = environment.processes.arguments(of: process.pid), !arguments.isEmpty else {
            return Self.programName(process.name)
        }
        return ([Self.programName(arguments[0])] + arguments.dropFirst()).joined(separator: " ")
    }

    /// `nvim` for `/opt/homebrew/bin/nvim` or `-zsh`.
    static func programName(_ command: String) -> String {
        let last = command.split(separator: "/").last.map(String.init) ?? command
        return last.hasPrefix("-") ? String(last.dropFirst()) : last
    }
}

/// The facts of the focused pane: tmux's or the tty's.
struct PaneFacts {
    /// `session:window.pane` in tmux, `nil` outside it.
    var tmuxTarget: String?
    var tmuxSession: String?
    var cwd: String
    var title: String
    /// The pane's shell, the root of its process tree.
    var shellPID: Int32
    /// The foreground process of the pane's tty.
    var program: ProcessEntry?
    /// Identifies the pane in the caches.
    var key: String

    /// The pane behind `located`'s tty: tmux's active pane of the client
    /// on it, else the tty's foreground process; `nil` when neither is known.
    @MainActor
    init?(located: LocatedPane, snapshot: TerminalSnapshot, processes: any ProcessProbe) {
        if let client = snapshot.tmux.client(onTTY: located.tty),
           let pane = snapshot.tmux.activePane(session: client.session, server: client.server)
        {
            self.tmuxTarget = pane.target
            self.tmuxSession = pane.session
            self.cwd = pane.path
            self.title = pane.title
            self.shellPID = pane.pid
            self.program = snapshot.processes.foreground(onTTY: pane.tty) ?? snapshot.processes[pane.pid]
            self.key = "\(pane.server):\(pane.target)"
            return
        }
        guard let process = snapshot.processes.foreground(onTTY: located.tty) else {
            return nil
        }
        self.cwd = processes.workingDirectory(of: process.pid) ?? located.cwd ?? ""
        self.title = located.title ?? ""
        self.shellPID = process.pid
        self.program = process
        self.key = "tty:\(located.tty)"
    }
}
