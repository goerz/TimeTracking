// AppIdentity: the identifiers and containers of the running build, read
// from its Info.plist (spec_architecture.md §1.5, §2.2).

public import Foundation

/// The identity of a build: its app id and everything derived from it.
///
/// Every identifier derives from the app id, so a Debug build has its own
/// containers. The values come from the `TT*` keys that `Project.xcconfig`
/// writes into every Info.plist (the tools carry theirs in the binary).
public struct AppIdentity: Sendable, Equatable {
    /// The app's bundle identifier, `<BUNDLE_ID>` or `<BUNDLE_ID>.debug`.
    public var appID: String
    /// The Release bundle identifier, shared by Release and Debug.
    public var bundleID: String
    /// The development team id.
    public var teamID: String
    /// The App Group: `<TEAM>.<APP_ID>` on the Mac, `group.<APP_ID>` on iOS.
    public var appGroup: String
    /// The CloudKit and ubiquity container, `iCloud.<APP_ID>`.
    public var cloudKitContainer: String
    /// The URL scheme, `timetracking` or `timetracking-debug`.
    public var urlScheme: String

    public init(
        appID: String,
        bundleID: String,
        teamID: String,
        appGroup: String,
        cloudKitContainer: String,
        urlScheme: String
    ) {
        self.appID = appID
        self.bundleID = bundleID
        self.teamID = teamID
        self.appGroup = appGroup
        self.cloudKitContainer = cloudKitContainer
        self.urlScheme = urlScheme
    }

    /// Reads the `TT*` keys of an Info.plist dictionary.
    public init(infoDictionary: [String: Any]) throws(AppIdentityError) {
        func string(_ key: String) throws(AppIdentityError) -> String {
            guard let value = infoDictionary[key] as? String, !value.isEmpty else {
                throw .missingKey(key)
            }
            return value
        }
        try self.init(
            appID: string("TTAppID"),
            bundleID: string("TTBundleID"),
            teamID: string("TTTeamID"),
            appGroup: string("TTAppGroup"),
            cloudKitContainer: string("TTCloudKitContainer"),
            urlScheme: string("TTURLScheme")
        )
    }

    /// The identity of the running process, or `nil` when its Info.plist has
    /// no `TT*` keys (package tests, previews).
    public static let main: Self? = try? Self(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// Whether this is a Debug identity.
    public var isDebug: Bool {
        appID.hasSuffix(".debug")
    }

    /// The agent's bundle identifier, which is also its launchd label and
    /// Mach service.
    public var agentBundleID: String {
        appID + ".agent"
    }

    /// The name of the agent's launchd plist in `Contents/Library/LaunchAgents/`.
    public var agentPlistName: String {
        agentBundleID + ".plist"
    }

    /// The Darwin notification posted after every store change.
    public var changeNotificationName: String {
        appID + ".changed"
    }

    /// The WidgetKit push topic.
    public var widgetPushTopic: String {
        appID + ".push-type.widgets"
    }

    /// The Keychain service of the APNs auth key.
    public var apnsKeychainService: String {
        bundleID + ".apns"
    }

    /// The App Group container, or `nil` if the system does not provide one.
    public var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// `<group container>/Library/Application Support/TimeTracking/`, the
    /// folder of the store and the agent's local files.
    public func supportDirectory(in container: URL) -> URL {
        container.appending(path: "Library/Application Support/TimeTracking", directoryHint: .isDirectory)
    }

    /// The store file in `container`.
    public func storeURL(in container: URL) -> URL {
        supportDirectory(in: container).appending(path: "store.sqlite", directoryHint: .notDirectory)
    }

    /// The agent's socket in `container`.
    public func agentSocketURL(in container: URL) -> URL {
        supportDirectory(in: container).appending(path: "tracker.sock", directoryHint: .notDirectory)
    }
}

/// Errors reading an `AppIdentity`.
public enum AppIdentityError: Error, Equatable, LocalizedError {
    /// The Info.plist lacks the key or its value is empty.
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case let .missingKey(key):
            "The Info.plist has no value for \(key)."
        }
    }
}
