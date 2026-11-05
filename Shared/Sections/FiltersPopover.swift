// FiltersPopover: the one layout of the Projects and Reports Filters
// popovers (projects.md §2.4, reports.md §3).

import SwiftUI

/// The tree under its headline, "Include archived projects", and Clear
/// All, 360 pt wide.
struct FiltersPopover<Tree: View>: View {
    var treeTitle: String
    @Binding var includeArchived: Bool
    /// The prefix of the controls' identifiers ("projects.filter").
    var identifier: String
    var clearAll: () -> Void
    @ViewBuilder var tree: Tree

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            FilterSection(treeTitle) { tree }
            Toggle("Include archived projects", isOn: $includeArchived)
                .accessibilityIdentifier("\(identifier).includeArchived")
            HStack {
                Spacer()
                Button("Clear All", action: clearAll)
                    .accessibilityIdentifier("\(identifier).clear")
            }
        }
        .padding(Design.Spacing.large)
        .frame(width: 360)
    }
}
