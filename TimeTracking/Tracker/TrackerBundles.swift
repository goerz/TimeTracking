// TrackerBundles: the app and agent bundles the privacy grants belong to
// (spec_activity_tracking.md §7.4, spec_architecture.md §1.4, §2.2).

import Foundation

/// The two bundles the Tracker pane names. System Settings lists them by
/// bundle file name: `<APP_NAME>` and `TimeTrackingAgent`, in Debug with
/// " Debug" appended.
struct TrackerBundles: Equatable {
    /// The app, `Bundle.main.bundleURL`.
    var app: URL
    /// The agent in `Contents/Library/LoginItems/`, if embedded.
    var agent: URL?

    /// The bundles of the running app.
    static var main: Self {
        let app = Bundle.main.bundleURL
        let loginItems = app.appending(path: "Contents/Library/LoginItems", directoryHint: .isDirectory)
        let bundles = (try? FileManager.default.contentsOfDirectory(at: loginItems, includingPropertiesForKeys: nil)) ?? []
        return Self(app: app, agent: bundles.first { $0.pathExtension == "app" })
    }

    /// The app's name in System Settings and Finder, e.g. "TimeTracking Debug".
    var appName: String {
        app.deletingPathExtension().lastPathComponent
    }

    /// The agent's name in System Settings and Finder.
    var agentName: String {
        agent?.deletingPathExtension().lastPathComponent ?? "TimeTrackingAgent"
    }

    /// What "Show … in Finder" reveals for the agent: the bundle, or the
    /// folder that should hold it.
    var agentOrFolder: URL {
        agent ?? app.appending(path: "Contents/Library/LoginItems", directoryHint: .isDirectory)
    }
}
