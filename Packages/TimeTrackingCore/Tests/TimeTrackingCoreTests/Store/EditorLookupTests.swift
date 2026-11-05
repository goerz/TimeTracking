// The lookups and rules the Timer, the entry editors, and the Calendar share
// (spec_timer.md §2, §4.2, §4.3; spec_ios.md §2.7;
// spec_calendar.md §2.6; spec_activity.md §1.3).

import Foundation
import Testing
import TimeTrackingCore

struct EditorLookupTests {
    @Test("TM-42 an editor's Start edit keeps a Stop another device stored after the editor read the entry")
    func editKeepsATimeChangedElsewhere() async throws {
        let test = try await TestStore()
        let created = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Model",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        let shown = created
        // Another device moves the end while the editor shows the entry.
        _ = try await test.store.update(shown.id, EntryChange(end: test.date("2024-03-14T09:30")))
        // Editing Start keeps the Stop the editor shows (§4.2).
        let edited = try EntryEditResult(start: test.date("2024-03-14T08:15"), end: shown.end)
        #expect(try edited.changeIfAny(from: shown) == EntryChange(start: test.date("2024-03-14T08:15")))
        #expect(EntryEditResult(start: shown.start, end: shown.end).changeIfAny(from: shown) == nil)
        _ = try await test.store.update(shown.id, edited.change(from: shown))
        let stored = try #require(try await test.store.entry(shown.id))
        #expect(try stored.start == test.date("2024-03-14T08:15"))
        #expect(try stored.end == test.date("2024-03-14T09:30"))
    }

    @Test("projectRow finds a live project, archived too, as projects(filter:) lists it; nil for a deleted one")
    func projectRowByID() async throws {
        let test = try await TestStore()
        let structure = try await test.structure(projects: ["Noise", "Paper"])
        let noise = structure.projects[0].id
        _ = try await test.store.create(EntryDraft(
            projectID: noise,
            task: "Model",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        let listed = try await test.store.projects(filter: ProjectFilter(state: .all)).first { $0.id == noise }
        let row = try #require(try await test.store.projectRow(noise))
        #expect(row == listed)
        #expect(row.area?.name == "Research")
        #expect(row.client?.id == structure.client.id)
        #expect(row.totalSeconds == 3600)
        let paper = structure.projects[1].id
        try await test.store.archive(paper)
        #expect(try await test.store.projectRow(paper)?.project.isArchived == true)
        try await test.store.deleteProject(paper)
        #expect(try await test.store.projectRow(paper) == nil)
        #expect(try await test.store.projectRow(ProjectID()) == nil)
    }

    @Test("projectListing keeps the names of a deleted project and its deleted area, as listings(for:) does")
    func projectListingWithTombstones() async throws {
        let test = try await TestStore()
        let structure = try await test.structure(projects: ["Noise"])
        let noise = structure.projects[0].id
        let entry = try await test.store.create(EntryDraft(
            projectID: noise,
            task: "Model",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        try await test.store.delete([entry.id])
        try await test.store.deleteProject(noise)
        try await test.store.deleteArea(structure.area.id)
        let found = try #require(try await test.store.projectListing(noise))
        let listing = try #require(try await test.store.listings(for: [entry]).first)
        #expect(found.project.name == "Noise")
        #expect(found.area?.name == "Research")
        #expect(found.client?.id == structure.client.id)
        #expect(found.project == listing.project)
        #expect(found.area == listing.area)
        #expect(found.client == listing.client)
        #expect(try await test.store.projectListing(ProjectID()) == nil)
    }

    @Test("A saved start and end: future first, then the order; a running end is not checked")
    func draftCheck() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        #expect(EntryEditRules.check(start: now + 60, end: now - 60, now: now) == .failure(.inFuture))
        #expect(EntryEditRules.check(start: now - 60, end: now + 1, now: now) == .failure(.inFuture))
        #expect(EntryEditRules.check(start: now - 60, end: now - 60, now: now) == .failure(.endBeforeStart))
        #expect(EntryEditRules.check(start: now - 60, end: now - 120, now: now) == .failure(.endBeforeStart))
        #expect(EntryEditRules.check(start: now - 60, end: nil, now: now) == .success(EntryEditResult(start: now - 60, end: nil)))
        #expect(EntryEditRules.check(start: now - 60, end: now, now: now) == .success(EntryEditResult(start: now - 60, end: now)))
    }

    @Test("assignContextColors adds new contexts, stores the setting, and keeps existing indexes")
    func contextColors() async throws {
        let test = try await TestStore()
        let first = try await test.store.assignContextColors(["safari", "tmux:(private)"])
        #expect(first == ["safari": 0])
        #expect(try await test.store.value(.activityContextColors) == first)
        let second = try await test.store.assignContextColors(["mail", "safari"])
        #expect(second == ["safari": 0, "mail": 1])
        #expect(try await test.store.value(.activityContextColors) == second)
    }

    @Test("OverlapAmount lists the entries overlapping by more than zero, in order, with the overlap")
    func overlapAmounts() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let entry = EntryID()
        let (early, late, touching) = (EntryID(), EntryID(), EntryID())
        let amounts = OverlapAmount.amounts(
            overlapping: DateInterval(start: base, end: base + 3600),
            of: entry,
            among: [
                (entry, DateInterval(start: base, end: base + 3600)),
                (touching, DateInterval(start: base + 3600, end: base + 4000)),
                (early, DateInterval(start: base - 600, end: base + 900)),
                (late, DateInterval(start: base + 3000, end: base + 7200)),
            ]
        )
        #expect(amounts == [OverlapAmount(id: early, seconds: 900), OverlapAmount(id: late, seconds: 600)])
    }
}
