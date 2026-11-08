// AgentService: registering the tracker agent as a login item
// (architecture.md §1.4, activity_tracking.md §7.4).

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
    /// Marks the tracker disabled with the file `disabled` in the agent
    /// folder, so the next start doesn't fill the time it was off
    /// (activity_tracking.md §2.4).
    func markDisabled()
    /// "Record on This Mac", and part of "Enable Tracker": makes this Mac
    /// the one that writes the block log (activity_tracking.md §4.1).
    func recordHere() async throws
}

/// An in-memory registration (tests, UI testing).
@MainActor
final class FakeAgentService: AgentService {
    var registration: AgentRegistration
    private(set) var registerCalls = 0
    private(set) var openedLoginItems = 0
    private(set) var restartCalls = 0
    private(set) var disabledMarks = 0
    private(set) var recordHereCalls = 0

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

    func markDisabled() {
        disabledMarks += 1
    }

    func recordHere() {
        recordHereCalls += 1
    }
}
