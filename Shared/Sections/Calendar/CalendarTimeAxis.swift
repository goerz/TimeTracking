// CalendarTimeAxis: the hour labels and the now bubble
// (spec_calendar.md §1.3, §1.5).

import SwiftUI
import TimeTrackingCore

/// The hour labels and the now bubble.
struct CalendarTimeAxis: View {
    var model: CalendarModel

    var body: some View {
        let axis = model.axis(model.today)
        let step = CalendarZoom.labelMinutes(pointsPerHour: model.pointsPerHour)
        ZStack(alignment: .topTrailing) {
            Color.clear.frame(height: axis.height)
            let now = model.days.contains(model.today) ? axis.nowOffset(model.clock.now) : nil
            ForEach(Array(stride(from: step, to: 24 * 60, by: step)), id: \.self) { minute in
                let y = CGFloat(minute) / 60 * model.pointsPerHour
                Text(ActivityText.clock(hour: (minute / 60 + model.calendar.midnightHour) % 24, minute: minute % 60))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
                    // The now bubble covers the hour label it would overlap.
                    .opacity(now.map { abs($0 - y) < 14 } == true ? 0 : 1)
                    .offset(x: -6, y: y - 7)
                    .accessibilityIdentifier("calendar.hourLabel.\(minute)")
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                if let offset = axis.nowOffset(model.clock.now) {
                    Text(CalendarText.clock(model.clock.now, zone: model.calendar.timeZone))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, Design.Spacing.tight)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: -4, y: offset - 8)
                }
            }
        }
    }
}
