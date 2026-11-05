// CalendarDayStrip: places the day headers and the day columns at their
// place in the viewport, cut off at its edges (spec_calendar.md §1.2).

import SwiftUI
import TimeTrackingCore

/// The days side by side at the viewport's scroll position. The headers
/// and the columns each use one, so the two always line up.
struct CalendarDayStrip<Content: View>: View {
    var model: CalendarModel
    @ViewBuilder var content: (TrackingDay, CGFloat) -> Content

    var body: some View {
        // The only reader of the viewport: a scroll re-lays out the strip,
        // while each day's view stays as it is.
        let viewport = model.viewport
        let width = CGFloat(viewport.dayWidth)
        DayStripLayout {
            ForEach(model.drawnDays, id: \.self) { day in
                content(day, width)
                    .frame(width: width)
                    .layoutValue(key: DayX.self, value: CGFloat(viewport.x(of: day)))
                    // A dragged card passes over the days beside it.
                    .zIndex(model.cardDrag?.day == day ? 1 : 0)
                    // The day kept just outside the viewport on each side
                    // is drawn for the slide only, not for VoiceOver.
                    .accessibilityHidden(!model.days.contains(day))
            }
        }
        .clipped()
    }
}

/// The line at a day's leading edge, in its header and its columns. (A
/// `Divider` outside a stack would lie horizontally.)
struct DaySeparator: View {
    var body: some View {
        Rectangle().fill(.separator).frame(width: 1).accessibilityHidden(true)
    }
}

/// A day's left edge in the viewport.
private nonisolated struct DayX: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// As wide as offered and as tall as the tallest day; each day at its `DayX`.
private nonisolated struct DayStripLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.minX + subview[DayX.self], y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: nil, height: bounds.height)
            )
        }
    }
}
