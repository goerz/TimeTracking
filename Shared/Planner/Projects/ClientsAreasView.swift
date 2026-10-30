// ClientsAreasView: clients alphabetically, each with its areas in order
// and "+ Add Area" (spec_planner_projects.md §4; mockups/planner_clients_areas.png).

import SwiftUI
import TimeTrackingCore

/// The outline that replaces the projects table.
struct ClientsAreasView: View {
    @Bindable var model: ClientsAreasModel
    var projects: ProjectsModel

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.outline) { client in
                DisclosureGroup(isExpanded: expansion(client.id)) {
                    ForEach(client.areas) { area in
                        areaRow(area, client: client).tag(ClientsAreasSelection.area(area.id))
                    }
                    .onMove { offsets, destination in
                        move(client, offsets: offsets, destination: destination)
                    }
                    Button {
                        Task { await model.newArea(in: client.id) }
                    } label: {
                        Label("Add Area", systemImage: "plus").foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 26)
                    .accessibilityIdentifier("clientsAreas.addArea")
                } label: {
                    clientRow(client).tag(ClientsAreasSelection.client(client.id))
                }
            }
        }
        .contextMenu(forSelectionType: ClientsAreasSelection.self) { items in
            if let item = items.first {
                menu(for: item)
            }
        } primaryAction: { _ in
            model.editSelection()
        }
        .onKeyPress(.return) {
            model.editSelection()
            return .handled
        }
        .accessibilityIdentifier("clientsAreas.list")
        .toolbar {
            #if os(macOS)
                // The iPad pushes this view and has the system back button.
                ToolbarItem(placement: .navigation) {
                    Button {
                        projects.showTable()
                    } label: {
                        Label("Projects", systemImage: "chevron.left")
                    }
                    .help("Back to Projects")
                    .accessibilityIdentifier("clientsAreas.back")
                }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.newClient() }
                } label: {
                    Label("New Client", systemImage: "plus")
                }
                .help("New Client")
                .accessibilityIdentifier("clientsAreas.newClient")
            }
        }
        .sheet(item: $model.clientForm) { form in
            ClientFormView(model: form) { _, _ in
                Task { await model.sheetFinished() }
            }
        }
        .sheet(item: $model.areaForm) { form in
            AreaFormView(model: form) { _ in
                Task { await model.sheetFinished() }
            }
        }
        .alert(
            model.confirmation?.title ?? "",
            isPresented: .isPresent($model.confirmation),
            presenting: model.confirmation
        ) { _ in
            Button("Delete", role: .destructive) { Task { await model.confirm() } }
            Button("Cancel", role: .cancel) { model.confirmation = nil }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private func expansion(_ client: ClientID) -> Binding<Bool> {
        Binding {
            !model.collapsed.contains(client)
        } set: { open in
            if open {
                model.collapsed.remove(client)
            } else {
                model.collapsed.insert(client)
            }
        }
    }

    private func clientRow(_ client: ClientOutline) -> some View {
        HStack {
            Text(client.client.name).fontWeight(.semibold)
            Spacer()
            Text(client.countsText).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("clientsAreas.client")
    }

    private func areaRow(_ area: AreaOutline, client _: ClientOutline) -> some View {
        HStack(spacing: 10) {
            AreaSwatch(color: area.area.color)
            Text(area.area.isGeneral ? area.area.name : area.area.name)
                .frame(minWidth: 200, alignment: .leading)
            if let tag = area.tag {
                Text(tag).foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            Text(area.countsText).foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
        .moveDisabled(area.area.isGeneral)
        .accessibilityIdentifier("clientsAreas.area")
    }

    @ViewBuilder
    private func menu(for item: ClientsAreasSelection) -> some View {
        switch item {
        case let .client(id):
            if let client = model.client(id) {
                Button("Rename…") { model.renameClient(id) }
                Button("New Area…") { Task { await model.newArea(in: id) } }
                Button("Show Projects") { projects.showProjects(client: id, area: nil) }
                Button("Remove…") { model.requestRemove(id) }
                    .disabled(!client.canRemove)
                    .help(client.removeTooltip ?? "")
            }
        case let .area(id):
            if let (_, area) = model.area(id) {
                Button("Edit…") { model.editArea(id) }
                Button("Move Up") { Task { await model.move(id, by: -1) } }
                    .disabled(!area.canMoveUp)
                Button("Move Down") { Task { await model.move(id, by: 1) } }
                    .disabled(!area.canMoveDown)
                if !area.area.isGeneral {
                    if area.area.isRetired {
                        Button("Un-retire") { Task { await model.setRetired(id, false) } }
                    } else {
                        Button("Retire") { Task { await model.setRetired(id, true) } }
                            .disabled(!area.canRetire)
                    }
                }
                Button("Show Projects") { projects.showProjects(client: nil, area: id) }
                if !area.area.isGeneral {
                    Button("Delete…") { model.requestDelete(id) }
                        .disabled(!area.canDelete)
                        .help(area.deleteTooltip ?? "")
                }
            }
        }
    }

    /// A drag within the client; the general area stays first.
    private func move(_ client: ClientOutline, offsets: IndexSet, destination: Int) {
        guard let from = offsets.first, client.areas.indices.contains(from) else {
            return
        }
        let area = client.areas[from].id
        // Positions among the non-general areas (the general area is index 0).
        let target = max(destination > from ? destination - 2 : destination - 1, 0)
        Task { await model.move(area, toIndex: target) }
    }
}
