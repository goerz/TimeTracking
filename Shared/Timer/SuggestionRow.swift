// SuggestionRow: one line of the Mac's task suggestions, under the bar and
// in the edit popover (timer.md §2.2, §4.1).

import SwiftUI
import TimeTrackingCore

/// A suggestion of `field` as a button, highlighted like a menu item.
struct SuggestionRow: View {
    var field: TaskFieldModel
    var index: Int
    var suggestion: TaskSuggestion
    var accept: () -> Void

    var body: some View {
        let label = suggestion.projectID.flatMap { field.labels[$0] } ?? .noProject
        let highlighted = field.highlightedSuggestion == index
        Button(action: accept) {
            SuggestionLabel(
                suggestion: suggestion,
                label: label,
                projectStyle: highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
            )
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Design.Spacing.medium)
            .padding(.vertical, Design.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(highlighted ? Color.accentColor : .clear)
                    .padding(.horizontal, Design.Spacing.compact)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
