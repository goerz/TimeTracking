// The apps "Ask for Access" asks for are the ones the agent scripts
// (activity_tracking.md §3.1, §3.3, §7.4).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

struct AutomationTargetsTests {
    @Test("TRK-55 Ask for Access asks for exactly the browsers and terminals the agent reads through Apple Events")
    func targetsMatchTheAgentTables() {
        let browsers = BrowserApp.known.filter { $0.value.scripting != .unscriptable }.keys
        let terminals = TerminalApp.known.filter { [.iterm, .terminal].contains($0.value.adapter) }.keys
        #expect(Set(AutomationTargets.bundleIDs) == Set(browsers).union(terminals))
        #expect(Set(AutomationTargets.bundleIDs).count == AutomationTargets.bundleIDs.count)
    }
}
