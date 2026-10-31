// AutomationPermissionService: "Ask for Access" on the Tracker pane's
// Automation row (spec_activity_tracking.md §7.4).

import Foundation

/// What macOS answered for one app.
enum AutomationAnswer: Equatable, Sendable {
    case allowed
    case declined
    /// Any other error; the app may have quit while macOS asked.
    case failed
}

/// One app that was asked, by the name it shows.
struct AutomationOutcome: Equatable, Sendable {
    var name: String
    var answer: AutomationAnswer
}

/// Asks macOS whether the app may control other apps.
@MainActor
protocol AutomationPermissionService: AnyObject {
    /// Asks for each of `bundleIDs` that is running, one after another,
    /// showing the macOS prompt where there is no answer yet; apps that are
    /// not running are skipped.
    func ask(_ bundleIDs: [String]) async -> [AutomationOutcome]
}

/// Asks nothing real (tests and `-UITesting`): answers from a table.
@MainActor
final class FakeAutomationPermission: AutomationPermissionService {
    /// The running apps by bundle identifier, with their answers.
    var running: [String: AutomationOutcome]
    private(set) var requests: [[String]] = []

    init(running: [String: AutomationOutcome] = [:]) {
        self.running = running
    }

    func ask(_ bundleIDs: [String]) -> [AutomationOutcome] {
        requests.append(bundleIDs)
        return bundleIDs.compactMap { running[$0] }
    }
}
