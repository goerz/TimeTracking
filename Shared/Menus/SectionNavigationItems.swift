// SectionNavigationItems: the View menu's commands for the shown range, on
// the Mac and the iPad (projects.md §1.2).

import SwiftUI
import TimeTrackingCore

/// Go to Today, Previous Period, Next Period, and Date Range… (Go to Date…
/// in the Calendar): one item each for the sections with a date range,
/// acting on the section shown.
struct SectionNavigationItems: View {
    var router: SectionRouter
    var state: MenuState

    var body: some View {
        Button("Go to Today") { Task { await router.goToToday() } }
            .contextCommand(KeyboardShortcut("t"), enabled: state.periodCommands)
        Button("Previous Period") { Task { await router.shiftPeriod(by: -1) } }
            .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .option]), enabled: canShiftPeriod)
        Button("Next Period") { Task { await router.shiftPeriod(by: 1) } }
            .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .option]), enabled: canShiftPeriod)
        Button(router.dateRangeTitle) { router.showDateRange() }
            .contextCommand(KeyboardShortcut("d", modifiers: [.command, .shift]), enabled: state.periodCommands)
    }

    private var canShiftPeriod: Bool {
        state.periodCommands && router.canShiftPeriod
    }
}
