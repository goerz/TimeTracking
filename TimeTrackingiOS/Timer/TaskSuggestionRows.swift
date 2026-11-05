// TaskSuggestionRows: the suggestions under a task field, on the card and
// in the edit sheet (ios.md §2.2, §2.7).

import SwiftUI
import TimeTrackingCore

/// Up to four suggestions; a tap calls `accept`.
struct TaskSuggestionRows: View {
    var field: TaskFieldModel
    /// The rows' identifiers: `<identifier>.0`, `<identifier>.1`, and so on.
    var identifier: String
    var accept: (TaskSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(field.suggestions.prefix(4).enumerated()), id: \.offset) { index, suggestion in
                Button {
                    accept(suggestion)
                } label: {
                    SuggestionLabel(suggestion: suggestion, label: suggestion.projectID.flatMap { field.labels[$0] })
                        .padding(.vertical, Design.Spacing.small)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier).\(index)")
            }
        }
    }
}
