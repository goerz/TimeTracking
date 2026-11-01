// The Planner shell and the Projects section's view models
// (spec_planner_projects.md §1, §2, §3, §4).

import Foundation
import SwiftUI
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct PlannerProjectsTests {
    @Test("PP-1 ⌘2 to ⌘5 select Calendar, Reports, Projects, Activity; the section menu is named for the section")
    func sectionCommands() async throws {
        let test = try await TestApp()
        #expect(PlannerSection.allCases.map(\.mainWindowKey) == ["2", "3", "4", "5"])
        #expect(PlannerSection.allCases.map(\.title) == ["Calendar", "Reports", "Projects", "Activity"])
        #expect(PlannerSection.allCases.map(\.menuTitle) == ["Calendar", "Report", "Project", "Activity"])
        for section in PlannerSection.allCases {
            test.app.planner.select(section)
            #expect(test.app.planner.section == section)
        }
    }

    @Test("PP-2 the Planner reopens on the last section; nothing opens it at launch")
    func lastSection() async throws {
        let test = try await TestApp()
        test.app.planner.select(.reports)
        let again = PlannerRouter(store: test.store, clock: test.clock, device: test.app.settings.device)
        #expect(again.section == .reports)
        #expect(!test.app.plannerIsOpen)
        #expect(!test.router.calls.contains(.openPlanner))
    }

    @Test("PP-3 Include archived projects, grouping, and sort survive a relaunch; the search does not; defaults Client and Area, Name")
    func storedViewState() async throws {
        let test = try await TestApp()
        let fresh = test.app.planner.projects
        #expect(fresh.options.grouping == .clientAndArea)
        #expect(fresh.options.sort == .name && fresh.options.ascending)
        fresh.options.includeArchived = true
        fresh.options.grouping = .client
        fresh.options.sort(by: .lastTracked)
        fresh.options.sort(by: .lastTracked)
        fresh.search = "noise"
        let again = ProjectsModel(store: test.store, clock: test.clock, device: test.app.settings.device)
        #expect(again.options.includeArchived)
        #expect(again.options.grouping == .client)
        #expect(again.options.sort == .lastTracked && !again.options.ascending)
        #expect(again.search.isEmpty)
    }

    @Test("PP-10 archiving three projects removes them while archived ones are hidden; ⌘Z restores all three")
    func archiveAndUndo() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["A", "B", "C", "D"])
        let model = test.app.planner.projects
        model.undoManager = test.undo
        await model.reload()
        model.selection = Set(projects.prefix(3).map(\.id))
        await model.archiveSelection()
        #expect(model.table.rows.map(\.row.project.name) == ["D"])
        test.undo.undo()
        await model.waitForUndo()
        #expect(model.table.rows.map(\.row.project.name) == ["A", "B", "C", "D"])
    }

    @Test("PP-11 Delete… is disabled for a project with one entry, with the tooltip")
    func deleteRule() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Used", "Unused"])
        try await test.entry("Work", projects[0], from: "08:00", to: "09:00")
        let model = test.app.planner.projects
        await model.reload()
        model.selection = [projects[0].id]
        #expect(!model.canDelete)
        #expect(model.deleteTooltip == "Has 1 entry; archive it instead")
        model.selection = [projects[1].id]
        #expect(model.canDelete)
        model.requestDelete()
        #expect(model.confirmation?.title == "Delete “Unused”?")
        #expect(model.confirmation?.message == "This cannot be undone.")
        await model.confirm()
        #expect(model.rows.map(\.project.name) == ["Used"])
    }

    @Test(
        "PP-12 ⌘O on a project stops a running entry, starts one on it with an empty task, and shows no window; disabled when archived"
    )
    func startTimer() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Paper", "Old"])
        _ = try await test.store.start(projectID: nil, task: "Running", at: test.date("2024-03-14T09:00"))
        let model = test.app.planner.projects
        test.app.planner.select(.projects)
        await model.reload()
        model.selection = [projects[0].id]
        #expect(model.canStartTimer)
        #expect(test.app.planner.continueTarget == .project)
        await test.app.continueCommand(timerKey: false, plannerKey: true)
        let running = try #require(try await test.store.runningEntry())
        #expect(running.projectID == projects[0].id)
        #expect(running.task.isEmpty)
        #expect(try await test.store.entries(on: TrackingDay(year: 2024, month: 3, day: 14)).count == 2)
        #expect(test.router.calls.isEmpty)
        try await test.store.archive(projects[1].id)
        await model.reload()
        model.selection = [projects[1].id]
        #expect(!model.canStartTimer)
        #expect(test.app.planner.continueTarget == nil)
    }

    @Test("PP-13 Show in Reports selects Reports with the project as the only filter and All time")
    func showInReports() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Paper"])
        let model = test.app.planner.projects
        await model.reload()
        model.selection = [projects[0].id]
        await model.showInReports()
        let planner = test.app.planner
        #expect(planner.section == .reports)
        #expect(planner.range.range == .preset(.allTime))
        #expect(planner.reports.state.filters == ReportFilters(projects: [projects[0].id]))
        #expect(test.router.calls == [.openPlanner])
    }

    @Test("PP-14 a project URL for an archived project selects Projects, includes archived ones, All time, clears the search, selects it")
    func projectURL() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Old", "Current"])
        try await test.store.archive(projects[0].id)
        let model = test.app.planner.projects
        model.range.select(.today)
        await model.reload()
        model.search = "current"
        test.app.planner.select(.reports)
        let router = URLRouter(app: test.app, scheme: "timetracking-debug")
        let url = try #require(URL(string: "timetracking-debug://project/\(projects[0].id.rawValue)"))
        #expect(await router.open(url) == .shown)
        #expect(test.app.planner.section == .projects)
        #expect(model.options.includeArchived)
        #expect(model.range.isAllTime)
        #expect(model.search.isEmpty)
        #expect(model.selection == [projects[0].id])
        #expect(model.scrollTarget == projects[0].id)
        #expect(model.table.rows.contains { $0.id == projects[0].id })
    }

    @Test("PP-15 moving a project with entries to another client confirms first and reports follow; a move within the client is undoable")
    func moveProject() async throws {
        let test = try await TestApp(now: "2024-03-14T10:00")
        let projects = try await test.projects(["Paper"])
        try await test.entry("Old work", projects[0], from: "2023-05-02T09:00", to: "2023-05-02T10:00")
        let (teaching, _) = try await test.store.createClient(name: "Teaching")
        let dialog = ProjectDialogModel(store: test.store, mode: .edit(projects[0]))
        dialog.undoManager = test.undo
        await dialog.load()
        await dialog.select(client: teaching.id)
        #expect(await dialog.submit() == nil)
        #expect(dialog.confirmation?.title == "Move “Paper” and its 1 entry to Teaching?")
        #expect(dialog.confirmation?.message == "Reports for past dates will show them there.")
        #expect(await dialog.submit(confirmed: true) != nil)
        let lastYear = ReportRange.preset(.lastYear).days(today: TrackingDay(year: 2024, month: 3, day: 14), earliest: nil)
        let report = try await test.store.report(ReportQuery(days: lastYear, groupBy: [.client]))
        #expect(report.children.map(\.key) == [.client(teaching.id)])

        let moved = try #require(try await test.store.project(projects[0].id))
        let other = try await test.store.createArea(AreaDraft(clientID: teaching.id, name: "Lectures"))
        let within = ProjectDialogModel(store: test.store, mode: .edit(moved))
        let undo = UndoManager()
        within.undoManager = undo
        await within.load()
        within.areaID = other.id
        #expect(await within.submit() != nil)
        #expect(within.confirmation == nil)
        #expect(try await test.store.project(moved.id)?.areaID == other.id)
        undo.undo()
        await within.pendingUndo?.value
        #expect(try await test.store.project(moved.id)?.areaID == moved.areaID)
    }

    @Test("PP-19 restoring a project in a retired area asks first and reactivates the area; retired areas leave the dialog's Area popup")
    func restoreRetired() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Paper"])
        try await test.store.archive(projects[0].id)
        try await test.store.updateArea(projects[0].areaID, AreaChange(retired: true))
        let dialog = ProjectDialogModel(store: test.store, mode: .create)
        await dialog.load(preferredArea: projects[0].areaID)
        #expect(!dialog.areas.contains { $0.id == projects[0].areaID })
        let model = test.app.planner.projects
        await model.reload()
        model.options.includeArchived = true
        model.selection = [projects[0].id]
        await model.restoreSelection()
        #expect(model.confirmation?.title == "Restore and reactivate “Research”?")
        #expect(try await test.store.project(projects[0].id)?.isArchived == true)
        await model.confirm()
        #expect(try await test.store.project(projects[0].id)?.isArchived == false)
        let area = try await test.store.areas(of: nil, includeRetired: true).first { $0.id == projects[0].areaID }
        #expect(area?.isRetired == false)
    }

    @Test("PP-20 the client and area sheets prefill the default color; a Display P3 color is stored clamped as uppercase #RRGGBB")
    func sheetColors() async throws {
        let test = try await TestApp()
        let (client, general) = try await test.store.createClient(name: "Consulting")
        let expected = try AreaColor.defaultColor(existing: [AreaColor(general.color)]).hex
        let clientForm = await ClientFormModel.create(store: test.store)
        #expect(clientForm.color == expected)
        let areaForm = await AreaFormModel.create(store: test.store, client: client.id)
        #expect(areaForm.color == expected)
        #expect(Color(.displayP3, red: 1, green: 0, blue: 0).hexString == "#FF0000")
        #expect(Color(hex: "#1F3A93").hexString == "#1F3A93")
        areaForm.name = "Consulting"
        await areaForm.validate()
        #expect(areaForm.nameError == "This name is used by the client's general area")
        clientForm.name = "CONSULTING"
        await clientForm.validate()
        #expect(clientForm.nameError == "A client with this name already exists")
    }

    @Test("PP-18 a general area offers no Rename, Retire, Delete, or move, and its sheet keeps its name with the note")
    func generalAreaSheet() async throws {
        let test = try await TestApp()
        let (client, general) = try await test.store.createClient(name: "Consulting")
        _ = try await test.store.createArea(AreaDraft(clientID: client.id, name: "Research"))
        let model = test.app.planner.projects
        await model.reload()
        model.selectRows(["area:\(general.id.rawValue)"])
        let row = try #require(model.selectedAreaRow)
        #expect(!row.canRename && !row.canRetire && !row.canDelete && !row.canMoveUp && !row.canMoveDown)
        #expect(!model.canArchiveSelection && !model.canDeleteSelection)
        model.editSelection()
        let form = try #require(model.clientsAndAreas.areaForm)
        #expect(!form.nameEditable)
        #expect(form.nameNote == "Named after the client")
    }

    @Test func clientsAndAreasActions() async throws {
        let test = try await TestApp()
        let projects = try await test.projects(["Paper"])
        let areas = test.app.planner.projects.clientsAndAreas
        areas.undoManager = test.undo
        let research = try #require(try await test.store.areas(of: nil, includeRetired: true).first { $0.id == projects[0].areaID })
        let teaching = try await test.store.createArea(AreaDraft(clientID: research.clientID, name: "Teaching"))
        await areas.reload()
        await areas.move(teaching.id, by: -1)
        #expect(areas.outline[0].areas.map(\.area.name) == ["University", "Teaching", "Research"])
        test.undo.undo()
        await areas.waitForUndo()
        #expect(areas.outline[0].areas.map(\.area.name) == ["University", "Research", "Teaching"])
        areas.requestDelete(teaching.id)
        #expect(areas.confirmation?.title == "Delete “Teaching”?")
        await areas.confirm()
        #expect(areas.outline[0].areas.map(\.area.name) == ["University", "Research"])
        areas.requestRemove(research.clientID)
        #expect(areas.confirmation == nil)
    }
}
