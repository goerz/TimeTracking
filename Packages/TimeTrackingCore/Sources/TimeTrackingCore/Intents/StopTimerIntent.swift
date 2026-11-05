// The shared App Intents (automation.md §5, ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Stops the running entry; nothing running is not an error.
public struct StopTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Timer"
    public static let description = IntentDescription("Stops the running entry.")
    public static let supportedModes: IntentModes = .background

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<TimeEntryEntity?> & ProvidesDialog {
        let service = try await environment.automation()
        let outcome = try await IntentActions.stop(service: service)
        if outcome.value != nil {
            await environment.didChange()
        }
        return .result(value: outcome.value, dialog: "\(outcome.dialog)")
    }
}
