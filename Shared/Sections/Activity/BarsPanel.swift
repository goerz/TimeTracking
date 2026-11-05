// BarsPanel: active time by day (activity.md §1.5).

import Charts
import SwiftUI
import TimeTrackingCore

/// Active time by day, stacked by context (§1.5).
struct BarsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.contextColors) private var colors
    /// The bar or segment under the pointer.
    @State private var hovered: ActivityBars.Target?
    @FocusState private var isFocused: Bool

    var body: some View {
        let bars = summary.bars
        ActivityPanel(title: "Active time by day") {
            chart(bars)
                .chartOverlay { proxy in pointerArea(proxy, bars: bars) }
                .overlay(alignment: .top) {
                    if let text = shownTarget.flatMap({ bars.tooltip(of: $0, displayName: model.displayName) }) {
                        tooltip(text)
                    }
                }
                .frame(height: 220)
                .activityPanelKeys(isFocused: $isFocused, onFocus: model.barsFocused, perform: handle)
                // One element, and the tooltip inside keeps its identifier.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity.bars.chart")
        }
        .accessibilityIdentifier("activity.bars")
    }

    private func chart(_ bars: ActivityBars) -> some View {
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
        // Every day has its column: a future day has no marks to make one.
        .chartXScale(domain: bars.bars.map(\.id))
    }

    /// What the tooltip is about: the pointer's target, else the focused
    /// one while Space shows it.
    private var shownTarget: ActivityBars.Target? {
        hovered ?? (isFocused && model.showsBarDetails ? model.focusedBar : nil)
    }

    /// The arrows move, Space shows or hides the tooltip, Return drills down (§2).
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if let move = ActivityFocusMove(press.key) {
            model.moveFocusedBar(move)
        } else if press.key == .space {
            model.showsBarDetails.toggle()
        } else {
            model.openFocusedBar()
        }
        return .handled
    }

    /// The pointer over the chart: hovering shows a tooltip, a click drills
    /// into the Calendar (§1.5, §3), and beside the bars takes the focus, by
    /// `focusable`: setting it again in the tap gesture loses it.
    private func pointerArea(_ proxy: ChartProxy, bars: ActivityBars) -> some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hovered = target(at: location, proxy, geometry, bars: bars)
                    case .ended:
                        hovered = nil
                    }
                }
                .onTapGesture { location in
                    if let target = target(at: location, proxy, geometry, bars: bars) {
                        model.showInCalendar(target, in: bars)
                    }
                }
        }
    }

    /// The bar at a point of the chart and the segment there; the proxy
    /// counts from the plot area, which starts after the y axis.
    private func target(at location: CGPoint, _ proxy: ChartProxy, _ geometry: GeometryProxy, bars: ActivityBars) -> ActivityBars.Target? {
        guard let plot = proxy.plotFrame.map({ geometry[$0] }),
              (plot.minX ... plot.maxX).contains(location.x),
              let id = proxy.value(atX: location.x - plot.minX, as: String.self),
              let bar = bars.bars.first(where: { $0.id == id })
        else {
            return nil
        }
        let hours = proxy.value(atY: location.y - plot.minY, as: Double.self)
        return ActivityBars.Target(bar: id, series: hours.flatMap { bar.series(atSeconds: $0 * 3600) })
    }

    private func tooltip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, Design.Spacing.small)
            .padding(.vertical, Design.Spacing.tight)
            .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(.background).shadow(radius: 4))
            .allowsHitTesting(false)
            .accessibilityIdentifier("activity.bars.tooltip")
    }

    /// The bar's segments, the open block's hatched top, and its total above it.
    @ChartContentBuilder
    private func marks(_ bar: ActivityBars.Bar) -> some ChartContent {
        ForEach(bar.segments, id: \.series) { segment in
            BarMark(x: .value("Day", bar.id), y: .value("Hours", Double(segment.seconds) / 3600))
                .foregroundStyle(color(segment.series))
                .opacity(opacity(bar, segment.series))
        }
        if let open = bar.openRange {
            BarMark(
                x: .value("Day", bar.id),
                yStart: .value("Hours", Double(open.lowerBound) / 3600),
                yEnd: .value("Hours", Double(open.upperBound) / 3600)
            )
            .foregroundStyle(Hatch.paint(.white.opacity(0.55)))
            .opacity(opacity(bar, nil))
        }
        if !bar.isFuture, bar.seconds > 0 {
            PointMark(x: .value("Day", bar.id), y: .value("Hours", Double(bar.seconds) / 3600))
                .symbolSize(0)
                .annotation(position: .top) {
                    Text(ActivityText.duration(bar.seconds)).font(.caption.weight(.semibold)).monospacedDigit()
                }
        }
    }

    /// While the chart has the focus, everything but the focused bar or
    /// segment is dimmed.
    private func opacity(_ bar: ActivityBars.Bar, _ series: ActivityBars.Series?) -> Double {
        guard isFocused, let focus = model.focusedBar else {
            return 1
        }
        return focus.bar == bar.id && (focus.series == nil || focus.series == series) ? 1 : 0.35
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
