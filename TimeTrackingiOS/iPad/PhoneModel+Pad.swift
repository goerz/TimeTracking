// PhoneModel+Pad: the iPad's tab selection, its hardware-keyboard commands,
// and the Planner's links to the Timer (spec_ios.md §2.3, §6.4, §10.1, §10.3).

import Foundation
import TimeTrackingCore

/// A hardware-keyboard command of the iPad outside the Planner tabs' own
/// keys (spec_ios.md §10.3).
enum PadCommand: Hashable, CaseIterable {
    /// ⌘1: the Timer tab with the task field focused.
    case timerTab
    /// ⌘2 to ⌘5, after the Timer's ⌘1.
    case calendar, reports, projects, activity
    /// ⌥⌘P: the most recently selected Planner tab.
    case planner
    /// ⌘N, ⌘O, ⌘S, ⌥⌘⌫.
    case new, continueLatest, stop, discard
    /// ⌘P, ⌘E, ⌘⌫, ⌘↑ (Timer tab only).
    case setProject, edit, delete, scrollToToday
    /// ⌘F: the Timer list's filter, the Projects and Reports search.
    case find
    /// ⇧⌘P, ⌃⌘P.
    case pomodoro, nextPhase
    /// ⌘,
    case settings

    /// The commands that act only in some tabs; their menu items hold their
    /// keys only while enabled (spec_timer_window.md §9).
    var isTimerTabOnly: Bool {
        switch self {
        case .setProject, .edit, .delete, .find, .scrollToToday: true
        default: false
        }
    }
}

extension PhoneModel {
    /// The Planner's sections select tabs; its writes reach the Timer and
    /// the fan-out as the Timer's own.
    func wirePad() {
        guard let router = pad?.router else {
            return
        }
        router.sectionChanged = { [weak self] section in
            guard let self, padTab.section != section else {
                return
            }
            padTab = PadTab(section)
        }
        router.wireTimer(timer) { [weak self] in await self?.localWrite() }
        router.copyText = { Clipboard.copy($0) }
        router.calendar.openEvent = { CalendarLink.open($0.start) }
        if let identity = AppIdentity.main {
            router.calendar.urlScheme = identity.urlScheme
        }
    }

    /// The tab ⌥⌘P selects: the most recent Planner tab, Projects at first.
    var lastPlannerTab: PadTab {
        PadTab(pad?.router.section ?? .projects)
    }

    /// The Mac activity line: on the iPad it opens the Activity tab.
    func macActivityTapped() {
        guard pad != nil else {
            return
        }
        padTab = .activity
    }

    /// Whether a keyboard command acts in the selected tab.
    func isEnabled(_ command: PadCommand) -> Bool {
        guard pad != nil else {
            return false
        }
        switch command {
        case .find:
            return padMenuState.findCommand
        case .delete:
            return padTab == .timer && list.selection != nil
        case .continueLatest:
            return timer.mostRecentOther != nil || (padTab != .timer && pad?.router.continueTarget != nil)
        case .stop, .discard:
            return timer.isRunning
        case .pomodoro:
            return pomodoro.state.isOn || timer.isRunning
        case .nextPhase:
            return pomodoro.pomodoro.nextPhaseAction != nil
        default:
            return !command.isTimerTabOnly || padTab == .timer
        }
    }

    /// Performs a keyboard command; one that does not apply does nothing.
    func perform(_ command: PadCommand) async { // swiftlint:disable:this cyclomatic_complexity
        guard isEnabled(command), let pad else {
            return
        }
        switch command {
        case .timerTab:
            padTab = .timer
            timer.requestTaskFieldFocus()
        case .calendar, .reports, .projects, .activity:
            padTab = PadTab(command.plannerSection)
        case .planner:
            padTab = lastPlannerTab
        case .new:
            padTab = .timer
            await timer.new()
        case .continueLatest:
            // A Planner tab's selected project or entry, else the latest entry.
            let started = padTab != .timer ? await pad.router.continueSelection() : false
            if !started {
                await timer.continueEntry()
            }
        case .stop:
            await timer.stop()
        case .discard:
            await timer.requestDiscard(skipAlert: false)
        case .pomodoro:
            pomodoro.perform(pomodoro.state.isOn ? .cancel : .start, isRunning: timer.isRunning)
        case .nextPhase:
            if let action = pomodoro.pomodoro.nextPhaseAction {
                pomodoro.perform(action, isRunning: timer.isRunning)
            }
        case .settings:
            padTab = .timer
            sheet = .settings
        case .find:
            find(in: pad.router)
        default:
            performTimerTab(command)
        }
        if timer.alert != nil {
            // Discard, restore, and delete ask on the Timer tab.
            padTab = .timer
        }
    }

    private func performTimerTab(_ command: PadCommand) {
        switch command {
        case .setProject:
            openPicker()
        case .edit:
            if let id = list.selection ?? timer.running?.id {
                openEditor(id)
            }
        case .delete:
            timer.alert = list.deleteAlert()
        case .scrollToToday:
            list.scrollToTop()
        default:
            break
        }
    }

    /// The main menu's context: the Timer tab stands in for the Mac's Timer
    /// window, a Planner tab for its Planner window.
    var padMenuState: MenuState {
        MenuState(router: pad?.router, timerKey: padTab == .timer, plannerKey: padTab != .timer)
    }

    /// ⌘F: the Timer list's filter, or the Projects or Reports search.
    private func find(in router: PlannerRouter) {
        switch padTab {
        case .timer: list.showFilter()
        case .projects: router.projects.focusSearch()
        case .reports: router.reports.focusTaskFilter()
        case .calendar, .activity: break
        }
    }
}

extension PadCommand {
    /// The section of ⌘2 to ⌘5 (Projects for the other commands).
    var plannerSection: PlannerSection {
        switch self {
        case .calendar: .calendar
        case .reports: .reports
        case .activity: .activity
        default: .projects
        }
    }
}
