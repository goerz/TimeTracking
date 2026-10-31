// CalendarNoticeView: the transient notice, a future refusal or a deletion
// with Undo (spec_planner_calendar.md §2.2, §2.5).

import SwiftUI
import TimeTrackingCore

/// The transient notice (future refusal, deletion with Undo).
struct CalendarNoticeView: View {
    var model: CalendarModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        if let notice = model.notice {
            HStack {
                Text(notice.text)
                if !notice.deleted.isEmpty {
                    Button("Undo") {
                        undoManager?.undo()
                        model.notice = nil
                    }
                }
            }
            .padding(Design.Spacing.medium)
            .background(.regularMaterial, in: Capsule())
            .padding()
            .accessibilityIdentifier("calendar.notice")
            .task(id: notice) {
                try? await Task.sleep(for: .seconds(notice.duration))
                if model.notice == notice {
                    model.notice = nil
                }
            }
        }
    }
}
