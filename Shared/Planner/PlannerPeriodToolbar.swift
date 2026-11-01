// PlannerPeriodToolbar: the leading toolbar items that Calendar, Reports,
// Projects, and Activity share: the period arrows, the Calendar's Go to Today, and the
// section's date control (spec_design.md §4; spec_planner_projects.md §1.1).

import SwiftUI
import TimeTrackingCore

/// Previous and next as one group; a fixed gap; then the section's date
/// controls as a second group: in the Calendar Go to Today and Go to
/// Date…, in Reports, Projects, and Activity the range menu. The items sit
/// in `.navigation`, so the arrows keep their place when the section
/// changes.
struct PlannerPeriodToolbar<DateControl: View>: ToolbarContent {
    /// "Previous Day", "Previous Period".
    var previousTitle: String
    var nextTitle: String
    var canShift = true
    /// The accessibility identifier prefix: `range` or `calendar`.
    var identifier: String
    var previous: () -> Void
    var next: () -> Void
    /// Go to Today, only in the Calendar (the other sections have ⌘T).
    var goToToday: GoToToday?
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
        // Keeps the date controls in a capsule of their own.
        ToolbarSpacer(.fixed, placement: .navigation)
        ToolbarItemGroup(placement: .navigation) {
            if let goToToday {
                // Re-read every minute, so the date on the symbol turns at midnight.
                TimelineView(.everyMinute) { _ in
                    Button(action: goToToday.action) {
                        Label("Go to Today", systemImage: SymbolName.today(goToToday.currentDay()))
                    }
                    .help("Go to Today")
                    .accessibilityIdentifier("\(identifier).today")
                }
            }
            dateControl()
        }
        .visibilityPriority(.high)
    }
}

/// The Go to Today button's action and today's day from the section's clock
/// (its symbol shows the day of the month).
struct GoToToday {
    var action: () -> Void
    var currentDay: () -> TrackingDay
}
