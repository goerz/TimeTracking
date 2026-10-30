// The Mac app's URL scheme and the store path it opens
// (spec_automation.md §6, §9 item 38; spec_architecture.md ARCH-19).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct URLRouterTests {
    private func router(_ test: TestApp) -> (URLRouter, AlertLog) {
        let log = AlertLog()
        let router = URLRouter(app: test.app, scheme: "timetracking-debug")
        router.alert = { log.messages.append($0) }
        return (router, log)
    }

    @Test("AUTO-38 a start URL starts the entry with a banner and no window; an unknown project and an unknown URL show alerts")
    func startURL() async throws {
        let test = try await TestApp()
        _ = try await test.projects(["Noise paper"])
        let (router, alerts) = router(test)
        let outcome = try await router.open(#require(URL(string: "timetracking-debug://start?project=Noise%20paper&task=Hello")))
        #expect(outcome == .tracked("Started Noise paper"))
        #expect(test.app.timer.running?.task == "Hello")
        #expect(test.notifier.posted.last?.title == "Started Noise paper")
        #expect(test.router.calls.isEmpty)
        let missing = try await router.open(#require(URL(string: "timetracking-debug://start?project=Nonexistent")))
        #expect(missing == .failed("No project named \"Nonexistent\"."))
        #expect(test.app.timer.running?.task == "Hello")
        let unknown = try await router.open(#require(URL(string: "timetracking-debug://delete")))
        #expect(unknown == .failed("This link isn't one the app understands."))
        #expect(alerts.messages == ["No project named \"Nonexistent\".", "This link isn't one the app understands."])
        #expect(try await test.store.projects(filter: ProjectFilter(state: .all)).count == 1)
    }

    @Test("AUTO-38 stop and continue URLs act in the background; show and planner URLs open windows")
    func otherURLs() async throws {
        let test = try await TestApp()
        try await test.entry("Earlier", from: "08:00", to: "09:00")
        let (router, _) = router(test)
        #expect(try await router.open(#require(URL(string: "timetracking-debug://continue"))) == .tracked("Started Earlier."))
        #expect(test.app.timer.running?.task == "Earlier")
        #expect(try await router.open(#require(URL(string: "timetracking-debug://stop"))) == .tracked("Stopped Earlier"))
        #expect(test.app.timer.running == nil)
        #expect(test.router.calls.isEmpty)
        #expect(try await router.open(#require(URL(string: "timetracking-debug://show"))) == .shown)
        #expect(try await router.open(#require(URL(string: "timetracking-debug://planner/calendar?date=2024-03-14"))) == .shown)
        #expect(test.router.calls == [.showTimer(focusTask: false), .openPlanner])
    }

    @Test("ARCH-19 the Debug app's store is in the Debug group container, never the Release one")
    func debugStorePath() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let url = try #require(TimeStore.Location.defaultFile(for: identity))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let container = "\(home)/Library/Group Containers/\(identity.teamID).\(identity.appID)"
        #expect(url.path == container + "/Library/Application Support/TimeTracking/store.sqlite")
        #expect(identity.appID.hasSuffix(".debug"))
    }
}

/// The alerts a router showed.
@MainActor
final class AlertLog {
    var messages: [String] = []
}
