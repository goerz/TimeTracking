// PlannerFiltersButton: the Filters toolbar button of Projects and Reports
// (spec_design.md §4, §5).

import SwiftUI

/// An icon-only Filters button; the symbol fills while a filter is active
/// and the title names the count ("Filters (2)") for help and overflow.
struct PlannerFiltersButton<Popover: View>: View {
    var activeFilters: Int
    @Binding var isPresented: Bool
    var identifier: String
    @ViewBuilder var popover: () -> Popover

    var body: some View {
        let title = activeFilters > 0 ? "Filters (\(activeFilters))" : "Filters"
        Button {
            isPresented.toggle()
        } label: {
            Label(title, systemImage: activeFilters > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
        .help(title)
        .accessibilityIdentifier(identifier)
        .popover(isPresented: $isPresented, arrowEdge: .bottom, content: popover)
    }
}
