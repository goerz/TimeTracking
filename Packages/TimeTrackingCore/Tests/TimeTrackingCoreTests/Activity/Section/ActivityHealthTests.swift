// The Activity section's health footer, empty states, and exclusion drafts
// (activity.md §1.9, §1.10, §4, §5).

import Foundation
import Testing
import TimeTrackingCore

struct ActivityHealthTests {
    @Test(
        "PA-16 the Mac footer's dot and line match the Tracker pane for one current.json and list only sources with a problem"
    )
    func macFooter() throws {
        let now = try ActivityFixture.instant("2024-03-14T14:20:00-04:00")
        let sources = [
            TrackerSourceHealth(id: "window", name: "Window titles", status: .active),
            TrackerSourceHealth(id: "history", name: "Browser history", status: .fallback, reason: "Full Disk Access is off"),
            TrackerSourceHealth(id: "knowledge", name: "Knowledge", status: .off),
            TrackerSourceHealth(id: "tmux", name: "tmux", status: .active),
        ]
        let state = SectionFixture.trackerState(block: nil, lastTick: now - 12, sources: sources)
        let health = ActivityHealth(registration: .enabled, state: state, now: now)
        #expect(health.dot == .green)
        #expect(health.statusLine == "Tracker running · checked 12 s ago")
        #expect(health.problems == ["Browser history: Full Disk Access is off", "App usage history: Off"])
        #expect(health.tooltip == ["Tracker version 1.0", "Now: WezTerm · refactor-parser · MyApp", "In use"])

        let cases = [
            FooterCase(.enabled, age: 12, .green), FooterCase(.enabled, age: 95, .yellow), FooterCase(.enabled, age: 130, .red),
            FooterCase(.enabled, age: nil, .red), FooterCase(.requiresApproval, age: 12, .green),
            FooterCase(.notRegistered, age: 12, .gray), FooterCase(.notFound, age: nil, .gray),
        ]
        for test in cases {
            let state = test.age.map { SectionFixture.trackerState(block: nil, lastTick: now - $0) }
            let footer = ActivityHealth(registration: test.registration, state: state, now: now)
            let pane = TrackerLiveness(registration: test.registration, state: state, now: now)
            #expect(footer.dot == test.dot)
            #expect(footer.statusLine == pane.statusLine(now: now))
            #expect(footer.isRed == (test.dot == .red))
        }
    }

    @Test("PA-16 the iPad footer shows lastTick from LiveState with the presence in the tooltip and no source list")
    func padFooter() throws {
        let now = try ActivityFixture.instant("2024-03-14T14:20:00-04:00")
        var remote = LiveState.MacActivity(
            device: "MacBook",
            foreground: ActivityFixture.terminal(),
            groupKey: "~/Code/MyApp",
            presence: "idle",
            since: now - 300,
            agentRunning: true,
            lastTick: now - 120,
            health: ["shared_folder"],
            updatedAt: now
        )
        let running = ActivityHealth(remote: remote, now: now)
        #expect(running.dot == .green)
        #expect(running.statusLine == "Mac tracker: checked 2 min ago")
        #expect(running.problems == ["iCloud Drive needs attention on the Mac"])
        #expect(running.tooltip == ["Idle for 5 min"])
        remote.agentRunning = false
        remote.lastTick = now - 7200
        remote.health = []
        let stopped = ActivityHealth(remote: remote, now: now)
        #expect(stopped.dot == .gray)
        #expect(stopped.statusLine == "Mac tracker: last checked 2 h ago")
        #expect(stopped.problems.isEmpty)
        remote.lastTick = nil
        #expect(ActivityHealth(remote: remote, now: now).statusLine == "Mac tracker: not checked yet")
    }

