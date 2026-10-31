// PlannerPeriodToolbar: the leading toolbar items that Calendar, Reports,
// and Activity share: the period arrows, Today, and the section's date
// control (spec_design.md §4; spec_planner_projects.md §1.1).

import SwiftUI
import TimeTrackingCore

/// Previous and next as one control group, then Today, then the section's
/// date control (Calendar: Go to Date…; Reports and Activity: the range
/// menu). The items sit in `.navigation`, so they keep their place when the
/// section changes.
struct PlannerPeriodToolbar<DateControl: View>: ToolbarContent {
    /// "Previous Day", "Previous Period".
    var previousTitle: String
    var nextTitle: String
    var canShift = true
    /// The accessibility identifier prefix: `range` or `calendar`.
    var identifier: String
    var previous: () -> Void
    var next: () -> Void
    var today: () -> Void
    /// The section's date control, which anchors its own popover.
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
            Button(action: today) {
                Label("Go to Today", systemImage: SymbolName.today)
            }
            .help("Go to Today")
            .accessibilityIdentifier("\(identifier).today")
        }
        .visibilityPriority(.high)
        ToolbarItem(placement: .navigation) {
            dateControl()
        }
        .visibilityPriority(.high)
    }
}
