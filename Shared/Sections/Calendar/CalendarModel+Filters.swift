// The Calendar's Filters and search, those of Reports: entries they leave
// out are faded and leave the tracked totals (spec_calendar.md §1.6).

import Foundation
import TimeTrackingCore

/// The Filters tree's clients, areas, and projects (retired included).
struct CalendarFilterTree {
    var clients: [Client] = []
    var areas: [Area] = []
    var projects: [ProjectRow] = []
}

extension CalendarModel {
    /// Whether a filter or the search is active.
    var isFiltering: Bool {
        filters.activeKindCount > 0 || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `listing` passes the Filters and the search.
    func passesFilters(_ listing: EntryListing) -> Bool {
        !isFiltering || filters.entryFilter(search: search).admits(listing)
    }

    /// The removable tokens of the filter bar.
    var filterChips: [ReportFilterChip] {
        filters.chips(clients: filterTree.clients, areas: filterTree.areas, projects: filterTree.projects)
    }

    func removeChip(_ kind: ReportFilterChip.Kind) {
        filters.remove(kind)
    }

    /// "Clear All" and View › Clear Filters.
    func clearFilters() {
        filters = ReportFilters()
    }

    /// ⌘F: focus in the search field.
    func focusSearch() {
        searchFocusRequests += 1
    }
}
