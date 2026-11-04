// The Calendar's overlapping loads and commits (spec_calendar.md §1.2,
// §2.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension CalendarSectionTests {
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

    @Test("PC-32 a reload finishing after a later one leaves the later one's entries; the days count as loaded only once their data is in")
    func laterReloadWins() async throws {
        let test = try await TestApp()
        let reader = GatedActivityReader(InMemoryActivityStore())
        let router = SectionRouter(
            store: test.store,
            clock: test.clock,
            device: test.app.settings.device,
            activity: reader,
            events: InMemoryCalendarEventStore()
        )
        let model = router.calendar
        let slow = Task { await model.reload() }
        await reader.waitUntilHeld()
        #expect(model.loadedDays == nil)
        _ = try await test.entry("Written meanwhile", from: "08:00", to: "09:00")
        await model.reload()
        #expect(model.entries.map(\.entry.task) == ["Written meanwhile"])
        #expect(model.loadedDays != nil)
        reader.release()
        await slow.value
        #expect(model.entries.map(\.entry.task) == ["Written meanwhile"])
    }
}
