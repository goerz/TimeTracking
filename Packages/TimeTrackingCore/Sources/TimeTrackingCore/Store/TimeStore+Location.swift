// Where a process opens the store (spec_architecture.md §1.5, §2.5, ARCH-17, ARCH-19).

public import Foundation

extension TimeStore.Location {
    /// The location for a process: in memory under `-UITesting YES`, the
    /// file of `TIMETRACKING_STORE` when set, else `store.sqlite` in the App
    /// Group container of `identity` (a Debug identity has its own). `nil`
    /// when there is no identity or container.
    public static func resolve(arguments: LaunchArguments, identity: AppIdentity?) -> Self? {
        if arguments.uiTesting {
            return .inMemory
        }
        if let path = arguments.storePath {
            let expanded = path.hasPrefix("~/") ? NSHomeDirectory() + path.dropFirst() : path
            return .file(URL(filePath: expanded))
        }
        return identity.flatMap(defaultFile).map { .file($0) }
    }

    /// `<group container>/Library/Application Support/TimeTracking/store.sqlite`.
    public static func defaultFile(for identity: AppIdentity) -> URL? {
        identity.groupContainerURL.map { identity.storeURL(in: $0) }
    }
}

extension TimeStore {
    /// Opens the store the way the apps, agent, and tool do: the location of
    /// `Location.resolve`, the Darwin change notification of `identity`, and
    /// under `-UITesting YES` an in-memory store with `-Fixture <name>`
    /// loaded (no disk, no CloudKit).
    @preconcurrency
    public static func open(
        arguments: LaunchArguments,
        identity: AppIdentity?,
        deviceID: DeviceID,
        clock: any Clock,
        timeZone: @escaping @Sendable () -> TimeZone = { .current },
        readOnly: Bool = false
    ) async throws -> TimeStore {
        guard let location = Location.resolve(arguments: arguments, identity: identity) else {
            throw StoreError.database("No App Group container")
        }
        let notifier: (any ChangeNotifier)? = arguments.uiTesting ? nil : identity.map { DarwinChangeNotifier(identity: $0) }
        let store = try await open(Configuration(
            location: location,
            clock: clock,
            deviceID: deviceID,
            timeZone: timeZone,
            notifier: notifier,
            readOnly: readOnly
        ))
        if arguments.uiTesting, let name = arguments.fixture {
            try await StoreFixture.load(named: name, into: store, timeZone: timeZone())
        }
        return store
    }
}
