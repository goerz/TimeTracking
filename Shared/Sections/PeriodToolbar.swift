// PeriodToolbar: the leading toolbar items that Calendar, Reports,
// Projects, and Activity share: the period arrows and the section's date
// menu (spec_design.md §4; spec_projects.md §1.1).

import SwiftUI
import TimeTrackingCore

/// Previous and next as one group, then the section's date menu, a text
/// menu that the system draws in a capsule of its own: the Calendar's (Go
/// to Today, Go to Date…) or the range menu of Reports, Projects, and
/// Activity. The items sit in `.navigation`, so the arrows keep their place
/// when the section changes.
struct PeriodToolbar<DateControl: View>: ToolbarContent {
    /// "Previous Day", "Previous Period".
    var previousTitle: String
    var nextTitle: String
    var canShift = true
    /// The accessibility identifier prefix: `range` or `calendar`.
    var identifier: String
    var previous: () -> Void
    var next: () -> Void
    /// The section's date menu, which anchors its own popover.
    @ViewBuilder var dateControl: () -> DateControl

    var body: some ToolbarContent {
        // One group, so the system draws the arrows as one glass capsule.
        ToolbarItemGroup(placement: .navigation) {
            Button(action: previous) {
                Label(previousTitle, systemImage: SymbolName.previous)
            }
            .help(previousTitle)
            .disabled(!canShift)
            .accessibilityIdentifier("\(identifier).previous")
            Button(action: next) {
                Label(nextTitle, systemImage: SymbolName.next)
            }
            .help(nextTitle)
            .disabled(!canShift)
            .accessibilityIdentifier("\(identifier).next")
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .navigation) {
            dateControl()
        }
        .visibilityPriority(.high)
    }
}
