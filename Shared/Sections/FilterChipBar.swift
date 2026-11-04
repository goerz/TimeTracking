// FilterChipBar: the active filters as removable tokens at the top of the
// content, with Clear All, in Reports and the Calendar (spec_design.md §4;
// spec_reports.md §3; spec_calendar.md §1.6).

import SwiftUI
import TimeTrackingCore

/// One token per checked client, area, or project, "No project", and the
/// archived exclusion, each removed with its ×, then "Clear All".
struct FilterChipBar: View {
    var chips: [ReportFilterChip]
    /// The identifiers' prefix: `reports` or `calendar`.
    var identifier: String
    var remove: (ReportFilterChip.Kind) -> Void
    var clearAll: () -> Void

    var body: some View {
        HStack(spacing: Design.Spacing.small) {
            Image(systemName: SymbolName.filter)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            ForEach(chips) { chip in
                Button {
                    remove(chip.kind)
                } label: {
                    HStack(spacing: Design.Spacing.tight) {
                        Text(chip.text)
                        Image(systemName: SymbolName.discard).imageScale(.small).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help("Remove Filter")
                .accessibilityIdentifier("\(identifier).chip")
            }
            Button("Clear All", action: clearAll)
                .buttonStyle(.borderless)
                .controlSize(.small)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifier).filterBar")
    }
}
