// AppsPanel: the apps by active time (activity.md §1.6).

import SwiftUI
import TimeTrackingCore

/// The apps by active time (§1.6).
struct AppsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.appColors) private var colors

    var body: some View {
        let rows = summary.appRows
        let largest = rows.map(\.seconds).max() ?? 1
        ActivityPanel(title: "Apps") {
            ForEach(rows.prefix(model.showsAllApps ? rows.count : 20)) { row in
                rowView(row, largest: largest)
            }
            if rows.count > 20, !model.showsAllApps {
                Button("Show all (\(rows.count))") { model.showsAllApps = true }.buttonStyle(.borderless)
            }
        }
        .accessibilityIdentifier("activity.apps")
    }

    private func rowView(_ row: ActivityAppRow, largest: Int) -> some View {
        HStack {
            AppGlyph(app: row.app, kind: row.kind)
            Text(row.app)
            Spacer()
            Capsule().fill(colors.color(row.app))
                .frame(width: 160 * CGFloat(row.seconds) / CGFloat(max(largest, 1)), height: 8)
            Text(ActivityText.duration(row.seconds)).frame(width: 64, alignment: .trailing)
            Text("\(Int((row.share * 100).rounded()))%").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
        }
        .modifier(ActivityRowAction(identifier: "activity.app.\(row.app)") { Task { await model.toggle(row.app) } })
        .contextMenu {
            Button("Show Only \(row.app)") { Task { await model.showOnly(row.app) } }
            Button("Show in Calendar") { model.showAppInCalendar(row.app) }
            if model.isMac, row.kind != .browser, row.kind != .screenTime {
                Button("Exclude \(row.app) from Tracking…") { model.exclude(app: row.app) }
            }
        }
    }
}
