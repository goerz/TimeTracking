// The Projects section's Filters popover (spec_planner_projects.md §2.4).

import SwiftUI
import TimeTrackingCore

/// The tree of clients and areas, Last tracked, "Include archived
/// projects", and Clear All, in the layout shared with Reports.
struct ProjectsFiltersPopover: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        PlannerFiltersPopover(
            treeTitle: "Clients and Areas",
            includeArchived: $model.options.includeArchived,
            identifier: "projects.filter",
            clearAll: { model.options.clearFilters() },
            tree: {
                ProjectScopeTreeView(
                    tree: ProjectScopeTree(clients: model.clients, areas: model.areas),
                    scope: $model.options.scope,
                    identifier: "projects.filter"
                )
            },
            sections: {
                FilterSection("Last Tracked") {
                    Picker("Last tracked", selection: $model.options.lastTracked) {
                        ForEach(LastTrackedFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("projects.filter.lastTracked")
                }
            }
        )
    }
}
