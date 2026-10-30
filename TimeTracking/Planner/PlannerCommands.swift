// PlannerCommands: the View, Project, Report, File, and Edit commands of the
// Planner (spec_planner_projects.md §1.2, §2.5; spec_planner_reports.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// Which Planner commands apply: sections while the Planner is key, the
/// Project menu while Projects shows its table, Report while Reports shows.
struct PlannerMenuState: Equatable {
    var plannerKey: Bool
    var section: PlannerSection
    var showsClientsAndAreas: Bool
    /// A popover, editor, or sheet of the Calendar takes the plain keys.
    var calendarEditing = false

    var calendarCommands: Bool {
        plannerKey && section == .calendar
    }

    /// Whether a Calendar command's menu item is enabled (plain keys only
    /// while nothing takes text input).
    func isEnabled(_ command: CalendarKeyCommand) -> Bool {
        calendarCommands && (command.shortcut.modifiers.contains(.command) || !calendarEditing)
    }

    /// Activity's range shortcuts and its submenu.
    var activityCommands: Bool {
        plannerKey && section == .activity
    }

    var sectionCommands: Bool {
        plannerKey
    }

    var projectCommands: Bool {
        plannerKey && section == .projects && !showsClientsAndAreas
    }

    var clientsAndAreasCommands: Bool {
        plannerKey && section == .projects && showsClientsAndAreas
    }

    var reportCommands: Bool {
        plannerKey && section == .reports
    }
}

/// The Planner's menu commands.
struct PlannerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: PlannerMenuState {
        PlannerMenuState(
            plannerKey: plannerActive ?? false,
            section: router?.section ?? .projects,
            showsClientsAndAreas: router?.projects.showsClientsAndAreas ?? false,
            calendarEditing: router?.calendar.takesTextInput ?? false
        )
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(before: .sidebar) {
            ForEach(PlannerSection.allCases) { section in
                Button(section.title) { router?.select(section) }
                    .keyboardShortcut(KeyEquivalent(section.key))
                    .disabled(!state.sectionCommands)
            }
            Button("Clients & Areas") { router?.showClientsAndAreas() }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(!state.sectionCommands)
            if state.reportCommands, let reports = router?.reports {
                ReportMenu(model: reports)
            }
            if state.calendarCommands, let calendar = router?.calendar {
                CalendarViewMenu(model: calendar, state: state)
            }
            if state.activityCommands, let activity = router?.activity {
                ActivityMenu(model: activity)
            }
            Divider()
        }
        CommandMenu("Entry") {
            if let calendar = router?.calendar {
                CalendarEntryItems(model: calendar, state: state)
            }
        }
        CommandMenu("Project") {
            if let projects = router?.projects {
                Button("New Project…") { projects.newProject() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .disabled(!state.projectCommands)
                ProjectMenuItems(model: projects, enabled: state.projectCommands)
                Divider()
                Button("New Client") { Task { await projects.clientsAndAreas.newClient() } }
                    .disabled(!state.clientsAndAreasCommands)
                Button("New Area…") { Task { await projects.clientsAndAreas.newArea() } }
                    .keyboardShortcut("n", modifiers: [.command, .option, .shift])
                    .disabled(!state.clientsAndAreasCommands || projects.clientsAndAreas.selectedClient == nil)
                AreaMoveItems(model: projects.clientsAndAreas, enabled: state.clientsAndAreasCommands)
            }
        }
        CommandGroup(after: .importExport) {
            if state.reportCommands, let reports = router?.reports {
                Button("Export…") { reports.requestExport() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        CommandGroup(replacing: .printItem) {
            if state.reportCommands, let reports = router?.reports {
                Button("Print…") { ReportPrinter.print(reports) }
                    .keyboardShortcut("p")
            }
        }
    }
}

/// The selection commands with their shortcuts.
private struct ProjectMenuItems: View {
    var model: ProjectsModel
    var enabled: Bool

    var body: some View {
        Button("Start Timer") { Task { await model.startTimerOnSelection() } }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!enabled || !model.canStartTimer)
        Button("Edit…") { model.editSelection() }
            .disabled(!enabled || model.single == nil)
        Button("Rename") { model.renaming = model.single?.id }
            .keyboardShortcut(.return, modifiers: .option)
            .disabled(!enabled || model.single == nil)
        Button(model.canArchive || !model.canRestore ? "Archive" : "Restore") {
            Task {
                if model.canArchive {
                    await model.archiveSelection()
                } else {
                    await model.restoreSelection()
                }
            }
        }
        .disabled(!enabled || !(model.canArchive || model.canRestore))
        Button("Merge Into…") { model.mergeSource = model.single?.id }
            .disabled(!enabled || model.single == nil)
        Button("Delete…") { model.requestDelete() }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!enabled || !model.canDelete)
        Button("Show in Reports") { Task { await model.showInReports() } }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!enabled || model.single == nil)
        Button("Copy Name") { model.router?.copyText(model.copyNames()) }
            .keyboardShortcut("c")
            .disabled(!enabled || model.selection.isEmpty)
    }
}

/// Move Up and Move Down in Clients & Areas.
private struct AreaMoveItems: View {
    var model: ClientsAreasModel
    var enabled: Bool

    private var area: AreaOutline? {
        if case let .area(id) = model.selection {
            return model.area(id)?.1
        }
        return nil
    }

    var body: some View {
        Button("Move Up") {
            if let id = area?.id {
                Task { await model.move(id, by: -1) }
            }
        }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(!enabled || !(area?.canMoveUp ?? false))
        Button("Move Down") {
            if let id = area?.id {
                Task { await model.move(id, by: 1) }
            }
        }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(!enabled || !(area?.canMoveDown ?? false))
    }
}

/// View › Report (spec_planner_reports.md §8).
private struct ReportMenu: View {
    var model: ReportsModel

    var body: some View {
        Menu("Report") {
            Button("Previous Period") { Task { await model.previousPeriod() } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Next Period") { Task { await model.nextPeriod() } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.range.canShift)
            Button("Go to Today") { Task { await model.goToToday() } }
                .keyboardShortcut("t")
            Button("Back to Previous Range") { Task { await model.backToPreviousRange() } }
                .keyboardShortcut("[")
                .disabled(model.previousRange == nil)
            Button("Date Range…") { model.showsDatePopover = true }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            ReportViewItems(model: model)
        }
    }
}

/// The Report submenu's filter, card, chart, and table commands.
private struct ReportViewItems: View {
    var model: ReportsModel

    var body: some View {
        Button("Filters…") { model.showsFilters = true }
            .keyboardShortcut("f", modifiers: [.command, .option])
        Button("Clear Filters") { Task { await model.clearFilters() } }
            .keyboardShortcut("f", modifiers: [.command, .option, .shift])
        Divider()
        Button("Show Breakdown") { Task { await model.show(.breakdown) } }
            .keyboardShortcut("1", modifiers: [.command, .control])
        Button("Show Entries") { Task { await model.show(.entries) } }
            .keyboardShortcut("2", modifiers: [.command, .control])
        Divider()
        Menu("Granularity") {
            Button("Automatic") { Task { await model.setGranularity(nil) } }
            ForEach([Granularity.day, .week, .month, .year], id: \.self) { granularity in
                Button(granularity.title) { Task { await model.setGranularity(granularity) } }
            }
        }
        Menu("Stack By") {
            ForEach(StackKind.allCases, id: \.self) { kind in
                Button(kind.title) { Task { await model.setStack(kind) } }
            }
        }
        Divider()
        Button("Expand All") { model.expandAll() }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        Button("Collapse All") { model.collapseAll() }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
    }
}
