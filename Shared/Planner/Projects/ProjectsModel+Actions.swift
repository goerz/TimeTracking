// ProjectsModel+Actions: the Projects section's commands and the project
// dialog's defaults (spec_planner_projects.md §2.5, §3.2).

import Foundation
import TimeTrackingCore

extension ProjectsModel {
    // MARK: Actions

    /// ⌘↩: an entry on the project with an empty task; the Planner stays key.
    func startTimerOnSelection() async {
        guard canStartTimer, let row = single else {
            return
        }
        await startTimer(row.id)
    }

    /// ⌫ on active rows; undoable.
    func archiveSelection() async {
        let ids = selectedRows.filter { !$0.project.isArchived }.map(\.id)
        await perform(name: "Archive") { store in
            for id in ids {
                try await store.archive(id)
            }
        } undo: { model in
            await model.restore(Set(ids), confirmed: true)
        }
    }

    /// ⌫ on archived rows; asks first when an area is retired.
    func restoreSelection() async {
        await restore(Set(selectedRows.filter(\.project.isArchived).map(\.id)), confirmed: false)
    }

    /// Restores projects; a retired area is named and reactivated after confirmation.
    func restore(_ ids: Set<ProjectID>, confirmed: Bool) async {
        let retired = Set(rows.filter { ids.contains($0.id) }.compactMap(\.area).filter(\.isRetired).map(\.name))
        if !confirmed, !retired.isEmpty {
            let names = retired.sorted().map { "“\($0)”" }.joined(separator: ", ")
            confirmation = PlannerConfirmation(
                title: "Restore and reactivate \(names)?",
                message: "The area \(names) is retired. Restoring makes it active again.",
                confirmTitle: "Restore",
                action: .restore(ids)
            )
            return
        }
        await perform(name: "Restore") { store in
            for id in ids {
                try await store.restoreProject(id)
            }
        } undo: { model in
            for id in ids {
                try? await model.store.archive(id)
            }
            await model.reload()
        }
    }

    /// Rename: ↩ commits; the name rules of the dialog apply; undoable.
    func rename(_ id: ProjectID, to name: String) async {
        renaming = nil
        guard let row = rows.first(where: { $0.id == id }), name.trimmed != row.project.name, !name.trimmed.isEmpty else {
            return
        }
        let old = row.project.name
        await perform(name: "Rename") { store in
            try await store.updateProject(id, ProjectChange(name: name))
        } undo: { model in
            try? await model.store.updateProject(id, ProjectChange(name: old))
            await model.reload()
        }
    }

    /// Delete… asks first; not undoable.
    func requestDelete() {
        guard canDelete, let row = single else {
            return
        }
        confirmation = PlannerConfirmation(
            title: "Delete “\(row.project.name)”?",
            message: "This cannot be undone.",
            confirmTitle: "Delete",
            action: .delete(row.id)
        )
    }

    /// Merge Into…: after the target was picked, asks first; not undoable.
    func requestMerge(into target: ProjectID) {
        guard let source = mergeSource, let row = rows.first(where: { $0.id == source }),
              let other = rows.first(where: { $0.id == target }), source != target
        else {
            return
        }
        mergeSource = nil
        let count = "\(row.entryCount) \(row.entryCount == 1 ? "entry" : "entries")"
        confirmation = PlannerConfirmation(
            title: "Move \(count) of “\(row.project.name)” to “\(other.project.name)” and delete “\(row.project.name)”?",
            message: "This cannot be undone.",
            confirmTitle: "Merge",
            action: .merge(source, into: target)
        )
    }

    /// The alert's confirm button.
    func confirm() async {
        guard let confirmation else {
            return
        }
        self.confirmation = nil
        switch confirmation.action {
        case let .restore(ids):
            await restore(ids, confirmed: true)
        case let .delete(id):
            await perform(name: nil) { store in try await store.deleteProject(id) }
        case let .merge(source, target):
            await perform(name: nil) { store in try await store.merge(project: source, into: target) }
            selection = [target]
        }
    }

    /// Show in Reports: this project as the only filter, All time.
    func showInReports() async {
        guard let row = single else {
            return
        }
        await router?.showReports(range: .preset(.allTime), filter: .project(row.id))
    }

    /// ⌘C: the selected names, one per line, in table order.
    func copyNames() -> String {
        table.rows.filter { selection.contains($0.id) }.map(\.row.project.name).joined(separator: "\n")
    }

    // MARK: Dialog

    /// The default area of a new project (§3.2): the area or client row it
    /// was created from or that is selected, the one selected project's
    /// area, the one client or area the filters restrict to; else the
    /// dialog's own rule.
    var dialogDefaultArea: AreaID? {
        if let area = newProjectArea {
            return area
        }
        switch clientsAndAreas.selection {
        case let .area(id):
            return id
        case let .client(id):
            return areas.first { $0.clientID == id && $0.isGeneral }?.id
        case nil:
            break
        }
        if let row = single, row.area != nil {
            return row.project.areaID
        }
        if options.clients.count == 1, options.areas.isEmpty, let client = options.clients.first {
            return areas.first { $0.clientID == client && $0.isGeneral }?.id
        }
        if options.areas.count == 1, options.clients.isEmpty {
            return options.areas.first
        }
        return nil
    }

    /// ⌥⌘N.
    func newProject() {
        newProjectArea = nil
        dialog = ProjectDialogModel(store: store, mode: .create)
    }

    /// Edit… (↩, double-click): the project's dialog, the area's sheet, or
    /// the client's rename sheet.
    func editSelection() {
        if clientsAndAreas.selection != nil {
            clientsAndAreas.editSelection()
            return
        }
        guard let row = single else {
            return
        }
        let dialog = ProjectDialogModel(store: store, mode: .edit(row.project))
        dialog.undoManager = undoManager
        self.dialog = dialog
    }

    /// The dialog closed.
    func dialogFinished(_ project: Project?) async {
        dialog = nil
        newProjectArea = nil
        await reload()
        if let project {
            selection = [project.id]
            scrollTarget = project.id
        }
    }
}
