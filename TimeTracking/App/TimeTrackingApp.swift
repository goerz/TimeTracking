// TimeTrackingApp: the Mac app's entry point and scenes
// (spec_timer.md §1, §8, §9; spec_menubar.md; spec_projects.md §1;
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
        // The main window, the Timer its sidebar's first item.
        Window(AppHost.appName, id: MainWindowSetup.sceneID) {
            HostedContent(host: delegate.host) { app in
                MainWindowView()
                    .environment(app)
                    .modifier(RouterActions(router: delegate.router))
            }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        // Opened at every launch, also when state restoration recorded it
        // closed: the router's `openWindow` and `openSettings` come from
        // this window's view (`RouterActions`), so without it the menu bar
        // and the Dock tile could open nothing. A login launch closes it
        // again on attach (`hidesMainWindowOnAttach`).
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        // The scene keeps its Window menu item (the main window, by name).
        .commands {
            MainMenuCommands(host: delegate.host)
        }

        // The Mini Timer: a small window like
        // Music's MiniPlayer (compact bar or bar and list, Float on Top,
        // ⌥⌘R). It opens from Window › Mini Timer, not at launch.
        Window("Mini Timer", id: "timer") {
            HostedContent(host: delegate.host) { app in
                TimerView()
                    .environment(app)
                    .background(WindowAccessor { window in
                        delegate.miniTimerWindow?.attach(window)
                    })
                    .modifier(RouterActions(router: delegate.router))
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(MiniTimerGeometry.defaultFullSize)
        .defaultLaunchBehavior(.suppressed)
        // Never reopened at launch, also not by state restoration; its
        // frame and mode come from MiniTimerController.
        .restorationBehavior(.disabled)
        // Window › Mini Timer (in MainMenuCommands) replaces the scene's item.
        .commandsRemoved()

        Settings {
            HostedContent(host: delegate.host) { app in
                SettingsView().environment(app)
            }
        }
        // A restored Settings window counts as restored state, and SwiftUI
        // then skips the main window's `.presented` launch: the app came up
        // with no window and the router without actions.
        .restorationBehavior(.disabled)
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
