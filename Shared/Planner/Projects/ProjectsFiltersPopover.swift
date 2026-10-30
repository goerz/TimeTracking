// The Projects section's Filters popover (spec_planner_projects.md §2.4).

import SwiftUI
import TimeTrackingCore

/// Clients and areas as check boxes, Last tracked, and Clear.
struct ProjectsFiltersPopover: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clients and Areas").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.clients) { client in
                        clientToggle(client)
                        ForEach(areas(of: client.id).filter { !$0.isGeneral }) { area in
                            areaToggle(area)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            Picker("Last tracked:", selection: $model.options.lastTracked) {
                ForEach(LastTrackedFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            HStack {
                Spacer()
                Button("Clear") { model.options.clearFilters() }
                    .accessibilityIdentifier("projects.filter.clear")
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func clientToggle(_ client: Client) -> some View {
        Toggle(client.name, isOn: Binding {
            model.options.clients.contains(client.id)
        } set: { _ in
            model.options.toggle(client: client.id, areasOfClient: areas(of: client.id).map(\.id))
        })
        .accessibilityIdentifier("projects.filter.client")
    }

    /// Areas indented under their client; retired ones in secondary color.
    private func areaToggle(_ area: Area) -> some View {
        Toggle(isOn: Binding {
            model.options.areas.contains(area.id)
        } set: { _ in
            model.options.toggle(area: area)
        }) {
            HStack(spacing: 6) {
                AreaSwatch(color: area.color)
                Text(area.name).foregroundStyle(area.isRetired ? .secondary : .primary)
            }
        }
        .padding(.leading, 20)
    }

    private func areas(of client: ClientID) -> [Area] {
        model.areas.filter { $0.clientID == client }
    }
}
