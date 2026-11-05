// ActivityRowAction: a row of the Apps or Subjects list that a click and
// Space act on (spec_activity.md §1.6, §2).

import SwiftUI

/// A click or, while the row has the focus, Space performs `action`; a row
/// without an action takes no focus.
struct ActivityRowAction: ViewModifier {
    var identifier: String
    var action: (() -> Void)?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: Design.Radius.small).fill(focused ? Color.accentColor.opacity(0.12) : .clear))
            .focusable(action != nil)
            .focusEffectDisabled()
            .focused($focused)
            .onTapGesture {
                if let action {
                    focused = true
                    action()
                }
            }
            .onKeyPress(.space) {
                action?()
                return .handled
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)
    }
}
