// ProjectTableItem+Sort: the column headers' sort indicators and clicks
// (spec_planner_projects.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The library sorts the rows (`ProjectTable`); the table only shows the
/// sort on its headers and reports clicks. Each sortable column names one
/// of these key paths, so a header click maps back to a `ProjectSortKey`.
/// Their values are never compared.
extension ProjectTableItem {
    nonisolated var sortName: String {
        ""
    }

    nonisolated var sortClient: String {
        ""
    }

    nonisolated var sortArea: String {
        ""
    }

    nonisolated var sortCreated: String {
        ""
    }

    nonisolated var sortLastTracked: String {
        ""
    }

    nonisolated var sortTotalTracked: String {
        ""
    }

    static func sortPath(_ key: ProjectSortKey) -> any KeyPath<Self, String> & Sendable {
        switch key {
        case .name: \.sortName
        case .client: \.sortClient
        case .area: \.sortArea
        case .created: \.sortCreated
        case .lastTracked: \.sortLastTracked
        case .totalTracked: \.sortTotalTracked
        }
    }

    /// The table's sort order as the stored sort key and direction: a click
    /// on another header sorts ascending by it, a second click reverses.
    static func sortOrder(_ options: Binding<ProjectTableOptions>) -> Binding<[KeyPathComparator<Self>]> {
        Binding {
            [KeyPathComparator(sortPath(options.wrappedValue.sort), order: options.wrappedValue.ascending ? .forward : .reverse)]
        } set: { comparators in
            guard let first = comparators.first,
                  let key = ProjectSortKey.allCases.first(where: { (sortPath($0) as AnyKeyPath) == (first.keyPath as AnyKeyPath) })
            else {
                return
            }
            if key == options.wrappedValue.sort {
                options.wrappedValue.ascending = first.order == .forward
            } else {
                options.wrappedValue.sort(by: key)
            }
        }
    }
}
