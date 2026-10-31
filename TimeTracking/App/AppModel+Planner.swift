// The Mac's wiring of the Planner's Calendar and Activity sections
// (spec_planner_calendar.md §3.4, spec_planner_activity.md §1.10).

import Foundation
import TimeTrackingCore

extension AppModel {
    /// The Planner window appeared.
    func plannerOpened() {
        plannerIsOpen = true
        planner.activity.plannerReopened()
    }

    /// The Planner window closed: its undo stack goes with it.
    func plannerClosed() {
        plannerIsOpen = false
        planner.projects.undoManager?.removeAllActions()
        planner.calendar.undoManager?.removeAllActions()
    }

    /// The tracker agent, the Timer, and the tracker status for Calendar and Activity.
    func wirePlannerSections(trackerCommands: TrackerCommandSending) {
        planner.openTrackerSettings = { [weak self] draft in
            if let draft {
                self?.trackerSettings.prepare(draft)
            }
            self?.router?.openSettings(pane: .tracker)
        }
        let calendar = planner.calendar
        calendar.sendTrackerCommand = { command in
            switch await trackerCommands.send(command) {
            case .accepted: nil
            case let .rejected(reason): reason
            }
        }
        calendar.openEvent = { event in CalendarApp.open(event) }
        if let identity = AppIdentity.main {
            calendar.urlScheme = identity.urlScheme
        }
        let activity = planner.activity
        activity.registration = { [weak self] in
            await self?.tracker.refresh()
            return self?.tracker.registration ?? .notRegistered
        }
        activity.trackerSetUp = { [weak self] in
            guard let self else {
                return false
            }
            return tracker.registration == .enabled && tracker.state != nil
        }
        activity.appName = { InstalledApps.name(forBundleIdentifier: $0) }
    }
}
