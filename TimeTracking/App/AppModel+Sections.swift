// The Mac's main window and its wiring of the Calendar and Activity sections
// (calendar.md §3.4, activity.md §1.10).

import Foundation
import TimeTrackingCore

extension AppModel {
    /// The main window's sidebar item: the Timer or the router's section.
    var mainItem: MainSidebarItem {
        get {
            showsTimer ? .timer : .section(sections.section)
        }
        set {
            switch newValue {
            case .timer:
                showsTimer = true
            case let .section(section):
                showsTimer = false
                sections.select(section)
            }
        }
    }

    /// The main window appeared.
    func mainWindowOpened() {
        mainWindowIsOpen = true
        openWindows.opened(.mainWindow)
        sections.activity.mainWindowReopened()
    }

    /// The main window closed: its undo stacks go with it.
    func mainWindowClosed() {
        mainWindowIsOpen = false
        openWindows.closed(.mainWindow)
        sections.projects.undoManager?.removeAllActions()
        sections.calendar.undoManager?.removeAllActions()
    }

    /// The tracker agent, the Timer, and the tracker status for Calendar and Activity.
    func wireSections(trackerCommands: TrackerCommandSending) {
        sections.openTrackerSettings = { [weak self] draft in
            if let draft {
                self?.trackerSettings.prepare(draft)
            }
            self?.router?.openSettings(pane: .tracker)
        }
        let calendar = sections.calendar
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
        let activity = sections.activity
        activity.registration = { [weak self] in
            await self?.tracker.refresh()
            return self?.tracker.registration ?? .notRegistered
        }
        activity.trackerSetUp = { [weak self] in
            guard let self else {
                return false
            }
            return ActivityEmptyState.trackerSetUp(registration: tracker.registration, state: tracker.state)
        }
    }
}
