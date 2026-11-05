// The Timer list's query (timer.md §3).

import Foundation
import Testing
import TimeTrackingCore

struct TimerListTests {
    @Test("TM-15 identical consecutive entries are two rows; 14 days with entries load, then 14 more")
    func daysAndRows() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        // One entry on each of 30 days, every other day, newest first.
        for offset in 0 ..< 30 {
            let start = try test.date("2024-03-14T08:00") - TimeInterval(offset * 2 * 86_400)
            _ = try await test.store.create(EntryDraft(projectID: nil, task: "Day \(offset)", start: start, end: start + 60))
        }
        let today = try test.date("2024-03-14T08:30")
        _ = try await test.store.create(EntryDraft(projectID: nil, task: "Same", start: today, end: today + 60))
        _ = try await test.store.create(EntryDraft(projectID: nil, task: "Same", start: today + 60, end: today + 120))

        let list = try await test.store.timerList(dayLimit: 14)
        #expect(list.count == 14)
        #expect(list.first?.rows.map(\.entry.task) == ["Same", "Same", "Day 0"])
        #expect(list.first?.stoppedSeconds == 180)
        // Empty days are omitted.
        #expect(list[1].day == TrackingDay(year: 2024, month: 3, day: 12))
        let more = try await test.store.timerList(dayLimit: 28)
        #expect(more.count == 28)
        #expect(Array(more.prefix(14)) == list)
    }

    @Test("TM-17 a filter keeps entries matching task, project, client, or area, and totals sum them")
    func filter() async throws {
        let test = try await TestStore(now: "2024-03-14T10:00")
        let structure = try await test.structure(projects: ["Noise Model", "Website"])
        let start = try test.date("2024-03-14T08:00")
        _ = try await test.store.create(EntryDraft(projectID: structure.projects[0].id, task: "Draft", start: start, end: start + 600))
        _ = try await test.store.create(EntryDraft(
            projectID: structure.projects[1].id,
            task: "Fix nöise",
            start: start + 600,
            end: start + 900
        ))
        _ = try await test.store.create(EntryDraft(
            projectID: structure.projects[1].id,
            task: "Deploy",
            start: start + 900,
            end: start + 1000
        ))
        _ = try await test.store.start(projectID: structure.projects[1].id, task: "Other", at: start + 1200)
        let list = try await test.store.timerList(dayLimit: 14, filter: "NOISE")
        #expect(list.count == 1)
        #expect(list[0].rows.map(\.entry.task) == ["Fix nöise", "Draft"])
        #expect(list[0].running == nil)
        #expect(list[0].totalSeconds(at: test.clock.now) == 900)
        // Unfiltered: the running entry counts toward the total and ticks.
        let all = try await test.store.timerList(dayLimit: 14)
        #expect(all[0].rows.count == 3)
        #expect(all[0].totalSeconds(at: test.clock.now) == 1000 + 6000)
        #expect(all[0].totalSeconds(at: test.clock.now + 1) == 1000 + 6001)
        // Area and client names match too.
        #expect(try await test.store.timerList(dayLimit: 14, filter: "research").first?.rows.count == 3)
    }
}
