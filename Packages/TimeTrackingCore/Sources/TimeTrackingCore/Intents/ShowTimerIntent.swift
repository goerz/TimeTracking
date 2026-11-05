// The shared App Intents (automation.md §5, ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Shows the Timer: the Mini Timer on the Mac, the Timer tab on iOS.
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
