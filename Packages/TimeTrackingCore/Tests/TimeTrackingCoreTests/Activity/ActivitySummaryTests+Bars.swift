// Tests of the Activity bars' open block, tooltips, and segments, and the
// keyboard focus on the heatmap and the bars (spec_activity.md §6).

import Foundation
import Testing
import TimeTrackingCore

extension ActivitySummaryTests {
    @Test("PA-24 today's bar marks the open block's part as the top of its stack, also under a filter")
    func openBlockIsTheTopOfTheStack() throws {
        let closed = try Self.block("2026-10-29", "08:00", "09:00", [Self.item("mail", 1800)], active: 2000)
        let items = [Self.item("safari", 1000), Self.item("mail", 100)]
        let open = try Self.block("2026-10-29", "09:00", "09:20", items, active: 1200, isOpen: true)
        let bar = Self.summary([closed, open]).bars.bars[3]
        #expect(bar.seconds == 3200)
        #expect(bar.openRange == 2000 ... 3200)
        let filtered = Self.summary([closed, open], contexts: ["safari"]).bars.bars[3]
        #expect(filtered.openRange == 0 ... 1000)
        #expect(Self.summary([closed]).bars.bars[3].openRange == nil)
    }

    @Test("PA-25 hovering a segment names it with its time; a label or empty area gives the total and the three largest contexts")
    func barTooltips() throws {
        let block = try Self.block(
            "2026-10-29",
            "08:00",
            "12:00",
            [Self.item("mail", 600), Self.item("tmux:paper", 7200), Self.item("safari", 3600), Self.item("skim", 1200)],
            active: 13_200
        )
        let bars = Self.summary([block]).bars
        let thursday = bars.bars[3]
        let name = { (context: String) in context == "mail" ? "Apple Mail" : ActivityContext(context).displayName() }
        let mail = ActivityBars.Target(bar: thursday.id, series: .context("mail"))
        #expect(bars.tooltip(of: mail, displayName: name) == "Thu Oct 29 · Apple Mail · 10m of 3h 40m")
        let brief = ActivityBars.Target(bar: thursday.id, series: .notItemized)
        #expect(bars.tooltip(of: brief, displayName: name) == "Thu Oct 29 · Brief activity · 10m of 3h 40m")
        #expect(bars.tooltip(of: .init(bar: thursday.id), displayName: name) == "Thu Oct 29 · 3h 40m · paper 2h, Safari 1h, Skim 20m")
        let friday = bars.bars[4]
        #expect(bars.tooltip(of: .init(bar: friday.id), displayName: name) == nil)
        let wednesday = bars.bars[2]
        #expect(bars.tooltip(of: .init(bar: wednesday.id), displayName: name) == "Wed Oct 28 · 0h")
    }

    @Test("PA-26 a height in a bar finds the segment there, bottom up; outside the stack there is none")
    func segmentAtHeight() throws {
        let block = try Self.block("2026-10-29", "08:00", "09:00", [Self.item("safari", 1000), Self.item("mail", 500)], active: 2000)
        let bar = Self.summary([block]).bars.bars[3]
        #expect(bar.series(atSeconds: 0) == .context("safari"))
        #expect(bar.series(atSeconds: 999) == .context("safari"))
        #expect(bar.series(atSeconds: 1000) == .context("mail"))
        #expect(bar.series(atSeconds: 1500) == .notItemized)
        #expect(bar.series(atSeconds: 2000) == nil)
        #expect(bar.series(atSeconds: -1) == nil)
    }

    @Test("PA-27 the arrow keys walk the heatmap in column order, through the All row, and stop at the edges")
    func heatmapFocus() throws {
        let block = try Self.block("2026-10-29", "08:00", "09:00", [Self.item("mail", 600)])
        let days = ActivityHeatmap.Cell(row: "day:2026-10-26", hour: 4)
        let heatmap = Self.summary([block]).heatmap
        #expect(heatmap.firstCell(midnightHour: 4) == days)
        #expect(heatmap.cell(.right, from: nil, midnightHour: 4) == days)
        #expect(heatmap.cell(.right, from: days, midnightHour: 4)?.hour == 5)
        #expect(heatmap.cell(.left, from: days, midnightHour: 4) == days)
        #expect(heatmap.cell(.above, from: days, midnightHour: 4) == days)
        #expect(heatmap.cell(.below, from: days, midnightHour: 4)?.row == "day:2026-10-27")
        // Midnight at 04:00: the row wraps from 23 to 0, and ends at 3.
        #expect(heatmap.cell(.right, from: .init(row: days.row, hour: 23), midnightHour: 4)?.hour == 0)
        #expect(heatmap.cell(.right, from: .init(row: days.row, hour: 3), midnightHour: 4)?.hour == 3)
        let lastDay = ActivityHeatmap.Cell(row: "day:2026-11-01", hour: 9)
        #expect(heatmap.cell(.below, from: lastDay, midnightHour: 0) == lastDay)
        #expect(heatmap.cell(.left, from: .init(row: "gone", hour: 9), midnightHour: 0)?.row == "day:2026-10-26")
        // The All row of week rows is the last stop.
        let month = Self.day("2026-10-01") ... Self.day("2026-10-31")
        let long = ActivitySummary(ActivitySummaryInput(blocks: [block], days: month, today: Self.thursday)).heatmap
        let last = try #require(long.rows.last)
        #expect(long.cell(.below, from: .init(row: last.id, hour: 9), midnightHour: 0)?.row == "all")
        #expect(long.row(of: .init(row: "all", hour: 9))?.label == "All")
    }

    @Test("PA-28 the arrow keys walk the bars and a bar's segments, bottom up and back to the whole bar")
    func barsFocus() throws {
        let blocks = try [
            Self.block("2026-10-28", "08:00", "09:00", [Self.item("safari", 1000)]),
            Self.block("2026-10-29", "08:00", "09:00", [Self.item("mail", 500), Self.item("safari", 1000)], active: 2000),
        ]
        let bars = Self.summary(blocks).bars
        let monday = bars.bars[0].id
        let wednesday = bars.bars[2].id
        let thursday = bars.bars[3].id
        #expect(bars.firstTarget == .init(bar: monday))
        #expect(bars.target(.right, from: nil) == .init(bar: monday))
        #expect(bars.target(.left, from: .init(bar: monday)) == .init(bar: monday))
        #expect(bars.target(.right, from: .init(bar: wednesday)) == .init(bar: thursday))
        let last = try #require(bars.bars.last)
        #expect(bars.target(.right, from: .init(bar: last.id)) == .init(bar: last.id))
        let safari = ActivityBars.Target(bar: thursday, series: .context("safari"))
        let mail = ActivityBars.Target(bar: thursday, series: .context("mail"))
        let brief = ActivityBars.Target(bar: thursday, series: .notItemized)
        #expect(bars.target(.above, from: .init(bar: thursday)) == safari)
        #expect(bars.target(.above, from: safari) == mail)
        #expect(bars.target(.above, from: mail) == brief)
        #expect(bars.target(.above, from: brief) == brief)
        #expect(bars.target(.below, from: mail) == safari)
        #expect(bars.target(.below, from: safari) == .init(bar: thursday))
        #expect(bars.target(.below, from: .init(bar: thursday)) == .init(bar: thursday))
        // The neighbor has Safari but no Mail.
        #expect(bars.target(.left, from: safari) == .init(bar: wednesday, series: .context("safari")))
        #expect(bars.target(.left, from: mail) == .init(bar: wednesday))
    }
}
