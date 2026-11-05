// ErrorLine: an error under a control, the warning symbol and the message
// in the error color (design.md §6, §7).

import SwiftUI
import TimeTrackingCore

/// An error under a control: the warning symbol and the message.
struct ErrorLine: View {
    var text: String

    // The caption size beside Mac controls, the footnote size in iOS lists.
    #if os(macOS)
        private static let font = Font.caption
    #else
        private static let font = Font.footnote
    #endif

    var body: some View {
        Label(text, systemImage: SymbolName.warning)
            .font(Self.font)
            .foregroundStyle(Color.errorText)
    }
}
