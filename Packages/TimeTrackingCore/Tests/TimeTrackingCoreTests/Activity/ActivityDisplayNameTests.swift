// The names of apps, sessions, sites, folders, and devices on screen
// (spec_activity.md §1.3; spec_design.md §12).

import Foundation
import Testing
@testable import TimeTrackingCore

struct ActivityDisplayNameTests {
    @Test func appNames() {
        #expect(ActivityContext("vscode").displayName() == "VS Code")
        #expect(ActivityContext("powerpoint").displayName() == "PowerPoint")
        #expect(ActivityContext("mail").displayName() == "Mail")
        #expect(ActivityContext("activity monitor").displayName() == "Activity Monitor")
        #expect(ActivityContext("iPhone games").displayName() == "iPhone games")
        #expect(ActivityContext("mail").displayName(bundleIdentifier: "com.apple.mail") { _ in "Apple Mail" } == "Apple Mail")
        #expect(ActivityContext("safari").displayName() == "Safari")
        #expect(ActivityContext("tmux:paper").displayName() == "paper")
        #expect(ActivityContext("tmux:(private)").displayName() == "(private session)")
    }

    @Test func labels() {
        #expect(ActivityContext("tmux:paper").label() == "paper (tmux)")
        #expect(ActivityContext("tmux:(private)").label() == "(private session)")
        #expect(ActivityContext("claude").label() == "Claude")
        #expect(ActivityContext("chrome").label() == "Chrome")
    }

    @Test func groupKeys() {
        #expect(ActivityContext.groupKeyName("tmux:paper") == "paper (tmux)")
        #expect(ActivityContext.groupKeyName("safari") == "Safari")
        #expect(ActivityContext.groupKeyName("github.com/owner") == "github.com/owner")
        #expect(ActivityContext.groupKeyName("example.org") == "example.org")
        #expect(ActivityContext.groupKeyName("~/Documents/Papers/2026_Noise") == "~/Documents/Papers/2026_Noise")
        #expect(ActivityContext.groupKeyName("vscode") == "VS Code")
        #expect(ActivityContext.groupKeyName("private") == "(private)")
    }

    @Test func devices() {
        #expect(ActivityContext.deviceName("remote") == "Other devices (Safari)")
        #expect(ActivityContext.deviceName("MacBook") == "MacBook")
    }

    @Test func backgroundTitles() {
        #expect(ActivityBackgroundRow.title(context: "claude", subject: "refactor-parser") == "Claude refactor-parser")
        #expect(ActivityBackgroundRow.title(context: "tmux:paper", subject: "~/Code/app") == "paper (tmux) in ~/Code/app")
        #expect(ActivityBackgroundRow.title(context: "claude", subject: "") == "Claude")
    }

    @Test func rulePatterns() {
        #expect(SuggestionRule(kind: .groupKey, pattern: "tmux:paper").patternText == "paper (tmux)")
        #expect(SuggestionRule(kind: .context, pattern: "vscode").patternText == "VS Code")
        #expect(SuggestionRule(kind: .subjectPrefix, pattern: "~/Papers").patternText == "~/Papers")
        #expect(SuggestionRule.Kind.allCases.map(\.title) == ["Session, site, or folder", "App", "Starts with", "Event title contains"])
    }

    @Test func fillDaySummary() throws {
        let start = try ActivityFixture.instant("2026-10-26T09:00:00-04:00")
        func block(_ minutes: Double, _ key: String, _ items: [ActivityItem]) -> ActivityBlock {
            ActivityBlock(
                start: start + minutes * 60,
                end: start + (minutes + 10) * 60,
                activeSeconds: 600,
                device: "macbook",
                groupKey: key,
                groupShare: 0.71,
                items: items,
                utcOffset: -4 * 3600
            )
        }
        let blocks = [
            block(0, "tmux:paper", [ActivityItem(context: "tmux:paper", subject: "draft", detail: "", seconds: 600)]),
            block(10, "safari", [ActivityItem(context: "safari", subject: "github.com/owner", detail: "", seconds: 600)]),
            block(20, "mail", [ActivityItem(context: "mail", subject: "Inbox", detail: "", seconds: 600)]),
        ]
        let interval = DateInterval(start: start, duration: 1800)
        let query = SuggestionQuery(parts: [], interval: interval, timeZone: .gmt)
        let three = FillDayProposal(interval: interval, blocks: blocks, query: query, candidates: [])
        #expect(three.summary == "paper (tmux) and 2 more")
        #expect(three.itemsText == "paper (tmux) draft 10m\nSafari github.com/owner 10m\nMail Inbox 10m")
        let one = FillDayProposal(interval: interval, blocks: Array(blocks.prefix(1)), query: query, candidates: [])
        #expect(one.summary == "paper (tmux)")
    }

    @Test func awayAndCoverageTexts() {
        #expect(ActivityAway.Part(cause: .idle, seconds: 4200, count: 3).text == "idle 1h 10m (3 times)")
        #expect(ActivityAway.Part(cause: .asleep, seconds: 600, count: 1).text == "asleep 10m (1 time)")
        #expect(ActivitySubjectKind.allCases.map(\.title) == ["All", "Sites", "Sessions", "Folders"])
    }
}
