// The Calendar section: time blocks, events, calendar access, the router
// request, and the key commands (spec_planner_calendar.md §8).

import Foundation
import SwiftUI
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension PlannerCalendarTests {
    @Test("PC-18 a drawn time block is saved as an event; ⌘Z after Delete recreates it with the same fields")
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
        "PC-20 dragging a 09:00 to 11:00 time block into Tracked at 10:00 gives 09:00 to 10:00 with its project and title; events give their title"
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
        model.shownCalendars = [external.choice]
        let seminar = world.events.add(CalendarEventDraft(calendarID: "work", title: "Seminar", start: start - 3600, end: start - 1800))
        await model.reload()
        let timeBlock = try #require(model.timeBlocks.first { $0.id == block.id })
        await model.createEntry(fromEvent: timeBlock.event, timeBlock: timeBlock)
        #expect(try model.draft?.interval == DateInterval(start: start, end: TestApp.date("2024-03-14T10:00")))
        #expect(model.draft?.projectID == project.id)
        #expect(model.draft?.task == "Write noise section")
        model.escape()
        await model.createEntry(fromEvent: seminar, timeBlock: nil)
        #expect(model.draft?.task == "Seminar")
        model.escape()
        // External events cannot be moved or deleted.
        await model.moveTimeBlock(seminar.id, by: 3600)
        model.selection = [.event(seminar.id)]
        await model.perform(.delete)
        #expect(world.events.allEvents.first { $0.id == seminar.id }?.start == seminar.start)
    }

    @Test("PC-21 without calendar access or an iCloud account the column shows its notice and the rest works")
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
        "PC-23 showCalendar(day: Oct 29, hour: 9, highlight: hour) makes Oct 29 leftmost with 09:00 at the top, Activity on, the hour's blocks pulsed"
    )
    func showCalendarRequest() async throws {
        let morning = try Self.block("09:10", "09:40")
        let afternoon = try Self.block("07:00", "07:20")
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

    @Test("PC-24 every key of section 6 has a menu item and its effect")
    func keyCommands() async throws {
        let world = try await World()
        let model = world.model
        let shortcuts = CalendarKeyCommand.allCases.map { "\($0.shortcut.key.character)\($0.shortcut.modifiers.rawValue)" }
        #expect(Set(shortcuts).count == CalendarKeyCommand.allCases.count)
        #expect(CalendarKeyCommand.allCases.allSatisfy { !$0.title.isEmpty })
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
        await model.perform(.fillDay)
        #expect(model.fillDay != nil)
        model.cancelFillDay()
        await model.perform(.createEntry)
        #expect(model.draft == nil)
    }
}
