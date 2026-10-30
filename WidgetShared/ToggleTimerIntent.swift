// ToggleTimerIntent: the wrapper intent of the Control Center timer toggle
// (spec_ios.md §1, §5, §6.1).
// Compiled into the app and the widget extension; it runs in the app
// process, which performs the library operation, sends the change at once,
// and reloads timelines and controls. Hidden from Shortcuts.

import AppIntents
import Foundation
import TimeTrackingCore

/// The Control Center toggle's action: on continues the most recent entry,
/// off stops the running one. Authentication first, so nothing changes on a
/// locked phone (spec_ios.md §5).
struct ToggleTimerIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Timer"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Running") var value: Bool

    @Dependency private var actions: WidgetActionEnvironment

    init() {
        self.value = false
    }

    init(value: Bool) {
        self.value = value
    }

    var action: WidgetAction {
        .toggle(value)
    }

    func perform() async throws -> some IntentResult {
        try await actions.perform(action)
        return .result()
    }
}
