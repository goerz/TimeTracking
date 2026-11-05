// The Projects section's own date range and the View commands on it
// (projects.md §2.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

extension ProjectsSectionTests {
    @Test("PP-8 in Projects the View commands move the section's own range, not the Reports range")
    func projectsRange() async throws {
        let test = try await TestApp()
        _ = try await test.projects(["Paper"])
        let sections = test.app.sections
        #expect(sections.projects.range.isAllTime)
        sections.select(.projects)
        // The menu items reach the section, not only the router.
        #expect(MenuState(sectionKey: true, section: .projects).periodCommands)
        #expect(!MenuState(sectionKey: false, section: .projects).periodCommands)
        #expect(!sections.canShiftPeriod)
        sections.projects.range.select(.thisWeek)
        let reportsRange = sections.range.range
        #expect(sections.canShiftPeriod)
        await sections.shiftPeriod(by: -1)
        #expect(sections.projects.range.range != .preset(.thisWeek))
        #expect(sections.range.range == reportsRange)
        #expect(sections.projects.table.rows.isEmpty)
        await sections.goToToday()
        #expect(sections.projects.range.range == .preset(.thisWeek))
        sections.showDateRange()
        #expect(sections.projects.showsDatePopover)
    }
}
