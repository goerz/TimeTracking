// Tests of the Activity section's figures (spec_planner_activity.md §6).

import Foundation
import Testing
import TimeTrackingCore

@Suite("Activity summary")
struct ActivitySummaryTests {
    static let week = day("2026-10-26") ... day("2026-11-01")
    static let thursday = day("2026-10-29")

    static func day(_ text: String) -> TrackingDay {
        TrackingDay(text) ?? TrackingDay(year: 2000, month: 1, day: 1)
    }

    static func item(_ context: String, _ subject: String, _ detail: String, _ seconds: Int) -> ActivityItem {
        ActivityItem(context: context, subject: subject, detail: detail, seconds: seconds)
    }

    static func item(_ context: String, _ seconds: Int) -> ActivityItem {
        ActivityItem(context: context, subject: "s", detail: "", seconds: seconds)
    }

    /// A block on a day of the week (`HH:mm` local, offset −4 h) with `a` = `active` or the item sum.
    static func block(
        _ day: String,
        _ start: String,
        _ end: String,
        _ items: [ActivityItem],
        active: Int? = nil,
        device: String = "macbook",
        background: [ActivityItem] = [],
        isOpen: Bool = false
    ) throws -> ActivityBlock {
        try ActivityBlock(
            start: ActivityFixture.instant("\(day)T\(start):00-04:00"),
            end: ActivityFixture.instant("\(day)T\(end):00-04:00"),
            activeSeconds: active ?? items.reduce(0) { $0 + $1.seconds },
            device: device,
            groupKey: items.first?.context ?? "",
            groupShare: 1,
            items: items,
            utcOffset: -4 * 3600,
            background: background,
            isOpen: isOpen
        )
    }

    static func summary(_ blocks: [ActivityBlock], contexts: Set<String> = [], device: String? = nil) -> ActivitySummary {
        ActivitySummary(ActivitySummaryInput(blocks: blocks, days: week, today: thursday, contexts: contexts, device: device))
    }

    @Test("PA-1 the header sums a, or the selected item seconds; device totals sum to it with more than one device")
    func headerTotals() throws {
        let blocks = try [
            Self.block("2026-10-26", "09:00", "10:00", [Self.item("safari", 1200), Self.item("tmux:paper", 1800)], active: 3300),
            Self.block("2026-10-27", "09:00", "09:30", [Self.item("safari", 1500)], device: "iPad"),
        ]
        let all = Self.summary(blocks)
        #expect(all.total == 4800)
        #expect(all.deviceTotals.map(\.seconds).reduce(0, +) == all.total)
        #expect(all.deviceTotals.map(\.device) == ["macbook", "iPad"])
        #expect(all.activeDays == 2)
        #expect(all.headerDetail == "2 days with activity · 40m per day · macbook 55m · iPad 25m")
        let filtered = Self.summary(blocks, contexts: ["safari"])
        #expect(filtered.total == 2700)
        #expect(filtered.deviceTotals.map(\.seconds).reduce(0, +) == 2700)
        let single = Self.summary([blocks[0]])
        #expect(single.deviceTotals.isEmpty)
        #expect(ActivitySummary.DeviceTotal(device: "remote", seconds: 1).displayName == "Other devices (Safari)")
    }

    @Test("PA-2 durations read Nh Mm from one hour, Mm below, Ss below a minute")
    func durations() {
        #expect(ActivityText.duration(25 * 3600 + 120) == "25h 02m")
        #expect(ActivityText.duration(5 * 3600) == "5h")
        #expect(ActivityText.duration(57 * 60 + 30) == "57m")
        #expect(ActivityText.duration(42) == "42s")
        #expect(ActivityText.duration(0) == "0h")
    }

