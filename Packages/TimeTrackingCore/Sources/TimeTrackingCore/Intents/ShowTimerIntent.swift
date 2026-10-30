// The shared App Intents (spec_automation.md §5, spec_ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Opens the Timer window or tab.
public struct ShowTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Timer"
    public static let description = IntentDescription("Opens the Timer.")
    public static let supportedModes: IntentModes = .foreground

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func perform() async -> some IntentResult {
        await environment.showTimer()
        return .result()
    }
}
