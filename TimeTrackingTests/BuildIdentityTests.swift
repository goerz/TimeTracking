// The Debug Mac app's identity as built (spec_architecture.md §1.4, §1.5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

struct BuildIdentityTests {
    @Test("ARCH-6 the Debug Mac app carries the Debug identifiers")
    func debugIdentifiers() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        #expect(Bundle.main.bundleIdentifier == identity.appID)
        #expect(identity.appID == identity.bundleID + ".debug")
        #expect(identity.appGroup == "\(identity.teamID).\(identity.appID)")
        #expect(identity.cloudKitContainer == "iCloud.\(identity.appID)")
        #expect(identity.urlScheme == "timetracking-debug")
    }

    @Test("ARCH-6 the Debug app embeds the Debug agent and its launchd plist")
    func debugAgent() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        let contents = Bundle.main.bundleURL.appending(path: "Contents")
        let agent = try #require(Bundle(url: contents.appending(path: "Library/LoginItems/TimeTrackingAgent.app")))
        #expect(agent.bundleIdentifier == identity.appID + ".agent")
        let plistURL = contents.appending(path: "Library/LaunchAgents/\(identity.agentPlistName)")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == identity.agentBundleID)
        #expect(plist["BundleProgram"] as? String == "Contents/Library/LoginItems/TimeTrackingAgent.app/Contents/MacOS/TimeTrackingAgent")
    }
}
