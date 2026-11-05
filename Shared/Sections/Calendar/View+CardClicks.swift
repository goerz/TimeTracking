// View+CardClicks: a Calendar card's click and double-click
// (spec_calendar.md §2.5).

import SwiftUI

extension View {
    /// `onClick` on a click, `onDoubleClick` on the click that makes it a
    /// double-click. On the Mac one tap gesture reads the click count, so
    /// `onClick` runs at once: two tap gestures hold it back for the
    /// double-click time, and a ⌘ released by then is missed. A simultaneous
    /// double-tap gesture would stop `onHover` on the card.
    func cardClicks(onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) -> some View {
        #if os(macOS)
            onTapGesture {
                if ModifierState.clickCount() > 1 {
                    onDoubleClick()
                } else {
                    onClick()
                }
            }
        #else
            onTapGesture(count: 2, perform: onDoubleClick)
                .onTapGesture(perform: onClick)
        #endif
    }
}
