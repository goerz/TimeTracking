// InMemoryCalendarEventStore: calendars and events in memory, for tests and
// `-UITesting`; never touches EventKit (spec_planner_calendar.md §4).

public import Foundation
import Synchronization

/// A `CalendarEventStore` over in-memory calendars and events.
public final class InMemoryCalendarEventStore: CalendarEventStore {
    private struct State {
        var access: CalendarAccess
        var grantOnRequest: Bool
        var sources: [CalendarSourceInfo]
        var calendars: [CalendarInfo]
        var events: [CalendarEvent] = []
        var nextID = 1
    }

    private let state: Mutex<State>
    private let broadcaster = Broadcaster<Void>(bufferingPolicy: .bufferingNewest(1))

    /// With an iCloud account by default; `access` starts as given.
    public init(
        access: CalendarAccess = .fullAccess,
        grantOnRequest: Bool = true,
        sources: [CalendarSourceInfo] = [CalendarSourceInfo(id: "icloud", title: "iCloud", isICloud: true)],
        calendars: [CalendarInfo] = []
    ) {
        self.state = Mutex(State(access: access, grantOnRequest: grantOnRequest, sources: sources, calendars: calendars))
    }

    // MARK: Inspection and setup

    /// Every event, by start.
    public var allEvents: [CalendarEvent] {
        state.withLock(\.events).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Adds an event as another app would.
    @discardableResult
    public func add(_ draft: CalendarEventDraft, location: String? = nil, attendees: Int = 0, isAllDay: Bool = false) -> CalendarEvent {
        let event = state.withLock { state in
            var event = Self.event(draft, id: "external-\(state.nextID)|\(draft.start.timeIntervalSince1970)")
            event.location = location
            event.attendeeCount = attendees
            event.isAllDay = isAllDay
            state.nextID += 1
            state.events.append(event)
            return event
        }
        notify()
        return event
    }

    public func addCalendar(_ calendar: CalendarInfo) {
        state.withLock { $0.calendars.append(calendar) }
    }

    private func notify() {
        broadcaster.yield(())
    }

    private static func event(_ draft: CalendarEventDraft, id: String) -> CalendarEvent {
        CalendarEvent(
            id: id,
            calendarID: draft.calendarID,
            title: draft.title,
            start: draft.start,
            end: draft.end,
            url: draft.url,
            notes: draft.notes
        )
    }

    // MARK: CalendarEventStore

    public func access() -> CalendarAccess {
        state.withLock(\.access)
    }

    public func requestAccess() -> Bool {
        let granted = state.withLock { state in
            if state.access == .notDetermined {
                state.access = state.grantOnRequest ? .fullAccess : .denied
            }
            return state.access == .fullAccess
        }
        notify()
        return granted
    }

    public func sources() -> [CalendarSourceInfo] {
        state.withLock(\.sources)
    }

    public func calendars() -> [CalendarInfo] {
        state.withLock(\.calendars)
    }

    public func events(in interval: DateInterval, calendarIDs: Set<String>) throws(CalendarStoreError) -> [CalendarEvent] {
        guard access() == .fullAccess else {
            throw .noAccess
        }
        return allEvents.filter { event in
            calendarIDs.contains(event.calendarID) && event.start < interval.end && event.end > interval.start
        }
    }

    public func create(_ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        let event = try state.withLock { state throws(CalendarStoreError) in
            guard state.access == .fullAccess else {
                throw .noAccess
            }
            guard state.calendars.contains(where: { $0.id == draft.calendarID }) else {
                throw .unknownCalendar
            }
            let event = Self.event(draft, id: "event-\(state.nextID)|\(draft.start.timeIntervalSince1970)")
            state.nextID += 1
            state.events.append(event)
            return event
        }
        notify()
        return event
    }

    public func update(_ id: CalendarEvent.ID, _ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        let event = try state.withLock { state throws(CalendarStoreError) in
            guard let index = state.events.firstIndex(where: { $0.id == id }) else {
                throw .unknownEvent
            }
            var event = state.events[index]
            event.calendarID = draft.calendarID
            event.title = draft.title
            event.start = draft.start
            event.end = draft.end
            event.url = draft.url
            event.notes = draft.notes
            state.events[index] = event
            return event
        }
        notify()
        return event
    }

    public func remove(_ id: CalendarEvent.ID) throws(CalendarStoreError) {
        try state.withLock { state throws(CalendarStoreError) in
            guard let index = state.events.firstIndex(where: { $0.id == id }) else {
                throw .unknownEvent
            }
            state.events.remove(at: index)
        }
        notify()
    }

    public func createCalendar(title: String, sourceID: String) throws(CalendarStoreError) -> CalendarInfo {
        try state.withLock { state throws(CalendarStoreError) in
            guard let source = state.sources.first(where: { $0.id == sourceID }) else {
                throw .noICloudAccount
            }
            let calendar = CalendarInfo(
                id: "calendar-\(state.nextID)",
                title: title,
                sourceID: source.id,
                sourceTitle: source.title,
                color: "#8E8E93"
            )
            state.nextID += 1
            state.calendars.append(calendar)
            return calendar
        }
    }

    public var changes: AsyncStream<Void> {
        broadcaster.stream()
    }
}
