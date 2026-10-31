// The Debug Mac app's identity and names as built (spec_architecture.md §1.4,
// §1.5, §2.2).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

struct BuildIdentityTests {
    /// The one agent bundle in `Contents/Library/LoginItems`, whatever its
    /// Debug file name.
    private static func embeddedAgent() throws -> Bundle {
        let folder = Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems", directoryHint: .isDirectory)
        let apps = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        try #require(apps.count == 1)
        return try #require(Bundle(url: apps[0]))
    }

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
        let agent = try Self.embeddedAgent()
        #expect(agent.bundleIdentifier == identity.appID + ".agent")
        let plistURL = contents.appending(path: "Library/LaunchAgents/\(identity.agentPlistName)")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == identity.agentBundleID)
        #expect(plist["BundleProgram"] as? String ==
            "Contents/Library/LoginItems/\(agent.bundleURL.lastPathComponent)/Contents/MacOS/TimeTrackingAgent")
    }

    @Test("ARCH-24 the Debug app and agent carry Debug in their file, bundle, and display names; executables keep theirs")
    func debugNames() throws {
        let app = Bundle.main
        let agent = try Self.embeddedAgent()
        for (bundle, executable) in [(app, "TimeTracking"), (agent, "TimeTrackingAgent")] {
            let name = bundle.bundleURL.deletingPathExtension().lastPathComponent
            #expect(name.hasSuffix(" Debug"))
            #expect(bundle.infoDictionary?["CFBundleName"] as? String == name)
            #expect(bundle.infoDictionary?["CFBundleDisplayName"] as? String == name)
            #expect(bundle.executableURL?.lastPathComponent == executable)
        }
    }
}
