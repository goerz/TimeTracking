// The Activity section's "Exclude <name> from tracking…" draft in the
// Tracker pane (spec_planner_activity.md §4).

import Foundation
import TimeTrackingCore

/// An exclusion the pane shows unsaved and focused.
struct PendingExclusion: Equatable {
    var list: ExclusionList
    var value: String
}

extension TrackerSettingsModel {
    /// Prepares the draft; nothing is saved until the user adds it.
    func prepare(_ draft: TrackerExclusionDraft) {
        switch draft {
        case let .app(bundleIdentifier):
            pendingExclusion = PendingExclusion(list: .excludeApps, value: bundleIdentifier ?? "")
        case let .tmuxSession(name):
            pendingExclusion = PendingExclusion(list: .excludeTmuxSessions, value: name)
        case let .domain(domain):
            pendingExclusion = PendingExclusion(list: .excludeDomains, value: domain)
        }
    }

    /// The draft's Add button: adds it to its list (the pane's Save writes the file).
    func addPendingExclusion() {
        guard let pending = pendingExclusion, !pending.value.trimmed.isEmpty else {
            return
        }
        add(pending.value, to: pending.list)
        pendingExclusion = nil
    }
}
