// SourceHealthBoard: the status of every source of §2.3 for current.json
// (activity_tracking.md §2.3, §4.4).

import TimeTrackingCore

/// The sources, their display names, and their current status and reason.
nonisolated struct SourceHealthBoard: Hashable, Sendable {
    private var entries: [SourceID: TrackerSourceHealth]

    init() {
        var initial: [SourceID: TrackerSourceHealth] = [:]
        for source in SourceID.allCases {
            initial[source] = TrackerSourceHealth(id: source.rawValue, name: source.name, status: .active)
        }
        // Until the first check of iCloud.
        initial[.deviceEvents]?.status = .fallback
        initial[.deviceEvents]?.reason = "Checking…"
        self.entries = initial
    }

    /// Sets a source's status; `reason` is cleared for `active`.
    mutating func set(_ id: SourceID, _ status: TrackerSourceStatus, _ reason: String = "") {
        entries[id]?.status = status
        entries[id]?.reason = status == .active ? "" : reason
    }

    func status(_ id: SourceID) -> TrackerSourceStatus? {
        entries[id]?.status
    }

    /// Every source in table order.
    var all: [TrackerSourceHealth] {
        SourceID.allCases.compactMap { entries[$0] }
    }
}
