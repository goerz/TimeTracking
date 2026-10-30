// The Debug agent's identity as built (spec_architecture.md §1.4, §1.5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingAgent

struct AgentIdentityTests {
    @Test("ARCH-6 the Debug agent's bundle identifier is <BUNDLE_ID>.debug.agent")
    func debugAgentIdentifier() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        #expect(identity.appID == identity.bundleID + ".debug")
        #expect(Bundle.main.bundleIdentifier == identity.agentBundleID)
        #expect(identity.appGroup == "\(identity.teamID).\(identity.appID)")
    }
}
