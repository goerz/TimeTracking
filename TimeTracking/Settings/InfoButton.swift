// InfoButton: the info button of a settings row (spec_activity_tracking.md
// §7.4, spec_timer_window.md §8.1).

import SwiftUI
import TimeTrackingCore

/// The info button at a settings row's trailing edge: `info.circle`,
/// borderless, opening a popover with the explanation and, where there is
/// one, the snippet and its Copy button.
struct InfoButton: View {
    var info: SettingsInfo
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Label("About \(info.title)", systemImage: SymbolName.info).labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("About \(info.title)")
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            InfoPopover(info: info)
        }
    }
}

/// The popover's content: title, paragraphs, snippet.
private struct InfoPopover: View {
    var info: SettingsInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            Text(info.title).font(.headline)
            ForEach(Array(info.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).fixedSize(horizontal: false, vertical: true)
            }
            if let snippet = info.snippet {
                ScrollView(.horizontal) {
                    Text(snippet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(Design.Spacing.small)
                }
                .background(.quaternary, in: .rect(cornerRadius: Design.Radius.small))
                HStack {
                    Spacer()
                    CopyButton(title: "Copy", text: snippet)
                }
            }
        }
        .padding(Design.Spacing.large)
        .frame(width: 400)
    }
}
