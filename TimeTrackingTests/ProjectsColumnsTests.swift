// The Projects table's columns (spec_projects.md §2.2).

import Foundation
import SwiftUI
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct ProjectsColumnsTests {
    @Test("PP-4 every column but Project stays hidden after a relaunch; State shows only with archived projects included")
    func columns() async throws {
        let test = try await TestApp()
        let model = test.app.sections.projects
        // Every column but Project, hidden from the header menu, stays hidden after a relaunch.
        let hideable = ["client", "area", "state", "created", "lastTracked", "totalTracked"]
        var customization = TableColumnCustomization<ProjectTableItem>()
        for column in hideable {
            customization[visibility: column] = .hidden
        }
        model.columnData = try JSONEncoder().encode(customization)
        let again = ProjectsModel(store: test.store, clock: test.clock, device: test.app.settings.device)
        let restored = try JSONDecoder().decode(TableColumnCustomization<ProjectTableItem>.self, from: again.columnData)
        for column in hideable {
            #expect(restored[visibility: column] == .hidden, "\(column)")
        }
        #expect(restored[visibility: "project"] == .automatic)
        // Showing one again persists too.
        customization[visibility: "area"] = .visible
        model.columnData = try JSONEncoder().encode(customization)
        let third = ProjectsModel(store: test.store, clock: test.clock, device: test.app.settings.device)
        let shown = try JSONDecoder().decode(TableColumnCustomization<ProjectTableItem>.self, from: third.columnData)
        #expect(shown[visibility: "area"] == .visible)
        #expect(shown[visibility: "client"] == .hidden)
        #expect(!model.showsStateColumn)
        model.options.includeArchived = true
        #expect(model.showsStateColumn)
        model.options.includeArchived = false
        #expect(!model.showsStateColumn)
    }
}
