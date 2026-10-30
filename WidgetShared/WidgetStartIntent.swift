// WidgetStartIntent: the wrapper intent of the Pinned buttons, the Recent
// rows, and the project control (spec_ios.md §1, §5, §6.1).
// Compiled into the app and the widget extension; it runs in the app
// process, which performs the library operation, sends the change at once,
// and reloads timelines and controls. Hidden from Shortcuts.

import AppIntents
import Foundation
import TimeTrackingCore

/// Starts a project and task (Pinned buttons, Recent rows, the project control).
struct WidgetStartIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Entry"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Project") var projectID: String?
    @Parameter(title: "Task") var task: String

    @Dependency private var actions: WidgetActionEnvironment

    init() {
        self.task = ""
    }

    init(project: ProjectID?, task: String) {
        self.projectID = project?.rawValue
        self.task = task
    }

    var action: WidgetAction {
        .start(project: projectID.flatMap { ProjectID($0) }, task: task)
    }

    func perform() async throws -> some IntentResult {
        try await actions.perform(action)
        return .result()
    }
}
