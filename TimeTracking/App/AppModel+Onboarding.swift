// AppModel+Onboarding: the first-launch tracker alert and its "Open at
// login" checkbox (spec_timer_window.md §8.2).

import Foundation

/// Shows the first-launch alert: the app name for the checkbox, the
/// checkbox's initial state, and the answer (open settings, open at login).
typealias TrackerOnboardingPresenter = (
    _ appName: String,
    _ opensAtLogin: Bool,
    _ answer: @escaping @MainActor (_ openSettings: Bool, _ opensAtLogin: Bool) -> Void
) -> Void

extension AppModel {
    /// The first launch on a Mac: ask once about activity tracking.
    func showTrackerOnboardingIfNeeded() {
        if !settings.trackerOnboardingPrompted {
            showsTrackerOnboarding = true
        }
    }

    /// Presents the alert once the main window shows, through the AppKit
    /// presenter (its checkbox is an `NSAlert` suppression button).
    func presentTrackerOnboarding() {
        guard showsTrackerOnboarding, !onboardingPresented, let present = onboardingPresenter else {
            return
        }
        onboardingPresented = true
        present(tracker.bundles.appName, onboardingOpensAtLogin) { [weak self] openSettings, opensAtLogin in
            self?.onboardingOpensAtLogin = opensAtLogin
            self?.answerTrackerOnboarding(openSettings: openSettings)
        }
    }

    /// "Open Tracker Settings" or "Later"; either marks the alert as shown
    /// and, with the checkbox on, turns on "Open at login".
    func answerTrackerOnboarding(openSettings: Bool) {
        settings.trackerOnboardingPrompted = true
        showsTrackerOnboarding = false
        if onboardingOpensAtLogin {
            tracker.setOpensAtLogin(true)
        }
        if openSettings {
            router?.openSettings(pane: .tracker)
        }
    }
}
