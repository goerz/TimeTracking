// The projects table, Clients & Areas outline, and area colors
// (spec_planner_projects.md §2, §4).

import Foundation
import Testing
import TimeTrackingCore

struct ProjectTableTests {
    /// Consulting (general, Research) and University (general, Teaching, Research).
    struct World {
        let test: TestStore
        let consulting: Client
        let university: Client
        let consultingGeneral: Area
        let consultingResearch: Area
        let teaching: Area
        let universityResearch: Area

        var store: TimeStore {
            test.store
        }

        init() async throws {
            self.test = try await TestStore(now: "2024-03-14T10:00")
            (self.consulting, self.consultingGeneral) = try await test.store.createClient(name: "Consulting")
            (self.university, _) = try await test.store.createClient(name: "University")
            self.consultingResearch = try await test.store.createArea(AreaDraft(clientID: consulting.id, name: "Research"))
            self.teaching = try await test.store.createArea(AreaDraft(clientID: university.id, name: "Teaching"))
            self.universityResearch = try await test.store.createArea(AreaDraft(clientID: university.id, name: "Research"))
        }

        @discardableResult
        func project(_ name: String, _ area: Area, hours: Int = 0, daysAgo: Int? = nil) async throws -> Project {
            let project = try await store.createProject(ProjectDraft(areaID: area.id, name: name))
            if let daysAgo {
                let start = test.clock.now.addingTimeInterval(-Double(daysAgo) * 86_400 - Double(max(hours, 1)) * 3600)
                _ = try await store.create(EntryDraft(
                    projectID: project.id,
                    task: "",
                    start: start,
                    end: start + Double(max(hours, 1)) * 3600
                ))
            }
            return project
        }

        func table(_ options: ProjectTableOptions = ProjectTableOptions(), search: String = "") async throws -> ProjectTable {
            let rows = try await store.projects(filter: ProjectFilter(state: .all))
            let areas = try await store.areas(of: nil, includeRetired: true)
            let clients = try await store.clients(includeRetired: true)
            return ProjectTable(rows: rows, clients: clients, areas: areas, options: options, search: search, now: test.clock.now)
        }
    }

    @Test("PP-5 Total tracked descending orders by duration, ties by name; Last tracked puts Never last both ways")
    func sorting() async throws {
        let world = try await World()
        try await world.project("Beta", world.teaching, hours: 2, daysAgo: 3)
        try await world.project("Alpha", world.teaching, hours: 2, daysAgo: 5)
        try await world.project("Gamma", world.teaching, hours: 5, daysAgo: 1)
        try await world.project("Delta", world.teaching)
        var options = ProjectTableOptions()
        options.grouping = .ungrouped
        options.sort = .totalTracked
        options.ascending = false
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Gamma", "Alpha", "Beta", "Delta"])
        options.sort(by: .lastTracked)
        #expect(options.ascending)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Alpha", "Beta", "Gamma", "Delta"])
        options.sort(by: .lastTracked)
        #expect(!options.ascending)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Gamma", "Beta", "Alpha", "Delta"])
        options.sort(by: .name)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Alpha", "Beta", "Delta", "Gamma"])
    }

    @Test("PP-6 Client and Area nests clients, areas, and projects, lists empty areas without a search, and sums totals")
    func grouping() async throws {
        let world = try await World()
        try await world.project("Website", world.consultingGeneral, hours: 1, daysAgo: 1)
        try await world.project("Audit", world.consultingResearch, hours: 2, daysAgo: 2)
        try await world.project("Lectures", world.teaching, hours: 3, daysAgo: 1)
        let retired = try await world.store.createArea(AreaDraft(clientID: world.university.id, name: "Old"))
        try await world.store.updateArea(retired.id, AreaChange(retired: true))
        #expect(ProjectTableOptions().grouping == .clientAndArea)

        // The outline: clients by name, areas in order (general first, shown
        // with the client's name), the empty University area and Research too.
        let outline = try await world.table()
        #expect(outline.groups.map(\.title) == ["Consulting", "University"])
        #expect(outline.groups[0].subgroups.map(\.title) == ["Consulting", "Research"])
        #expect(outline.groups[0].subgroups.map(\.tag) == ["general", nil])
        #expect(outline.groups[1].subgroups.map(\.title) == ["University", "Teaching", "Research"])
        #expect(outline.groups[1].subgroups.map(\.count) == [0, 1, 0])
        #expect(outline.groups[0].totalSeconds == 3 * 3600)
        #expect(outline.groups[0].subgroups[1].totalSeconds == 2 * 3600)
        #expect(outline.rows.map(\.row.project.name) == ["Website", "Audit", "Lectures"])
        #expect(outline.allGroups.count == 7)

        // The retired area only under "All"; a search or filter drops empty groups.
        var options = ProjectTableOptions()
        options.includeArchived = true
        #expect(try await world.table(options).groups[1].subgroups.map(\.title) == ["University", "Teaching", "Research", "Old"])
        #expect(try await world.table(options).groups[1].subgroups.last?.tag == "retired")
        let searched = try await world.table(search: "lect")
        #expect(searched.groups.map(\.title) == ["University"])
        #expect(searched.groups[0].subgroups.map(\.title) == ["Teaching"])

        // Reordering areas reorders their groups at once.
        let clients = try await ClientAreaOutline.build(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true),
            projects: world.store.projects(filter: ProjectFilter(state: .all))
        )
        let university = try #require(clients.first { $0.id == world.university.id })
        for (area, order) in ClientAreaOutline.move(university, area: world.universityResearch.id, by: -1) {
            try await world.store.updateArea(area, AreaChange(sortOrder: order))
        }
        #expect(try await world.table().groups[1].subgroups.map(\.title) == ["University", "Research", "Teaching"])

