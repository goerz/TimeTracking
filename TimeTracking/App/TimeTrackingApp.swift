// TimeTrackingApp: the Mac app's entry point and scenes
// (spec_timer_window.md §1, §8, §9; spec_menubar.md; spec_planner_projects.md §1;
// `--unregister`: spec_activity_tracking.md §5).

import SwiftUI
import TimeTrackingCore

/// The entry point: `--unregister` removes the agent's registration and
/// exits before any scene exists; anything else runs the app.
@main
enum AppMain {
    static func main() {
        if LaunchArguments.current.unregister {
            exit(LoginItemAgentService.unregisterAgent())
        }
        TimeTrackingApp.main()
    }
}

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
        // The scene's own Window menu item would list the Timer a second
        // time next to Window › Timer; the main menu replaces it.
        .commandsReplaced {
            MainMenuCommands(host: delegate.host)
        }

        Window("Planner", id: "planner") {
            HostedContent(host: delegate.host) { app in
                PlannerWindowView()
                    .environment(app)
                    .modifier(RouterActions(router: delegate.router))
            }
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1360, height: 840)
        .windowResizability(.contentMinSize)
        // Window › Planner (in MainMenuCommands) replaces the scene's item.
        .commandsRemoved()

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
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                Text("\(AppHost.appName) Couldn't Open Your Entries").font(.headline)
                Text(failure)
            }
            .padding()
        } else {
            ProgressView()
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
