// The block summary, the redaction filters, and the exclusions applied to
// Items (activity_tracking.md §2.8, §4.3, §7.2).

import Foundation
import Testing
@testable import TimeTrackingCore

struct SummaryAndPrivacyTests {
    @Test(
        "TRK-48 summary: workspaces by share, at most summary_lines lines, the rest in +n more, three background items, footer if rebuilt"
    )
    func blockSummary() throws {
        var settings = TrackerSettings()
        settings.blocks.summaryLines = 3
        let items: [(ActivityItem, Int)] = [
            (ActivityFixture.terminal("MyApp"), 1500),
            (ActivityFixture.page("https://github.com/owner/MyApp/pull/1", workspace: "~/Code/MyApp"), 600),
            (ActivityItem(app: "Skim", documents: ["~/Papers/2026_Noise/notes.pdf"], workspace: "~/Papers/2026_Noise"), 700),
            (ActivityItem(app: "WezTerm", session: "paper:draft.1", workspace: "~/Papers/2026_Noise"), 300),
            (ActivityFixture.app("Mail"), 100),
        ]
        let jobs = ActivityItem(app: "tmux", session: "paper:build.0", command: "make test", workspace: "~/Code/MyApp")
        let block = try ActivityFixture.block(
            "2024-03-14",
            "09:00",
            "10:00",
            items,
            background: [
                (ActivityFixture.agent, 2000),
                (jobs, 500),
                (ActivityFixture.app("Music"), 400),
                (ActivityFixture.app("Backup"), 300),
            ]
        )
        let summary = ActivityBlockSummary(block: block, settings: settings)
        #expect(summary.groups.map(\.name) == ["MyApp", "2026_Noise"])
        #expect(summary.groups.first?.subtitle == "~/Code/MyApp")
        #expect(summary.groups.flatMap(\.lines).map(\.label) == ["WezTerm · refactor-parser", "Safari · Page", "Skim · notes.pdf"])
        #expect(summary.moreCount == 2)
        #expect(summary.background.map(\.label) == ["Claude Code · refactor-parser", "tmux · make test", "Music"])
        #expect(summary.reconstructedSeconds == 0)
        #expect(ActivityBlockSummary(block: block, settings: settings, extent: .everything).groups.flatMap(\.lines).count == 5)
    }

    @Test("TRK-48 summary: items that read the same are one line with their seconds added, where the first of them was")
    func blockSummaryMergesSameLabel() throws {
        func page(_ number: Int) -> ActivityItem {
            ActivityItem(
                app: "Skim",
                window: "notes.pdf – Page \(number) of 20",
                documents: ["~/Papers/2026_Noise/notes.pdf"],
                workspace: "~/Papers/2026_Noise"
            )
        }
        let draft = ActivityItem(app: "WezTerm", session: "paper:draft.1", workspace: "~/Papers/2026_Noise")
        let build = { (location: String) in
            ActivityItem(app: "tmux", session: "paper:build.0", location: location, command: "make test", workspace: "~/Papers/2026_Noise")
        }
        let block = try ActivityFixture.block(
            "2024-03-14",
            "09:00",
            "10:00",
            [(page(1), 120), (page(2), 300), (draft, 600), (page(3), 60)],
            background: [(build("~/Papers/2026_Noise"), 200), (ActivityFixture.agent, 250), (build("~/Papers/2026_Noise/notes"), 100)]
        )
        let summary = ActivityBlockSummary(block: block, settings: TrackerSettings(), extent: .everything)
        let lines = summary.groups.flatMap(\.lines)
        #expect(lines.map(\.label) == ["Skim · notes.pdf", "WezTerm · paper:draft.1"])
        #expect(lines.map(\.seconds) == [480, 600])
        #expect(summary.background.map(\.label) == ["tmux · make test", "Claude Code · refactor-parser"])
        #expect(summary.background.map(\.seconds) == [300, 250])
    }

