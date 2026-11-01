// Tiles, chart, breakdown, entry list, filters, and exports of Reports
// (spec_reports.md §3 to §7).

import Foundation
import Testing
import TimeTrackingCore

struct ReportSnapshotTests {
    @Test("PR-1 Average per day divides by the days with entries: over 4 of 4 days, and over 3 of 4 without Wednesday")
    func averagePerDay() async throws {
        let world = try await ReportWorld()
        let summary = try await world.snapshot().summary
        #expect(summary.loggedSeconds == 26_400)
        #expect(summary.entryCount == 7)
        #expect(summary.includesRunning)
        #expect(summary.daysWithEntries == 4)
        #expect(summary.elapsedDays == 4)
        #expect(summary.averagePerDay == 6600)
        #expect(ReportText.tile(summary.loggedSeconds) == "7h 20m")
        let without = try await ReportWorld(wednesday: false).snapshot().summary
        #expect(without.daysWithEntries == 3)
        #expect(without.elapsedDays == 4)
        #expect(without.averagePerDay == 21_000 / 3)
        #expect(ReportText.averageCaption(summary) == "over 4 of 4 days")
        #expect(ReportText.averageCaption(without) == "over 3 of 4 days")
        let none = try await world.snapshot(search: "nothing matches").summary
        #expect(none.averagePerDay == 0)
        #expect(ReportText.tile(0) == "0h")
        #expect(ReportText.tile(3000) == "50m")
        #expect(ReportText.tile(67_800) == "18h 50m")
    }

    @Test("PR-3 leaf shares sum to 100% within rounding; under Project › Day a project's entries equal its days'")
    func shares() async throws {
        let world = try await ReportWorld()
        let tree = try await world.snapshot().tree
        let leaves = tree.leafPaths.compactMap(\.last)
        let shares = leaves.map { Double(ReportText.share($0.seconds, of: tree.seconds).dropLast()) ?? 0 }
        #expect(abs(shares.reduce(0, +) - 100) < 0.05 * Double(leaves.count))
        let byDay = try await world.snapshot(levels: [.project, .day]).tree
        for project in byDay.children {
            #expect(project.entryCount == project.children.reduce(0) { $0 + $1.entryCount })
            #expect(project.seconds == project.children.reduce(0) { $0 + $1.seconds })
        }
        let noise = try #require(byDay.children.first { $0.key == .project(world.noise.id) })
        #expect(noise.children.map { $0.displayName(level: .day) } == ["Mon 10/26", "Thu 10/29"])
        #expect(ReportText.share(7200, of: 26_400) == "27.3%")
        #expect(ReportText.seconds(46_214) == "12h 50m 14s")
        #expect(ReportText.seconds(1194) == "19m 54s")
        #expect(ReportText.seconds(4) == "4s")
        #expect(ReportText.seconds(22_203, padded: true) == "6h 10m 03s")
    }

    @Test("PR-4 the tree restricts everything, an area of another client adds its entries, and No project matches entries without one")
    func clientFilter() async throws {
        let world = try await ReportWorld()
        let consulting = try await world.snapshot(filters: ReportFilters(clients: [world.consulting.id]))
        #expect(consulting.summary.loggedSeconds == 3600)
        #expect(consulting.chart.buckets.map(\.total).reduce(0, +) == 3600)
        #expect(consulting.tree.children.map(\.key) == [.area(world.consultingArea.id)])
        #expect(consulting.entries.listings.map(\.entry.task) == ["Bugfixes"])
        #expect(consulting.breakdownCSV.split(separator: "\n").count == 2)
        #expect(consulting.entriesCSV().split(separator: "\n").count == 2)
        let union = try await world.snapshot(filters: ReportFilters(clients: [world.consulting.id], areas: [world.teaching.id]))
        #expect(Set(union.entries.listings.map(\.entry.task)) == ["Bugfixes", "Prepare lecture", "Große Aufgabe"])
        let none = try await world.snapshot(filters: ReportFilters(noProject: true))
        #expect(none.entries.listings.map(\.entry.task) == ["Mail"])
        let both = try await world.snapshot(filters: ReportFilters(clients: [world.consulting.id], noProject: true))
        #expect(Set(both.entries.listings.map(\.entry.task)) == ["Mail", "Bugfixes"])
        #expect(ReportFilters(clients: [world.consulting.id], noProject: true).activeKindCount == 1)
        let rows = try await world.store.projects(filter: ProjectFilter(state: .all))
        let areas = [world.consultingArea, world.research, world.teaching]
        let chips = ReportFilters(clients: [world.consulting.id], projects: [world.noise.id, world.grant.id])
            .chips(clients: [world.consulting, world.university], areas: areas, projects: rows)
        #expect(chips.map(\.text) == ["Consulting", "University · Research · Grant", "University · Research · Noise Model"])
    }

