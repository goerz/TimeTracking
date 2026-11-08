// The task suggestions of the Calendar's drawn entry (calendar.md §2.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension CalendarSectionTests {
    @Test("PC-43 a drawn entry's task field suggests earlier tasks; Return stores its task and project, after Escape the text")
    func draftSuggestions() async throws {
        let world = try await World()
        let model = world.model
        let day = Self.day("2024-03-14")
        let project = try await world.test.projects(["Noise Model"])[0]
        try await world.test.entry("Clarify noise model", project, from: "07:00", to: "07:30")
        try model.draw(on: day, from: TestApp.date("2024-03-14T08:00"), to: TestApp.date("2024-03-14T08:30"))
        await model.draftTaskEdited("clar")
        #expect(model.draftTaskField.suggestions.map(\.task) == ["Clarify noise model"])
        await model.submitDraft()
        #expect(model.draft == nil)
        let eight = try TestApp.date("2024-03-14T08:00")
        let stored = try await world.test.store.entries(on: day).first { $0.start == eight }
        #expect(stored?.task == "Clarify noise model" && stored?.projectID == project.id)

        // Escape closes the suggestions and Return then stores the text.
        try model.draw(on: day, from: TestApp.date("2024-03-14T08:30"), to: TestApp.date("2024-03-14T09:00"))
        await model.draftTaskEdited("clar")
        #expect(model.draftTaskField.escape(text: "clar"))
        await model.submitDraft()
        let halfPast = try TestApp.date("2024-03-14T08:30")
        let plain = try await world.test.store.entries(on: day).first { $0.start == halfPast }
        #expect(plain?.task == "clar" && plain?.projectID == nil)
    }
}
