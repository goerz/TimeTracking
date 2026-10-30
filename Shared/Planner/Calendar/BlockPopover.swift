// BlockPopover: an activity block's range, items, secondaries, suggestion,
// and actions (spec_planner_calendar.md §3.2).

import SwiftUI
import TimeTrackingCore

/// The block popover: range, items, secondaries, suggestion, actions (§3.2).
struct BlockPopover: View {
    var model: CalendarModel
    var block: ActivityBlock
    @State private var candidates: [SuggestionCandidate] = []
    @State private var showsOthers = false

    var body: some View {
        let zone = model.calendar.timeZone
        let span = Int(block.end.timeIntervalSince(block.start))
        VStack(alignment: .leading, spacing: 8) {
            Text("\(CalendarText.range(block.start, block.end, zone: zone)) · \(ActivityText.duration(span)) · \(block.device)")
                .font(.headline)
            if block.activeSeconds < span {
                Text("\(ActivityText.duration(span)), \(ActivityText.duration(block.activeSeconds)) active").foregroundStyle(.secondary)
            }
            if block.source == .knowledge {
                Text("reconstructed").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.context).fontWeight(.semibold)
                    Text([item.subject, item.detail].filter { !$0.isEmpty }.joined(separator: " ")).lineLimit(1)
                    Spacer()
                    Text(ActivityText.duration(item.seconds)).monospacedDigit()
                }
                .font(.caption)
            }
            ForEach(Array(block.background.enumerated()), id: \.offset) { _, item in
                Text("+ \(item.context) \(item.subject) (busy \(ActivityText.duration(item.seconds)))").font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            suggestion
            HStack {
                Button("Create Entry…") { Task { await model.createEntry(from: block) } }
                if block.isOpen {
                    Button("Start Now") { Task { await model.startNow(block) } }
                }
            }
        }
        .padding()
        .frame(width: 340)
        .task { candidates = await model.suggestions(for: block) }
    }

    @ViewBuilder private var suggestion: some View {
        Text("Suggested").font(.caption).foregroundStyle(.secondary)
        if let top = candidates.first, top.isConfident {
            HStack {
                Text(CandidateText.title(top, model: model))
                Spacer()
                ConfidenceMeter(candidate: top)
                Button("Log") { Task { await model.log(block) } }
                    .accessibilityIdentifier("calendar.block.log")
            }
            DisclosureGroup("Other suggestions", isExpanded: $showsOthers) {
                ForEach(Array(candidates.dropFirst().prefix(2).enumerated()), id: \.offset) { _, candidate in
                    HStack {
                        Text(CandidateText.title(candidate, model: model))
                        Spacer()
                        ConfidenceMeter(candidate: candidate)
                    }
                }
            }
            .font(.caption)
        } else {
            Text("No confident suggestion").foregroundStyle(.secondary)
        }
    }
}
