// IntentEnvironment: what an app hands its intents and queries
// (spec_automation.md §2, §5).

import AppIntents
public import Foundation

/// The app's services for intents, registered once at launch with
/// `AppDependencyManager.shared.add(dependency:)` before any intent runs.
public final class IntentEnvironment: Sendable {
    /// The store's operations; waits until the app has opened the store.
    public let service: @Sendable () async throws -> AutomationService
    /// Called after an intent changed the store (the app re-reads and syncs).
    public let didChange: @Sendable () async -> Void
    /// Shows the Timer window or tab.
    public let showTimer: @Sendable () async -> Void

    @preconcurrency
    public init(
        service: @escaping @Sendable () async throws -> AutomationService,
        didChange: @escaping @Sendable () async -> Void = {},
        showTimer: @escaping @Sendable () async -> Void = {}
    ) {
        self.service = service
        self.didChange = didChange
        self.showTimer = showTimer
    }

    /// The service, with its failures as automation errors.
    func automation() async throws(AutomationError) -> AutomationService {
        do {
            return try await service()
        } catch {
            throw AutomationError(wrapping: error)
        }
    }
}

extension AutomationError: CustomLocalizedStringResourceConvertible {
    /// The tool's message, so Siri and Shortcuts show the same text.
    public var localizedStringResource: LocalizedStringResource {
        "\(message)"
    }
}
