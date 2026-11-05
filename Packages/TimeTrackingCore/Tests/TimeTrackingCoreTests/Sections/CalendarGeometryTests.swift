// Tests of the Calendar's geometry, gestures, and overlaps
// (spec_calendar.md §7).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Calendar geometry")
struct CalendarGeometryTests {
    static let zone = TestTime.newYork
    static let calendar = TrackingCalendar(timeZone: zone)
    static let thursday = TrackingDay(year: 2026, month: 10, day: 29)

    static func time(_ text: String) throws -> Date {
        try TestTime.local(text, in: zone)
    }

    static func editing(now: String = "2026-10-29T14:20", snap: Int = 5) throws -> CalendarEditing {
        try CalendarEditing(day: calendar.interval(of: thursday), now: time(now), snap: CalendarSnap(minutes: snap))
    }

    @Test("PC-1 at 72 pt per hour 09:00 to 10:30 is 108 pt; ⌘+ makes it 135, the now-line or center kept in place; zoom clamps to 24…480")
    func zoom() throws {
        let axis = CalendarDayAxis(day: Self.thursday, calendar: Self.calendar, pointsPerHour: 72)
        let entry = try DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T10:30"))
        #expect(axis.frame(of: entry)?.height == 108)
        let zoomed = CalendarZoom.zoomedIn(72)
        #expect(zoomed == 90)
        let larger = CalendarDayAxis(day: Self.thursday, calendar: Self.calendar, pointsPerHour: zoomed)
        #expect(larger.frame(of: entry)?.height == 135)
        // The time at the viewport's center stays put.
        let offset = 600.0
        let anchor = 300.0
        let center = axis.date(atY: offset + anchor)
        let newOffset = CalendarZoom.scrollOffset(offset, anchor: anchor, from: 72, to: zoomed)
        #expect(abs(larger.date(atY: newOffset + anchor).timeIntervalSince(center)) < 1)
        // The now-line stays put while in view; else the center; a pinch's point wins.
        #expect(CalendarZoom.anchor(offset: 500, viewportHeight: 600, nowY: 720, pinchY: nil) == 220)
        #expect(CalendarZoom.anchor(offset: 1000, viewportHeight: 600, nowY: 144, pinchY: nil) == 300)
        #expect(CalendarZoom.anchor(offset: 500, viewportHeight: 600, nowY: 720, pinchY: 100) == 100)
        let kept = CalendarZoom.scrollOffset(500, anchor: 220, from: 72, to: 90)
        #expect(abs((720 * 90 / 72 - kept) - 220) < 1e-9)
        // Never past the end of the day.
        #expect(CalendarZoom.scrollOffset(1100, anchor: 300, from: 72, to: 48, maximum: 24 * 48 - 600) == 24 * 48 - 600)
        #expect(CalendarZoom.zoomedIn(470) == 480)
        #expect(CalendarZoom.zoomedOut(25) == 24)
        #expect(CalendarZoom.labelMinutes(pointsPerHour: 30) == 120)
        #expect(CalendarZoom.labelMinutes(pointsPerHour: 72) == 60)
        #expect(CalendarZoom.labelMinutes(pointsPerHour: 200) == 30)
        #expect(CalendarZoom.labelMinutes(pointsPerHour: 300) == 15)
        #expect(CalendarZoom.cardStyle(height: 10) == .bar)
        #expect(CalendarZoom.cardStyle(height: 20) == .oneLine)
        #expect(CalendarZoom.cardStyle(height: 40) == .full)
    }

