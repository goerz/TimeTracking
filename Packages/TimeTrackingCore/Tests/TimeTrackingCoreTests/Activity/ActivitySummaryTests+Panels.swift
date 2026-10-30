// Tests of the Activity section's lists, Away, health, and logs
// (spec_planner_activity.md §6).

import Foundation
import Testing
import TimeTrackingCore

extension ActivitySummaryTests {
    @Test("PA-14 a subject has a chevron only with a detail record, and says details for N of M periods")
    func subjectDetails() throws {
        let first = try Self.block("2026-10-26", "09:00", "10:00", [Self.item("tmux:paper", "~/Papers/Noise", "nvim a.tex", 600)])
        let second = try Self.block("2026-10-27", "09:00", "10:00", [Self.item("tmux:paper", "~/Papers/Noise", "nvim b.tex", 300)])
        let detail = ActivityBlockDetail(
            blockID: first.id,
            items: [
                Self.item("tmux:paper", "~/Papers/Noise", "nvim a.tex", 500),
                Self.item("tmux:paper", "~/Papers/Noise", "nvim c.tex", 100),
            ],
            files: [ActivityFileChange(time: first.start, path: "/Users/alex/Papers/Noise/a.tex")]
        )
        let input = ActivitySummaryInput(blocks: [first, second], days: Self.week, today: Self.thursday, details: [first.id: detail])
        let summary = ActivitySummary(input)
        let row = try #require(summary.subjectRows.first)
        #expect(row.hasDetails)
        let drill = try #require(summary.subjectDetail(row, homeDirectory: "/Users/alex"))
        #expect(drill.lines.map(\.detail) == ["nvim a.tex", "nvim c.tex"])
        #expect(drill.coverageText == "details for 1 of 2 periods")
        #expect(drill.visitedText == "1 modified file")
        // Elsewhere (no details): no chevron.
        let elsewhere = Self.summary([first, second])
        #expect(elsewhere.subjectRows.first?.hasDetails == false)
    }

    @Test("PA-15 Away counts only gaps over idle_close between one device's blocks of a day, classified with details")
    func away() throws {
        let morning = try Self.block("2026-10-26", "09:00", "10:00", [Self.item("safari", 3600)])
        let shortGap = try Self.block("2026-10-26", "10:04", "11:00", [Self.item("safari", 3000)])
        let afterLunch = try Self.block("2026-10-26", "12:00", "13:00", [Self.item("mail", 3000)])
        let otherDevice = try Self.block("2026-10-26", "10:30", "10:40", [Self.item("safari", 600)], device: "iPad")
        let nextDay = try Self.block("2026-10-27", "09:00", "10:00", [Self.item("safari", 3600)])
        let blocks = [morning, shortGap, afterLunch, otherDevice, nextDay]
        let unknown = Self.summary(blocks).away
        #expect(unknown.seconds == 3600)
        #expect(unknown.parts == [ActivityAway.Part(cause: .unknown, seconds: 3600, count: 1)])
        #expect(unknown.partsText == "unknown 1h (1 time) (cause known only on the Mac that recorded it)")
        let detail = ActivityBlockDetail(
            blockID: shortGap.id,
            items: shortGap.items,
            presence: [ActivityPresenceTransition(time: shortGap.end + 30, state: .locked)]
        )
        let input = ActivitySummaryInput(blocks: blocks, days: Self.week, today: Self.thursday, details: [shortGap.id: detail])
        let classified = ActivitySummary(input).away
        #expect(classified.parts == [ActivityAway.Part(cause: .locked, seconds: 3600, count: 1)])
        #expect(!classified.hasUnclassified)
        #expect(classified.totalText == "1h during the day")
    }

    @Test("PA-16 the Mac footer's dot follows the liveness rule of the Tracker pane; the iPad footer shows lastTick")
    func healthFooter() throws {
        let now = try ActivityFixture.instant("2026-10-29T14:20:00-04:00")
        let state = TrackerState(
            device: "macbook",
            openBlock: nil,
            primary: nil,
            presence: TrackerPresence(state: .active, since: now - 600),
            health: TrackerHealth(lastTick: now - 12, version: "1.0", sources: [
                TrackerSourceHealth(id: "terminal", name: "Terminal", status: .active),
                TrackerSourceHealth(id: "knowledge", name: "Knowledge store", status: .off, reason: "Full Disk Access not granted"),
            ])
        )
        let health = ActivityHealth(registration: .enabled, state: state, now: now)
        #expect(health.dot == .green)
        #expect(health.statusLine == TrackerLiveness(registration: .enabled, state: state, now: now).statusLine(now: now))
        #expect(health.activeSources == ["Terminal"])
        #expect(health.problems == ["Knowledge store off (Full Disk Access not granted)"])
        #expect(ActivityHealth(registration: .enabled, state: state, now: now + 600).dot == .red)
        #expect(ActivityHealth(registration: .notRegistered, state: nil, now: now).dot == .gray)
        let remote = LiveState.MacActivity(
            device: "macbook",
            primary: nil,
            groupKey: nil,
            presence: "active",
            since: now - 60,
            agentRunning: true,
            lastTick: now - 120,
            health: [],
            updatedAt: now
        )
        let ipad = ActivityHealth(remote: remote, now: now)
        #expect(ipad.statusLine == "Mac tracker: last tick 2 min ago")
        #expect(ipad.activeSources.isEmpty)
        var stopped = remote
        stopped.agentRunning = false
        #expect(ActivityHealth(remote: stopped, now: now).dot == .gray)
    }

