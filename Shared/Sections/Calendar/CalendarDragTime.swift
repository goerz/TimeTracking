// CalendarDragTime: the time label over a card while it is dragged
// (calendar.md §2.4, §4.2).

import SwiftUI
import TimeTrackingCore

/// The start a drag would give, sitting on the card's top edge.
struct CalendarDragTime: View {
    var time: Date
    var zone: TimeZone

    var body: some View {
        Text(CalendarText.clock(time, zone: zone))
            .font(.caption)
            .monospacedDigit()
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.background, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
            .alignmentGuide(.top) { $0[.bottom] + 2 }
            .allowsHitTesting(false)
            .accessibilityIdentifier("calendar.dragTime")
    }
}
