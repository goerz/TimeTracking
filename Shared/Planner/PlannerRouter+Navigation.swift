// PlannerRouter+Navigation: the View menu's commands shared by sections,
// and Timer › Continue on a Planner selection, acting on the section shown
// (spec_planner_projects.md §1.2, spec_timer_window.md §9).

import Foundation
import TimeTrackingCore

/// What Timer › Continue (⌘O) starts from a Planner selection.
enum PlannerContinueTarget: Equatable {
    /// The selected project in the projects table ("Start Timer").
    case project
    /// The one selected entry of the Calendar or the Reports entry list.
    case entry(EntryID)
}

extension PlannerRouter {
    /// View › Go to Today: the section shown.
    func goToToday() async {
        switch section {
        case .calendar:
            await calendar.goToToday()
        case .reports:
            await reports.goToToday()
        case .activity:
            activity.range.goToToday()
            await activity.reload()
        case .projects:
            projects.range.goToToday()
            await projects.reload()
        }
    }

    /// View › Previous Period and Next Period apply: the Calendar, or a
    /// range of Reports, Projects, or Activity that can move.
    var canShiftPeriod: Bool {
        switch section {
        case .calendar: true
        case .reports: reports.range.canShift
        case .activity: activity.range.canShift
        case .projects: projects.range.canShift
        }
    }

    /// View › Previous Period (`step` -1) and Next Period (1); in the
    /// Calendar by the visible span.
    func shiftPeriod(by step: Int) async {
        switch section {
        case .calendar:
            await calendar.shift(days: step * calendar.visibleDays)
        case .reports:
            if step < 0 {
                await reports.previousPeriod()
            } else {
                await reports.nextPeriod()
            }
        case .activity:
            await activity.shiftPeriod(by: step)
        case .projects:
            if step < 0 {
                projects.range.previous()
            } else {
                projects.range.next()
            }
            await projects.reload()
        }
    }

    /// The title of View › Date Range…: the Calendar picks a day.
    var dateRangeTitle: String {
        section == .calendar ? "Go to Date…" : "Date Range…"
    }

    /// View › Date Range…: the date popover of Reports, Projects, or
    /// Activity, the Calendar's month picker.
    func showDateRange() {
        switch section {
        case .calendar: calendar.showsMonthPicker = true
        case .reports: reports.showsDatePopover = true
        case .activity: activity.showsDatePopover = true
        case .projects: projects.showsDatePopover = true
        }
    }

    /// Timer › Continue in the section shown: the selected project or the
    /// one selected entry; nil when nothing selected can be started.
    var continueTarget: PlannerContinueTarget? {
        switch section {
        case .projects:
            return projects.canStartTimer ? .project : nil
        case .calendar:
            guard calendar.selection.count == 1, case let .entry(id) = calendar.selection.first else {
                return nil
            }
            return .entry(id)
        case .reports:
            guard reports.state.card == .entries, reports.listSelection.count == 1, let id = reports.listSelection.first else {
                return nil
            }
            return .entry(id)
        case .activity:
            return nil
        }
    }

    /// Starts the continue target; false when there is none.
    func continueSelection() async -> Bool {
        switch continueTarget {
        case .project:
            await projects.startTimerOnSelection()
        case let .entry(id):
            if section == .calendar {
                await calendar.continueEntry(id)
            } else {
                await reports.continueListing(id)
            }
        case nil:
            return false
        }
        return true
    }
}
