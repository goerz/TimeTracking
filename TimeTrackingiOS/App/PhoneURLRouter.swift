// PhoneURLRouter: what the iOS app does with a `timetracking://` URL from
// `onOpenURL` (spec_ios.md §6.4; spec_automation.md §6).

import Foundation
import TimeTrackingCore

/// Acts on scheme URLs through the library; the Timer shows the result.
@MainActor
struct PhoneURLRouter {
    /// What opening a URL did.
    enum Outcome: Equatable {
        /// A start, stop, or continue; the banner text.
        case tracked(String)
        /// The Timer (or, on the iPad, a section tab) was shown.
        case shown
        /// Nothing happened; the alert text.
        case failed(String)
    }

    let model: PhoneModel
    let scheme: String

    @discardableResult
    func open(_ url: URL) async -> Outcome {
        let outcome = await outcome(of: url)
        if case let .failed(message) = outcome {
            model.urlAlert = message
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
        model.sheet = nil
        switch parsed {
        case .start, .stop, .continue:
            do {
                let banner = try await AutomationService(store: model.store).perform(parsed) ?? ""
                await model.localWrite()
                model.padTab = .timer
                return .tracked(banner)
            } catch {
                return .failed(AutomationError(wrapping: error).message)
            }
        case .show:
            model.padTab = .timer
            return .shown
        case .calendar, .reports, .projects, .activity, .project:
            // The iPad selects the tab and its state; the iPhone shows the Timer.
            if let pad = model.pad {
                model.padTab = PadTab(url: parsed)
                await pad.router.open(parsed, now: model.clock.now)
            }
            return .shown
        }
    }
}
