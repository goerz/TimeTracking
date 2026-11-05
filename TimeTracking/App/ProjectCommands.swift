// ProjectCommands: the Project menu (timer.md §9).

import SwiftUI
import TimeTrackingCore

/// The Project menu, shared with the iPad (`ProjectMenuContent`).
struct ProjectCommands: Commands {
    var host: AppHost
    @FocusedValue(\.mainWindowActive) private var windowActive
    @FocusedValue(\.timerViewActive) private var timerActive

    private var state: MenuState {
        MenuState(app: host.model, mainKey: windowActive == true, timerViewKey: timerActive == true)
    }

    var body: some Commands {
        CommandMenu("Project") {
            if let model = host.model?.sections.projects {
                ProjectMenuContent(model: model, state: state)
            }
        }
    }
}
