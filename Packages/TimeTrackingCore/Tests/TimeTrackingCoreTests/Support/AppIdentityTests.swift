// Tests for AppIdentity (spec_architecture.md §1.5).

import Foundation
import Testing
import TimeTrackingCore

struct AppIdentityTests {
    private static var debugMac: [String: Any] {
        [
            "TTAppID": "com.example.timetracking.debug",
            "TTBundleID": "com.example.timetracking",
            "TTTeamID": "TEAM000000",
            "TTAppGroup": "TEAM000000.com.example.timetracking.debug",
            "TTCloudKitContainer": "iCloud.com.example.timetracking.debug",
            "TTURLScheme": "timetracking-debug",
        ]
    }

    @Test func readsTheInfoPlistKeysAndDerivesTheRest() throws {
        let identity = try AppIdentity(infoDictionary: Self.debugMac)
        #expect(identity.isDebug)
        #expect(identity.agentBundleID == "com.example.timetracking.debug.agent")
        #expect(identity.agentPlistName == "com.example.timetracking.debug.agent.plist")
        #expect(identity.changeNotificationName == "com.example.timetracking.debug.changed")
        #expect(identity.widgetPushTopic == "com.example.timetracking.debug.push-type.widgets")
        #expect(identity.apnsKeychainService == "com.example.timetracking.apns")
        let container = URL(filePath: "/tmp/Group Containers/T.app", directoryHint: .isDirectory)
        let store = identity.storeURL(in: container).path
        #expect(store == "/tmp/Group Containers/T.app/Library/Application Support/TimeTracking/store.sqlite")
        #expect(identity.agentSocketURL(in: container).lastPathComponent == "tracker.sock")
    }

    @Test func aMissingKeyIsAnError() {
        var info = Self.debugMac
        info["TTAppGroup"] = ""
        #expect(throws: AppIdentityError.missingKey("TTAppGroup")) {
            try AppIdentity(infoDictionary: info)
        }
    }

    @Test("ARCH-1 the package tests run without local.mk, signing, or a build identity")
    func packageTestsNeedNoBuildIdentity() {
        // `swift test` runs an unsigned test runner whose Info.plist has no
        // TT keys; nothing in the library may require one to load.
        #expect(AppIdentity.main == nil)
        #expect(!Logging.subsystem.isEmpty)
    }
}
