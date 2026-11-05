// Entries stored whole and cut when shown, and the invariant pass
// (spec_data_and_sync.md §1.5, §3.3, §8; §9 items 17 to 23, 46, 61).

import Foundation
import Testing
import TimeTrackingCore

struct WholeEntryTests {
    @Test("DATA-17 a create across midnight in Europe/Berlin stores one entry, and shown it has a piece on each date")
    func createAcrossMidnight() async throws {
        let test = try await TestStore(now: "2026-03-03T10:00")
        let id = EntryID()
        let entry = try await test.store.create(EntryDraft(
            id: id,
            projectID: nil,
            task: "Late",
            start: test.date("2026-03-02T22:00"),
            end: test.date("2026-03-03T01:30")
        ))
        #expect(entry.id == id)
        #expect(try entry.end == (test.date("2026-03-03T01:30")))
        #expect(entry.day.description == "2026-03-02")
        #expect(try await test.store.entry(id) == entry)
        #expect(try await test.store.entries(on: TrackingDay(year: 2026, month: 3, day: 3)).isEmpty)
        let pieces = test.store.displayCalendar(timeZone: test.zone).pieces(of: entry, at: test.clock.now)
        #expect(pieces.map(\.id) == [id, id])
        #expect(try pieces[0].end == (test.date("2026-03-03T00:00")))
        #expect(pieces[0].day.description == "2026-03-02")
        #expect(try pieces[1].start == (test.date("2026-03-03T00:00")))
        #expect(pieces[1].end == entry.end)
        #expect(pieces[1].day.description == "2026-03-03")
    }

