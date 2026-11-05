// The midnight split, the chain, and the invariant pass (spec_data_and_sync.md §1.5, §3.3, §8; §9 items 17 to 23, 46).

import Foundation
import Testing
import TimeTrackingCore

struct MidnightSplitTests {
    private func pieceID(_ root: EntryID, _ date: String) -> EntryID {
        EntryID(UUID.version5(namespace: root.uuid, name: "split:\(date)"))
    }

    @Test("DATA-17 a create across midnight in Europe/Berlin keeps the id until 00:00 and adds a derived piece")
    func createAcrossMidnight() async throws {
        let test = try await TestStore(now: "2026-03-03T10:00")
        let id = EntryID()
        let pieces = try await test.store.create(EntryDraft(
            id: id,
            projectID: nil,
            task: "Late",
            start: test.date("2026-03-02T22:00"),
            end: test.date("2026-03-03T01:30")
        ))
        #expect(pieces.count == 2)
        #expect(pieces[0].id == id)
        #expect(try pieces[0].end == (test.date("2026-03-03T00:00")))
        #expect(pieces[0].day.description == "2026-03-02")
        let piece = pieces[1]
        #expect(piece.id == pieceID(id, "2026-03-03"))
        #expect(try piece.start == (test.date("2026-03-03T00:00")))
        #expect(try piece.end == (test.date("2026-03-03T01:30")))
        #expect(piece.splitRootID == id)
        #expect(piece.createdAt == piece.start)
        #expect(piece.task == "Late")
        #expect(piece.timeZone == "Europe/Berlin")
        #expect(piece.deviceID == test.deviceID)
        #expect(piece.day.description == "2026-03-03")
        #expect(try await test.store.entry(piece.id) == piece)
    }

