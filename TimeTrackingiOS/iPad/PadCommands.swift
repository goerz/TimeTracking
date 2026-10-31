// PadCommands: the iPad's hardware-keyboard commands in the iPadOS menu
// bar and the ⌘-hold overlay (spec_ios.md §10.3). The Planner tabs add
// their own sections' keys (spec_planner_calendar.md §6,
// spec_planner_reports.md §8, spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

extension PadCommand {
    var title: String {
        switch self {
        case .timerTab: "Timer"
        case .projects, .calendar, .reports, .activity: plannerSection.title
        case .planner: "Last Planner Tab"
        case .clientsAndAreas: "Clients & Areas"
        case .new: "New Entry"
        case .continueLatest: "Continue Latest Entry"
        case .stop: "Stop"
        case .discard: "Discard Running Entry"
        case .setProject: "Set Project…"
        case .edit: "Edit Entry…"
        case .delete: "Delete Entry…"
        case .find: "Find"
        case .scrollToToday: "Scroll to Top"
        case .pomodoro: "Start or Cancel Pomodoro"
        case .nextPhase: "End Focus or Break Now"
        case .confirm: "Start Break or Focus"
        case .settings: "Settings…"
        case .today: "Go to Today"
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
        case .confirm: KeyboardShortcut(.return, modifiers: .command)
        case .settings: KeyboardShortcut(",")
        case .today: KeyboardShortcut("t")
        }
    }
}

/// The menu bar of the iPad (nothing on the iPhone).
struct PadCommands: Commands {
    var host: PhoneHost

    private var model: PhoneModel? {
        host.model.flatMap { $0.pad == nil ? nil : $0 }
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            item(.settings)
        }
        CommandGroup(replacing: .newItem) {
            item(.new)
        }
        CommandMenu("Timer") {
            ForEach([PadCommand.continueLatest, .stop, .discard], id: \.self, content: item)
            Divider()
            ForEach([PadCommand.setProject, .edit, .delete], id: \.self, content: item)
            Divider()
            ForEach([PadCommand.pomodoro, .nextPhase, .confirm], id: \.self, content: item)
        }
        CommandGroup(before: .sidebar) {
            ForEach([PadCommand.timerTab, .projects, .calendar, .reports, .activity, .planner, .clientsAndAreas], id: \.self, content: item)
            Divider()
            ForEach([PadCommand.find, .scrollToToday, .today], id: \.self, content: item)
            Divider()
            if let model, let router = model.pad?.router {
                sectionMenus(model: model, router: router)
            }
        }
    }

    private func item(_ command: PadCommand) -> some View {
        Button(command.title) {
            if let model {
                Task { await model.perform(command) }
            }
        }
        .keyboardShortcut(command.shortcut)
        .disabled(!(model?.isEnabled(command) ?? false))
    }

    /// The selected Planner tab's own keys.
    @ViewBuilder
    private func sectionMenus(model: PhoneModel, router: PlannerRouter) -> some View {
        switch model.padTab {
        case .calendar:
            PadCalendarMenu(model: router.calendar)
        case .reports:
            PadReportMenu(model: router.reports)
        case .activity:
            PadActivityMenu(model: router.activity)
        case .timer, .projects:
            EmptyView()
        }
    }
}

/// The Calendar's keys (⌘T is the shared Go to Today); plain keys only
/// while no popover, editor, or sheet takes text input.
private struct PadCalendarMenu: View {
    var model: CalendarModel

    var body: some View {
        Menu("Calendar") {
            ForEach(CalendarKeyCommand.allCases.filter { $0 != .today }) { command in
                Button(command.title) { Task { await model.perform(command) } }
                    .keyboardShortcut(command.shortcut)
                    .disabled(!command.shortcut.modifiers.contains(.command) && model.takesTextInput)
            }
        }
    }
}

/// View › Report: the period and range keys, filters, and cards.
private struct PadReportMenu: View {
    var model: ReportsModel

    var body: some View {
        Menu("Report") {
            Button("Previous Period") { Task { await model.previousPeriod() } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Next Period") { Task { await model.nextPeriod() } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Back to Previous Range") { Task { await model.backToPreviousRange() } }
                .keyboardShortcut("[")
                .disabled(model.previousRange == nil)
            Button("Date Range…") { model.showsDatePopover = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Filters…") { model.showsFilters = true }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Clear Filters") { Task { await model.clearFilters() } }
                .keyboardShortcut("f", modifiers: [.command, .option, .shift])
            Button("Show Breakdown") { Task { await model.show(.breakdown) } }
                .keyboardShortcut("1", modifiers: [.command, .control])
            Button("Show Entries") { Task { await model.show(.entries) } }
                .keyboardShortcut("2", modifiers: [.command, .control])
            Button("Export…") { model.requestExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}

/// View › Activity: the period keys and Escape.
private struct PadActivityMenu: View {
    var model: ActivityModel

    var body: some View {
        Menu("Activity") {
            Button("Previous Period") { Task { await model.shiftPeriod(by: -1) } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Next Period") { Task { await model.shiftPeriod(by: 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
        }
    }
}