    @Test("PA-4 the filter narrows every panel but Away; more than eight contexts go behind N more and filter by text")
    func chipsAndFilter() throws {
        let contexts = ["safari", "tmux:paper", "mail", "zoom", "skim", "tmux:audit", "tmux:tracker", "pages", "tmux:website", "messages"]
        let blocks = try contexts.enumerated().map { index, context in
            try Self.block("2026-10-26", "\(10 + index):00", "\(10 + index):30", [Self.item(context, 1800 - index * 60)])
        } + [Self.block("2026-10-27", "09:00", "09:10", [Self.item("safari", 600)])]
        let all = Self.summary(blocks)
        #expect(all.ranking.count == 10)
        #expect(all.moreContexts(search: "").map(\.context) == ["tmux:website", "messages"])
        #expect(all.moreContexts(search: "mess").map(\.context) == ["messages"])
        let mail = Self.summary(blocks, contexts: ["mail"])
        #expect(mail.contextRows.map(\.context) == ["mail"])
        #expect(mail.bars.series == [.context("mail")])
        #expect(mail.subjectRows.allSatisfy { $0.contexts == ["mail"] })
        #expect(mail.away == all.away)
        #expect(mail.heatmap.rows[0].seconds == 1800 - 2 * 60)
    }

    @Test("PA-5 a new context gets the least-used index, lowest on ties, never changed; private contexts get none")
    func contextColors() async throws {
        var colors = ContextPalette.assigning(["safari", "tmux:paper", "tmux:(private)"], to: [:])
        #expect(colors == ["safari": 0, "tmux:paper": 1])
        colors = ContextPalette.assigning(["mail", "safari"], to: colors.merging(["zoom": 0]) { $1 })
        #expect(colors["mail"] == 2)
        #expect(colors["safari"] == 0)
        #expect(ContextPalette.hex(nil, dark: false) == nil)
        #expect(ContextPalette.hex(0, dark: false) == "#3B5BDB")
        #expect(ContextPalette.hex(11, dark: true) == "#E64980")
        // Stored in the synced setting, which merges as a union.
        let store = try await TimeStore.inMemory(clock: ManualClock.fixture(), timeZone: ActivityFixture.newYork)
        try await store.set(.activityContextColors, colors)
        #expect(try await store.value(.activityContextColors) == colors)
        #expect(SettingMerge.mergeContextColors(["a": 3], ["a": 1, "b": 2]) == ["a": 1, "b": 2])
    }

    @Test("PA-6 day rows for 1 to 7 days, week rows for 8 to 98, month rows for 99 to 366; shading and the All footer")
    func heatmapModes() throws {
        #expect(ActivityHeatmap.mode(dayCount: 1) == .days)
        #expect(ActivityHeatmap.mode(dayCount: 7) == .days)
        #expect(ActivityHeatmap.mode(dayCount: 8) == .weeks)
        #expect(ActivityHeatmap.mode(dayCount: 98) == .weeks)
        #expect(ActivityHeatmap.mode(dayCount: 99) == .months)
        #expect(ActivityHeatmap.mode(dayCount: 366) == .months)
        #expect([0, 1, 15, 16, 30, 31, 45, 46, 60].map { ActivityHeatmap.level(minutes: Double($0)) } == [0, 1, 1, 2, 2, 3, 3, 4, 4])
        let blocks = try [Self.block("2026-10-26", "09:00", "10:00", [Self.item("safari", 3600)])]
        let days = Self.summary(blocks).heatmap
        #expect(days.rows.map(\.label) == ["Mon 26", "Tue 27", "Wed 28", "Thu 29", "Fri 30", "Sat 31", "Sun 1"])
        #expect(days.rows[0].minutes[9] == 60)
        #expect(days.footer == nil)
        let weeks = ActivitySummary(ActivitySummaryInput(
            blocks: blocks,
            days: Self.day("2026-10-19") ... Self.week.upperBound,
            today: Self.thursday
        ))
        .heatmap
        #expect(weeks.mode == .weeks)
        #expect(weeks.rows.map(\.label) == ["W43", "W44"])
        #expect(weeks.rows[1].sublabel == "Oct 26")
        // Four past days in W44: 60 minutes / 4.
        #expect(weeks.rows[1].minutes[9] == 15)
        #expect(weeks.rows[1].pastDays == 4)
        #expect(weeks.footer?.minutes[9] == 60.0 / 11)
        let year = ActivitySummary(ActivitySummaryInput(
            blocks: blocks,
            days: Self.day("2025-11-01") ... Self.week.upperBound,
            today: Self.thursday
        ))
        .heatmap
        #expect(year.mode == .months)
        #expect(year.rows.first?.label == "Nov 2025")
        #expect(year.rows.count == 13)
        #expect(year.footer != nil)
    }

