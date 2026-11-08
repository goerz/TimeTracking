// The Activity section's bar chart: stacking, the open block, tooltips,
// segments under the pointer, and the arrow keys (activity.md §1.5, §1.9, §2, §3).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityBarsTests {
    @Test("PA-10 bars merge apps beyond the twelfth into Other apps and, without a filter, equal the day's active time")
    func stacking() throws {
        let items = (1 ... 14).map { (ActivityFixture.app("App\($0)"), 3000 - $0 * 100) }
        let block = try ActivityFixture.block("2024-03-11", "08:00", "18:00", items)
        let bars = SectionFixture.summary([block]).bars
        #expect(bars.granularity == .day)
        #expect(bars.series.count == 13)
        #expect(Array(bars.series.prefix(12)) == (1 ... 12).map { ActivityBars.Series.app("App\($0)") })
        #expect(bars.series.last == .otherApps)
        #expect(ActivityBars.Series.otherApps.title == "Other apps")
        let monday = bars.bars[0]
        #expect(monday.seconds == block.activeSeconds)
        #expect(monday.segments.last?.series == .otherApps)
        #expect(monday.segments.last?.seconds == 1700 + 1600)
        // 8h 45m rounds up to 10 hours, the next even hour.
        #expect(bars.axisHours == 10)
        let filtered = SectionFixture.summary([block], apps: ["App1", "App14"]).bars
        #expect(filtered.series == [.app("App1"), .app("App14")])
        #expect(filtered.bars[0].seconds == 2900 + 1600)

        func days(_ first: TrackingDay, _ last: TrackingDay) -> [TrackingDay] {
            ActivitySummary.days(first ... last)
        }
        #expect(ActivityBars
            .granularity(days: days(TrackingDay(year: 2024, month: 1, day: 1), TrackingDay(year: 2024, month: 1, day: 31))) == .day)
        #expect(ActivityBars
            .granularity(days: days(TrackingDay(year: 2024, month: 1, day: 1), TrackingDay(year: 2024, month: 2, day: 1))) == .week)
        // 366 days over 53 ISO weeks still get week bars; over 54, month bars.
        #expect(ActivityBars.granularity(days: days(TrackingDay(year: 2023, month: 3, day: 15), SectionFixture.thursday)) == .week)
        let year = TrackingDay(year: 2023, month: 3, day: 19) ... TrackingDay(year: 2024, month: 3, day: 18)
        #expect(ActivityBars.granularity(days: ActivitySummary.days(year)) == .month)
        let weeks = SectionFixture.summary([block], days: TrackingDay(year: 2024, month: 2, day: 1) ... SectionFixture.thursday).bars
        #expect(weeks.bars.first?.label == "W5")
        #expect(weeks.bars.last?.label == "W11")
        #expect(weeks.bars.last?.seconds == block.activeSeconds)
        let months = SectionFixture.summary([block], days: year).bars
        #expect(months.bars.count == 13)
        #expect(months.bars.first?.title == "March 2023")
        #expect(months.bars.last?.label == "Mar")
    }

    @Test("PA-11 today's bar includes the open block until the closed block replaces it, with a change on the append")
    func openBlockReplaced() async throws {
        let now = try ActivityFixture.instant("2024-03-14T09:20:00-04:00")
        let open = try SectionFixture.opened(ActivityFixture.block("2024-03-14", "09:00", "09:20", [(SectionFixture.mail, 1200)]))
        let memory = InMemoryActivityStore(trackerState: SectionFixture.trackerState(block: open, lastTick: now))
        let reader: any ActivityReading = memory
        let interval = SectionFixture.interval(SectionFixture.week)
        var changes = reader.changes.makeAsyncIterator()
        let before = try await SectionFixture.summary(reader.blocks(in: interval, devices: nil)).bars.bars[3]
        #expect(before.seconds == 1200)
        #expect(before.openSeconds == 1200)
        let closed = try ActivityFixture.block("2024-03-14", "09:00", "09:25", [(SectionFixture.mail, 1500)])
        memory.append([closed])
        #expect(await changes.next() == .blocks(day: SectionFixture.thursday))
        let read = try await reader.blocks(in: interval, devices: nil)
        #expect(read == [closed])
        let after = SectionFixture.summary(read).bars.bars[3]
        #expect(after.seconds == 1500)
        #expect(after.openSeconds == 0)
    }

    @Test(
        "PA-11 PA-24 the reader keeps an open block that starts when the last closed block ended"
    )
    func openBlockAfterTouchingBlock() async throws {
        let now = try ActivityFixture.instant("2024-03-14T09:20:00-04:00")
        let closed = try ActivityFixture.block("2024-03-14", "08:00", "09:00", [(SectionFixture.mail, 3600)], reason: .split)
        let open = try SectionFixture.opened(ActivityFixture.block("2024-03-14", "09:00", "09:20", [(ActivityFixture.terminal(), 1200)]))
        let reader: any ActivityReading = InMemoryActivityStore(
            blocks: [closed],
            trackerState: SectionFixture.trackerState(block: open, lastTick: now)
        )
        let read = try await reader.blocks(in: SectionFixture.interval(SectionFixture.week), devices: nil)
        #expect(read == [closed, open])
        let bar = SectionFixture.summary(read).bars.bars[3]
        #expect(bar.seconds == 4800)
        #expect(bar.openRange == 3600 ... 4800)
    }

    @Test(
        "PA-24 today's bar marks the open block's part as the top of its stack, also under a filter; a bar without an open block has none"
    )
    func openBlockOnTop() throws {
        let closed = try ActivityFixture.block("2024-03-14", "08:00", "09:00", [(SectionFixture.mail, 1800)])
        let page = SectionFixture.page("https://arxiv.org/abs/2401.00001", window: "arXiv", workspace: "arxiv.org")
        let open = try SectionFixture.opened(ActivityFixture.block(
            "2024-03-14",
            "09:00",
            "09:20",
            [(page, 1000), (SectionFixture.mail, 100)]
        ))
        let bar = SectionFixture.summary([closed, open]).bars.bars[3]
        #expect(bar.seconds == 2900)
        #expect(bar.openSeconds == 1100)
        #expect(bar.openRange == 1800 ... 2900)
        let safari = SectionFixture.summary([closed, open], apps: ["Safari"]).bars.bars[3]
        #expect(safari.openRange == 0 ... 1000)
        let mail = SectionFixture.summary([closed, open], apps: ["Mail"]).bars.bars[3]
        #expect(mail.openRange == 1800 ... 1900)
        let bars = SectionFixture.summary([closed]).bars.bars
        #expect(bars.allSatisfy { $0.openRange == nil })
    }

    @Test(
        "PA-25 a segment shows its day, name, and time of the total; a bar its total and three largest apps; a future bar nothing"
    )
    func tooltips() throws {
        let block = try ActivityFixture.block("2024-03-14", "08:00", "12:00", [
            (SectionFixture.mail, 600), (ActivityFixture.terminal(), 7200),
            (SectionFixture.page("https://arxiv.org/abs/2401.00001", window: "arXiv", workspace: "arxiv.org"), 3600),
            (SectionFixture.skim, 1200),
        ])
        let bars = SectionFixture.summary([block]).bars
        let name = { (app: String) in app == "Mail" ? "Apple Mail" : app }
        let thursday = bars.bars[3].id
        #expect(bars
            .tooltip(of: .init(bar: thursday, series: .app("Mail")), displayName: name) == "Thu Mar 14 · Apple Mail · 10m of 3h 30m")
        #expect(bars.tooltip(of: .init(bar: thursday), displayName: name) == "Thu Mar 14 · 3h 30m · WezTerm 2h, Safari 1h, Skim 20m")
        #expect(bars.tooltip(of: .init(bar: bars.bars[2].id), displayName: name) == "Wed Mar 13 · 0h")
        #expect(bars.tooltip(of: .init(bar: bars.bars[4].id), displayName: name) == nil)
    }

    @Test("PA-26 a point in a bar finds its segment bottom up, the gray layer included; beside the stack there is none")
    func segmentUnderPointer() throws {
        let block = try ActivityFixture.block("2024-03-14", "08:00", "09:00", [
            (SectionFixture.page("https://arxiv.org/abs/2401.00001", window: "arXiv", workspace: "arxiv.org"), 1000),
            (SectionFixture.mail, 500),
        ])
        let bar = SectionFixture.summary([block]).bars.bars[3]
        #expect(bar.series(atSeconds: 0) == .app("Safari"))
        #expect(bar.series(atSeconds: 999) == .app("Safari"))
        #expect(bar.series(atSeconds: 1000) == .app("Mail"))
        #expect(bar.series(atSeconds: 1499) == .app("Mail"))
        #expect(bar.series(atSeconds: 1500) == nil)
        #expect(bar.series(atSeconds: -1) == nil)
        let many = try ActivityFixture.block(
            "2024-03-14",
            "08:00",
            "18:00",
            (1 ... 13).map { (ActivityFixture.app("App\($0)"), 2000 - $0 * 10) }
        )
        let full = SectionFixture.summary([many]).bars.bars[3]
        #expect(full.series(atSeconds: Double(full.seconds) - 1) == .otherApps)
    }

    @Test(
        "PA-28 left and right move between bars keeping the app; up and down move through the segments and back to the bar"
    )
    func barsFocus() throws {
        let page = SectionFixture.page("https://arxiv.org/abs/2401.00001", window: "arXiv", workspace: "arxiv.org")
        let blocks = try [
            ActivityFixture.block("2024-03-13", "08:00", "09:00", [(page, 1000)]),
            ActivityFixture.block("2024-03-14", "08:00", "09:00", [(SectionFixture.mail, 500), (page, 1000)]),
        ]
        let bars = SectionFixture.summary(blocks).bars
        let monday = bars.bars[0].id
        let wednesday = bars.bars[2].id
        let thursday = bars.bars[3].id
        let sunday = bars.bars[6].id
        #expect(bars.firstTarget == .init(bar: monday))
        #expect(bars.target(.right, from: nil) == .init(bar: monday))
        #expect(bars.target(.left, from: .init(bar: monday)) == .init(bar: monday))
        #expect(bars.target(.right, from: .init(bar: wednesday)) == .init(bar: thursday))
        #expect(bars.target(.right, from: .init(bar: sunday)) == .init(bar: sunday))
        let safari = ActivityBars.Target(bar: thursday, series: .app("Safari"))
        let mail = ActivityBars.Target(bar: thursday, series: .app("Mail"))
        #expect(bars.target(.above, from: .init(bar: thursday)) == safari)
        #expect(bars.target(.above, from: safari) == mail)
        #expect(bars.target(.above, from: mail) == mail)
        #expect(bars.target(.below, from: mail) == safari)
        #expect(bars.target(.below, from: safari) == .init(bar: thursday))
        #expect(bars.target(.below, from: .init(bar: thursday)) == .init(bar: thursday))
        // Wednesday has Safari but no Mail.
        #expect(bars.target(.left, from: safari) == .init(bar: wednesday, series: .app("Safari")))
        #expect(bars.target(.left, from: mail) == .init(bar: wednesday))
    }
}
