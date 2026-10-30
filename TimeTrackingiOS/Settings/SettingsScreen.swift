// SettingsScreen: the iOS Settings (spec_ios.md §2.9): short sections on the
// first screen; pinned projects, activity collection, and privacy on screens
// of their own. Calendars belong to the iPad tabs.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct SettingsScreen: View {
    @Bindable var model: PhoneModel

    @State private var pinned: PinnedProjectsModel?
    @State private var notificationsDenied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Form {
                iCloudSection
                pomodoroSection
                notificationSection
                widgetSection
                if let collection = model.collection as? CollectionModel {
                    activitySection(collection)
                }
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { model.sheet = nil }.accessibilityIdentifier("settings.done")
                }
            }
            .task { await load() }
        }
        .accessibilityIdentifier("settings")
    }

    private func load() async {
        let pinned = PinnedProjectsModel(store: model.store)
        await pinned.load()
        self.pinned = pinned
        notificationsDenied = await model.notifications.isDenied()
        await model.refreshOutbox()
        if let collection = model.collection as? CollectionModel {
            collection.refresh()
            await collection.refreshSettingsCopy()
        }
    }

    private var iCloudSection: some View {
        Section {
            LabeledContent("Status", value: model.syncStatusText)
            LabeledContent("Pending changes", value: "\(model.outboxCount)")
            LabeledContent("Device name") {
                TextField("Device name", text: Bindable(model.settings).deviceName)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .onSubmit { Task { await model.registerDevice() } }
                    .accessibilityIdentifier("settings.deviceName")
            }
            Button("Sync Now") {
                Task {
                    await model.sync?.sendNow()
                    await model.sync?.fetchNow()
                    await model.refreshOutbox()
                }
            }
            .disabled(model.sync == nil)
        } header: {
            Text("iCloud")
        } footer: {
            Text("Entries show the name of the device that created them.")
        }
    }

    private var pomodoroSection: some View {
        Section {
            Stepper(value: focusMinutes, in: 1 ... 180) {
                LabeledContent("Focus", value: "\(model.pomodoro.focusMinutes) min")
            }
            Stepper(value: breakMinutes, in: 1 ... 60) {
                LabeledContent("Break", value: "\(model.pomodoro.breakMinutes) min")
            }
            Toggle("Play sounds at phase changes", isOn: Bindable(model.settings).pomodoroSounds)
        } header: {
            Text("Pomodoro")
        } footer: {
            Text("The durations are the same on all your devices.")
        }
    }

    private var focusMinutes: Binding<Int> {
        Binding {
            model.pomodoro.focusMinutes
        } set: { value in
            Task { await model.pomodoro.setFocusMinutes(value) }
        }
    }

    private var breakMinutes: Binding<Int> {
        Binding {
            model.pomodoro.breakMinutes
        } set: { value in
            Task { await model.pomodoro.setBreakMinutes(value) }
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Long-running entry reminder", isOn: Bindable(model.settings).longRunningEnabled)
                .accessibilityIdentifier("settings.longRunning")
            Stepper(value: Bindable(model.settings).longRunningHours, in: 1 ... 12) {
                LabeledContent("Remind after", value: "\(model.settings.longRunningHours) h")
            }
            .disabled(!model.settings.longRunningEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            if notificationsDenied {
                VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                    Text("Notifications are off for TimeTracking. The Pomodoro buttons still work.")
                    Button("Open Settings") {
                        if let url = DeviceInfo.settingsURL {
                            openURL(url)
                        }
                    }
                    .font(.footnote)
                }
            } else {
                Text("A notification when an entry has run this long, whichever device started it.")
            }
        }
        .onChange(of: model.settings.longRunningEnabled) { model.rescheduleLongRunning() }
        .onChange(of: model.settings.longRunningHours) { model.rescheduleLongRunning() }
    }

    private var widgetSection: some View {
        Section {
            NavigationLink {
                if let pinned {
                    PinnedProjectsScreen(pinned: pinned, store: model.store)
                }
            } label: {
                LabeledContent("Pinned projects", value: pinned.map { "\($0.rows.count)" } ?? "")
            }
            .accessibilityIdentifier("settings.pinned")
            Picker("Pinned buttons start", selection: Bindable(model.settings).pinnedTaskMode) {
                Text("Last task").tag(PinnedTaskMode.latest)
                Text("No task").tag(PinnedTaskMode.blank)
            }
        } header: {
            Text("Widgets")
        } footer: {
            Text("The Pinned widget starts these projects, with the project's last task or none.")
        }
    }

    private func activitySection(_ collection: CollectionModel) -> some View {
        Section {
            NavigationLink {
                ActivityCollectionScreen(collection: collection)
            } label: {
                LabeledContent("Activity collection", value: collection.isEnabled ? "On" : "Off")
            }
            .accessibilityIdentifier("settings.collection")
            NavigationLink {
                PrivacyScreen(privacy: collection.privacy)
            } label: {
                Text("Privacy")
            }
            .accessibilityIdentifier("settings.privacy")
        } header: {
            Text("Activity")
        } footer: {
            Text("Labeled events from this device for the Mac's activity log.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.version)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        }
    }

    /// "1.0 (1)": the version and build.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

extension PhoneModel {
    /// The iCloud status line.
    var syncStatusText: String {
        guard sync != nil else {
            return "This device only"
        }
        return switch syncStatus {
        case .idle: "Up to date"
        case let .sending(count): "Sending \(count) change\(count == 1 ? "" : "s")…"
        case .fetching: "Receiving changes…"
        case .waitingForNetwork: "Waiting for the network"
        case .noAccount: "Not signed in to iCloud"
        case let .error(message): message
        }
    }
}
