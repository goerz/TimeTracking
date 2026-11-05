// FileCommands: the File menu (timer.md §9).

import SwiftUI
import TimeTrackingCore

/// New Project, Area, and Client (in the Projects view), then
/// Reports' Export…; there is no Print….
struct FileCommands: Commands {
    var host: AppHost
    @FocusedValue(\.mainWindowActive) private var windowActive
    @FocusedValue(\.timerViewActive) private var timerActive

    private var app: AppModel? {
        host.model
    }

    private var router: SectionRouter? {
        host.model?.sections
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
        CommandGroup(replacing: .printItem) {}
    }

    /// The window on Projects.
    private func show(_ section: MainSection) {
        app?.router?.showMainWindow(item: .section(section))
    }
}