    @Test(
        "PC-2 with today Thursday and room for 5 whole days, ⌘T makes Tuesday first, Monday for 7, Thursday for 1 and 2; the date menu"
    )
    func today() {
        #expect(CalendarStrip.firstDay(centering: Self.thursday, visibleDays: 5) == TrackingDay(year: 2026, month: 10, day: 27))
        #expect(CalendarStrip.firstDay(centering: Self.thursday, visibleDays: 7) == TrackingDay(year: 2026, month: 10, day: 26))
        #expect(CalendarStrip.firstDay(centering: Self.thursday, visibleDays: 1) == Self.thursday)
        #expect(CalendarStrip.firstDay(centering: Self.thursday, visibleDays: 2) == Self.thursday)
        // The whole days that fit decide; a cut-off day does not count.
        for (days, first) in [(5.0, 27), (5.9, 27), (7.2, 26), (1.0, 29), (2.5, 29), (0.5, 29)] {
            var viewport = CalendarViewport(firstDay: Self.thursday.adding(days: 30), offset: 0.3, dayWidth: 200, width: days * 200)
            viewport.center(Self.thursday)
            #expect(viewport.firstDay == TrackingDay(year: 2026, month: 10, day: first))
            #expect(viewport.offset == 0)
        }
        #expect(CalendarStrip.label(first: TrackingDay(year: 2026, month: 10, day: 26), count: 5) == "Mon, Oct 26 – Fri, Oct 30 · W44")
        let monday = TrackingDay(year: 2026, month: 10, day: 26)
        #expect(CalendarStrip.menuTitle(first: monday, count: 5, today: Self.thursday) == "Today")
        #expect(CalendarStrip.menuTitle(first: monday.adding(days: -7), count: 5, today: Self.thursday) == "Oct 19 – 23")
        #expect(CalendarStrip.menuTitle(first: monday.adding(days: 4), count: 5, today: Self.thursday) == "Oct 30 – Nov 3")
        #expect(CalendarStrip.menuTitle(first: monday.adding(days: -7), count: 1, today: Self.thursday) == "Oct 19")
    }

    @Test("PC-4 the day daylight-saving time ends is 25 hours tall; a 23:00 to 01:00 event is two pieces that move together")
    func daylightSaving() throws {
        let fallBack = TrackingDay(year: 2026, month: 11, day: 1)
        let axis = CalendarDayAxis(day: fallBack, calendar: Self.calendar, pointsPerHour: 72)
        #expect(axis.height == 25 * 72)
        let event = try DateInterval(start: Self.time("2026-10-29T23:00"), end: Self.time("2026-10-30T01:00"))
        let pieces = CalendarPiece.pieces(of: event, id: "e", calendar: Self.calendar)
        #expect(pieces.map(\.day) == [Self.thursday, Self.thursday.adding(days: 1)])
        #expect(pieces.map(\.interval.duration) == [3600, 3600])
        let moved = pieces[1].moved(by: 1800)
        #expect(moved == pieces[0].moved(by: 1800))
        #expect(moved.start == event.start + 1800)
    }

    @Test("PC-5 the now-line's offset is (now − the column's start) · pph / 3600, on today only")
    func nowLine() throws {
        let axis = CalendarDayAxis(day: Self.thursday, calendar: Self.calendar, pointsPerHour: 72)
        let now = try Self.time("2026-10-29T14:20")
        #expect(abs((axis.nowOffset(now) ?? 0) - (14 + 20.0 / 60) * 72) < 1)
        let tomorrow = CalendarDayAxis(day: Self.thursday.adding(days: 1), calendar: Self.calendar, pointsPerHour: 72)
        #expect(tomorrow.nowOffset(now) == nil)
    }

    @Test("PC-6 drawing 09:02 to 09:58 gives 09:00 to 10:00 (with ⌥ unchanged); under 1 minute creates nothing")
    func drawing() throws {
        let editing = try Self.editing()
        let drawn = try editing.draw(from: Self.time("2026-10-29T09:02"), to: Self.time("2026-10-29T09:58"))
        #expect(try drawn == .interval(DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T10:00"))))
        let option = try Self.editing(snap: 1)
        let exact = try option.draw(from: Self.time("2026-10-29T09:02"), to: Self.time("2026-10-29T09:58"))
        #expect(try exact == .interval(DateInterval(start: Self.time("2026-10-29T09:02"), end: Self.time("2026-10-29T09:58"))))
        #expect(try option.draw(from: Self.time("2026-10-29T09:02"), to: Self.time("2026-10-29T09:02:40")) == .tooShort)
        #expect(try editing.draw(from: Self.time("2026-10-29T09:02"), to: Self.time("2026-10-29T09:02:50")) == .tooShort)
    }

