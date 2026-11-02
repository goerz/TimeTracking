// BlockPopover: an activity block's range, items, secondaries, and
// Create Entry… (spec_calendar.md §3.2).

import SwiftUI
import TimeTrackingCore

/// The block popover: range, items, secondaries, Create Entry… (§3.2).
struct BlockPopover: View {
    var model: CalendarModel
    var block: ActivityBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            header
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(ActivityContext(item.context).label()).fontWeight(.semibold)
                    Text([item.subject, item.detail].filter { !$0.isEmpty }.joined(separator: " ")).lineLimit(1)
                    Spacer()
                    if block.devices.count > 1 {
                        Text(ActivityContext.deviceName(item.device)).foregroundStyle(.secondary)
                    }
                    Text(ActivityText.duration(item.seconds)).monospacedDigit()
                }
                .font(.caption)
            }
            ForEach(Array(block.background.enumerated()), id: \.offset) { _, item in
                let title = ActivityBackgroundRow.title(context: item.context, subject: item.subject)
                Text("In the background: \(title), \(ActivityText.duration(item.seconds))").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Create Entry…") { model.createEntry(from: block) }
        }
        .padding()
        .frame(width: 340)
    }

    /// Range, duration, devices; the group key's share; active time; reconstructed time.
    @ViewBuilder private var header: some View {
        let zone = model.calendar.timeZone
        let span = Int(block.end.timeIntervalSince(block.start))
        Text("\(CalendarText.range(block.start, block.end, zone: zone)) · \(ActivityText.duration(span)) · \(device)")
            .font(.headline)
        Text("\(ActivityContext.groupKeyName(block.groupKey)), \(Int((block.groupShare * 100).rounded()))% of this time")
            .foregroundStyle(.secondary)
        if block.activeSeconds < span {
            Text("\(ActivityText.duration(span)), \(ActivityText.duration(block.activeSeconds)) active").foregroundStyle(.secondary)
        }
        if block.reconstructedSeconds > 0 {
            let text = block.reconstructedSeconds >= block.activeSeconds
                ? "Reconstructed from macOS app usage history"
                : "\(ActivityText.duration(block.reconstructedSeconds)) reconstructed from macOS app usage history"
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The devices, with their active time when there are several; `remote`
    /// reads "Other devices (Safari)".
    private var device: String {
        guard block.devices.count > 1 else {
            return block.deviceNames.first.map(ActivityContext.deviceName) ?? ""
        }
        return block.devices.map { "\(ActivityContext.deviceName($0.name)) \(ActivityText.duration($0.seconds))" }
            .joined(separator: ", ")
    }
}
