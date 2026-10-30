// The shared App Intents (spec_automation.md §5, spec_ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Entries whose start lies in a half-open range of days.
public struct EntriesIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Entries"
    public static let description = IntentDescription("Returns the entries starting from the first date up to, not including, the second.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "From") public var from: Date
    @Parameter(title: "To") public var to: Date
    @Parameter(title: "Project") public var project: ProjectEntity?
    @Parameter(title: "Client") public var client: ClientEntity?

    @Dependency private var environment: IntentEnvironment

    public static var parameterSummary: some ParameterSummary {
        Summary("Entries from \(\.$from) to \(\.$to)") {
            \.$project
            \.$client
        }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<[TimeEntryEntity]> {
        let outcome = try await IntentActions.entries(
            from: from,
            to: to,
            project: project?.projectID,
            client: client?.clientID,
            service: environment.automation()
        )
        return .result(value: outcome.value)
    }
}
