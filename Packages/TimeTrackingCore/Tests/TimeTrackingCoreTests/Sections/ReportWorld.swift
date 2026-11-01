// A small catalog with a week of entries for the Reports tests
// (spec_reports.md §10).

import Foundation
import Testing
import TimeTrackingCore

/// Consulting (general area) and University (general, Research, Teaching);
/// entries Monday to Thursday of 2026-W44 with one running at Thursday 10:00.
struct ReportWorld {
    let test: TestStore
    let consulting: Client
    let university: Client
    let research: Area
    let teaching: Area
    let consultingArea: Area
    let website: Project
    let noise: Project
    let grant: Project
    let lectures: Project
    let old: Project

    /// Thursday, October 29, 2026.
    static let today = TrackingDay(year: 2026, month: 10, day: 29)
    static let week = TrackingDay(year: 2026, month: 10, day: 26) ... TrackingDay(year: 2026, month: 11, day: 1)

    var store: TimeStore {
        test.store
    }

    init(wednesday: Bool = true) async throws {
        let test = try await TestStore(now: "2026-10-29T10:00")
        self.test = test
        let store = test.store
        (consulting, consultingArea) = try await store.createClient(name: "Consulting", generalAreaColor: "#D94A6A")
        (university, _) = try await store.createClient(name: "University", generalAreaColor: "#7A8090")
        self.research = try await store.createArea(AreaDraft(clientID: university.id, name: "Research", color: "#13A08F"))
        self.teaching = try await store.createArea(AreaDraft(clientID: university.id, name: "Teaching", color: "#E8892F"))
        self.website = try await store.createProject(ProjectDraft(areaID: consultingArea.id, name: "Website"))
        self.noise = try await store.createProject(ProjectDraft(areaID: research.id, name: "Noise Model"))
        self.grant = try await store.createProject(ProjectDraft(areaID: research.id, name: "Grant"))
        self.lectures = try await store.createProject(ProjectDraft(areaID: teaching.id, name: "Lectures"))
        self.old = try await store.createProject(ProjectDraft(areaID: teaching.id, name: "Old Course"))
        try await add(noise, "Clarify Noise Model", "2026-10-26T09:00", "2026-10-26T11:00")
        try await add(website, "Bugfixes", "2026-10-26T13:00", "2026-10-26T14:00")
        try await add(lectures, "Prepare lecture", "2026-10-27T09:00", "2026-10-27T10:30")
        try await add(nil, "Mail", "2026-10-27T11:00", "2026-10-27T11:20")
        if wednesday {
            try await add(old, "Große Aufgabe", "2026-10-28T09:00", "2026-10-28T09:30")
            try await add(grant, "Draft", "2026-10-28T10:00", "2026-10-28T11:00")
        }
        _ = try await store.start(projectID: noise.id, task: "Clarify noise model", at: test.date("2026-10-29T09:00"))
        try await store.archive(old.id)
    }

    func add(_ project: Project?, _ task: String, _ start: String, _ end: String) async throws {
        _ = try await store.create(EntryDraft(projectID: project?.id, task: task, start: test.date(start), end: test.date(end)))
    }

    func snapshot(
        _ days: ClosedRange<TrackingDay> = week,
        levels: [GroupKey] = [.area, .project, .task],
        granularity: Granularity? = nil,
        stack: StackKind = .area,
        filters: ReportFilters = ReportFilters(),
        search: String = "",
        path: [GroupKeyValue] = []
    ) async throws -> ReportSnapshot {
        try await store.reportSnapshot(ReportRequest(
            days: days,
            today: Self.today,
            levels: levels,
            granularity: granularity,
            stack: stack,
            filter: filters.entryFilter(search: search),
            entryPath: path
        ))
    }
}
