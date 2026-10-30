// The shared App Intents (spec_automation.md §5, spec_ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Continues the most recent entry, or a project's.
public struct ContinueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Continue"
    public static let description = IntentDescription("Starts a new entry with the task and project of the most recent entry.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Project") public var project: ProjectEntity?

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<TimeEntryEntity> & ProvidesDialog {
        let service = try await environment.automation()
        let outcome = try await IntentActions.continue(project: project?.projectID, service: service)
        await environment.didChange()
        return .result(value: outcome.value, dialog: "\(outcome.dialog)")
    }
}
