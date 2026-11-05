// HeatmapPanel: active time by hour (spec_activity.md §1.4).

import SwiftUI
import TimeTrackingCore

/// Active time by hour, a row per day or week (§1.4).
struct HeatmapPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @FocusState private var isFocused: Bool

    var body: some View {
        let heatmap = summary.heatmap
        let cell: CGFloat = heatmap.mode == .days ? 14 : 12
        let gap: CGFloat = heatmap.mode == .days ? 3 : 2
        let hours = ActivityHeatmap.columns(midnightHour: model.range.calendar.midnightHour)
        ActivityPanel(title: "Active time by hour") {
            // A click beside the cells only takes the focus; the cells are the buttons.
            // swiftlint:disable:next accessibility_trait_for_button
            VStack(alignment: .leading, spacing: gap) {
                HStack(spacing: gap) {
                    Color.clear.frame(width: 56, height: 10)
                    ForEach(hours, id: \.self) { hour in
                        Text(ActivityHeatmap.labeledHours.contains(hour) ? "\(hour)" : "").font(.caption).frame(width: cell)
                    }
                }
                ForEach(Array(heatmap.rows.enumerated()), id: \.element.id) { _, row in
                    rowView(row, hours: hours, cell: cell, gap: gap)
                }
                if let footer = heatmap.footer {
                    rowView(footer, hours: hours, cell: cell, gap: gap, footer: true)
                }
                legend(cell: cell)
                if let text = details(heatmap) {
                    Text(text).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("activity.cell.details")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .activityPanelKeys(isFocused: $isFocused, onFocus: model.heatmapFocused, perform: handle)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.heatmap")
    }

    /// The arrows move, Space shows or hides the details, Return drills down (§2).
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if let move = ActivityFocusMove(press.key) {
            model.moveFocusedCell(move)
        } else if press.key == .space {
            model.showsCellDetails.toggle()
        } else {
            model.openFocusedCell()
        }
        return .handled
    }

    /// The tooltip of the focused cell, while Space shows it.
    private func details(_ heatmap: ActivityHeatmap) -> String? {
        guard isFocused, model.showsCellDetails, let cell = model.focusedCell, let row = heatmap.row(of: cell) else {
            return nil
        }
        return row.id == heatmap.footer?.id ? summary.footerTooltip(hour: cell.hour) : tooltip(row, cell.hour)
    }

    private func rowView(_ row: ActivityHeatmap.Row, hours: [Int], cell: CGFloat, gap: CGFloat, footer: Bool = false) -> some View {
        HStack(spacing: gap) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.label)
                if let sublabel = row.sublabel {
                    Text(sublabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(row.isEmpty ? .tertiary : .primary)
            .frame(width: 56, alignment: .leading)
            ForEach(hours, id: \.self) { hour in
                let focused = isFocused && model.focusedCell == ActivityHeatmap.Cell(row: row.id, hour: hour)
                RoundedRectangle(cornerRadius: 2)
                    .fill(shade(row.minutes[hour]))
                    .frame(width: cell, height: cell)
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: 2).stroke(Color.primary, lineWidth: 1.5)
                        }
                    }
                    .help(footer ? summary.footerTooltip(hour: hour) : tooltip(row, hour))
                    .accessibilityAddTraits(.isButton)
                    .onTapGesture { model.showInCalendar(row: row, hour: hour) }
                    .accessibilityValue(focused ? "focused" : "")
                    .accessibilityIdentifier("activity.cell.\(row.id).\(hour)")
            }
            Text(row.totalText).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
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
            Text("Less").font(.caption).foregroundStyle(.secondary)
            ForEach(0 ..< 5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(Double(level) * 0.25))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(.caption).foregroundStyle(.secondary)
        }
    }
}
