// CopyButton: a button that copies text and says so (spec_design.md §7.1).

import SwiftUI
import TimeTrackingCore

/// A button that copies `text` and says so for two seconds, at the width of
/// its longer title so nothing beside it moves (spec_design.md §7.1).
struct CopyButton: View {
    var title: String
    var text: String
    /// Text-only beside other text buttons; with the symbols in the popover.
    var showsIcon = true
    @State private var copied = false

    var body: some View {
        Button {
            Pasteboard.copy(text)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            if showsIcon {
                labels.labelStyle(.titleAndIcon)
            } else {
                labels.labelStyle(.titleOnly)
            }
        }
        .accessibilityValue(copied ? "Copied" : "")
    }

    /// Both titles, hidden, under the visible one: the button keeps its width.
    private var labels: some View {
        ZStack {
            Label(title, systemImage: SymbolName.copy).hidden()
            Label("Copied", systemImage: SymbolName.checkmark).hidden()
            Label(copied ? "Copied" : title, systemImage: copied ? SymbolName.checkmark : SymbolName.copy)
        }
    }
}
