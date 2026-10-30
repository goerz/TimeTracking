// TerminalResolver: the item of a frontmost terminal and the terminal
// secondaries (spec_activity_tracking.md §2.2, §2.4, §3.1, §7.2).

import Foundation
import TimeTrackingCore

/// The item a terminal gives, with what the sources reported.
struct TerminalObservation {
    var item: SampleItem
    var tmuxTarget: String
    var health: [(id: String, status: TrackerSourceStatus, reason: String)]
}

/// Resolves the focused pane: the terminal adapter (or the process-tree
/// fallback) gives its tty, tmux the session and pane, and the pane's
/// foreground program refines the item (editor file, coding agent session,
/// interpreter, shell, job command).
@MainActor
final class TerminalResolver {
    /// The editor RPC timeout of §3.1.
    static let rpcTimeout = 0.2
    /// How often RPC cross-checks a working pane title, per pane.
    static let crossCheckInterval: TimeInterval = 600
    /// How long a silent RPC socket is skipped.
    static let silentBackoff: TimeInterval = 60

    private let environment: AgentEnvironment
    /// Notebook ports and the items of the panes that registered them (§2.2 rule 2).
    private(set) var ports = PortRegistry()
    private var lastCrossCheck: [String: Date] = [:]
    private var silentSockets: [String: Date] = [:]
    /// Files modified below a folder recently, for panes without a file (§3.4).
    var recentFile: (String) -> String? = { _ in nil }

    init(environment: AgentEnvironment) {
        self.environment = environment
    }

    // MARK: Primary

    /// The item of `app`, a terminal, with window title `title`.
    func resolve(app: FrontApp, title: String, snapshot: TerminalSnapshot, context: inout ResolveContext) async -> TerminalObservation {
        let terminal = TerminalApp.known[app.bundleID] ?? TerminalApp(context: app.name.lowercased(), adapter: nil)
        var health: [(String, TrackerSourceStatus, String)] = []
        var located = await adapterTTY(terminal, snapshot: snapshot)
        if located != nil {
            health.append(("terminal", .active, ""))
        } else {
            located = fallbackTTY(below: app.pid, snapshot: snapshot)
            let reason = terminal.adapter == nil ? "No adapter for \(app.name); using the process tree" : "\(app.name) did not answer; using the process tree"
            health.append(("terminal", .fallback, reason))
        }
        health.append(snapshot.tmuxExecutable == nil || snapshot.tmux.servers.isEmpty ? ("tmux", .fallback, "tmux is not running") : ("tmux", .active, ""))
        guard let tty = located?.tty else {
            let item = SampleItem(context: terminal.context, subject: context.filteredTitle(title), groupKey: terminal.context, app: app.bundleID)
            return TerminalObservation(item: item, tmuxTarget: "", health: health)
        }
        if let client = snapshot.tmux.client(onTTY: tty), let pane = snapshot.tmux.activePane(session: client.session, server: client.server) {
            let (item, editorHealth) = await paneItem(
                PaneFacts(pane: pane, terminalContext: terminal.context, app: app.bundleID),
                snapshot: snapshot,
                context: &context
            )
            health += editorHealth
            return TerminalObservation(item: item, tmuxTarget: pane.target, health: health)
        }
        guard let process = snapshot.processes.foreground(onTTY: tty) else {
            let cwd = located?.cwd ?? ""
            let item = SampleItem(context: terminal.context, subject: context.tilde(cwd), groupKey: terminal.context, app: app.bundleID)
            return TerminalObservation(item: item, tmuxTarget: "", health: health)
        }
        let cwd = environment.processes.workingDirectory(of: process.pid) ?? located?.cwd ?? ""
        let facts = PaneFacts(
            session: nil,
            windowName: "",
            automaticRename: true,
            command: process.name,
            cwd: cwd,
            title: located?.title ?? title,
            pid: process.pid,
            key: "\(terminal.context):\(tty)",
            terminalContext: terminal.context,
            app: app.bundleID
        )
        let (item, editorHealth) = await paneItem(facts, snapshot: snapshot, context: &context)
        health += editorHealth
        return TerminalObservation(item: item, tmuxTarget: "", health: health)
    }

    /// What locates a pane: its terminal, and title and cwd when the adapter knows them.
    struct Located {
        var tty: String
        var title: String?
        var cwd: String?
    }

