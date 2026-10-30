// TimeTrackingURL: the `timetracking://` URL scheme, parsed (spec_automation.md §6).
// URLs start, stop, continue, and show; nothing destructive.

public import Foundation

/// One URL of the scheme.
public enum TimeTrackingURL: Hashable, Sendable {
    /// How a `start` URL names its project.
    public enum ProjectReference: Hashable, Sendable {
        case name(String)
        case id(ProjectID)
    }

    case start(project: ProjectReference?, task: String)
    case stop
    case `continue`
    case show
    case calendar(date: TrackingDay?)
    case reports(from: TrackingDay?, to: TrackingDay?)
    case projects
    case activity(date: TrackingDay?)
    case project(ProjectID)

    /// The longest query value accepted.
    public static let maximumValueLength = 1000

    /// Parses `url` for `scheme` (`timetracking` or `timetracking-debug`).
    public init(_ url: URL, scheme: String) throws(TimeTrackingURLError) { // swiftlint:disable:this cyclomatic_complexity
        guard url.scheme?.lowercased() == scheme.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            throw .unknown
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let value = item.value ?? ""
            guard value.count <= Self.maximumValueLength else {
                throw .tooLong
            }
            query[item.name] = value
        }
        let host = (components.host ?? "").lowercased()
        let path = components.path.split(separator: "/").map(String.init)
        switch (host, path) {
        case ("start", []):
            if let text = query["project_id"] {
                guard let id = ProjectID(text.lowercased()) else {
                    throw .badValue("project_id")
                }
                self = .start(project: .id(id), task: query["task"] ?? "")
            } else {
                let name = query["project"].flatMap { $0.trimmed.isEmpty ? nil : $0 }
                self = .start(project: name.map(ProjectReference.name), task: query["task"] ?? "")
            }
        case ("stop", []):
            self = .stop
        case ("continue", []):
            self = .continue
        case ("show", []):
            self = .show
        case ("planner", ["calendar"]):
            self = try .calendar(date: Self.day(query, "date"))
        case ("planner", ["reports"]):
            self = try .reports(from: Self.day(query, "from"), to: Self.day(query, "to"))
        case ("planner", ["projects"]):
            self = .projects
        case ("planner", ["activity"]):
            self = try .activity(date: Self.day(query, "date"))
        case let ("project", segments) where segments.count == 1:
            guard let id = ProjectID(segments[0].lowercased()) else {
                throw .badValue("project")
            }
            self = .project(id)
        default:
            throw .unknown
        }
    }

    /// Whether the URL changes tracking (start, stop, continue) rather
    /// than showing something.
    public var tracks: Bool {
        switch self {
        case .start, .stop, .continue: true
        default: false
        }
    }

    private static func day(_ query: [String: String], _ key: String) throws(TimeTrackingURLError) -> TrackingDay? {
        guard let text = query[key] else {
            return nil
        }
        guard let day = TrackingDay(text) else {
            throw .badValue(key)
        }
        return day
    }
}

/// Why a URL was not acted on; the message is the alert's text.
public enum TimeTrackingURLError: Error, Equatable, Sendable, LocalizedError {
    case unknown
    case tooLong
    case badValue(String)

    public var errorDescription: String? {
        switch self {
        case .unknown: "Unknown TimeTracking URL"
        case .tooLong: "A value of the TimeTracking URL is longer than 1,000 characters."
        case let .badValue(key): "The TimeTracking URL has a malformed \(key)."
        }
    }
}

extension AutomationService {
    /// Performs a tracking URL (start, stop, continue) and returns the
    /// banner text, `Started Noise paper`. A project name that is unknown,
    /// archived, or ambiguous starts nothing and throws the problem; URLs
    /// never create projects.
    public func perform(_ url: TimeTrackingURL) async throws(AutomationError) -> String? {
        switch url {
        case let .start(reference, task):
            var projectID: ProjectID?
            switch reference {
            case let .name(name):
                projectID = try await store.resolveProject(name).project.id
            case let .id(id):
                projectID = try await store.resolveProject(id: id.rawValue).project.id
            case nil:
                break
            }
            let result = try await start(task: task, projectID: projectID)
            return "Started \(result.entry.project?.name ?? IntentText.subject(result.entry))"
        case .stop:
            let stopped = try await stop()
            return "Stopped \(IntentText.subject(stopped))"
        case .continue:
            let result = try await self.continue(.latest)
            return IntentText.started(result.entry)
        default:
            return nil
        }
    }
}
