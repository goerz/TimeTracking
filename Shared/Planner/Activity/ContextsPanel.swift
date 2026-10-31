// ContextsPanel: the contexts by active time (spec_planner_activity.md §1.6).

import SwiftUI
import TimeTrackingCore

/// The contexts by active time (§1.6).
struct ContextsPanel: View {
    var model: ActivityModel
    var summary: ActivitySummary
    @Environment(\.contextColors) private var colors

    var body: some View {
        let rows = summary.contextRows
        let largest = rows.map(\.seconds).max() ?? 1
        ActivityPanel(title: "Apps") {
            ForEach(rows.prefix(model.showsAllContexts ? rows.count : 20)) { row in
                rowView(row, largest: largest)
            }
            if rows.count > 20, !model.showsAllContexts {
                Button("Show all (\(rows.count))") { model.showsAllContexts = true }.buttonStyle(.borderless)
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
                    Text("tmux").font(.caption2).padding(.horizontal, Design.Spacing.tight).overlay(Capsule().stroke(.secondary))
                }
            } else {
                Text("Brief activity").foregroundStyle(.secondary)
                    .help("Activity too short to list separately")
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
                    Button("Exclude \(model.displayName(context)) from Tracking…") { model.exclude(context: context) }
                }
            }
        }
    }
}
