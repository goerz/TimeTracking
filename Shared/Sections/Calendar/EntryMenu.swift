// EntryMenu: the calendar cards' context menu, a popover on the iPad
// (spec_calendar.md §5; spec_ios.md §10.2).

import SwiftUI

/// The context menu on the Mac; on the iPad, where a long press lifts the
/// item, the same buttons in a popover that a long press without a drag
/// opens (spec_ios.md §10.2).
struct EntryMenu<Items: View>: ViewModifier {
    @Binding var showsMenu: Bool
    @ViewBuilder var items: () -> Items

    func body(content: Content) -> some View {
        #if os(iOS)
            content.popover(isPresented: $showsMenu) {
                VStack(alignment: .leading, spacing: 0) {
                    Group { items() }
                        .buttonStyle(.borderless)
                        .padding(.horizontal, Design.Spacing.large)
                        .padding(.vertical, Design.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .simultaneousGesture(TapGesture().onEnded { showsMenu = false })
                }
                .frame(minWidth: 220)
                .padding(.vertical, Design.Spacing.compact)
                .presentationCompactAdaptation(.popover)
                .accessibilityIdentifier("calendar.menu")
            }
        #else
            content.contextMenu { items() }
        #endif
    }
}
