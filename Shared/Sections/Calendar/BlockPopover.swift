// BlockPopover: an activity block's summary with every item, and Create
// Entry… (calendar.md §3.2; activity_tracking.md §2.8).

import SwiftUI
import TimeTrackingCore

/// The summary's header and footer, every foreground item grouped by
/// workspace, every background item, and Create Entry… (§3.2).
struct BlockPopover: View {
    var model: CalendarModel
    var block: ActivityBlock

    var body: some View {
        let summary = ActivityBlockSummary(block: block, settings: model.activity.settings, extent: .everything)
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            Text(BlockSummaryText.range(summary, zone: model.calendar.timeZone)).font(.headline)
            Text(BlockSummaryText.detail(summary)).foregroundStyle(.secondary)
            groupRows(summary)
            backgroundRows(summary)
            if let footer = BlockSummaryText.footer(summary) {
                Text(footer).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button("Create Entry…") { model.createEntry(from: block) }
        }
        .padding()
        .frame(width: 360)
    }

    /// Every foreground item, grouped by workspace.
    private func groupRows(_ summary: ActivityBlockSummary) -> some View {
        ForEach(summary.groups, id: \.workspace) { group in
            HStack {
                Text(group.name).fontWeight(.semibold)
                if !group.subtitle.isEmpty {
                    Text(group.subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(ActivityText.duration(group.seconds)).monospacedDigit()
                Text("\(Int((group.share * 100).rounded()))%").foregroundStyle(.secondary)
            }
            ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                HStack {
                    if let device = line.otherDevice {
                        Text(ActivityDeviceName.display(device)).font(.caption2).foregroundStyle(.orange)
                    }
                    Text(line.label).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(line.seconds)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.leading, Design.Spacing.medium)
            }
        }
        .font(.caption)
    }

    /// Every background item, under a heading.
    @ViewBuilder
    private func backgroundRows(_ summary: ActivityBlockSummary) -> some View {
        if !summary.background.isEmpty {
            Text("Background").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(summary.background.enumerated()), id: \.offset) { _, line in
                HStack {
                    Text(line.label).lineLimit(1)
                    Text(line.workspaceName).foregroundStyle(.secondary)
                    Spacer()
                    Text(ActivityText.duration(line.seconds)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
