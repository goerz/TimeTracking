// CalendarSummaryStrip: the tracked, block, and activity totals above the
// day headers, and the day width slider (spec_calendar.md §1.1, §1.2).

import SwiftUI
import TimeTrackingCore

/// "Tracked ▇▇▇ 18h 51m   Time blocks 1h 30m   Activity 25h 02m", and the
/// day width slider at the trailing end.
struct CalendarSummaryStrip: View {
    var model: CalendarModel

    var body: some View {
        HStack(spacing: Design.Spacing.large) {
            if let summary = model.summary {
                HStack(spacing: Design.Spacing.small) {
                    Text("Tracked").foregroundStyle(.secondary).fixedSize()
                    SummaryBar(summary: summary).frame(minWidth: 48, maxWidth: 200).frame(height: 8)
                    value(summary.tracked)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Time blocks").foregroundStyle(.secondary).fixedSize()
                    value(summary.blocks)
                }
                HStack(spacing: Design.Spacing.tight) {
                    Text("Activity").foregroundStyle(.secondary).fixedSize()
                    value(summary.activity)
                }
            }
            Spacer(minLength: Design.Spacing.large)
            DayWidthSlider(model: model)
        }
        .font(.subheadline)
        .lineLimit(1)
        .padding(.horizontal, Design.Spacing.content)
        .padding(.vertical, Design.Spacing.small)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.summary")
    }

    private func value(_ seconds: Int) -> some View {
        Text(ActivityText.duration(seconds)).fontWeight(.semibold).monospacedDigit().fixedSize()
    }
}

/// The horizontal zoom: how wide a day is, so the window's width decides
/// how many days show (§1.2).
private struct DayWidthSlider: View {
    var model: CalendarModel

    var body: some View {
        HStack(spacing: Design.Spacing.tight) {
            Image(systemName: SymbolName.narrowerDays)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: Binding {
                    CalendarViewport.sliderValue(dayWidth: model.dayWidth)
                } set: { value in
                    model.setDayWidth(CalendarViewport.dayWidth(sliderValue: value))
                },
                in: 0 ... 1
            ) {
                Text("Day Width")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 140)
            .accessibilityIdentifier("calendar.dayWidth")
            Image(systemName: SymbolName.widerDays)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .help("Day Width")
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
