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
        var result: [SampleItem] = []
        let exclusions = context.exclusions
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
        let primarySession = primary?.context.hasPrefix("tmux:") == true ? String(primary?.context.dropFirst(5) ?? "") : nil
        var seenSessions = Set<String>()
        for client in snapshot.tmux.clients.sorted(by: { $0.session < $1.session })
            where now.timeIntervalSince(client.activity) <= Self.otherClientWindow && client.session != primarySession {
            guard seenSessions.insert(client.session).inserted, !exclusions.excludesTmuxSession(client.session),
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
        let jobs = Set(context.settings.terminal.jobCommands)
        for pane in snapshot.tmux.panes where pane.target != primaryTarget || primaryTarget.isEmpty {
            let program = Self.programName(pane.command)
            guard jobs.contains(program), !exclusions.excludesTmuxSession(pane.session) else {
                continue
            }
            if primaryTarget.isEmpty, pane.windowActive, pane.paneActive, primarySession == pane.session {
                continue
            }
            var item = SampleItem(
                context: "tmux:\(pane.session)",
                subject: context.tilde(pane.path),
                detail: program,
                groupKey: "tmux:\(pane.session)",
                app: "tmux"
            )
            if exclusions.excludesPath(pane.path) {
                item = ResolveContext.privatePath(item, keepGroup: true)
            }
            result.append(item)
        }
        return result
    }
}
