// The Activity section's header, app chips, and Apps and Workspaces lists
// (activity.md §1.2, §1.3, §1.6).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityHeaderTests {
    @Test(
        "PA-1 the header sums active time after exclusions, or the selected apps' seconds; device totals sum to it, shown for several"
    )
    func headerTotals() async throws {
        let vault = ActivityFixture.app("Vault", appID: "com.example.vault")
        let blocks = try [
            ActivityFixture.block(
                "2024-03-11",
                "09:00",
                "10:00",
                [(ActivityFixture.terminal(), 1800), (SectionFixture.mail, 1200), (vault, 300)]
            ),
            ActivityFixture.block("2024-03-12", "09:00", "09:30", [(SectionFixture.mail, 1500)], device: "iPhone"),
        ]
        var settings = TrackerSettings.defaults
        settings.privacy.excludeApps = ["com.example.vault"]
        let reader: any ActivityReading = InMemoryActivityStore(blocks: blocks, settings: settings, homeDirectory: "/Users/alex")
        let read = try await reader.blocks(in: SectionFixture.interval(SectionFixture.week), devices: nil)
        let all = SectionFixture.summary(read)
        #expect(all.total == 4500)
        #expect(all.total == read.reduce(0) { $0 + $1.activeSeconds })
        #expect(all.deviceTotals.map(\.device) == ["MacBook", "iPhone"])
        #expect(all.deviceTotals.map(\.seconds).reduce(0, +) == all.total)
        #expect(all.headerDetail == "2 days with activity · 37m per day · MacBook 50m · iPhone 25m")

        let mail = SectionFixture.summary(read, apps: ["Mail"])
        #expect(mail.total == 2700)
        #expect(mail.deviceTotals.map(\.device) == ["iPhone", "MacBook"])
        #expect(mail.deviceTotals.map(\.seconds).reduce(0, +) == mail.total)

        let single = SectionFixture.summary([read[0]])
        #expect(single.deviceTotals.isEmpty)
        #expect(single.headerDetail == "1 day with activity · 50m per day")
        let phone = SectionFixture.summary(read, device: "iPhone")
        #expect(phone.total == 1500)
        #expect(phone.devices.map(\.device) == ["MacBook", "iPhone"])
        #expect(ActivitySummary.DeviceTotal(device: ActivityBlockItem.remoteDevice, seconds: 1).displayName == "Other devices (Safari)")
    }

    @Test("PA-2 durations read Nh MMm from one hour, Nh on the hour, Mm below, Ss below one minute, and 0h for none")
    func durations() {
        #expect(ActivityText.duration(3600 + 300) == "1h 05m")
        #expect(ActivityText.duration(25 * 3600 + 120) == "25h 02m")
        #expect(ActivityText.duration(5 * 3600) == "5h")
        #expect(ActivityText.duration(3599) == "59m")
        #expect(ActivityText.duration(60) == "1m")
        #expect(ActivityText.duration(59) == "59s")
        #expect(ActivityText.duration(0) == "0h")
    }

    @Test("PA-4 the app filter narrows every panel but Away; over eight apps, the rest are behind N more and filter by the typed text")
    func filterAndMoreApps() throws {
        let names = ["WezTerm", "Safari", "Mail", "Zoom", "Skim", "Pages", "Notes", "Xcode", "Messages", "Music"]
        let blocks = try names.enumerated().map { index, name in
            try ActivityFixture.block(
                "2024-03-11",
                "\(10 + index):00",
                "\(10 + index):30",
                [(ActivityFixture.app(name), 1800 - index * 60)],
                background: index == 0 ? [(ActivityFixture.agent, 600)] : []
            )
        }
        let all = SectionFixture.summary(blocks)
        #expect(all.ranking.map(\.app) == names)
        #expect(all.moreApps(search: "").map(\.app) == ["Messages", "Music"])
        #expect(all.moreApps(search: "MUS").map(\.app) == ["Music"])
        #expect(all.moreApps(search: "Mail").isEmpty)
        #expect(all.away.seconds == 9 * 1800)
        #expect(all.backgroundRows.count == 1)

        let mail = SectionFixture.summary(blocks, apps: ["Mail"])
        #expect(mail.ranking.count == names.count)
        #expect(mail.total == 1680)
        #expect(mail.appRows.map(\.app) == ["Mail"])
        #expect(mail.workspaceRows.map(\.apps) == [["Mail"]])
        #expect(mail.bars.series == [.app("Mail")])
        #expect(mail.bars.bars[0].seconds == 1680)
        #expect(mail.heatmap.rows[0].seconds == 1680)
        #expect(mail.cellTooltip(row: mail.heatmap.rows[0], hour: 12).lines.map(\.app) == ["Mail"])
        #expect(mail.cellTooltip(row: mail.heatmap.rows[0], hour: 10).lines.isEmpty)
        #expect(mail.backgroundRows.isEmpty)
        #expect(mail.away == all.away)
    }

    @Test("PA-12 app shares stay relative to the unfiltered total, and without a filter the Apps rows sum to the header total")
    func appShares() throws {
        let page = SectionFixture.page("https://github.com/owner/MyApp", window: "MyApp", workspace: "owner/MyApp")
        let block = try ActivityFixture.block(
            "2024-03-11",
            "09:00",
            "10:00",
            [(ActivityFixture.terminal(), 1800), (SectionFixture.mail, 1200), (page, 600)]
        )
        let all = SectionFixture.summary([block])
        #expect(all.appRows.map(\.app) == ["WezTerm", "Mail", "Safari"])
        #expect(all.appRows.map(\.share) == [0.5, 1.0 / 3, 1.0 / 6])
        #expect(all.appRows.map(\.seconds).reduce(0, +) == all.total)
        #expect(all.appRows.map(\.kind) == [.terminal, .other, .browser])
        let mail = SectionFixture.summary([block], apps: ["Mail"])
        #expect(mail.total == 1200)
        #expect(mail.appRows.map(\.share) == [1.0 / 3])
    }

    @Test("PA-13 selecting only browsers switches Workspaces to Sites, any other selection or All to All; folders and sites are told apart")
    func workspaceKinds() throws {
        #expect(ActivityWorkspaceKind.automatic(for: [.browser]) == .sites)
        #expect(ActivityWorkspaceKind.automatic(for: [.browser, .browser]) == .sites)
        #expect(ActivityWorkspaceKind.automatic(for: [.browser, .terminal]) == .all)
        #expect(ActivityWorkspaceKind.automatic(for: [.terminal]) == .all)
        #expect(ActivityWorkspaceKind.automatic(for: [.other]) == .all)
        #expect(ActivityWorkspaceKind.automatic(for: []) == .all)
        let chrome = ActivityItem(
            app: "Chrome",
            appID: "com.google.Chrome",
            window: "arXiv",
            location: "https://arxiv.org/abs/2401.00001",
            workspace: "arxiv.org"
        )
        let block = try ActivityFixture.block("2024-03-11", "09:00", "10:00", [
            (ActivityFixture.terminal(), 1200),
            (SectionFixture.page("https://github.com/owner/MyApp/pull/7", window: "Pull request #7", workspace: "owner/MyApp"), 900),
            (chrome, 600),
            (SectionFixture.mail, 300),
        ])
        let summary = SectionFixture.summary([block])
        let kinds = summary.ranking.filter { ["Safari", "Chrome"].contains($0.app) }.map(\.kind)
        #expect(ActivityWorkspaceKind.automatic(for: kinds) == .sites)
        let rows = summary.workspaceRows
        #expect(rows.filter { $0.matches(.all) }.map(\.workspace) == ["~/Code/MyApp", "owner/MyApp", "arxiv.org", "Mail"])
        #expect(rows.filter { $0.matches(.folders) }.map(\.workspace) == ["~/Code/MyApp"])
        #expect(rows.filter { $0.matches(.sites) }.map(\.workspace) == ["owner/MyApp", "arxiv.org"])
        #expect(rows.map(\.name) == ["MyApp", "MyApp", "arxiv.org", "Mail"])
    }
}
