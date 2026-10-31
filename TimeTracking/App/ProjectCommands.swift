// ProjectCommands: the Project menu (experiment: one window, object menus).

import SwiftUI
import TimeTrackingCore

/// The Project menu, shared with the iPad (`ProjectMenuContent`).
struct ProjectCommands: Commands {
    var host: AppHost
    @FocusedValue(\.plannerWindowActive) private var windowActive
    @FocusedValue(\.timerWindowActive) private var timerActive

    private var state: MenuState {
        MenuState(app: host.model, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        CommandMenu("Project") {
            if let model = host.model?.planner.projects {
                ProjectMenuContent(model: model, state: state)
            }
        }
    }
}
