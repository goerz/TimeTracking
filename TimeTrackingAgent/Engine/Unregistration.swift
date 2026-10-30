// Unregistration: `--unregister` removes the login item registration and
// exits (spec_activity_tracking.md §5, spec_architecture.md §2.5).

import Foundation
import os
import ServiceManagement
import TimeTrackingCore

/// The login item registration the agent can remove.
protocol LoginItemService {
    var isRegistered: Bool { get }
    func unregister() throws
}

extension SMAppService: LoginItemService {
    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }
}

/// `--unregister`: not being registered is the goal, so it is never a failure.
enum Unregistration {
    /// Unregisters `service`; returns the exit status (0, or 1 when the
    /// registration is still there afterwards).
    static func run(_ service: some LoginItemService) -> Int32 {
        guard service.isRegistered else {
            return 0
        }
        do {
            try service.unregister()
        } catch {
            Logging.logger(category: "Agent").info("unregister: \(error.localizedDescription, privacy: .public)")
        }
        return service.isRegistered ? 1 : 0
    }
}
