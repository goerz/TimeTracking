// A small store for the automation tests (spec_automation.md §9): now is
// 2026-10-29T10:00 in Europe/Berlin.

import Foundation
import Testing
import TimeTrackingCore

/// University (Research: Noise paper, Old paper archived; Teaching: Admin),
/// Side business (Admin), and a few entries.
struct AutomationTestStore {
    let test: TestStore
    let service: AutomationService
    let noisePaper: Project
    let oldPaper: Project
    let research: Area

    init(running: Bool = true) async throws {
        let test = try await TestStore(now: "2026-10-29T10:00", zone: "Europe/Berlin")
        self.test = test
        let store = test.store
        let (university, _) = try await store.createClient(name: "University")
        let research = try await store.createArea(AreaDraft(clientID: university.id, name: "Research", color: "#0A9396"))
        let teaching = try await store.createArea(AreaDraft(clientID: university.id, name: "Teaching", color: "#EE9B00"))
        let (_, sideGeneral) = try await store.createClient(name: "Side business")
        self.noisePaper = try await store.createProject(ProjectDraft(areaID: research.id, name: "Noise paper"))
        self.oldPaper = try await store.createProject(ProjectDraft(areaID: research.id, name: "Old paper"))
        _ = try await store.createProject(ProjectDraft(areaID: teaching.id, name: "Admin"))
        _ = try await store.createProject(ProjectDraft(areaID: sideGeneral.id, name: "Admin"))
        self.research = research
        _ = try await store.create(EntryDraft(
            projectID: noisePaper.id,
            task: "Draft intro",
            start: test.date("2026-10-20T09:00"),
            end: test.date("2026-10-20T11:00")
        ))
        _ = try await store.create(EntryDraft(
            projectID: noisePaper.id,
            task: "Bugfixes",
            start: test.date("2026-10-21T09:00"),
            end: test.date("2026-10-21T10:00")
        ))
        _ = try await store.create(EntryDraft(
            projectID: oldPaper.id,
            task: "Bugfixes",
            start: test.date("2026-10-22T09:00"),
            end: test.date("2026-10-22T10:00")
        ))
        _ = try await store.create(EntryDraft(
            projectID: nil,
            task: "Misc",
            start: test.date("2026-10-23T09:00"),
            end: test.date("2026-10-23T09:30")
        ))
        try await store.archive(oldPaper.id)
        if running {
            _ = try await store.start(projectID: noisePaper.id, task: "Review", at: test.date("2026-10-29T09:29:48"))
        }
        self.service = AutomationService(store: store, timeZone: test.zone)
    }

    func date(_ text: String) throws -> Date {
        try test.date(text)
    }
}
