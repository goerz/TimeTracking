// The Activity section's heatmap: rows, cells, tooltips, future days, and the
// arrow keys (activity.md §1.1, §1.4, §2).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityHeatmapTests {
    private static func mondayMail() throws -> ActivityBlock {
        try ActivityFixture.block("2024-03-11", "09:00", "10:00", [(SectionFixture.mail, 3600)])
    }

    @Test(
        "PA-6 day rows to 7 days, ISO-week rows to 98, month rows to 366, values and shading, the All footer only for weeks and months"
    )
    func rowsAndShading() throws {
        #expect([1, 7, 8, 98, 99, 366].map(ActivityHeatmap.mode(dayCount:)) == [.days, .days, .weeks, .weeks, .months, .months])
        let levels = [0, 0.4, 1, 15, 16, 30, 31, 45, 46, 60].map { ActivityHeatmap.level(minutes: $0) }
        #expect(levels == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4])
        #expect(ActivityHeatmap.labeledHours == [0, 3, 6, 9, 12, 15, 18, 21])
        let blocks = try [Self.mondayMail()]

        let days = SectionFixture.summary(blocks).heatmap
        #expect(days.mode == .days)
        #expect(days.rows.map(\.label) == ["Mon 11", "Tue 12", "Wed 13", "Thu 14", "Fri 15", "Sat 16", "Sun 17"])
        #expect(days.rows[0].minutes[9] == 60)
        #expect(days.rows[0].totalText == "1h")
        #expect(days.rows.map(\.isEmpty) == [false, true, true, true, true, true, true])
        #expect(days.footer == nil)

        let twoWeeks = TrackingDay(year: 2024, month: 3, day: 4) ... SectionFixture.week.upperBound
        let weeks = SectionFixture.summary(blocks, days: twoWeeks).heatmap
        #expect(weeks.mode == .weeks)
        #expect(weeks.rows.map(\.label) == ["W10", "W11"])
        #expect(weeks.rows.map(\.sublabel) == ["Mar 4", "Mar 11"])
        // Four past days in W11 (Monday to Thursday): 60 minutes over 4.
        #expect(weeks.rows[1].pastDays == 4)
        #expect(weeks.rows[1].minutes[9] == 15)
        #expect(weeks.rows[1].totalText == "15m avg/day")
        #expect(weeks.footer?.label == "All")
        #expect(weeks.footer?.pastDays == 11)
        #expect(weeks.footer?.minutes[9] == 60.0 / 11)

        let sunday = TrackingDay(year: 2024, month: 3, day: 17)
        let longest = SectionFixture.summary(blocks, days: sunday ... sunday.adding(days: 97)).heatmap
        #expect(longest.mode == .weeks)
        #expect(longest.rows.count == 15)

        let year = TrackingDay(year: 2023, month: 3, day: 15) ... SectionFixture.thursday
        let months = SectionFixture.summary(blocks, days: year).heatmap
        #expect(months.mode == .months)
        #expect(months.rows.count == 13)
        #expect(months.rows.first?.label == "Mar 2023")
        #expect(months.rows.last?.label == "Mar 2024")
        // March 2024 has 14 past days in the range.
        #expect(months.rows.last?.minutes[9] == 60.0 / 14)
        #expect(months.footer?.label == "All")
    }

    @Test(
        "PA-7 a 09:40 to 10:20 block with 2400 s active adds 20 minutes to the 9 cell and 20 to the 10 cell, its items alike"
    )
    func hourSpread() throws {
        let block = try ActivityFixture.block(
            "2024-03-11",
            "09:40",
            "10:20",
            [(SectionFixture.mail, 1600), (ActivityFixture.terminal(), 800)]
        )
        #expect(block.activeSeconds == 2400)
        #expect(block.hourShares() == [9: 1200, 10: 1200])
        let summary = SectionFixture.summary([block])
        let row = summary.heatmap.rows[0]
        #expect(row.minutes[9] == 20)
        #expect(row.minutes[10] == 20)
        #expect(row.minutes.reduce(0, +) == 40)
        #expect(summary.cellTooltip(row: row, hour: 9).lines.map(\.seconds) == [800, 400])
        #expect(summary.cellTooltip(row: row, hour: 10).lines.map(\.seconds) == [800, 400])
        let terminal = SectionFixture.summary([block], apps: ["WezTerm"]).heatmap.rows[0]
        #expect(terminal.minutes[9] == 400.0 / 60)
        #expect(terminal.minutes[10] == 400.0 / 60)
    }

    @Test("DATA-44 aggregating by hour of day a block from 09:50 to 10:20 gives 600 s to hour 9 and 1200 s to hour 10")
    func hourOfDay() throws {
        let block = try ActivityFixture.block("2024-03-11", "09:50", "10:20", [(SectionFixture.mail, 1800)])
        #expect(block.hourShares() == [9: 600, 10: 1200])
    }

    @Test(
        "PA-8 a cell tooltip lists at most five items, then + N more, with about when several blocks overlap the cell"
    )
    func cellTooltip() throws {
        let items = (1 ... 7).map { (ActivityFixture.app("App\($0)"), 60 * $0) }
        let first = try ActivityFixture.block("2024-03-14", "09:00", "09:30", Array(items.prefix(4)))
        let second = try ActivityFixture.block("2024-03-14", "09:30", "10:00", Array(items.suffix(3)))
        let summary = SectionFixture.summary([first, second])
        let row = try #require(summary.heatmap.rows.first { $0.label == "Thu 14" })
        let tooltip = summary.cellTooltip(row: row, hour: 9)
        #expect(tooltip.title == "Thu Mar 14 · 09:00–10:00")
        #expect(tooltip.summary == "about 28m active (MacBook)")
        #expect(tooltip.lines.map(\.app) == ["App7", "App6", "App5", "App4", "App3"])
        #expect(tooltip.lines.allSatisfy { $0.device == nil })
        #expect(tooltip.moreText == "+ 2 more")

        let single = SectionFixture.summary([first])
        let alone = try single.cellTooltip(row: #require(single.heatmap.rows.first { $0.label == "Thu 14" }), hour: 9)
        #expect(alone.summary == "10m active (MacBook)")
        #expect(alone.lines.count == 4)
        #expect(alone.moreText == nil)

        let devices = SectionFixture.summary([first, SectionFixture.moved(second, to: "iPhone")])
        let both = try devices.cellTooltip(row: #require(devices.heatmap.rows.first { $0.label == "Thu 14" }), hour: 9)
        #expect(both.summary == "about 28m active (MacBook, iPhone)")
        #expect(both.lines.first?.device == "iPhone")
        #expect(both.lines.last?.device == "MacBook")

        // Week rows list apps with their average per past day.
        let twoWeeks = TrackingDay(year: 2024, month: 3, day: 4) ... SectionFixture.week.upperBound
        let weeks = SectionFixture.summary([first, second], days: twoWeeks)
        let week = try #require(weeks.heatmap.rows.last)
        let average = weeks.cellTooltip(row: week, hour: 9)
        #expect(average.title == "W11 · 09:00–10:00")
        #expect(average.summary == "about 7m per day over 4 days")
        #expect(Set(average.lines.map(\.text)) == [""])
        #expect(average.lines.first?.seconds == 105)
    }

    @Test("PA-9 in This week on Thursday, Friday to Sunday are empty rows and bars, excluded from the per-day average")
    func futureDays() throws {
        let blocks = try ["11", "12", "13", "14"].map { day in
            try ActivityFixture.block("2024-03-\(day)", "09:00", "10:00", [(SectionFixture.mail, 3600)])
        }
        let summary = SectionFixture.summary(blocks)
        #expect(summary.pastDays.count == 4)
        #expect(summary.averagePerActiveDay == 3600)
        #expect(summary.headerDetail == "4 days with activity · 1h per day")
        let bars = summary.bars.bars
        #expect(bars.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(bars.map(\.isFuture) == [false, false, false, false, true, true, true])
        #expect(bars.suffix(3).allSatisfy { $0.seconds == 0 && $0.segments.isEmpty })
        #expect(bars[3].isToday)
        #expect(summary.heatmap.rows.map(\.isEmpty) == [false, false, false, false, true, true, true])
        // Week rows average over the past days only.
        let twoWeeks = TrackingDay(year: 2024, month: 3, day: 4) ... SectionFixture.week.upperBound
        let week = try #require(SectionFixture.summary(blocks, days: twoWeeks).heatmap.rows.last)
        #expect(week.pastDays == 4)
        #expect(week.minutes[9] == 60)
    }

    @Test(
        "PA-27 the arrow keys move the heatmap cell in column and row order, the All row included, and stop at the edges"
    )
    func heatmapFocus() throws {
        let block = try ActivityFixture.block("2024-03-14", "08:00", "09:00", [(SectionFixture.mail, 600)])
        let heatmap = SectionFixture.summary([block]).heatmap
        let first = ActivityHeatmap.Cell(row: "day:2024-03-11", hour: 4)
        #expect(heatmap.firstCell(startOfDayHour: 4) == first)
        #expect(heatmap.cell(.right, from: nil, startOfDayHour: 4) == first)
        #expect(heatmap.cell(.right, from: first, startOfDayHour: 4)?.hour == 5)
        #expect(heatmap.cell(.left, from: first, startOfDayHour: 4) == first)
        #expect(heatmap.cell(.above, from: first, startOfDayHour: 4) == first)
        #expect(heatmap.cell(.below, from: first, startOfDayHour: 4) == ActivityHeatmap.Cell(row: "day:2024-03-12", hour: 4))
        // With days starting at 04:00 a row runs from 4 round to 3.
        #expect(heatmap.cell(.right, from: .init(row: first.row, hour: 23), startOfDayHour: 4)?.hour == 0)
        #expect(heatmap.cell(.right, from: .init(row: first.row, hour: 3), startOfDayHour: 4)?.hour == 3)
        let lastDay = ActivityHeatmap.Cell(row: "day:2024-03-17", hour: 9)
        #expect(heatmap.cell(.below, from: lastDay, startOfDayHour: 0) == lastDay)
        #expect(heatmap.cell(.left, from: .init(row: "gone", hour: 9), startOfDayHour: 0)?.row == "day:2024-03-11")

        let month = TrackingDay(year: 2024, month: 3, day: 1) ... TrackingDay(year: 2024, month: 3, day: 31)
        let weeks = SectionFixture.summary([block], days: month).heatmap
        let last = try #require(weeks.rows.last)
        let all = ActivityHeatmap.Cell(row: "all", hour: 9)
        #expect(weeks.cell(.below, from: .init(row: last.id, hour: 9), startOfDayHour: 0) == all)
        #expect(weeks.cell(.below, from: all, startOfDayHour: 0) == all)
        #expect(weeks.cell(.above, from: all, startOfDayHour: 0)?.row == last.id)
        #expect(weeks.row(of: all)?.label == "All")
    }
}
