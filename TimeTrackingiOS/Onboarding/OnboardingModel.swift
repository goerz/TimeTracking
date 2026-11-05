// OnboardingModel: the iCloud account check, the device name, and the
// initial sync before anything else shows (ios.md §11).

import Foundation
import Observation
import TimeTrackingCore

/// The iCloud account as onboarding sees it.
enum AccountState: Equatable, Sendable {
    case available
    case unavailable
}

/// The onboarding steps.
enum OnboardingStep: Equatable {
    case checking
    /// No usable iCloud account: the blocking explanation.
    case noAccount
    case deviceName
    /// The initial fetch, with the entries received so far.
    case syncing(entries: Int)
    case done
}

/// Runs the steps of §11; the app shows the Timer once `step` is `done`.
@Observable
final class OnboardingModel {
    @ObservationIgnored let settings: PhoneSettings
    @ObservationIgnored let shared: WidgetSharedState
    @ObservationIgnored let accountStatus: @Sendable () async -> AccountState

    private(set) var step: OnboardingStep = .checking
    var deviceName = ""

    init(settings: PhoneSettings, shared: WidgetSharedState, accountStatus: @escaping @Sendable () async -> AccountState) {
        self.settings = settings
        self.shared = shared
        self.accountStatus = accountStatus
    }

    /// Checks the account ("Try Again" calls it too); a device that finished
    /// onboarding before goes straight to the Timer.
    func check() async {
        step = .checking
        guard await accountStatus() == .available else {
            step = .noAccount
            return
        }
        if settings.onboarded {
            step = .done
            return
        }
        deviceName = settings.deviceName.isEmpty ? DeviceInfo.systemName : settings.deviceName
        step = .deviceName
    }

    /// "Continue" after the name: register the device and fetch the zone.
    func confirmName(model: PhoneModel) async {
        let name = deviceName.trimmed
        settings.deviceName = name.isEmpty ? DeviceInfo.systemName : name
        step = .syncing(entries: 0)
        await model.registerDevice()
        let progress = Task { [weak self] in
            for await change in model.store.changes {
                if case .entries = change {
                    let count = await (try? model.store.entries(
                        in: DateInterval(start: .distantPast, end: .distantFuture),
                        includeDeleted: false
                    ).count) ?? 0
                    // A count arriving after the sync finished must not
                    // take the step back from done.
                    guard !Task.isCancelled, case .syncing = self?.step else {
                        continue
                    }
                    self?.step = .syncing(entries: count)
                }
            }
        }
        await model.sync?.fetchNow()
        progress.cancel()
        finish()
    }

    /// The first sync delivered the store.
    func finish() {
        shared.setupComplete = true
        settings.onboarded = true
        step = .done
    }
}
