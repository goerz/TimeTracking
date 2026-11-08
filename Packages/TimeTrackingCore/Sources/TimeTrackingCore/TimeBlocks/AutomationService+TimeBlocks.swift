// AutomationService+TimeBlocks: the tool's time-block commands, which find
// the time-block calendar and link projects as the app does
// (automation.md §3.14; calendar.md §4.1, §4.2).

public import Foundation

extension DeviceSettingKey where Value == String {
    /// The resolved time-block calendar identifier (device state, calendar.md §4.1).
    public static var calendarTimeBlockCalendar: Self {
        Self("planner.calendar.timeBlockCalendar", default: "")
    }
}

/// The calendar side of the time-block commands.
public struct TimeBlockContext: Sendable {
    public var events: any CalendarEventStore
    /// The identifier this device resolved before (`calendarTimeBlockCalendar`).
    public var deviceCalendarID: String?
    /// The URL scheme of the project links (`timetracking`, Debug `timetracking-debug`).
    public var scheme: String

    public init(events: any CalendarEventStore, deviceCalendarID: String?, scheme: String) {
        self.events = events
        self.deviceCalendarID = deviceCalendarID
        self.scheme = scheme
    }
}

/// The fields `block edit` changes; `nil` keeps a field.
public struct TimeBlockChange: Sendable, Hashable {
    public var title: String?
    public var start: Date?
    public var end: Date?
    /// `.some(nil)` removes the project link.
    public var projectID: ProjectID??
    /// `.some(nil)` removes the notes.
    public var notes: String??

    public init(title: String? = nil, start: Date? = nil, end: Date? = nil, projectID: ProjectID?? = nil, notes: String?? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.projectID = projectID
        self.notes = notes
    }
}

extension AutomationService {
    /// The time-block calendar, found as the app finds it but never
    /// created; asks for calendar access when it was never asked.
    public func timeBlockCalendar(_ context: TimeBlockContext) async throws(AutomationError) -> CalendarInfo {
        let events = context.events
        if events.access() == .notDetermined {
            _ = await events.requestAccess()
        }
        guard events.access() == .fullAccess else {
            throw .storeUnavailable(
                "No access to calendars; allow it in System Settings > Privacy & Security > Calendars for the app that runs timetracking."
            )
        }
        let store = store
        let (setting, title) = try await run { try await (store.value(.timeBlockCalendarID), store.value(.timeBlockCalendarTitle)) }
        let resolution = TimeBlockCalendar.resolve(
            store: events,
            settingID: setting,
            settingTitle: title,
            deviceID: context.deviceCalendarID,
            creating: false
        )
        if case let .ready(calendar) = resolution.state {
            return calendar
        }
        guard events.sources().contains(where: \.isICloud) else {
            throw .storeUnavailable("Time blocks need an iCloud calendar account.")
        }
        throw .storeUnavailable("No time-block calendar yet; open the Calendar section of the app once to create it.")
    }

    /// The time blocks whose start lies in `range`, by start.
    public func timeBlocks(in range: DayRange, context: TimeBlockContext) async throws(AutomationError) -> TimeBlockListing {
        let calendar = try await timeBlockCalendar(context)
        let interval = range.interval(in: self.calendar)
        let found = try Self.calendarCall { try context.events.events(in: interval, calendarIDs: [calendar.id]) }
            .filter { $0.start >= interval.start && $0.start < interval.end }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let projects = try await projectRows()
        return TimeBlockListing(
            range: range,
            calendar: calendar,
            records: found.map { TimeBlockRecord(event: $0, projects: projects) },
            timeZone: timeZone
        )
    }

    /// The time block with the id `id` (as `block list` prints it).
    public func timeBlock(_ id: String, context: TimeBlockContext) async throws(AutomationError) -> TimeBlockRecord {
        let calendar = try await timeBlockCalendar(context)
        return try await TimeBlockRecord(event: event(id, in: calendar, context: context), projects: projectRows())
    }

    /// A new time block linked to `projectID` by its URL.
    public func createTimeBlock( // swiftlint:disable:this function_parameter_count
        title: String,
        start: Date,
        end: Date,
        projectID: ProjectID?,
        notes: String?,
        context: TimeBlockContext
    ) async throws(AutomationError) -> TimeBlockRecord {
        guard end > start else {
            throw .refused("The end must be after the start.")
        }
        let calendar = try await timeBlockCalendar(context)
        let draft = TimeBlock.draft(
            calendarID: calendar.id,
            title: title,
            project: projectID,
            interval: DateInterval(start: start, end: end),
            notes: notes,
            scheme: context.scheme
        )
        let created = try Self.calendarCall { try context.events.create(draft) }
        return try await TimeBlockRecord(event: created, projects: projectRows())
    }

