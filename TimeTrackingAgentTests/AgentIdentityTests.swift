// The Debug agent's identity and folders as built (spec_architecture.md
// §1.4, §1.5).

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

    @Test("ARCH-19 the Debug agent's folder, store path, and socket are in the Debug group container, never the Release one")
    func debugAgentFolder() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let container = try #require(identity.groupContainerURL)
        let debugGroup = "Library/Group Containers/\(identity.teamID).\(identity.bundleID).debug"
        #expect(container.path.hasSuffix(debugGroup))
        #expect(identity.supportDirectory(in: container).path.contains(debugGroup + "/Library/Application Support/TimeTracking"))
        #expect(identity.storeURL(in: container).path.hasSuffix(debugGroup + "/Library/Application Support/TimeTracking/store.sqlite"))
        #expect(identity.agentSocketURL(in: container).lastPathComponent == "tracker.sock")
        #expect(!container.path.hasSuffix("\(identity.teamID).\(identity.bundleID)"))
    }
}
