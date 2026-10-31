// FilterSection: a section of the Projects and Reports Filters popovers
// (spec_planner_projects.md §2.4, spec_planner_reports.md §3).

import SwiftUI

/// A Filters popover's section: a headline above its control.
struct FilterSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.compact) {
            Text(title).font(.headline)
            content
        }
    }
}
