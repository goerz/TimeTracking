// The Calendar section: time blocks, events, calendar access, the router
// request, and the key commands (spec_calendar.md §7).

import Foundation
import SwiftUI
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension CalendarSectionTests {
    @Test("PC-16 a drawn time block is saved as an event; ⌘Z after Delete recreates it with the same fields")
    func timeBlocks() async throws {
        let world = try await World()
        let model = world.model
        let project = try await world.test.projects(["Noise Model"])[0]
        await model.reload()
        try model.drawTimeBlock(on: Self.day("2024-03-14"), from: TestApp.date("2024-03-14T14:00"), to: TestApp.date("2024-03-14T15:30"))
        model.blockDraft?.title = "Write noise section"
        model.blockDraft?.projectID = project.id
        await model.saveTimeBlock()
        let event = try #require(world.events.allEvents.first)
        #expect(event.title == "Write noise section")
        #expect(event.url == TimeBlockLink.url(for: project.id, scheme: "timetracking"))
        #expect(model.timeBlocks.first?.link == .project(project.id))
        await model.deleteTimeBlocks([event.id])
        #expect(world.events.allEvents.isEmpty)
        world.test.undo.undo()
        await model.waitForUndo()
        #expect(world.events.allEvents.first?.draft == event.draft)
    }

    @Test(
        "PC-18 a 09:00 to 11:00 time block dropped at 10:00 gives 09:00 to 10:00 with project and title; events give their title"
    )
    func entriesFromEvents() async throws {
        let world = try await World()
        let model = world.model
        let project = try await world.test.projects(["Noise Model"])[0]
        await model.reload()
        let calendar = try #require(model.timeBlockCalendar)
        let start = try TestApp.date("2024-03-14T09:00")
        let block = try world.events.create(TimeBlock.draft(
            calendarID: calendar.id,
            title: "Write noise section",
            project: project.id,
            interval: DateInterval(start: start, duration: 7200),
            notes: nil,
            scheme: "timetracking"
        ))
        let external = CalendarInfo(id: "work", title: "Work", sourceID: "icloud", sourceTitle: "iCloud", color: "#3B5BDB")
        world.events.addCalendar(external)
        await model.setShown(external, true)
        let seminar = world.events.add(CalendarEventDraft(calendarID: "work", title: "Seminar", start: start - 3600, end: start - 1800))
        await model.reload()
        let timeBlock = try #require(model.timeBlocks.first { $0.id == block.id })
        model.createEntry(fromEvent: timeBlock.event, timeBlock: timeBlock)
        #expect(try model.draft?.interval == DateInterval(start: start, end: TestApp.date("2024-03-14T10:00")))
        #expect(model.draft?.projectID == project.id)
        #expect(model.draft?.task == "Write noise section")
        model.escape()
        model.createEntry(fromEvent: seminar, timeBlock: nil)
        #expect(model.draft?.task == "Seminar")
        model.escape()
        // External events cannot be moved or deleted.
        await model.moveTimeBlock(seminar.id, by: 3600)
        model.selection = [.event(seminar.id)]
        await model.perform(.delete)
        #expect(world.events.allEvents.first { $0.id == seminar.id }?.start == seminar.start)
    }

    @Test("PC-24 with Sleep on and Workouts off, a night reaching into the day is drawn there and a workout is not")
    func healthLines() async throws {
        let world = try await World()
        let model = world.model
        let store = world.test.store
        let night = try DateInterval(start: world.test.date("2024-03-13T23:00"), end: world.test.date("2024-03-14T06:30"))
        let run = try DateInterval(start: world.test.date("2024-03-14T07:00"), end: world.test.date("2024-03-14T07:40"))
        try await store.replaceHealthPeriods(.sleep, from: world.test.date("2024-03-01T00:00"), with: [night])
        try await store.replaceHealthPeriods(.workout, from: world.test.date("2024-03-01T00:00"), with: [run])
        await model.reload()
        #expect(model.healthPeriods(on: Self.day("2024-03-14")).isEmpty)
        await model.setShowHealth(.sleep, true)
        #expect(try await store.value(.calendarShowSleep))
        #expect(model.healthPeriods(on: Self.day("2024-03-14")).map(\.interval) == [night])
        #expect(model.healthPeriods(on: Self.day("2024-03-13")).map(\.interval) == [night])
        await model.setShowHealth(.workout, true)
        #expect(model.healthPeriods(on: Self.day("2024-03-14")).map(\.kind) == [.sleep, .workout])
        await model.setShowHealth(.sleep, false)
        #expect(model.healthPeriods(on: Self.day("2024-03-14")).map(\.interval) == [run])
    }

    @Test("PC-22 snapping and Calendars to show are synced; a checked calendar this device lacks stays checked")
    func syncedSettings() async throws {
        let world = try await World()
        let model = world.model
        let work = CalendarInfo(id: "work", title: "Work", sourceID: "icloud", sourceTitle: "iCloud", color: "#3B5BDB")
        world.events.addCalendar(work)
        let elsewhere = CalendarChoice(account: "Google", calendar: "Team")
        try await world.test.store.set(.calendarShownCalendars, [elsewhere])
        await model.loadSettings()
        #expect(model.calendarChoices.flatMap(\.calendars).contains(work))
        #expect(model.shownCalendars == [elsewhere])
        await model.setShown(work, true)
        #expect(try await world.test.store.value(.calendarShownCalendars) == [elsewhere, work.choice])
        await model.setShown(work, false)
        #expect(try await world.test.store.value(.calendarShownCalendars) == [elsewhere])
        await model.setSnapMinutes(15)
        #expect(model.snapMinutes == 15)
        #expect(try await world.test.store.value(.calendarSnapMinutes) == 15)
    }

    @Test("PC-19 without calendar access or an iCloud account the column shows its notice and the rest works")
    func calendarAccess() async throws {
        let denied = try await World(events: InMemoryCalendarEventStore(access: .denied))
        _ = try await denied.test.entry("Paper", from: "08:00", to: "09:00")
        await denied.model.reload()
        #expect(denied.model.timeBlockState == .noAccess)
        #expect(denied.model.entries.count == 1)
        #expect(!denied.model.canDrawTimeBlocks)
        let local = InMemoryCalendarEventStore(sources: [CalendarSourceInfo(id: "local", title: "On My Mac", isICloud: false)])
        let noICloud = try await World(events: local)
        #expect(noICloud.model.timeBlockState == .noICloudAccount)
        #expect(!noICloud.model.canDrawTimeBlocks)
        // Granting access fills the column without relaunch.
        let later = InMemoryCalendarEventStore(access: .notDetermined)
        let granted = try await World(events: later)
        #expect(granted.model.timeBlockCalendar?.title == "Time Blocks")
    }

    @Test(
        "PC-20 showCalendar(day:hour:highlight:) puts the day leftmost, the hour on top, Activity on, the hour's blocks pulsed"
    )
    func showCalendarRequest() async throws {
        let morning = try TestBlocks.block("09:10", "09:40")
        let afternoon = try TestBlocks.block("07:00", "07:20")
        let world = try await World(blocks: [morning, afternoon])
        let model = world.model
        await model.toggle(.activity)
        model.zoom(by: 1)
        await model.setVisibleDays(3)
        let zoom = model.pointsPerHour
        world.router.showCalendar(day: Self.day("2024-03-14"), hour: 9, highlight: .hour(9))
        await world.router.consumeCalendarRequest()
        #expect(world.router.section == .calendar)
        #expect(model.firstDay == Self.day("2024-03-14"))
        #expect(model.scrollRequest?.hour == 9)
        #expect(model.showsActivity)
        #expect(model.isHighlighted(morning))
        #expect(!model.isHighlighted(afternoon))
        #expect(model.pointsPerHour == zoom)
        #expect(model.visibleDays == 3)
    }

    @Test(
        "PC-21 every key of section 5 has its effect; arrows, Tab, and Escape are the view's, the rest Entry menu or View menu items"
    )
    func keyCommands() async throws {
        let world = try await World()
        let model = world.model
        let shortcuts = CalendarKeyCommand.allCases.map { "\($0.shortcut.key.character)\($0.shortcut.modifiers.rawValue)" }
        #expect(Set(shortcuts).count == CalendarKeyCommand.allCases.count)
        #expect(CalendarKeyCommand.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(
            Set(CalendarKeyCommand.allCases.filter(\.isViewKey))
                == [.previousDay, .nextDay, .previousSpan, .nextSpan, .nextEntry, .previousEntry, .escape]
        )
        #expect(Set(CalendarKeyHandlers.commands) == Set(CalendarKeyCommand.allCases.filter(\.isViewKey)))
        #expect(CalendarKeyHandlers.commands.count == CalendarKeyCommand.allCases.count(where: \.isViewKey))
        // A plain key's button taking the key with ⇧ held does the ⇧ command.
        #expect(CalendarKeyHandlers.resolved(.nextDay, shiftDown: true) == .nextSpan)
        #expect(CalendarKeyHandlers.resolved(.previousDay, shiftDown: true) == .previousSpan)
        #expect(CalendarKeyHandlers.resolved(.nextEntry, shiftDown: true) == .previousEntry)
        #expect(CalendarKeyHandlers.resolved(.nextSpan, shiftDown: true) == .nextSpan)
        #expect(CalendarKeyHandlers.resolved(.nextDay, shiftDown: false) == .nextDay)
        try await sharedViewCommands(world)
        let first = model.firstDay
        await model.perform(.nextDay)
        #expect(model.firstDay == first.adding(days: 1))
        await model.perform(.previousDay)
        await model.perform(.nextSpan)
        #expect(model.firstDay == first.adding(days: model.visibleDays))
        await model.perform(.previousSpan)
        #expect(model.firstDay == first)
        await model.perform(.zoomIn)
        #expect(model.pointsPerHour == 90)
        await model.perform(.zoomOut)
        await model.perform(.zoomOut)
        #expect(model.pointsPerHour == 72 / 1.25)
        await model.perform(.zoomReset)
        #expect(model.pointsPerHour == 72)
        await model.perform(.fewerDays)
        #expect(model.visibleDays == 4)
        await model.perform(.moreDays)
        #expect(model.visibleDays == 5)
        await model.perform(.toggleActivity)
        #expect(!model.showsActivity)
        await model.perform(.toggleCalendar)
        #expect(!model.showsCalendar)
        await model.perform(.today)
        #expect(model.firstDay == CalendarStrip.firstDay(centering: model.today, visibleDays: 5))
        try await entryCommands(world)
    }

    /// View › Previous Period, Next Period, and Go to Date… in the Calendar,
    /// and Timer › Continue on its one selected entry.
    private func sharedViewCommands(_ world: World) async throws {
        let model = world.model
        let router = world.router
        router.select(.calendar)
        #expect(router.canShiftPeriod)
        let first = model.firstDay
        await router.shiftPeriod(by: 1)
        #expect(model.firstDay == first.adding(days: model.visibleDays))
        await router.shiftPeriod(by: -1)
        #expect(model.firstDay == first)
        #expect(router.dateRangeTitle == "Go to Date…")
        router.showDateRange()
        #expect(model.showsMonthPicker)
        model.showsMonthPicker = false
        let entry = try await world.test.entry("Continue me", from: "07:00", to: "07:30")
        await model.reload()
        #expect(router.continueTarget == nil)
        model.select(.entry(entry.id))
        #expect(router.continueTarget == .entry(entry.id))
        #expect(await router.continueSelection())
        let running = try #require(try await world.test.store.runningEntry())
        #expect(running.task == "Continue me")
        model.selection = []
        try await world.test.store.delete([running.id, entry.id])
        await model.reload()
    }

    private func entryCommands(_ world: World) async throws {
        let model = world.model
        let early = try await world.test.entry("Early", from: "08:00", to: "08:30")
        let late = try await world.test.entry("Late", from: "09:00", to: "09:30")
        await model.reload()
        await model.perform(.nextEntry)
        #expect(model.selectedEntry == early.id)
        await model.perform(.nextEntry)
        #expect(model.selectedEntry == late.id)
        await model.perform(.previousEntry)
        #expect(model.selectedEntry == early.id)
        await model.perform(.moveLater)
        #expect(try await world.test.store.entry(early.id)?.start == TestApp.date("2024-03-14T08:05"))
        await model.perform(.moveEarlier)
        await model.perform(.lengthen)
        #expect(try await world.test.store.entry(early.id)?.end == TestApp.date("2024-03-14T08:35"))
        await model.perform(.shorten)
        #expect(try await world.test.store.entry(early.id)?.end == TestApp.date("2024-03-14T08:30"))
        await model.perform(.edit)
        #expect(model.editingEntry == early.id)
        await model.perform(.escape)
        #expect(model.editingEntry == nil)
        await model.perform(.escape)
        #expect(model.selection.isEmpty)
        model.select(.entry(early.id))
        await model.perform(.duplicate)
        #expect(try await world.test.store.entries(on: Self.day("2024-03-15")).isEmpty)
        await model.perform(.delete)
        #expect(try await world.test.store.entry(early.id) == nil)
        await model.perform(.createEntry)
        #expect(model.draft == nil)
    }
}
