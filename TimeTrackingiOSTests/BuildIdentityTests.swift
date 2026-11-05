// The Debug iOS app's identity as built (architecture.md §1.5).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

struct BuildIdentityTests {
    @Test("ARCH-6 the Debug iOS app carries the Debug identifiers")
    func debugIdentifiers() throws {
        let identity = try AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
        #expect(Bundle.main.bundleIdentifier == identity.appID)
        #expect(identity.appID == identity.bundleID + ".debug")
        #expect(identity.appGroup == "group.\(identity.appID)")
        #expect(identity.cloudKitContainer == "iCloud.\(identity.appID)")
        #expect(identity.urlScheme == "timetracking-debug")
    }
}
