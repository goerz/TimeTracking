// ProjectMenuContent: the Project menu's items, on the Mac and the iPad
// (spec_planner_projects.md §2.5, §4).

import SwiftUI
import TimeTrackingCore

/// The projects table's commands, or, while Clients & Areas shows, its own;
/// ⌥⌘N is New Project in the table and New Client in Clients & Areas.
/// Starting a timer on the selection is Timer › Start Timer (⌘O).
struct ProjectMenuContent: View {
    var model: ProjectsModel
    var state: MenuState

    var body: some View {
        if state.clientsAndAreasCommands {
            Button("New Client") { Task { await model.clientsAndAreas.newClient() } }
                .contextCommand(KeyboardShortcut("n", modifiers: [.command, .option]), enabled: true)
            Button("New Area…") { Task { await model.clientsAndAreas.newArea() } }
                .contextCommand(
                    KeyboardShortcut("n", modifiers: [.command, .option, .shift]),
                    enabled: model.clientsAndAreas.selectedClient != nil
                )
            Divider()
            AreaMoveItems(model: model.clientsAndAreas)
        } else if state.projectCommands {
            Button("New Project…") { model.newProject() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            ProjectSelectionItems(model: model)
        }
    }
}

/// The commands on the selected projects.
private struct ProjectSelectionItems: View {
    var model: ProjectsModel

    var body: some View {
        Button("Edit…") { model.editSelection() }
            .disabled(model.single == nil)
        Button("Rename") { model.renaming = model.single?.id }
            .contextCommand(KeyboardShortcut(.return, modifiers: .option), enabled: model.single != nil)
        Button(model.canArchive || !model.canRestore ? "Archive" : "Restore") {
            Task {
                if model.canArchive {
                    await model.archiveSelection()
                } else {
                    await model.restoreSelection()
                }
            }
        }
        .disabled(!(model.canArchive || model.canRestore))
        Button("Merge Into…") { model.mergeSource = model.single?.id }
            .disabled(model.single == nil)
        Button("Delete…") { model.requestDelete() }
            .contextCommand(KeyboardShortcut(.delete, modifiers: .command), enabled: model.canDelete)
        Divider()
        Button("Show in Reports") { Task { await model.showInReports() } }
            .contextCommand(KeyboardShortcut("r", modifiers: [.command, .shift]), enabled: model.single != nil)
        // On the Mac ⌘C is Edit › Copy, which copies the same names from the table.
        Button("Copy Name") { model.router?.copyText(model.copyNames()) }
            .disabled(model.selection.isEmpty)
    }
}

/// Move Up and Move Down in Clients & Areas.
private struct AreaMoveItems: View {
    var model: ClientsAreasModel

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
        .contextCommand(KeyboardShortcut(.upArrow, modifiers: [.command, .option]), enabled: area?.canMoveUp ?? false)
        Button("Move Down") {
            if let id = area?.id {
                Task { await model.move(id, by: 1) }
            }
        }
        .contextCommand(KeyboardShortcut(.downArrow, modifiers: [.command, .option]), enabled: area?.canMoveDown ?? false)
    }
}