    @Test("DATA-18 a running entry stays one entry when the clock passes midnight; its last piece runs on the new day")
    func runningAcrossMidnight() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let entry = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-03T00:10"))
        let outbox = try await test.store.outboxCount()
        try await test.store.checkInvariants()
        #expect(try await test.store.outboxCount() == outbox)
        #expect(try await test.store.runningEntry() == entry)
        let today = try #require(try await test.store.timerList(dayLimit: 1).first)
        #expect(today.day.description == "2026-03-03")
        #expect(try today.running?.start == test.date("2026-03-03T00:00"))
        #expect(today.totalSeconds(at: test.clock.now) == 600)
    }

    @Test(
        "DATA-19 an entry forgotten for days is one record: each day lists its part, totals agree, a range inside it finds it"
    )
    func entryAcrossManyDays() async throws {
        let test = try await TestStore(now: "2026-10-26T22:00")
        let entry = try await test.store.start(projectID: nil, task: "Long", at: test.date("2026-10-26T22:00"))
        try test.clock.set(test.date("2026-10-28T10:00"))
        let wednesday = TrackingDay(year: 2026, month: 10, day: 28)
        let tuesday = wednesday.adding(days: -1)
        let groups = try await test.store.days(ending: wednesday, count: 3)
        #expect(groups.map(\.totalSeconds) == [10 * 3600, 24 * 3600, 2 * 3600])
        #expect(groups.flatMap(\.entries).allSatisfy { $0.id == entry.id })
        #expect(groups.map(\.includesRunning) == [true, false, false])
        #expect(try await test.store.entryDays(limit: 3).map(\.description) == ["2026-10-28", "2026-10-27", "2026-10-26"])
        let list = try await test.store.timerList(dayLimit: 2)
        #expect(list.map(\.day) == [wednesday, tuesday])
        #expect(list.last?.rows.first?.editable == entry, "the list holds no earlier row of the entry")
        let middle = try await test.store.report(ReportQuery(days: tuesday ... tuesday, groupBy: [.task], granularity: .day))
        #expect(middle.seconds == 24 * 3600 && middle.entryCount == 1)
        let all = try await test.store.report(ReportQuery(days: tuesday.adding(days: -1) ... wednesday, groupBy: [.day], granularity: .day))
        #expect(all.seconds == 36 * 3600 && all.children.count == 3)
        let snapshot = try await test.store.reportSnapshot(ReportRequest(days: tuesday ... tuesday, today: wednesday, includeEntries: true))
        #expect(snapshot.entries.listings.map(\.id) == [entry.id])
        #expect(try await test.store.projectSeconds(days: tuesday ... tuesday).isEmpty)
    }

    @Test("DATA-20 editing an end past midnight changes that entry alone; an entry ending at 00:00 has one piece")
    func editingAcrossMidnight() async throws {
        let test = try await TestStore(now: "2026-03-03T10:00")
        let store = test.store
        let entry = try await store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2026-03-02T22:00"),
            end: test.date("2026-03-02T23:30")
        ))
        let edited = try await store.update(entry.id, EntryChange(end: test.date("2026-03-03T00:45")))
        #expect(edited.id == entry.id)
        #expect(try await store.entries(in: DateInterval(start: test.date("2026-03-02T00:00"), end: test.clock.now)) == [edited])
        let exact = try await store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2026-03-02T20:00"),
            end: test.date("2026-03-03T00:00")
        ))
        #expect(store.displayCalendar(timeZone: test.zone).pieces(of: exact, at: test.clock.now).count == 1)
    }

    @Test("DATA-21 in America/Sao_Paulo the 2018-11-04 day starts at 01:00 and the cut lies there")
    func midnightlessDay() async throws {
        let test = try await TestStore(now: "2018-11-05T10:00", zone: "America/Sao_Paulo")
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2018-11-03T22:00"),
            end: test.date("2018-11-04T02:00")
        ))
        let calendar = TrackingCalendar(timeZone: test.zone)
        let pieces = calendar.pieces(of: entry, at: test.clock.now)
        #expect(pieces.count == 2)
        let sunday = TrackingDay(year: 2018, month: 11, day: 4)
        #expect(calendar.startOfDay(sunday) == pieces[1].start)
        #expect(pieces[0].end == pieces[1].start)
        #expect(pieces[1].end?.timeIntervalSince(pieces[1].start) == 3600)
        #expect(pieces[0].end?.timeIntervalSince(pieces[0].start) == 7200)
        let report = try await test.store.report(ReportQuery(days: sunday ... sunday, groupBy: [], granularity: .day))
        #expect(report.seconds == 3600)
    }

    @Test("DATA-22 a New York entry has one piece on a device in Berlin and keeps its New York day")
    func ownZone() async throws {
        let test = try await TestStore(now: "2026-10-29T12:00")
        let york = try #require(TimeZone(identifier: "America/New_York"))
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: TestStore.date("2026-10-27T20:00", york),
            end: TestStore.date("2026-10-27T23:00", york),
            timeZone: "America/New_York"
        ))
        let tuesday = TrackingDay(year: 2026, month: 10, day: 27)
        #expect(entry.day == tuesday)
        #expect(TrackingCalendar(timeZone: test.zone).pieces(of: entry, at: test.clock.now).count == 1)
        #expect(try await test.store.entries(on: tuesday).count == 1)
        let days = try await test.store.days(ending: tuesday, count: 1)
        #expect(days[0].totalSeconds == 3 * 3600)
    }

    @Test("DATA-23 several running entries reduce to the latest start; equal starts keep the greater id; idempotent")
    func runningReduction() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let store = test.store
        let ids = [EntryID(), EntryID(), EntryID()]
        let starts = ["2024-03-14T08:00", "2024-03-14T09:00", "2024-03-14T09:30"]
        try await store.transaction { transaction in
            for (id, start) in zip(ids, starts) {
                _ = try transaction.create(EntryDraft(id: id, projectID: nil, task: "", start: TestStore.date(start, test.zone), end: nil))
            }
        }
        #expect(try await store.runningEntry()?.id == ids[2])
        #expect(try await store.entry(ids[0])?.end == (test.date("2024-03-14T09:00")))
        #expect(try await store.entry(ids[1])?.end == (test.date("2024-03-14T09:30")))
        let outbox = try await store.outboxCount()
        try await store.checkInvariants()
        #expect(try await store.outboxCount() == outbox)

        let tie = try await TestStore(now: "2024-03-14T10:00")
        let pair = [EntryID(), EntryID()].sorted()
        try await tie.store.transaction { transaction in
            for id in pair {
                _ = try transaction.create(EntryDraft(
                    id: id,
                    projectID: nil,
                    task: "",
                    start: TestStore.date("2024-03-14T09:00", tie.zone),
                    end: nil
                ))
            }
        }
        #expect(try await tie.store.runningEntry()?.id == pair[1])
        #expect(try await tie.store.entry(pair[0]) == nil)
    }

    @Test("TM-49 a stop reaches back over midnights, and never before the entry's start")
    func stopBackAcrossMidnights() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let entry = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-04T00:30"))
        let stop = try test.date("2026-03-02T23:50")
        let stopped = try await test.store.transaction { try $0.stop(entry: entry.id, at: stop) }
        #expect(stopped?.id == entry.id && stopped?.end == stop)
        #expect(try await test.store.runningEntry() == nil)

        let other = try await test.store.start(projectID: nil, task: "Dawn", at: test.date("2026-03-03T23:40"))
        let clamped = try await test.store.transaction { try $0.stop(entry: other.id, at: other.start - 3600) }
        #expect(clamped?.end == other.start)
    }

    @Test("DATA-46 Berlin DST days are 23 and 25 hours; consecutive days at midnight; ISO week 1 of 2027")
    func calendarRules() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let calendar = TrackingCalendar(timeZone: zone)
        #expect(calendar.interval(of: TrackingDay(year: 2026, month: 3, day: 29)).duration == 23 * 3600)
        #expect(calendar.interval(of: TrackingDay(year: 2026, month: 10, day: 25)).duration == 25 * 3600)
        let before = try TestStore.date("2026-10-28T23:59:59", zone)
        #expect(calendar.day(containing: before).description == "2026-10-28")
        #expect(calendar.day(containing: before + 1).description == "2026-10-29")
        let week = calendar.week(containing: TrackingDay(year: 2026, month: 10, day: 29))
        #expect(week.first?.description == "2026-10-26")
        #expect(week.first?.isoWeekday == 1)
        let first = TrackingPeriod(.week, containing: TrackingDay(year: 2027, month: 1, day: 6))
        #expect(first.start.description == "2027-01-04")
        #expect(first.description == "2027-W01")
        #expect(TrackingPeriod(.week, containing: TrackingDay(year: 2027, month: 1, day: 3)).description == "2026-W53")
    }

    @Test("DATA-61 a report cuts an entry at every day change in its own zone, across a DST day and with Midnight at another hour")
    func reportCutsManyTimes() async throws {
        let test = try await TestStore(now: "2026-03-31T12:00")
        try await test.store.set(.midnightHour, 4)
        let saturday = TrackingDay(year: 2026, month: 3, day: 28)
        let sunday = saturday.adding(days: 1)
        let monday = sunday.adding(days: 1)
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Weekend",
            start: test.date("2026-03-28T02:00"),
            end: test.date("2026-03-30T06:00")
        ))
        let report = try await test.store.report(ReportQuery(
            days: saturday.adding(days: -1) ... monday,
            groupBy: [.day],
            granularity: .day
        ))
        // The day of Friday ends at 04:00 on Saturday; that of Saturday holds the DST change.
        #expect(report.children.map(\.seconds) == [2 * 3600, 23 * 3600, 24 * 3600, 2 * 3600])
        #expect(report.seconds == 51 * 3600)
        #expect(report.entryCount == 4)
    }
}
