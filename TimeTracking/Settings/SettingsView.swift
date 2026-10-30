// SettingsView: the settings window with six panes (spec_timer_window.md §8,
// spec_design.md §7, §8).

import KeyboardShortcuts
import SwiftUI
import TimeTrackingCore

/// The `Settings` scene's content; reopens on the last pane shown.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane = SettingsPane.general.rawValue

    /// Every pane has this width (spec_design.md §8).
    static let width: CGFloat = 520

    var body: some View {
        TabView(selection: $pane) {
            ForEach(SettingsPane.allCases) { pane in
                Tab(value: pane.rawValue) {
                    content(for: pane)
                        .accessibilityIdentifier("settings.pane.\(pane.rawValue)")
                } label: {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(symbol: pane.symbol)
                    }
                }
            }
        }
        .frame(width: Self.width)
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .pomodoro: PomodoroPane()
        case .idle: IdlePane()
        case .reminders: RemindersPane()
        case .shortcuts: ShortcutsPane()
        case .tracker: TrackerPane()
        }
    }
}

extension View {
    /// A grouped settings form whose window fits its content.
    func settingsForm() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A value with a stepper at the trailing edge: "Focus duration   25 min ⇅".
struct StepperRow: View {
    var title: String
    var value: String
    @Binding var amount: Int
    var range: ClosedRange<Int>
    var step = 1

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Design.Spacing.tight) {
                Text(value).monospacedDigit()
                Stepper(title, value: $amount, in: range, step: step)
                    .labelsHidden()
            }
        }
    }
}

/// General (§8.1).
struct GeneralPane: View {
    @Environment(AppModel.self) private var app
    @State private var notificationsAllowed = true

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { app.tracker.opensAtLogin },
                    set: { app.tracker.setOpensAtLogin($0) }
                ))
                .accessibilityIdentifier("settings.openAtLogin")
                Toggle("Show the Timer window at login", isOn: $settings.showTimerAtLogin)
                    .disabled(!app.tracker.opensAtLogin)
            }
            Section {
                Toggle("Float above other windows", isOn: Binding(
                    get: { app.settings.timerPinned },
                    set: { app.setPinned($0) }
                ))
                .accessibilityIdentifier("settings.floatOnTop")
            } header: {
                Text("Timer window")
            } footer: {
                Text("The same as the pin in the Timer window's title bar.")
            }
            menuBarSection
            if let live = app.live {
                LiveStatusSection(live: live)
            }
            if !notificationsAllowed {
                notificationSection
            }
        }
        .settingsForm()
        .task { notificationsAllowed = await UserNotifications.isAuthorized() }
    }

    private var menuBarSection: some View {
        @Bindable var settings = app.settings
        return Section {
            Toggle("Show timer", isOn: $settings.menuBarShowTimer)
            Toggle("Show seconds", isOn: $settings.menuBarShowSeconds)
                .disabled(!settings.menuBarShowTimer)
            Toggle("Show project", isOn: $settings.menuBarShowProject)
            Picker("During a Pomodoro, show", selection: $settings.menuBarPomodoroDisplay) {
                Text("Timer and countdown").tag(MenuBarPomodoroDisplay.both)
                Text("Countdown only").tag(MenuBarPomodoroDisplay.countdown)
                Text("Timer only").tag(MenuBarPomodoroDisplay.timer)
            }
            .accessibilityIdentifier("settings.menuBarPomodoroDisplay")
            Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                .accessibilityIdentifier("settings.showDockIcon")
        } header: {
            Text("Menu bar and Dock")
        } footer: {
            Text("Without the Dock icon, the menu bar item opens the app's windows.")
        }
    }

    private var notificationSection: some View {
        Section {
            LabeledContent {
                Button("Open Notification Settings") { SystemSettings.openNotifications() }
            } label: {
                Label("Notifications are off for this app.", systemImage: "exclamationmark.triangle")
            }
        } footer: {
            Text("Pomodoro, idle, and reminder alerts need notifications.")
        }
    }
}

