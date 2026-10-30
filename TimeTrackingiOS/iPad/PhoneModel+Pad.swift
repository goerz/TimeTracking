// PhoneModel+Pad: the iPad's tab selection, its hardware-keyboard commands,
// and the Planner's links to the Timer (spec_ios.md §2.3, §6.4, §10.1, §10.3).

import Foundation
import TimeTrackingCore

/// A hardware-keyboard command of the iPad outside the Planner tabs' own
/// keys (spec_ios.md §10.3).
enum PadCommand: Hashable, CaseIterable {
    /// ⌥⌘R: the Timer tab with the task field focused.
    case timerTab
    /// ⌘1 to ⌘4.
    case projects, calendar, reports, activity
    /// ⌥⌘P: the most recently selected Planner tab.
    case planner
    /// ⌥⌘1.
    case clientsAndAreas
    /// ⌘N, ⌘O, ⌘S, ⌥⌘⌫.
    case new, continueLatest, stop, discard
    /// ⌘P, ⌘E, ⌘⌫, ⌘F, ⌘↑ (Timer tab only).
    case setProject, edit, delete, find, scrollToToday
    /// ⇧⌘P, ⌃⌘P, ⌘↩.
    case pomodoro, nextPhase, confirm
    /// ⌘,
    case settings
    /// ⌘T: Go to Today in Calendar, Reports, and Activity.
    case today

    /// The commands that act only while the Timer tab shows.
    var isTimerTabOnly: Bool {
        switch self {
        case .setProject, .edit, .delete, .find, .scrollToToday: true
        default: false
        }
    }
}

extension PadTab {
    /// The tab of a Planner section.
    init(_ section: PlannerSection) {
        switch section {
        case .projects: self = .projects
        case .calendar: self = .calendar
        case .reports: self = .reports
        case .activity: self = .activity
        }
    }

    /// The Planner section of the tab; `nil` for the Timer.
    var section: PlannerSection? {
        switch self {
        case .timer: nil
        case .projects: .projects
        case .calendar: .calendar
        case .reports: .reports
        case .activity: .activity
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
        router.projects.startTimer = { [weak self] id in
            guard let self else {
                return
            }
            do {
                _ = try await store.start(projectID: id, task: "", at: clock.now)
            } catch {
                timer.report(error)
            }
            await localWrite()
        }
        router.reports.continueEntry = { [weak self] id in await self?.timer.continueEntry(id) }
        router.reports.entriesChanged = { [weak self] in await self?.localWrite() }
        router.calendar.entriesChanged = { [weak self] in await self?.localWrite() }
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
        case .today:
            return [.calendar, .reports, .activity].contains(padTab)
        case .continueLatest:
            return timer.mostRecentOther != nil
        case .stop, .discard:
            return timer.isRunning
        case .pomodoro:
            return pomodoro.state.isOn || timer.isRunning
        case .nextPhase:
            return pomodoro.pomodoro.nextPhaseAction != nil
        case .confirm:
            return pomodoro.state.isPendingConfirmation
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
        case .projects, .calendar, .reports, .activity:
            padTab = PadTab(command.plannerSection)
        case .planner:
            padTab = lastPlannerTab
        case .clientsAndAreas:
            pad.router.showClientsAndAreas()
        case .new:
            padTab = .timer
            await timer.new()
        case .continueLatest:
            await timer.continueEntry()
        case .stop:
            await timer.stop()
        case .discard:
            await timer.requestDiscard(skipAlert: false)
        case .pomodoro:
            pomodoro.perform(pomodoro.state.isOn ? .cancel : .start, isRunning: timer.isRunning)
        case .nextPhase, .confirm:
            if let action = pomodoro.pomodoro.nextPhaseAction {
                pomodoro.perform(action, isRunning: timer.isRunning)
            }
        case .settings:
            padTab = .timer
            sheet = .settings
        case .today:
            await goToToday(in: pad.router)
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
        case .find:
            list.showFilter()
        case .scrollToToday:
            list.scrollToTop()
        default:
            break
        }
    }

    private func goToToday(in router: PlannerRouter) async {
        switch padTab {
        case .calendar:
            await router.calendar.goToToday()
        case .reports:
            await router.reports.goToToday()
        case .activity:
            router.range.goToToday()
            await router.activity.reload()
        case .timer, .projects:
            break
        }
    }
}

extension PadCommand {
    /// The section of ⌘1 to ⌘4 (Projects for the other commands).
    var plannerSection: PlannerSection {
        switch self {
        case .calendar: .calendar
        case .reports: .reports
        case .activity: .activity
        default: .projects
        }
    }
}
