// The Calendar's cards: selecting, dragging, and resizing them
// (calendar.md §2.4, §2.5, §4.2, §4.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension CalendarSectionTests {
    @Test("PC-37 ⇧-click and ⌘-click extend the selection over any kind of card; a plain click selects alone")
    func extendingClicks() async throws {
        let world = try await World()
        let model = world.model
        let entry = try await world.test.entry("Paper", from: "08:00", to: "09:00")
        let other = try await world.test.entry("Email", from: "09:00", to: "09:30")
        await model.reload()
        let plain = ModifierState.extendDown
        defer { ModifierState.extendDown = plain }
        ModifierState.extendDown = { false }
        #expect(model.click(.entry(entry.id)))
        ModifierState.extendDown = { true }
        #expect(!model.click(.entry(other.id)))
        #expect(!model.click(.timeBlock("block")))
        #expect(!model.click(.block("activity")))
        #expect(!model.click(.event("event")))
        #expect(model.selection == [.entry(entry.id), .entry(other.id), .timeBlock("block"), .block("activity"), .event("event")])
        model.click(.entry(other.id))
        #expect(!model.selection.contains(.entry(other.id)))
        ModifierState.extendDown = { false }
        model.click(.entry(other.id))
        #expect(model.selection == [.entry(other.id)])
    }

    @Test("PC-38 a drag's pointer finds the column, ⌥ snaps to the minute, and Escape cancels the rest of the drag")
    func entryDrag() async throws {
        let world = try await World()
        let model = world.model
        let entry = try await world.test.entry("Paper", from: "08:00", to: "09:00")
        await model.reload()
        model.setViewportWidth(1040)
        model.viewport.show(Self.day("2024-03-13"))
        let today = Self.day("2024-03-14")
        let yesterday = Self.day("2024-03-13")
        // 260 points: Activity to 57.8, Tracked to 173.3, then Calendar.
        #expect(model.dropTarget(from: today, at: CGPoint(x: 100, y: 0)) == CalendarDropTarget(day: today, column: .tracked))
        #expect(model.dropTarget(from: today, at: CGPoint(x: 20, y: 0)) == CalendarDropTarget(day: today, column: .activity))
        #expect(model.dropTarget(from: today, at: CGPoint(x: 200, y: 0)) == CalendarDropTarget(day: today, column: .calendar))
        #expect(model.dropTarget(from: today, at: CGPoint(x: -150, y: 0)) == CalendarDropTarget(day: yesterday, column: .tracked))
        // The time axis lies left of the first day, the headers above the hours.
        #expect(model.dropTarget(from: yesterday, at: CGPoint(x: -10, y: 0)) == nil)
        model.visibleColumnsY = 300 ... 900
        #expect(model.dropTarget(from: today, at: CGPoint(x: 100, y: 200)) == nil)
        #expect(model.dropTarget(from: today, at: CGPoint(x: 100, y: 400)) != nil)

        // The time label and the drop agree; ⌥ keeps the minute.
        let listed = try #require(model.listing(entry.id)?.entry)
        #expect(try model.movedInterval(of: listed, by: 420)?.start == TestApp.date("2024-03-14T08:05"))
        #expect(try model.movedInterval(of: listed, by: 420, option: true)?.start == TestApp.date("2024-03-14T08:07"))
        await model.move(entry.id, by: 420, option: true)
        #expect(try await world.test.store.entry(entry.id)?.start == TestApp.date("2024-03-14T08:07"))

        // Escape during a drag: the card goes back, the selection stays.
        model.selection = [.entry(entry.id)]
        let start = CGPoint(x: 10, y: 10)
        #expect(model.continueCardDrag(.entry(entry.id), on: today, from: start))
        await model.perform(.escape)
        #expect(model.cardDragCancelled)
        #expect(model.selection == [.entry(entry.id)])
        #expect(!model.continueCardDrag(.entry(entry.id), on: today, from: start))
        #expect(!model.finishCardDrag())
        #expect(model.cardDrag == nil)
        // The next drag works, and Escape deselects again.
        #expect(model.continueCardDrag(.entry(entry.id), on: today, from: start))
        #expect(model.finishCardDrag())
        await model.perform(.escape)
        #expect(model.selection.isEmpty)
        // A cancelled drag the system ended does not reach the next one.
        #expect(model.continueCardDrag(.entry(entry.id), on: today, from: start))
        #expect(model.cancelCardDrag())
        #expect(model.continueCardDrag(.entry(entry.id), on: today, from: CGPoint(x: 20, y: 30)))
    }

    /// A time block from `start` to `end` on the time-block calendar.
    private func timeBlock(_ world: World, from start: String, to end: String, project: Project? = nil) async throws -> TimeBlock {
        let calendar = try #require(world.model.timeBlockCalendar)
        let event = try world.events.create(TimeBlock.draft(
            calendarID: calendar.id,
            title: "Write",
            project: project?.id,
            interval: DateInterval(start: world.test.time(start), end: world.test.time(end)),
            notes: nil,
            scheme: "timetracking"
        ))
        await world.model.reload()
        return try #require(world.model.timeBlocks.first { $0.id == event.id })
    }

    @Test("PC-39 a time block's label and color come from its project, whether or not an entry of it is loaded")
    func timeBlockLabel() async throws {
        let world = try await World()
        let project = try await world.test.projects(["Noise Model"])[0]
        await world.model.reload()
        #expect(world.model.entries.isEmpty)
        let linked = try await timeBlock(world, from: "14:00", to: "15:00", project: project)
        let row = try #require(world.model.projectRows[project.id])
        let label = try #require(world.model.label(of: linked))
        #expect(label.name == "Noise Model")
        #expect(label.projectAndClient == ProjectLabel(row).projectAndClient)
        #expect(label.color != nil)
        #expect(label.color == row.area?.color)
        let unlinked = try await timeBlock(world, from: "16:00", to: "17:00")
        #expect(world.model.label(of: unlinked) == nil)
    }

    @Test("PC-40 a time block moves across days past the now-line, snaps, moves whole, and resizes in its piece's column")
    func timeBlockMoveAndResize() async throws {
        let world = try await World()
        let model = world.model
        let block = try await timeBlock(world, from: "14:00", to: "15:00")
        let today = Self.day("2024-03-14")
        let tomorrow = Self.day("2024-03-15")
        await model.moveTimeBlock(block.id, by: 3600, to: tomorrow, from: today)
        var moved = try #require(world.events.allEvents.first)
        #expect(try moved.start == world.test.time("2024-03-15T15:00"))
        #expect(try moved.end == world.test.time("2024-03-15T16:00"))
        // One undo step takes it back.
        world.test.undo.undo()
        await model.waitForUndo()
        #expect(world.events.allEvents.first?.start == block.event.start)

        // 7 minutes snap to 5, with ⌥ to the minute; the label agrees.
        let current = try #require(model.timeBlocks.first)
        #expect(try model.movedInterval(of: current, by: 420).start == world.test.time("14:05"))
        #expect(try model.movedInterval(of: current, by: 420, option: true).start == world.test.time("14:07"))

        // The edges: to the next snap mark, down to 1 minute.
        let id = current.id
        try await model.resizeTimeBlock(id, top: false, to: world.test.time("15:32"))
        moved = try #require(world.events.allEvents.first)
        #expect(try moved.end == world.test.time("15:30"))
        try await model.resizeTimeBlock(moved.id, top: true, to: world.test.time("16:00"))
        moved = try #require(world.events.allEvents.first)
        #expect(try moved.start == world.test.time("15:29"))
        #expect(try moved.end == world.test.time("15:30"))
    }

    @Test("PC-40 with Midnight at 04:00 the later piece of a block moves it whole, and its edge stays in that column")
    func timeBlockAcrossMidnight() async throws {
        let world = try await World()
        let model = world.model
        try await world.test.store.set(.midnightHour, 4)
        let block = try await timeBlock(world, from: "03:00", to: "05:00")
        let later = Self.day("2024-03-14")
        await model.moveTimeBlock(block.id, by: 3600, to: later, from: later)
        let moved = try #require(world.events.allEvents.first)
        #expect(try moved.start == world.test.time("04:00"))
        #expect(try moved.end == world.test.time("06:00"))
        let earlier = try await timeBlock(world, from: "2024-03-14T02:00", to: "2024-03-14T04:30")
        // The later piece's top edge cannot leave its column.
        try await model.resizeTimeBlock(earlier.id, top: true, to: world.test.time("03:00"), on: later)
        let resized = try #require(world.events.allEvents.first { $0.id == earlier.id })
        #expect(try resized.start == world.test.time("04:00"))
    }

    @Test("PC-41 the + of a time block or event opens the popover, past blocks only")
    func createFromCards() async throws {
        let world = try await World()
        let model = world.model
        let project = try await world.test.projects(["Noise Model"])[0]
        await model.reload()
        let block = try await timeBlock(world, from: "08:00", to: "11:00", project: project)
        model.createEntry(fromEvent: block.event, timeBlock: block)
        #expect(try model.draft?.interval == DateInterval(start: world.test.time("08:00"), end: world.test.time("10:00")))
        #expect(model.draft?.projectID == project.id)
        model.escape()
        let future = try await timeBlock(world, from: "12:00", to: "13:00")
        model.createEntry(fromEvent: future.event, timeBlock: future)
        #expect(model.draft == nil)
        #expect(model.notice?.text == CalendarEditing.futureNotice)
    }
}
