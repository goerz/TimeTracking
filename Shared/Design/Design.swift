// Design: spacing, radius, and color tokens of the design language
// (spec_design.md §3, §6).

import SwiftUI

/// The shared layout values; views use these instead of literals.
enum Design {
    /// The width of the Calendar's sleep and workout lines.
    static let healthLineWidth: CGFloat = 4

    enum Spacing {
        /// Icon to label, dot to text.
        static let tight: CGFloat = 4
        /// Dense rows: vertical row padding in popups and compact tables, a
        /// highlight's inset, and the status menu header's symbol gap.
        static let compact: CGFloat = 6
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
        /// Calendar cards, swatches, tags, list row highlights.
        static let small: CGFloat = 6
    }

    /// Circle button diameters (spec_design.md §7).
    enum CircleDiameter {
        #if os(macOS)
            /// Start, stop, discard, and Pomodoro in the Timer's running-entry bar.
            static let bar: CGFloat = 32
            /// Continue in list rows, shown on hover and selection.
            static let row: CGFloat = 24
        #else
            /// Start, stop, discard, and Pomodoro on the Timer card.
            static let bar: CGFloat = 44
            /// Continue in list rows.
            static let row: CGFloat = 32
        #endif
    }
}

extension Color {
    /// Start and continue buttons.
    static let startTint = Color.green
    /// Stop buttons.
    static let stopTint = Color.red
    /// Error messages under a control or in a dialog.
    static let errorText = Color.red
    /// The tracker's block cards in the Calendar's Activity column, one
    /// neutral color for every context.
    static let activityBlock = Color.secondary
    /// Saturdays and Sundays in the Calendar, a shade darker than weekdays
    /// (lighter in dark mode).
    static let weekendTint = Color.primary.opacity(0.035)
    /// Sleep from Apple Health in the Calendar's Activity column (dark blue).
    static let sleepLine = Color(red: 0.11, green: 0.22, blue: 0.56)
    /// Workouts from Apple Health there (dark green).
    static let workoutLine = Color(red: 0.07, green: 0.42, blue: 0.20)
}

extension View {
    /// A card (spec_design.md §3): the secondary background in the card radius.
    func cardBackground() -> some View {
        background(.background.secondary, in: .rect(cornerRadius: Design.Radius.card))
    }
}