    /// Changes the given fields of one time block; the URL is the only link written.
    public func editTimeBlock(
        _ id: String,
        _ change: TimeBlockChange,
        context: TimeBlockContext
    ) async throws(AutomationError) -> TimeBlockRecord {
        let calendar = try await timeBlockCalendar(context)
        let event = try event(id, in: calendar, context: context)
        var draft = event.draft
        draft.title = change.title ?? draft.title
        draft.start = change.start ?? draft.start
        draft.end = change.end ?? draft.end
        if let projectID = change.projectID {
            draft.url = projectID.flatMap { TimeBlockLink.url(for: $0, scheme: context.scheme) }
        }
        if let notes = change.notes {
            draft.notes = notes
        }
        guard draft.end > draft.start else {
            throw .refused("The end must be after the start.")
        }
        let updated = try Self.calendarCall { try context.events.update(event.id, draft) }
        return try await TimeBlockRecord(event: updated, projects: projectRows())
    }

    /// Deletes one time block and returns it as it was.
    public func deleteTimeBlock(_ id: String, context: TimeBlockContext) async throws(AutomationError) -> TimeBlockRecord {
        let record = try await timeBlock(id, context: context)
        try Self.calendarCall { try context.events.remove(record.block.id) }
        return record
    }

    // MARK: Helpers

    /// The event `id` (`<identifier>|<occurrence start>`) of `calendar`.
    private func event(_ id: String, in calendar: CalendarInfo, context: TimeBlockContext) throws(AutomationError) -> CalendarEvent {
        let parts = id.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let seconds = Double(parts[1]) else {
            throw .usage("Malformed time block id \"\(id)\"; use an id that block list prints.")
        }
        let start = Date(timeIntervalSince1970: seconds)
        let window = DateInterval(start: start - 86_400, end: start + 86_400)
        let found = try Self.calendarCall { try context.events.events(in: window, calendarIDs: [calendar.id]) }
        guard let event = found.first(where: { $0.id == id }) else {
            throw .notFound("No time block with id \(id).")
        }
        return event
    }

    private func projectRows() async throws(AutomationError) -> [ProjectRow] {
        let store = store
        return try await run { try await store.projects(filter: ProjectFilter(state: .all)) }
    }

    /// Runs a calendar operation, its `CalendarStoreError` as the tool's error.
    private static func calendarCall<R>(_ body: () throws -> R) throws(AutomationError) -> R {
        do {
            return try body()
        } catch CalendarStoreError.noAccess {
            throw .storeUnavailable("No access to calendars.")
        } catch CalendarStoreError.unknownEvent {
            throw .notFound("The time block no longer exists.")
        } catch {
            throw .failure(error.localizedDescription)
        }
    }
}

/// A time block with its link resolved as the Calendar resolves it.
public struct TimeBlockRecord: Sendable, Hashable {
    public var block: TimeBlock
    /// The linked project with its area and client; `nil` when unlinked.
    public var project: ProjectRow?

    init(event: CalendarEvent, projects: [ProjectRow]) {
        let block = TimeBlock(event: event, projects: projects.map(\.project))
        self.block = block
        self.project = block.link.projectID.flatMap { id in projects.first { $0.project.id == id } }
    }

    /// Why the block is unlinked, as its tooltip says; `nil` when linked or
    /// when it names no project at all.
    public var unlinkedReason: String? {
        if case let .unlinked(reason) = block.link {
            return reason
        }
        return nil
    }

    /// `{"id", "title", "start", "end", "duration", "notes", "url", "project",
    /// "area", "client", "unlinkedReason"}`.
    public func json(timeZone: TimeZone) -> JSONValue {
        let event = block.event
        return .object([
            "id": .string(event.id),
            "title": .string(event.title),
            "start": .string(ReportCSVWriter.timestamp(event.start, in: timeZone)),
            "end": .string(ReportCSVWriter.timestamp(event.end, in: timeZone)),
            "duration": .int(Int(event.interval.duration.rounded())),
            "notes": .optional(event.notes?.isEmpty == false ? event.notes : nil),
            "url": .optional(event.url?.absoluteString),
            "project": project.map { .object(["id": .string($0.project.id.rawValue), "name": .string($0.project.name)]) } ?? .null,
            "area": project?.area.map(AutomationRecords.areaReference) ?? .null,
            "client": project?.client.map(AutomationRecords.clientReference) ?? .null,
            "unlinkedReason": .optional(unlinkedReason),
        ])
    }
}

/// The time blocks `block list` prints.
public struct TimeBlockListing: Sendable, Hashable {
    public var range: DayRange
    public var calendar: CalendarInfo
    public var records: [TimeBlockRecord]
    public var timeZone: TimeZone

    /// `{"from", "to", "calendar": {"id", "title"}, "blocks": [time block records]}`.
    public var json: JSONValue {
        .object([
            "from": .string(range.fromText(in: timeZone)),
            "to": .string(range.toText(in: timeZone)),
            "calendar": .object(["id": .string(calendar.id), "title": .string(calendar.title)]),
            "blocks": .array(records.map { $0.json(timeZone: timeZone) }),
        ])
    }
}
