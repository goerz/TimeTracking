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
        if state.showsClientsAndAreas {
            let enabled = state.clientsAndAreasCommands
            Button("New Client") { Task { await model.clientsAndAreas.newClient() } }
                .contextCommand(KeyboardShortcut("n", modifiers: [.command, .option]), enabled: enabled)
            Button("New Area…") { Task { await model.clientsAndAreas.newArea() } }
                .contextCommand(
                    KeyboardShortcut("n", modifiers: [.command, .option, .shift]),
                    enabled: enabled && model.clientsAndAreas.selectedClient != nil
                )
            Divider()
            AreaMoveItems(model: model.clientsAndAreas, enabled: enabled)
        } else {
            Button("New Project…") { model.newProject() }
                .contextCommand(KeyboardShortcut("n", modifiers: [.command, .option]), enabled: state.projectCommands)
            Divider()
            ProjectSelectionItems(model: model, enabled: state.projectCommands)
        }
    }
}

/// The commands on the selected projects.
private struct ProjectSelectionItems: View {
    var model: ProjectsModel
    var enabled: Bool

    var body: some View {
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
        Divider()
        Button("Show in Reports") { Task { await model.showInReports() } }
            .contextCommand(KeyboardShortcut("r", modifiers: [.command, .shift]), enabled: enabled && model.single != nil)
        // On the Mac ⌘C is Edit › Copy, which copies the same names from the table.
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
