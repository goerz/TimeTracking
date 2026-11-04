// The Calendar section's view model: Today, scrolling, deleting, splitting,
// Delete This Activity, time blocks, calendar access, the settings, the
// router request, and the key commands (spec_calendar.md §7).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct CalendarSectionTests {
    /// A section router over the test store with an in-memory activity log and calendar store.
    @MainActor
    struct World {
        let test: TestApp
        let router: SectionRouter
        let model: CalendarModel
        let activity: InMemoryActivityStore
        let events: InMemoryCalendarEventStore
        let commands = RecordingTrackerCommands()

        init(
            blocks: [ActivityBlock] = [],
            stretches: [ActivityBackgroundStretch] = [],
            events: InMemoryCalendarEventStore = InMemoryCalendarEventStore()
        ) async throws {
            let test = try await TestApp()
            self.test = test
            self.activity = InMemoryActivityStore(blocks: blocks, stretches: stretches)
            self.events = events
            self.router = SectionRouter(
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

    @Test("PC-26 the activity column has the day's background stretches, each named by its items and their time while away")
    func backgroundStretches() async throws {
        let start = ManualClock.fixtureNow().addingTimeInterval(-3 * 3600)
        let item = ActivityItem(context: "claude", subject: "refactor-parser", detail: "", seconds: 2280, device: "macbook")
        let stretch = ActivityBackgroundStretch(
            start: start,
            end: start.addingTimeInterval(2310),
            items: [item],
            utcOffset: TimeZone.current.secondsFromGMT(for: start)
        )
        let world = try await World(stretches: [stretch])
        #expect(world.model.stretches == [stretch])
        #expect(stretch.summaryText == "In the background while away: Claude refactor-parser 38m")
    }

    @Test("PC-2 with today Thursday and room for 5 whole days, ⌘T makes Tuesday first, Monday for 7, Thursday for 1 and 2")
    func today() async throws {
        let world = try await World()
        let model = world.model
        for (days, first) in [(5.0, "2024-03-12"), (7, "2024-03-11"), (1, "2024-03-14"), (2, "2024-03-14"), (5.6, "2024-03-12")] {
            model.setViewportWidth(days * model.dayWidth)
            await model.shift(days: 20)
            await model.perform(.today)
            #expect(model.firstDay == Self.day(first))
            #expect(model.viewport.offset == 0)
        }
        // The subtitle names the days at least half visible.
        #expect(model.rangeLabel == "Tue, Mar 12 – Sun, Mar 17 · W11")
        #expect(model.menuTitle == "Today")
        // A new window width keeps the leftmost day.
        model.setViewportWidth(3 * model.dayWidth)
        #expect(model.firstDay == Self.day("2024-03-12"))
    }

    @Test("PC-3 a sideways scroll of 1.4 day widths moves 1.4 days and loads what comes into view; the URL's date is first")
    func scrollAndURL() async throws {
        let world = try await World()
        let model = world.model
        model.setViewportWidth(5 * model.dayWidth)
        let first = model.firstDay
        model.scroll(byPoints: 1.4 * model.dayWidth)
        #expect(model.firstDay == first.adding(days: 1))
        #expect(abs(model.viewport.offset - 0.4) < 1e-9)
        #expect(model.days == (1 ... 6).map { first.adding(days: $0) })
        // The arrows snap: → to the next day start, ← to the cut-off day's.
        await model.shift(days: 1)
        #expect(model.firstDay == first.adding(days: 2))
        model.scroll(byPoints: -0.5 * model.dayWidth)
        await model.shift(days: -1)
        #expect(model.firstDay == first.adding(days: 1))
        #expect(model.viewport.offset == 0)
        // A trackpad's momentum stops at the snap; the next gesture scrolls.
        model.scroll(byPoints: 30, momentum: true)
        #expect(model.viewport.offset == 0)
        model.scroll(byPoints: 26)
        model.scroll(byPoints: 26, momentum: true)
        #expect(abs(model.viewport.offset - 0.2) < 1e-9)
        await model.shift(days: -1)
        // Far away, the data loads around the new days.
        let entry = try await world.test.entry("Earlier", from: "2024-02-22T09:00", to: "2024-02-22T10:00")
        model.scroll(byPoints: -20 * model.dayWidth)
        await model.loaded()
        #expect(model.days.contains(Self.day("2024-02-22")))
        #expect(model.coversDays)
        #expect(model.entries(on: Self.day("2024-02-22")).map(\.entry.id) == [entry.id])
        let router = URLRouter(app: world.test.app, scheme: "timetracking-debug")
        _ = try await router.open(#require(URL(string: "timetracking-debug://planner/calendar?date=2026-10-29")))
        let sections = world.test.app.sections
        #expect(sections.section == .calendar)
        await sections.consumeCalendarRequest()
        #expect(sections.calendar.firstDay == Self.day("2026-10-29"))
    }

    @Test("PC-28 Filters and the search fade the entries they leave out and keep them out of the tracked totals")
    func filtersAndSearch() async throws {
        let world = try await World()
        let model = world.model
        let projects = try await world.test.projects(["Noise Model", "Teaching"])
        let noise = try await world.test.entry("Clarify noise model", projects[0], from: "08:00", to: "09:00")
        let teaching = try await world.test.entry("Grade draft", projects[1], from: "09:00", to: "09:30")
        await model.reload()
        let listing = { (entry: TimeEntry) in try #require(model.listing(entry.id)) }
        #expect(!model.isFiltering)
        #expect(model.summary?.tracked == 5400)
        model.filters.projects = [projects[0].id]
        #expect(model.filters.activeKindCount == 1)
        #expect(try model.passesFilters(listing(noise)))
        #expect(try !model.passesFilters(listing(teaching)))
        #expect(model.summary?.tracked == 3600)
        #expect(model.dayTotals[Self.day("2024-03-14")]?.tracked == 3600)
        #expect(model.filterChips.map(\.text) == ["University · Research · Noise Model"])
        model.clearFilters()
        model.search = "draft"
        #expect(try model.passesFilters(listing(teaching)))
        #expect(try !model.passesFilters(listing(noise)))
        #expect(model.summary?.tracked == 1800)
        // The plain keys are off while the search field has the focus.
        model.searchFocused = true
        #expect(model.takesTextInput)
        model.search = ""
        #expect(model.summary?.tracked == 5400)
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

    @Test("PC-31 two commits of one draft arriving together store one entry")
    func draftCommitsOnce() async throws {
        let world = try await World()
        let model = world.model
        try model.draw(on: Self.day("2024-03-14"), from: TestApp.date("2024-03-14T08:00"), to: TestApp.date("2024-03-14T09:00"))
        model.draft?.task = "Draft intro"
        // Return and a click elsewhere: the second starts while the first awaits the store.
        async let first: Void = model.commitDraft()
        async let second: Void = model.dismissDraft(commit: true)
        _ = await (first, second)
        #expect(model.draft == nil)
        #expect(try await world.test.store.entries(on: Self.day("2024-03-14")).map(\.task) == ["Draft intro"])
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

    @Test(
        "PC-14 a confirmed Delete This Activity sends one delete-block; Cancel sends nothing; the open block and the iPad do not offer it"
    )
    func deleteBlockFromLog() async throws {
        let closed = try TestBlocks.block("08:00", "08:30")
        let open = try TestBlocks.block("09:30", "10:00", open: true)
        let world = try await World(blocks: [closed, open])
        let model = world.model
        model.confirmDeleteFromLog(closed)
        await model.deleteBlockFromLog(confirmed: false)
        #expect(world.commands.commands.isEmpty)
        model.confirmDeleteFromLog(closed)
        #expect(model.blockToDelete == closed)
        await model.deleteBlockFromLog(confirmed: true)
        #expect(world.commands.commands == ["delete-block \(ActivityTimestamp.text(closed.start, utcOffset: closed.utcOffset))"])
        #expect(!model.canDeleteFromLog(open))
        model.isRecordingMac = false
        #expect(!model.canDeleteFromLog(closed))
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
