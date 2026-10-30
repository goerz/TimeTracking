// TimeTrackingApp: the Mac app's entry point and scenes
// (spec_timer_window.md §1, §8, §9; spec_menubar.md; spec_planner_projects.md §1).

import SwiftUI
import TimeTrackingCore

@main
struct TimeTrackingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Before any intent can run, also when one launches the app.
        IntentBridge.register()
    }

    var body: some Scene {
        Window("Timer", id: "timer") {
            HostedContent(host: delegate.host) { app in
                TimerWindowView()
                    .environment(app)
                    .background(WindowAccessor { window in
                        delegate.timerWindow?.attach(window)
                    })
                    .modifier(RouterActions(router: delegate.router))
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(TimerWindowGeometry.defaultFullSize)
        .commands {
            TimerCommands(host: delegate.host)
        }

        Window("Planner", id: "planner") {
            HostedContent(host: delegate.host) { app in
                PlannerPlaceholderView().environment(app)
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1360, height: 840)

        Settings {
            HostedContent(host: delegate.host) { app in
                SettingsView().environment(app)
            }
        }
    }
}

/// Shows `content` once the model exists, a placeholder before.
private struct HostedContent<Content: View>: View {
    var host: AppHost
    @ViewBuilder var content: (AppModel) -> Content

    var body: some View {
        if let model = host.model {
            content(model)
        } else if let failure = host.failure {
            Text(failure).padding()
        } else {
            Text(AppIdentity.main?.appID ?? "TimeTracking")
                .foregroundStyle(.secondary)
                .padding()
                .accessibilityIdentifier("timer.placeholder")
        }
    }
}

/// Hands the scene's `openSettings` and `openWindow` to the router.
private struct RouterActions: ViewModifier {
    var router: WindowRouter?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            router?.openSettingsAction = openSettings
            router?.openWindowAction = openWindow
        }
    }
}

/// The Planner window until the Planner exists (step 7 replaces it).
struct PlannerPlaceholderView: View {
    var body: some View {
        Text("Planner")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(minWidth: 820, minHeight: 560)
            .accessibilityIdentifier("planner.placeholder")
    }
}
