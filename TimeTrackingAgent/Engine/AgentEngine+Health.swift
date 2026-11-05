// AgentEngine+Health: the health of the sources checked at every tick
// (activity_tracking.md §2.3, §4.4, §7.2).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// Applies what a resolver reported to the board.
    func apply(_ entries: [SourceReport]) {
        for entry in entries {
            health.set(entry.id, entry.status, entry.reason)
        }
    }

    /// Health of the sources checked at every tick.
    func updateStaticHealth(snapshot: TerminalSnapshot, now: Date) {
        if snapshot.sessions == nil {
            health.set(.agents, .fallback, "Claude Code not found; when it is working can't be told")
        } else {
            health.set(.agents, .active)
        }
        updateEventSource(
            .tmuxEvents,
            key: Self.tmuxEventKey,
            reason: "No tmux hook event in the last 7 days; switches are noticed up to 30 seconds late",
            now: now
        )
        updateEventSource(
            .agentEvents,
            key: Self.agentEventKey,
            reason: "No Claude Code hook event in the last 7 days; changes are noticed up to 30 seconds late",
            now: now
        )
        if environment.history.canReadSafari {
            health.set(.history, .active)
        } else {
            health.set(.history, .fallback, SourceID.noFullDiskAccessReason)
        }
        let context = resolveContext()
        if settings.files.roots.map(context.expand).contains(where: environment.files.exists) {
            health.set(.files, .active)
        } else {
            health.set(.files, .off, "None of the watched folders in the settings file exist")
        }
        if !settings.devices.syncedSafariHistory {
            health.set(.syncedSafari, .off, "Turned off in the settings file")
        } else if !environment.history.canReadSafari {
            health.set(.syncedSafari, .off, "Full Disk Access is off")
        } else {
            health.set(.syncedSafari, .active)
        }
    }

    /// A pushed-event source is `active` while an event arrived in the last 7 days.
    private func updateEventSource(_ id: SourceID, key: String, reason: String, now: Date) {
        if let seen = try? store.date(key), now.timeIntervalSince(seen) < Self.eventSourceWindow {
            health.set(id, .active)
        } else {
            health.set(id, .fallback, reason)
        }
    }
}
