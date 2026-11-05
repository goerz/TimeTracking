// AutomationPermission: asks macOS for Automation of running apps with
// AEDeterminePermissionToAutomateTarget (activity_tracking.md §7.4).

import AppKit
import CoreServices

/// The live "Ask for Access". The answer is recorded for the app, which is
/// also what macOS checks for the agent's Apple Events (5).
@MainActor
final class AutomationPermission: AutomationPermissionService {
    func ask(_ bundleIDs: [String]) async -> [AutomationOutcome] {
        var outcomes: [AutomationOutcome] = []
        for bundleID in bundleIDs {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                continue
            }
            let name = app.localizedName ?? bundleID
            let status = await Self.determine(bundleID)
            switch status {
            case OSStatus(noErr):
                outcomes.append(AutomationOutcome(name: name, answer: .allowed))
            case OSStatus(errAEEventNotPermitted):
                outcomes.append(AutomationOutcome(name: name, answer: .declined))
            case OSStatus(procNotFound):
                continue
            default:
                outcomes.append(AutomationOutcome(name: name, answer: .failed))
            }
        }
        return outcomes
    }

    /// Blocks while the prompt is up, so it runs off the main actor.
    private nonisolated static func determine(_ bundleID: String) async -> OSStatus {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let desc = target.aeDesc else {
                return OSStatus(procNotFound)
            }
            return AEDeterminePermissionToAutomateTarget(desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
        }.value
    }
}
