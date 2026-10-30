// BarsPanel: active time by day (spec_planner_activity.md §1.5).

import Charts
import SwiftUI
import TimeTrackingCore

/// Active time by day, stacked by context (§1.5).
struct BarsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.contextColors) private var colors

    var body: some View {
        let bars = summary.bars
        ActivityPanel(title: "Active time by day") {
            Chart {
                ForEach(bars.bars) { bar in
                    marks(bar)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel { axisLabel(value.as(String.self).flatMap { id in bars.bars.first { $0.id == id } }) }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: bars.axisHours, by: 2)).map(Double.init)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text("\(Int(value.as(Double.self) ?? 0))h").font(.caption).monospacedDigit()
                    }
                }
            }
            .chartYScale(domain: 0 ... Double(bars.axisHours))
            .chartOverlay { proxy in tapArea(proxy, bars: bars) }
            .frame(height: 220)
        }
        .accessibilityIdentifier("activity.bars")
    }

    /// A click on a bar drills into the Calendar (§3).
    private func tapArea(_ proxy: ChartProxy, bars: ActivityBars) -> some View {
        Rectangle().fill(.clear).contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .onTapGesture { location in
                if let id: String = proxy.value(atX: location.x), let bar = bars.bars.first(where: { $0.id == id }) {
                    model.showInCalendar(bar: bar, series: nil)
                }
            }
    }

    /// The bar's segments and its total above it.
    @ChartContentBuilder
    private func marks(_ bar: ActivityBars.Bar) -> some ChartContent {
        ForEach(bar.segments, id: \.series) { segment in
            BarMark(x: .value("Day", bar.id), y: .value("Hours", Double(segment.seconds) / 3600))
                .foregroundStyle(color(segment.series))
        }
        if !bar.isFuture, bar.seconds > 0 {
            PointMark(x: .value("Day", bar.id), y: .value("Hours", Double(bar.seconds) / 3600))
                .symbolSize(0)
                .annotation(position: .top) {
                    Text(ActivityText.duration(bar.seconds)).font(.caption.weight(.semibold)).monospacedDigit()
                }
        }
    }

    @ViewBuilder
    private func axisLabel(_ bar: ActivityBars.Bar?) -> some View {
        if let bar {
            VStack(spacing: 0) {
                Text(bar.label)
                if let sublabel = bar.sublabel {
                    Text(sublabel)
                }
                if bar.isToday {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                }
            }
            .font(.caption)
        }
    }

    private func color(_ series: ActivityBars.Series) -> Color {
        switch series {
        case let .context(context): colors.color(context)
        case .otherContexts: .gray.opacity(0.6)
        case .notItemized: .gray.opacity(0.35)
        }
    }
}
