// Image+SymbolName: one initializer for SF Symbols and the app's own symbols
// (design.md §5).

import SwiftUI
import TimeTrackingCore

extension Image {
    /// The SF Symbol `name`, or the app's own symbol of that name.
    init(symbol name: String) {
        if SymbolName.isCustom(name) {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}