    @Test("PR-5 excluding archived projects removes their entries and tree rows everywhere; included, the node is marked archived")
    func archivedFilter() async throws {
        let world = try await ReportWorld()
        let excluded = try await world.snapshot(filters: ReportFilters(includeArchived: false))
        #expect(excluded.summary.loggedSeconds == 26_400 - 1800)
        #expect(!excluded.entries.listings.contains { $0.entry.projectID == world.old.id })
        #expect(!excluded.breakdownCSV.contains("Old Course"))
        #expect(ReportFilters(includeArchived: false).chips(clients: [], areas: [], projects: []).map(\.text) == ["Archived excluded"])
        let included = try await world.snapshot(levels: [.project])
        let old = try #require(included.tree.children.first { $0.key == .project(world.old.id) })
        #expect(old.isArchived)
        let clients = [world.consulting, world.university]
        let areas = [world.consultingArea, world.research, world.teaching]
        let rows = try await world.store.projects(filter: ProjectFilter(state: .all))
        let checked = ReportFilters(projects: [world.old.id, world.lectures.id], includeArchived: false)
        #expect(!checked.tree(clients: clients, areas: areas, projects: rows).rows.contains { $0.node == .project(world.old.id) })
        #expect(checked.normalized(clients: clients, areas: areas, projects: rows).projects == [world.lectures.id])
    }

