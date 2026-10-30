// EventKitCalendarStore: the live CalendarEventStore over EventKit (Mac and
// iPad; the iPhone never creates one) (spec_planner_calendar.md §4).

import CoreGraphics
import EventKit
public import Foundation
import Synchronization

/// Calendar access through one `EKEventStore`. Tests never create one.
public final class EventKitCalendarStore: CalendarEventStore {
    /// EKEventStore is documented as usable from any thread; the mutex keeps
    /// the strict-concurrency checker honest about it.
    private let store: Mutex<EKEventStore>

    public init() {
        self.store = Mutex(EKEventStore())
    }

    public func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .fullAccess
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        let store = store.withLock { $0 }
        return await (try? store.requestFullAccessToEvents()) ?? false
    }

    public func sources() -> [CalendarSourceInfo] {
        store.withLock { store in
            store.sources.map { source in
                CalendarSourceInfo(id: source.sourceIdentifier, title: source.title, isICloud: Self.isICloud(source))
            }
        }
    }

    public func calendars() -> [CalendarInfo] {
        store.withLock { store in
            store.calendars(for: .event).map(Self.info)
        }
    }

    public func events(in interval: DateInterval, calendarIDs: Set<String>) throws(CalendarStoreError) -> [CalendarEvent] {
        guard access() == .fullAccess else {
            throw .noAccess
        }
        return store.withLock { store in
            let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            guard !calendars.isEmpty else {
                return []
            }
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
            return store.events(matching: predicate).map(Self.event)
        }
    }

    public func create(_ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        try store.withLock { store throws(CalendarStoreError) in
            guard let calendar = store.calendar(withIdentifier: draft.calendarID) else {
                throw .unknownCalendar
            }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            Self.apply(draft, to: event)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw .eventKit(error.localizedDescription)
            }
            return Self.event(event)
        }
    }

    public func update(_ id: CalendarEvent.ID, _ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        try store.withLock { store throws(CalendarStoreError) in
            let event = try Self.occurrence(id, in: store)
            if let calendar = store.calendar(withIdentifier: draft.calendarID) {
                event.calendar = calendar
            }
            Self.apply(draft, to: event)
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw .eventKit(error.localizedDescription)
            }
            return Self.event(event)
        }
    }

    public func remove(_ id: CalendarEvent.ID) throws(CalendarStoreError) {
        try store.withLock { store throws(CalendarStoreError) in
            let event = try Self.occurrence(id, in: store)
            do {
                try store.remove(event, span: .thisEvent, commit: true)
            } catch {
                throw .eventKit(error.localizedDescription)
            }
        }
    }

    public func createCalendar(title: String, sourceID: String) throws(CalendarStoreError) -> CalendarInfo {
        try store.withLock { store throws(CalendarStoreError) in
            guard let source = store.sources.first(where: { $0.sourceIdentifier == sourceID }) else {
                throw .noICloudAccount
            }
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = title
            calendar.source = source
            calendar.cgColor = CGColor(gray: 0.56, alpha: 1)
            do {
                try store.saveCalendar(calendar, commit: true)
            } catch {
                throw .eventKit(error.localizedDescription)
            }
            return Self.info(calendar)
        }
    }

    public var changes: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged).map({ _ in () }) {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    private static func isICloud(_ source: EKSource) -> Bool {
        source.sourceType == .calDAV && source.title.localizedCaseInsensitiveContains("iCloud")
    }

    private static func info(_ calendar: EKCalendar) -> CalendarInfo {
        CalendarInfo(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceID: calendar.source?.sourceIdentifier ?? "",
            sourceTitle: calendar.source?.title ?? "",
            color: hex(calendar.cgColor)
        )
    }

    private static func event(_ event: EKEvent) -> CalendarEvent {
        let start = event.occurrenceDate ?? event.startDate ?? Date(timeIntervalSince1970: 0)
        return CalendarEvent(
            id: "\(event.eventIdentifier ?? "")|\(start.timeIntervalSince1970)",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            start: event.startDate ?? start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            url: event.url,
            notes: event.notes,
            location: event.location,
            attendeeCount: event.attendees?.count ?? 0
        )
    }

    private static func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.url = draft.url
        event.notes = draft.notes
    }

    /// The occurrence named by `id` (`<identifier>|<occurrence start>`).
    private static func occurrence(_ id: CalendarEvent.ID, in store: EKEventStore) throws(CalendarStoreError) -> EKEvent {
        let parts = id.split(separator: "|", maxSplits: 1)
        guard let identifier = parts.first, let seconds = parts.last.flatMap({ Double($0) }) else {
            throw .unknownEvent
        }
        let start = Date(timeIntervalSince1970: seconds)
        let predicate = store.predicateForEvents(withStart: start - 1, end: start + 86_400, calendars: nil)
        if let match = store.events(matching: predicate)
            .first(where: { $0.eventIdentifier == String(identifier) && $0.occurrenceDate == start })
        {
            return match
        }
        guard let event = store.event(withIdentifier: String(identifier)) else {
            throw .unknownEvent
        }
        return event
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let color, let srgb = color.converted(
                  to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  intent: .defaultIntent,
                  options: nil
              ),
              let components = srgb.components, components.count >= 3
        else {
            return "#8E8E93"
        }
        let bytes = components.prefix(3).map { min(255, max(0, Int(($0 * 255).rounded()))) }
        return "#" + bytes.map { String(format: "%02X", $0) }.joined()
    }
}
