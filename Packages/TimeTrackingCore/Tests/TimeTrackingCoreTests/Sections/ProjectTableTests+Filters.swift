// The date range, the Filters popover's tree folding, and "Include
// archived projects" (spec_projects.md §2.4).

import Foundation
import Testing
import TimeTrackingCore

extension ProjectTableTests {
    @Test("PP-8 a date range lists only projects tracked in it, Total tracked over the range; All time lists every project")
    func dateRange() async throws {
        let world = try await World()
        try await world.project("Old", world.teaching, hours: 3, daysAgo: 91)
        try await world.project("Recent", world.teaching, hours: 2, daysAgo: 1)
        try await world.project("Unused", world.teaching)
        var options = ProjectTableOptions()
        options.grouping = .ungrouped
        let today = TrackingCalendar(timeZone: .current).day(containing: world.test.clock.now)
        let lastWeek = try await world.table(options, days: today.adding(days: -6) ... today)
        #expect(lastWeek.rows.map(\.row.project.name) == ["Recent"])
        #expect(lastWeek.rows.first?.row.totalSeconds == 2 * 3600)
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Old", "Recent", "Unused"])
        let year = try await world.table(options, days: today.adding(days: -364) ... today)
        #expect(year.rows.map(\.row.project.name) == ["Old", "Recent"])
        #expect(year.rows.first?.row.totalSeconds == 3 * 3600)
    }

    @Test("PP-27 areas with projects open folded unless partly checked; unfolding shows the projects; a search unfolds")
    func treeFolding() async throws {
        let world = try await World()
        let website = try await world.project("Website", world.consultingGeneral)
        try await world.project("Cloud", world.consultingGeneral)
        try await world.project("Audit", world.consultingResearch)
        try await world.project("Lectures", world.teaching)
        let tree = try await ProjectScopeTree(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true),
            projects: world.store.projects(filter: ProjectFilter(state: .all))
        )
        #expect(tree.hasChildren(.client(world.consulting.id)))
        #expect(tree.hasChildren(.area(world.teaching.id)))
        #expect(!tree.hasChildren(.area(world.universityResearch.id)))

        var collapsed = tree.initiallyCollapsed(in: ProjectScope())
        #expect(collapsed == [.area(world.consultingGeneral.id), .area(world.consultingResearch.id), .area(world.teaching.id)])
        #expect(tree.rows(matching: "", collapsed: collapsed).map(\.path) == [
            "Consulting", "Consulting", "Consulting · Research", "University", "University", "University · Teaching",
            "University · Research",
        ])
        collapsed.remove(.area(world.teaching.id))
        #expect(tree.rows(matching: "", collapsed: collapsed).map(\.name).contains("Lectures"))
        #expect(tree.rows(matching: "audit", collapsed: collapsed).map(\.name) == ["Consulting", "Research", "Audit"])

        // A partly checked area opens unfolded; a fully checked one folded.
        let partly = ProjectScope(projects: [website.id])
        #expect(!tree.initiallyCollapsed(in: partly).contains(.area(world.consultingGeneral.id)))
        let whole = ProjectScope(areas: [world.consultingGeneral.id])
        #expect(tree.initiallyCollapsed(in: whole).contains(.area(world.consultingGeneral.id)))

        // Without projects (the Projects section's tree) nothing is folded.
        let areasOnly = try await ProjectScopeTree(
            clients: world.store.clients(includeRetired: true),
            areas: world.store.areas(of: nil, includeRetired: true)
        )
        #expect(areasOnly.initiallyCollapsed(in: ProjectScope()).isEmpty)
    }

    @Test("PP-28 Include archived projects hides or shows archived ones, is not counted, and takes over a stored state selector")
    func includeArchived() async throws {
        let world = try await World()
        try await world.project("Website", world.consultingGeneral)
        let old = try await world.project("Old", world.consultingGeneral)
        try await world.store.archive(old.id)
        var options = ProjectTableOptions()
        options.grouping = .ungrouped
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Website"])
        options.includeArchived = true
        #expect(try await world.table(options).rows.map(\.row.project.name) == ["Old", "Website"])
        #expect(options.filterCount == 0)
        options.clearFilters()
        #expect(!options.includeArchived)

        let decoder = JSONDecoder()
        for (state, included) in [("active", false), ("archived", true), ("all", true)] {
            // As stored before "Include archived projects" replaced the state selector.
            let json = #"{"state":"\#(state)","clients":[],"areas":[],"lastTracked":"never","#
                + #""grouping":"client","sort":"last_tracked","ascending":false}"#
            let decoded = try decoder.decode(ProjectTableOptions.self, from: Data(json.utf8))
            #expect(decoded.includeArchived == included)
            #expect(decoded.grouping == .client)
            #expect(decoded.sort == .lastTracked)
            #expect(!decoded.ascending)
        }
        options.includeArchived = true
        let roundTrip = try decoder.decode(ProjectTableOptions.self, from: JSONEncoder().encode(options))
        #expect(roundTrip == options)
    }
}
