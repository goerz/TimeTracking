// TerminalObserver+Background: the background Items of a Sample: busy
// coding agents, other active tmux clients, and job commands
// (activity_tracking.md §2.3, §3.1, §7.2).

import Foundation
import TimeTrackingCore

extension TerminalObserver {
    /// How recent another tmux client's input must be to count.
    static let otherClientWindow: TimeInterval = 30
    /// The app of a coding agent's background Item.
    static let agentApp = ExclusionRules.codingAgentApp

    /// The background Items at `now`: every busy coding agent session, the
    /// active pane of every tmux client with recent input in another session
    /// than the focused pane's, and every pane running a `job_commands`
    /// program other than the focused pane. Without their workspaces.
    func background(
        snapshot: TerminalSnapshot,
        focusedPane: String,
        now: Date,
        settings: TrackerSettings,
        exclusions: ExclusionRules
    ) -> [ActivityItem] {
        let focusedSession = ExclusionRules.tmuxSessionName(focusedPane)
        return busyAgents(snapshot, exclusions: exclusions)
            + otherClients(snapshot, focusedSession: focusedSession, now: now, exclusions: exclusions)
            + jobs(snapshot, focusedPane: focusedPane, settings: settings, exclusions: exclusions)
    }

    private func busyAgents(_ snapshot: TerminalSnapshot, exclusions: ExclusionRules) -> [ActivityItem] {
        (snapshot.sessions ?? [:]).values.sorted { $0.pid < $1.pid }.compactMap { session in
            guard session.busy else {
                return nil
            }
            if !session.tmuxSession.isEmpty, exclusions.excludesTmuxSession(session.tmuxSession) {
                return Self.privateItem(app: Self.agentApp, appID: "claude")
            }
            if exclusions.isPrivateAgentPath(session.cwd) {
                return ActivityItem(app: Self.agentApp, appID: "claude", session: session.name)
            }
            return ActivityItem(
                app: Self.agentApp,
                appID: "claude",
                session: session.name,
                location: paths.tilde(session.cwd),
                command: commandLine(snapshot.processes[session.pid])
            )
        }
    }

    private func otherClients(
        _ snapshot: TerminalSnapshot,
        focusedSession: String?,
        now: Date,
        exclusions: ExclusionRules
    ) -> [ActivityItem] {
        var seen = Set<String>()
        return snapshot.tmux.clients
            .filter { now.timeIntervalSince($0.activity) <= Self.otherClientWindow && $0.session != focusedSession }
            .sorted { $0.session < $1.session }
            .compactMap { client in
                guard seen.insert(client.session).inserted,
                      let pane = snapshot.tmux.activePane(session: client.session, server: client.server)
                else {
                    return nil
                }
                return paneItem(pane, snapshot: snapshot, exclusions: exclusions)
            }
    }

    private func jobs(
        _ snapshot: TerminalSnapshot,
        focusedPane: String,
        settings: TrackerSettings,
        exclusions: ExclusionRules
    ) -> [ActivityItem] {
        let commands = Set(settings.terminal.jobCommands)
        return snapshot.tmux.panes.compactMap { pane in
            let program = snapshot.processes.foreground(onTTY: pane.tty).map { Self.programName($0.name) } ?? Self.programName(pane.command)
            guard commands.contains(program), pane.target != focusedPane else {
                return nil
            }
            return paneItem(pane, snapshot: snapshot, exclusions: exclusions)
        }
    }

    /// A tmux pane as a background Item; private in an excluded session.
    private func paneItem(_ pane: TmuxPane, snapshot: TerminalSnapshot, exclusions: ExclusionRules) -> ActivityItem {
        if exclusions.excludesTmuxSession(pane.session) {
            return Self.privateItem(app: "tmux", appID: "tmux")
        }
        return ActivityItem(
            app: "tmux",
            appID: "tmux",
            session: pane.target,
            location: paths.tilde(pane.path),
            command: commandLine(snapshot.processes.foreground(onTTY: pane.tty) ?? snapshot.processes[pane.pid])
        )
    }

    /// The Item of work in an excluded tmux session (§7.2): it still
    /// counts, with only the app and the session `(private)`.
    private static func privateItem(app: String, appID: String) -> ActivityItem {
        ActivityItem(app: app, appID: appID, session: Redactor.marker, workspace: ActivityItem.privateWorkspace)
    }
}
