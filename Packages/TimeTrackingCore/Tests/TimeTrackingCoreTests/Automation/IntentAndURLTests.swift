// App Intents, the URL scheme, and the change signal the menu bar follows
// (spec_automation.md §5, §6, §9 items 38 to 40). What only Shortcuts,
// Siri, or a running app can show is listed in the ledger.

import Foundation
import Testing
import TimeTrackingCore

struct IntentAndURLTests {
    @Test(
        "AUTO-39 StopTimer with nothing running returns nil; StartTimer refuses an archived project; only inferProject infers"
    )
    func intentActions() async throws {
        let idle = try await AutomationTestStore(running: false)
        let stop = try await IntentActions.stop(service: idle.service)
        #expect(stop.value == nil)
        #expect(stop.dialog == "Nothing is running.")
        await #expect(throws: AutomationError.refused("Project \"Old paper\" is archived; unarchive it first.")) {
            try await IntentActions.start(task: "X", project: idle.oldPaper.id, inferProject: false, service: idle.service)
        }
        let literal = try await IntentActions.start(task: "Draft intro", project: nil, inferProject: false, service: idle.service)
        #expect(literal.value.project == nil)
        #expect(literal.dialog == "Started Draft intro.")
        let inferred = try await IntentActions.start(task: "  draft INTRO ", project: nil, inferProject: true, service: idle.service)
        #expect(inferred.value.project == "Noise paper")
        #expect(inferred.dialog == "Started draft INTRO on Noise paper.")
        // The latest "Bugfixes" is on the archived Old paper: the inference skips it.
        let skipped = try await IntentActions.start(task: "Bugfixes", project: nil, inferProject: true, service: idle.service)
        #expect(skipped.value.project == "Noise paper")
        let unknown = try await IntentActions.start(task: "Never seen", project: nil, inferProject: true, service: idle.service)
        #expect(unknown.value.project == nil)
        let stopped = try await IntentActions.stop(service: idle.service)
        #expect(stopped.value?.running == false)
        #expect(stopped.dialog == "Stopped Never seen after 0 minutes.")
        #expect(AutomationError.refused("No entry running.").localizedStringResource.key.isEmpty == false)
    }

    @Test("AUTO-39 the other intents: continue, current entry, today's total, entries, create project, and the entity queries")
    func otherIntents() async throws {
        let fixture = try await AutomationTestStore()
        let current = try await IntentActions.current(service: fixture.service)
        #expect(current.value?.task == "Review")
        #expect(current.value?.duration == 1812)
        let total = try await IntentActions.total(on: nil, service: fixture.service)
        #expect(total.value == 1812)
        #expect(total.dialog == "30 minutes today")
        #expect(IntentText.duration(4 * 3600 + 120) == "4 hours 2 minutes")
        let continued = try await IntentActions.continue(project: nil, service: fixture.service)
        #expect(continued.value.task == "Misc")
        let entries = try await IntentActions.entries(
            from: fixture.date("2026-10-20T00:00"),
            to: fixture.date("2026-10-22T00:00"),
            project: nil,
            client: nil,
            service: fixture.service
        )
        #expect(entries.value.map(\.task) == ["Draft intro", "Bugfixes"])
        let area = fixture.research.id
        let created = try await IntentActions.createProject(name: "Grant renewal", area: area, service: fixture.service)
        #expect(created.value.name == "Grant renewal")
        #expect(created.value.client == "University")
        await #expect(throws: AutomationError.refused("That name is already taken.")) {
            try await IntentActions.createProject(name: "noise paper", area: area, service: fixture.service)
        }
        let rows = try await fixture.service.projects(state: .all)
        #expect(ProjectEntityQuery.matching("pap", in: rows).map(\.project.name) == ["Noise paper"])
        #expect(ProjectEntityQuery.matching("", in: rows).first?.project.name == "Noise paper")
        let suggestsArchived = ProjectEntityQuery.suggested(rows).contains(where: \.project.isArchived)
        #expect(!suggestsArchived)
        let archived = ProjectEntityQuery.filter(rows, [.state(.archived)], all: true)
        #expect(archived.map(\.project.name) == ["Old paper"])
        #expect(ProjectEntityQuery.filter(rows, [.client("side business")], all: true).map(\.project.name) == ["Admin"])
        let entity = try ProjectEntity(#require(rows.first { $0.project.name == "Noise paper" }))
        #expect(entity.areaColor == "#0A9396")
        #expect(entity.state == .active)
    }

    @Test("AUTO-38 the URL scheme parses start, stop, continue, show, and planner URLs; others are unknown; long values are rejected")
    func urlParsing() throws {
        func parse(_ text: String) throws(TimeTrackingURLError) -> TimeTrackingURL {
            try TimeTrackingURL(URL(string: text) ?? URL(filePath: "/"), scheme: "timetracking-debug")
        }
        #expect(try parse("timetracking-debug://start?project=Noise%20paper&task=Hello") == .start(
            project: .name("Noise paper"),
            task: "Hello"
        ))
        #expect(try parse("timetracking-debug://start") == .start(project: nil, task: ""))
        let id = ProjectID()
        #expect(try parse("timetracking-debug://start?project_id=\(id.rawValue)") == .start(project: .id(id), task: ""))
        #expect(try parse("timetracking-debug://stop") == .stop)
        #expect(try parse("timetracking-debug://continue") == .continue)
        #expect(try parse("timetracking-debug://show") == .show)
        #expect(try parse("timetracking-debug://planner/calendar?date=2026-10-29") == .calendar(date: TrackingDay(
            year: 2026,
            month: 10,
            day: 29
        )))
        #expect(try parse("timetracking-debug://planner/reports?from=2026-10-19&to=2026-10-26")
            == .reports(from: TrackingDay(year: 2026, month: 10, day: 19), to: TrackingDay(year: 2026, month: 10, day: 26)))
        #expect(try parse("timetracking-debug://planner/projects") == .projects)
        #expect(try parse("timetracking-debug://planner/activity") == .activity(date: nil))
        #expect(try parse("timetracking-debug://project/\(id.rawValue)") == .project(id))
        #expect(throws: TimeTrackingURLError.unknown) {
            try parse("timetracking-debug://delete")
        }
        #expect(TimeTrackingURLError.unknown.localizedDescription == "Unknown TimeTracking URL")
        #expect(throws: TimeTrackingURLError.unknown) {
            try parse("timetracking://stop")
        }
        #expect(throws: TimeTrackingURLError.tooLong) {
            try parse("timetracking-debug://start?task=" + String(repeating: "a", count: 1001))
        }
        #expect(try parse("timetracking-debug://stop").tracks)
        #expect(try !parse("timetracking-debug://show").tracks)
    }

    @Test(
        "AUTO-38 a start URL starts the named project; an unknown, archived, or ambiguous name starts nothing; URLs never create projects"
    )
    func urlActions() async throws {
        let fixture = try await AutomationTestStore(running: false)
        let service = fixture.service
        let banner = try await service.perform(.start(project: .name("Noise paper"), task: "Hello"))
        #expect(banner == "Started Noise paper")
        #expect(try await service.store.runningEntry()?.task == "Hello")
        let projects = try await service.projects(state: .all).count
        for name in ["Nonexistent", "Old paper", "Admin"] {
            await #expect(throws: AutomationError.self) {
                try await service.perform(.start(project: .name(name), task: "No"))
            }
        }
        #expect(try await service.store.runningEntry()?.task == "Hello")
        #expect(try await service.projects(state: .all).count == projects)
        #expect(try await service.perform(.stop) == "Stopped Hello on Noise paper")
        #expect(try await service.perform(.continue) == "Started Hello on Noise paper.")
        #expect(try await service.perform(.show) == nil)
    }

    @Test("AUTO-40 a write by another process reaches an observing store's changes within a second")
    func crossProcessChange() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "auto40-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store.sqlite")
        let name = "auto40.\(UUID().uuidString).changed"
        let clock = ManualClock(Date(timeIntervalSince1970: 1_800_000_000))
        func open() async throws -> TimeStore {
            try await TimeStore.open(TimeStore.Configuration(
                location: .file(url),
                clock: clock,
                deviceID: DeviceID(),
                notifier: DarwinChangeNotifier(name: name)
            ))
        }
        let app = try await open()
        let tool = try await open()
        let changes = app.changes
        let received = Task {
            for await change in changes {
                if case let .runningEntry(entry) = change, entry != nil {
                    return true
                }
            }
            return false
        }
        let started = ContinuousClock.now
        _ = try await tool.start(projectID: nil, task: "From the tool", at: clock.now)
        let timeout = Task {
            try await Task.sleep(for: .seconds(1))
            received.cancel()
        }
        let value = await received.value
        timeout.cancel()
        #expect(value)
        #expect(ContinuousClock.now - started < .seconds(1))
        await app.close()
        await tool.close()
    }
}
