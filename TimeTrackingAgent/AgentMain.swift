// AgentMain: the tracker agent's entry point and flags
// (spec_activity_tracking.md §5, spec_architecture.md §1.4).

import AppKit
import os
import ServiceManagement
import TimeTrackingCore

@main
enum AgentMain {
    static func main() {
        let arguments = LaunchArguments.current
        if arguments.unregister {
            unregister()
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.run()
    }

    /// `--unregister`: removes the login item registration and exits.
    private static func unregister() -> Never {
        guard let identity = AppIdentity.main else {
            FileHandle.standardError.write(Data("TimeTrackingAgent: no identity in the Info.plist\n".utf8))
            exit(1)
        }
        let service = SMAppService.agent(plistName: identity.agentPlistName)
        do {
            try service.unregister()
        } catch {
            // Not registered is the goal state, so it is not a failure.
            Logging.logger(category: "TimeTrackingAgent").info("unregister: \(error.localizedDescription, privacy: .public)")
        }
        exit(0)
    }
}
