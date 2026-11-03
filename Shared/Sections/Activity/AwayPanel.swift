// AwayPanel: the time away (spec_activity.md §1.8).

import SwiftUI
import TimeTrackingCore

/// The time away, nights not counted (§1.8).
struct AwayPanel: View {
    var summary: ActivitySummary

    var body: some View {
        let away = summary.away
        ActivityPanel(title: "Away") {
            Text(away.totalText).fontWeight(.semibold).monospacedDigit()
            if !away.parts.isEmpty {
                Text(away.partsText).foregroundStyle(.secondary)
            }
            if let text = away.backgroundText {
                Text(text).foregroundStyle(.secondary)
            }
            Text("Time before your first and after your last activity of the day is not counted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("activity.away")
    }
}
