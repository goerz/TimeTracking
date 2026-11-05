// The shared App Intents (automation.md §5, ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// Starts an entry, stopping the running one.
public struct StartTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Timer"
    public static let description = IntentDescription("Starts an entry with an optional task and project, stopping the running one.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Task", requestValueDialog: "What are you working on?") public var task: String?
    @Parameter(title: "Project") public var project: ProjectEntity?
    /// Set only by the Siri App Shortcut: infer the project from the task.
    @Parameter(title: "Infer Project", default: false) public var inferProject: Bool

    @Dependency private var environment: IntentEnvironment

    public static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$task) on \(\.$project)")
    }

    public init() {}

    /// The App Shortcut's intent, which infers the project.
    public init(inferProject: Bool) {
        self.inferProject = inferProject
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<TimeEntryEntity> & ProvidesDialog {
        if inferProject, task == nil, project == nil {
            throw $task.needsValueError("What are you working on?")
        }
        let service = try await environment.automation()
        let outcome = try await IntentActions.start(task: task, project: project?.projectID, inferProject: inferProject, service: service)
        await environment.didChange()
        return .result(value: outcome.value, dialog: "\(outcome.dialog)")
    }
}
