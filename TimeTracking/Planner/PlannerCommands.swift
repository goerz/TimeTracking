// PlannerCommands: the File menu's Export and Print and the Project menu
// (spec_planner_projects.md §2.5, §4; spec_planner_reports.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// The Planner's own menu commands; the View menu's are in `ViewCommands`.
struct PlannerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(host: host, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        CommandMenu("Project") {
            if let projects = router?.projects {
                Button("New Project…") { projects.newProject() }
                    .contextCommand(KeyboardShortcut("n", modifiers: [.command, .option]), enabled: state.projectCommands)
                ProjectMenuItems(model: projects, enabled: state.projectCommands)
                Divider()
                // ⌥⌘N is New Project in the table, New Client in Clients & Areas.
                Button("New Client") { Task { await projects.clientsAndAreas.newClient() } }
                    .contextCommand(KeyboardShortcut("n", modifiers: [.command, .option]), enabled: state.clientsAndAreasCommands)
                Button("New Area…") { Task { await projects.clientsAndAreas.newArea() } }
                    .contextCommand(
                        KeyboardShortcut("n", modifiers: [.command, .option, .shift]),
                        enabled: state.clientsAndAreasCommands && projects.clientsAndAreas.selectedClient != nil
                    )
                AreaMoveItems(model: projects.clientsAndAreas, enabled: state.clientsAndAreasCommands)
            }
        }
        CommandGroup(after: .importExport) {
            Button("Export…") { router?.reports.requestExport() }
                .contextCommand(KeyboardShortcut("e", modifiers: [.command, .shift]), enabled: state.reportCommands)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let reports = router?.reports {
                    ReportPrinter.print(reports)
                }
            }
            .contextCommand(KeyboardShortcut("p"), enabled: state.reportCommands)
        }
    }
}

/// The selection commands with their shortcuts.
private struct ProjectMenuItems: View {
    var model: ProjectsModel
    var enabled: Bool

    var body: some View {
        Button("Start Timer") { Task { await model.startTimerOnSelection() } }
            .contextCommand(KeyboardShortcut(.return, modifiers: .command), enabled: enabled && model.canStartTimer)
        Button("Edit…") { model.editSelection() }
            .disabled(!enabled || model.single == nil)
        Button("Rename") { model.renaming = model.single?.id }
            .contextCommand(KeyboardShortcut(.return, modifiers: .option), enabled: enabled && model.single != nil)
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
            .contextCommand(KeyboardShortcut(.delete, modifiers: .command), enabled: enabled && model.canDelete)
        Button("Show in Reports") { Task { await model.showInReports() } }
            .contextCommand(KeyboardShortcut("r", modifiers: [.command, .shift]), enabled: enabled && model.single != nil)
        // ⌘C is Edit › Copy, which copies the same names from the table.
        Button("Copy Name") { model.router?.copyText(model.copyNames()) }
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
        .contextCommand(KeyboardShortcut(.upArrow, modifiers: [.command, .option]), enabled: enabled && (area?.canMoveUp ?? false))
        Button("Move Down") {
            if let id = area?.id {
                Task { await model.move(id, by: 1) }
            }
        }
        .contextCommand(KeyboardShortcut(.downArrow, modifiers: [.command, .option]), enabled: enabled && (area?.canMoveDown ?? false))
    }
}
