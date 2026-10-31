// ProjectMenuContent: the Project menu, on the Mac and the iPad (experiment:
// object menus; spec_planner_projects.md §2.5, §4).

import SwiftUI
import TimeTrackingCore

/// Commands on the selected projects of the Projects view, then on the
/// selected area in Clients & Areas. New Project, Client, and Area are in
/// File; starting a timer on a project is Timer › Start Timer (⌘O).
struct ProjectMenuContent: View {
    var model: ProjectsModel
    var state: MenuState

    var body: some View {
        ProjectSelectionItems(model: model, enabled: state.projectCommands)
        Divider()
        AreaMoveItems(model: model.clientsAndAreas, enabled: state.clientsAndAreasCommands)
    }
}

/// The commands on the selected projects.
private struct ProjectSelectionItems: View {
    var model: ProjectsModel
    var enabled: Bool

    var body: some View {
        Button("Edit Project…") { model.editSelection() }
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
        Button("Delete Project…") { model.requestDelete() }
            .contextCommand(KeyboardShortcut(.delete, modifiers: .command), enabled: enabled && model.canDelete)
        Divider()
        Button("Show in Reports") { Task { await model.showInReports() } }
            .contextCommand(KeyboardShortcut("r", modifiers: [.command, .shift]), enabled: enabled && model.single != nil)
        // On the Mac ⌘C is Edit › Copy, which copies the same names from the table.
        Button("Copy Name") { model.router?.copyText(model.copyNames()) }
            .disabled(!enabled || model.selection.isEmpty)
    }
}

/// Move Up and Move Down of the selected area in Clients & Areas.
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
        Button("Move Area Up") {
            if let id = area?.id {
                Task { await model.move(id, by: -1) }
            }
        }
        .contextCommand(KeyboardShortcut(.upArrow, modifiers: [.command, .option]), enabled: enabled && (area?.canMoveUp ?? false))
        Button("Move Area Down") {
            if let id = area?.id {
                Task { await model.move(id, by: 1) }
            }
        }
        .contextCommand(KeyboardShortcut(.downArrow, modifiers: [.command, .option]), enabled: enabled && (area?.canMoveDown ?? false))
    }
}
