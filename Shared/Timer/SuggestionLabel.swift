// SuggestionLabel: one task suggestion under the task field on the Mac and
// iOS (spec_timer.md §2.2; spec_ios.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The task, then the project's area dot and name at the trailing edge.
/// Padding and the highlight stay with the list that shows it.
struct SuggestionLabel: View {
    var suggestion: TaskSuggestion
    /// The suggested project; nil shows the task alone.
    var label: ProjectLabel?
    var projectStyle = AnyShapeStyle(.secondary)

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            Text(suggestion.task).lineLimit(1)
            Spacer()
            if let label {
                AreaDot(color: label.color)
                Text(label.name).lineLimit(1).foregroundStyle(projectStyle)
            }
        }
    }
}
