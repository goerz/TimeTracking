// The shared App Intents (automation.md §5, ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Creates an active project in an area.
public struct CreateProjectIntent: AppIntent {
    public static let title: LocalizedStringResource = "Create Project"
    public static let description = IntentDescription("Creates an active project in an area.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Name") public var name: String
    @Parameter(title: "Area") public var area: AreaEntity

    @Dependency private var environment: IntentEnvironment

    public static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$name) in \(\.$area)")
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<ProjectEntity> & ProvidesDialog {
        let outcome = try await IntentActions.createProject(name: name, area: area.areaID, service: environment.automation())
        await environment.didChange()
        return .result(value: outcome.value, dialog: "\(outcome.dialog)")
    }
}
