// SettingsScreen: the iOS Settings (ios.md §2.9): short sections on the
// first screen; pinned projects, activity collection, and privacy on screens
// of their own; Apple Health on the iPhone, the Calendar settings on the iPad.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct SettingsScreen: View {
    @Bindable var model: PhoneModel

    @State private var pinned: PinnedProjectsModel?
    @State private var notificationsDenied = false
    @State private var showSleep = false
    @State private var showWorkouts = false
    @Environment(\.openURL) private var openURL

    /// The iPad's Calendar settings on a screen of their own.
    @ViewBuilder private var calendarRow: some View {
        if let calendar = model.pad?.router.calendar {
            NavigationLink {
                Form { CalendarSettingsSections(model: calendar) }
                    .navigationTitle("Calendar")
            } label: {
                Text("Calendar")
            }
            .accessibilityIdentifier("settings.calendar")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                iCloudSection
                MidnightSection(store: model.store)
                pomodoroSection
                notificationSection
                widgetSection
                if let collection = model.collection as? CollectionModel {
                    activitySection(collection)
                }
                if model.pad == nil {
                    healthSection
                }
                calendarRow
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
        let kinds = await model.healthKinds()
        showSleep = kinds.contains(.sleep)
        showWorkouts = kinds.contains(.workout)
        await model.refreshOutbox()
        if let collection = model.collection as? CollectionModel {
            collection.refresh()
            await collection.refreshSettingsCopy()
        }
    }

    private var iCloudSection: some View {
        Section {
            LabeledContent("Status", value: model.syncStatusText)
            LabeledContent("Waiting to sync", value: "\(model.outboxCount)")
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

    /// The iPhone's Apple Health import (§7 item 6), the same synced
    /// settings as the Calendar's on the Mac and iPad.
    private var healthSection: some View {
        Section {
            Toggle("Sleep", isOn: health(.sleep, $showSleep))
                .accessibilityIdentifier("settings.health.sleep")
            Toggle("Workouts", isOn: health(.workout, $showWorkouts))
                .accessibilityIdentifier("settings.health.workouts")
        } header: {
            Text("Apple Health")
        } footer: {
            Text("This iPhone reads your sleep and workouts from the Health app, so the Calendar on your Mac and iPad shows them.")
        }
    }

    private func health(_ kind: HealthPeriod.Kind, _ value: Binding<Bool>) -> Binding<Bool> {
        Binding {
            value.wrappedValue
        } set: { isOn in
            value.wrappedValue = isOn
            Task { await model.setHealth(kind, isOn) }
        }
    }

    private var pomodoroSection: some View {
        Section {
            PomodoroDurationRows(pomodoro: model.pomodoro, focusTitle: "Focus", breakTitle: "Break")
            Toggle("Play a sound when a focus or break ends", isOn: Bindable(model.settings).pomodoroSounds)
        } header: {
            Text("Pomodoro")
        } footer: {
            Text("The durations are the same on all your devices.")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Remind me when an entry runs long", isOn: Bindable(model.settings).longRunningEnabled)
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
                    Text("Notifications are off, so focus, break, and reminder alerts won't appear.")
                    Button("Open Settings") {
                        if let url = DeviceInfo.settingsURL {
                            openURL(url)
                        }
                    }
                    .font(.footnote)
                }
            } else {
                Text("You get a notification when an entry has run this long, on any device.")
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
            Picker("Task for pinned buttons", selection: Bindable(model.settings).pinnedTaskMode) {
                Text("The project's last task").tag(PinnedTaskMode.latest)
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
            Text("Shows what you do on this device in Activity on your Mac and iPad.")
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
