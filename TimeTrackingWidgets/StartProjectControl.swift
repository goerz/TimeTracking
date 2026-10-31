// StartProjectControl: the control that starts a chosen project, for example
// on the Action button (spec_ios.md §5).

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

struct StartProjectControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WidgetKind.startProject, intent: StartProjectConfiguration.self) { configuration in
            ControlWidgetButton(action: WidgetStartIntent(project: configuration.project?.projectID, task: "")) {
                Label(configuration.project?.name ?? "Start Project", systemImage: SymbolName.start)
            }
        }
        .displayName("Start Project")
        .description("Starts the project you choose.")
        .promptsForUserConfiguration()
    }
}
