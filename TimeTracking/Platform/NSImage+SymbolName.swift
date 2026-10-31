// NSImage+SymbolName: symbol images for the status item and its menu, SF
// Symbols or the app's own (spec_design.md §5, spec_menubar.md §1.1).

import AppKit
import TimeTrackingCore

extension NSImage {
    /// The SF Symbol `name`, or the app's own symbol of that name.
    static func symbol(_ name: String) -> NSImage? {
        if SymbolName.isCustom(name) {
            return NSImage(symbolName: name, bundle: .main, variableValue: 1)
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}
