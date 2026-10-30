// The wrapper intents of the widget and control buttons (spec_ios.md §1,
// §5, §6.1). Compiled into the app and the widget extension; they run in the
// app process, which performs the library operation, sends the change at
// once, and reloads timelines and controls. Hidden from Shortcuts.

import AppIntents
import Foundation
import TimeTrackingCore

/// The widget kinds and control kinds.
nonisolated enum WidgetKind {
    static let now = "now"
    static let recent = "recent"
    static let pinned = "pinned"
    static let timerToggle = "timerToggle"
    static let startProject = "startProject"
}

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

/// Stops the running entry the widget showed.
struct WidgetStopIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Entry"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Entry") var entryID: String?

    @Dependency private var actions: WidgetActionEnvironment

    init() {}

    init(entry: EntryID?) {
        self.entryID = entry?.rawValue
    }

    var action: WidgetAction {
        .stop(expected: entryID.flatMap { EntryID($0) })
    }

    func perform() async throws -> some IntentResult {
        try await actions.perform(action)
        return .result()
    }
}

/// Continues an entry, or the most recent one.
struct WidgetContinueIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Continue Entry"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Entry") var entryID: String?

    @Dependency private var actions: WidgetActionEnvironment

    init() {}

    init(entry: EntryID?) {
        self.entryID = entry?.rawValue
    }

    var action: WidgetAction {
        .continueEntry(entryID.flatMap { EntryID($0) })
    }

    func perform() async throws -> some IntentResult {
        try await actions.perform(action)
        return .result()
    }
}

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
