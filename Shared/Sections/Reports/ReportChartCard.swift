// ReportChartCard: the stacked bar chart in area colors with totals, the
// average rule, hover tooltips, the legend, and drill-down
// (spec_reports.md §4).

import Charts
import SwiftUI
import TimeTrackingCore

extension StackColor {
    /// The eight client colors.
    static let palette: [Color] = [.blue, .orange, .green, .pink, .purple, .teal, .yellow, .brown]

    var color: Color {
        switch self {
        case .accent: .accentColor
        case let .palette(index): Self.palette[index % Self.palette.count]
        case let .area(hex, _): Color(hex: hex)
        case .gray: Color(white: 0.6)
        }
    }

    /// From the seventh project of an area.
    var isHatched: Bool {
        if case let .area(_, hatched) = self {
            return hatched
        }
        return false
    }

    /// The color, with a light diagonal hatch from the seventh project.
    var fill: AnyShapeStyle {
        isHatched ? AnyShapeStyle(Hatch.paint(.white.opacity(0.55), on: color)) : AnyShapeStyle(color)
    }
}

/// "Logged time" with Stack by, the chart, and the legend.
struct ReportChartCard: View {
    var model: ReportsModel
    var height: CGFloat

    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            HStack {
                Text("Logged time").font(.headline)
                Spacer()
                Picker("Stack by", selection: Binding(get: { model.state.stack }, set: { value in
                    Task { await model.setStack(value) }
                })) {
                    ForEach(StackKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityIdentifier("reports.stackBy")
            }
            if let chart = model.snapshot?.chart {
                chartView(chart).frame(height: height)
                legend(chart)
            } else {
                Color.clear.frame(height: height)
            }
        }
        .padding(Design.Spacing.large)
        .cardBackground()
    }

    private func chartView(_ chart: ReportChart) -> some View {
        let ids = chart.buckets.map(\.id.description)
        return Chart {
            marks(chart)
        }
        .chartXScale(domain: ids)
        .chartYScale(domain: 0 ... Double(chart.axisHours))
        .chartYAxis {
            AxisMarks(position: .leading, values: hourMarks(chart)) { value in
                AxisGridLine()
                AxisValueLabel {
                    Text("\(Int(value.as(Double.self) ?? 0))h").font(.caption).monospacedDigit()
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: ids) { value in
                AxisValueLabel(centered: true) {
                    xLabel(chart, index: ids.firstIndex(of: value.as(String.self) ?? "") ?? 0)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            // The overlay starts left of the plot, at the y axis.
                            let plotX = proxy.plotFrame.map { location.x - geometry[$0].minX } ?? location.x
                            hovered = proxy.value(atX: plotX, as: String.self)
                        case .ended:
                            hovered = nil
                        }
                    }
                    .onTapGesture(count: 2) {
                        if let bucket = hoveredBucket(chart) {
                            Task { await model.drillDown(bucket) }
                        }
                    }
            }
        }
        .overlay(alignment: .top) {
            if let bucket = hoveredBucket(chart) {
                ReportTooltip(bucket: bucket).allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("reports.chart")
    }

    @ChartContentBuilder
    private func marks(_ chart: ReportChart) -> some ChartContent {
        ForEach(chart.buckets) { bucket in
            ForEach(bucket.segments, id: \.key.value) { segment in
                BarMark(x: .value("Period", bucket.id.description), y: .value("Hours", Double(segment.seconds) / 3600))
                    .foregroundStyle(segment.key.color.fill)
                    .opacity(opacity(bucket: bucket, key: segment.key.value, hovered: hoveredBucket(chart)))
                    .accessibilityLabel(tooltipText(bucket))
            }
            if !bucket.isFuture {
                PointMark(x: .value("Period", bucket.id.description), y: .value("Hours", Double(bucket.total) / 3600))
                    .symbolSize(0)
                    .annotation(position: .top) {
                        Text(ReportText.bar(bucket.total)).font(.caption.weight(.semibold)).monospacedDigit()
                    }
            }
        }
        if let average = chart.averageLine {
            // The label sits above the rule at the right edge, inside the plot.
            RuleMark(y: .value("Average", Double(average) / 3600))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("avg \(ReportText.bar(average))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
        }
    }

    /// Whole hours with grid lines.
    private func hourMarks(_ chart: ReportChart) -> [Double] {
        Array(stride(from: 0, through: chart.axisHours, by: max(1, chart.axisHours / 5))).map(Double.init)
    }

    /// Two lines per bucket; above 31 buckets every n-th.
    @ViewBuilder
    private func xLabel(_ chart: ReportChart, index: Int) -> some View {
        if index.isMultiple(of: chart.labelStride), chart.buckets.indices.contains(index) {
            VStack(spacing: 0) {
                ForEach(chart.buckets[index].label, id: \.self) { line in
                    Text(line)
                }
            }
            .font(.caption)
            .opacity(chart.buckets[index].isFuture ? 0.5 : 1)
        }
    }

    private func hoveredBucket(_ chart: ReportChart) -> ChartBucket? {
        guard let hovered else {
            return nil
        }
        return chart.buckets.first { $0.id.description == hovered && !$0.isFuture }
    }

    /// Hovering an empty or future slot dims nothing.
    private func opacity(bucket: ChartBucket, key: GroupKeyValue, hovered: ChartBucket?) -> Double {
        if let hovered, hovered.id != bucket.id {
            return 0.35
        }
        if let highlighted = model.highlightedKey, highlighted != key {
            return 0.25
        }
        return 1
    }

    private func legend(_ chart: ReportChart) -> some View {
        FlowChips(spacing: Design.Spacing.medium) {
            ForEach(chart.legend) { key in
                Button {
                    model.toggleHighlight(key.value)
                } label: {
                    HStack(spacing: Design.Spacing.tight) {
                        RoundedRectangle(cornerRadius: 2).fill(key.color.fill).frame(width: 10, height: 10)
                        Text(key.name).lineLimit(1)
                    }
                    .opacity(model.highlightedKey == nil || model.highlightedKey == key.value ? 1 : 0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.legend")
    }

    /// The bar's accessibility label: the tooltip's lines.
    private func tooltipText(_ bucket: ChartBucket) -> String {
        ([bucket.title] + bucket.segments.map { "\($0.key.name) \(ReportText.seconds($0.seconds, padded: true))" }
            + ["Total \(ReportText.seconds(bucket.total, padded: true))"]).joined(separator: ", ")
    }
}

/// The hover tooltip: date, one line per segment, Total, and for longer
/// buckets the average per day.
struct ReportTooltip: View {
    var bucket: ChartBucket

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.tight) {
            Text(bucket.title).fontWeight(.semibold)
            if let note = bucket.partialNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(bucket.segments, id: \.key.value) { segment in
                HStack {
                    RoundedRectangle(cornerRadius: 2).fill(segment.key.color.fill).frame(width: 10, height: 10)
                    Text(segment.key.name)
                    Spacer(minLength: 16)
                    Text(ReportText.seconds(segment.seconds, padded: true)).monospacedDigit()
                }
            }
            Divider()
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer(minLength: 16)
                Text(ReportText.seconds(bucket.total, padded: true)).fontWeight(.semibold).monospacedDigit()
            }
            if let average = bucket.averagePerDay {
                HStack {
                    Text("Average per day")
                    Spacer(minLength: 16)
                    Text(ReportText.seconds(average, padded: true)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(Design.Spacing.medium)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: Design.Radius.card).fill(.background).shadow(radius: 4))
    }
}
