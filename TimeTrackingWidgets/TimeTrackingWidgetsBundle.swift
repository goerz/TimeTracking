// TimeTrackingWidgetsBundle: the widget extension's entry point
// (spec_ios.md §3, §4, §5): widgets, controls, the widget push handler, and
// the read-only intent environment the project pickers of configurations use.

import AppIntents
import SwiftUI
import TimeTrackingCore
import WidgetKit

@main
struct TimeTrackingWidgetsBundle: WidgetBundle {
    init() {
        AppDependencyManager.shared.add(dependency: Self.intentEnvironment)
        AppDependencyManager.shared.add(dependency: WidgetActionEnvironment { _ in
            // The wrapper intents run in the app process (allowedExecutionTargets).
            throw AutomationError.failure(WidgetIntentActions.setupMessage)
        })
    }

    /// Project queries in the configuration sheets read the store read-only.
    nonisolated static var intentEnvironment: IntentEnvironment {
        IntentEnvironment(service: {
            guard let store = await WidgetEnvironment().openStore() else {
                throw AutomationError.storeUnavailable(WidgetIntentActions.setupMessage)
            }
            return AutomationService(store: store)
        })
    }

    var body: some Widget {
        NowWidget()
        RecentWidget()
        PinnedWidget()
        TimerToggleControl()
        StartProjectControl()
    }
}

/// The widget extension's App Intents: the library's entities for the configurations.
struct TimeTrackingWidgetsAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TimeTrackingCoreIntents.self]
    }
}
