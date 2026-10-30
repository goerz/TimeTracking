// The shared App Intents (spec_automation.md §5, spec_ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// The running entry.
public struct CurrentEntryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Running Entry"
    public static let description = IntentDescription("Returns the running entry, if any.")
    public static let supportedModes: IntentModes = .background

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<TimeEntryEntity?> & ProvidesDialog {
        let outcome = try await IntentActions.current(service: environment.automation())
        return .result(value: outcome.value, dialog: "\(outcome.dialog)")
    }
}
