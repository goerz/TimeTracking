// Tests of time blocks and calendar access (calendar.md §7).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Time blocks")
struct TimeBlockTests {
    static func date(_ text: String) throws -> Date {
        try TestTime.local(text, in: TestTime.newYork)
    }

    static func project(_ name: String, archived: Bool = false) -> Project {
        Project(
            id: ProjectID(),
            areaID: AreaID(),
            name: name,
            isArchived: archived,
            createdAt: .distantPast,
            modifiedAt: .distantPast
        )
    }

    @Test(
        "PC-15 without a time-block calendar the app creates Time Blocks in iCloud and writes the setting; another device finds it by title"
    )
    func timeBlockCalendar() {
        let first = InMemoryCalendarEventStore()
        let created = TimeBlockCalendar.resolve(store: first, settingID: nil, deviceID: nil)
        guard case let .ready(calendar) = created.state else {
            Issue.record("expected a calendar")
            return
        }
        #expect(calendar.title == "Time Blocks")
        #expect(calendar.sourceID == "icloud")
        #expect(created.settingToWrite == calendar.id)
        // A second device: its identifier lookup fails, the title matches.
        let second = InMemoryCalendarEventStore(calendars: [
            CalendarInfo(id: "local-id", title: "Time Blocks", sourceID: "icloud", sourceTitle: "iCloud", color: "#8E8E93"),
        ])
        let found = TimeBlockCalendar.resolve(store: second, settingID: calendar.id, deviceID: nil)
        #expect(found.state == .ready(second.calendars()[0]))
        #expect(found.settingToWrite == nil)
        #expect(found.resolvedID == "local-id")
        #expect(second.calendars().count == 1)
        let recreated = TimeBlockCalendar.recreate(store: second)
        #expect(recreated.settingToWrite != nil)
        #expect(second.calendars().count == 2)
    }

    @Test("PC-23 the Calendar menu lists the iCloud account's writable calendars; a chosen one is found by title elsewhere")
    func chooseTimeBlockCalendar() {
        let sources = [
            CalendarSourceInfo(id: "icloud", title: "iCloud", isICloud: true),
            CalendarSourceInfo(id: "google", title: "Google", isICloud: false),
        ]
        let blocks = CalendarInfo(id: "tb", title: "Time Blocks", sourceID: "icloud", sourceTitle: "iCloud", color: "#8E8E93")
        let work = CalendarInfo(id: "work-mac", title: "Work", sourceID: "icloud", sourceTitle: "iCloud", color: "#FF0000")
        let holidays = CalendarInfo(
            id: "hol", title: "Holidays", sourceID: "icloud", sourceTitle: "iCloud", color: "#00FF00", allowsModifications: false
        )
        let team = CalendarInfo(id: "team", title: "Team", sourceID: "google", sourceTitle: "Google", color: "#0000FF")
        let mac = InMemoryCalendarEventStore(sources: sources, calendars: [work, holidays, team, blocks])
        #expect(TimeBlockCalendar.choices(store: mac).map(\.title) == ["Time Blocks", "Work"])
        let chosen = TimeBlockCalendar.choose(work)
        #expect(chosen.state == .ready(work))
        #expect(chosen.settingToWrite == "work-mac")
        #expect(chosen.titleToWrite == "Work")
        // The iPad: another identifier for "Work", and its old resolution
        // still points at Time Blocks.
        let padWork = CalendarInfo(id: "work-pad", title: "Work", sourceID: "icloud", sourceTitle: "iCloud", color: "#FF0000")
        let pad = InMemoryCalendarEventStore(sources: sources, calendars: [blocks, padWork])
        let found = TimeBlockCalendar.resolve(store: pad, settingID: "work-mac", settingTitle: "Work", deviceID: "tb")
        #expect(found.state == .ready(padWork))
        #expect(found.settingToWrite == nil)
        #expect(found.resolvedID == "work-pad")
        // "New Calendar…" with "Time Blocks" taken.
        let created = TimeBlockCalendar.recreate(store: mac)
        guard case let .ready(calendar) = created.state else {
            Issue.record("expected a calendar")
            return
        }
        #expect(calendar.title == "Time Blocks 2")
        #expect(created.settingToWrite == calendar.id)
        #expect(created.titleToWrite == "Time Blocks 2")
    }

