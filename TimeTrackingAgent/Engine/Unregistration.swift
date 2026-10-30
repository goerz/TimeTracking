// Unregistration: `--unregister` removes the login item registration and
// exits (spec_activity_tracking.md §5, spec_architecture.md §2.5).

import Foundation
import os
import TimeTrackingCore

/// `--unregister`. `SMAppService` acts on the calling process's bundle, and
/// the launchd plist lives in the host app's `Contents/Library/LaunchAgents`,
/// so the agent runs the host app's executable with `--unregister` and
/// returns its exit status.
enum Unregistration {
    /// The app bundle that embeds `agentBundle` at
    /// `Contents/Library/LoginItems/`, or `nil` for a standalone agent.
    static func hostApp(of agentBundle: URL) -> URL? {
        let loginItems = agentBundle.deletingLastPathComponent()
        let library = loginItems.deletingLastPathComponent()
        let contents = library.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard loginItems.lastPathComponent == "LoginItems", library.lastPathComponent == "Library",
              contents.lastPathComponent == "Contents", app.pathExtension == "app"
        else {
            return nil
        }
        return app
    }

    /// Runs the host app of `agentBundle` with `--unregister`; returns its
    /// exit status, 0 for a standalone agent (it has no registration to
    /// remove), 1 when the app cannot run.
    static func run(agentBundle: URL = Bundle.main.bundleURL) -> Int32 {
        let logger = Logging.logger(category: "Agent")
        guard let app = hostApp(of: agentBundle) else {
            logger.info("unregister: not inside an app bundle")
            return 0
        }
        guard let executable = Bundle(url: app)?.executableURL else {
            logger.error("unregister: no executable in \(app.path, privacy: .public)")
            return 1
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--unregister"]
        do {
            try process.run()
        } catch {
            logger.error("unregister: \(error.localizedDescription, privacy: .public)")
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
