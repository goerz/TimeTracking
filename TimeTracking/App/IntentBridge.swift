// IntentBridge: hands the library's App Intents the Mac app's store, its
// re-read after a change, and the Mini Timer (spec_automation.md §5).

import AppIntents
import Foundation
import TimeTrackingCore

/// The app's side of `IntentEnvironment`: intents wait until the store is
/// open, so an intent that launches the app in the background works too.
@MainActor
final class IntentBridge {
    static let shared = IntentBridge()

    private var model: AppModel?
    private var waiting: [CheckedContinuation<AppModel, Never>] = []
    private var shortcutTask: Task<Void, Never>?

    /// The environment registered with `AppDependencyManager` at launch.
    nonisolated static var environment: IntentEnvironment {
        IntentEnvironment(
            service: { await AutomationService(store: shared.awaitModel().store) },
            didChange: { await shared.model?.afterChange() },
            showTimer: { await shared.showTimer() }
        )
    }

    /// Registers the environment; call once from `App.init`.
    static func register() {
        AppDependencyManager.shared.add(dependency: environment)
    }

    /// The model is ready: resumes every waiting intent and keeps the App
    /// Shortcut parameters current with the project list (spec_ios.md §6.2).
    func attach(_ model: AppModel) {
        self.model = model
        let stream = model.store.changes
        shortcutTask?.cancel()
        shortcutTask = Task {
            for await change in stream where change == .structure {
                TimeTrackingShortcuts.updateAppShortcutParameters()
            }
        }
        let waiting = waiting
        self.waiting = []
        for continuation in waiting {
            continuation.resume(returning: model)
        }
    }

    func showTimer() {
        model?.router?.showTimer(focusTask: false)
    }

    func awaitModel() async -> AppModel {
        if let model {
            return model
        }
        return await withCheckedContinuation { waiting.append($0) }
    }
}
