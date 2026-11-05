// CreateEntryButton: the "+" a card shows on hover (spec_calendar.md §3.3,
// §4.4).

import SwiftUI
import TimeTrackingCore

/// The "+" at a card's top trailing corner.
struct CreateEntryButton: View {
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: SymbolName.addCircle) }
            .buttonStyle(.plain)
            .foregroundStyle(tint)
            .padding(Design.Spacing.tight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .help("Create Entry…")
            .accessibilityLabel("Create Entry")
            .accessibilityIdentifier("calendar.createEntry")
    }
}
