// TerminalResolver+Secondaries: busy coding agents, other active tmux
// clients, and job commands (spec_activity_tracking.md §2.4 step 4, §7.2).

import Foundation
import TimeTrackingCore

extension TerminalResolver {
    /// How recent another tmux client's input must be to count.
    static let otherClientWindow: TimeInterval = 30

    /// The secondary items at `now`, excluding the primary's own pane and session.
    func secondaries(
        snapshot: TerminalSnapshot,
        primary: SampleItem?,
        primaryTarget: String,
        now: Date,
        context: inout ResolveContext
    ) -> [SampleItem] {
        let primarySession = primary?.context.hasPrefix("tmux:") == true ? String(primary?.context.dropFirst(5) ?? "") : nil
        return busyAgents(snapshot, context: context)
            + otherClients(snapshot, primarySession: primarySession, now: now, context: context)
            + jobs(snapshot, primarySession: primarySession, primaryTarget: primaryTarget, context: context)
    }

    /// Every busy coding agent session, by name.
    private func busyAgents(_ snapshot: TerminalSnapshot, context: ResolveContext) -> [SampleItem] {
        let exclusions = context.exclusions
        var result: [SampleItem] = []
        for session in (snapshot.sessions ?? [:]).values.sorted(by: { $0.pid < $1.pid }) where session.busy {
            if !session.tmuxSession.isEmpty, exclusions.excludesTmuxSession(session.tmuxSession) {
                continue
            }
            var subject = session.name.isEmpty ? Self.programName(session.cwd) : session.name
            if !exclusions.isPrivateAgentPath(session.cwd), !session.cwd.isEmpty, exclusions.excludesPath(session.cwd) {
                subject = ExclusionRules.privateMarker
            }
            if exclusions.excludesTitle(subject) {
                subject = ""
            }
            result.append(SampleItem(context: "claude", subject: subject, groupKey: "claude", app: "claude"))
        }
        return result
    }

    /// The active pane of every tmux client with input in the last 30 s, in another session.
    private func otherClients(_ snapshot: TerminalSnapshot, primarySession: String?, now: Date, context: ResolveContext) -> [SampleItem] {
        let exclusions = context.exclusions
        var result: [SampleItem] = []
        var seen = Set<String>()
        let recent = snapshot.tmux.clients.filter { client in
            now.timeIntervalSince(client.activity) <= Self.otherClientWindow && client.session != primarySession
        }
        for client in recent.sorted(by: { $0.session < $1.session }) {
            guard seen.insert(client.session).inserted, !exclusions.excludesTmuxSession(client.session),
                  let pane = snapshot.tmux.activePane(session: client.session, server: client.server)
            else {
                continue
            }
            let program = Self.programName(pane.command)
            let fromCwd = pane.automaticRename || pane.windowName == program || pane.windowName.isEmpty
            var item = SampleItem(
                context: "tmux:\(client.session)",
                subject: fromCwd ? context.tilde(pane.path) : pane.windowName,
                groupKey: "tmux:\(client.session)",
                app: "tmux"
            )
            if exclusions.excludesPath(pane.path) {
                item = ResolveContext.privatePath(item, keepGroup: true)
            }
            if exclusions.excludesTitle(item.subject) {
                item.subject = ""
            }
            result.append(item)
        }
        return result
    }

    /// `job_commands` running in panes other than the primary's.
    private func jobs(
        _ snapshot: TerminalSnapshot,
        primarySession: String?,
        primaryTarget: String,
        context: ResolveContext
    ) -> [SampleItem] {
        let exclusions = context.exclusions
        let commands = Set(context.settings.terminal.jobCommands)
        return snapshot.tmux.panes.compactMap { pane in
            let program = Self.programName(pane.command)
            let isPrimary = primaryTarget.isEmpty ? pane.windowActive && pane.paneActive && primarySession == pane.session : pane
                .target == primaryTarget
            guard commands.contains(program), !isPrimary, !exclusions.excludesTmuxSession(pane.session) else {
                return nil
            }
            let item = SampleItem(
                context: "tmux:\(pane.session)",
                subject: context.tilde(pane.path),
                detail: program,
                groupKey: "tmux:\(pane.session)",
                app: "tmux"
            )
            return exclusions.excludesPath(pane.path) ? ResolveContext.privatePath(item, keepGroup: true) : item
        }
    }
}
