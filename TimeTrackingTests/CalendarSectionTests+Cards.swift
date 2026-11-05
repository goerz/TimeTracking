// The Calendar's cards: selecting, dragging, and resizing them
// (spec_calendar.md §2.4, §2.5, §4.2, §4.4).

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
}
