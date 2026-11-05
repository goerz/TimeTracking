// View+ActivityPanelKeys: the heatmap or chart as one stop of the keyboard
// focus (activity.md §2).

import SwiftUI
import TimeTrackingCore

extension View {
    /// The panel takes the focus as a whole and gets the arrows, Space, and
    /// Return; its cells or bars are the model's business.
    func activityPanelKeys(
        isFocused: FocusState<Bool>.Binding,
        onFocus: @escaping () -> Void,
        perform: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(isFocused)
            .onChange(of: isFocused.wrappedValue) { _, focused in
                if focused {
                    onFocus()
                }
            }
            .onKeyPress(keys: ActivityFocusMove.panelKeys, action: perform)
    }
}
