// The Activity section's workspace items, In the background, and Away panels
// (activity.md §1.6, §1.7, §1.8).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityListsTests {
    @Test(
        "PA-14 a workspace's chevron lists its items from the blocks of every device, ranked by seconds and labeled as in the block summary"
    )
    func workspaceItems() throws {
        let phonePage = SectionFixture.page(
            "https://github.com/owner/MyApp/issues/3",
            window: "Issue #3",
            workspace: "owner/MyApp",
            appID: "com.apple.mobilesafari"
        )
        let blocks = try [
            ActivityFixture.block("2024-03-11", "09:00", "10:00", [
                (ActivityFixture.terminal(), 1800),
                (ActivityFixture.terminal(session: "docs"), 600),
                (SectionFixture.page("https://github.com/owner/MyApp/pull/7", window: "Pull request #7", workspace: "owner/MyApp"), 900),
            ]),
            ActivityFixture.block("2024-03-11", "12:00", "12:20", [(phonePage, 1200)], device: "iPhone"),
        ]
        let rows = SectionFixture.summary(blocks).workspaceRows
        #expect(rows.map(\.workspace) == ["~/Code/MyApp", "owner/MyApp"])
        #expect(rows.map(\.seconds) == [2400, 2100])
        #expect(rows.map(\.hasItems) == [true, true])
        #expect(rows[0].items.map(\.label) == ["WezTerm · refactor-parser", "WezTerm · docs"])
        #expect(rows[0].items.map(\.seconds) == [1800, 600])
        #expect(rows[1].items.map(\.label) == ["Safari · Issue #3", "Safari · Pull request #7"])
        #expect(rows[1].items.map(\.seconds) == [1200, 900])
    }

    @Test(
        "PA-14 a workspace of a domain in private_domains has no items"
    )
    func privateDomainHasNoItems() async throws {
        var settings = TrackerSettings.defaults
        settings.privacy.privateDomains = ["example.org"]
        let account = SectionFixture.page("https://example.org/account", window: "Account", workspace: "example.org")
        let block = try ActivityFixture.block("2024-03-11", "09:00", "10:00", [(account, 1200), (ActivityFixture.terminal(), 600)])
        let reader: any ActivityReading = InMemoryActivityStore(blocks: [block], settings: settings, homeDirectory: "/Users/alex")
        let read = try await reader.blocks(in: SectionFixture.interval(SectionFixture.week), devices: nil)
        let summary = SectionFixture.summary(read, settings: reader.settings, exclusions: reader.exclusions)
        let row = try #require(summary.workspaceRows.first { $0.workspace == "example.org" })
        #expect(row.seconds == 1200)
        #expect(row.kind == .sites)
        #expect(!row.hasItems)
        #expect(summary.workspaceRows.first { $0.workspace == "~/Code/MyApp" }?.hasItems == true)
    }

    @Test(
        "PA-15 Away counts only gaps over idle_close between consecutive blocks of a day, by the end reason of the block before"
    )
    func away() throws {
        let mail = SectionFixture.mail
        let blocks = try [
            ActivityFixture.block("2024-03-11", "09:00", "10:00", [(mail, 3600)], reason: .idle),
            // 4 minutes after the block before: not away.
            ActivityFixture.block("2024-03-11", "10:04", "11:00", [(mail, 3000)], reason: .locked),
            ActivityFixture.block("2024-03-11", "12:00", "13:00", [(mail, 3600)], reason: .split),
            ActivityFixture.block("2024-03-11", "13:30", "13:40", [(mail, 600)], device: "iPhone", reason: .asleep),
            ActivityFixture.block("2024-03-11", "15:00", "16:00", [(mail, 3600)], reason: .stopped),
            // The night before the next day's first block is not away.
            ActivityFixture.block("2024-03-12", "09:00", "10:00", [(mail, 3600)], reason: .otherUser),
        ]
        let away = SectionFixture.summary(blocks).away
        #expect(away.seconds == 3600 + 1800 + 4800)
        #expect(away.parts == [
            ActivityAway.Part(cause: .locked, seconds: 3600, count: 1),
            ActivityAway.Part(cause: .asleep, seconds: 4800, count: 1),
            ActivityAway.Part(cause: .unknown, seconds: 1800, count: 1),
        ])
        #expect(away.totalText == "2h 50m during the day")
        #expect(away.partsText == "locked 1h (1 time) · asleep 1h 20m (1 time) · unknown 30m (1 time)")
        #expect(away.backgroundText == nil)

        // A gap of exactly idle_close is not longer than it.
        var settings = TrackerSettings.defaults
        settings.blocks.idleClose = 3600
        let asleep = ActivityAway.Part(cause: .asleep, seconds: 4800, count: 1)
        #expect(SectionFixture.summary(blocks, settings: settings).away.parts == [asleep])

        let causes = ActivityEndReason.allCases.map { ActivityAway.Cause(endReason: $0).title }
        #expect(causes == ["idle", "locked", "asleep", "another user", "Focus", "unknown", "unknown", "tracker stopped"])
        #expect(ActivityAway.Cause(endReason: nil) == .unknown)
        #expect(ActivityAway.Part(cause: .idle, seconds: 4200, count: 3).text == "idle 1h 10m (3 times)")
    }

    @Test(
        "PA-15 Away treats all devices as one timeline, so a block on one device inside a block on another leaves no gap"
    )
    func awayAcrossOverlappingDevices() throws {
        let blocks = try [
            ActivityFixture.block("2024-03-11", "09:00", "10:00", [(SectionFixture.mail, 3600)], reason: .idle),
            ActivityFixture.block("2024-03-11", "09:30", "09:45", [(SectionFixture.mail, 900)], device: "iPhone", reason: .asleep),
            ActivityFixture.block("2024-03-11", "10:30", "11:00", [(SectionFixture.mail, 1800)]),
        ]
        let away = SectionFixture.summary(blocks).away
        #expect(away.seconds == 1800)
        #expect(away.parts == [ActivityAway.Part(cause: .idle, seconds: 1800, count: 1)])
    }

    @Test(
        "PA-21 In the background adds background blocks' items with their part while away; Away tells how much they cover"
    )
    func backgroundWhileAway() throws {
        let build = ActivityItem(app: "tmux", appID: "tmux", session: "build:1.0", command: "make test", workspace: "~/Code/MyApp")
        let morning = try ActivityFixture.block(
            "2024-03-11", "09:00", "10:00", [(SectionFixture.mail, 3600)], background: [(ActivityFixture.agent, 600)]
        )
        let afternoon = try ActivityFixture.block("2024-03-11", "11:00", "12:00", [(SectionFixture.mail, 3600)], background: [(build, 300)])
        let whileAway = try ActivityFixture.block(
            "2024-03-11",
            "10:10",
            "10:48",
            [],
            background: [(ActivityFixture.agent, 2280)],
            reason: .split
        )
        #expect(whileAway.isBackgroundBlock)
        #expect(whileAway.activeSeconds == 0)

        let summary = SectionFixture.summary([morning, afternoon], background: [whileAway])
        #expect(summary.total == 7200)
        #expect(summary.backgroundRows.map(\.title) == ["Claude Code refactor-parser in MyApp", "tmux make test in MyApp"])
        #expect(summary.backgroundRows.map(\.seconds) == [2880, 300])
        #expect(summary.backgroundRows.map(\.awaySeconds) == [2280, 0])
        #expect(summary.away.seconds == 3600)
        #expect(summary.away.backgroundSeconds == 2280)
        #expect(summary.away.backgroundText == "Work went on in the background for 38m of it.")
        #expect(whileAway.backgroundText(jobCommands: TrackerSettings.defaults.terminal.jobCommands)
            == "In the background while away: Claude Code refactor-parser 38m")

        let without = SectionFixture.summary([morning, afternoon])
        #expect(without.away.backgroundText == nil)
        #expect(without.backgroundRows.map(\.awaySeconds) == [0, 0])

        let mail = SectionFixture.summary([morning, afternoon], background: [whileAway], apps: ["Mail"])
        #expect(mail.backgroundRows.isEmpty)
        #expect(mail.away.backgroundSeconds == 2280)
        let agent = SectionFixture.summary([morning, afternoon], background: [whileAway], apps: ["Claude Code"])
        #expect(agent.backgroundRows.map(\.awaySeconds) == [2280])
    }
}
