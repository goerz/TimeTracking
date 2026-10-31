// ActivityPanel: the card every Activity panel sits in
// (spec_planner_activity.md §1.4 to §1.8; spec_design.md §3).

import SwiftUI

/// A card (12 pt corners, 16 pt padding).
struct ActivityPanel<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(Design.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