    @Test("PA-7 a 09:40 to 10:20 block with a 2400 adds 20 minutes to hour 9 and 20 to hour 10, items alike")
    func hourSpread() throws {
        let block = try Self.block("2026-10-26", "09:40", "10:20", [Self.item("safari", 1600), Self.item("mail", 800)])
        let summary = Self.summary([block])
        let row = summary.heatmap.rows[0]
        #expect(row.minutes[9] == 20)
        #expect(row.minutes[10] == 20)
        let tooltip = summary.cellTooltip(row: row, hour: 9)
        #expect(tooltip.lines.map(\.seconds) == [800, 400])
        let filtered = Self.summary([block], contexts: ["mail"]).heatmap.rows[0]
        #expect(filtered.minutes[9] == 400.0 / 60)
    }

    @Test("PA-8 a cell tooltip lists at most five items, then + N more, with about when several blocks overlap")
    func cellTooltip() throws {
        let items = (1 ... 7).map { Self.item("app\($0)", "subject\($0)", "", 60 * $0) }
        let first = try Self.block("2026-10-29", "09:00", "09:30", Array(items.prefix(4)))
        let second = try Self.block("2026-10-29", "09:30", "10:00", Array(items.suffix(3)))
        let summary = Self.summary([first, second])
        let row = try #require(summary.heatmap.rows.first { $0.label == "Thu 29" })
        let tooltip = summary.cellTooltip(row: row, hour: 9)
        #expect(tooltip.title == "Thu Oct 29 · 09:00–10:00")
        #expect(tooltip.lines.count == 5)
        #expect(tooltip.moreText == "+ 2 more")
        #expect(tooltip.summary.hasPrefix("about 28m active"))
        let single = Self.summary([first])
        let alone = try single.cellTooltip(row: #require(single.heatmap.rows.first { $0.label == "Thu 29" }), hour: 9)
        #expect(alone.summary == "10m active (macbook)")
        #expect(alone.moreText == nil)
    }

    @Test("PA-9 in This week on Thursday, Friday to Sunday are empty rows and bars, left out of the average")
    func futureDays() throws {
        let blocks = try ["26", "27", "28", "29"].map { try Self.block("2026-10-\($0)", "09:00", "10:00", [Self.item("safari", 3600)]) }
        let summary = Self.summary(blocks)
        #expect(summary.averagePerActiveDay == 3600)
        #expect(summary.pastDays.count == 4)
        let bars = summary.bars.bars
        #expect(bars.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(bars.suffix(3).allSatisfy { $0.isFuture && $0.seconds == 0 })
        #expect(summary.heatmap.rows.suffix(3).filter(\.isEmpty).count == 3)
        #expect(bars[3].isToday)
    }

    @Test("PA-10 bars merge contexts beyond the twelfth into Other contexts and, without a filter, equal the day's a")
    func barsStack() throws {
        let items = (1 ... 14).map { Self.item("app\($0)", 3000 - $0 * 100) }
        let block = try Self.block("2026-10-26", "08:00", "18:00", items, active: 40_000)
        let bars = Self.summary([block]).bars
        #expect(bars.series.count == 14)
        #expect(bars.series[12] == .otherContexts)
        #expect(bars.series[13] == .notItemized)
        #expect(bars.bars[0].seconds == 40_000)
        #expect(bars.axisHours == 12)
        #expect(bars.bars[0].tooltip(for: .context("app1")) == "Mon Oct 26 · App1 · 48m of 11h 06m")
        #expect(ActivityBars.granularity(days: ActivitySummary.days(Self.day("2026-01-01") ... Self.day("2026-01-31"))) == .day)
        #expect(ActivityBars.granularity(days: ActivitySummary.days(Self.day("2026-01-01") ... Self.day("2026-06-30"))) == .week)
        #expect(ActivityBars.granularity(days: ActivitySummary.days(Self.day("2025-10-20") ... Self.day("2026-10-31"))) == .month)
    }

    @Test("PA-11 today's bar includes the open block until the closed block replaces it")
    func openBlock() async throws {
        let open = try Self.block("2026-10-29", "09:00", "09:20", [Self.item("safari", 1200)], isOpen: true)
        let memory = InMemoryActivityStore(blocks: [open])
        let reader: any ActivityReading = memory
        let interval = TrackingCalendar(timeZone: TimeZone(secondsFromGMT: -4 * 3600) ?? .gmt).interval(of: Self.week)
        let changes = reader.changes
        var iterator = changes.makeAsyncIterator()
        var summary = try await Self.summary(reader.blocks(in: interval, devices: nil))
        #expect(summary.bars.bars[3].openSeconds == 1200)
        var closed = open
        closed.isOpen = false
        closed.end += 300
        memory.append([closed])
        #expect(await iterator.next() == .blocks(month: "2026-10"))
        summary = try await Self.summary(reader.blocks(in: interval, devices: nil))
        #expect(summary.bars.bars[3].openSeconds == 0)
        #expect(summary.bars.bars[3].seconds == 1200)
    }

    @Test("PA-12 context shares stay relative to the unfiltered total; Not itemized equals a minus item seconds")
    func contextShares() throws {
        let block = try Self.block(
            "2026-10-26",
            "09:00",
            "10:00",
            [Self.item("safari", "github.com", "", 1800), Self.item("mail", "Inbox", "", 1200)],
            active: 3600
        )
        let all = Self.summary([block])
        #expect(all.contextRows.map(\.share) == [0.5, 1.0 / 3, 600.0 / 3600])
        #expect(all.contextRows.last?.context == nil)
        #expect(all.subjectRows.last?.subject == nil)
        #expect(all.subjectRows.last?.seconds == 600)
        let mail = Self.summary([block], contexts: ["mail"])
        #expect(mail.contextRows.map(\.share) == [1.0 / 3])
        #expect(mail.subjectRows.map(\.subject) == ["Inbox"])
    }

    @Test("PA-13 only browsers switch Subjects to Sites, only sessions to Sessions, a mix or All to All")
    func subjectKinds() throws {
        #expect(ActivitySubjectKind.automatic(for: ["safari", "chrome"]) == .sites)
        #expect(ActivitySubjectKind.automatic(for: ["tmux:paper"]) == .sessions)
        #expect(ActivitySubjectKind.automatic(for: ["safari", "tmux:paper"]) == .all)
        #expect(ActivitySubjectKind.automatic(for: []) == .all)
        #expect(ActivitySubjectKind.automatic(for: ["mail"]) == .all)
        let block = try Self.block("2026-10-26", "09:00", "10:00", [
            Self.item("safari", "github.com/owner", "", 600), Self.item("tmux:paper", "~/Papers/2026_Noise", "", 600),
            Self.item("mail", "Inbox", "", 600),
        ])
        let rows = Self.summary([block]).subjectRows
        #expect(rows.filter { $0.matches(.sites) }.map(\.subject) == ["github.com/owner"])
        #expect(rows.filter { $0.matches(.sessions) }.map(\.subject) == ["~/Papers/2026_Noise"])
        #expect(rows.filter { $0.matches(.folders) }.map(\.subject) == ["~/Papers/2026_Noise"])
    }
}
