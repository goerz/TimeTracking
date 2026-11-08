// Browsers and the private-window test (activity_tracking.md §3.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct BrowserTests {
    static let pullRequest = "https://github.com/owner/repo/pull/123?diff=split#discussion"

    @Test("TRK-9 a Safari URL without a History.db visit in the last 24 hours is recorded as a private window with no URL")
    func safariPrivateWindow() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.apple.Safari", name: "Safari")
        let tab = AgentHarness.fixture("applescript/safari-pull-request.txt").trimmingCharacters(in: .newlines)
        harness.scripts.results["com.apple.Safari"] = .value(tab)
        // A visit older than 24 hours doesn't count.
        harness.history.safari = [(HistoryVisit(time: harness.time(-86_500), browser: "safari", url: Self.pullRequest, title: "PR"), 0)]
        await harness.workThenLock(for: 720)
        let hidden = ActivityItem(app: "Safari", appID: "com.apple.Safari", location: "(private)")
        let attentive = harness.liveSamples().filter(\.isAttentive)
        #expect(attentive.count == 25)
        #expect(attentive.allSatisfy { $0.foreground == hidden })
        #expect(harness.blocks(AgentHarness.today).first?.foreground.map(\.item) == [hidden])
        #expect(!harness.allOutput.contains("github.com"))
        #expect(!harness.allOutput.contains("Pull Request"))

        // Its visit shows up: the tab is a normal window's.
        await harness.unlock()
        harness.history.safari.append((HistoryVisit(time: harness.clock.now, browser: "safari", url: Self.pullRequest, title: "PR"), 0))
        harness.advance(30)
        let visible = try #require(await harness.tick()?.foreground)
        #expect(visible.location == Self.pullRequest)
        #expect(visible.window == "Fix the parser by owner · Pull Request #123")
    }

    @Test("TRK-9 Chromium incognito is never read, and Private Browsing in a window title marks a private window")
    func chromiumIncognito() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.google.Chrome", name: "Google Chrome")
        harness.scripts.results["com.google.Chrome"] = .value(AgentHarness.fixture("applescript/chrome-incognito.txt"))
        await harness.workThenLock(for: 720)
        #expect(harness.liveSamples().first?.foreground == ActivityItem(
            app: "Google Chrome",
            appID: "com.google.Chrome",
            location: "(private)"
        ))
        #expect(harness.blocks(AgentHarness.today).count == 1)
        #expect(!harness.allOutput.contains("example.org"))
        #expect(!harness.allOutput.contains("Account settings"))

        await harness.unlock()
        harness.frontmost("org.mozilla.firefox", name: "Firefox", title: "Docs — Private Browsing", url: "https://docs.example.com/guide")
        harness.advance(30)
        let firefox = try #require(await harness.tick()?.foreground)
        #expect(firefox == ActivityItem(app: "Firefox", appID: "org.mozilla.firefox", location: "(private)"))
        #expect(!harness.allOutput.contains("docs.example.com"))
    }
}
