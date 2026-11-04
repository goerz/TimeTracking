// ViewDisplayItems: the View menu's navigation and each view's display
// options, on the Mac and the iPad (spec_timer.md §9).

import SwiftUI
import TimeTrackingCore

/// Go to Today, Previous and Next Period, and Date Range…, then each view's
/// display options under its own header, enabled while that view shows.
struct ViewDisplayItems: View {
    var router: SectionRouter
    var state: MenuState
    var scrollToToday: () -> Void

    var body: some View {
        SectionNavigationItems(router: router, state: state)
        Divider()
        Section("Timer") {
            Button("Scroll to Today", action: scrollToToday)
                .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
        }
        Section("Calendar") {
            ForEach([
                CalendarKeyCommand.zoomIn,
                .zoomOut,
                .zoomReset,
                .narrowerDays,
                .widerDays,
                .toggleActivity,
                .toggleCalendar,
            ]) { command in
                CalendarCommandButton(model: router.calendar, command: command, enabled: state.isEnabled(command))
            }
            Button("Filters…") { router.calendar.showsFilters = true }
                .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option]), enabled: state.calendarCommands)
            Button("Clear Filters") { router.calendar.clearFilters() }
                .contextCommand(KeyboardShortcut("f", modifiers: [.command, .option, .shift]), enabled: state.calendarCommands)
        }
        Section("Report") {
            ReportMenuContent(model: router.reports, enabled: state.reportCommands)
        }
        Section("Activity") {
            ActivityMenuContent(model: router.activity, enabled: state.activityCommands)
        }
    }
}