    @Test("PR-6 every search word occurs in the task or the project, area, or client name, case- and diacritic-insensitively")
    func search() async throws {
        let world = try await ReportWorld()
        func tasks(_ search: String) async throws -> Set<String> {
            try await Set(world.snapshot(search: search).entries.listings.map(\.entry.task))
        }
        #expect(try await tasks("noise") == ["Clarify Noise Model", "Clarify noise model"])
        #expect(try await tasks("grosse") == ["Große Aufgabe"])
        #expect(try await tasks("course") == ["Große Aufgabe"])
        #expect(try await tasks("research") == ["Clarify Noise Model", "Clarify noise model", "Draft"])
        #expect(try await tasks("university draft") == ["Draft"])
        #expect(try await tasks("mail") == ["Mail"])
        #expect(try await world.snapshot(search: "research").summary.loggedSeconds
            == world.snapshot(filters: ReportFilters(areas: [world.research.id])).summary.loggedSeconds)
    }

    @Test("PR-7 after a project moves to another area, last year's report by area shows its time under the new area")
    func movedProject() async throws {
        let world = try await ReportWorld()
        try await world.add(world.lectures, "2025 lecture", "2025-05-05T09:00", "2025-05-05T10:00")
        try await world.store.updateProject(world.lectures.id, ProjectChange(areaID: world.research.id))
        let lastYear = ReportRange.preset(.lastYear).days(today: ReportWorld.today, earliest: nil)
        let snapshot = try await world.snapshot(lastYear, levels: [.area])
        #expect(snapshot.tree.children.map(\.key) == [.area(world.research.id)])
        #expect(snapshot.tree.children.first?.seconds == 3600)
    }

    @Test("PR-12 This week on Thursday draws seven slots, Friday to Sunday future; the average line equals the tile")
    func weekChart() async throws {
        let world = try await ReportWorld()
        let snapshot = try await world.snapshot()
        let chart = snapshot.chart
        #expect(chart.granularity == .day)
        #expect(chart.buckets.count == 7)
        #expect(chart.buckets.map(\.isFuture) == [false, false, false, false, true, true, true])
        #expect(chart.buckets.map(\.label) == [
            ["Mon", "10/26"], ["Tue", "10/27"], ["Wed", "10/28"], ["Thu", "10/29"], ["Fri", "10/30"], ["Sat", "10/31"], ["Sun", "11/1"],
        ])
        #expect(chart.averageLine == snapshot.summary.averagePerDay)
        #expect(chart.axisHours == 3)
        #expect(chart.labelStride == 1)
        let weeks = try await world.snapshot(ReportWorld.today ... TrackingDay(year: 2026, month: 11, day: 30), granularity: .week)
        #expect(weeks.chart.averageLine == nil)
        let first = try #require(weeks.chart.buckets.first)
        #expect(first.isPartial)
        #expect(first.label == ["W44", "Oct 29 – Nov 1"])
        #expect(first.partialNote == "partial week (4 days)")
        #expect(first.averagePerDay == 3600)
    }

    @Test("PR-13 a bar's tooltip lists the non-zero segments in stack order and its total equals their sum")
    func tooltip() async throws {
        let world = try await ReportWorld()
        let chart = try await world.snapshot().chart
        let monday = chart.buckets[0]
        #expect(monday.title == "Monday, October 26")
        #expect(monday.segments.map(\.key.name) == ["Consulting", "Research"])
        #expect(monday.segments.allSatisfy { $0.seconds > 0 })
        #expect(monday.total == monday.segments.reduce(0) { $0 + $1.seconds })
        #expect(monday.total == 10_800)
        #expect(chart.buckets[4].segments.isEmpty)
    }

    @Test("PR-14 Area stacks use area colors in area order; Project uses lightness steps; None is one accent segment without legend")
    func stacking() async throws {
        let world = try await ReportWorld()
        let byArea = try await world.snapshot().chart
        #expect(byArea.legend.map(\.name) == ["Consulting", "Research", "Teaching", "No area"])
        #expect(byArea.legend.map(\.color) == [
            .area("#D94A6A", hatched: false), .area("#13A08F", hatched: false), .area("#E8892F", hatched: false), .gray,
        ])
        let byProject = try await world.snapshot(stack: .project).chart
        let research = try AreaColor("#13A08F")
        let grant = try #require(byProject.legend.first { $0.value == .project(world.grant.id) })
        let noise = try #require(byProject.legend.first { $0.value == .project(world.noise.id) })
        #expect(grant.color == .area(research.hex, hatched: false))
        #expect(noise.color == .area(research.lightnessStep(1).hex, hatched: false))
        // The second project's color is the area's at HSL lightness +0.12, same hue.
        let base = try Self.hsl(research.hex)
        let second = try Self.hsl(research.lightnessStep(1).hex)
        #expect(abs(second.lightness - base.lightness - 0.12) < 0.005)
        #expect(abs(second.hue - base.hue) < 1.5)
        #expect(abs(second.saturation - base.saturation) < 0.02)
        #expect(byProject.legend.map(\.name) == ["Website", "Grant", "Noise Model", "Lectures", "Old Course", "No project"])
        let none = try await world.snapshot(stack: .unstacked).chart
        #expect(none.legend.isEmpty)
        #expect(none.buckets.allSatisfy { $0.segments.count <= 1 && $0.segments.allSatisfy { $0.key.color == .accent } })
        let byClient = try await world.snapshot(stack: .client).chart
        #expect(byClient.legend.map(\.color) == [.palette(0), .palette(1), .gray])
    }

    @Test("PR-17 the list's footer total equals the Logged time tile; the running entry's duration grows each second")
    func listTotal() async throws {
        let world = try await ReportWorld()
        let snapshot = try await world.snapshot()
        let now = world.test.clock.now
        #expect(snapshot.entries.totalSeconds(at: now) == snapshot.summary.loggedSeconds)
        #expect(snapshot.entries.totalSeconds(at: now + 1) == snapshot.summary.loggedSeconds + 1)
        let runningListing = snapshot.entries.listings.first(where: \.entry.isRunning)
        let running = try #require(runningListing)
        #expect(running.entry.seconds(at: now + 1) == running.entry.seconds(at: now) + 1)
        let path: [GroupKeyValue] = [.area(world.research.id), .project(world.noise.id)]
        let narrowed = try await world.snapshot(path: path)
        #expect(narrowed.entries.listings.count == 2)
        #expect(narrowed.summary.loggedSeconds == 26_400)
        #expect(snapshot.tree.node(at: path)?.seconds == 10_800)
    }

    @Test("PR-19 both CSV exports are byte-identical to the tool's writers over the report query")
    func csvParity() async throws {
        let world = try await ReportWorld()
        let filters = ReportFilters(clients: [world.university.id])
        let snapshot = try await world.snapshot(levels: [.client, .area, .project], filters: filters, search: "a")
        let query = ReportQuery(
            days: ReportWorld.week,
            groupBy: [.client, .area, .project],
            granularity: .total,
            filter: filters.entryFilter(search: "a")
        )
        let tool = try await ReportCSVWriter.breakdownCSV(world.store.report(query), levels: [.client, .area, .project])
        #expect(snapshot.breakdownCSV == tool)
        #expect(tool.hasPrefix("client,area,project,seconds,duration,share,entries\n"))
        let entries = try await world.store.listings(for: world.store.entries(matching: query))
        #expect(snapshot.entriesCSV() == ReportCSVWriter.entriesCSV(entries, now: world.test.clock.now))
    }

    @Test func breakdownSortingAndNames() async throws {
        let world = try await ReportWorld()
        let tree = try await world.snapshot(levels: [.area]).tree
        let byTime = tree.sorted(by: .loggedTime, ascending: false)
        #expect(byTime.children.map(\.seconds) == byTime.children.map(\.seconds).sorted(by: >))
        #expect(tree.sorted(by: .name, ascending: false).children.map(\.key) == tree.children.reversed().map(\.key))
        #expect(tree.children.last?.displayName(level: .area) == "No area")
        #expect(ReportNode(key: .task("")).displayName(level: .task) == "(no task)")
        #expect(try await world.store.earliestEntryDay() == TrackingDay(year: 2026, month: 10, day: 26))
    }

    /// Hue (degrees), saturation, and lightness of `#RRGGBB`, computed
    /// independently of `AreaColor`.
    static func hsl(_ hex: String) throws -> HSL {
        let value = try #require(UInt32(hex.dropFirst(), radix: 16))
        let red = Double(value >> 16 & 0xFF) / 255
        let green = Double(value >> 8 & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if delta > 0 {
            switch maximum {
            case red: hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            case green: hue = 60 * ((blue - red) / delta + 2)
            default: hue = 60 * ((red - green) / delta + 4)
            }
        }
        return HSL(hue: hue < 0 ? hue + 360 : hue, saturation: saturation, lightness: lightness)
    }
}

/// Hue in degrees, saturation and lightness in 0...1.
struct HSL {
    var hue: Double
    var saturation: Double
    var lightness: Double
}
