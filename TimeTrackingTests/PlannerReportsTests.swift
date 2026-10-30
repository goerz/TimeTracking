// The Reports section's view model: shared range, drill-down, levels,
// entry list, commands, refresh, and the router request
// (spec_planner_reports.md §2, §4.5, §5, §6, §8, §9).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct PlannerReportsTests {
    /// Entries Monday to Wednesday of 2024-W11 and one running since 09:00 Thursday.
    private func week(_ test: TestApp) async throws -> [Project] {
        let projects = try await test.projects(["Paper", "Grant"])
        try await test.entry("Clarify noise model", projects[0], from: "2024-03-11T09:00", to: "2024-03-11T11:00")
        try await test.entry("Draft", projects[1], from: "2024-03-12T09:00", to: "2024-03-12T10:00")
        try await test.entry("Mail", nil, from: "2024-03-13T09:00", to: "2024-03-13T09:30")
        _ = try await test.store.start(projectID: projects[0].id, task: "Clarify noise model", at: test.date("2024-03-14T09:00"))
        return projects
    }

    @Test("PR-10 the range is one state for Reports and Activity")
    func sharedRange() async throws {
        let test = try await TestApp()
        let planner = test.app.planner
        #expect(planner.reports.range === planner.range)
        await planner.reports.previousPeriod()
        #expect(planner.range.days == TrackingDay(year: 2024, month: 3, day: 4) ... TrackingDay(year: 2024, month: 3, day: 10))
        planner.showActivity(range: .preset(.lastMonth))
        #expect(planner.section == .activity)
        #expect(planner.reports.range.label == "Last month · February 2024")
        let again = PlannerRouter(store: test.store, clock: test.clock, device: test.app.settings.device)
        #expect(again.range.range == .preset(.lastMonth))
    }

    @Test("PR-11 double-clicking a day bar makes it the range; ⌘[ restores the previous range once")
    func drillDown() async throws {
        let test = try await TestApp()
        _ = try await week(test)
        let reports = test.app.planner.reports
        await reports.reload()
        let tuesday = try #require(reports.snapshot?.chart.buckets[1])
        await reports.drillDown(tuesday)
        #expect(reports.range.days == TrackingDay(year: 2024, month: 3, day: 12) ... TrackingDay(year: 2024, month: 3, day: 12))
        #expect(reports.snapshot?.summary.loggedSeconds == 3600)
        await reports.backToPreviousRange()
        #expect(reports.range.range == .preset(.thisWeek))
        await reports.backToPreviousRange()
        #expect(reports.range.range == .preset(.thisWeek))
        #expect(reports.previousRange == nil)
    }

    @Test("PR-15 the level chain offers unused kinds, holds at most four levels, and a change resets expansion")
    func levels() async throws {
        let test = try await TestApp()
        _ = try await week(test)
        let reports = test.app.planner.reports
        await reports.reload()
        #expect(reports.state.levels == [.area, .project, .task])
        #expect(reports.availableKinds(at: 0) == [.client, .area, .day])
        reports.expandAll()
        #expect(!reports.expanded.isEmpty)
        await reports.addLevel()
        #expect(reports.state.levels == [.area, .project, .task, .client])
        #expect(reports.expanded.isEmpty)
        #expect(!reports.canAddLevel)
        await reports.addLevel()
        #expect(reports.state.levels.count == 4)
        await reports.setLevel(1, to: .task)
        #expect(reports.state.levels == [.area, .project, .task, .client])
        await reports.removeLevel(0)
        #expect(reports.state.levels.count == 4)
        await reports.removeLevel(3)
        await reports.setLevel(2, to: .day)
        #expect(reports.state.levels == [.area, .project, .day])
    }

    @Test("PR-16 double-clicking a node shows the entry list filtered to its key path with a chip; Escape removes it")
    func openNode() async throws {
        let test = try await TestApp()
        let projects = try await week(test)
        let reports = test.app.planner.reports
        await reports.reload()
        let research = try #require(reports.snapshot?.tree.children.first { $0.name == "Research" })
        let path: [GroupKeyValue] = [research.key, .project(projects[0].id)]
        await reports.openNode(path)
        #expect(reports.state.card == .entries)
        #expect(reports.pathChipText == "Research › Paper")
        #expect(reports.listings.count == 2)
        await reports.clearEntryPath()
        #expect(reports.pathChipText == nil)
        #expect(reports.listings.count == 4)
    }

    @Test("PR-18 an entry opens the edit popover; a saved edit updates tiles; the menu's Continue and Show in Calendar act")
    func entryActions() async throws {
        let test = try await TestApp()
        _ = try await week(test)
        let reports = test.app.planner.reports
        await reports.show(.entries)
        await reports.reload()
        let draft = try #require(reports.listings.first { $0.entry.task == "Draft" })
        reports.edit(draft.id)
        #expect(reports.editing == draft.id)
        let before = try #require(reports.snapshot?.summary.loggedSeconds)
        let editor = EntryEditorModel(store: test.store, clock: test.clock, entry: draft.entry)
        editor.onChange = { await reports.editorChanged() }
        await editor.load()
        editor.durationText = "2:00"
        let tuesdayBefore = try #require(reports.snapshot?.chart.buckets[1].total)
        let grantBefore = try #require(reports.breakdownRows.first { $0.node.name == "Research" }?.node.seconds)
        await editor.commitDuration()
        // Tiles, chart, and table all follow the saved edit.
        #expect(reports.snapshot?.summary.loggedSeconds == before + 3600)
        #expect(reports.snapshot?.chart.buckets[1].total == tuesdayBefore + 3600)
        #expect(reports.breakdownRows.first { $0.node.name == "Research" }?.node.seconds == grantBefore + 3600)
        #expect(reports.listings.first { $0.id == draft.id }?.entry.end == draft.entry.start + 7200)
        await reports.continueListing(draft.id)
        #expect(test.app.timer.running?.task == "Draft")
        reports.showInCalendar(draft)
        #expect(test.app.planner.section == .calendar)
        #expect(test.app.planner.calendarRequest == CalendarRequest(day: draft.entry.day, hour: nil, highlight: nil))
    }

    @Test("PR-20 Report commands exist only while Reports is active in the key Planner; ⌃⌘1 and ⌃⌘2 switch the card, not the section")
    func reportCommands() async throws {
        let test = try await TestApp()
        #expect(PlannerMenuState(plannerKey: true, section: .reports, showsClientsAndAreas: false).reportCommands)
        #expect(!PlannerMenuState(plannerKey: false, section: .reports, showsClientsAndAreas: false).reportCommands)
        #expect(!PlannerMenuState(plannerKey: true, section: .projects, showsClientsAndAreas: false).reportCommands)
        let planner = test.app.planner
        planner.select(.reports)
        await planner.reports.show(.entries)
        #expect(planner.reports.state.card == .entries)
        await planner.reports.show(.breakdown)
        #expect(planner.reports.state.card == .breakdown)
        #expect(planner.section == .reports)
    }

    @Test("PR-21 with the running entry in the range the tiles refresh every 60 s; without one no timer runs")
    func refresh() async throws {
        let test = try await TestApp()
        _ = try await week(test)
        let reports = test.app.planner.reports
        await reports.reload()
        #expect(reports.refreshInterval == .seconds(60))
        let before = try #require(reports.snapshot?.summary.loggedSeconds)
        test.clock.advance(by: 60)
        await reports.reload()
        #expect(reports.snapshot?.summary.loggedSeconds == before + 60)
        await reports.previousPeriod()
        #expect(reports.refreshInterval == nil)
        #expect(!reports.listTicks)
    }

    @Test("PR-22 showReports with a project and All time sets exactly that filter, includes archived projects, and shows the Breakdown")
    func showReports() async throws {
        let test = try await TestApp()
        let projects = try await week(test)
        let planner = test.app.planner
        await planner.reports.setFilters(ReportFilters(task: "noise", includeArchived: false))
        await planner.reports.show(.entries)
        await planner.showReports(range: .preset(.allTime), filter: .project(projects[1].id))
        #expect(planner.section == .reports)
        #expect(planner.reports.state.filters == ReportFilters(projects: [projects[1].id]))
        #expect(planner.reports.state.filters.includeArchived)
        #expect(planner.reports.state.card == .breakdown)
        #expect(planner.range.range == .preset(.allTime))
        #expect(planner.reports.snapshot?.summary.loggedSeconds == 3600)
    }

    @Test("PR-5 an archived project's breakdown row reads (archived); excluding archived projects removes it and its time")
    func archivedRow() async throws {
        let test = try await TestApp()
        let projects = try await week(test)
        try await test.store.archive(projects[1].id)
        let reports = test.app.planner.reports
        await reports.reload()
        reports.expandAll()
        let grant = try #require(reports.breakdownRows.first { $0.node.key == .project(projects[1].id) })
        #expect(grant.title == "Grant (archived)")
        let paper = try #require(reports.breakdownRows.first { $0.node.key == .project(projects[0].id) })
        #expect(!paper.title.contains("archived"))
        let before = try #require(reports.snapshot?.summary.loggedSeconds)
        await reports.setFilters(ReportFilters(includeArchived: false))
        reports.expandAll()
        #expect(!reports.breakdownRows.contains { $0.node.key == .project(projects[1].id) })
        #expect(reports.snapshot?.summary.loggedSeconds == before - 3600)
        #expect(!reports.breakdownCSV.contains("Grant"))
    }

    @Test("PR-19 both Reports CSV exports are byte-identical to the bundled tool's output for the same range, filters, and levels")
    func csvMatchesTool() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pr19-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let test = try await TestApp(storeFile: url)
        _ = try await week(test)
        let university = try #require(try await test.store.clients(includeRetired: false).first { $0.name == "University" })
        let reports = test.app.planner.reports
        await reports.setFilters(ReportFilters(clients: [university.id], task: "a"))
        await reports.reload()
        #expect(reports.state.levels == [.area, .project, .task])
        let week = ["--from", "2024-03-11", "--to", "2024-03-18"]
        let breakdown = try HelperTool.run(
            ["report", "--csv"] + week + ["--group-by", "area,project,task", "--client", "University", "--task", "a"],
            store: url,
            now: test.clock.now
        )
        #expect(breakdown.status == 0, "\(breakdown.error)")
        #expect(breakdown.output.hasPrefix("area,project,task,seconds,duration,share,entries\n"))
        #expect(breakdown.output == reports.breakdownCSV)
        // The tool's Entries CSV has no filters: compare with the unfiltered Reports export.
        await reports.setFilters(ReportFilters())
        await reports.reload()
        let entries = try HelperTool.run(["export", "--format", "csv"] + week, store: url, now: test.clock.now)
        #expect(entries.status == 0, "\(entries.error)")
        #expect(entries.output.split(separator: "\n").count == 5)
        #expect(entries.output == reports.entriesCSV)
        await test.store.close()
    }

    @Test func exportsAndNames() async throws {
        let test = try await TestApp()
        _ = try await week(test)
        let reports = test.app.planner.reports
        await reports.reload()
        #expect(reports.exportFileName(entries: false) == "Report 2024-03-11 to 2024-03-17.csv")
        #expect(reports.exportFileName(entries: true) == "Entries 2024-03-11 to 2024-03-17.csv")
        let tool = try await ReportCSVWriter.breakdownCSV(test.store.report(reports.request.query), levels: reports.state.levels)
        #expect(reports.breakdownCSV == tool)
        #expect(reports.entriesCSV.split(separator: "\n").count == 5)
        #expect(reports.listFooter(at: test.clock.now) == "Total 4h 30m 0s · 4 entries")
    }
}
