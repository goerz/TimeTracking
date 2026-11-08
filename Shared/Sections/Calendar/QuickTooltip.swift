// QuickTooltip: the tooltip of the Activity column's thin lines, shown at
// once on hover (calendar.md §3.1).

import SwiftUI

/// A tooltip that appears as soon as the pointer is over the view, at the
/// pointer's height and to the view's leading side. The system tooltip
/// waits for the pointer to rest, which a 4-point line makes hard.
struct QuickTooltip: ViewModifier {
    var text: String
    @State private var pointerY: CGFloat?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    pointerY = location.y
                case .ended:
                    pointerY = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let pointerY {
                    let gap = Design.Spacing.small
                    Text(text)
                        .font(.caption)
                        .fixedSize()
                        .padding(.horizontal, Design.Spacing.small)
                        .padding(.vertical, Design.Spacing.tight)
                        .background(RoundedRectangle(cornerRadius: Design.Radius.card).fill(.background).shadow(radius: 4))
                        .alignmentGuide(.leading) { $0[.trailing] + gap }
                        .alignmentGuide(.top) { $0[VerticalAlignment.center] - pointerY }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            // Over the blocks drawn after it in the column.
            .zIndex(pointerY == nil ? 0 : 1)
    }
}

extension View {
    /// `text` as a tooltip that shows at once on hover.
    func quickTooltip(_ text: String) -> some View {
        modifier(QuickTooltip(text: text))
    }
}
