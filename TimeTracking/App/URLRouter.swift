// URLRouter: what the Mac app does with a `timetracking://` URL
// (automation.md §6). Start, stop, and continue run in the
// background with a banner; nothing destructive.

import Foundation
import TimeTrackingCore

/// Acts on scheme URLs through the library and the app's router.
@MainActor
final class URLRouter {
    /// What opening a URL did.
    enum Outcome: Equatable {
        /// A start, stop, or continue; the banner text.
        case tracked(String)
        /// The Timer or a section was shown.
        case shown
        /// Nothing happened; the alert text.
        case failed(String)
    }

    private let app: AppModel
    private let scheme: String
    /// Shows an alert naming the problem.
    var alert: (String) -> Void = { _ in }

    init(app: AppModel, scheme: String) {
        self.app = app
        self.scheme = scheme
    }

    @discardableResult
    func open(_ url: URL) async -> Outcome {
        let outcome = await outcome(of: url)
        if case let .failed(message) = outcome {
            alert(message)
        }
        return outcome
    }

    private func outcome(of url: URL) async -> Outcome {
        let parsed: TimeTrackingURL
        do {
            parsed = try TimeTrackingURL(url, scheme: scheme)
        } catch {
            return .failed(error.localizedDescription)
        }
        switch parsed {
        case .start, .stop, .continue:
            do {
                let banner = try await AutomationService(store: app.store).perform(parsed) ?? ""
                await app.afterChange()
                app.notifier.post(NotificationRequest(category: .tracking, title: banner, body: "", sound: nil))
                return .tracked(banner)
            } catch {
                return .failed(AutomationError(wrapping: error).message)
            }
        case .show:
            app.router?.showTimer(focusTask: false)
            return .shown
        case .calendar, .reports, .projects, .activity, .project:
            await app.sections.open(parsed, now: app.clock.now)
            return .shown
        }
    }
}