    @Test(
        "TRK-12 each default redaction filter replaces only the secret with (private) in what leaves the Mac; the Sample keeps it"
    )
    func redaction() throws {
        let redactor = Redactor(privacy: TrackerPrivacySettings())
        #expect(redactor.redacted("deploy --token abc123 --verbose") == "deploy --token (private) --verbose")
        #expect(redactor.redacted("deploy --password=hunter2") == "deploy --password=(private)")
        #expect(redactor.redacted("API_TOKEN=xyz make") == "API_TOKEN=(private) make")
        #expect(redactor.redacted("curl -H 'Authorization: Bearer abc'") == "curl -H 'Authorization: (private)")
        #expect(redactor.redacted("https://alex:pw@example.com/x") == "https://(private)@example.com/x")
        #expect(redactor.redacted("https://example.com/cb?code=42&state=ok") == "https://example.com/cb?code=(private)&state=ok")
        #expect(redactor.redacted("https://www.google.com/search?q=private+matter") == "https://www.google.com/search?(private)")
        let curl = "curl 'https://api.example/v1?token=abc&page=2'"
        #expect(redactor.redacted(curl) == "curl 'https://api.example/v1?token=(private)&page=2'")
        #expect(redactor.redacted("nvim notes.tex") == "nvim notes.tex")

        let rig = try RebuildRig()
        let item = ActivityItem(app: "WezTerm", location: "~/Code/MyApp", command: "deploy --token abc123", workspace: "~/Code/MyApp")
        var timeline = SampleTimeline()
        timeline.work("09:00", "09:20", item)
        timeline.away("09:20", "09:40")
        try rig.insert(timeline)
        try rig.run(now: .distantFuture)
        #expect(rig.blocks("2024-03-14").first?.foreground.first?.item.command == "deploy --token (private)")
        let stored = try rig.store.samples(SampleSelection(range: DateInterval(start: .distantPast, end: .distantFuture)))
        #expect(stored.first?.foreground?.command == "deploy --token abc123")
    }

    @Test("TRK-11 each exclusion of §7.2 changes an Item as its table says")
    func exclusions() {
        var privacy = TrackerPrivacySettings()
        privacy.excludePaths = ["~/Documents/Medical"]
        privacy.excludeKeywords = ["sparsebundle"]
        privacy.excludeTmuxSessions = ["secret"]
        privacy.privateAgentPaths = ["~/Private"]
        privacy.nameOnlyApps = ["com.1password.1password"]
        privacy.excludeApps = ["com.example.vault"]
        privacy.privateDomains = ["bank.example"]
        privacy.excludeDomains = ["shop.example"]
        privacy.excludeTitleKeywords = ["Diagnosis"]
        let rules = ExclusionRules(privacy: privacy, homeDirectory: "/Users/alex")

        let medical = rules.applied(to: ActivityItem(
            app: "Skim",
            window: "scan.pdf",
            session: "s",
            location: "~/Documents/Medical",
            documents: ["~/Documents/Medical/scan.pdf"],
            command: "open scan.pdf",
            workspace: "~/Documents/Medical"
        ))
        #expect(medical == ActivityItem(
            app: "Skim",
            window: "(private)",
            session: "s",
            location: "(private)",
            documents: ["(private)"],
            command: "(private)",
            workspace: "private"
        ))
        #expect(rules.applied(to: ActivityItem(app: "Finder", location: "/Volumes/SparseBundle-2024"))?.workspace == "private")
        let secret = ActivityItem(app: "WezTerm", window: "w", session: "secret:1.0", location: "~/x", command: "vim", workspace: "~/x")
        #expect(rules.applied(to: secret) == ActivityItem(app: "WezTerm", session: "(private)", workspace: "private"))
        let privateFolder = ActivityItem(
            app: "Claude Code",
            appID: "claude",
            session: "notes",
            location: "~/Private",
            command: "claude",
            workspace: "~/Private"
        )
        #expect(rules.applied(to: privateFolder) == ActivityItem(app: "Claude Code", appID: "claude", session: "notes"))
        let password = ActivityItem(app: "1Password", appID: "com.1password.1password", window: "Bank login")
        #expect(rules.applied(to: password) == ActivityItem(app: "1Password", appID: "com.1password.1password"))
        #expect(rules.applied(to: ActivityItem(app: "Vault", appID: "com.example.vault")) == nil)
        #expect(rules.applied(to: ActivityFixture.page("https://www.bank.example/accounts/1", workspace: "bank.example"))
            == ActivityItem(app: "Safari", appID: "com.apple.Safari", location: "https://bank.example", workspace: "bank.example"))
        #expect(rules.applied(to: ActivityFixture.page("https://shop.example/cart", workspace: "shop.example"))
            == ActivityItem(app: "Safari", appID: "com.apple.Safari", location: "(private)"))
        #expect(rules.applied(to: ActivityItem(app: "Mail", window: "Re: Diagnosis"))?.window.isEmpty == true)
    }
}
