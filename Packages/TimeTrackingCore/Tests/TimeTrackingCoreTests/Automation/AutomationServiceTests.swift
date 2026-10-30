// The library side of the tool: ranges, names, refusals, report, check
// (spec_automation.md §3, §4, §9).

import Foundation
import Testing
import TimeTrackingCore

struct AutomationServiceTests {
    private let calendar = TrackingCalendar(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .gmt)

    private func now() throws -> Date {
        try TestStore.date("2026-10-29T10:00", calendar.timeZone)
    }

    private func range(_ text: String) throws -> DayRange? {
        if case let .period(range) = try DateArgument.parse(text, now: now(), calendar: calendar) {
            return range
        }
        return nil
    }

    @Test("AUTO-7 date words, weeks, months, and relative dates resolve against now; days run Monday to Sunday")
    func dateArguments() throws {
        let day = { (text: String) in TrackingDay(text) ?? TrackingDay(year: 1, month: 1, day: 1) }
        #expect(try range("today") == DayRange(from: day("2026-10-29"), to: day("2026-10-30")))
        #expect(try range("yesterday")?.from == day("2026-10-28"))
        #expect(try range("week") == DayRange(from: day("2026-10-26"), to: day("2026-11-02")))
        #expect(try range("last-week")?.from == day("2026-10-19"))
        #expect(try range("month") == DayRange(from: day("2026-10-01"), to: day("2026-11-01")))
        #expect(try range("last-month") == DayRange(from: day("2026-09-01"), to: day("2026-10-01")))
        #expect(try range("year") == DayRange(from: day("2026-01-01"), to: day("2027-01-01")))
        #expect(try range("2026-W44") == DayRange(from: day("2026-10-26"), to: day("2026-11-02")))
        #expect(try range("2026-W01")?.from == day("2025-12-29"))
        #expect(try range("2026-10") == DayRange(from: day("2026-10-01"), to: day("2026-11-01")))
        #expect(try range("-3d")?.from == day("2026-10-26"))
        #expect(try range("-2w")?.from == day("2026-10-12"))
        #expect(try range("-1m")?.from == day("2026-09-01"))
        let instant = try DateArgument.parse("2026-10-29T09:15", now: now(), calendar: calendar)
        #expect(try instant == .instant(TestStore.date("2026-10-29T09:15", calendar.timeZone)))
        let offset = try DateArgument.parse("2026-10-29T09:15+00:00", now: now(), calendar: calendar)
        #expect(try offset.instant(in: calendar) == Date.ISO8601FormatStyle().parse("2026-10-29T09:15:00Z"))
        for bad in ["2026-13-01", "2026-W60", "tomorrowish", "2026-10-32", "-3x"] {
            #expect(throws: AutomationError.self) {
                try DateArgument.parse(bad, now: now(), calendar: calendar)
            }
        }
    }

    @Test("AUTO-8 ranges are half-open, over 366 days need --all-time, and shorthands exclude --from")
    func dayRanges() throws {
        let parse = { (text: String) throws -> DateArgument in try DateArgument.parse(text, now: now(), calendar: calendar) }
        func resolve(from: String? = nil, to: String? = nil, week: String? = nil, allTime: Bool = false) throws -> DayRange? {
            try DayRange.resolve(
                from: from.map(parse),
                to: to.map(parse),
                day: nil,
                week: week.map(parse),
                month: nil,
                allTime: allTime,
                defaultRange: nil,
                now: now(),
                calendar: calendar
            )
        }
        let range = try #require(try resolve(from: "2026-10-20", to: "2026-10-27"))
        #expect(range.dayCount == 7)
        #expect(range.days?.upperBound == TrackingDay(year: 2026, month: 10, day: 26))
        #expect(try resolve(from: "2026-10-20")?.to == TrackingDay(year: 2026, month: 10, day: 30))
        #expect(throws: AutomationError.usage("The range spans 731 days, more than 366; add --all-time.")) {
            try resolve(from: "2024-10-20", to: "2026-10-21")
        }
        #expect(try resolve(from: "2024-10-20", to: "2026-10-21", allTime: true)?.dayCount == 731)
        #expect(try resolve(allTime: true) == nil)
        #expect(throws: AutomationError.self) {
            try resolve(from: "2026-10-20", week: "week")
        }
        #expect(throws: AutomationError.self) {
            try resolve(from: "2026-10-20", to: "2026-10-20")
        }
    }

    @Test("AUTO-5 names fold case and diacritics, Client/Project and --client resolve duplicates, and ambiguity lists candidates")
    func nameResolution() async throws {
        let fixture = try await AutomationTestStore()
        let store = fixture.service.store
        #expect(try await store.resolveProject("noise PAPER").project.id == fixture.noisePaper.id)
        await #expect(throws: AutomationError.ambiguous(
            "The project name \"Admin\" exists in several clients; use Client/Project or --client:",
            candidates: ["Side business/Admin", "University/Admin"]
        )) {
            try await store.resolveProject("Admin")
        }
        #expect(try await store.resolveProject("university/admin").client?.name == "University")
        #expect(try await store.resolveProject("Admin", client: "side BUSINESS").client?.name == "Side business")
        await #expect(throws: AutomationError.refused("Project \"Old paper\" is archived; unarchive it first.")) {
            try await store.resolveProject("Old paper")
        }
        #expect(try await store.resolveProject("Old paper", includeArchived: true).project.isArchived)
        await #expect(throws: AutomationError.notFound("No project named \"Nothing\".")) {
            try await store.resolveProject("Nothing")
        }
        #expect(AutomationError.ambiguous("x", candidates: []).exitCode == 3)
    }

    @Test("AUTO-4 checked starts refuse the future, before the running start, over 24 hours back, overlaps, and archived projects")
    func checkedStart() async throws {
        let fixture = try await AutomationTestStore()
        let service = fixture.service
        await #expect(throws: AutomationError.refused("The start 10:05 lies in the future.")) {
            try await service.start(task: "", projectID: nil, at: fixture.date("2026-10-29T10:05"))
        }
        await #expect(throws: AutomationError.self) {
            try await service.start(task: "", projectID: nil, at: fixture.date("2026-10-29T09:00"))
        }
        await #expect(throws: AutomationError.refused("Project \"Old paper\" is archived; unarchive it first.")) {
            try await service.start(task: "", projectID: fixture.oldPaper.id)
        }
        let idle = try await AutomationTestStore(running: false)
        await #expect(throws: AutomationError.refused("A start may lie at most 24 hours back.")) {
            try await idle.service.start(task: "", projectID: nil, at: idle.date("2026-10-28T09:00"))
        }
        await #expect(throws: AutomationError.refused("No entry running.")) {
            try await idle.service.stop()
        }
        _ = try await idle.service.createEntry(EntryDraft(
            projectID: nil,
            task: "Call",
            start: idle.date("2026-10-29T09:00"),
            end: idle.date("2026-10-29T09:40")
        ))
        await #expect(throws: AutomationError.self) {
            try await idle.service.start(task: "Late", projectID: nil, at: idle.date("2026-10-29T09:30"))
        }
        let forced = try await idle.service.start(task: "Late", projectID: nil, at: idle.date("2026-10-29T09:30"), force: true)
        #expect(forced.entry.entry.isRunning)
        #expect(forced.stopped == nil)
    }

    @Test("AUTO-12 the tool's report rows equal the library's report query row for row")
    func reportRowsMatchLibrary() async throws {
        let fixture = try await AutomationTestStore()
        let week = DayRange(from: TrackingDay(year: 2026, month: 10, day: 19), to: TrackingDay(year: 2026, month: 10, day: 26))
        let result = try await fixture.service.report(range: week, groupBy: [.project], granularity: .day)
        let query = try #require(week.days.map { ReportQuery(days: $0, groupBy: [.project], granularity: .day) })
        let library = try await fixture.service.store.report(query)
        #expect(result.root == library)
        var expected: [String] = []
        for period in TrackingCalendar(timeZone: fixture.test.zone).periods(.day, covering: query.days) {
            for leaf in library.children {
                if let seconds = leaf.buckets[period], seconds > 0 {
                    expected.append("\(period) \(leaf.name ?? "-") \(seconds)")
                }
            }
        }
        #expect(result.rows.map { "\($0.period) \($0.path.last?.name ?? "-") \($0.seconds)" } == expected)
        #expect(result.periods.count == 7)
        #expect(result.json["total"] == .int(library.seconds))
    }

    @Test("AUTO-31 report CSV is the Reports Breakdown writer's output for the same query")
    func reportCSVMatchesBreakdown() async throws {
        let fixture = try await AutomationTestStore()
        let week = DayRange(from: TrackingDay(year: 2026, month: 10, day: 19), to: TrackingDay(year: 2026, month: 10, day: 26))
        let filter = try await fixture.service.filter(client: "University")
        let result = try await fixture.service.report(range: week, groupBy: [.client, .area, .project], granularity: .total, filter: filter)
        let query = try #require(week.days.map { ReportQuery(days: $0, groupBy: [.client, .area, .project], filter: filter) })
        let breakdown = try await ReportCSVWriter.breakdownCSV(fixture.service.store.report(query), levels: query.groupBy)
        #expect(result.csv == breakdown)
        #expect(result.csv.hasPrefix("client,area,project,seconds,duration,share,entries\n"))
    }

    @Test("AUTO-20 check reports the rules in order; AUTO-21 the file validation; AUTO-23 fix repairs without archiving or moving")
    func descriptionCheck() async throws {
        let fixture = try await AutomationTestStore()
        let text = """
        version = 1
        [[client]]
        name = "University"
          [[client.area]]
          name = "Research"
          color = "#123456"
          projects = ["Noise paper", { name = "Old paper" }, "Grant renewal", "Admin"]
          [[client.area]]
          name = "Teaching"
          color = "#EE9B00"
          projects = []
        [[client]]
        name = "Lab"
          [[client.area]]
          name = "Lab"
          color = "#112233"
          projects = ["Setup"]
        """
        let file = try DescriptionFile(text: text)
        let check = try await fixture.service.check(file)
        #expect(check.inconsistencies.map(\.kind) == [
            .missingClient,
            .colorMismatch,
            .archivedProject,
            .missingProject,
            .wrongArea,
            .unlistedClient,
        ])
        let fixed = try await fixture.service.fix(file)
        #expect(fixed.actions.map(\.message) == [
            "created client: Lab",
            "recolored area: University / Research from #0A9396 to #123456",
            "unarchived project: University / Research / Old paper",
            "created project: University / Research / Grant renewal",
            "created project: Lab / Lab / Setup",
        ])
        #expect(fixed.inconsistencies.map(\.message) == [
            "wrong area: University / Admin is in Teaching, expected Research",
            "unlisted client: Side business (active projects: 1)",
        ])
        for bad in [
            "version = 1\n[[client]]\nname = \"A\"",
            "[[client]]\nname = \"A\"",
            "{\"version\": 1, \"client\": [{\"name\": \"A\", \"area\": [{\"name\": \"B\", \"color\": \"red\", \"projects\": []}]}]}",
        ] {
            #expect(throws: AutomationError.self) {
                try DescriptionFile(text: bad)
            }
        }
        let duplicate = "version = 1\n[[client]]\nname = \"A\"\n[[client.area]]\nname = \"B\"\n"
            + "color = \"#000000\"\nprojects = [\"X\", \"x\"]"
        #expect(throws: AutomationError.invalidInput("client[0]: the project name \"x\" appears twice.")) {
            try DescriptionFile(text: duplicate)
        }
    }

    @Test("AUTO-33 a write through the service queues one outbox row per changed record; a refused one none")
    func outboxRows() async throws {
        let fixture = try await AutomationTestStore()
        let before = try await fixture.service.store.outboxCount()
        // The stopped entry, the new entry, and the LiveState record.
        _ = try await fixture.service.start(task: "Next", projectID: nil)
        #expect(try await fixture.service.store.outboxCount() == before + 3)
        await #expect(throws: AutomationError.self) {
            try await fixture.service.start(task: "", projectID: fixture.oldPaper.id)
        }
        #expect(try await fixture.service.store.outboxCount() == before + 3)
    }
}
