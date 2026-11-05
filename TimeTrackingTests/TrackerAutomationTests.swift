// "Ask for Access" on the Tracker pane's Automation row
// (activity_tracking.md §7.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

@MainActor
struct TrackerAutomationTests {
    @Test("TRK-37 Ask for Access asks for every scriptable browser and terminal, and the Automation row lists each open app's answer")
    func askForAutomation() async throws {
        let automation = FakeAutomationPermission(running: [
            "com.apple.Safari": AutomationOutcome(name: "Safari", answer: .allowed),
            "com.googlecode.iterm2": AutomationOutcome(name: "iTerm2", answer: .allowed),
            "com.google.Chrome": AutomationOutcome(name: "Google Chrome", answer: .declined),
        ])
        let tracker = TrackerStatusModel(
            agent: FakeAgentService(),
            automation: automation,
            clock: ManualClock.fixture(),
            readState: { nil }
        )
        await tracker.refresh()
        func step() throws -> TrackerSetupStep {
            try #require(tracker.setupSteps.first { $0.id == "automation" })
        }
        #expect(try step().actions == [.askAutomation, .openSettings(anchor: "Privacy_Automation")])
        #expect(try step().actions.first?.title == "Ask for Access")
        #expect(try step().outcome == nil)
        #expect(automation.requests.isEmpty)

        await tracker.askForAutomation()
        #expect(automation.requests == [AutomationTargets.bundleIDs])
        #expect(try step().outcome == "Allowed: Safari and iTerm2. Declined: Google Chrome; turn it on in System Settings.")

        automation.running = [:]
        await tracker.askForAutomation()
        #expect(try step().outcome == "None of the browsers and terminals the tracker asks are open.")
        #expect(TrackerStatusModel.automationOutcomeLine([
            AutomationOutcome(name: "Arc", answer: .declined),
            AutomationOutcome(name: "Terminal", answer: .declined),
            AutomationOutcome(name: "Brave Browser", answer: .failed),
        ]) == "Declined: Arc and Terminal; turn them on in System Settings. Couldn't ask: Brave Browser.")
    }
}
