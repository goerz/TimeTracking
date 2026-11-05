// DraftCard: the provisional entry and its popovers
// (calendar.md §2.3, §2.6).

import SwiftUI
import TimeTrackingCore

/// The provisional entry with a dashed border and the edit popover.
struct DraftCard: View {
    var model: CalendarModel
    var size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: Design.Radius.small)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(Color.accentColor.opacity(0.1)))
            .frame(width: size.width, height: size.height)
            .popover(isPresented: draftBinding, arrowEdge: .trailing) { DraftEditor(model: model) }
            .popover(isPresented: overlapBinding, arrowEdge: .trailing) { OverlapPopover(model: model) }
            .accessibilityIdentifier("calendar.draft")
    }

    private var draftBinding: Binding<Bool> {
        Binding { model.draft != nil && model.pendingOverlap == nil } set: { shown in
            if !shown {
                Task { await model.dismissDraft(commit: true) }
            }
        }
    }

    private var overlapBinding: Binding<Bool> {
        Binding {
            if case .create = model.pendingOverlap?.action {
                return true
            }
            return false
        } set: { shown in
            if !shown {
                Task { await model.resolveOverlap(.cancel) }
            }
        }
    }
}