    @Test("DATA-18 a running entry is split when the clock passes midnight; the chain start stays")
    func runningSplitsAtMidnight() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let entry = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-03T00:10"))
        #expect(try await test.store.nextMidnightSplit() == (test.date("2026-03-03T00:00")))
        try await test.store.checkInvariants()
        let running = try #require(try await test.store.runningEntry())
        #expect(running.id == pieceID(entry.id, "2026-03-03"))
        #expect(try await test.store.chainStart(of: running.id) == (test.date("2026-03-02T23:00")))
        #expect(try await test.store.entry(entry.id)?.end == (test.date("2026-03-03T00:00")))
    }

    @Test("DATA-19 a wake two days later yields three pieces; a night-by-night split gives identical pieces")
    func wakeAfterTwoNights() async throws {
        let monday = "2026-10-26T22:00"
        let wake = try await TestStore(now: "2026-10-26T22:00")
        let entry = try await wake.store.start(projectID: nil, task: "Long", at: wake.date(monday))
        let nightly = try await TestStore(now: "2026-10-26T22:00", deviceID: wake.deviceID)
        let document = try await wake.store.exportDocument()
        _ = try await nightly.store.importDocument(document, options: ImportOptions())
        for time in ["2026-10-27T00:00:01", "2026-10-28T00:00:01", "2026-10-28T10:00"] {
            try nightly.clock.set(nightly.date(time))
            try await nightly.store.checkInvariants()
        }
        try wake.clock.set(wake.date("2026-10-28T10:00"))
        try await wake.store.checkInvariants()
        let interval = try DateInterval(start: wake.date("2026-10-26T00:00"), end: wake.date("2026-10-29T00:00"))
        let pieces = try await wake.store.entries(in: interval)
        #expect(pieces.map(\.id) == [entry.id, pieceID(entry.id, "2026-10-27"), pieceID(entry.id, "2026-10-28")])
        #expect(pieces.last?.isRunning == true)
        let other = try await nightly.store.entries(in: interval)
        #expect(other.map(\.id) == pieces.map(\.id))
        #expect(other.map(\.start) == pieces.map(\.start))
        #expect(other.map(\.end) == pieces.map(\.end))
        #expect(other.map(\.createdAt) == pieces.map(\.createdAt))
    }

    @Test("DATA-20 editing an end past midnight creates the continuation; pieces are independent; 00:00 does not split")
    func editingAcrossMidnight() async throws {
        let test = try await TestStore(now: "2026-03-03T10:00")
        let store = test.store
        let entry = try await store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2026-03-02T22:00"),
            end: test.date("2026-03-02T23:30")
        ))[0]
        let pieces = try await store.update(entry.id, EntryChange(end: test.date("2026-03-03T00:45")))
        #expect(pieces.map(\.id) == [entry.id, pieceID(entry.id, "2026-03-03")])
        _ = try await store.update(pieces[1].id, EntryChange(task: "Continued"))
        #expect(try await store.entry(entry.id)?.task.isEmpty == true)
        try await store.delete([pieces[1].id])
        #expect(try await store.entry(entry.id) != nil)
        let exact = try await store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2026-03-02T20:00"),
            end: test.date("2026-03-03T00:00")
        ))
        #expect(exact.count == 1)
        // The tombstoned derived id stays deleted when the original is extended again.
        let again = try await store.update(entry.id, EntryChange(end: test.date("2026-03-03T01:00")))
        #expect(again.map(\.id) == [entry.id])
        #expect(try await store.entry(pieces[1].id) == nil)
        #expect(try await store.entry(entry.id)?.end == (test.date("2026-03-03T00:00")))
    }

    @Test("DATA-21 in America/Sao_Paulo the 2018-11-04 day starts at 01:00 and the split happens there")
    func midnightlessDay() async throws {
        let test = try await TestStore(now: "2018-11-05T10:00", zone: "America/Sao_Paulo")
        let pieces = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2018-11-03T22:00"),
            end: test.date("2018-11-04T02:00")
        ))
        #expect(pieces.count == 2)
        let calendar = TrackingCalendar(timeZone: test.zone)
        #expect(calendar.startOfDay(TrackingDay(year: 2018, month: 11, day: 4)) == pieces[1].start)
        #expect(pieces[0].end == pieces[1].start)
        #expect(pieces[1].end?.timeIntervalSince(pieces[1].start) == 3600)
        #expect(pieces[0].end?.timeIntervalSince(pieces[0].start) == 7200)
    }

    @Test("DATA-22 a New York entry is not split on a device in Berlin and keeps its New York day")
    func ownZone() async throws {
        let test = try await TestStore(now: "2026-10-29T12:00")
        let york = try #require(TimeZone(identifier: "America/New_York"))
        let pieces = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: TestStore.date("2026-10-27T20:00", york),
            end: TestStore.date("2026-10-27T23:00", york),
            timeZone: "America/New_York"
        ))
        #expect(pieces.count == 1)
        #expect(pieces[0].day.description == "2026-10-27")
        #expect(try await test.store.entries(on: TrackingDay(year: 2026, month: 10, day: 27)).count == 1)
    }

    @Test("DATA-23 several running entries reduce to the latest start; equal starts keep the greater root; idempotent")
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

    @Test("TM-49 a chain stopped before its running piece ends there: the pieces from that time on are removed, across several midnights")
    func stopChainBackAcrossMidnights() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let root = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-04T00:30"))
        try await test.store.checkInvariants()
        let stop = try test.date("2026-03-02T23:50")
        let stopped = try await test.store.transaction { try $0.stop(chainOf: root.id, at: stop) }
        #expect(stopped?.id == root.id && stopped?.end == stop)
        #expect(try await test.store.runningEntry() == nil)
        #expect(try await test.store.chain(of: root.id).map(\.id) == [root.id])
        // The next pass brings nothing back.
        try await test.store.checkInvariants()
        #expect(try await test.store.entry(pieceID(root.id, "2026-03-03")) == nil)
        #expect(try await test.store.entry(pieceID(root.id, "2026-03-04")) == nil)
    }

    @Test("TM-49 a chain stopped at midnight keeps the piece before it; a chain never stops before its start")
    func stopChainBackInsidePieces() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let root = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-04T00:30"))
        try await test.store.checkInvariants()
        let midnight = try test.date("2026-03-03T00:00")
        let stopped = try await test.store.transaction { try $0.stop(chainOf: root.id, at: midnight) }
        #expect(stopped?.id == root.id && stopped?.end == midnight)

        let other = try await test.store.start(projectID: nil, task: "Dawn", at: test.date("2026-03-03T23:40"))
        try test.clock.set(test.date("2026-03-04T00:50"))
        try await test.store.checkInvariants()
        let start = try test.date("2026-03-03T23:40")
        let early = try test.date("2026-03-03T22:00")
        let clamped = try await test.store.transaction { try $0.stop(chainOf: other.id, at: early) }
        #expect(clamped?.id == other.id && clamped?.end == start)
        #expect(try await test.store.chain(of: other.id).count == 1)
    }

    @Test("TM-49 a chain stopped inside its running piece stops as a plain stop, keeping the earlier pieces")
    func stopChainInsideRunningPiece() async throws {
        let test = try await TestStore(now: "2026-03-02T23:30")
        let root = try await test.store.start(projectID: nil, task: "Night", at: test.date("2026-03-02T23:00"))
        try test.clock.set(test.date("2026-03-03T00:30"))
        try await test.store.checkInvariants()
        let stop = try test.date("2026-03-03T00:10")
        let stopped = try await test.store.transaction { try $0.stop(chainOf: root.id, at: stop) }
        #expect(stopped?.id == pieceID(root.id, "2026-03-03") && stopped?.end == stop)
        #expect(try await test.store.chain(of: root.id).count == 2)
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
}
