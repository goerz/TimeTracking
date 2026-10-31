// PadCommands: the iPad's menu bar, also shown in the ⌘-hold overlay
// (spec_ios.md §10.3). It has the Mac's menus and items
// (spec_timer_window.md §9), built from the same shared pieces; the Timer
// tab stands in for the Mac's Timer window and the Planner tabs for its
// Planner window.

import SwiftUI
import TimeTrackingCore

extension PadCommand {
    var title: String {
        switch self {
        case .timerTab: "Timer"
        case .projects, .calendar, .reports, .activity: plannerSection.title
        case .planner: "Planner"
        case .clientsAndAreas: "Clients & Areas"
        case .new: "New"
        case .continueLatest: "Continue"
        case .stop: "Stop"
        case .discard: "Discard Running Entry"
        case .setProject: "Set Project…"
        case .edit: "Edit Entry…"
        case .delete: "Delete Entry…"
        case .find: "Find"
        case .scrollToToday: "Scroll to Today"
        case .pomodoro: "Start Pomodoro"
        case .nextPhase: PomodoroAction.endFocusNow.title
        case .settings: "Settings…"
        }
    }

    var shortcut: KeyboardShortcut {
        switch self {
        case .timerTab: KeyboardShortcut("r", modifiers: [.command, .option])
        case .projects, .calendar, .reports, .activity: KeyboardShortcut(KeyEquivalent(plannerSection.key))
        case .planner: KeyboardShortcut("p", modifiers: [.command, .option])
        case .clientsAndAreas: KeyboardShortcut("1", modifiers: [.command, .option])
        case .new: KeyboardShortcut("n")
        case .continueLatest: KeyboardShortcut("o")
        case .stop: KeyboardShortcut("s")
        case .discard: KeyboardShortcut(.delete, modifiers: [.command, .option])
        case .setProject: KeyboardShortcut("p")
        case .edit: KeyboardShortcut("e")
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        case .find: KeyboardShortcut("f")
        case .scrollToToday: KeyboardShortcut(.upArrow)
        case .pomodoro: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .nextPhase: KeyboardShortcut("p", modifiers: [.command, .control])
        case .settings: KeyboardShortcut(",")
        }
    }
}

/// The menu bar of the iPad (nothing on the iPhone).
struct PadCommands: Commands {
    var host: PhoneHost

    private var model: PhoneModel? {
        host.model.flatMap { $0.pad == nil ? nil : $0 }
    }

    private var router: PlannerRouter? {
        model?.pad?.router
    }

    private var state: MenuState {
        model?.padMenuState ?? MenuState()
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            item(.settings)
        }
        // Timer › New is ⌘N, as on the Mac.
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .importExport) {
            Button("Export…") { router?.reports.requestExport() }
                .contextCommand(KeyboardShortcut("e", modifiers: [.command, .shift]), enabled: state.reportCommands)
        }
        CommandGroup(after: .textEditing) {
            item(.find)
        }
        CommandGroup(before: .sidebar) {
            ForEach([PadCommand.timerTab, .projects, .calendar, .reports, .activity, .clientsAndAreas, .planner], id: \.self, content: item)
            Divider()
            if let router {
                PlannerNavigationItems(router: router, state: state)
            }
            Divider()
            item(.scrollToToday)
            Divider()
        }
        CommandMenu("Timer") {
            item(.new)
            Button(continueTitle) { run(.continueLatest) }
                .keyboardShortcut(PadCommand.continueLatest.shortcut)
                .disabled(!(model?.isEnabled(.continueLatest) ?? false))
            ForEach([PadCommand.stop, .discard], id: \.self, content: item)
            Divider()
            pomodoroItems
            Divider()
            ForEach([PadCommand.setProject, .edit, .delete], id: \.self, content: item)
        }
        // Named for the last Planner tab; its items are disabled in the Timer tab.
        CommandMenu(state.sectionMenuTitle) {
            if let router {
                SectionMenuContent(router: router, state: state)
            }
        }
    }

    /// "Start Timer" on a selected project, as on the Mac.
    private var continueTitle: String {
        state.plannerKey && router?.continueTarget == .project ? "Start Timer" : PadCommand.continueLatest.title
    }

    /// Start/Cancel Pomodoro, and the next step titled by what it does, as
    /// on the Mac.
    @ViewBuilder private var pomodoroItems: some View {
        Button(model?.pomodoro.state.isOn == true ? "Cancel Pomodoro" : PadCommand.pomodoro.title) { run(.pomodoro) }
            .keyboardShortcut(PadCommand.pomodoro.shortcut)
            .disabled(!(model?.isEnabled(.pomodoro) ?? false))
        Button(model?.pomodoro.pomodoro.nextPhaseAction?.title ?? PadCommand.nextPhase.title) { run(.nextPhase) }
            .keyboardShortcut(PadCommand.nextPhase.shortcut)
            .disabled(!(model?.isEnabled(.nextPhase) ?? false))
    }

    /// A command of the whole app keeps its key while disabled, as on the
    /// Mac; one of the Timer tab holds it only while enabled.
    @ViewBuilder
    private func item(_ command: PadCommand) -> some View {
        let enabled = model?.isEnabled(command) ?? false
        let button = Button(command.title) { run(command) }
        if command.isTimerTabOnly {
            button.contextCommand(command.shortcut, enabled: enabled)
        } else {
            button.keyboardShortcut(command.shortcut).disabled(!enabled)
        }
    }

    private func run(_ command: PadCommand) {
        if let model {
            Task { await model.perform(command) }
        }
    }
}