    @Test("PC-16 a drawn time block is an event with title, project URL, start, and end, no store record; recreated alike")
    func timeBlockEvent() async throws {
        let events = InMemoryCalendarEventStore()
        guard case let .ready(calendar) = TimeBlockCalendar.resolve(store: events, settingID: nil, deviceID: nil).state else {
            Issue.record("expected a calendar")
            return
        }
        let project = Self.project("Noise Model")
        let start = try Self.date("2024-03-14T09:00")
        let draft = TimeBlock.draft(
            calendarID: calendar.id,
            title: "Write noise section",
            project: project.id,
            interval: DateInterval(start: start, duration: 5400),
            notes: nil,
            scheme: "timetracking"
        )
        let event = try events.create(draft)
        #expect(event.url?.absoluteString == "timetracking://project/\(project.id.rawValue)")
        #expect(TimeBlock(event: event, projects: [project]).link == .project(project.id))
        let store = try await TestStore()
        #expect(try await store.store.entries(in: DateInterval(start: start - 86_400, duration: 3 * 86_400), includeDeleted: true).isEmpty)
        try events.remove(event.id)
        let again = try events.create(event.draft)
        #expect(again.draft == event.draft)
        #expect(events.allEvents.count == 1)
    }

    @Test("PC-17 notes Project: noise model link the one active Noise Model; two matches are ambiguous; a URL wins")
    func projectLink() {
        let noise = Self.project("Noise Model")
        let archived = Self.project("Noise Model", archived: true)
        let admin1 = Self.project("Admin")
        let admin2 = Self.project("Admin")
        #expect(TimeBlockLink.resolve(url: nil, notes: "Agenda\nproject: noise model\n", projects: [noise, archived]) == .project(noise.id))
        #expect(TimeBlockLink
            .resolve(url: nil, notes: "Project: Admin", projects: [admin1, admin2]) ==
            .unlinked(reason: "Several projects are named “Admin”"))
        #expect(TimeBlockLink.resolve(url: nil, notes: "Project: Nothing", projects: [noise]) ==
            .unlinked(reason: "No project named “Nothing”"))
        let url = TimeBlockLink.url(for: admin1.id, scheme: "timetracking-debug")
        #expect(TimeBlockLink.resolve(url: url, notes: "Project: Noise Model", projects: [noise, admin1]) == .project(admin1.id))
        #expect(TimeBlockLink.resolve(url: nil, notes: nil, projects: [noise]) == .unlinked(reason: nil))
        #expect(TimeBlockLink.visibleNotes("Agenda\nProject: Noise Model\nRoom 2") == "Agenda\nRoom 2")
    }

    @Test("PC-19 without calendar access the time-block calendar is not resolved; without an iCloud account it says so")
    func accessStates() async {
        let denied: any CalendarEventStore = InMemoryCalendarEventStore(access: .notDetermined, grantOnRequest: false)
        #expect(TimeBlockCalendar.resolve(store: denied, settingID: nil, deviceID: nil).state == .noAccess)
        #expect(await denied.requestAccess() == false)
        #expect(throws: CalendarStoreError.noAccess) { try denied.events(
            in: DateInterval(start: .distantPast, end: .distantFuture),
            calendarIDs: []
        ) }
        let noICloud = InMemoryCalendarEventStore(sources: [CalendarSourceInfo(id: "local", title: "On My Mac", isICloud: false)])
        #expect(TimeBlockCalendar.resolve(store: noICloud, settingID: nil, deviceID: nil).state == .noICloudAccount)
        let granting: any CalendarEventStore = InMemoryCalendarEventStore(access: .notDetermined)
        #expect(await granting.requestAccess())
        #expect(granting.access() == .fullAccess)
    }
}
