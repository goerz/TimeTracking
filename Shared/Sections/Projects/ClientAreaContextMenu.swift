// ClientAreaContextMenu: the context menu of a client or area row in the
// projects table (projects.md §4.2, §4.3).

import SwiftUI
import TimeTrackingCore

/// A client's Rename…, New Area…, New Project…, Show in Reports, Remove…;
/// an area's Edit…, New Project…, Move Up and Down, Retire or Reactivate,
/// Show in Reports, Delete….
struct ClientAreaContextMenu: View {
    var model: ProjectsModel
    var row: ClientsAreasSelection

    private var areas: ClientsAreasModel {
        model.clientsAndAreas
    }

    var body: some View {
        switch row {
        case let .client(id):
            if let client = areas.client(id) {
                Button("Rename…") { areas.renameClient(id) }
                Button("New Area…") { Task { await areas.newArea(in: id) } }
                Button("New Project…") { model.newProject(in: row) }
                Divider()
                Button("Show in Reports") { showInReports(ReportFilters(clients: [id])) }
                Divider()
                Button("Remove…") { areas.requestRemove(id) }
                    .disabled(!client.canRemove)
                    .help(client.removeTooltip ?? "")
            }
        case let .area(id):
            if let (_, area) = areas.area(id) {
                Button("Edit…") { areas.editArea(id) }
                Button("New Project…") { model.newProject(in: row) }
                Divider()
                Button("Move Up") { Task { await areas.move(id, by: -1) } }
                    .disabled(!area.canMoveUp)
                Button("Move Down") { Task { await areas.move(id, by: 1) } }
                    .disabled(!area.canMoveDown)
                if area.area.isRetired {
                    Button("Reactivate") { Task { await areas.setRetired(id, false) } }
                } else if !area.area.isGeneral {
                    Button("Retire") { Task { await areas.setRetired(id, true) } }
                        .disabled(!area.canRetire)
                }
                Divider()
                Button("Show in Reports") { showInReports(ReportFilters(areas: [id])) }
                if !area.area.isGeneral {
                    Divider()
                    Button("Delete…") { areas.requestDelete(id) }
                        .disabled(!area.canDelete)
                        .help(area.deleteTooltip ?? "")
                }
            }
        }
    }

    private func showInReports(_ filter: ReportFilters) {
        Task { await model.router?.showReports(range: .preset(.allTime), filter: filter) }
    }
}
