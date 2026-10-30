// TimeTrackingApp: the Mac app's entry point and scenes
// (spec_timer_window.md, spec_menubar.md, spec_planner_projects.md).

import SwiftUI
import TimeTrackingCore

@main
struct TimeTrackingApp: App {
    var body: some Scene {
        Window("Timer", id: "timer") {
            Text(AppIdentity.main?.appID ?? "TimeTracking")
                .padding()
                .accessibilityIdentifier("timer.placeholder")
        }
    }
}
