// ProjectMenuContent: the Project menu, on the Mac and the iPad
// (spec_timer_window.md §9; spec_projects.md §2.5, §4).

import SwiftUI
import TimeTrackingCore

/// Commands on the selected row of the projects table: projects, or one
/// area or client, each item titled for what it acts on. New Project, Area,
/// and Client are in File; starting a timer on a project is Timer › Start
/// Timer (⌘O).
struct ProjectMenuContent: View {
    var model: ProjectsModel
    var state: MenuState

    private var enabled: Bool {
        state.projectCommands
    }

    var body: some View {
        Button(model.editSelectionTitle) { model.editSelection() }
            .disabled(!enabled || !model.canEditSelection)
        Button("Rename") { model.renaming = model.single?.id }
            .contextCommand(KeyboardShortcut(.return, modifiers: .option), enabled: enabled && model.single != nil)
        Button(model.archiveSelectionTitle) { Task { await model.archiveOrRestoreSelection() } }
            .disabled(!enabled || !model.canArchiveSelection)
        Button("Merge Into…") { model.mergeSource = model.single?.id }
            .disabled(!enabled || model.single == nil)
        Button(model.deleteSelectionTitle) { model.requestDeleteSelection() }
            .contextCommand(KeyboardShortcut(.delete, modifiers: .command), enabled: enabled && model.canDeleteSelection)
        Divider()
        Button("Show in Reports") { Task { await model.showSelectionInReports() } }
            .contextCommand(KeyboardShortcut("r", modifiers: [.command, .shift]), enabled: enabled && model.canShowSelectionInReports)
        // On the Mac ⌘C is Edit › Copy, which copies the same names from the table.
        Button("Copy Name") { model.router?.copyText(model.copySelectionNames()) }
            .disabled(!enabled || model.copySelectionNames().isEmpty)
        Divider()
        AreaMoveItems(model: model.clientsAndAreas, area: model.selectedAreaRow, enabled: enabled)
    }
}

/// Move Up and Move Down of the selected area row.
private struct AreaMoveItems: View {
    var model: ClientsAreasModel
    var area: AreaOutline?
    var enabled: Bool

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
