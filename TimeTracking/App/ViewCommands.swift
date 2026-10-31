// ViewCommands: the main menu's View menu (spec_timer_window.md §9;
// spec_planner_projects.md §1.2; spec_planner_calendar.md §6;
// spec_planner_reports.md §8; spec_planner_activity.md §2).

import SwiftUI
import TimeTrackingCore

/// The Planner's sections and their navigation, then the Timer window's
/// view options. A command shared by sections (Go to Today, Previous and
/// Next Period) is one item acting on the section shown.
struct ViewCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(host: host, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        SidebarCommands()
        CommandGroup(before: .sidebar) {
            sectionItems
            Divider()
            navigationItems
            Divider()
            if let router {
                CalendarViewMenu(model: router.calendar, state: state)
                ReportMenu(model: router.reports, enabled: state.reportCommands)
                ActivityMenu(model: router.activity, enabled: state.activityCommands)
            }
            Divider()
            timerItems
            Divider()
        }
    }

    /// ⌘1 to ⌘4 and Clients & Areas, while the Planner is key.
    @ViewBuilder private var sectionItems: some View {
        ForEach(PlannerSection.allCases) { section in
            Button(section.title) { router?.select(section) }
                .contextCommand(KeyboardShortcut(KeyEquivalent(section.key)), enabled: state.sectionCommands)
        }
        Button("Clients & Areas") { router?.showClientsAndAreas() }
            .contextCommand(KeyboardShortcut("1", modifiers: [.command, .option]), enabled: state.sectionCommands)
    }

    /// Go to Today (Calendar, Reports, Activity); Previous Period, Next
    /// Period, and Date Range… (Reports, Activity).
    @ViewBuilder private var navigationItems: some View {
        Button("Go to Today") { goToToday() }
            .contextCommand(KeyboardShortcut("t"), enabled: state.todayCommand)
        Button("Previous Period") { shiftPeriod(by: -1) }
            .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .option]), enabled: canShiftPeriod)
        Button("Next Period") { shiftPeriod(by: 1) }
            .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .option]), enabled: canShiftPeriod)
        Button("Date Range…") { showDateRange() }
            .contextCommand(KeyboardShortcut("d", modifiers: [.command, .shift]), enabled: state.periodCommands)
    }

    /// Compact Mode, Float on Top, and Scroll to Today, while the Timer
    /// window is key.
    @ViewBuilder private var timerItems: some View {
        Toggle("Compact Mode", isOn: Binding(
            get: { app?.window?.isCompact ?? false },
            set: { _ in app?.toggleCompact() }
        ))
        .contextCommand(KeyboardShortcut("m", modifiers: [.command, .shift]), enabled: state.timerKey)
        Toggle("Float on Top", isOn: Binding(
            get: { app?.settings.timerPinned ?? false },
            set: { app?.setPinned($0) }
        ))
        .disabled(!state.timerKey)
        Button("Scroll to Today") { app?.list.scrollToTop() }
            .contextCommand(KeyboardShortcut(.upArrow), enabled: state.timerKey)
    }

    private var canShiftPeriod: Bool {
        guard let router else {
            return false
        }
        if state.reportCommands {
            return router.reports.range.canShift
        }
        return state.activityCommands && router.activity.range.canShift
    }

    private func goToToday() {
        guard let router else {
            return
        }
        if state.calendarCommands {
            Task { await router.calendar.perform(.today) }
        } else if state.reportCommands {
            Task { await router.reports.goToToday() }
        } else if state.activityCommands {
            router.activity.range.goToToday()
            Task { await router.activity.reload() }
        }
    }

    private func showDateRange() {
        if state.reportCommands {
            router?.reports.showsDatePopover = true
        } else if state.activityCommands {
            router?.activity.showsDatePopover = true
        }
    }

    private func shiftPeriod(by step: Int) {
        guard let router else {
            return
        }
        if state.reportCommands {
            Task { await step < 0 ? router.reports.previousPeriod() : router.reports.nextPeriod() }
        } else if state.activityCommands {
            Task { await router.activity.shiftPeriod(by: step) }
        }
    }
}

/// View › Report (spec_planner_reports.md §8); its range commands are
/// View › Go to Today, Previous Period, Next Period, and Date Range….
private struct ReportMenu: View {
    var model: ReportsModel
    var enabled: Bool

    var body: some View {
        Menu("Report") {
            PlannerMenuItems.reportBack(model, enabled: enabled)
            Divider()
            PlannerMenuItems.reportFilters(model, enabled: enabled)
            Divider()
            PlannerMenuItems.reportCards(model, enabled: enabled)
            Divider()
            Menu("Show Totals By") {
                Button("Automatic") { Task { await model.setGranularity(nil) } }
                ForEach([Granularity.day, .week, .month, .year], id: \.self) { granularity in
                    Button(granularity.title) { Task { await model.setGranularity(granularity) } }
                }
            }
            .disabled(!enabled)
            Menu("Stack By") {
                ForEach(StackKind.allCases, id: \.self) { kind in
                    Button(kind.title) { Task { await model.setStack(kind) } }
                }
            }
            .disabled(!enabled)
            Divider()
            Button("Expand All") { model.expandAll() }
                .contextCommand(KeyboardShortcut(.rightArrow, modifiers: [.command, .shift]), enabled: enabled)
            Button("Collapse All") { model.collapseAll() }
                .contextCommand(KeyboardShortcut(.leftArrow, modifiers: [.command, .shift]), enabled: enabled)
        }
    }
}
