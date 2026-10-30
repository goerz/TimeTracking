// TimeBlock: a time block (an event of the time-block calendar), its
// project link, and the calendar's resolution (spec_planner_calendar.md §4.1, §4.2).

public import Foundation

/// How a time block links a project.
public enum TimeBlockLink: Sendable, Hashable {
    case project(ProjectID)
    /// Not linked; the reason shows in the tooltip.
    case unlinked(reason: String?)

    public var projectID: ProjectID? {
        if case let .project(id) = self {
            return id
        }
        return nil
    }

    /// A URL naming an existing project wins; else the first notes line
    /// `Project: <name>` links the single active project of that name
    /// (case and diacritics ignored); else unlinked.
    public static func resolve(url: URL?, notes: String?, projects: [Project]) -> Self {
        if let id = projectID(in: url), projects.contains(where: { $0.id == id && !$0.isDeleted }) {
            return .project(id)
        }
        guard let name = projectName(inNotes: notes) else {
            return .unlinked(reason: url.flatMap { projectID(in: $0) } == nil ? nil : "Unknown project")
        }
        let matches = projects.filter { !$0.isDeleted && !$0.isArchived && $0.name.folded == name.folded }
        switch matches.count {
        case 1: return .project(matches[0].id)
        case 0: return .unlinked(reason: "Unknown project")
        default: return .unlinked(reason: "Project name '\(name)' is ambiguous")
        }
    }

    /// The project id of `<scheme>://project/<uuid>`.
    public static func projectID(in url: URL?) -> ProjectID? {
        guard let url, url.host() == "project", let uuid = UUID(uuidString: url.lastPathComponent) else {
            return nil
        }
        return ProjectID(uuid)
    }

    /// `timetracking://project/<uuid>` with the app's scheme.
    public static func url(for project: ProjectID, scheme: String) -> URL? {
        URL(string: "\(scheme)://project/\(project.rawValue)")
    }

    /// The name of the first `Project:` notes line.
    public static func projectName(inNotes notes: String?) -> String? {
        for line in (notes ?? "").split(separator: "\n", omittingEmptySubsequences: true) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let colon = text.firstIndex(of: ":"), String(text[..<colon]).trimmed.lowercased() == "project" else {
                continue
            }
            let name = String(text[text.index(after: colon)...]).trimmed
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// The notes without `Project:` lines (the app hides them, never rewrites them).
    public static func visibleNotes(_ notes: String?) -> String {
        (notes ?? "").split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                guard let colon = line.firstIndex(of: ":") else {
                    return true
                }
                return String(line[..<colon]).trimmed.lowercased() != "project"
            }
            .joined(separator: "\n")
            .trimmed
    }
}

/// A time block as the Calendar column shows it.
public struct TimeBlock: Sendable, Hashable, Identifiable {
    public var event: CalendarEvent
    public var link: TimeBlockLink

    public init(event: CalendarEvent, projects: [Project]) {
        self.event = event
        self.link = TimeBlockLink.resolve(url: event.url, notes: event.notes, projects: projects)
    }

    public var id: CalendarEvent.ID {
        event.id
    }

    public var title: String {
        event.title
    }

    /// The event fields of a new or edited block: the URL is the only link
    /// the app writes; notes are kept as they are.
    public static func draft( // swiftlint:disable:this function_parameter_count
        calendarID: String,
        title: String,
        project: ProjectID?,
        interval: DateInterval,
        notes: String?,
        scheme: String
    ) -> CalendarEventDraft {
        CalendarEventDraft(
            calendarID: calendarID,
            title: title,
            start: interval.start,
            end: interval.end,
            url: project.flatMap { TimeBlockLink.url(for: $0, scheme: scheme) },
            notes: notes
        )
    }
}

/// The time-block calendar's state on this device.
public enum TimeBlockCalendarState: Sendable, Hashable {
    case ready(CalendarInfo)
    /// "Time blocks need an iCloud calendar account".
    case noICloudAccount
    /// The column's notice with "Open System Settings".
    case noAccess
}

/// Resolves the calendar titled "Time Blocks" (§4.1).
public enum TimeBlockCalendar {
    public static let title = "Time Blocks"

    /// What `resolve` found and what to store.
    public struct Resolution: Sendable, Hashable {
        public var state: TimeBlockCalendarState
        /// The synced `calendar.timeBlockCalendarID` to write, when created.
        public var settingToWrite: String?
        /// The device state to keep (the resolved identifier).
        public var resolvedID: String?
    }

    /// By the setting's identifier, else the device's resolved one, else
    /// by title in the iCloud source; only when all fail it creates the
    /// calendar there and asks to write the setting.
    public static func resolve(store: any CalendarEventStore, settingID: String?, deviceID: String?) -> Resolution {
        guard store.access() == .fullAccess else {
            return Resolution(state: .noAccess)
        }
        let calendars = store.calendars()
        for id in [settingID, deviceID].compactMap(\.self) {
            if let calendar = calendars.first(where: { $0.id == id }) {
                return Resolution(state: .ready(calendar), resolvedID: calendar.id)
            }
        }
        guard let source = store.sources().first(where: \.isICloud) else {
            return Resolution(state: .noICloudAccount)
        }
        if let calendar = calendars.first(where: { $0.sourceID == source.id && $0.title == title }) {
            return Resolution(state: .ready(calendar), resolvedID: calendar.id)
        }
        return create(store: store, source: source)
    }

    /// "Recreate": a new calendar in the iCloud account.
    public static func recreate(store: any CalendarEventStore) -> Resolution {
        guard store.access() == .fullAccess else {
            return Resolution(state: .noAccess)
        }
        guard let source = store.sources().first(where: \.isICloud) else {
            return Resolution(state: .noICloudAccount)
        }
        return create(store: store, source: source)
    }

    private static func create(store: any CalendarEventStore, source: CalendarSourceInfo) -> Resolution {
        guard let calendar = try? store.createCalendar(title: title, sourceID: source.id) else {
            return Resolution(state: .noICloudAccount)
        }
        return Resolution(state: .ready(calendar), settingToWrite: calendar.id, resolvedID: calendar.id)
    }
}

extension TimeBlockCalendar.Resolution {
    init(state: TimeBlockCalendarState, resolvedID: String? = nil) {
        self.init(state: state, settingToWrite: nil, resolvedID: resolvedID)
    }
}
