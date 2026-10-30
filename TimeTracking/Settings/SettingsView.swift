// SettingsView: the settings window with six panes (spec_timer_window.md §8).

import KeyboardShortcuts
import SwiftUI
import TimeTrackingCore

/// The `Settings` scene's content; reopens on the last pane shown.
struct SettingsView: View {
    @AppStorage(SettingsPane.storageKey) private var pane = SettingsPane.general.rawValue

    var body: some View {
        TabView(selection: $pane) {
            ForEach(SettingsPane.allCases) { pane in
                Tab(pane.title, systemImage: pane.symbol, value: pane.rawValue) {
                    content(for: pane)
                        .accessibilityIdentifier("settings.pane.\(pane.rawValue)")
                }
            }
        }
        .frame(width: 600)
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

/// General (§8.1).
struct GeneralPane: View {
    @Environment(AppModel.self) private var app
    @State private var notificationsAllowed = true

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Toggle("Open at login", isOn: Binding(
                get: { app.tracker.opensAtLogin },
                set: { app.tracker.setOpensAtLogin($0) }
            ))
            .accessibilityIdentifier("settings.openAtLogin")
            Toggle("Show the Timer window at login", isOn: $settings.showTimerAtLogin)
            Toggle("Float the Timer window above other windows", isOn: Binding(
                get: { app.settings.timerPinned },
                set: { app.setPinned($0) }
            ))
            .accessibilityIdentifier("settings.floatOnTop")
            Section("Menu bar") {
                Toggle("Show timer", isOn: $settings.menuBarShowTimer)
                Toggle("Show seconds", isOn: $settings.menuBarShowSeconds)
                    .disabled(!settings.menuBarShowTimer)
                    .padding(.leading, 18)
                Toggle("Show project", isOn: $settings.menuBarShowProject)
            }
            Toggle("Show Dock icon", isOn: $settings.showDockIcon)
                .accessibilityIdentifier("settings.showDockIcon")
            if let live = app.live {
                LiveStatusSection(live: live)
            }
            if !notificationsAllowed {
                HStack {
                    Text("Notifications are off for this app.").foregroundStyle(.secondary)
                    Button("Open Notification Settings") { SystemSettings.openNotifications() }
                }
            }
        }
        .formStyle(.grouped)
        .task { notificationsAllowed = await UserNotifications.isAuthorized() }
    }
}

/// Pomodoro (§5.2).
struct PomodoroPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Stepper(value: focusMinutes, in: 1 ... 180) {
                LabeledContent("Focus duration", value: "\(app.pomodoro.focusMinutes) min")
            }
            .accessibilityIdentifier("settings.focusMinutes")
            Stepper(value: breakMinutes, in: 1 ... 60) {
                LabeledContent("Break duration", value: "\(app.pomodoro.breakMinutes) min")
            }
            Toggle("Play sounds at phase ends", isOn: $settings.pomodoroSounds)
        }
        .formStyle(.grouped)
    }

    private var focusMinutes: Binding<Int> {
        Binding {
            app.pomodoro.focusMinutes
        } set: { value in
            Task { await app.pomodoro.setFocusMinutes(value) }
        }
    }

    private var breakMinutes: Binding<Int> {
        Binding {
            app.pomodoro.breakMinutes
        } set: { value in
            Task { await app.pomodoro.setBreakMinutes(value) }
        }
    }
}

/// Idle (§6.2).
struct IdlePane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Toggle("Detect idle time while an entry is running", isOn: $settings.idle.detectIdle)
            Stepper(value: $settings.idle.thresholdMinutes, in: 1 ... 120) {
                LabeledContent("Idle after", value: "\(settings.idle.thresholdMinutes) min")
            }
            .disabled(!settings.idle.detectIdle)
            Picker("On lock or sleep", selection: $settings.idle.onLockOrSleep) {
                Text("Ask when I return").tag(IdleLockBehavior.ask)
                Text("Stop the entry at that moment").tag(IdleLockBehavior.stop)
                Text("Keep tracking").tag(IdleLockBehavior.keep)
            }
            Toggle("Stop the running entry on shutdown or logout", isOn: $settings.idle.stopOnShutdown)
        }
        .formStyle(.grouped)
    }
}

/// Reminders (§7).
struct RemindersPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Toggle("Remind me to track time", isOn: $settings.reminders.isEnabled)
            Group {
                Stepper(value: $settings.reminders.everyMinutes, in: 1 ... 240) {
                    LabeledContent("Every", value: "\(settings.reminders.everyMinutes) min")
                }
                LabeledContent("Between") {
                    HStack {
                        minuteField($settings.reminders.startMinute)
                        Text("and")
                        minuteField($settings.reminders.endMinute)
                    }
                }
                LabeledContent("On") { weekdayToggles }
                Stepper(value: $settings.reminders.snoozeMinutes, in: 5 ... 480, step: 5) {
                    LabeledContent("Snooze for", value: "\(settings.reminders.snoozeMinutes) min")
                }
            }
            .disabled(!settings.reminders.isEnabled)
        }
        .formStyle(.grouped)
    }

    /// Monday first.
    static let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var weekdayToggles: some View {
        HStack(spacing: 4) {
            ForEach(1 ... 7, id: \.self) { weekday in
                Toggle(Self.weekdaySymbols[weekday - 1], isOn: weekdayBinding(weekday))
                    .toggleStyle(.button)
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
            LabeledContent("Show/hide Timer window:") {
                KeyboardShortcuts.Recorder(for: .showHideTimer) { _ in app.refreshShortcutDisplay() }
                    .accessibilityIdentifier("settings.showHideRecorder")
            }
            LabeledContent("Continue/stop timer:") {
                KeyboardShortcuts.Recorder(for: .continueStop)
                    .accessibilityIdentifier("settings.continueStopRecorder")
            }
            Toggle("Focus app when the timer starts", isOn: $settings.focusOnStart)
                .accessibilityIdentifier("settings.focusOnStart")
            Toggle("Focus app when the timer stops", isOn: $settings.focusOnStop)
        }
        .formStyle(.grouped)
    }
}
