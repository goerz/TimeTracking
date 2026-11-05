// The configuration of the Pinned widget and of the project control
// (ios.md §3.4, §5). Parameters only; the providers read them.

import AppIntents
import TimeTrackingCore

/// The Pinned widget's task mode.
enum PinnedTaskChoice: String, AppEnum {
    case settings
    case latest
    case blank

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .settings: "As in Settings",
        .latest: "The Project's Last Task",
        .blank: "No Task",
    ]

    /// The mode, with "As in Settings" resolved to `setting`.
    func mode(setting: PinnedTaskMode) -> PinnedTaskMode {
        switch self {
        case .settings: setting
        case .latest: .latest
        case .blank: .blank
        }
    }
}

/// "Use pinned list" (default) or an explicit ordered list of 1 to 12
/// projects, and the task mode.
struct PinnedProjectsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pinned Projects"
    static let description = IntentDescription("Buttons that start your pinned projects.")
    static let isDiscoverable = false

    @Parameter(title: "Use Pinned List", default: true) var usePinnedList: Bool
    @Parameter(title: "Projects", size: 12) var projects: [ProjectEntity]? // swiftlint:disable:this discouraged_optional_collection
    @Parameter(title: "Task", default: .settings) var task: PinnedTaskChoice

    init() {}

    init(projects: [ProjectEntity]?, task: PinnedTaskChoice = .settings) { // swiftlint:disable:this discouraged_optional_collection
        self.usePinnedList = projects == nil
        self.projects = projects
        self.task = task
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$usePinnedList, .equalTo, true) {
            Summary("Use the pinned list") {
                \.$usePinnedList
                \.$task
            }
        } otherwise: {
            Summary("Show \(\.$projects)") {
                \.$usePinnedList
                \.$task
            }
        }
    }

    /// The explicit list, or `nil` for the synced `pinnedProjectIDs`.
    var projectIDs: [ProjectID]? { // swiftlint:disable:this discouraged_optional_collection
        guard !usePinnedList, let projects, !projects.isEmpty else {
            return nil
        }
        return Array(projects.prefix(12).map(\.projectID))
    }
}

/// The project a "Start Project" control starts.
struct StartProjectConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Start Project"
    static let isDiscoverable = false

    @Parameter(title: "Project") var project: ProjectEntity?

    init() {}
}
