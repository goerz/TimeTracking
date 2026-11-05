// The Midnight setting: the days the app shows and reports, over entries
// stored at real midnights (data_and_sync.md §8; reports.md §1.1;
// timer.md §3; activity.md §1; automation.md §3.2; ios.md §3).

import Foundation
import Testing
import TimeTrackingCore

struct MidnightHourTests {
    private static func day(_ text: String) throws -> TrackingDay {
        try #require(TrackingDay(text))
    }

    /// A store at 2024-03-14T10:00 in Berlin with Midnight at `hour`, and
    /// three stopped entries: "Evening" on the 12th, "Night" across 04:00 on
    /// the 13th, and "Late" across the real midnight of the 14th.
    private static func nights(hour: Int = 4) async throws -> TestStore {
        let test = try await TestStore()
        try await test.store.set(.midnightHour, hour)
        for (task, start, end) in [
            ("Evening", "2024-03-12T22:00", "2024-03-12T23:30"),
            ("Night", "2024-03-13T03:00", "2024-03-13T05:00"),
            ("Late", "2024-03-13T23:00", "2024-03-14T01:00"),
        ] {
            _ = try await test.store.create(EntryDraft(projectID: nil, task: task, start: test.date(start), end: test.date(end)))
        }
        return test
    }

    @Test(
        "DATA-56 with Midnight at 04:00 a day runs to 04:00 under its date; at 22:00 under the date it ends on; at 00:00 the plain date"
    )
    func days() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let morning = TrackingCalendar(timeZone: zone, midnightHour: 4)
        #expect(try morning.day(containing: TestStore.date("2024-03-14T03:59:59", zone)) == Self.day("2024-03-13"))
        #expect(try morning.day(containing: TestStore.date("2024-03-14T04:00", zone)) == Self.day("2024-03-14"))
        #expect(try morning.startOfDay(Self.day("2024-03-14")) == TestStore.date("2024-03-14T04:00", zone))
        #expect(try morning.interval(of: Self.day("2024-03-14")).duration == 24 * 3600)
        let evening = TrackingCalendar(timeZone: zone, midnightHour: 22)
        #expect(try evening.day(containing: TestStore.date("2024-03-14T21:59", zone)) == Self.day("2024-03-14"))
        #expect(try evening.day(containing: TestStore.date("2024-03-14T22:00", zone)) == Self.day("2024-03-15"))
        #expect(try evening.startOfDay(Self.day("2024-03-15")) == TestStore.date("2024-03-14T22:00", zone))
        let plain = TrackingCalendar(timeZone: zone)
        #expect(plain.midnightHour == 0)
        #expect(try plain.startOfDay(Self.day("2024-03-14")) == TestStore.date("2024-03-14T00:00", zone))
        #expect(TrackingCalendar(timeZone: zone, midnightHour: 99).midnightHour == 23)
    }

    @Test("DATA-57 an hour a DST change skips starts the day at the first instant after it; of an hour it repeats the first counts")
    func daylightSaving() throws {
        let zone = TestTime.newYork
        let skipped = TrackingCalendar(timeZone: zone, midnightHour: 2)
        let spring = try Self.day("2024-03-10")
        #expect(try skipped.startOfDay(spring) == TestStore.date("2024-03-10T03:00", zone))
        #expect(skipped.interval(of: spring).duration == 23 * 3600)
        #expect(try skipped.day(containing: TestStore.date("2024-03-10T01:59", zone)) == Self.day("2024-03-09"))
        #expect(try skipped.day(containing: TestStore.date("2024-03-10T03:00", zone)) == spring)
        let repeated = TrackingCalendar(timeZone: zone, midnightHour: 1)
        let fall = try Self.day("2024-11-03")
        let first = repeated.startOfDay(fall)
        #expect(zone.isDaylightSavingTime(for: first))
        #expect(repeated.interval(of: fall).duration == 25 * 3600)
        #expect(repeated.day(containing: first + 3600) == fall)
    }

    @Test(
        "DATA-58 Midnight changes no stored entry: an entry across it becomes two pieces only when shown, at that hour"
    )
    func storageUnchanged() async throws {
        let test = try await Self.nights()
        let span = try DateInterval(start: test.date("2024-03-12T00:00"), end: test.date("2024-03-15T00:00"))
        let stored = try await test.store.entries(in: span)
        #expect(stored.map(\.task) == ["Evening", "Night", "Late"])
        let days = try await [test.store.entries(on: Self.day("2024-03-13")).count, test.store.entries(on: Self.day("2024-03-14")).count]
        #expect(days == [2, 0])
        let night = try #require(stored.first { $0.task == "Night" })
        let calendar = test.store.displayCalendar(timeZone: test.zone)
        let pieces = calendar.pieces(of: night, at: test.clock.now)
        #expect(try pieces.map(\.day) == [Self.day("2024-03-12"), Self.day("2024-03-13")])
        #expect(pieces.map(\.id) == [night.id, night.id])
        #expect(try pieces[0].end == test.date("2024-03-13T04:00"))
        #expect(try pieces[1].start == test.date("2024-03-13T04:00"))
        #expect(pieces[1].end == night.end)
        #expect(try await test.store.entry(night.id) == night)
        var unchanged = night
        unchanged.day = try Self.day("2024-03-13")
        #expect(TrackingCalendar(timeZone: test.zone).pieces(of: night, at: test.clock.now) == [unchanged])
    }

    @Test("DATA-58 a running entry's last piece runs, a piece in another zone cuts at that zone's Midnight")
    func runningAndZones() async throws {
        let test = try await TestStore(now: "2024-03-14T05:00")
        let running = try await test.store.start(projectID: nil, task: "Overnight", at: test.date("2024-03-14T03:30"))
        let calendar = TrackingCalendar(timeZone: test.zone, midnightHour: 4)
        let pieces = calendar.pieces(of: running, at: test.clock.now)
        #expect(pieces.map(\.isRunning) == [false, true])
        #expect(try pieces[1].seconds(at: test.clock.now) == 3600 && pieces[1].day == Self.day("2024-03-14"))
        var away = running
        away.timeZone = "America/New_York"
        away.end = away.start + 3600
        #expect(calendar.pieces(of: away, at: test.clock.now).count == 1)
    }

    @Test("PR-24 reports cut entries at Midnight, each part one entry of its day, and agree with day groups and project totals")
    func reports() async throws {
        let test = try await Self.nights()
        let made = try await test.structure(projects: ["Paper"])
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "Dawn",
            start: test.date("2024-03-14T03:30"),
            end: test.date("2024-03-14T04:30")
        ))
        let days = try Self.day("2024-03-12") ... Self.day("2024-03-14")
        let report = try await test.store.report(ReportQuery(days: days, groupBy: [.task], granularity: .day))
        let seconds = try [
            report.buckets[TrackingPeriod(.day, containing: Self.day("2024-03-12"))],
            report.buckets[TrackingPeriod(.day, containing: Self.day("2024-03-13"))],
            report.buckets[TrackingPeriod(.day, containing: Self.day("2024-03-14"))],
        ]
        #expect(seconds == [9000, 12_600, 1800])
        #expect(report.entryCount == 6)
        let groups = try await test.store.days(ending: days.upperBound, count: 3)
        #expect(groups.map(\.totalSeconds) == [1800, 12_600, 9000])
        let middle = try Self.day("2024-03-13")
        let single = try await test.store.report(ReportQuery(days: middle ... middle, groupBy: [], granularity: .day))
        #expect(single.seconds == 12_600)
        #expect(try await test.store.projectSeconds(days: days.upperBound ... days.upperBound) == [made.projects[0].id: 1800])
        #expect(try await test.store.projectSeconds(days: middle ... middle) == [made.projects[0].id: 1800])
    }

    @Test("PR-24 the entry list shows each day's part with the stored entry behind it, and a filter by day keeps that part")
    func reportEntries() async throws {
        let test = try await Self.nights()
        let snapshot = try await test.store.reportSnapshot(ReportRequest(
            days: Self.day("2024-03-13") ... Self.day("2024-03-13"),
            today: Self.day("2024-03-14"),
            includeEntries: true
        ))
        let listings = snapshot.entries.listings
        #expect(Set(listings.map(\.entry.task)) == ["Night", "Late"])
        let part = try #require(listings.first { $0.entry.task == "Night" })
        #expect(try part.entry.start == test.date("2024-03-13T04:00"))
        #expect(try part.whole?.start == test.date("2024-03-13T03:00"))
        #expect(part.editable == part.whole, "the first row of an entry in the list opens its editor")
        #expect(snapshot.entries.stoppedSeconds == 3600 + 7200)
    }

    @Test("PR-25 a report's running part counts up to now on the day it lies on, and sleep is cut at Midnight")
    func runningAndHealth() async throws {
        let test = try await TestStore(now: "2024-03-14T05:00")
        try await test.store.set(.midnightHour, 4)
        _ = try await test.store.start(projectID: nil, task: "Overnight", at: test.date("2024-03-14T03:00"))
        let (_, area) = try await test.store.createClient(name: "Life")
        try await test.store.set(.calendarShowSleep, true)
        try await test.store.set(.calendarSleepAreaID, area.id)
        let night = try DateInterval(start: test.date("2024-03-12T23:00"), end: test.date("2024-03-13T06:30"))
        try await test.store.replaceHealthPeriods(.sleep, from: test.date("2024-03-01T00:00"), with: [night])
        let today = try Self.day("2024-03-14")
        let yesterday = try Self.day("2024-03-13")
        let current = try await test.store.report(ReportQuery(days: today ... today, groupBy: [], granularity: .day))
        #expect(current.seconds == 3600)
        let before = try await test.store.report(ReportQuery(days: yesterday ... yesterday, groupBy: [], granularity: .day))
        #expect(before.seconds == 3600 + 2 * 3600 + 1800)
        let earlier = try Self.day("2024-03-12")
        let first = try await test.store.report(ReportQuery(days: earlier ... earlier, groupBy: [], granularity: .day))
        #expect(first.seconds == 5 * 3600)
    }

    @Test("TM-45 the Timer list groups by shown days: an entry across Midnight has a row on each day, a night across real midnight one day")
    func timerList() async throws {
        let test = try await Self.nights()
        let days = try await test.store.timerList(dayLimit: 10)
        #expect(try days.map(\.day) == [Self.day("2024-03-13"), Self.day("2024-03-12")])
        #expect(days[0].rows.map(\.entry.task) == ["Late", "Night"])
        #expect(days[1].rows.map(\.entry.task) == ["Night", "Evening"])
        #expect(days.map { $0.totalSeconds(at: test.clock.now) } == [10_800, 9000])
        #expect(try await test.store.entryDays(limit: 1).count == 1)
        #expect(try await test.store.entryDays(limit: 5) == days.map(\.day))
        let first = try #require(days[1].rows.first)
        #expect(try first.entry.end == test.date("2024-03-13T04:00"))
        #expect(try first.editable?.end == test.date("2024-03-13T05:00"))
        #expect(first.rowID != days[0].rows[1].rowID)
    }

    @Test("PA-23 a block counts on the shown day of its start, and a heatmap row runs from Midnight round the clock")
    func activity() throws {
        let block = try ActivityFixture.block(
            start: "2024-03-14T02:00:00-04:00",
            end: "2024-03-14T03:00:00-04:00",
            items: [ActivityItem(context: "mail", subject: "", detail: "", seconds: 3600, device: "macbook")]
        )
        #expect(block.shownDay == "2024-03-14")
        let shown = block.shown(midnightHour: 4)
        #expect(shown.shownDay == "2024-03-13")
        #expect(shown.localDay == "2024-03-14")
        #expect(block.shown(midnightHour: 0).shownDay == "2024-03-14")
        let days = try Self.day("2024-03-13") ... Self.day("2024-03-14")
        let summary = try ActivitySummary(ActivitySummaryInput(blocks: [shown], days: days, today: Self.day("2024-03-14")))
        let row = try #require(summary.heatmap.rows.first)
        #expect(row.minutes[2] == 60)
        #expect(ActivityHeatmap.columns(midnightHour: 4).prefix(2) == [4, 5])
        #expect(ActivityHeatmap.columns(midnightHour: 4).last == 3)
        #expect(ActivityHeatmap.columns(midnightHour: 0).first == 0)
    }

    @Test("AUTO-47 today and day ranges follow Midnight, report cuts at it, and entries lists stored entries by their start")
    func tool() async throws {
        let test = try await Self.nights()
        try test.clock.set(test.date("2024-03-14T02:00"))
        let service = AutomationService(store: test.store, timeZone: test.zone)
        #expect(try service.today == Self.day("2024-03-13"))
        let status = try await service.status()
        #expect(status.todaySeconds == 3600 + 7200)
        let range = try DayRange(from: Self.day("2024-03-13"), to: Self.day("2024-03-14"))
        let entries = try await service.entries(in: range)
        #expect(entries.listings.map(\.entry.task) == ["Late"])
        #expect(entries.listings.allSatisfy { $0.whole == nil })
        let report = try await service.report(range: range, groupBy: [.task], granularity: .day)
        #expect(report.root.seconds == 3600 + 7200)
    }

    @Test("AUTO-48 Today's Total counts the part of an entry that started before Midnight, as status does")
    func todayTotalIntent() async throws {
        let test = try await Self.nights()
        try test.clock.set(test.date("2024-03-13T12:00"))
        let service = AutomationService(store: test.store, timeZone: test.zone)
        let total = try await IntentActions.total(on: nil, service: service)
        #expect(total.value == 10_800)
        #expect(try await service.status().todaySeconds == 10_800)
    }

    @Test("DATA-60 a day watcher reports the start of a shown day once, and a change of Midnight that moves the day")
    func dayWatcher() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let calendar = TrackingCalendar(timeZone: zone, midnightHour: 4)
        var watcher = try ShownDayWatcher(calendar: calendar, now: TestStore.date("2024-03-14T03:59", zone))
        #expect(try !watcher.dayChanged(calendar: calendar, now: TestStore.date("2024-03-14T03:59:30", zone)))
        #expect(try watcher.dayChanged(calendar: calendar, now: TestStore.date("2024-03-14T04:00", zone)))
        #expect(try !watcher.dayChanged(calendar: calendar, now: TestStore.date("2024-03-14T04:01", zone)))
        let later = TrackingCalendar(timeZone: zone, midnightHour: 5)
        #expect(try watcher.dayChanged(calendar: later, now: TestStore.date("2024-03-14T04:02", zone)))
    }

    @Test("IOS-48 a widget's today follows Midnight: stopped parts, a live timer from the running entry, a timeline to the next day")
    func widgets() async throws {
        let test = try await TestStore(now: "2024-03-14T02:00")
        try await test.store.set(.midnightHour, 4)
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Evening",
            start: test.date("2024-03-13T20:00"),
            end: test.date("2024-03-13T21:00")
        ))
        _ = try await test.store.start(projectID: nil, task: "Late", at: test.date("2024-03-13T23:00"))
        let builder = WidgetSnapshotBuilder(store: test.store, timeZone: test.zone)
        let live = try await test.store.liveState()
        let snapshot = await builder.build(at: test.clock.now, live: live, setupComplete: true)
        // 1 h "Evening", then 3 h running since 23:00.
        #expect(snapshot.todayStoppedSeconds == 3600)
        #expect(snapshot.todaySeconds(at: test.clock.now) == 4 * 3600)
        #expect(try snapshot.reloadAt == test.date("2024-03-14T04:00"))
    }
}
