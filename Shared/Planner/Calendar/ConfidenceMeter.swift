// ConfidenceMeter: a suggestion's four-segment confidence meter
// (spec_planner_calendar.md §3.2, §5.4).

import SwiftUI
import TimeTrackingCore

/// The four-segment confidence meter.
struct ConfidenceMeter: View {
    var candidate: SuggestionCandidate?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< 4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < (candidate?.meterSegments ?? 0) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 8)
            }
        }
        .help(candidate.map { "Confidence \(Int(($0.confidence * 100).rounded()))%" } ?? "No suggestion")
    }
}
