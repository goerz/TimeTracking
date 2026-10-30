// ActivityPanels: heatmap, bars by day, Contexts, Subjects, In the
// background, and Away (spec_planner_activity.md §1.4 to §1.8).

import Charts
import SwiftUI
import TimeTrackingCore

/// The panels in two columns above 1100 points, one below.
struct ActivityPanels: View {
    var model: ActivityModel
    var summary: ActivitySummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    HeatmapPanel(model: model, summary: summary)
                    ContextsPanel(model: model, summary: summary)
                    BackgroundPanel(summary: summary)
                }
                .frame(width: 540)
                VStack(spacing: 16) {
                    BarsPanel(model: model, summary: summary)
                    SubjectsPanel(model: model)
                    AwayPanel(summary: summary)
                }
                .frame(width: 540)
            }
            VStack(spacing: 16) {
                HeatmapPanel(model: model, summary: summary)
                BarsPanel(model: model, summary: summary)
                ContextsPanel(model: model, summary: summary)
                SubjectsPanel(model: model)
                BackgroundPanel(summary: summary)
                AwayPanel(summary: summary)
            }
        }
    }
}

/// A card (12 pt corners, 16 pt padding).
private struct Panel<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
    }
}

// MARK: Heatmap

private struct HeatmapPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary

    var body: some View {
        let heatmap = summary.heatmap
        let cell: CGFloat = heatmap.mode == .days ? 14 : 12
        let gap: CGFloat = heatmap.mode == .days ? 3 : 2
        Panel(title: "Active time by hour") {
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {
                    Color.clear.frame(width: 70, height: 10)
                    ForEach(0 ..< 24, id: \.self) { hour in
                        Text(ActivityHeatmap.labeledHours.contains(hour) ? "\(hour)" : "").font(.caption2).frame(width: cell)
                    }
                }
                ForEach(Array(heatmap.rows.enumerated()), id: \.element.id) { _, row in
                    rowView(row, cell: cell, gap: gap)
                }
                if let footer = heatmap.footer {
                    rowView(footer, cell: cell, gap: gap, footer: true)
                }
                legend(cell: cell)
            }
        }
        .accessibilityIdentifier("activity.heatmap")
    }

    private func rowView(_ row: ActivityHeatmap.Row, cell: CGFloat, gap: CGFloat, footer: Bool = false) -> some View {
        HStack(spacing: gap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.label)
                if let sublabel = row.sublabel {
                    Text(sublabel).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(row.isEmpty ? .tertiary : .primary)
            .frame(width: 70, alignment: .leading)
            ForEach(0 ..< 24, id: \.self) { hour in
                RoundedRectangle(cornerRadius: 2)
                    .fill(shade(row.minutes[hour]))
                    .frame(width: cell, height: cell)
                    .help(footer ? summary.footerTooltip(hour: hour) : tooltip(row, hour))
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { model.showInCalendar(row: row, hour: hour) }
                    .focusable()
            }
            Text(row.totalText).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
        }
    }

    private func tooltip(_ row: ActivityHeatmap.Row, _ hour: Int) -> String {
        let tip = summary.cellTooltip(row: row, hour: hour)
        let lines = tip.lines.map { line in
            "\(model.displayName(line.context))  \(line.text)  \(ActivityText.duration(line.seconds))"
                + (line.device.map { " (\($0))" } ?? "")
        }
        return ([tip.title, tip.summary, ""] + lines + [tip.moreText].compactMap(\.self)).joined(separator: "\n")
    }

    private func shade(_ minutes: Double) -> Color {
        let level = ActivityHeatmap.level(minutes: minutes)
        return level == 0 ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(Double(level) * 0.25)
    }

    private func legend(cell: CGFloat) -> some View {
        HStack(spacing: 3) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0 ..< 5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(Double(level) * 0.25))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: Bars

