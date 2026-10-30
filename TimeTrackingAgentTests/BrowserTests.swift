// Browsers and the private-window test (spec_activity_tracking.md §3.3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

@MainActor
struct BrowserTests {
    static let pullRequest = "https://github.com/owner/repo/pull/123?diff=split#discussion"

    @Test("TRK-7 a Safari URL without a History.db visit is safari (private) and leaves the samples")
    func safariPrivateWindow() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        await harness.run(for: 240)
        let samples = harness.samples()
        #expect(samples.allSatisfy { sample in sample.primary == SampleItem(
            context: "safari",
            subject: "(private)",
            groupKey: "safari",
            app: "com.apple.Safari"
        ) })
        #expect(!samples.contains { !$0.url.isEmpty })
        #expect(!harness.allOutput.contains("github.com"))

        harness.history.safari = [(HistoryVisit(time: harness.clock.now, browser: "safari", url: Self.pullRequest, title: "PR"), 0)]
        let visible = await harness.engine.tick()
        #expect(visible.primary == SampleItem(
            context: "safari",
            subject: "github.com/owner/repo",
            detail: "pull/123",
            groupKey: "github.com/owner",
            app: "com.apple.Safari"
        ))
        #expect(visible.url == Self.pullRequest)
    }

    /// History.db is written late, so a normal window's visit may show up
    /// minutes after the tab is first sampled. Until it does, samples are
    /// private (stricter than the spec, which leaves 3 minutes: the URL
    /// never enters the samples unverified).
    @Test("TRK-7 a Safari URL stays safari (private) through 4 minutes without a visit; a visit showing up after 2 minutes reveals it")
    func safariVisitWindow() async throws {
        let privateItem = SampleItem(context: "safari", subject: "(private)", groupKey: "safari", app: "com.apple.Safari")
        let harness = try AgentHarness()
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        let firstSample = harness.clock.now
        for tick in 0 ..< 4 {
            if tick > 0 {
                harness.advance(30)
            }
            let sample = await harness.engine.tick()
            #expect(sample.primary == privateItem)
            #expect(sample.url.isEmpty)
        }
        // Two minutes in, Safari's history gets the visit of the page load.
        harness.advance(30)
        harness.history.safari = [(HistoryVisit(time: firstSample, browser: "safari", url: Self.pullRequest, title: "PR"), 0)]
        let revealed = await harness.engine.tick()
        #expect(revealed.primary?.subject == "github.com/owner/repo")
        #expect(revealed.url == Self.pullRequest)

        let unvisited = try AgentHarness()
        unvisited.frontmost("com.apple.Safari", name: "Safari")
        unvisited.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        await unvisited.run(for: 270)
        #expect(unvisited.samples().count >= 9)
        #expect(unvisited.samples().allSatisfy { $0.primary == privateItem && $0.url.isEmpty })
        #expect(!unvisited.allOutput.contains("github.com"))
    }

    @Test("TRK-7 Chromium incognito yields <browser> (private) with no URL")
    func chromiumIncognito() async throws {
        let harness = try AgentHarness()
        harness.frontmost("com.google.Chrome", name: "Google Chrome")
        harness.scripts.results["com.google.Chrome"] = .value(AgentHarness.fixture("applescript/chrome-incognito.txt"))
        let sample = await harness.engine.tick()
        #expect(sample.primary == SampleItem(context: "chrome", subject: "(private)", groupKey: "chrome", app: "com.google.Chrome"))
        #expect(sample.url.isEmpty)
        #expect(sample.title.isEmpty)
        #expect(!harness.allOutput.contains("example.org"))
        #expect(!harness.allOutput.contains("Account settings"))
    }

    @Test("TRK-7 without Full Disk Access Safari URLs keep only the domain")
    func safariWithoutFullDiskAccess() async throws {
        let harness = try AgentHarness()
        harness.history.canReadSafari = false
        harness.frontmost("com.apple.Safari", name: "Safari")
        harness.scripts.results["com.apple.Safari"] = .value(AgentHarness.fixture("applescript/safari-pull-request.txt"))
        let sample = await harness.engine.tick()
        #expect(sample.primary?.subject == "github.com")
        #expect(sample.primary?.detail.isEmpty == true)
        #expect(sample.url.isEmpty)
        #expect(harness.health("history")?.status == .fallback)
    }

    @Test("TRK-7 without Automation the tab comes from AXURL and Private Browsing in the title marks a private window")
    func accessibilityFallback() async throws {
        let harness = try AgentHarness()
        harness.frontmost("org.mozilla.firefox", name: "Firefox", title: "Docs — Private Browsing", url: "https://docs.example.com/guide")
        let hidden = await harness.engine.tick()
        #expect(hidden.primary?.subject == "(private)")
        harness.frontmost("com.google.Chrome", name: "Google Chrome", title: "Guide", url: "https://docs.example.com/guide")
        harness.scripts.results["com.google.Chrome"] = .denied
        harness.advance(30)
        let shown = await harness.engine.tick()
        #expect(shown.primary?.subject == "docs.example.com")
        #expect(shown.primary?.detail == "guide")
        #expect(harness.health("browser")?.status == .fallback)
    }
}
