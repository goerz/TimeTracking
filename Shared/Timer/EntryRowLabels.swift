// EntryRowLabels: the text of a Timer list row on the Mac and iOS
// (spec_timer_window.md §3, spec_design.md §1).

import SwiftUI
import TimeTrackingCore

/// The task ("No task" in placeholder style) over the project line: area
/// dot, project, " · client" in secondary.
struct EntryRowLabels: View {
    var listing: EntryListing
    /// Shows the "adjusted after syncing" badge after the task (iOS).
    var badged = false

    var body: some View {
        let label = ProjectLabel(listing)
        let archived = listing.project?.isArchived ?? false
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Design.Spacing.tight) {
                Text(listing.entry.task.isEmpty ? "No task" : listing.entry.task)
                    .foregroundStyle(listing.entry.task.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if badged {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .accessibilityLabel("Changed by another device")
                        .accessibilityIdentifier("timer.badge.\(listing.id)")
                }
            }
            HStack(spacing: Design.Spacing.tight + 2) {
                AreaDot(color: label.color)
                label.text(dimmed: label.isNone || archived)
            }
            .font(.subheadline)
        }
        .lineLimit(1)
    }
}
