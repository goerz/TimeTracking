// PlannerPeriodToolbar: the leading toolbar items that Calendar, Reports,
// and Activity share: the period arrows and Today with its date menu
// (spec_design.md §4; spec_planner_projects.md §1.1).

import SwiftUI
import TimeTrackingCore

/// Previous and next as one control group, then Today; Today's menu holds
/// the section's date choices. The items sit in `.navigation`, so they keep
/// their place when the section changes.
struct PlannerPeriodToolbar<DateMenu: View, DatePopover: View>: ToolbarContent {
    /// "Previous Day", "Previous Period".
    var previousTitle: String
    var nextTitle: String
    var canShift = true
    /// The accessibility identifier prefix: `range` or `calendar`.
    var identifier: String
    var previous: () -> Void
    var next: () -> Void
    var today: () -> Void
    @ViewBuilder var dateMenu: () -> DateMenu
    /// The date popover, anchored to Today.
    @Binding var showsPopover: Bool
    @ViewBuilder var datePopover: () -> DatePopover

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
            Menu {
                dateMenu()
            } label: {
                Text("Today")
            } primaryAction: {
                today()
            }
            .help("Go to Today")
            .accessibilityIdentifier("\(identifier).today")
            .popover(isPresented: $showsPopover, arrowEdge: .bottom, content: datePopover)
        }
        .visibilityPriority(.high)
    }
}
