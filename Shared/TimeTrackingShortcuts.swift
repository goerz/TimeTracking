// TimeTrackingShortcuts: the App Shortcut phrase table both apps use
// (ios.md §6.2). Every "in" phrase also exists with "with". It lives in
// Shared/ because App Shortcuts are extracted only from an app target, not
// from the library; the intents it names come from the library.
//
// The symbol names are literals because App Shortcuts are extracted at build
// time; they are SymbolName.start, .stop, .restore, .startTime, .total, and
// .pomodoroSystem (design.md §5).

import AppIntents
import TimeTrackingCore

/// The App Shortcuts and their phrases.
struct TimeTrackingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(inferProject: true),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Start a timer with \(.applicationName)",
                "Start tracking \(\.$project) in \(.applicationName)",
                "Start tracking \(\.$project) with \(.applicationName)",
                "Track \(\.$project) in \(.applicationName)",
                "Track \(\.$project) with \(.applicationName)",
                "Start \(\.$project) in \(.applicationName)",
                "Start \(\.$project) with \(.applicationName)",
            ],
            shortTitle: "Start Timer",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopTimerIntent(),
            phrases: [
                "Stop the timer in \(.applicationName)",
                "Stop the timer with \(.applicationName)",
                "Stop tracking in \(.applicationName)",
                "Stop tracking with \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Stop Timer",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: ContinueIntent(),
            phrases: [
                "Continue in \(.applicationName)",
                "Continue with \(.applicationName)",
                "Resume my last entry in \(.applicationName)",
                "Resume my last entry with \(.applicationName)",
                "Continue \(\.$project) in \(.applicationName)",
                "Continue \(\.$project) with \(.applicationName)",
            ],
            shortTitle: "Continue",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: CurrentEntryIntent(),
            phrases: [
                "What am I tracking in \(.applicationName)",
                "What am I tracking with \(.applicationName)",
                "What's running in \(.applicationName)",
                "What's running with \(.applicationName)",
                "Is \(.applicationName) running",
            ],
            shortTitle: "What's Running",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: TodayTotalIntent(),
            phrases: [
                "How much have I tracked today in \(.applicationName)",
                "How much have I tracked today with \(.applicationName)",
                "\(.applicationName) total for today",
            ],
            shortTitle: "Today's Total",
            systemImageName: "sum"
        )
        AppShortcut(
            intent: ShowTimerIntent(),
            phrases: [
                "Open the timer in \(.applicationName)",
                "Open the timer with \(.applicationName)",
            ],
            shortTitle: "Show Timer",
            systemImageName: "timer"
        )
    }
}
