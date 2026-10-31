// AppShortcutsUpdater: App Shortcut parameters, Spotlight, and intent
// donations (spec_ios.md §6.1, §6.2).

import AppIntents
import CoreSpotlight
import Foundation
import TimeTrackingCore

/// Updates the App Shortcut parameters and indexes projects for Spotlight.
final class AppShortcutsUpdater: ShortcutsUpdating {
    func projectsChanged(_ projects: [ProjectRow]) {
        TimeTrackingShortcuts.updateAppShortcutParameters()
        let entities = projects.filter { !$0.project.isArchived }.map(ProjectEntity.init)
        Task {
            try? await CSSearchableIndex.default().indexAppEntities(entities)
        }
    }

    func donate(_ entry: TimeEntry) {
        let intent = StartTimerIntent()
        intent.task = entry.task
        Task {
            _ = try? await IntentDonationManager.shared.donate(intent: intent)
        }
    }
}
