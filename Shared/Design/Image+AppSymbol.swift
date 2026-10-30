// Image+AppSymbol: one initializer for SF Symbols and the app's own symbols
// (spec_design.md §5).

import SwiftUI

extension Image {
    /// The SF Symbol `name`, or the app's own symbol of that name.
    init(symbol name: String) {
        if AppSymbol.isCustom(name) {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}
