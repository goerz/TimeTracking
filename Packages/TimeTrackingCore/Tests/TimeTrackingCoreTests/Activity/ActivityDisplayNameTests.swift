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

    @Test func awayAndCoverageTexts() {
        #expect(ActivityAway.Part(cause: .idle, seconds: 4200, count: 3).text == "idle 1h 10m (3 times)")
        #expect(ActivityAway.Part(cause: .asleep, seconds: 600, count: 1).text == "asleep 10m (1 time)")
        #expect(ActivitySubjectKind.allCases.map(\.title) == ["All", "Sites", "Sessions", "Folders"])
    }
}
