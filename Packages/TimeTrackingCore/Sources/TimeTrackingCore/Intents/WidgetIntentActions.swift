// WidgetIntentActions: what the iOS widget and control buttons do, behind
// the wrapper intents that run in the app process (spec_ios.md §4 item 3,
// §5, §6.1). The intents only build a `WidgetAction` and hand it to the
// app's `WidgetActionEnvironment`.

public import Foundation

/// A widget or control button's action.
public enum WidgetAction: Hashable, Sendable {
    /// Start `task` on `project` (Pinned buttons, Recent rows, the project control).
    case start(project: ProjectID?, task: String)
    /// Stop the running entry the widget showed (`nil`: whatever runs).
    case stop(expected: EntryID?)
    /// Continue `entry`, or the most recent entry.
    case continueEntry(EntryID?)
    /// The Control Center toggle: on continues the latest, off stops.
    case toggle(Bool)
}

/// The app's handler for `WidgetAction`s, registered with
/// `AppDependencyManager` at launch; the wrapper intents resolve it.
public final class WidgetActionEnvironment: Sendable {
    public let perform: @Sendable (WidgetAction) async throws -> Void

    @preconcurrency
    public init(perform: @escaping @Sendable (WidgetAction) async throws -> Void) {
        self.perform = perform
    }
}

/// The library side of the wrapper intents.
public enum WidgetIntentActions {
    /// How long a button waits for the entry it acts on to arrive.
    public static let fetchTimeout: TimeInterval = 10

    /// Tracking from any surface before the first sync (spec_ios.md §6.1).
    public static let setupMessage = "Open \(AppDisplayName.orGeneric) once to finish setting up."
    /// An entry known only from `LiveState` did not arrive (spec_ios.md §4 item 3).
    public static let unreachableMessage = "Couldn't reach iCloud. Try again in a moment."

    /// Performs `action`. A stop of an entry the store does not hold yet
    /// first runs `fetch` (the app bounds it at `fetchTimeout`); if the entry
    /// still has not arrived, it fails with `unreachableMessage`. The
    /// toggle's off stops what the control showed: the running entry of the
    /// store's `LiveState` merged with `resolved`, the widgets' last one.
    @preconcurrency
    public static func perform(
        _ action: WidgetAction,
        service: AutomationService,
        resolved: LiveState? = nil,
        fetch: @Sendable () async -> Void
    ) async throws(AutomationError) {
        switch action {
        case let .start(project, task):
            _ = try await service.start(task: task, projectID: project)
        case let .stop(expected):
            try await stop(expected: expected, service: service, fetch: fetch)
        case let .continueEntry(id):
            _ = try await service.continue(id.map { .entry($0) } ?? .latest)
        case let .toggle(isOn):
            if isOn {
                _ = try await service.continue(.latest)
            } else {
                let local = await (try? service.store.liveState()) ?? LiveState()
                let live = resolved.map(local.merged(with:)) ?? local
                try await stop(expected: live.running?.entryID, service: service, fetch: fetch)
            }
        }
    }

    private static func stop(
        expected: EntryID?,
        service: AutomationService,
        fetch: @Sendable () async -> Void
    ) async throws(AutomationError) {
        let store = service.store
        if let expected {
            if await (try? store.entry(expected)) == nil {
                await fetch()
            }
            guard await (try? store.entry(expected)) != nil else {
                throw .failure(unreachableMessage)
            }
            // Stopped elsewhere meanwhile, or another entry started there:
            // nothing to do (checked and stopped in one transaction).
            _ = try await service.stop(chainOf: expected)
            return
        }
        guard try await service.status().running != nil else {
            return
        }
        _ = try await service.stop()
    }
}
