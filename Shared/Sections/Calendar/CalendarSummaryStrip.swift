// CalendarSummaryStrip: the tracked, block, and activity totals above the
// day headers (spec_calendar.md §1.1).

import SwiftUI
import TimeTrackingCore

/// "Tracked ▇▇▇ 18h 51m   Time blocks 1h 30m   Activity 25h 02m".
struct CalendarSummaryStrip: View {
    var model: CalendarModel

    var body: some View {
        HStack(spacing: Design.Spacing.large) {
            if let summary = model.summary {
                HStack(spacing: Design.Spacing.small) {
                    Text("Tracked").foregroundStyle(.secondary)
                    SummaryBar(summary: summary).frame(width: 200, height: 8)
                    value(summary.tracked)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Time blocks").foregroundStyle(.secondary)
                    value(summary.blocks)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Activity").foregroundStyle(.secondary)
                    value(summary.activity)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, Design.Spacing.content)
        .padding(.vertical, Design.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.summary")
    }

    private func value(_ seconds: Int) -> some View {
        Text(ActivityText.duration(seconds)).fontWeight(.semibold).monospacedDigit()
    }
}

/// The tracked time stacked by project in area colors, each segment
/// proportional, with a hover tooltip.
private struct SummaryBar: View {
    var summary: CalendarSummary

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(summary.segments) { segment in
                    Rectangle()
                        .fill(segment.color.map { Color(hex: $0) } ?? Color.gray)
                        .frame(width: proxy.size.width * CGFloat(segment.seconds) / CGFloat(max(summary.tracked, 1)))
                        .help(CalendarSummary.tooltip(segment))
                }
                Spacer(minLength: 0)
            }
        }
        .background(.quaternary)
        .clipShape(Capsule())
    }
}