    /// The focused pane's tty from the terminal's adapter, or `nil`.
    private func adapterTTY(_ terminal: TerminalApp, snapshot _: TerminalSnapshot) async -> Located? {
        switch terminal.adapter {
        case .wezterm:
            guard let executable = TerminalApp.weztermExecutables.first(where: { environment.files.exists($0) }),
                  let clientsText = await environment.commands.run([executable, "cli", "list-clients", "--format", "json"]),
                  let listText = await environment.commands.run([executable, "cli", "list", "--format", "json"])
            else {
                return nil
            }
            return WezTermAdapter.focused(clients: clientsText, panes: listText)
        case .iterm:
            if case let .value(tty) = environment.scripts.run(TerminalApp.itermScript), !tty.isEmpty {
                return Located(tty: tty)
            }
            return nil
        case .terminal:
            if case let .value(tty) = environment.scripts.run(TerminalApp.terminalScript), !tty.isEmpty {
                return Located(tty: tty)
            }
            return nil
        case nil:
            return nil
        }
    }

    /// The tty below the terminal's process with the most recent input:
    /// tmux `client_activity`, else the tty's access time.
    func fallbackTTY(below pid: Int32, snapshot: TerminalSnapshot) -> Located? {
        let candidates = snapshot.processes.terminals(below: pid)
        let scored = candidates.map { tty -> (String, Date) in
            if let client = snapshot.tmux.client(onTTY: tty) {
                return (tty, client.activity)
            }
            return (tty, environment.processes.lastInput(onTTY: tty) ?? .distantPast)
        }
        return scored.max { $0.1 < $1.1 }.map { Located(tty: $0.0) }
    }

    // MARK: The pane's item

    /// The facts of one pane, from tmux or from the tty's foreground process.
    struct PaneFacts {
        var session: String?
        var windowName: String
        var automaticRename: Bool
        var command: String
        var cwd: String
        var title: String
        var pid: Int32
        /// Identifies the pane in the caches.
        var key: String
        var terminalContext: String
        var app: String

        init(
            session: String?,
            windowName: String,
            automaticRename: Bool,
            command: String,
            cwd: String,
            title: String,
            pid: Int32,
            key: String,
            terminalContext: String,
            app: String
        ) {
            self.session = session
            self.windowName = windowName
            self.automaticRename = automaticRename
            self.command = command
            self.cwd = cwd
            self.title = title
            self.pid = pid
            self.key = key
            self.terminalContext = terminalContext
            self.app = app
        }

        init(pane: TmuxPane, terminalContext: String, app: String) {
            self.init(
                session: pane.session,
                windowName: pane.windowName,
                automaticRename: pane.automaticRename,
                command: pane.command,
                cwd: pane.path,
                title: pane.title,
                pid: pane.pid,
                key: "\(pane.server):\(pane.target)",
                terminalContext: terminalContext,
                app: app
            )
        }
    }

    /// The item of a pane after exclusions, with editor and agent health.
    func paneItem(
        _ facts: PaneFacts,
        snapshot: TerminalSnapshot,
        context: inout ResolveContext
    ) async -> (SampleItem, [(String, TrackerSourceStatus, String)]) {
        var health: [(String, TrackerSourceStatus, String)] = []
        let exclusions = context.exclusions
        let program = Self.programName(facts.command)
        let contextName = facts.session.map { "tmux:\($0)" } ?? facts.terminalContext
        if let session = facts.session, exclusions.excludesTmuxSession(session) {
            let hidden = "tmux:\(ExclusionRules.privateMarker)"
            return (SampleItem(context: hidden, subject: "", groupKey: hidden, app: facts.app), health)
        }
        var subjectFromCwd = facts.session == nil || facts.automaticRename || facts.windowName == program || facts.windowName.isEmpty
        var detail = program
        var file: String?
        var agentSession: AgentSession?
        if TerminalPrograms.editors.contains(program) {
            let (resolved, editorHealth) = await editorFile(facts, program: program, snapshot: snapshot, context: context)
            file = resolved
            health += editorHealth
        } else if let session = snapshot.session(inTreeOf: facts.pid), program == "claude" || program == "node" || facts.command.contains("claude") {
            agentSession = session
            detail = session.name.isEmpty ? "claude" : "claude \(session.name)"
            if exclusions.isPrivateAgentPath(session.cwd) {
                subjectFromCwd = false
            }
        } else if context.settings.terminal.agentProcesses.contains(program) {
            detail = program
        } else if TerminalPrograms.isInterpreter(program) {
            if ports.needsScan(paneOf: facts.pid, now: environment.clock.now),
               let found = await PortRegistry.listeningPorts(paneOf: facts.pid, snapshot: snapshot, commands: environment.commands) {
                ports.setPorts(found, paneOf: facts.pid)
            }
        } else if TerminalPrograms.shells.contains(program) {
            detail = recentFile(facts.cwd).map { (($0 as NSString).lastPathComponent) } ?? ""
        }
        if let file {
            detail = exclusions.excludesPath(file) ? "\(program) \(ExclusionRules.privateMarker)" : "\(program) \((file as NSString).lastPathComponent)"
        }
        var subject = subjectFromCwd ? context.tilde(facts.cwd) : facts.windowName
        if agentSession != nil, !subjectFromCwd, facts.session == nil {
            subject = agentSession?.name ?? ""
        }
        let groupKey = facts.session.map { "tmux:\($0)" } ?? context.workFolder(ofFolder: facts.cwd)
        var item = SampleItem(context: contextName, subject: subject, detail: detail, groupKey: groupKey, app: facts.app)
        if !facts.cwd.isEmpty, exclusions.excludesPath(facts.cwd) {
            item = ResolveContext.privatePath(item, keepGroup: facts.session != nil)
        }
        if exclusions.excludesTitle(item.subject) {
            item.subject = ""
        }
        if exclusions.excludesTitle(item.detail) {
            item.detail = ""
        }
        if TerminalPrograms.isInterpreter(program) {
            ports.remember(item, forPaneOf: facts.pid)
        }
        return (item, health)
    }

