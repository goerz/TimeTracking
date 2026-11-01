// Sleep and workouts mapped to an area in reports (spec_reports.md §1.1).

import Foundation
import Testing
import TimeTrackingCore

struct HealthReportTests {
    @Test("PR-23 sleep mapped to an area counts as its project Sleep, cut at midnight; not unmapped, with a task filter, or as entries")
    func sleepInReports() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let made = try await test.structure(projects: ["Paper"])
        let health = try await test.store.createArea(AreaDraft(clientID: made.client.id, name: "Health"))
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "Draft",
            start: test.date("2024-03-13T09:00"),
            end: test.date("2024-03-13T10:00")
        ))
        let night = try DateInterval(start: test.date("2024-03-12T23:00"), end: test.date("2024-03-13T06:30"))
        let run = try DateInterval(start: test.date("2024-03-13T18:00"), end: test.date("2024-03-13T18:45"))
        try await test.store.replaceHealthPeriods(.sleep, from: test.date("2024-03-01T00:00"), with: [night])
        try await test.store.replaceHealthPeriods(.workout, from: test.date("2024-03-01T00:00"), with: [run])
        let days = TrackingDay(year: 2024, month: 3, day: 13) ... TrackingDay(year: 2024, month: 3, day: 14)
        let byArea = ReportQuery(days: days, groupBy: [.area, .project], granularity: .day)
        // Shown but not mapped: entries only.
        try await test.store.set(.calendarShowSleep, true)
        #expect(try await test.store.report(byArea).seconds == 3600)
        // Mapped: the part after midnight on March 13 counts, under Health.
        try await test.store.set(.calendarSleepAreaID, health.id)
        let report = try await test.store.report(byArea)
        #expect(report.seconds == 3600 + 6 * 3600 + 1800)
        let area = try #require(report.children.first { $0.key == .area(health.id) })
        #expect(area.children.map(\.name) == ["Sleep"])
        #expect(area.children.first?.key == .project(HealthPeriod.Kind.sleep.reportProjectID))
        #expect(area.entryCount == 1)
        // Workouts mapped but not shown: not counted.
        try await test.store.set(.calendarWorkoutAreaID, health.id)
        #expect(try await test.store.report(byArea).seconds == report.seconds)
        // A task filter and the entry list leave health time out; the
        // search finds it by its project name.
        var filtered = byArea
        filtered.filter = EntryFilter(taskContains: "dra")
        #expect(try await test.store.report(filtered).seconds == 3600)
        #expect(try await test.store.entries(matching: byArea).map(\.task) == ["Draft"])
        var searched = byArea
        searched.filter.search = "sleep"
        #expect(try await test.store.report(searched).seconds == 6 * 3600 + 1800)
        // Turning Sleep off removes it again.
        try await test.store.set(.calendarShowSleep, false)
        #expect(try await test.store.report(byArea).seconds == 3600)
    }
}
