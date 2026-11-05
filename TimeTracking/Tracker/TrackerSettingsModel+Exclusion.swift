// The Activity section's "Exclude <name> from tracking…" draft in the
// Tracker pane, and the exclusion lists of settings.toml
// (activity.md §4, activity_tracking.md §7.2).

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
        lastAdded = nil
        switch draft {
        case let .app(bundleIdentifier):
            pendingExclusion = PendingExclusion(list: .excludeApps, value: bundleIdentifier ?? "")
        case let .tmuxSession(name):
            pendingExclusion = PendingExclusion(list: .excludeTmuxSessions, value: name)
        case let .domain(domain):
            pendingExclusion = PendingExclusion(list: .excludeDomains, value: domain)
        }
    }
}

extension TrackerPrivacySettings {
    /// The entries of one exclusion list.
    func list(_ list: ExclusionList) -> [String] {
        switch list {
        case .excludePaths: excludePaths
        case .excludeKeywords: excludeKeywords
        case .excludeTmuxSessions: excludeTmuxSessions
        case .privateAgentPaths: privateAgentPaths
        case .nameOnlyApps: nameOnlyApps
        case .excludeApps: excludeApps
        case .privateDomains: privateDomains
        case .excludeDomains: excludeDomains
        case .excludeTitleKeywords: excludeTitleKeywords
        }
    }
}
