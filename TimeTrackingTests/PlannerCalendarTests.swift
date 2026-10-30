// The Calendar section's view model: Today, scrolling, deleting, splitting,
// Add Entry, Delete This Activity, Fill Day, time blocks, calendar access, the
// router request, and the key commands (spec_planner_calendar.md §8).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct PlannerCalendarTests {
    /// A Planner over the test store with an in-memory activity log and calendar store.
    @MainActor
    struct World {
        let test: TestApp
        let router: PlannerRouter
        let model: CalendarModel
        let activity: InMemoryActivityStore
        let events: InMemoryCalendarEventStore
        let commands = RecordingTrackerCommands()

        init(blocks: [ActivityBlock] = [], events: InMemoryCalendarEventStore = InMemoryCalendarEventStore()) async throws {
            let test = try await TestApp()
            self.test = test
            self.activity = InMemoryActivityStore(blocks: blocks)
            self.events = events
            self.router = PlannerRouter(
                store: test.store,
                clock: test.clock,
                device: test.app.settings.device,
                activity: activity,
                events: events
            )
            self.model = router.calendar
            model.undoManager = test.undo
            let commands = commands
            model.sendTrackerCommand = { command in
                switch commands.send(command) {
                case .accepted: nil
                case let .rejected(reason): reason
                }
            }
            await model.reload()
        }
    }

    static func day(_ text: String) -> TrackingDay {
        TrackingDay(text) ?? TrackingDay(year: 2000, month: 1, day: 1)
    }

    /// A block today (2024-03-14) from `start` to `end`, local time.
    static func block(_ start: String, _ end: String, context: String = "tmux:paper", open: Bool = false) throws -> ActivityBlock {
        let begin = try TestApp.date("2024-03-14T\(start)")
        let finish = try TestApp.date("2024-03-14T\(end)")
        let seconds = Int(finish.timeIntervalSince(begin) * 0.9)
        return ActivityBlock(
            start: begin,
            end: finish,
            activeSeconds: seconds,
            device: "macbook",
            groupKey: context,
            groupShare: 1,
            items: [ActivityItem(context: context, subject: "~/Papers", detail: "", seconds: seconds)],
            utcOffset: TimeZone.current.secondsFromGMT(for: begin),
            isOpen: open
        )
    }

    @Test("PC-2 with today Thursday, ⌘T makes the first day Tuesday for 5 days, Monday for 7, Thursday for 1 and 2")
    func today() async throws {
        let world = try await World()
        let model = world.model
        for (count, first) in [(5, "2024-03-12"), (7, "2024-03-11"), (1, "2024-03-14"), (2, "2024-03-14")] {
            await model.setVisibleDays(count)
            await model.shift(days: 20)
            await model.perform(.today)
            #expect(model.firstDay == Self.day(first))
        }
        // Changing the day count keeps the leftmost day.
        await model.setVisibleDays(3)
        #expect(model.firstDay == Self.day("2024-03-14"))
    }

    @Test("PC-3 a sideways scroll of 1.4 day widths snaps one day over; the calendar URL makes its date the first day")
    func scrollAndURL() async throws {
        let world = try await World()
        let model = world.model
        let first = model.firstDay
        await model.scrolled(dayWidths: 1.4)
        #expect(model.firstDay == first.adding(days: 1))
        let router = URLRouter(app: world.test.app, scheme: "timetracking-debug")
        _ = try await router.open(#require(URL(string: "timetracking-debug://planner/calendar?date=2026-10-29")))
        let planner = world.test.app.planner
        #expect(planner.section == .calendar)
        await planner.consumeCalendarRequest()
        #expect(planner.calendar.firstDay == Self.day("2026-10-29"))
    }

    @Test("PC-7 a press below the now-line draws nothing and says entries can't be in the future")
    func futureNotice() async throws {
        let world = try await World()
        let model = world.model
        try model.draw(on: Self.day("2024-03-14"), from: TestApp.date("2024-03-14T11:00"), to: TestApp.date("2024-03-14T12:00"))
        #expect(model.draft == nil)
        #expect(model.notice?.text == "Entries can't be in the future")
        try model.draw(on: Self.day("2024-03-14"), from: TestApp.date("2024-03-14T09:02"), to: TestApp.date("2024-03-14T09:58"))
        #expect(try model.draft?.interval == DateInterval(start: TestApp.date("2024-03-14T09:00"), end: TestApp.date("2024-03-14T10:00")))
        model.escape()
        #expect(model.draft == nil)
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).isEmpty)
    }

    @Test("PC-10 Delete then ⌘Z restores the entry with the same id and fields; the running entry asks first and comes back stopped")
    func deleteAndUndo() async throws {
        let world = try await World()
        let model = world.model
        let entry = try await world.test.entry("Clarify noise model", from: "08:00", to: "09:33")
        await model.reload()
        model.select(.entry(entry.id))
        await model.perform(.delete)
        #expect(model.notice?.text == "Deleted 'Clarify noise model' (1h 33m).")
        #expect(try await world.test.store.entry(entry.id) == nil)
        world.test.undo.undo()
        await model.waitForUndo()
        let restored = try #require(try await world.test.store.entry(entry.id))
        #expect(restored.task == entry.task)
        #expect(restored.start == entry.start)
        #expect(restored.end == entry.end)
        // The running entry.
        let running = try await world.test.store.start(projectID: nil, task: "Running", at: TestApp.date("2024-03-14T09:40"))
        await model.reload()
        model.select(.entry(running.id))
        await model.deleteSelection()
        #expect(model.confirmsRunningDelete)
        #expect(try await world.test.store.entry(running.id) != nil)
        await model.deleteSelection(confirmed: true)
        world.test.clock.advance(by: 300)
        world.test.undo.undo()
        await model.waitForUndo()
        let back = try #require(try await world.test.store.entry(running.id))
        #expect(try back.end == TestApp.date("2024-03-14T10:00"))
    }

    @Test("PC-11 Split Here at 10:00 on 09:00 to 11:00 gives two abutting entries, at 10:59:30 it is refused; Duplicate needs a past copy")
    func splitAndDuplicate() async throws {
        let world = try await World()
        let model = world.model
        await model.shift(days: -1)
        let entry = try await world.test.entry("Paper", from: "2024-03-13T09:00", to: "2024-03-13T11:00")
        await model.reload()
        try await model.split(entry.id, at: TestApp.date("2024-03-13T10:59:30"))
        #expect(try await world.test.store.entries(on: Self.day("2024-03-13")).count == 1)
        try await model.split(entry.id, at: TestApp.date("2024-03-13T10:00"))
        let pieces = try await world.test.store.entries(on: Self.day("2024-03-13")).sorted { $0.start < $1.start }
        #expect(pieces.count == 2)
        #expect(pieces[0].end == pieces[1].start)
        #expect(try pieces[0].end == TestApp.date("2024-03-13T10:00"))
        // Duplicate to Next Day: 09:00–10:00 would end at 10:00 today (now), 10:00–11:00 would not be past.
        model.select(.entry(pieces[1].id))
        await model.perform(.duplicate)
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).isEmpty)
        model.select(.entry(pieces[0].id))
        await model.perform(.duplicate)
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).count == 1)
    }

    @Test("PC-14 Add Entry above 0.8 with project and task creates the entry, records accepted; else the popover; below 0.35 nothing")
    func log() async throws {
        let block = try Self.block("08:00", "08:30")
        let world = try await World(blocks: [block])
        let model = world.model
        // Thresholds: Log skips the popover only above 0.8; below 0.35 nothing is prefilled.
        let project = try await world.test.projects(["Noise Model"])[0]
        #expect(SuggestionCandidate(projectID: project.id, task: "Draft", confidence: 0.85, reasons: []).logsDirectly)
        #expect(!SuggestionCandidate(projectID: project.id, task: "Draft", confidence: 0.8, reasons: []).logsDirectly)
        #expect(!SuggestionCandidate(projectID: project.id, task: "Draft", confidence: 0.34, reasons: []).isConfident)
        // Without examples nothing is prefilled and Log opens the popover.
        await model.log(block)
        #expect(model.draft?.projectID == nil)
        #expect(model.draft?.task.isEmpty == true)
        model.escape()
        // A rule gives confidence 1 with project and task: Log creates the entry directly.
        await model.setRules([SuggestionRule(kind: .groupKey, pattern: "tmux:paper", projectID: project.id, task: "Draft")])
        await model.log(block)
        #expect(model.draft == nil)
        let entries = try await world.test.store.entries(on: Self.day("2024-03-14"))
        #expect(entries.map(\.task) == ["Draft"])
        let feedback = try await world.test.store.feedback(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(feedback.map(\.outcome) == [.accepted])
        #expect(feedback.first?.source == .block)
        #expect(feedback.first?.blockDevice == "macbook")
    }

    @Test(
        "PC-15 a confirmed Delete This Activity sends one delete-block; Cancel sends nothing; the open block and the iPad do not offer it"
    )
    func deleteBlockFromLog() async throws {
        let closed = try Self.block("08:00", "08:30")
        let open = try Self.block("09:30", "10:00", open: true)
        let world = try await World(blocks: [closed, open])
        let model = world.model
        model.confirmDeleteFromLog(closed)
        await model.deleteBlockFromLog(confirmed: false)
        #expect(world.commands.commands.isEmpty)
        model.confirmDeleteFromLog(closed)
        #expect(model.blockToDelete == closed)
        await model.deleteBlockFromLog(confirmed: true)
        #expect(world.commands.commands == ["delete-block macbook \(ActivityTimestamp.text(closed.start, utcOffset: closed.utcOffset))"])
        #expect(!model.canDeleteFromLog(open))
        model.isRecordingMac = false
        #expect(!model.canDeleteFromLog(closed))
    }

    @Test(
        "PC-16 untracked 12, 3, and 40 minutes give two rows; Log is one transaction and one undo step; Cancel writes nothing"
    )
    func fillDay() async throws {
        let blocks = try [
            Self.block("07:00", "07:12"),
            Self.block("07:30", "07:33", context: "mail"),
            Self.block("08:00", "08:40", context: "safari"),
        ]
        let world = try await World(blocks: blocks)
        let model = world.model
        #expect(model.canFillDay)
        await model.openFillDay(Self.day("2024-03-14"))
        let sheet = try #require(model.fillDay)
        #expect(sheet.rows.count == 2)
        #expect(sheet.rows.allSatisfy { !$0.checked })
        model.cancelFillDay()
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).isEmpty)
        #expect(try await world.test.store.feedback(in: DateInterval(start: .distantPast, end: .distantFuture)).isEmpty)
        await model.openFillDay(Self.day("2024-03-14"))
        let again = try #require(model.fillDay)
        again.setTask("Mail", row: again.rows[0].id)
        #expect(again.logTitle == "Log 1 entry (12m)")
        await model.logFillDay()
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).map(\.task) == ["Mail"])
        let feedback = try await world.test.store.feedback(in: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(Set(feedback.map(\.outcome)) == [.edited, .skipped])
        #expect(world.test.undo.undoActionName == "Fill Day")
        world.test.undo.undo()
        await model.waitForUndo()
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).isEmpty)
    }

    @Test("PC-9 an overlapping card's ⚠ tooltip names the others and the whole minutes; touching entries are left out")
    func overlapHelp() async throws {
        let world = try await World()
        let model = world.model
        let paper = try await world.test.entry("Paper", from: "08:00", to: "09:00")
        _ = try await world.test.entry("Standup", from: "08:47:30", to: "09:15")
        _ = try await world.test.entry("Mail", from: "07:30", to: "08:05")
        _ = try await world.test.entry("Review", from: "09:00", to: "09:30")
        await model.reload()
        #expect(model.overlapping(on: Self.day("2024-03-14")).contains(paper.id))
        #expect(model.overlapHelp(for: paper) == "Overlaps \"Mail\" by 5 min, \"Standup\" by 12 min")
    }
}
