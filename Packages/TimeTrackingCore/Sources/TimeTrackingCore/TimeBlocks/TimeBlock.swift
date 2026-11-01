// TimeBlock: a time block (an event of the time-block calendar), its
// project link, and the calendar's resolution (spec_calendar.md §4.1, §4.2).

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
            return .unlinked(reason: url.flatMap { projectID(in: $0) } == nil ? nil : "The linked project no longer exists")
        }
        let matches = projects.filter { !$0.isDeleted && !$0.isArchived && $0.name.folded == name.folded }
        switch matches.count {
        case 1: return .project(matches[0].id)
        case 0: return .unlinked(reason: "No project named “\(name)”")
        default: return .unlinked(reason: "Several projects are named “\(name)”")
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

/// Resolves the time-block calendar (§4.1): the calendar of the iCloud
/// account the user chose, "Time Blocks" by default.
public enum TimeBlockCalendar {
    public static let title = "Time Blocks"

    /// What `resolve` found and what to store.
    public struct Resolution: Sendable, Hashable {
        public var state: TimeBlockCalendarState
        /// The synced `calendar.timeBlockCalendarID` to write, when chosen
        /// or created.
        public var settingToWrite: String?
        /// The synced `calendar.timeBlockCalendarTitle` to write with it.
        public var titleToWrite: String?
        /// The device state to keep (the resolved identifier).
        public var resolvedID: String?
    }

    /// By the setting's identifier, else by the synced title (`Time
    /// Blocks` when unset) in the iCloud source, else by the device's
    /// resolved identifier; only when all fail it creates "Time Blocks"
    /// there and asks to write the settings.
    public static func resolve(
        store: any CalendarEventStore,
        settingID: String?,
        settingTitle: String? = nil,
        deviceID: String?
    ) -> Resolution {
        guard store.access() == .fullAccess else {
            return Resolution(state: .noAccess)
        }
        let calendars = store.calendars()
        if let settingID, let calendar = calendars.first(where: { $0.id == settingID }) {
            return Resolution(state: .ready(calendar), resolvedID: calendar.id)
        }
        let source = store.sources().first(where: \.isICloud)
        let wanted = settingTitle ?? title
        if let source, let calendar = calendars.first(where: { $0.sourceID == source.id && $0.title == wanted }) {
            return Resolution(state: .ready(calendar), resolvedID: calendar.id)
        }
        if let deviceID, let calendar = calendars.first(where: { $0.id == deviceID }) {
            return Resolution(state: .ready(calendar), resolvedID: calendar.id)
        }
        guard let source else {
            return Resolution(state: .noICloudAccount)
        }
        return create(store: store, source: source)
    }

    /// The calendars the time-block calendar can be: the writable calendars
    /// of the iCloud account, by title.
    public static func choices(store: any CalendarEventStore) -> [CalendarInfo] {
        guard store.access() == .fullAccess, let source = store.sources().first(where: \.isICloud) else {
            return []
        }
        return store.calendars()
            .filter { $0.sourceID == source.id && $0.allowsModifications }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Makes `calendar` the time-block calendar.
    public static func choose(_ calendar: CalendarInfo) -> Resolution {
        Resolution(state: .ready(calendar), settingToWrite: calendar.id, titleToWrite: calendar.title, resolvedID: calendar.id)
    }

    /// "New Calendar…": a new calendar in the iCloud account, "Time
    /// Blocks", numbered when that title is taken there.
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
        let taken = Set(store.calendars().filter { $0.sourceID == source.id }.map(\.title))
        let name = ([title] + (2 ... 99).map { "\(title) \($0)" }).first { !taken.contains($0) } ?? title
        guard let calendar = try? store.createCalendar(title: name, sourceID: source.id) else {
            return Resolution(state: .noICloudAccount)
        }
        return choose(calendar)
    }
}

extension TimeBlockCalendar.Resolution {
    init(state: TimeBlockCalendarState, resolvedID: String? = nil) {
        self.init(state: state, settingToWrite: nil, titleToWrite: nil, resolvedID: resolvedID)
    }
}
