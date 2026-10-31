// ViewDisplayItems: the View menu's navigation and each view's display
// options, on the Mac and the iPad (experiment: object menus).

import SwiftUI
import TimeTrackingCore

/// Go to Today, Previous and Next Period, and Date Range…, then each view's
/// display options under its own header, enabled while that view shows.
struct ViewDisplayItems: View {
    var router: PlannerRouter
    var state: MenuState
    var scrollToToday: () -> Void

    var body: some View {
        PlannerNavigationItems(router: router, state: state)
        Divider()
        Section("Timer") {
            Button("Scroll to Today", action: scrollToToday)
                .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
        }
        Section("Calendar") {
            ForEach([CalendarKeyCommand.zoomIn, .zoomOut, .zoomReset, .fewerDays, .moreDays, .toggleActivity, .toggleCalendar]) { command in
                CalendarCommandButton(model: router.calendar, command: command, enabled: state.isEnabled(command))
            }
        }
        Section("Report") {
            ReportMenuContent(model: router.reports, enabled: state.reportCommands)
        }
        Section("Activity") {
            ActivityMenuContent(model: router.activity, enabled: state.activityCommands)
        }
    }
}
