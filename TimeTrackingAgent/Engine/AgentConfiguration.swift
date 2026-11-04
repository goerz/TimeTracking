// AgentConfiguration: the agent's folders, device name, and version
// (spec_activity_tracking.md §4.1, §4.4; spec_architecture.md §1.5).

import Foundation
import IOKit
import TimeTrackingCore

/// Where the agent keeps its files and how it names itself.
struct AgentConfiguration {
    /// The agent folder `<group container>/Library/Application Support/TimeTracking/`.
    var agentFolder: URL
    var folders: ActivityFolders
    var device: String
    /// The name of this Mac's subfolder of `blocks/` (§4.1): the hardware
    /// UUID, which stays when the Mac is renamed.
    var macFolder: String
    /// `1.0 (42)`.
    var version: String
    /// Whether the agent may write the shared folder (tests deny it).
    var canWriteShared: (URL) -> Bool = SharedFolderChoice.canWrite

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

    /// The configuration of the installed agent of `identity`, or `nil`
    /// without a group container.
    static func live(identity: AppIdentity) -> Self? {
        guard let group = identity.groupContainerURL, let folders = ActivityFolders.resolve(identity: identity) else {
            return nil
        }
        let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return Self(
            agentFolder: identity.supportDirectory(in: group),
            folders: folders,
            device: name,
            macFolder: hardwareUUID ?? name.replacing("/", with: "-").replacing(":", with: "-"),
            version: bundleVersion
        )
    }

    /// The Mac's hardware UUID, lower-case (`IOPlatformUUID`).
    static var hardwareUUID: String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? String)?.lowercased()
    }
}
