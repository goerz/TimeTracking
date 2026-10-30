// TimeTrackingiOSApp: the iPhone and iPad app's entry point (spec_ios.md).

import SwiftUI
import TimeTrackingCore

@main
struct TimeTrackingiOSApp: App {
    var body: some Scene {
        WindowGroup {
            Text(AppIdentity.main?.appID ?? "TimeTracking")
                .padding()
                .accessibilityIdentifier("timer.placeholder")
        }
    }
}
