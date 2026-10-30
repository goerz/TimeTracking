// Design: spacing, radius, and color tokens of the design language
// (spec_design.md §3, §6).

import SwiftUI

/// The shared layout values; views use these instead of literals.
enum Design {
    enum Spacing {
        /// Icon to label, dot to text.
        static let tight: CGFloat = 4
        /// Between related controls; row internal spacing.
        static let small: CGFloat = 8
        /// Between groups in a bar or card.
        static let medium: CGFloat = 12
        /// Content insets on iOS; card padding.
        static let large: CGFloat = 16
        /// Content insets in Mac windows.
        static let window: CGFloat = 20
        // Content insets of a view shared by both apps: `window` on the
        // Mac, `large` on iOS.
        #if os(macOS)
            static let content: CGFloat = window
        #else
            static let content: CGFloat = large
        #endif
    }

    enum Radius {
        /// Cards: Reports, Activity, the iOS Timer card.
        static let card: CGFloat = 12
        /// Calendar cards, swatches, tags.
        static let small: CGFloat = 6
    }
}

extension Color {
    /// Start and continue buttons.
    static let startTint = Color.green
    /// Stop buttons.
    static let stopTint = Color.red
}