    /// `nvim` for `/opt/homebrew/bin/nvim` or `-zsh`.
    static func programName(_ command: String) -> String {
        let last = command.split(separator: "/").last.map(String.init) ?? command
        return last.hasPrefix("-") ? String(last.dropFirst()) : last
    }

    // MARK: Editor chain

    /// The editor's file: the pane title through `title_patterns` while the
    /// pane's command is that editor, then Neovim RPC (200 ms), then the
    /// editor's arguments, then nothing (cwd only).
    func editorFile(
        _ facts: PaneFacts,
        program: String,
        snapshot: TerminalSnapshot,
        context: ResolveContext
    ) async -> (String?, [(String, TrackerSourceStatus, String)]) {
        let now = environment.clock.now
        if let pattern = context.settings.terminal.titlePatterns[program], let fromTitle = Self.match(pattern, facts.title) {
            let path = context.expand(fromTitle)
            if program == "nvim", now.timeIntervalSince(lastCrossCheck[facts.key] ?? .distantPast) >= Self.crossCheckInterval {
                lastCrossCheck[facts.key] = now
                if let socket = neovimSocket(forPaneOf: facts.pid, snapshot: snapshot),
                   let fromRPC = await environment.editorRPC.currentFile(socket: socket, timeout: Self.rpcTimeout), fromRPC != path {
                    return (path, [("editor", .fallback, "The pane title and Neovim disagree about the file")])
                }
            }
            return (path, [("editor", .active, "")])
        }
        let reason = "\(program) does not name its file in the pane title"
        if program == "nvim", let socket = neovimSocket(forPaneOf: facts.pid, snapshot: snapshot),
           now.timeIntervalSince(silentSockets[socket] ?? .distantPast) >= Self.silentBackoff {
            if let fromRPC = await environment.editorRPC.currentFile(socket: socket, timeout: Self.rpcTimeout) {
                return (fromRPC, [("editor", .fallback, reason)])
            }
            silentSockets[socket] = environment.clock.now
        }
        if let editor = snapshot.processes[facts.pid].map({ [$0] + snapshot.processes.descendants(of: facts.pid) })?
            .first(where: { $0.name == program }) ?? snapshot.processes[facts.pid],
            let arguments = environment.processes.arguments(of: editor.pid),
            let fileArgument = arguments.dropFirst().last(where: { !$0.hasPrefix("-") && !$0.hasPrefix("+") }) {
            let path = fileArgument.hasPrefix("/") || fileArgument.hasPrefix("~") ? context.expand(fileArgument) : facts.cwd + "/" + fileArgument
            return (path, [("editor", .fallback, reason)])
        }
        return (nil, [("editor", .fallback, reason)])
    }

    /// The server socket of the `nvim --embed` process below the pane.
    private func neovimSocket(forPaneOf pid: Int32, snapshot: TerminalSnapshot) -> String? {
        let embeds = snapshot.processes.descendants(of: pid).filter { $0.name == "nvim" }
        let folder = environment.neovimSocketFolder
        guard !embeds.isEmpty, let groups = environment.files.list(folder) else {
            return nil
        }
        for embed in embeds.reversed() {
            for group in groups.sorted() {
                let candidate = "\(folder)/\(group)/nvim.\(embed.pid).0"
                if environment.files.exists(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// The first capture group of `pattern` in `text`.
    static func match(_ pattern: String, _ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              result.numberOfRanges > 1, let range = Range(result.range(at: 1), in: text)
        else {
            return nil
        }
        let value = String(text[range])
        return value.isEmpty ? nil : value
    }
}
