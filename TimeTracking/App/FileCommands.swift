// FileCommands: the File menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// New Project, Client, and Area (in the Projects or Clients & Areas view), then
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
            Button("New Client") {
                show(.clientsAndAreas)
                if let router {
                    Task { await router.projects.clientsAndAreas.newClient() }
                }
            }
            Button("New Area…") {
                if let router {
                    Task { await router.projects.clientsAndAreas.newArea() }
                }
            }
            .contextCommand(
                KeyboardShortcut("n", modifiers: [.command, .option, .shift]),
                enabled: state.clientsAndAreasCommands && router?.projects.clientsAndAreas.selectedClient != nil
            )
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

    /// The window on Projects or Clients & Areas.
    private func show(_ section: PlannerSection) {
        router?.select(section)
        app?.router?.openPlanner()
    }
}
