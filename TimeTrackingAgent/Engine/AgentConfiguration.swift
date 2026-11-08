// AgentConfiguration: the agent's folders, this Mac's id and name, and the
// version (activity_tracking.md §2.2, §4.1, §4.4; architecture.md §1.5).

import Foundation
import TimeTrackingCore

/// Where the agent keeps its files and how it names itself.
struct AgentConfiguration {
    /// The agent folder `<group container>/Library/Application Support/TimeTracking/`.
    var agentFolder: URL
    var folders: ActivityFolders
    /// The Mac's computer name, which names its BlockItems.
    var macName: String
    /// The Mac's device id in Samples and `blocks/owner`: its hardware
    /// UUID, which stays when the Mac is renamed (§2.2).
    var macDeviceID: String
    /// `1.0 (42)`.
    var version: String
    /// Whether the agent may write the shared folder (tests deny it).
    var canWriteShared: (URL) -> Bool = SharedFolderChoice.canWrite

    /// The file the Mac app writes when the tracker is disabled (§2.4).
    var disabledURL: URL {
        agentFolder.appending(path: "disabled", directoryHint: .notDirectory)
    }

    var samplesURL: URL {
        agentFolder.appending(path: "samples.sqlite", directoryHint: .notDirectory)
    }

    /// `AppIdentity.agentSocketURL(in:)` for the installed agent; built from
    /// `agentFolder` so tests can run the socket in a temporary folder.
    var socketURL: URL {
        agentFolder.appending(path: "tracker.sock", directoryHint: .notDirectory)
    }

    /// The version of the running bundle.
    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// A `--record` run: its store, lock, socket, and activity folder
    /// inside the record folder, so it leaves the installed agent's alone.
    func recording(in folder: URL) -> Self {
        var result = self
        result.agentFolder = folder.appending(path: "agent", directoryHint: .isDirectory)
        let activity = result.agentFolder.appending(path: "Activity", directoryHint: .isDirectory)
        result.folders = ActivityFolders(shared: activity, local: activity, isFallback: true)
        return result
    }

    var lockURL: URL {
        agentFolder.appending(path: "agent.lock", directoryHint: .notDirectory)
    }

    /// The configuration of the installed agent of `identity`, or `nil`
    /// without a group container.
    static func live(identity: AppIdentity) -> Self? {
        guard let group = identity.groupContainerURL, let folders = ActivityFolders.resolve(identity: identity) else {
            return nil
        }
        let name = LocalHost.computerName
        return Self(
            agentFolder: identity.supportDirectory(in: group),
            folders: folders,
            macName: name,
            macDeviceID: HardwareUUID.current ?? name,
            version: bundleVersion
        )
    }
}