/// Pomodoro (§5.2).
struct PomodoroPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                PomodoroDurationRows(pomodoro: app.pomodoro, focusTitle: "Focus duration", breakTitle: "Break duration")
            } footer: {
                Text("The durations are the same on all your devices.")
            }
            Section {
                Toggle("Play sounds at phase ends", isOn: $settings.pomodoroSounds)
            }
        }
        .settingsForm()
    }
}

/// Idle (§6.2).
struct IdlePane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Detect idle time while an entry is running", isOn: $settings.idle.detectIdle)
                StepperRow(
                    title: "Idle after",
                    value: "\(settings.idle.thresholdMinutes) min",
                    amount: $settings.idle.thresholdMinutes,
                    range: 1 ... 120
                )
                .disabled(!settings.idle.detectIdle)
            } footer: {
                Text("After this long without keyboard or mouse input, the app asks what to do with the idle time when you return.")
            }
            Section {
                Picker("On lock or sleep", selection: $settings.idle.onLockOrSleep) {
                    Text("Ask when I return").tag(IdleLockBehavior.ask)
                    Text("Stop the entry at that moment").tag(IdleLockBehavior.stop)
                    Text("Keep tracking").tag(IdleLockBehavior.keep)
                }
                Toggle("Stop the running entry on shutdown or logout", isOn: $settings.idle.stopOnShutdown)
            }
        }
        .settingsForm()
    }
}

/// Reminders (§7).
struct RemindersPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Remind me to track time", isOn: $settings.reminders.isEnabled)
            } footer: {
                Text("A notification when nothing is running during the hours below.")
            }
            Section {
                StepperRow(
                    title: "Every",
                    value: "\(settings.reminders.everyMinutes) min",
                    amount: $settings.reminders.everyMinutes,
                    range: 1 ... 240
                )
                LabeledContent("Between") {
                    HStack(spacing: Design.Spacing.small) {
                        minuteField($settings.reminders.startMinute)
                        Text("and")
                        minuteField($settings.reminders.endMinute)
                    }
                }
                LabeledContent("On") { weekdayToggles }
                StepperRow(
                    title: "Snooze for",
                    value: "\(settings.reminders.snoozeMinutes) min",
                    amount: $settings.reminders.snoozeMinutes,
                    range: 5 ... 480,
                    step: 5
                )
            }
            .disabled(!settings.reminders.isEnabled)
        }
        .settingsForm()
    }

    /// Monday first.
    static let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var weekdayToggles: some View {
        HStack(spacing: Design.Spacing.tight) {
            ForEach(1 ... 7, id: \.self) { weekday in
                Toggle(Self.weekdaySymbols[weekday - 1], isOn: weekdayBinding(weekday))
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding {
            app.settings.reminders.weekdays.contains(weekday)
        } set: { isOn in
            if isOn {
                app.settings.reminders.weekdays.insert(weekday)
            } else {
                app.settings.reminders.weekdays.remove(weekday)
            }
        }
    }

    private func minuteField(_ minutes: Binding<Int>) -> some View {
        let date = Binding {
            Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes.wrappedValue * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        return DatePicker("", selection: date, displayedComponents: .hourAndMinute).labelsHidden()
    }
}

/// Shortcuts (§8.3).
struct ShortcutsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                LabeledContent("Show or hide the Timer window") {
                    KeyboardShortcuts.Recorder(for: .showHideTimer) { _ in app.refreshShortcutDisplay() }
                        .accessibilityIdentifier("settings.showHideRecorder")
                }
                LabeledContent("Continue or stop the timer") {
                    KeyboardShortcuts.Recorder(for: .continueStop)
                        .accessibilityIdentifier("settings.continueStopRecorder")
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("These work in every app.")
            }
            Section {
                Toggle("Focus app when the timer starts", isOn: $settings.focusOnStart)
                    .accessibilityIdentifier("settings.focusOnStart")
                Toggle("Focus app when the timer stops", isOn: $settings.focusOnStop)
            } footer: {
                Text(
                    "Shows the Timer window after a start or stop from a shortcut, the menu bar, "
                        + "a notification, Shortcuts, or another device."
                )
            }
        }
        .settingsForm()
    }
}
