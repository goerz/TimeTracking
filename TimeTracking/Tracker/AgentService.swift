// AgentService: registering the tracker agent as a login item
// (spec_architecture.md §1.4, spec_activity_tracking.md §7.4).

import Foundation
import TimeTrackingCore

/// The agent's login item registration.
@MainActor
protocol AgentService: AnyObject {
    var registration: AgentRegistration { get }
    /// "Enable Tracker".
    func register() throws
    /// "Disable Tracker".
    func unregister() async throws
    /// "Open Login Items" (System Settings).
    func openLoginItems()
    /// "Restart Tracker": the agent quits and launchd starts it again, so a
    /// new privacy grant applies.
    func restart() async throws
}

/// An in-memory registration (tests, UI testing).
@MainActor
final class FakeAgentService: AgentService {
    var registration: AgentRegistration
    private(set) var registerCalls = 0
    private(set) var openedLoginItems = 0
    private(set) var restartCalls = 0

    init(registration: AgentRegistration = .notRegistered) {
        self.registration = registration
    }

    func register() {
        registerCalls += 1
        registration = .enabled
    }

    func unregister() {
        registration = .notRegistered
    }

    func openLoginItems() {
        openedLoginItems += 1
    }

    func restart() {
        restartCalls += 1
    }
}
