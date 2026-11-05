// CalendarEventStore: the EventKit seam of the Calendar column; the live
// store wraps EventKit, tests use the in-memory store
// (calendar.md §4).

public import Foundation

/// The app's calendar access.
public enum CalendarAccess: Sendable, Hashable {
    case notDetermined
    case denied
    case fullAccess
}

/// A calendar account (EventKit source).
public struct CalendarSourceInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// The iCloud (CalDAV) account, where time blocks live.
    public var isICloud: Bool

    public init(id: String, title: String, isICloud: Bool) {
        self.id = id
        self.title = title
        self.isICloud = isICloud
    }
}

/// An event calendar.
public struct CalendarInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var sourceID: String
    public var sourceTitle: String
    /// `#RRGGBB`.
    public var color: String
    /// Events can be added (not a subscribed or read-only calendar).
    public var allowsModifications: Bool

    public init(id: String, title: String, sourceID: String, sourceTitle: String, color: String, allowsModifications: Bool = true) {
        self.id = id
        self.title = title
        self.sourceID = sourceID
        self.sourceTitle = sourceTitle
        self.color = color
        self.allowsModifications = allowsModifications
    }

    /// The per-device "Calendars to show" key: (account title, calendar title).
    public var choice: CalendarChoice {
        CalendarChoice(account: sourceTitle, calendar: title)
    }
}

/// A shown calendar, stored per device by account and calendar title (§4.3).
public struct CalendarChoice: Sendable, Hashable, Codable {
    public var account: String
    public var calendar: String

    public init(account: String, calendar: String) {
        self.account = account
        self.calendar = calendar
    }
}

/// One occurrence of an event.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// `<event identifier>|<occurrence start>`: unique per occurrence.
    public var id: String
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var url: URL?
    public var notes: String?
    public var location: String?
    public var attendeeCount: Int

    public init(
        id: String,
        calendarID: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        url: URL? = nil,
        notes: String? = nil,
        location: String? = nil,
        attendeeCount: Int = 0
    ) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.url = url
        self.notes = notes
        self.location = location
        self.attendeeCount = attendeeCount
    }

    public var interval: DateInterval {
        DateInterval(start: start, end: max(start, end))
    }

    /// Whether this all-day event falls on the calendar date `day`. It
    /// belongs to dates, not to shown days, so Midnight plays no part
    /// (calendar.md §1.4).
    public func isAllDay(on day: TrackingDay, in zone: TimeZone) -> Bool {
        let date = TrackingCalendar(timeZone: zone).interval(of: day)
        return isAllDay && start < date.end && max(end, start + 1) > date.start
    }

    /// The fields a write sets.
    public var draft: CalendarEventDraft {
        CalendarEventDraft(calendarID: calendarID, title: title, start: start, end: end, url: url, notes: notes)
    }
}

/// The fields the app writes to an event.
public struct CalendarEventDraft: Sendable, Hashable {
    public var calendarID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var url: URL?
    public var notes: String?

    public init(calendarID: String, title: String, start: Date, end: Date, url: URL? = nil, notes: String? = nil) {
        self.calendarID = calendarID
        self.title = title
        self.start = start
        self.end = end
        self.url = url
        self.notes = notes
    }
}

/// Errors of calendar writes.
public enum CalendarStoreError: Error, Sendable, Hashable, LocalizedError {
    case noAccess
    case unknownEvent
    case unknownCalendar
    case noICloudAccount
    case eventKit(String)

    public var errorDescription: String? {
        switch self {
        case .noAccess: "No calendar access"
        case .unknownEvent: "The event no longer exists"
        case .unknownCalendar: "The calendar no longer exists"
        case .noICloudAccount: "Time blocks need an iCloud calendar account"
        case let .eventKit(message): message
        }
    }
}

/// The calendar operations the Calendar section needs.
public protocol CalendarEventStore: Sendable {
    func access() -> CalendarAccess
    /// Asks for full access (the first time the Calendar column shows).
    func requestAccess() async -> Bool
    func sources() -> [CalendarSourceInfo]
    func calendars() -> [CalendarInfo]
    /// Occurrences overlapping `interval` in the given calendars.
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws(CalendarStoreError) -> [CalendarEvent]
    func create(_ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent
    /// Changes one occurrence (recurring events: that occurrence only).
    func update(_ id: CalendarEvent.ID, _ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent
    func remove(_ id: CalendarEvent.ID) throws(CalendarStoreError)
    func createCalendar(title: String, sourceID: String) throws(CalendarStoreError) -> CalendarInfo
    /// `EKEventStoreChanged`.
    var changes: AsyncStream<Void> { get }
}