    @Test("PC-7 no draw, move, resize, or drop puts any part of an entry after now or past the column's end; a press below now is refused")
    func neverInFuture() throws {
        let editing = try Self.editing()
        let now = editing.now
        #expect(try editing.draw(from: Self.time("2026-10-29T15:00"), to: Self.time("2026-10-29T16:00")) == .future)
        guard case let .interval(clamped) = try editing.draw(from: Self.time("2026-10-29T13:00"), to: Self.time("2026-10-29T16:00")) else {
            Issue.record("expected an interval")
            return
        }
        #expect(clamped.end == now)
        let entry = try DateInterval(start: Self.time("2026-10-29T13:00"), end: Self.time("2026-10-29T14:00"))
        #expect(editing.move(entry, by: 3 * 3600)?.end == now)
        #expect(editing.resizeEnd(entry, to: now + 3600).end == now)
        #expect(editing.move(entry, by: -20 * 3600)?.start == editing.day.start)
        let tomorrow = CalendarEditing(
            day: Self.calendar.interval(of: Self.thursday.adding(days: 1)),
            now: now,
            snap: CalendarSnap(minutes: 5)
        )
        #expect(tomorrow.move(entry, by: 86_400) == nil)
        let yesterday = CalendarEditing(
            day: Self.calendar.interval(of: Self.thursday.adding(days: -1)),
            now: now,
            snap: CalendarSnap(minutes: 5)
        )
        let late = try DateInterval(start: Self.time("2026-10-28T23:00"), end: Self.time("2026-10-28T23:50"))
        #expect(yesterday.move(late, by: 3600)?.end == yesterday.day.end)
        #expect(yesterday.lengthen(late, steps: 30).end == yesterday.day.end)
        #expect(editing.moveRunningStart(to: now) == now - 60)
        #expect(CalendarEditing.futureNotice == "Entries can't be in the future")
    }

    @Test("PC-8 a 7 minute move with 5 minute snapping lands on a 5 minute mark with the duration kept; resizing stops at 1 minute")
    func moveAndResize() throws {
        let editing = try Self.editing()
        let entry = try DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T10:00"))
        let moved = try #require(editing.move(entry, by: 7 * 60))
        #expect(try moved.start == Self.time("2026-10-29T09:05"))
        #expect(moved.duration == 3600)
        let shrunk = try editing.resizeEnd(entry, to: Self.time("2026-10-29T08:00"))
        #expect(shrunk.duration == 60)
        let fromTop = try editing.resizeStart(entry, to: Self.time("2026-10-29T11:00"))
        #expect(fromTop.duration == 60)
        #expect(try editing.move(entry, by: 300)?.start == Self.time("2026-10-29T09:05"))
    }