    @Test("PA-18 with an empty log and no tracker set up the setup card shows; after a block exists it does not return")
    func emptyStates() throws {
        let now = try ActivityFixture.instant("2024-03-14T14:20:00-04:00")
        let ready = SectionFixture.trackerState(block: nil, lastTick: now)
        let window = TrackerSourceHealth(id: "window", name: "Window titles", status: .off, reason: "Accessibility is off")
        let noAccessibility = SectionFixture.trackerState(block: nil, lastTick: now, sources: [window])
        #expect(ActivityEmptyState.trackerSetUp(registration: .enabled, state: ready))
        #expect(!ActivityEmptyState.trackerSetUp(registration: .notRegistered, state: ready))
        #expect(!ActivityEmptyState.trackerSetUp(registration: .enabled, state: nil))
        #expect(!ActivityEmptyState.trackerSetUp(registration: .enabled, state: noAccessibility))

        let empty = SectionFixture.summary([])
        #expect(ActivityEmptyState.resolve(summary: empty, everSawBlock: false, trackerSetUp: false, footerRed: true) == .setup)
        #expect(ActivityEmptyState
            .resolve(summary: empty, everSawBlock: true, trackerSetUp: false, footerRed: true) == .noActivity(trackerNotRunning: true))
        #expect(ActivityEmptyState
            .resolve(summary: empty, everSawBlock: false, trackerSetUp: true, footerRed: false) == .noActivity(trackerNotRunning: false))
        let block = try ActivityFixture.block("2024-03-11", "09:00", "10:00", [(SectionFixture.mail, 3600)])
        let some = SectionFixture.summary([block])
        #expect(ActivityEmptyState.resolve(summary: some, everSawBlock: false, trackerSetUp: false, footerRed: false) == .panels)
        let other = SectionFixture.summary([block], apps: ["Safari"])
        #expect(ActivityEmptyState.resolve(summary: other, everSawBlock: true, trackerSetUp: true, footerRed: false) == .nothingForApps)
        #expect(ActivityEmptyState.noActivityText(TrackingDay(year: 2024, month: 3, day: 4) ... SectionFixture.week.lowerBound)
            == "No activity recorded between Mar 4 and Mar 11")
        #expect(ActivityEmptyState.noActivityText(SectionFixture.thursday ... SectionFixture.thursday) == "No activity recorded on Mar 14")
    }

    @Test(
        "PA-19 Exclude from Tracking drafts an app's bundle identifier, a folder workspace's path, or a site's bare domain"
    )
    func exclusionDrafts() throws {
        #expect(TrackerExclusionDraft.forApp(appID: "com.apple.mail", kind: .other) == .app(bundleIdentifier: "com.apple.mail"))
        #expect(TrackerExclusionDraft.forApp(appID: "com.github.wez.wezterm", kind: .terminal)?.value == "com.github.wez.wezterm")
        #expect(TrackerExclusionDraft.forApp(appID: "com.apple.Safari", kind: .browser) == nil)
        #expect(TrackerExclusionDraft.forApp(appID: "", kind: .other) == nil)
        let arxiv = ActivityItem(
            app: "Safari",
            appID: "com.apple.Safari",
            window: "arXiv",
            location: "https://www.arxiv.org/abs/2401.00001",
            workspace: "www.arxiv.org"
        )
        let block = try ActivityFixture.block("2024-03-11", "09:00", "10:00", [
            (ActivityFixture.terminal(), 1800), (arxiv, 600), (SectionFixture.mail, 300),
            (
                ActivityItem(
                    app: "Skim",
                    appID: "net.sourceforge.skim-app.skim",
                    location: "(private)",
                    workspace: ActivityItem.privateWorkspace
                ),
                200
            ),
        ])
        let rows = SectionFixture.summary([block]).workspaceRows
        #expect(rows.map(\.workspace) == ["~/Code/MyApp", "www.arxiv.org", "Mail", "private"])
        #expect(rows.map(TrackerExclusionDraft.forWorkspace) == [.path("~/Code/MyApp"), .domain("arxiv.org"), nil, nil])
    }

    @Test(
        "PA-19 a site workspace named by a URL pattern drafts its page's bare domain"
    )
    func siteDraftFromPattern() throws {
        let page = SectionFixture.page("https://github.com/owner/MyApp/pull/7", window: "Pull request #7", workspace: "owner/MyApp")
        let block = try ActivityFixture.block("2024-03-11", "09:00", "10:00", [(page, 600)])
        let row = try #require(SectionFixture.summary([block]).workspaceRows.first)
        #expect(row.kind == .sites)
        #expect(TrackerExclusionDraft.forWorkspace(row) == .domain("github.com"))
    }
}

/// A registration, the age of the last tick (no `current.json` without), and the footer's dot.
private struct FooterCase {
    var registration: AgentRegistration
    var age: TimeInterval?
    var dot: ActivityHealthDot

    init(_ registration: AgentRegistration, age: TimeInterval?, _ dot: ActivityHealthDot) {
        self.registration = registration
        self.age = age
        self.dot = dot
    }
}
