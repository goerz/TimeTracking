// TerminalResolver: the item of a frontmost terminal and the terminal
// secondaries (spec_activity_tracking.md §2.2, §2.4, §3.1, §7.2).

import Foundation
import TimeTrackingCore

/// The item a terminal gives, with what the sources reported.
struct TerminalObservation {
    var item: SampleItem
    var tmuxTarget: String
    var health: [SourceReport]
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

    let environment: AgentEnvironment
    /// Notebook ports and the items of the panes that registered them (§2.2 rule 2).
    var ports = PortRegistry()
    var lastCrossCheck: [String: Date] = [:]
    var silentSockets: [String: Date] = [:]
    /// Files modified below a folder recently, for panes without a file (§3.4).
    var recentFile: (String) -> String? = { _ in nil }

    init(environment: AgentEnvironment) {
        self.environment = environment
    }

    // MARK: Primary

    /// The item of `app`, a terminal, with window title `title`.
    func resolve(app: FrontApp, title: String, snapshot: TerminalSnapshot, context: inout ResolveContext) async -> TerminalObservation {
        let terminal = TerminalApp.known[app.bundleID] ?? TerminalApp(context: app.name.lowercased(), adapter: nil)
        var health: [SourceReport] = []
        var located = await adapterTTY(terminal)
        if located != nil {
            health.append(SourceReport(.terminal, .active))
        } else {
            located = fallbackTTY(below: app.pid, snapshot: snapshot)
            let cause = terminal.adapter == nil ? "\(app.name) can't report its front tab" : "\(app.name) didn't answer"
            health.append(SourceReport(.terminal, .fallback, cause + "; the tab is guessed from recent activity"))
        }
        if snapshot.tmuxExecutable == nil || snapshot.tmux.servers.isEmpty {
            health.append(SourceReport(.tmux, .fallback, "tmux is not running"))
        } else {
            health.append(SourceReport(.tmux, .active))
        }
        guard let tty = located?.tty else {
            let item = SampleItem(
                context: terminal.context,
                subject: context.filteredTitle(title),
                groupKey: terminal.context,
                app: app.bundleID
            )
            return TerminalObservation(item: item, tmuxTarget: "", health: health)
        }
        if let client = snapshot.tmux.client(onTTY: tty), let pane = snapshot.tmux.activePane(
            session: client.session,
            server: client.server
        ) {
            let (item, editorHealth) = await paneItem(
                PaneFacts(pane: pane, terminalContext: terminal.context, app: app.bundleID),
                snapshot: snapshot,
                context: &context
            )
            health += editorHealth
            let hidden = context.exclusions.excludesTmuxSession(pane.session)
            return TerminalObservation(item: item, tmuxTarget: hidden ? "" : pane.target, health: health)
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
    private func adapterTTY(_ terminal: TerminalApp) async -> Located? {
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
            return scriptTTY(TerminalApp.itermScript)
        case .terminal:
            return scriptTTY(TerminalApp.terminalScript)
        case nil:
            return nil
        }
    }

    /// The tty an adapter script answers, or `nil` for no answer.
    private func scriptTTY(_ script: String) -> Located? {
        guard case let .value(tty) = environment.scripts.run(script), !tty.isEmpty else {
            return nil
        }
        return Located(tty: tty)
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
    }
}

extension TerminalResolver.PaneFacts {
    /// The facts of a tmux pane.
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
