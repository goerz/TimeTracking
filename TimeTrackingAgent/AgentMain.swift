// AgentMain: the tracker agent's entry point and flags
// (activity_tracking.md §5, architecture.md §1.4).

import AppKit
import os
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
            exit(replayFixture(at: replay))
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        if !isHostingTests, let identity = AppIdentity.main, var configuration = AgentConfiguration.live(identity: identity) {
            if let folder = arguments.recordFolder {
                configuration = configuration.recording(in: folder)
            }
            try? FileManager.default.createDirectory(at: configuration.agentFolder, withIntermediateDirectories: true)
            guard InstanceLock.acquire(at: configuration.lockURL) else {
                Logging.logger(category: "Agent").notice("Another tracker agent is running, or the lock file can't be opened; exiting")
                exit(0)
            }
            runner = AgentRunner.live(
                identity: identity,
                configuration: configuration,
                clock: arguments.clock(honorFixedNow: identity.isDebug),
                recordFolder: arguments.recordFolder
            )
            runner?.start()
            TerminationSignal.install { await runner?.stop() }
        }
        application.run()
    }

    /// `--replay <fixture>`: forms the fixture's date files from its Samples
    /// and exits non-zero when they differ from the expected ones.
    static func replayFixture(at folder: URL) -> Int32 {
        do {
            let differences = try SampleFixture.replay(folder: folder)
            for day in differences {
                FileHandle.standardError.write(Data("differs: \(day)\n".utf8))
            }
            return differences.isEmpty ? 0 : 1
        } catch {
            FileHandle.standardError.write(Data("cannot replay \(folder.path): \(error.localizedDescription)\n".utf8))
            return 2
        }
    }

    /// Whether the process hosts `TimeTrackingAgentTests` (the tests drive the engine themselves).
    static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
