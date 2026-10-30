// Entry writes and reads (spec_data_and_sync.md §1.4, §1.7, §2.2, §7; §9 items 5, 9, 12, 13, 15, 16).

import Foundation
import Testing
import TimeTrackingCore

struct EntryWriteTests {
    @Test("DATA-5 a start while an entry runs stops it at the new start")
    func startStopsRunning() async throws {
        let test = try await TestStore()
        let first = try await test.store.start(projectID: nil, task: "One", at: test.date("2024-03-14T09:00"))
        let second = try await test.store.start(projectID: nil, task: "Two", at: test.date("2024-03-14T09:30"))
        #expect(try await test.store.entry(first.id)?.end == test.date("2024-03-14T09:30"))
        #expect(try await test.store.runningEntry()?.id == second.id)
        let stopped = try await test.store.stop(at: test.date("2024-03-14T09:45"))
        #expect(stopped?.id == second.id)
        #expect(try await test.store.runningEntry() == nil)
        let continued = try await test.store.continue(first.id, at: test.date("2024-03-14T09:50"))
        #expect(continued.task == "One")
        #expect(continued.isRunning)
    }

    @Test("DATA-9 writes after the device's current time fail with inFuture; end before start fails")
    func futureAndOrder() async throws {
        let test = try await TestStore()
        let store = test.store
        await #expect(throws: StoreError.inFuture) {
            try await store.create(EntryDraft(
                projectID: nil,
                task: "",
                start: test.date("2024-03-14T09:00"),
                end: test.date("2024-03-14T10:01")
            ))
        }
        await #expect(throws: StoreError.inFuture) {
            try await store.start(projectID: nil, task: "", at: test.date("2024-03-14T10:00:01"))
        }
        let entries = try await store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2024-03-14T09:00"),
            end: test.date("2024-03-14T09:30")
        ))
        await #expect(throws: StoreError.inFuture) {
            try await store.move(entries[0].id, by: 3600)
        }
        _ = try await store.start(projectID: nil, task: "now", at: test.date("2024-03-14T10:00"))
        await #expect(throws: StoreError.endBeforeStart) {
            try await store.create(EntryDraft(
                projectID: nil,
                task: "",
                start: test.date("2024-03-14T09:00"),
                end: test.date("2024-03-14T08:59")
            ))
        }
    }

    @Test("DATA-12 deleted entries vanish from reads, restore within 180 days, and expire after")
    func softDeletion() async throws {
        let test = try await TestStore()
        let store = test.store
        let day = TrackingDay(year: 2024, month: 3, day: 14)
        let entry = try await store.create(EntryDraft(
            projectID: nil,
            task: "x",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))[0]
        try await store.delete([entry.id])
        #expect(try await store.entries(on: day).isEmpty)
        #expect(try await store.entry(entry.id) == nil)
        let interval = try DateInterval(start: test.date("2024-03-14T00:00"), duration: 86_400)
        #expect(try await store.entries(in: interval, includeDeleted: true).map(\.id) == [entry.id])
        test.clock.advance(by: 179 * 86_400)
        try await store.restore([entry.id])
        #expect(try await store.entries(on: day).map(\.id) == [entry.id])
        try await store.delete([entry.id])
        test.clock.advance(by: 181 * 86_400)
        #expect(try await store.purgeExpiredTombstones() == 1)
        #expect(try await store.entries(in: interval, includeDeleted: true).isEmpty)
        await #expect(throws: StoreError.retentionExpired) {
            try await store.restore([entry.id])
        }
    }

    @Test("DATA-13 overlaps are accepted and reported")
    func overlaps() async throws {
        let test = try await TestStore()
        let store = test.store
        let first = try await store.create(EntryDraft(
            projectID: nil,
            task: "a",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))[0]
        let second = try await store.create(EntryDraft(
            projectID: nil,
            task: "b",
            start: test.date("2024-03-14T08:30"),
            end: test.date("2024-03-14T09:30")
        ))[0]
        _ = try await store.create(EntryDraft(
            projectID: nil,
            task: "c",
            start: test.date("2024-03-14T09:30"),
            end: test.date("2024-03-14T09:40")
        ))
        let draft = try EntryDraft(projectID: nil, task: "", start: test.date("2024-03-14T08:45"), end: test.date("2024-03-14T09:15"))
        #expect(try await Set(store.overlaps(for: draft, excluding: nil).map(\.id)) == [first.id, second.id])
        #expect(try await store.overlaps(for: draft, excluding: first.id).map(\.id) == [second.id])
        let pairs = try await store.overlappingEntries(in: DateInterval(start: test.date("2024-03-14T00:00"), duration: 86_400))
        #expect(pairs.map { [$0.0.id, $0.1.id] } == [[first.id, second.id]])
    }

    @Test("DATA-15 every write appends one outbox row per changed record and one notification; a failed write neither")
    func outboxAndNotification() async throws {
        let test = try await TestStore()
        let store = test.store
        let before = try await store.outboxCount()
        _ = try await store.createClient(name: "Client")
        #expect(try await store.outboxCount() == before + 2)
        #expect(test.notifier.postCount == 1)
        await #expect(throws: StoreError.duplicateName) {
            try await store.createClient(name: "client")
        }
        #expect(try await store.outboxCount() == before + 2)
        #expect(test.notifier.postCount == 1)
        _ = try await store.start(projectID: nil, task: "a", at: test.date("2024-03-14T09:00"))
        _ = try await store.start(projectID: nil, task: "b", at: test.date("2024-03-14T09:10"))
        // Each start also changes the LiveState record (§4.2).
        #expect(try await store.outboxCount() == before + 2 + (1 + 1) + (2 + 1))
        #expect(test.notifier.postCount == 3)
    }

    @Test("DATA-16 recentProjects returns the five projects with the latest starts, each once")
    func recentProjects() async throws {
        let test = try await TestStore()
        let projects = try await test.structure(projects: (1 ... 7).map { "P\($0)" }).projects
        var start = try test.date("2024-03-14T01:00")
        for project in projects + [projects[1], projects[0]] {
            _ = try await test.store.create(EntryDraft(projectID: project.id, task: "", start: start, end: start + 300))
            start += 600
        }
        let recent = try await test.store.recentProjects(limit: 5)
        #expect(recent == [projects[0], projects[1], projects[6], projects[5], projects[4]].map(\.id))
    }

    @Test func dayGroupsAndAutocompletion() async throws {
        let test = try await TestStore()
        let store = test.store
        let projects = try await test.structure(projects: ["P"]).projects
        _ = try await store.create(EntryDraft(
            projectID: projects[0].id,
            task: "Clarify noise model",
            start: test.date("2024-03-13T08:00"),
            end: test.date("2024-03-13T09:00")
        ))
        _ = try await store.create(EntryDraft(
            projectID: projects[0].id,
            task: "clarify noise model ",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T08:30")
        ))
        _ = try await store.create(EntryDraft(
            projectID: nil,
            task: "Email",
            start: test.date("2024-03-14T08:30"),
            end: test.date("2024-03-14T08:45")
        ))
        _ = try await store.start(projectID: nil, task: "Running", at: test.date("2024-03-14T09:50"))
        let days = try await store.days(ending: TrackingDay(year: 2024, month: 3, day: 14), count: 3)
        #expect(days.map(\.day.description) == ["2024-03-14", "2024-03-13", "2024-03-12"])
        #expect(days[0].totalSeconds == 1800 + 900 + 600)
        #expect(days[0].includesRunning)
        #expect(days[1].totalSeconds == 3600)
        #expect(days[2].entries.isEmpty)
        let tasks = try await store.distinctTasks(projectID: projects[0].id, prefix: "CLA", limit: 5)
        #expect(tasks.map(\.task) == ["clarify noise model"])
        #expect(tasks.first?.useCount == 2)
        #expect(try await store.distinctTasks(projectID: nil, prefix: "", limit: 5).map(\.task) == ["Running", "Email"])
        #expect(try await store.projectsByTask(matching: "noise", since: test.date("2024-01-01T00:00")) == [projects[0].id])
        #expect(try await store.lastStoppedEntry(excluding: nil)?.task == "Email")
        #expect(try await store.recentEntries(before: nil, limit: 2).map(\.task) == ["Running", "Email"])
        #expect(try await store.searchProjects("p", limit: 5).map(\.project.id) == [projects[0].id])
    }
}
