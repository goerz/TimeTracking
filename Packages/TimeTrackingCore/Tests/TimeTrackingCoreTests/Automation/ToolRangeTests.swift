// The tool's instant bounds, `tomorrow`, report health time, and the strict
// check (spec_automation.md §3.2, §3.7, §4.2, §9 items 41 and 43 to 45).

import Foundation
import Testing
import TimeTrackingCore

struct ToolRangeTests {
    private func resolve(_ fixture: AutomationTestStore, from: String?, to: String? = nil) throws -> DayRange? {
        let service = fixture.service
        let parse = { (text: String) throws -> DateArgument in
            try DateArgument.parse(text, now: service.now, calendar: service.calendar)
        }
        return try DayRange.resolve(
            from: from.map(parse),
            to: to.map(parse),
            day: nil,
            week: nil,
            month: nil,
            allTime: false,
            defaultRange: nil,
            now: service.now,
            calendar: service.calendar
        )
    }

    @Test("AUTO-41 a --from or --to with a time is an instant bound: entries start inside it, report counts them, JSON echoes the instant")
    func instantBounds() async throws {
        let fixture = try await AutomationTestStore()
        let service = fixture.service
        let range = try #require(try resolve(fixture, from: "2026-10-20T10:00", to: "2026-10-22T09:30"))
        #expect(range.from == TrackingDay(year: 2026, month: 10, day: 20))
        #expect(range.to == TrackingDay(year: 2026, month: 10, day: 23))
        #expect(range.fromText(in: service.timeZone) == "2026-10-20T10:00:00+02:00")
        #expect(range.toText(in: service.timeZone) == "2026-10-22T09:30:00+02:00")
        let entries = try await service.entries(in: range)
        #expect(try entries.listings.map(\.entry.start) == [fixture.date("2026-10-21T09:00"), fixture.date("2026-10-22T09:00")])
        let report = try await service.report(range: range, groupBy: [.project], granularity: .day)
        #expect(report.root.seconds == 2 * 3600)
        #expect(report.periods.count == 3)
        #expect(report.json["from"] == .string("2026-10-20T10:00:00+02:00"))
        #expect(report.json["to"] == .string("2026-10-22T09:30:00+02:00"))
        // A date bound stays a day; a time at midnight is still an instant.
        let mixed = try #require(try resolve(fixture, from: "2026-10-21", to: "2026-10-22T00:00"))
        #expect(mixed.to == TrackingDay(year: 2026, month: 10, day: 22))
        #expect(mixed.fromText(in: service.timeZone) == "2026-10-21")
        #expect(mixed.toText(in: service.timeZone) == "2026-10-22T00:00:00+02:00")
        #expect(try await service.entries(in: mixed).listings.count == 1)
        // Without --to an instant --from runs through today.
        let open = try #require(try resolve(fixture, from: "2026-10-29T09:00"))
        #expect(open.to == TrackingDay(year: 2026, month: 10, day: 30))
        #expect(try await service.entries(in: open).listings.count == 1)
        #expect(throws: AutomationError.self) {
            try resolve(fixture, from: "2026-10-21T10:00", to: "2026-10-21T09:00")
        }
    }

    @Test("AUTO-45 tomorrow is the day after today")
    func tomorrow() throws {
        let calendar = TrackingCalendar(timeZone: TimeZone(identifier: "Europe/Berlin") ?? .gmt)
        let now = try TestStore.date("2026-10-29T10:00", calendar.timeZone)
        let argument = try DateArgument.parse("tomorrow", now: now, calendar: calendar)
        let day = TrackingDay(year: 2026, month: 10, day: 30)
        #expect(argument == .period(DayRange(from: day, to: day.adding(days: 1))))
    }

    @Test("AUTO-43 the tool's report counts mapped sleep only with includeHealth, cut at instant bounds")
    func healthOptIn() async throws {
        let fixture = try await AutomationTestStore()
        let store = fixture.service.store
        let night = try DateInterval(start: fixture.date("2026-10-20T23:00"), end: fixture.date("2026-10-21T07:00"))
        try await store.replaceHealthPeriods(.sleep, from: fixture.date("2026-10-01T00:00"), with: [night])
        try await store.set(.calendarShowSleep, true)
        try await store.set(.calendarSleepAreaID, fixture.research.id)
        let day = TrackingDay(year: 2026, month: 10, day: 21)
        let whole = DayRange(from: day, to: day.adding(days: 1))
        let service = fixture.service
        #expect(try await service.report(range: whole, groupBy: [.project], granularity: .total).root.seconds == 3600)
        let health = try await service.report(range: whole, groupBy: [.project], granularity: .total, includeHealth: true)
        #expect(health.root.seconds == 3600 + 7 * 3600)
        #expect(health.root.children.map(\.name).contains("Sleep"))
        // The Reports query keeps counting it.
        let query = ReportQuery(days: day ... day, groupBy: [.project])
        #expect(try await store.report(query).seconds == 3600 + 7 * 3600)
        let bounded = try #require(try resolve(fixture, from: "2026-10-21T04:00", to: "2026-10-22T04:00"))
        let cut = try await service.report(range: bounded, groupBy: [.project], granularity: .total, includeHealth: true)
        #expect(cut.root.seconds == 3600 + 3 * 3600)
    }

    @Test("AUTO-44 strict check reports active projects of a listed area that the file omits; fix leaves them")
    func strictCheck() async throws {
        let fixture = try await AutomationTestStore()
        let text = """
        version = 1
        [[client]]
        name = "University"
          [[client.area]]
          name = "Research"
          color = "#0A9396"
          projects = []
          [[client.area]]
          name = "Teaching"
          color = "#EE9B00"
          projects = ["Noise paper"]
        [[client]]
        name = "Side business"
          [[client.area]]
          name = "Side business"
          color = "#CC47C3"
          projects = ["Admin"]
        """
        let file = try DescriptionFile(text: text)
        let plain = try await fixture.service.check(file)
        #expect(plain.inconsistencies.map(\.message) == ["wrong area: University / Noise paper is in Research, expected Teaching"])
        let strict = try await fixture.service.check(file, strict: true)
        #expect(strict.inconsistencies.map(\.message) == [
            "wrong area: University / Noise paper is in Research, expected Teaching",
            "unlisted project: University / Teaching / Admin",
        ])
        let unlisted = try #require(strict.inconsistencies.last)
        #expect(unlisted.kind == .unlistedProject)
        #expect(unlisted.json["rule"] == .int(7))
        #expect(unlisted.json["kind"] == .string("unlisted-project"))
        #expect(unlisted.project == "Admin")
        let fixed = try await fixture.service.fix(file, strict: true)
        #expect(fixed.actions.isEmpty)
        #expect(fixed.inconsistencies == strict.inconsistencies)
        #expect(try await fixture.service.projects(state: .active).count == 3)
    }
}
