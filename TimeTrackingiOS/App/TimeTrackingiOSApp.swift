// TimeTrackingiOSApp: the iPhone and iPad app's entry point (spec_ios.md
// §1, §2, §6.4, §7, §10, §11).

import AppIntents
import SwiftUI
import TimeTrackingCore

@main
struct TimeTrackingiOSApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @State private var host = PhoneHost.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneIntentBridge.register()
        if LaunchArguments.current.uiTesting {
            UIViewAnimations.disable()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(host: host)
                .task { await host.load() }
                .onOpenURL { url in
                    Task {
                        // A URL that launches the app waits for the store.
                        let model = await PhoneIntentBridge.shared.awaitModel()
                        await PhoneURLRouter(model: model, scheme: AppIdentity.main?.urlScheme ?? "timetracking").open(url)
                    }
                }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            host.scenePhaseChanged(to: phase)
        }
        .backgroundTask(.appRefresh(RefreshScheduler.identifier)) {
            await RefreshScheduler.run()
        }
        .commands { PadCommands(host: host) }
    }
}

/// The model's screens once onboarding is done; the iPad gets its tabs.
struct RootView: View {
    var host: PhoneHost

    var body: some View {
        if let model = host.model, let onboarding = host.onboarding {
            if onboarding.step == .done {
                if model.settings.isPad {
                    PadTabsView(model: model)
                } else {
                    TimerScreen(model: model)
                }
            } else {
                OnboardingView(onboarding: onboarding, model: model)
            }
        } else if let failure = host.failure {
            ContentUnavailableView(
                "\(AppDisplayName.current ?? "The App") Couldn't Open Your Entries",
                systemImage: SymbolName.warning,
                description: Text(failure)
            )
        } else {
            ProgressView()
        }
    }
}

/// The App Intents of the iOS app: the library's intents and entities.
struct TimeTrackingiOSAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TimeTrackingCoreIntents.self]
    }
}
