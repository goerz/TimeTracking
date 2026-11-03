// ProjectColumnSort: the column headers' sort indicators and clicks
// (spec_projects.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The library sorts the rows (`ProjectTable`); the table only shows the
/// sort on its headers and reports clicks. Each sortable column carries
/// one of these, naming its `ProjectSortKey`, so a header click maps back
/// to the key by value.
///
/// Key paths to placeholder properties can't do this: in an optimized
/// build, properties with identical bodies share one getter, their key
/// paths compare equal, and every header click read as Project.
nonisolated struct ProjectColumnSort: SortComparator, Hashable {
    let key: ProjectSortKey
    var order: SortOrder = .forward

    /// Never called: the table doesn't sort its rows.
    func compare(_: ProjectTableItem, _: ProjectTableItem) -> ComparisonResult {
        .orderedSame
    }

    /// The table's sort order as the stored sort key and direction: a click
    /// on another header sorts ascending by it, a second click reverses.
    @MainActor
    static func sortOrder(_ options: Binding<ProjectTableOptions>) -> Binding<[Self]> {
        Binding {
            [Self(key: options.wrappedValue.sort, order: options.wrappedValue.ascending ? .forward : .reverse)]
        } set: { comparators in
            guard let first = comparators.first else {
                return
            }
            if first.key == options.wrappedValue.sort {
                options.wrappedValue.ascending = first.order == .forward
            } else {
                options.wrappedValue.sort(by: first.key)
            }
        }
    }
}
