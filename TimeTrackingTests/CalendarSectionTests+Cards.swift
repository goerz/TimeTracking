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
}