        // Group by Client: one header per client with its count and total.
        options = ProjectTableOptions()
        options.grouping = .client
        let byClient = try await world.table(options)
        #expect(byClient.groups.map(\.title) == ["Consulting · 2 projects", "University · 1 project"])
        for group in byClient.groups {
            #expect(group.totalSeconds == group.rows.reduce(0) { $0 + $1.row.totalSeconds })
        }
        #expect(byClient.groups[0].totalSeconds == 3 * 3600)
    }

    @Test("PP-7 a client checks its areas; unchecking one leaves the client mixed; the last child checks it again; search")
    func filters() async throws {
        let world = try await World()
        try await world.project("Website", world.consultingGeneral)
        try await world.project("Audit", world.consultingResearch)
        try await world.project("Lectures", world.teaching)
        try await world.project("Noise", world.universityResearch)
        let tree = try await ProjectScopeTree(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true)
        )
        var options = ProjectTableOptions()
        options.grouping = .ungrouped
        options.scope = tree.toggling(.client(world.consulting.id), in: options.scope)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Audit", "Website"])
        #expect(tree.state(of: .area(world.consultingResearch.id), in: options.scope) == .checked)
        options.scope = tree.toggling(.area(world.teaching.id), in: options.scope)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Audit", "Lectures", "Website"])
        #expect(tree.state(of: .client(world.university.id), in: options.scope) == .mixed)
        #expect(options.filterCount == 1)

        // Unchecking an area of a checked client keeps the client's others.
        options.scope = tree.toggling(.area(world.consultingResearch.id), in: options.scope)
        #expect(options.scope == ProjectScope(areas: [world.consultingGeneral.id, world.teaching.id]))
        #expect(tree.state(of: .client(world.consulting.id), in: options.scope) == .mixed)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Lectures", "Website"])
        options.scope = tree.toggling(.area(world.consultingResearch.id), in: options.scope)
        #expect(options.scope == ProjectScope(clients: [world.consulting.id], areas: [world.teaching.id]))

        // Same-named areas: the search tells them apart by their client.
        #expect(tree.rows(matching: "research university").map(\.path) == ["University", "University · Research"])
        #expect(tree.rows(matching: "consulting").map(\.path) == ["Consulting", "Consulting", "Consulting · Research"])

        options.lastTracked = .never
        #expect(options.filterCount == 2)
        options.clearFilters()
        #expect(options.filterCount == 0)
        #expect(try await world.table(options).rows.count == 4)
    }

    @Test("PP-8 Not in the last 90 days shows 91 days ago, hides 89 days ago and never; Never shows only the latter")
    func lastTracked() async throws {
        let world = try await World()
        try await world.project("Old", world.teaching, daysAgo: 91)
        try await world.project("Recent", world.teaching, daysAgo: 89)
        try await world.project("Unused", world.teaching)
        var options = ProjectTableOptions()
        options.lastTracked = .notLast90Days
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Old"])
        options.lastTracked = .never
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Unused"])
        options.lastTracked = .last90Days
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Recent"])
    }

    @Test("PP-9 every search word must match the project, area, or client name")
    func search() async throws {
        let world = try await World()
        try await world.project("Noise Model", world.consultingResearch)
        try await world.project("Noise Model", world.universityResearch)
        let table = try await world.table(search: "noise consulting")
        #expect(table.rows.map(\.row.client?.name) == ["Consulting"])
        #expect(try await world.table(search: "NOÏSE").rows.count == 2)
        #expect(try await world.table(search: "noise zzz").emptyText == "No projects match")
    }

    @Test func statusAndDates() async throws {
        let world = try await World()
        #expect(try await world.table().emptyText == "No projects yet")
        let archived = try await world.project("Old", world.teaching)
        try await world.project("New", world.teaching)
        try await world.store.archive(archived.id)
        let table = try await world.table()
        #expect(table.statusText == "1 project shown (1 active, 1 archived)")
        let calendar = TrackingCalendar(timeZone: world.test.zone)
        let now = world.test.clock.now
        #expect(ProjectTable.dateText(nil, now: now, calendar: calendar) == "Never")
        #expect(ProjectTable.dateText(now, now: now, calendar: calendar) == "Today")
        #expect(ProjectTable.dateText(now - 86_400, now: now, calendar: calendar) == "Yesterday")
        #expect(ProjectTable.dateText(now - 2 * 86_400, now: now, calendar: calendar) == "Tuesday")
        #expect(ProjectTable.dateText(now - 30 * 86_400, now: now, calendar: calendar) == "Feb 13")
        #expect(ProjectTable.dateText(now - 300 * 86_400, now: now, calendar: calendar) == "2023")
    }

    @Test("PP-18 a general area offers no Rename, Retire, or Delete and cannot move from first place")
    func generalArea() async throws {
        let world = try await World()
        let outline = try await ClientAreaOutline.build(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true),
            projects: []
        )
        let university = try #require(outline.first { $0.id == world.university.id })
        let general = try #require(university.areas.first)
        #expect(general.area.isGeneral)
        #expect(general.tag == "general")
        #expect(!general.canRename && !general.canRetire && !general.canDelete && !general.canMoveUp && !general.canMoveDown)
        #expect(ClientAreaOutline.reorder(university, moving: general.id, to: 1).isEmpty)
        #expect(ClientAreaOutline.reorder(university, moving: world.universityResearch.id, to: -5).map(\.0).first == world
            .universityResearch.id)
        #expect(!university.areas[1].canMoveUp)
        #expect(university.areas[2].canMoveUp && !university.areas[2].canMoveDown)
        await #expect(throws: StoreError.generalArea) {
            try await world.store.updateArea(general.id, AreaChange(sortOrder: 3))
        }
    }

    @Test("PP-19 Retire is disabled while the area has an active project and enabled after archiving it")
    func retireRule() async throws {
        let world = try await World()
        let project = try await world.project("Lectures", world.teaching, daysAgo: 1)
        func teaching() async throws -> AreaOutline {
            let outline = try await ClientAreaOutline.build(
                clients: world.store.clients(includeRetired: true),
                areas: world.store.areas(of: nil, includeRetired: true),
                projects: world.store.projects(filter: ProjectFilter(state: .all))
            )
            return try #require(outline.flatMap(\.areas).first { $0.id == world.teaching.id })
        }
        #expect(try await !teaching().canRetire)
        #expect(try await teaching().deleteTooltip == "Has 1 project")
        // The picker finds the area by name while it is active.
        func pickerAreas(_ search: String) async throws -> Set<AreaID> {
            let content = try await world.store.pickerContent(search: search, taskMatching: false)
            return Set((content.recent + content.groups.flatMap(\.rows)).map(\.area.id))
        }
        #expect(try await pickerAreas("Teaching").contains(world.teaching.id))
        try await world.store.archive(project.id)
        #expect(try await teaching().canRetire)
        #expect(try await teaching().countsText == "0 active · 1 archived")
        try await world.store.updateArea(world.teaching.id, AreaChange(retired: true))
        #expect(try await teaching().tag == "retired")
        // Retired: gone from the picker, searched or not, and from the Area popup's list.
        #expect(try await !pickerAreas("").contains(world.teaching.id))
        #expect(try await !pickerAreas("Teaching").contains(world.teaching.id))
        #expect(try await !world.store.areas(of: world.university.id, includeRetired: false).contains { $0.id == world.teaching.id })
        #expect(try await teaching().canUnretire)
        let client = try await #require(ClientAreaOutline.build(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true),
            projects: world.store.projects(filter: ProjectFilter(state: .all))
        ).first { $0.id == world.university.id })
        #expect(client.removeTooltip == "Has 2 areas and 1 project")
        #expect(client.countsText == "3 areas · 0 active · 1 archived")
    }

    @Test(
        "PP-20 PP-21 the default color rule; a wide-gamut color is clamped; text on #1F3A93 is white, on #F5D76E black"
    )
    func colors() throws {
        let wide = AreaColor(red: 1.09, green: -0.2, blue: 0.5)
        #expect(wide.hex == "#FF0080")
        #expect(try AreaColor("#1F3A93").textColor == .white)
        #expect(try AreaColor("#F5D76E").textColor == .black)
        #expect(AreaColor.defaultColor(existing: []).hsb.hue.rounded() == 210)
    }
}
