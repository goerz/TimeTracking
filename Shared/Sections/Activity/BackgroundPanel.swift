// BackgroundPanel: in the background (spec_activity.md §1.7).

import SwiftUI
import TimeTrackingCore

/// "In the background", which does not count as active time (§1.7).
struct BackgroundPanel: View {
    var summary: ActivitySummary

    var body: some View {
        let rows = summary.backgroundRows
        if !rows.isEmpty {
            ActivityPanel(title: "In the background", subtitle: "Does not count as active time") {
                ForEach(rows) { row in
                    HStack {
                        Image(systemName: SymbolName.settings).accessibilityHidden(true).foregroundStyle(.secondary)
                        Text(row.title)
                        Spacer()
                        if row.awaySeconds > 0 {
                            Text("\(ActivityText.duration(row.awaySeconds)) while away").foregroundStyle(.secondary)
                        }
                        Text(ActivityText.duration(row.seconds))
                    }
                }
            }
            .accessibilityIdentifier("activity.background")
        }
    }
}
