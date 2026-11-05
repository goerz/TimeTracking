// FamilyControlsAuthorization: Screen Time authorization through
// AuthorizationCenter (ios.md §9.2, §11 item 3). Needs a device with
// the Family Controls entitlement; the simulator reports it unavailable.

import FamilyControls
import Foundation
import TimeTrackingCore

/// Individual authorization, requested only from the collection screen.
final class FamilyControlsAuthorization: ScreenTimeAuthorizing {
    var status: ScreenTimeStatus {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved, .approvedWithDataAccess: .approved
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func request() async -> ScreenTimeStatus {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            return .denied
        }
        return status
    }

    func measureCap() -> Int {
        DeviceActivityLadderMonitor.measureCap()
    }
}

/// A fixed answer (tests, UI testing).
final class FixedScreenTime: ScreenTimeAuthorizing {
    var status: ScreenTimeStatus
    var requested = 0
    let cap: Int

    init(status: ScreenTimeStatus, cap: Int = LadderPlan.defaultCap) {
        self.status = status
        self.cap = cap
    }

    func request() -> ScreenTimeStatus {
        requested += 1
        return status
    }

    func measureCap() -> Int {
        cap
    }
}
