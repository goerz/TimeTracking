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

    /// Range, duration, device; the group key's share; active time; the source.
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
        if block.source == .knowledge {
            Text("Reconstructed from macOS app usage history").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The recording device; `remote` reads "Other devices (Safari)".
    private var device: String {
        ActivityContext.deviceName(block.device)
    }
}
