// SourceID: the sources of §2.3 as current.json names them
// (spec_activity_tracking.md §2.3, §4.4).

import TimeTrackingCore

/// A source of §2.3; the raw value is its `id` in `current.json`, and the
/// cases are in table order.
nonisolated enum SourceID: String, CaseIterable, Hashable, Sendable {
    case window
    case terminal
    case tmux
    case editor
    case agents
    case tmuxEvents = "tmux_events"
    case agentEvents = "agent_events"
    case browser
    case history
    case knowledge
    case files
    case sharedFolder = "shared_folder"
    case deviceEvents = "device_events"
    case syncedSafari = "synced_safari"

    /// The display name in `current.json`, from the library's table.
    var name: String {
        TrackerSourceHealth.name(forID: rawValue) ?? rawValue
    }

    /// The reason shared by `history` and the browser resolver.
    static let noFullDiskAccessReason = "Full Disk Access is off; Safari pages are recorded by site only"
}
