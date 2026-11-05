// WidgetStopIntent: the wrapper intent of the widgets' Stop buttons
// (ios.md §1, §6.1).
// Compiled into the app and the widget extension; it runs in the app
// process, which performs the library operation, sends the change at once,
// and reloads timelines and controls. Hidden from Shortcuts.

import AppIntents
import Foundation
import TimeTrackingCore

/// Stops the running entry the widget showed.
struct WidgetStopIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Entry"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Entry") var entryID: String?

    @Dependency private var actions: WidgetActionEnvironment

    init() {}

    init(entry: EntryID?) {
        self.entryID = entry?.rawValue
    }

    var action: WidgetAction {
        .stop(expected: entryID.flatMap { EntryID($0) })
    }

    func perform() async throws -> some IntentResult {
        try await actions.perform(action)
        return .result()
    }
}
