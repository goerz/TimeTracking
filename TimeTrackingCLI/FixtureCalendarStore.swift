// FixtureCalendarStore: calendars and events in a JSON file, which
// `TIMETRACKING_CALENDAR` names in Debug builds, so the tool tests run the
// time-block commands without EventKit (automation.md §3.14, §9).

import Foundation
import Synchronization
import TimeTrackingCore

/// A `CalendarEventStore` over a JSON file, written back after every change.
final nonisolated class FixtureCalendarStore: CalendarEventStore {
    /// The file's content.
    struct Content: Codable {
        var access: String
        var sources: [Source]
        var calendars: [Calendar]
        var events: [Event]
        var nextID: Int
    }

    struct Source: Codable {
        var id: String
        var title: String
        var isICloud: Bool
    }

    struct Calendar: Codable {
        var id: String
        var title: String
        var sourceID: String
    }

    struct Event: Codable {
        var id: String
        var calendarID: String
        var title: String
        var start: Date
        var end: Date
        var url: String?
        var notes: String?
    }

    private let url: URL
    private let content: Mutex<Content>

    init(url: URL) throws {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.content = try Mutex(decoder.decode(Content.self, from: Data(contentsOf: url)))
    }

    private func save(_ content: Content) throws(CalendarStoreError) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(content).write(to: url)
        } catch {
            throw .eventKit(error.localizedDescription)
        }
    }

    private func change<R>(_ body: (inout Content) throws(CalendarStoreError) -> R) throws(CalendarStoreError) -> R {
        try content.withLock { content throws(CalendarStoreError) in
            guard content.access == "fullAccess" else {
                throw .noAccess
            }
            let result = try body(&content)
            try save(content)
            return result
        }
    }

    private static func event(_ event: Event) -> CalendarEvent {
        CalendarEvent(
            id: event.id,
            calendarID: event.calendarID,
            title: event.title,
            start: event.start,
            end: event.end,
            url: event.url.flatMap(URL.init(string:)),
            notes: event.notes
        )
    }

    private static func stored(_ draft: CalendarEventDraft, id: String) -> Event {
        Event(
            id: id,
            calendarID: draft.calendarID,
            title: draft.title,
            start: draft.start,
            end: draft.end,
            url: draft.url?.absoluteString,
            notes: draft.notes
        )
    }

    // MARK: CalendarEventStore

    func access() -> CalendarAccess {
        switch content.withLock(\.access) {
        case "fullAccess": .fullAccess
        case "notDetermined": .notDetermined
        default: .denied
        }
    }

    func requestAccess() -> Bool {
        access() == .fullAccess
    }

    func sources() -> [CalendarSourceInfo] {
        content.withLock(\.sources).map { CalendarSourceInfo(id: $0.id, title: $0.title, isICloud: $0.isICloud) }
    }

    func calendars() -> [CalendarInfo] {
        content.withLock { content in
            content.calendars.map { calendar in
                let source = content.sources.first { $0.id == calendar.sourceID }
                return CalendarInfo(
                    id: calendar.id,
                    title: calendar.title,
                    sourceID: calendar.sourceID,
                    sourceTitle: source?.title ?? "",
                    color: "#8E8E93"
                )
            }
        }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws(CalendarStoreError) -> [CalendarEvent] {
        guard access() == .fullAccess else {
            throw .noAccess
        }
        return content.withLock(\.events)
            .filter { calendarIDs.contains($0.calendarID) && $0.start < interval.end && $0.end > interval.start }
            .map(Self.event)
    }

    func create(_ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        try change { content throws(CalendarStoreError) in
            guard content.calendars.contains(where: { $0.id == draft.calendarID }) else {
                throw .unknownCalendar
            }
            let event = Self.stored(draft, id: "event-\(content.nextID)|\(draft.start.timeIntervalSince1970)")
            content.nextID += 1
            content.events.append(event)
            return Self.event(event)
        }
    }

    func update(_ id: CalendarEvent.ID, _ draft: CalendarEventDraft) throws(CalendarStoreError) -> CalendarEvent {
        try change { content throws(CalendarStoreError) in
            guard let index = content.events.firstIndex(where: { $0.id == id }) else {
                throw .unknownEvent
            }
            // The id follows the occurrence start, as EventKit's does.
            let identifier = id.split(separator: "|").first.map(String.init) ?? id
            content.events[index] = Self.stored(draft, id: "\(identifier)|\(draft.start.timeIntervalSince1970)")
            return Self.event(content.events[index])
        }
    }

    func remove(_ id: CalendarEvent.ID) throws(CalendarStoreError) {
        try change { content throws(CalendarStoreError) in
            guard let index = content.events.firstIndex(where: { $0.id == id }) else {
                throw .unknownEvent
            }
            content.events.remove(at: index)
        }
    }

    func createCalendar(title _: String, sourceID _: String) throws(CalendarStoreError) -> CalendarInfo {
        throw .eventKit("The tool never creates calendars.")
    }

    var changes: AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
