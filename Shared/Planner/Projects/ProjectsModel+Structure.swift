// ProjectsModel+Structure: the Project menu's commands on the selected row of
// any kind, a project, an area, or a client (spec_planner_projects.md §2.5).

import Foundation
import TimeTrackingCore

extension ClientsAreasSelection {
    /// The table's row id, the group's collapse key.
    var rowID: String {
        switch self {
        case let .client(id): "client:\(id.rawValue)"
        case let .area(id): "area:\(id.rawValue)"
        }
    }

    init?(rowID: String) {
        if rowID.hasPrefix("client:"), let id = ClientID(String(rowID.dropFirst(7))) {
            self = .client(id)
        } else if rowID.hasPrefix("area:"), let id = AreaID(String(rowID.dropFirst(5))) {
            self = .area(id)
        } else {
            return nil
        }
    }
}

extension ProjectsModel {
    /// The selected client row's outline.
    var selectedClientRow: ClientOutline? {
        if case let .client(id) = clientsAndAreas.selection {
            return clientsAndAreas.client(id)
        }
        return nil
    }

    /// The selected area row's outline.
    var selectedAreaRow: AreaOutline? {
        if case let .area(id) = clientsAndAreas.selection {
            return clientsAndAreas.area(id)?.1
        }
        return nil
    }

    /// The client New Area… starts on: the selected client, the selected
    /// area's client, or the one selected project's client.
    var clientForNewArea: ClientID? {
        clientsAndAreas.selectedClient ?? single?.client?.id
    }

    /// ↩, double-click, and the Project menu's first item.
    var editSelectionTitle: String {
        switch clientsAndAreas.selection {
        case .client: "Rename Client…"
        case .area: "Edit Area…"
        case nil: "Edit Project…"
        }
    }

    var canEditSelection: Bool {
        clientsAndAreas.selection != nil || single != nil
    }

    /// Archive or Restore on projects, Retire or Reactivate on an area.
    var archiveSelectionTitle: String {
        if let area = selectedAreaRow {
            return area.area.isRetired ? "Reactivate Area" : "Retire Area"
        }
        return canArchive || !canRestore ? "Archive" : "Restore"
    }

    var canArchiveSelection: Bool {
        if let area = selectedAreaRow {
            return area.canRetire || area.canUnretire
        }
        return clientsAndAreas.selection == nil && (canArchive || canRestore)
    }

    func archiveOrRestoreSelection() async {
        if let area = selectedAreaRow {
            await clientsAndAreas.setRetired(area.id, !area.area.isRetired)
        } else if canArchive {
            await archiveSelection()
        } else if canRestore {
            await restoreSelection()
        }
    }

    /// Delete Project…, Delete Area…, or Remove Client….
    var deleteSelectionTitle: String {
        switch clientsAndAreas.selection {
        case .client: "Remove Client…"
        case .area: "Delete Area…"
        case nil: "Delete Project…"
        }
    }

    var canDeleteSelection: Bool {
        if let client = selectedClientRow {
            return client.canRemove
        }
        if let area = selectedAreaRow {
            return area.canDelete
        }
        return canDelete
    }

    /// Why Delete… is disabled, for its tooltip.
    var deleteSelectionTooltip: String? {
        selectedClientRow?.removeTooltip ?? selectedAreaRow?.deleteTooltip ?? deleteTooltip
    }

    func requestDeleteSelection() {
        switch clientsAndAreas.selection {
        case let .client(id): clientsAndAreas.requestRemove(id)
        case let .area(id): clientsAndAreas.requestDelete(id)
        case nil: requestDelete()
        }
    }

    /// Show in Reports: the project, area, or client as the only filter,
    /// All time.
    var canShowSelectionInReports: Bool {
        clientsAndAreas.selection != nil || single != nil
    }

    func showSelectionInReports() async {
        let filter: ReportFilters? = switch clientsAndAreas.selection {
        case let .client(id): ReportFilters(clients: [id])
        case let .area(id): ReportFilters(areas: [id])
        case nil: single.map { .project($0.id) }
        }
        if let filter {
            await router?.showReports(range: .preset(.allTime), filter: filter)
        }
    }

    /// Copy Name and ⌘C: the selected projects' names, or the selected
    /// client's or area's.
    func copySelectionNames() -> String {
        if let client = selectedClientRow {
            return client.client.name
        }
        if let area = selectedAreaRow {
            return area.area.name
        }
        return copyNames()
    }

    /// New Project… on an area or client row: the dialog in that area (a
    /// client's general area).
    func newProject(in row: ClientsAreasSelection) {
        switch row {
        case let .area(id):
            newProjectArea = id
        case let .client(id):
            newProjectArea = areas.first { $0.clientID == id && $0.isGeneral }?.id
        }
        dialog = ProjectDialogModel(store: store, mode: .create)
    }
}
