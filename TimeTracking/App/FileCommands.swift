// FileCommands: the File menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// New Project, Area, and Client (in the Projects view), then
/// Reports' Export… and Print….
struct FileCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive
    @FocusedValue(\.timerWindowActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var router: PlannerRouter? {
        host.model?.planner
    }

    private var state: MenuState {
        MenuState(app: app, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                show(.projects)
                router?.projects.newProject()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            // The Client popup starts on the selected row's client.
            Button("New Area…") {
                show(.projects)
                if let projects = router?.projects {
                    Task { await projects.clientsAndAreas.newArea(in: projects.clientForNewArea) }
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            Button("New Client…") {
                show(.projects)
                if let router {
                    Task { await router.projects.clientsAndAreas.newClient() }
                }
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

    /// The window on Projects.
    private func show(_ section: PlannerSection) {
        router?.select(section)
        app?.router?.openPlanner()
    }
}
