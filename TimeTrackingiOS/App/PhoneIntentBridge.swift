// PhoneIntentBridge: hands the library's App Intents and the widget wrapper
// intents the iOS app's store, its fan-out, and the Timer (spec_ios.md §6.1;
// spec_automation.md §5).

import AppIntents
import Foundation
import TimeTrackingCore

/// The app's side of `IntentEnvironment` and `WidgetActionEnvironment`.
/// Intents wait until the store is open, so an intent that launches the app
/// in the background works too; before the first sync they fail with
/// "Open TimeTracking once to finish setting up."
@MainActor
final class PhoneIntentBridge {
    static let shared = PhoneIntentBridge()

    private var model: PhoneModel?
    private var waiting: [CheckedContinuation<PhoneModel, Never>] = []

    nonisolated static var environment: IntentEnvironment {
        IntentEnvironment(
            service: { try await shared.service() },
            didChange: { await shared.model?.localWrite() },
            showTimer: { await shared.showTimer() }
        )
    }

    nonisolated static var widgetActions: WidgetActionEnvironment {
        WidgetActionEnvironment { action in
            try await shared.perform(action)
        }
    }

    /// Registers both environments; call once from `App.init`.
    static func register() {
        AppDependencyManager.shared.add(dependency: environment)
        AppDependencyManager.shared.add(dependency: widgetActions)
    }

    func attach(_ model: PhoneModel) {
        self.model = model
        let waiting = waiting
        self.waiting = []
        for continuation in waiting {
            continuation.resume(returning: model)
        }
    }

    func awaitModel() async -> PhoneModel {
        if let model {
            return model
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    func service() async throws(AutomationError) -> AutomationService {
        let model = await awaitModel()
        guard model.shared.setupComplete else {
            throw .failure(WidgetIntentActions.setupMessage)
        }
        return AutomationService(store: model.store)
    }

    func showTimer() {
        model?.sheet = nil
    }

    /// A widget or control button: the library operation, an immediate
    /// send, and the reloads (spec_ios.md §6.1).
    func perform(_ action: WidgetAction) async throws {
        let service = try await service()
        let model = await awaitModel()
        try await model.performWidgetAction(action, service: service)
    }
}

extension PhoneModel {
    /// What every wrapper intent does in the app process.
    func performWidgetAction(_ action: WidgetAction, service: AutomationService) async throws(AutomationError) {
        let sync = sync
        let bounded = boundedFetch
        try await WidgetIntentActions.perform(action, service: service, resolved: shared.liveState) {
            await bounded { await sync?.fetchNow() }
        }
        await localWrite()
    }
}
