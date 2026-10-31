// The Projects section's Filters popover (spec_planner_projects.md §2.4).

import SwiftUI
import TimeTrackingCore

/// The tree of clients and areas, Last tracked, and Clear All, laid out as
/// the Reports popover.
struct ProjectsFiltersPopover: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            FilterSection("Clients and Areas") {
                ProjectScopeTreeView(
                    tree: ProjectScopeTree(clients: model.clients, areas: model.areas),
                    scope: $model.options.scope,
                    identifier: "projects.filter"
                )
            }
            FilterSection("Last Tracked") {
                Picker("Last tracked", selection: $model.options.lastTracked) {
                    ForEach(LastTrackedFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Spacer()
                Button("Clear All") { model.options.clearFilters() }
                    .accessibilityIdentifier("projects.filter.clear")
            }
        }
        .padding(Design.Spacing.large)
        .frame(width: 360)
    }
}
