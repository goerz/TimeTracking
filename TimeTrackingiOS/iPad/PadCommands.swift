// PadCommands: the iPad's menu bar, also shown in the ⌘-hold overlay
// (spec_ios.md §10.3; experiment: the Mac's object menus, built from the
// same shared items). The tabs are the Mac's sidebar items.

import SwiftUI
import TimeTrackingCore

extension PadCommand {
    var title: String {
        switch self {
        case .timerTab: "Timer"
        case .projects, .calendar, .reports, .activity: plannerSection.title
        case .planner: "Planner"
        case .clientsAndAreas: "Clients & Areas"
        case .new: "New Entry"
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
        case .timerTab: KeyboardShortcut("1")
        case .projects, .calendar, .reports, .activity: KeyboardShortcut(plannerSection.mainWindowKey)
        case .planner: KeyboardShortcut("p", modifiers: [.command, .option])
        case .clientsAndAreas: KeyboardShortcut("2", modifiers: [.command, .option])
        case .new: KeyboardShortcut("n")
        case .continueLatest: KeyboardShortcut("o")
        case .stop: KeyboardShortcut("s")
        case .discard: KeyboardShortcut(.delete, modifiers: [.command, .option])
        case .setProject: KeyboardShortcut("j")
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
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                router?.select(.projects)
                router?.projects.showsClientsAndAreas = false
                router?.projects.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(router == nil)
            Button("New Client") {
                router?.showClientsAndAreas()
                if let router {
                    Task { await router.projects.clientsAndAreas.newClient() }
                }
            }
            .disabled(router == nil)
            Button("New Area…") {
                if let router {
                    Task { await router.projects.clientsAndAreas.newArea() }
                }
            }
            .contextCommand(
                KeyboardShortcut("n", modifiers: [.command, .option, .shift]),
                enabled: state.clientsAndAreasCommands && router?.projects.clientsAndAreas.selectedClient != nil
            )
        }
        CommandGroup(after: .importExport) {
            Button("Export…") { router?.reports.requestExport() }
                .contextCommand(KeyboardShortcut("e", modifiers: [.command, .shift]), enabled: state.reportCommands)
        }
        CommandGroup(after: .textEditing) {
            item(.find)
        }
        CommandGroup(before: .sidebar) {
            ForEach([PadCommand.timerTab, .projects, .calendar, .reports, .activity, .clientsAndAreas], id: \.self, content: item)
            Divider()
            if let router {
                ViewDisplayItems(router: router, state: state) { run(.scrollToToday) }
            }
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
        }
        CommandMenu("Entry") {
            if let router {
                EntryMenuItems(router: router, state: state, timer: TimerEntryActions(
                    setProject: { run(.setProject) },
                    edit: { run(.edit) },
                    delete: { run(.delete) },
                    canDelete: model?.isEnabled(.delete) ?? false
                ))
            }
        }
        CommandMenu("Project") {
            if let router {
                ProjectMenuContent(model: router.projects, state: state)
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
