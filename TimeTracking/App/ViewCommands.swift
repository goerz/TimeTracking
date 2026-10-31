// ViewCommands: the View menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// The sidebar's items (⌘1 to ⌘5), the sidebar, the shown range's
/// navigation, then each view's display options under its own header,
/// enabled while that view shows.
struct ViewCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(app: app, windowKey: windowActive == true)
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(before: .sidebar) {
            sidebarItems
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Divider()
            if let router {
                PlannerNavigationItems(router: router, state: state)
                Divider()
                Section("Timer") {
                    Button("Scroll to Today") { app?.list.scrollToTop() }
                        .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
                }
                Section("Calendar") {
                    calendarItems(router.calendar)
                }
                Section("Report") {
                    ReportMenuContent(model: router.reports, enabled: state.reportCommands)
                }
                Section("Activity") {
                    ActivityMenuContent(model: router.activity, enabled: state.activityCommands)
                }
            }
        }
    }

    /// Timer ⌘1, Projects ⌘2 to Activity ⌘5, Clients & Areas ⌥⌘2.
    @ViewBuilder private var sidebarItems: some View {
        Button("Timer") { app?.router?.showTimer(focusTask: false) }
            .keyboardShortcut("1")
        ForEach(PlannerSection.allCases) { section in
            Button(section.title) {
                router?.select(section)
                app?.router?.openPlanner()
            }
            .keyboardShortcut(section.mainWindowKey)
        }
        Button("Clients & Areas") {
            router?.showClientsAndAreas()
            app?.router?.openPlanner()
        }
        .keyboardShortcut("2", modifiers: [.command, .option])
    }

    /// Zoom, the number of days, and the two columns.
    private func calendarItems(_ calendar: CalendarModel) -> some View {
        ForEach([CalendarKeyCommand.zoomIn, .zoomOut, .zoomReset, .fewerDays, .moreDays, .toggleActivity, .toggleCalendar]) { command in
            CalendarCommandButton(model: calendar, command: command, enabled: state.isEnabled(command))
        }
    }
}