    @Test("PA-18 the setup card shows with an empty log and no tracker, never once a block existed")
    func emptyStates() throws {
        let empty = Self.summary([])
        #expect(ActivityEmptyState.resolve(summary: empty, everSawBlock: false, trackerSetUp: false, footerRed: true) == .setup)
        #expect(ActivityEmptyState
            .resolve(summary: empty, everSawBlock: true, trackerSetUp: false, footerRed: true) == .noActivity(trackerNotRunning: true))
        #expect(ActivityEmptyState
            .resolve(summary: empty, everSawBlock: false, trackerSetUp: true, footerRed: false) == .noActivity(trackerNotRunning: false))
        let block = try Self.block("2026-10-26", "09:00", "10:00", [Self.item("safari", 3600)])
        #expect(ActivityEmptyState
            .resolve(summary: Self.summary([block]), everSawBlock: true, trackerSetUp: false, footerRed: false) == .panels)
        #expect(
            ActivityEmptyState.resolve(
                summary: Self.summary([block], contexts: ["mail"]),
                everSawBlock: true,
                trackerSetUp: true,
                footerRed: false
            )
                == .nothingForContexts
        )
        #expect(ActivityEmptyState
            .noActivityText(Self.day("2026-10-20") ... Self.day("2026-10-26")) == "No activity recorded between Oct 20 and Oct 26")
    }

    @Test("PA-19 exclusion drafts name the right list and value; exclusions apply at read time and leave the log byte-identical")
    func exclusions() async throws {
        #expect(TrackerExclusionDraft.forContext("tmux:paper", bundleIdentifier: nil) == .tmuxSession("paper"))
        #expect(TrackerExclusionDraft.forContext("mail", bundleIdentifier: "com.apple.mail") == .app(bundleIdentifier: "com.apple.mail"))
        #expect(TrackerExclusionDraft.forContext("skim", bundleIdentifier: nil)?.value.isEmpty == true)
        #expect(TrackerExclusionDraft.forContext("safari", bundleIdentifier: nil) == nil)
        #expect(TrackerExclusionDraft.forSite("github.com/owner/repo") == .domain("github.com"))
        try await withTemporaryFolder { folder in
            let folders = folder.folders
            let now = try ActivityFixture.instant("2026-10-29T12:00:00-04:00")
            var writer = BlockLogWriter(folder: folders.blockFolders[0], device: "macbook")
            let block = try Self.block("2026-10-26", "09:00", "10:00", [Self.item("tmux:paper", 1800), Self.item("mail", 1200)])
            try writer.append(block, contexts: ["mail": "com.apple.mail"])
            let file = folders.blockFolders[0].appending(path: "2026-10.jsonl")
            let before = try Data(contentsOf: file)
            let reader = FileActivityStore(folders: folders, timeZone: ActivityFixture.newYork, clock: ManualClock(now))
            let interval = TrackingCalendar(timeZone: ActivityFixture.newYork).interval(of: Self.week)
            #expect(try await Self.summary(reader.blocks(in: interval, devices: nil)).total == 3000)
            var settings = TrackerSettings.defaults
            settings.privacy.excludeTmuxSessions = ["paper"]
            try ActivityFixture.write(settings.tomlText(), to: folders.settingsURL, modified: now)
            await reader.refresh()
            let after = try await Self.summary(reader.blocks(in: interval, devices: nil))
            #expect(after.ranking.map(\.context) == ["mail"])
            #expect(after.total == 1200)
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test("PA-20 building every panel reads the logs and changes none of them")
    func readOnly() async throws {
        try await withTemporaryFolder { folder in
            let folders = folder.folders
            let now = try ActivityFixture.instant("2026-10-29T12:00:00-04:00")
            var writer = BlockLogWriter(folder: folders.blockFolders[0], device: "macbook")
            let block = try Self.block("2026-10-26", "09:00", "10:00", [Self.item("tmux:paper", 1800)])
            try writer.append(block, contexts: [:])
            try ActivityFixture.write(TrackerSettings.defaultFileContents, to: folders.settingsURL, modified: now)
            let files = [folders.blockFolders[0].appending(path: "2026-10.jsonl"), folders.settingsURL]
            let before = try files.map { try Data(contentsOf: $0) }
            let reader = FileActivityStore(folders: folders, timeZone: ActivityFixture.newYork, clock: ManualClock(now))
            let interval = TrackingCalendar(timeZone: ActivityFixture.newYork).interval(of: Self.week)
            let blocks = try await reader.blocks(in: interval, devices: nil)
            let details = try await reader.details(for: blocks.map(\.id))
            let summary = ActivitySummary(ActivitySummaryInput(blocks: blocks, days: Self.week, today: Self.thursday, details: details))
            _ = (summary.heatmap, summary.bars, summary.contextRows, summary.subjectRows, summary.backgroundRows, summary.away)
            _ = await reader.currentState()
            #expect(try files.map { try Data(contentsOf: $0) } == before)
        }
    }
}
