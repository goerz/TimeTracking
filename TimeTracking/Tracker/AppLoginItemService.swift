// AppLoginItemService: "Open at login" for the app itself
// (spec_timer.md §8.1, §8.2; spec_activity_tracking.md §7.4).

import Foundation
import TimeTrackingCore

/// "Open at login" for the app itself (`SMAppService.mainApp`).
@MainActor
protocol AppLoginItemService: AnyObject {
    var registration: AgentRegistration { get }

    func setOpensAtLogin(_ enabled: Bool) throws
}

/// An in-memory "Open at login" (tests and `-UITesting`, which never
/// register the real login item).
@MainActor
final class FakeAppLoginItem: AppLoginItemService {
    var registration: AgentRegistration
    private(set) var changes: [Bool] = []

    init(registration: AgentRegistration = .notRegistered) {
        self.registration = registration
    }

    func setOpensAtLogin(_ enabled: Bool) {
        changes.append(enabled)
        registration = enabled ? .enabled : .notRegistered
    }
}
