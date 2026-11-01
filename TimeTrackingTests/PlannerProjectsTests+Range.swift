// The Projects section's own date range and the View commands on it
// (spec_planner_projects.md §2.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension PlannerProjectsTests {
    @Test("PP-8 in Projects the View commands move the section's own range, not the Reports range")
    func projectsRange() async throws {
        let test = try await TestApp()
        _ = try await test.projects(["Paper"])
        let planner = test.app.planner
        #expect(planner.projects.range.isAllTime)
        planner.select(.projects)
        #expect(!planner.canShiftPeriod)
        planner.projects.range.select(.thisWeek)
        let reportsRange = planner.range.range
        #expect(planner.canShiftPeriod)
        await planner.shiftPeriod(by: -1)
        #expect(planner.projects.range.range != .preset(.thisWeek))
        #expect(planner.range.range == reportsRange)
        #expect(planner.projects.table.rows.isEmpty)
        await planner.goToToday()
        #expect(planner.projects.range.range == .preset(.thisWeek))
        planner.showDateRange()
        #expect(planner.projects.showsDatePopover)
    }
}
