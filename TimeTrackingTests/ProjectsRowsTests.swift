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

    @Test("PP-26 New Area… starts on the selected row's client or on none, Create waits for a client, and the name rule follows it")
    func newAreaClient() async throws {
        let test = try await TestApp()
        let (consulting, _) = try await test.store.createClient(name: "Consulting")
        let (university, _) = try await test.store.createClient(name: "University")
        _ = try await test.store.createArea(AreaDraft(clientID: university.id, name: "Research"))
        let model = test.app.planner.projects
        await model.reload()

        await model.clientsAndAreas.newArea(in: model.clientForNewArea)
        let empty = try #require(model.clientsAndAreas.areaForm)
        #expect(empty.clientID == nil && !empty.clientFixed)
        #expect(empty.clients.map(\.name) == ["Consulting", "University"])
        empty.name = "Research"
        await empty.validate()
        #expect(!empty.canSubmit)
        empty.clientID = university.id
        await empty.validate()
        #expect(empty.nameError == "An area with this name already exists for University")
        empty.clientID = consulting.id
        await empty.validate()
        #expect(empty.canSubmit)

        model.selectRows(["client:\(university.id.rawValue)"])
        await model.clientsAndAreas.newArea(in: model.clientForNewArea)
        #expect(model.clientsAndAreas.areaForm?.clientID == university.id)
        let fixed = await AreaFormModel.create(store: test.store, client: university.id, fixed: true)
        #expect(fixed.clientFixed)
        let research = try #require(model.areas.first { $0.name == "Research" })
        model.clientsAndAreas.editArea(research.id)
        #expect(model.clientsAndAreas.areaForm?.clientFixed == true)
        #expect(model.clientsAndAreas.areaForm?.clientID == university.id)
    }
}
