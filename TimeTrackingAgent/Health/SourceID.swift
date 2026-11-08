// SourceID: the sources of §3.5 as current.json names them
// (activity_tracking.md §3.5, §4.4).

import TimeTrackingCore

/// A source of §3.5; the raw value is its `id` in `current.json`, and the
/// cases are in table order.
nonisolated enum SourceID: String, CaseIterable, Hashable, Sendable {
    case window
    case terminal
    case tmux
    case editor
    case agents
    case tmuxEvents = "tmux_events"
    case agentEvents = "agent_events"
    case remoteShell = "remote_shell"
    case browser
    case history
    case knowledge
    case sharedFolder = "shared_folder"
    case deviceEvents = "device_events"
    case syncedSafari = "synced_safari"

    /// The display name in `current.json`, from the library's table.
    var name: String {
        TrackerSourceHealth.name(forID: rawValue) ?? rawValue
    }

    /// The reason shared by `history` and the browser resolver.
    static let noFullDiskAccessReason = "Full Disk Access is off; Safari pages are recorded by site only"
    /// The reason of `device_events` when a fetch skipped records it can't read.
    static let otherAppVersionReason = "Some iPhone or iPad activity comes from another version of the app; update the app on every device"
    /// The reason of `synced_safari` without Full Disk Access.
    static let noSyncedSafariReason = "Full Disk Access is off; Safari on other devices can't be read"
}
