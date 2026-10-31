// PlannerCommands: the section menu and the File menu's Export and Print
// (spec_timer_window.md §9; spec_planner_projects.md §2.5, §4;
// spec_planner_reports.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// The main window's own menus: one menu named for the sidebar item shown
/// (Entry for the Timer; Project, Calendar, Report, Activity), and Reports'
/// Export… and Print… in File. The menu always lists that item's commands;
/// they are enabled while the window is key.
struct PlannerCommands: Commands {
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
        MenuState(router: router, timerKey: timerActive ?? false, plannerKey: plannerActive == true && timerActive != true)
    }

    private var showsTimer: Bool {
        app?.showsTimer ?? true
    }

    var body: some Commands {
        CommandMenu(showsTimer ? "Entry" : state.sectionMenuTitle) {
            if showsTimer {
                timerEntryItems
            } else if let router {
                SectionMenuContent(router: router, state: state)
            }
        }
        CommandGroup(after: .importExport) {
            Button("Export…") { router?.reports.requestExport() }
                .contextCommand(KeyboardShortcut("e", modifiers: [.command, .shift]), enabled: state.reportCommands)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let reports = router?.reports {
                    ReportPrinter.print(reports)
                }
            }
            .contextCommand(KeyboardShortcut("p"), enabled: state.reportCommands)
        }
    }

    /// Set Project…, Edit Entry…, and Delete Entry…: the running entry or
    /// the Timer list's selected row.
    @ViewBuilder private var timerEntryItems: some View {
        Button("Set Project…") { app?.openChipPicker() }
            .contextCommand(KeyboardShortcut("p"), enabled: state.timerKey)
        Button("Edit Entry…") { app?.editEntry() }
            .contextCommand(KeyboardShortcut("e"), enabled: state.timerKey)
        Button("Delete Entry…") {
            if let app {
                app.timer.alert = app.list.deleteAlert()
            }
        }
        .contextCommand(
            KeyboardShortcut(.delete, modifiers: .command),
            enabled: state.timerKey && app?.list.selection != nil && app?.presentation.listFocused == true
        )
    }
}
