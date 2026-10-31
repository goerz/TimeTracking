// The client and area rows of the projects table (spec_planner_projects.md
// §2.5, §4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct ProjectsRowsTests {
    @Test("PP-25 a client or area row is selected alone, and the Project menu, ↩, and Show in Reports act on it")
    func clientAndAreaRows() async throws {
        let test = try await TestApp()
        let paper = try #require(try await test.projects(["Paper"]).first)
        let model = test.app.planner.projects
        await model.reload()
        let area = try #require(model.areas.first { $0.id == paper.areaID })
        let areaRow = "area:\(area.id.rawValue)"
        let clientRow = "client:\(area.clientID.rawValue)"
        let projectRow = "project:\(paper.id.rawValue)"

        model.selectRows([areaRow])
        #expect(model.selectedRowIDs == [areaRow])
        #expect(model.editSelectionTitle == "Edit Area…")
        #expect(model.deleteSelectionTitle == "Delete Area…")
        #expect(model.archiveSelectionTitle == "Retire Area")
        #expect(model.dialogDefaultArea == area.id)
        await model.showSelectionInReports()
        #expect(test.app.planner.section == .reports)
        #expect(test.app.planner.reports.state.filters.areas == [area.id])

        model.selectRows([clientRow])
        #expect(model.editSelectionTitle == "Rename Client…")
        #expect(model.deleteSelectionTitle == "Remove Client…")
        #expect(model.clientForNewArea == area.clientID)
        model.editSelection()
        #expect(model.clientsAndAreas.clientForm != nil)

        model.selectRows([clientRow, areaRow, projectRow])
        #expect(model.selection == [paper.id])
        #expect(model.clientsAndAreas.selection == nil)
        #expect(model.editSelectionTitle == "Edit Project…")
        #expect(model.dialogDefaultArea == paper.areaID)
        model.clientsAndAreas.selection = .area(area.id)
        #expect(model.selection.isEmpty)

        model.newProject(in: .area(area.id))
        #expect(model.dialogDefaultArea == area.id)
        await model.dialogFinished(nil)
        #expect(model.newProjectArea == nil)
    }
}
