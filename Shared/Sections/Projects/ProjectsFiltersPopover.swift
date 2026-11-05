// The Projects section's Filters popover (projects.md §2.4).

import SwiftUI
import TimeTrackingCore

/// The tree of clients and areas, "Include archived projects", and Clear
/// All, in the layout shared with Reports.
struct ProjectsFiltersPopover: View {
    @Bindable var model: ProjectsModel

    var body: some View {
        FiltersPopover(
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
            }
        )
    }
}
