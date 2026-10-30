// TimeTrackingAppIntents: the Mac app's App Intents, the library's
// package (spec_automation.md §5).

import AppIntents
import TimeTrackingCore

/// Exposes the library's intents, entities, and App Shortcuts.
struct TimeTrackingAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TimeTrackingCoreIntents.self]
    }
}
