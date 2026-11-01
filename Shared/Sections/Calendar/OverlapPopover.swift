// OverlapPopover: the overlap question, Trim, Overlap, or Cancel
// (spec_calendar.md §2.6).

import SwiftUI
import TimeTrackingCore

/// Overlaps "Standup" (11:00 to 11:30) by 12 min. [Trim] [Overlap] [Cancel]
struct OverlapPopover: View {
    var model: CalendarModel

    var body: some View {
        if let pending = model.pendingOverlap {
            VStack(alignment: .leading, spacing: Design.Spacing.medium) {
                Label(pending.prompt.text(in: model.calendar.timeZone), systemImage: SymbolName.warning)
                HStack {
                    Button("Trim") { Task { await model.resolveOverlap(.trim) } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pending.prompt.trimmed == nil)
                        .accessibilityIdentifier("calendar.overlap.trim")
                    Button("Overlap") { Task { await model.resolveOverlap(.overlap) } }
                        .accessibilityIdentifier("calendar.overlap.overlap")
                    Button("Cancel") { Task { await model.resolveOverlap(.cancel) } }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        }
    }
}