    @Test("PC-9 a 12 minute overlap asks Trim / Overlap / Cancel; 1 minute or less trims silently; overlapping cards go side by side")
    func overlaps() throws {
        let standup = try OverlapNeighbor(
            id: EntryID(),
            title: "Standup",
            interval: DateInterval(start: Self.time("2026-10-29T11:00"), end: Self.time("2026-10-29T11:30"))
        )
        let changed = try DateInterval(start: Self.time("2026-10-29T10:00"), end: Self.time("2026-10-29T11:12"))
        guard case let .ask(prompt) = OverlapResolution.resolve(changed, neighbors: [standup]) else {
            Issue.record("expected a prompt")
            return
        }
        #expect(prompt.overlapSeconds == 720)
        #expect(prompt.text(in: Self.zone) == "Overlaps \"Standup\" (11:00 to 11:30) by 12 min.")
        #expect(try prompt.trimmed == DateInterval(start: Self.time("2026-10-29T10:00"), end: Self.time("2026-10-29T11:00")))
        #expect(prompt.proposed == changed)
        let slight = try DateInterval(start: Self.time("2026-10-29T10:00"), end: Self.time("2026-10-29T11:01"))
        #expect(try OverlapResolution.resolve(slight, neighbors: [standup]) == .trimmedSilently(DateInterval(
            start: Self.time("2026-10-29T10:00"),
            end: Self.time("2026-10-29T11:00")
        )))
        #expect(OverlapResolution.resolve(slight, neighbors: []) == .clear(slight))
        let lanes = CalendarLane.assign([("a", changed), ("b", standup.interval)])
        #expect(lanes["a"] == CalendarLane(index: 0, count: 2))
        #expect(lanes["b"] == CalendarLane(index: 1, count: 2))
        #expect(CalendarLane.overlapping([("a", changed), ("b", standup.interval)]) == ["a", "b"])
    }

    @Test("PC-11 Split Here is refused within 1 minute of either end; Duplicate to Next Day only when the copy is entirely past")
    func splitAndDuplicate() throws {
        let start = try Self.time("2026-10-28T09:00")
        let end = try Self.time("2026-10-28T11:00")
        let now = try Self.time("2026-10-29T14:20")
        #expect(try CalendarEditing.canSplit(start: start, end: end, at: Self.time("2026-10-28T10:00"), now: now))
        #expect(try !CalendarEditing.canSplit(start: start, end: end, at: Self.time("2026-10-28T10:59:30"), now: now))
        #expect(!CalendarEditing.canSplit(start: start, end: nil, at: now - 30, now: now))
        #expect(try CalendarEditing.duplicateToNextDay(DateInterval(start: start, end: end), in: Self.zone, now: now)?.start == Self
            .time("2026-10-29T09:00"))
        let late = try DateInterval(start: Self.time("2026-10-28T13:00"), end: Self.time("2026-10-28T15:00"))
        #expect(CalendarEditing.duplicateToNextDay(late, in: Self.zone, now: now) == nil)
    }

    @Test("PC-12 a block half covered by entries is dimmed on that half")
    func coverage() throws {
        let block = try DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T10:00"))
        let entry = try DateInterval(start: Self.time("2026-10-29T09:30"), end: Self.time("2026-10-29T11:00"))
        let late = try DateInterval(start: Self.time("2026-10-29T09:30"), end: Self.time("2026-10-29T10:00"))
        let early = try DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T09:30"))
        #expect(CalendarCoverage.covered(block, by: [entry]) == [late])
        #expect(CalendarCoverage.uncovered(block, by: [entry]) == [early])
    }

    @Test("PC-13 the + on a 09:10 to 09:44 block with its first 20 minutes covered proposes 09:30 to 09:44")
    func longestUntracked() throws {
        let block = try DateInterval(start: Self.time("2026-10-29T09:10"), end: Self.time("2026-10-29T09:44"))
        let entry = try DateInterval(start: Self.time("2026-10-29T09:00"), end: Self.time("2026-10-29T09:30"))
        let stretch = try CalendarCoverage.longestUntracked(block, entries: [entry], now: Self.time("2026-10-29T14:20"))
        #expect(try stretch == DateInterval(start: Self.time("2026-10-29T09:30"), end: Self.time("2026-10-29T09:44")))
        let open = try CalendarCoverage.longestUntracked(block, entries: [], now: Self.time("2026-10-29T09:40"))
        #expect(try open?.end == (Self.time("2026-10-29T09:40")))
    }

    @Test("PC-12 summary strip and day headers total tracked time by project, time blocks, and activity")
    func summary() throws {
        let entry = try TimeEntry(
            projectID: nil,
            task: "",
            start: Self.time("2026-10-29T09:00"),
            end: Self.time("2026-10-29T10:00"),
            timeZone: Self.zone.identifier,
            deviceID: DeviceID(),
            createdAt: .now,
            modifiedAt: .now
        )
        let block = try ActivityBlock(
            start: Self.time("2026-10-29T09:00"),
            end: Self.time("2026-10-29T09:30"),
            activeSeconds: 1500,
            devices: [ActivityDeviceTime(name: "macbook", seconds: 1500)],
            groupKey: "safari",
            groupShare: 1,
            items: [],
            utcOffset: -4 * 3600
        )
        let timeBlock = try DateInterval(start: Self.time("2026-10-29T23:00"), end: Self.time("2026-10-30T01:00"))
        let summary = try CalendarSummary(
            days: [Self.thursday, Self.thursday.adding(days: 1)],
            calendar: Self.calendar,
            entries: [EntryListing(entry: entry, project: nil, area: nil, client: nil)],
            activity: [block],
            timeBlocks: [timeBlock],
            now: Self.time("2026-10-30T14:00")
        )
        #expect(summary.tracked == 3600)
        #expect(summary.blocks == 7200)
        #expect(summary.activity == 1500)
        #expect(summary.days[Self.thursday]?.text(columns: CalendarColumn.allCases) == ["25m", "1h", "1h"])
        #expect(summary.segments.map(\.name) == ["No project"])
        let widths = CalendarColumn.widths(dayWidth: 270, visible: CalendarColumn.allCases)
        #expect(widths[.tracked] == 120)
        #expect(CalendarColumn.drawsBars(width: widths[.activity] ?? 0))
    }
}

