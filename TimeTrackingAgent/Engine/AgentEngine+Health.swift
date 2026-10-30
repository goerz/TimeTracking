// AgentEngine+Health: the health of the sources checked at every tick
// (spec_activity_tracking.md §2.3, §4.4, §7.2).

import Foundation
import TimeTrackingCore

extension AgentEngine {
    /// The window title kept as a debug field: none for a hidden item or
    /// a title naming an excluded path.
    static func debugTitle(_ title: String, item: SampleItem, exclusions: ExclusionRules) -> String {
        let marker = ExclusionRules.privateMarker
        if item.context.contains(marker) || item.subject.contains(marker) || item.detail.contains(marker) {
            return ""
        }
        let paths = title.split(separator: " ").filter { $0.hasPrefix("/") || $0.hasPrefix("~") || $0.hasPrefix("file://") }
        return paths.contains { exclusions.excludesPath(String($0)) } ? "" : title
    }

    func apply(_ entries: [SourceReport]) {
        for entry in entries {
            health.set(entry.id, entry.status, entry.reason)
        }
    }

    /// Health of the sources checked at every tick.
    func updateStaticHealth(snapshot: TerminalSnapshot, now: Date) {
        if snapshot.sessions == nil {
            health.set("agents", .fallback, "No Claude Code sessions folder; busy state unknown")
        } else {
            health.set("agents", .active)
        }
        updateEventSource("tmux_events", key: "event.tmux", reason: "No tmux hook event in the last 7 days; the tick alone", now: now)
        updateEventSource("agent_events", key: "event.agent", reason: "No agent hook event in the last 7 days; the tick alone", now: now)
        if environment.history.canReadSafari {
            health.set("history", .active)
        } else {
            health.set("history", .fallback, "Full Disk Access not granted; Safari URLs keep only the domain")
        }
        let context = resolveContext()
        if settings.files.roots.map(context.expand).contains(where: environment.files.exists) {
            health.set("files", .active)
        } else {
            health.set("files", .off, "No watched folder exists")
        }
        if !settings.devices.syncedSafariHistory {
            health.set("synced_safari", .off, "Turned off in the settings")
        } else if !environment.history.canReadSafari {
            health.set("synced_safari", .off, "Full Disk Access not granted")
        } else {
            health.set("synced_safari", .active)
        }
    }

    /// A pushed-event source is `active` while an event arrived in the last 7 days.
    private func updateEventSource(_ id: String, key: String, reason: String, now: Date) {
        if let seen = try? store.date(key), now.timeIntervalSince(seen) < Self.eventSourceWindow {
            health.set(id, .active)
        } else {
            health.set(id, .fallback, reason)
        }
    }
}