private struct BarsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.contextColors) private var colors

    var body: some View {
        let bars = summary.bars
        Panel(title: "Active time by day") {
            Chart {
                ForEach(bars.bars) { bar in
                    ForEach(bar.segments, id: \.series) { segment in
                        BarMark(x: .value("Day", bar.id), y: .value("Hours", Double(segment.seconds) / 3600))
                            .foregroundStyle(color(segment.series))
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel { axisLabel(value.as(String.self).flatMap { id in bars.bars.first { $0.id == id } }) }
                }
            }
            .chartYScale(domain: 0 ... Double(bars.axisHours))
            .chartOverlay { proxy in
                GeometryReader { _ in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture { location in
                            if let id: String = proxy.value(atX: location.x), let bar = bars.bars.first(where: { $0.id == id }) {
                                model.showInCalendar(bar: bar, series: nil)
                            }
                        }
                }
            }
            .frame(height: 220)
        }
        .accessibilityIdentifier("activity.bars")
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

// MARK: Contexts and subjects

private struct ContextsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.contextColors) private var colors

    var body: some View {
        let rows = summary.contextRows
        let largest = rows.map(\.seconds).max() ?? 1
        Panel(title: "Contexts") {
            ForEach(rows.prefix(model.showsAllContexts ? rows.count : 20)) { row in
                rowView(row, largest: largest)
            }
            if rows.count > 20, !model.showsAllContexts {
                Button("Show all (\(rows.count))") { model.showsAllContexts = true }.buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("activity.contexts")
    }

    private func rowView(_ row: ActivityContextRow, largest: Int) -> some View {
        HStack {
            if let context = row.context {
                ContextGlyph(context: context)
                Text(model.displayName(context))
                if ActivityContext(context).kind == .session {
                    Text("session").font(.caption2).padding(.horizontal, 4).overlay(Capsule().stroke(.secondary))
                }
            } else {
                Text("Not itemized").foregroundStyle(.secondary)
            }
            Spacer()
            Capsule().fill(row.context == nil || row.isPrivate ? Color.gray : colors.color(row.context))
                .frame(width: 160 * CGFloat(row.seconds) / CGFloat(max(largest, 1)), height: 8)
            Text(ActivityText.duration(row.seconds)).frame(width: 64, alignment: .trailing)
            Text("\(Int((row.share * 100).rounded()))%").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            if let context = row.context {
                Task { await model.toggle(context) }
            }
        }
        .contextMenu {
            if let context = row.context {
                Button("Show Only \(model.displayName(context))") { Task { await model.showOnly(context) } }
                Button("Show in Calendar") { model.showContextInCalendar(context) }
                if model.isRecordingMac, ActivityContext(context).kind != .browser {
                    Button("Exclude \(model.displayName(context)) from tracking…") { model.exclude(context: context) }
                }
            }
        }
    }
}

private struct SubjectsPanel: View {
    @Bindable var model: ActivityModel

    var body: some View {
        Panel(title: "Where the time went") {
            Picker("Kind", selection: $model.subjectKind) {
                ForEach(ActivitySubjectKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if let detail = model.drillDetail {
                drill(detail)
            } else {
                list
            }
        }
        .accessibilityIdentifier("activity.subjects")
    }

    @ViewBuilder private var list: some View {
        let rows = model.subjectRows
        let largest = rows.map(\.seconds).max() ?? 1
        ForEach(rows.prefix(model.showsAllSubjects ? rows.count : 20)) { row in
            HStack {
                ForEach(row.contexts.prefix(2), id: \.self) { ContextGlyph(context: $0) }
                Text(row.subject ?? "Other (not itemized)").foregroundStyle(row.subject == nil ? .secondary : .primary).lineLimit(1)
                Spacer()
                Capsule().fill(Color.accentColor).frame(width: 140 * CGFloat(row.seconds) / CGFloat(max(largest, 1)), height: 8)
                Text(ActivityText.duration(row.seconds)).frame(width: 64, alignment: .trailing)
                if model.isRecordingMac, row.hasDetails {
                    Image(systemName: "chevron.right").accessibilityHidden(true).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .onTapGesture { model.open(row) }
            .contextMenu {
                if model.isRecordingMac, let subject = row.subject, row.contexts.contains(where: { ActivityContext($0).kind == .browser }) {
                    Button("Exclude \(ActivityContext.domain(ofSite: subject)) from tracking…") { model.exclude(site: subject) }
                }
            }
        }
        if rows.count > 20, !model.showsAllSubjects {
            Button("Show all (\(rows.count))") { model.showsAllSubjects = true }.buttonStyle(.link)
        }
        if !model.isRecordingMac {
            Text("Details stay on the Mac that recorded them").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func drill(_ detail: ActivitySubjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(model.displayName(detail.context)) { model.closeDrill() }.buttonStyle(.link)
                Text("› \(detail.subject)")
                if let visited = detail.visitedText {
                    Text("· \(visited)").foregroundStyle(.secondary)
                }
            }
            if let coverage = detail.coverageText {
                Text(coverage).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(detail.lines) { line in
                HStack {
                    Text(line.detail).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(line.seconds))
                }
            }
        }
    }
}

// MARK: Background and Away

private struct BackgroundPanel: View {
    var summary: ActivitySummary

    var body: some View {
        let rows = summary.backgroundRows
        if !rows.isEmpty {
            Panel(title: "In the background", subtitle: "Does not count as active time") {
                ForEach(rows) { row in
                    HStack {
                        Image(systemName: "gearshape").accessibilityHidden(true).foregroundStyle(.secondary)
                        Text(row.title)
                        Spacer()
                        Text(ActivityText.duration(row.seconds))
                    }
                }
            }
            .accessibilityIdentifier("activity.background")
        }
    }
}

private struct AwayPanel: View {
    var summary: ActivitySummary

    var body: some View {
        let away = summary.away
        Panel(title: "Away") {
            Text(away.totalText).bold()
            if !away.parts.isEmpty {
                Text(away.partsText).foregroundStyle(.secondary)
            }
            Text("Night (before the first and after the last block of a day) is not counted.").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("activity.away")
    }
}
