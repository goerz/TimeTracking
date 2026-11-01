// Tests of time blocks, calendar access, and Fill Day (spec_calendar.md §8).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Time blocks and Fill Day")
struct TimeBlockAndFillDayTests {
    static let zone = SuggestionWorld.zone

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
        "PC-17 without a time-block calendar the app creates Time Blocks in iCloud and writes the setting; another device finds it by title"
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

    @Test("PC-18 a drawn time block is an event with title, project URL, start, and end, no store record; recreated alike")
    func timeBlockEvent() async throws {
        let events = InMemoryCalendarEventStore()
        guard case let .ready(calendar) = TimeBlockCalendar.resolve(store: events, settingID: nil, deviceID: nil).state else {
            Issue.record("expected a calendar")
            return
        }
        let project = Self.project("Noise Model")
        let start = SuggestionWorld.date("2024-03-14T09:00")
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

    @Test("PC-19 notes Project: noise model link the one active Noise Model; two matches are ambiguous; a URL wins")
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

    @Test("PC-21 without calendar access the time-block calendar is not resolved; without an iCloud account it says so")
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

    // MARK: Fill Day

    static func block(
        _ start: String,
        minutes: Int,
        context: String = "tmux:paper",
        subject: String = "~/Papers/2026_Noise"
    ) -> ActivityBlock {
        let begin = SuggestionWorld.date(start)
        return ActivityBlock(
            start: begin,
            end: begin + Double(minutes * 60),
            activeSeconds: minutes * 54,
            device: "macbook",
            groupKey: context,
            groupShare: 1,
            items: [ActivityItem(context: context, subject: subject, detail: "", seconds: minutes * 54)],
            utcOffset: zone.secondsFromGMT(for: begin)
        )
    }

    static func context(_ world: SuggestionWorld, rules: [SuggestionRule] = [], feedback: [SuggestionFeedback] = []) -> FillDay.Context {
        FillDay.Context(
            index: world.index(),
            rules: rules,
            titles: world.titles,
            feedback: feedback,
            fillMinMinutes: 5,
            now: SuggestionWorld.date("2024-03-18T20:00"),
            timeZone: zone
        )
    }

    static let day = TrackingCalendar(timeZone: zone).interval(of: SuggestionWorld.heldOutDay)

    @Test("PC-16 untracked segments of 12, 3, and 40 minutes give two rows; logging is one transaction with skipped feedback")
    func fillDay() async throws {
        let world = try await SuggestionWorld.load()
        let blocks = [
            Self.block("2024-03-18T09:00", minutes: 12),
            Self.block("2024-03-18T10:00", minutes: 3, context: "mail", subject: "Inbox"),
            Self.block("2024-03-18T14:00", minutes: 50, context: "tmux:acme", subject: "~/Code/acme-sequencer"),
        ]
        let tracked = [DateInterval(start: SuggestionWorld.date("2024-03-18T14:00"), duration: 600)]
        let rows = FillDay.proposals(day: Self.day, blocks: blocks, entries: tracked, context: Self.context(world))
        #expect(rows.map { $0.interval.duration / 60 } == [12, 40])
        #expect(rows.filter(\.startsChecked).count == 2)
        #expect(rows[0].top?.projectID == SuggestionWorld.id(SuggestionWorld.noise))
        let test = try await TestStore(now: "2024-03-18T20:00", zone: Self.zone.identifier)
        let project = try await test.structure(projects: ["Noise Model"]).projects[0]
        let created = try await test.store.logFillDay(
            checked: [FillDayChoice(proposal: rows[0], projectID: project.id, task: rows[0].top?.task ?? "")],
            skipped: [rows[1]]
        )
        #expect(created.count == 1)
        let feedback = try await test.store.feedback(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(Set(feedback.map(\.outcome)) == [.edited, .skipped])
        #expect(feedback.allSatisfy { $0.source == .fill })
        #expect(feedback.first { $0.outcome == .edited }?.entryID == created[0].id)
    }

    @Test("PC-22 an ignore rule removes a block from Fill Day; a skipped proposal is not proposed again that day")
    func ignoreAndSkip() async throws {
        let world = try await SuggestionWorld.load()
        let blocks = [
            Self.block("2024-03-18T09:00", minutes: 30),
            Self.block("2024-03-18T11:00", minutes: 30, context: "mail", subject: "Inbox"),
        ]
        let ignore = SuggestionRule(kind: .groupKey, pattern: "mail", ignore: true)
        let rows = FillDay.proposals(day: Self.day, blocks: blocks, entries: [], context: Self.context(world, rules: [ignore]))
        #expect(rows.count == 1)
        #expect(rows[0].blocks[0].groupKey == "tmux:paper")
        let skipped = SuggestionFeedback.skipped(
            query: rows[0].query,
            source: .fill,
            block: rows[0].blocks[0],
            top: rows[0].top,
            now: SuggestionWorld.date("2024-03-18T19:00")
        )
        let again = FillDay.proposals(
            day: Self.day,
            blocks: blocks,
            entries: [],
            context: Self.context(world, rules: [ignore], feedback: [skipped])
        )
        #expect(again.isEmpty)
    }

    @Test("PC-22 feedback is written for each outcome and source")
    func feedbackOutcomes() async throws {
        let world = try await SuggestionWorld.load()
        let block = Self.block("2024-03-18T09:00", minutes: 30)
        let query = SuggestionQuery(blocks: [block], interval: DateInterval(start: block.start, end: block.end), timeZone: Self.zone)
        let top = world.index().suggest(query).first
        let now = SuggestionWorld.date("2024-03-18T20:00")
        let accepted = SuggestionFeedback.decision(
            query: query,
            source: .block,
            block: block,
            top: top,
            chosenProject: top?.projectID,
            chosenTask: "  draft  PAPER ",
            entryID: nil,
            now: now
        )
        #expect(accepted.outcome == .accepted)
        let edited = SuggestionFeedback.decision(
            query: query,
            source: .event,
            block: nil,
            top: top,
            chosenProject: nil,
            chosenTask: "Other",
            entryID: nil,
            now: now
        )
        #expect(edited.outcome == .edited)
        #expect(edited.chosenTask == "Other")
        let skipped = SuggestionFeedback.skipped(query: query, source: .fill, block: block, top: top, now: now)
        let test = try await TestStore(now: "2024-03-18T20:00", zone: Self.zone.identifier)
        for record in [accepted, edited, skipped] {
            try await test.store.recordSuggestionFeedback(record)
        }
        let stored = try await test.store.feedback(in: DateInterval(start: now - 86_400, end: now + 1))
        #expect(Set(stored.map(\.source)) == [.block, .event, .fill])
        let report = SuggestionFeedbackReport(stored)
        #expect(report.accepted == 1)
        #expect(abs(report.acceptanceRate - 1.0 / 3) < 0.001)
    }
}
