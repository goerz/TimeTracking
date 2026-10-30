// Reports, CSV, and suggestion data (spec_data_and_sync.md §7.3; §9 items 47, 48; spec_automation.md §8.2).

import Foundation
import Testing
import TimeTrackingCore

struct ReportTests {
    @Test("DATA-47 daily reports give split pieces to their days, buckets sum to the total, and agree with DayGroup")
    func dailyReport() async throws {
        let test = try await TestStore(now: "2026-03-04T10:00")
        let made = try await test.structure(projects: ["Paper"])
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "Late",
            start: test.date("2026-03-02T22:00"),
            end: test.date("2026-03-03T01:30")
        ))
        _ = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "Mail",
            start: test.date("2026-03-03T09:00"),
            end: test.date("2026-03-03T09:20")
        ))
        _ = try await test.store.start(projectID: made.projects[0].id, task: "Now", at: test.date("2026-03-04T09:30"))
        let days = TrackingDay(year: 2026, month: 3, day: 2) ... TrackingDay(year: 2026, month: 3, day: 4)
        let report = try await test.store.report(ReportQuery(days: days, groupBy: [.project, .task], granularity: .day))
        #expect(report.seconds == 7200 + 5400 + 1200 + 1800)
        #expect(report.buckets.values.reduce(0, +) == report.seconds)
        let groups = try await test.store.days(ending: days.upperBound, count: 3)
        for group in groups {
            #expect(report.buckets[TrackingPeriod(.day, containing: group.day)] == group.totalSeconds)
        }
        #expect(groups[0].includesRunning)
        #expect(groups[0].totalSeconds == 1800)
        let paper = try #require(report.children.first { $0.key == .project(made.projects[0].id) })
        #expect(paper.name == "Paper")
        #expect(paper.children.map(\.name) == ["Late", "Now"])
        #expect(report.children.last?.key == .project(nil))
        let series = try await test.store.series(ReportQuery(days: days, groupBy: [.project], granularity: .day))
        #expect(series.map(\.0.description) == ["2026-03-02", "2026-03-03", "2026-03-04"])
        #expect(series[1].1[.project(nil)] == 1200)
        let matching = try await test.store.entries(matching: ReportQuery(
            days: days,
            groupBy: [],
            filter: EntryFilter(taskContains: "mai")
        ))
        #expect(matching.map(\.task) == ["Mail"])
    }

    @Test("DATA-48 a report by area puts a moved project's entries under its new area")
    func movedProject() async throws {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["Paper"])
        let other = try await test.store.createArea(AreaDraft(clientID: made.client.id, name: "Teaching"))
        _ = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))
        try await test.store.updateProject(made.projects[0].id, ProjectChange(areaID: other.id))
        let day = TrackingDay(year: 2024, month: 3, day: 14)
        let report = try await test.store.report(ReportQuery(days: day ... day, groupBy: [.client, .area]))
        let areas = try #require(report.children.first?.children)
        #expect(areas.map(\.key) == [.area(other.id)])
        #expect(areas.first?.seconds == 3600)
        #expect(areas.first?.color == other.color)
    }

    @Test func csvWriters() async throws {
        let test = try await TestStore()
        let made = try await test.structure(projects: ["Noise, paper"])
        let entries = try await test.store.create(EntryDraft(
            projectID: made.projects[0].id,
            task: "Say \"hi\"",
            start: test.date("2024-03-14T09:15"),
            end: test.date("2024-03-14T10:00")
        ))
        let listings = try await test.store.listings(for: entries)
        let csv = ReportCSVWriter.entriesCSV(listings, now: test.clock.now, timeZone: test.zone)
        let lines = csv.split(separator: "\n")
        #expect(lines.first == "start,stop,seconds,client,area,project,task,running")
        let expected = "2024-03-14T09:15:00+01:00,2024-03-14T10:00:00+01:00,2700,"
            + "\(made.client.name),Research,\"Noise, paper\",\"Say \"\"hi\"\"\",false"
        #expect(lines.last.map(String.init) == expected)
        let day = TrackingDay(year: 2024, month: 3, day: 14)
        let report = try await test.store.report(ReportQuery(days: day ... day, groupBy: [.project, .task]))
        let breakdown = ReportCSVWriter.breakdownCSV(report, levels: [.project, .task])
        #expect(breakdown == "project,task,seconds,duration,share,entries\n\"Noise, paper\",\"Say \"\"hi\"\"\",2700,0:45:00,100.0,1\n")
        #expect(ReportCSVWriter.clientsCSV([made.client]).hasPrefix("id,name\n"))
    }

    @Test func suggestionDataOverlaps() async throws {
        let test = try await TestStore()
        let entry = try await test.store.create(EntryDraft(
            projectID: nil,
            task: "",
            start: test.date("2024-03-14T08:00"),
            end: test.date("2024-03-14T09:00")
        ))[0]
        let block = try ActivityBlock(
            start: test.date("2024-03-14T08:30"),
            end: test.date("2024-03-14T09:30"),
            activeSeconds: 3600,
            device: "mac",
            groupKey: "mail",
            groupShare: 1,
            items: [],
            utcOffset: 3600
        )
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let reader = FileActivityStore(folders: ActivityFolders(shared: folder.url, local: folder.url, isFallback: true))
        let data = StoreSuggestionData(store: test.store, activity: reader)
        let result = try await data.entriesOverlapping([block], minOverlap: 600)
        #expect(result.first?.1.map(\.0.id) == [entry.id])
        #expect(result.first?.1.first?.overlapSeconds == 1800)
        #expect(try await data.feedback(in: DateInterval(start: test.clock.now - 86_400, end: test.clock.now)).isEmpty)
    }
}
