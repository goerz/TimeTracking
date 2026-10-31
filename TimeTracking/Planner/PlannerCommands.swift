// PlannerCommands: the section menu and the File menu's Export and Print
// (spec_timer_window.md §9; spec_planner_projects.md §2.5, §4;
// spec_planner_reports.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// The Planner's own menus: one menu named for the Planner's section
/// (Project, Calendar, Report, Activity), always in the menu bar with that
/// section's commands, enabled while the Planner is key; and Reports'
/// Export… and Print… in File.
struct PlannerCommands: Commands {
    var host: AppHost
    @FocusedValue(\.timerWindowActive) private var timerActive
    @FocusedValue(\.plannerWindowActive) private var plannerActive

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(router: router, timerKey: timerActive ?? false, plannerKey: plannerActive ?? false)
    }

    var body: some Commands {
        CommandMenu(state.sectionMenuTitle) {
            if let router {
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
}
