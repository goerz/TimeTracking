// SourceHealthBoard: the status of every source of §2.3 for current.json
// (spec_activity_tracking.md §2.3, §4.4).

import TimeTrackingCore

/// The sources, their display names, and their current status and reason.
nonisolated struct SourceHealthBoard: Hashable, Sendable {
    /// Every source of §2.3 in table order with its name.
    static let sources: [(id: String, name: String)] = [
        ("window", "Window titles"),
        ("terminal", "Terminal"),
        ("tmux", "tmux"),
        ("editor", "Editor file"),
        ("agents", "Coding agents"),
        ("tmux_events", "tmux hooks"),
        ("agent_events", "Agent hooks"),
        ("browser", "Browsers"),
        ("history", "Browser history"),
        ("knowledge", "Knowledge store"),
        ("files", "Modified files"),
        ("shared_folder", "iCloud Drive folder"),
        ("device_events", "iPhone and iPad"),
        ("synced_safari", "Synced Safari history"),
    ]

    private var entries: [String: TrackerSourceHealth]

    init() {
        var initial: [String: TrackerSourceHealth] = [:]
        for source in Self.sources {
            initial[source.id] = TrackerSourceHealth(id: source.id, name: source.name, status: .active)
        }
        initial["device_events"]?.status = .off
        initial["device_events"]?.reason = "Not collected by this version"
        self.entries = initial
    }

    /// Sets a source's status; `reason` is cleared for `active`.
    mutating func set(_ id: String, _ status: TrackerSourceStatus, _ reason: String = "") {
        entries[id]?.status = status
        entries[id]?.reason = status == .active ? "" : reason
    }

    func status(_ id: String) -> TrackerSourceStatus? {
        entries[id]?.status
    }

    func reason(_ id: String) -> String {
        entries[id]?.reason ?? ""
    }

    /// Every source in table order.
    var all: [TrackerSourceHealth] {
        Self.sources.compactMap { entries[$0.id] }
    }
}
