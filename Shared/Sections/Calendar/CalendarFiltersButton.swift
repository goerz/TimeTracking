// The Calendar's Filters button and popover, those of Reports
// (calendar.md §1.6; reports.md §3).

import SwiftUI
import TimeTrackingCore

/// The Filters toolbar button.
struct CalendarFiltersButton: View {
    @Bindable var model: CalendarModel

    var body: some View {
        FiltersButton(
            activeFilters: model.filters.activeKindCount,
            isPresented: $model.showsFilters,
            identifier: "calendar.filters"
        ) {
            CalendarFiltersPopover(model: model)
        }
    }
}

/// The tree of clients, areas, and projects with "No project", "Include
/// archived projects", and Clear All, in the layout of Reports and Projects.
private struct CalendarFiltersPopover: View {
    @Bindable var model: CalendarModel

    var body: some View {
        let tree = model.filterTree
        FiltersPopover(
            treeTitle: "Clients, Areas, and Projects",
            includeArchived: $model.filters.includeArchived,
            identifier: "calendar.filter",
            clearAll: { model.clearFilters() },
            tree: {
                ProjectScopeTreeView(
                    tree: model.filters.tree(clients: tree.clients, areas: tree.areas, projects: tree.projects),
                    scope: $model.filters.scope,
                    noProject: $model.filters.noProject,
                    identifier: "calendar.filter"
                )
            }
        )
    }
}
