// ActivityFolders: where the activity files live (spec_data_and_sync.md §6,
// spec_activity_tracking.md §4.1).

public import Foundation

/// The shared and the local activity folder.
///
/// The shared folder is `Activity/` in the ubiquity container
/// `iCloud.<APP_ID>`, outside `Documents/`; it holds `blocks/` and
/// `settings.toml`. The local folder is `Activity/` in the support
/// directory of the App Group container; it holds `current.json`,
/// `detail/`, `events.jsonl` (iOS), and the fallback `blocks/`. Without a
/// ubiquity container the local folder takes the shared folder's place.
public struct ActivityFolders: Sendable, Hashable {
    public var shared: URL
    public var local: URL
    /// Whether `shared` is the local fallback because iCloud Drive is unavailable.
    public var isFallback: Bool

    /// Folders at explicit locations (tests, tools).
    public init(shared: URL, local: URL, isFallback: Bool = false) {
        self.shared = shared
        self.local = local
        self.isFallback = isFallback
    }

    /// The folders of `identity` given its containers; a missing ubiquity
    /// container selects the fallback.
    public init(identity: AppIdentity, groupContainer: URL, ubiquityContainer: URL?) {
        let localFolder = identity.supportDirectory(in: groupContainer).appending(path: "Activity", directoryHint: .isDirectory)
        if let ubiquityContainer {
            self.init(shared: ubiquityContainer.appending(path: "Activity", directoryHint: .isDirectory), local: localFolder)
        } else {
            self.init(shared: localFolder, local: localFolder, isFallback: true)
        }
    }

    /// The folders of the running build, or `nil` without an App Group
    /// container. Looking up the ubiquity container can block; call this
    /// off the main actor.
    public static func resolve(identity: AppIdentity) -> Self? {
        guard let group = identity.groupContainerURL else {
            return nil
        }
        let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: identity.cloudKitContainer)
        return Self(identity: identity, groupContainer: group, ubiquityContainer: ubiquity)
    }

    /// `blocks/` of the shared folder.
    public var sharedBlocks: URL {
        shared.appending(path: "blocks", directoryHint: .isDirectory)
    }

    /// `blocks/` of the local folder (the agent's fallback copy).
    public var localBlocks: URL {
        local.appending(path: "blocks", directoryHint: .isDirectory)
    }

    /// The `blocks/` folders to read, shared first, each once.
    public var blockFolders: [URL] {
        shared.standardizedFileURL == local.standardizedFileURL ? [sharedBlocks] : [sharedBlocks, localBlocks]
    }

    /// `settings.toml` in the shared folder.
    public var settingsURL: URL {
        shared.appending(path: "settings.toml", directoryHint: .notDirectory)
    }

    /// `current.json` in the local folder.
    public var currentStateURL: URL {
        local.appending(path: "current.json", directoryHint: .notDirectory)
    }

    /// `detail/` in the local folder.
    public var detailFolder: URL {
        local.appending(path: "detail", directoryHint: .isDirectory)
    }

    /// `events.jsonl`, the iOS staging file, in the local folder.
    public var eventsURL: URL {
        local.appending(path: "events.jsonl", directoryHint: .notDirectory)
    }
}