extension CalendarGeometryTests {
    @Test("PC-35 an all-day event belongs to its calendar dates, whatever the shown days are")
    func allDayDates() throws {
        // As EventKit gives it: the last second of the last date ends it.
        let oneDay = try CalendarEvent(
            id: "e",
            calendarID: "c",
            title: "Holiday",
            start: Self.time("2026-10-29T00:00"),
            end: Self.time("2026-10-29T23:59:59"),
            isAllDay: true
        )
        #expect(oneDay.isAllDay(on: Self.thursday, in: Self.zone))
        #expect(!oneDay.isAllDay(on: Self.thursday.adding(days: -1), in: Self.zone))
        #expect(!oneDay.isAllDay(on: Self.thursday.adding(days: 1), in: Self.zone))
        // A store may end it at the next midnight instead.
        var twoDays = oneDay
        twoDays.end = try Self.time("2026-10-31T00:00")
        #expect(twoDays.isAllDay(on: Self.thursday.adding(days: 1), in: Self.zone))
        #expect(!twoDays.isAllDay(on: Self.thursday.adding(days: 2), in: Self.zone))
        var timed = oneDay
        timed.isAllDay = false
        #expect(!timed.isAllDay(on: Self.thursday, in: Self.zone))
    }

    @Test("PC-38 the column at a point of the viewport, none outside it or where the columns end")
    func dropTargets() {
        let viewport = CalendarViewport(firstDay: Self.thursday, dayWidth: 450, width: 900)
        let all = CalendarColumn.allCases
        #expect(CalendarColumn.x(of: .activity, dayWidth: 450, visible: all) == 0)
        #expect(CalendarColumn.x(of: .tracked, dayWidth: 450, visible: all) == 100)
        #expect(CalendarColumn.x(of: .calendar, dayWidth: 450, visible: all) == 300)
        #expect(viewport.target(atX: 99, columns: all) == CalendarDropTarget(day: Self.thursday, column: .activity))
        #expect(viewport.target(atX: 100, columns: all) == CalendarDropTarget(day: Self.thursday, column: .tracked))
        #expect(viewport.target(atX: 449, columns: all) == CalendarDropTarget(day: Self.thursday, column: .calendar))
        let friday = Self.thursday.adding(days: 1)
        #expect(viewport.target(atX: 600, columns: all) == CalendarDropTarget(day: friday, column: .tracked))
        #expect(viewport.target(atX: -1, columns: all) == nil)
        #expect(viewport.target(atX: 900, columns: all) == nil)
        // A hidden column gives its width to the others.
        #expect(viewport.target(atX: 10, columns: [.tracked]) == CalendarDropTarget(day: Self.thursday, column: .tracked))
    }
}
