// AgentMain: the tracker agent's entry point and flags
// (spec_activity_tracking.md §5, spec_architecture.md §1.4).

import AppKit
import TimeTrackingCore

@main
enum AgentMain {
    /// The running agent; `nil` while hosting tests or without a container.
    private static var runner: AgentRunner?

    static func main() {
        let arguments = LaunchArguments.current
        if arguments.unregister {
            exit(Unregistration.run())
        }
        if let replay = arguments.replayFile {
            exit(Replay.main(fixture: replay))
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        if !isHostingTests, let identity = AppIdentity.main {
            runner = AgentRunner.live(
                identity: identity,
                clock: arguments.clock(honorFixedNow: identity.isDebug),
                recordFolder: arguments.recordFolder
            )
            runner?.start()
        }
        application.run()
    }

    /// Whether the process hosts `TimeTrackingAgentTests` (the tests drive the engine themselves).
    static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
