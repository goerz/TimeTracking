// SourceHealthBoard: the status of every source of §3.5 for current.json
// (activity_tracking.md §3.5, §4.4).

import TimeTrackingCore

/// The sources, their display names, and their current status and reason.
nonisolated struct SourceHealthBoard: Hashable, Sendable {
    private var entries: [SourceID: TrackerSourceHealth]

    /// No source is listed before its first report, so nothing claims to work unchecked.
    init() {
        self.entries = [:]
    }

    /// Sets a source's status; `reason` is cleared for `active`.
    mutating func set(_ id: SourceID, _ status: TrackerSourceStatus, _ reason: String = "") {
        entries[id] = TrackerSourceHealth(id: id.rawValue, name: id.name, status: status, reason: status == .active ? "" : reason)
    }

    func status(_ id: SourceID) -> TrackerSourceStatus? {
        entries[id]?.status
    }

    /// The sources `current.json` lists, in table order: every source
    /// reported so far that the settings file doesn't turn off
    /// (`synced_safari` is off by default).
    func listed(settings: TrackerSettings) -> [TrackerSourceHealth] {
        SourceID.allCases.filter { $0 != .syncedSafari || settings.devices.syncedSafariHistory }.compactMap { entries[$0] }
    }
}
