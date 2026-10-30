// SettingsScreen: the iOS Settings (spec_ios.md §2.9), with the Activity
// Collection and Privacy sections; Calendars belong to the iPad tabs (step 8c).

import AppIntents
import SwiftUI
import TimeTrackingCore

struct SettingsScreen: View {
    @Bindable var model: PhoneModel

    @State private var pinned: PinnedProjectsModel?
    @State private var picker: ProjectPickerModel?
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
                    ActivityCollectionSection(collection: collection)
                    PrivacySection(privacy: collection.privacy)
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
            .sheet(item: $picker) { picker in
                pinnedPicker(picker)
            }
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

    private func pinnedPicker(_ picker: ProjectPickerModel) -> some View {
        NavigationStack {
            ProjectPickerView(model: picker) { choice in
                self.picker = nil
                if case let .project(id?) = choice {
                    Task { await pinned?.add(id) }
                }
            } onCancel: {
                self.picker = nil
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var iCloudSection: some View {
        Section("iCloud") {
            LabeledContent("Status", value: model.syncStatusText)
            LabeledContent("Pending changes", value: "\(model.outboxCount)")
            Button("Sync Now") {
                Task {
                    await model.sync?.sendNow()
                    await model.sync?.fetchNow()
                    await model.refreshOutbox()
                }
            }
            .disabled(model.sync == nil)
            TextField("Device name", text: Bindable(model.settings).deviceName)
                .onSubmit { Task { await model.registerDevice() } }
                .accessibilityIdentifier("settings.deviceName")
        }
    }

    private var pomodoroSection: some View {
        Section("Pomodoro") {
            Stepper(
                "Focus: \(model.pomodoro.focusMinutes) min",
                value: Binding(
                    get: { model.pomodoro.focusMinutes },
                    set: { value in Task { await model.pomodoro.setFocusMinutes(value) } }
                ),
                in: 1 ... 180
            )
            Stepper(
                "Break: \(model.pomodoro.breakMinutes) min",
                value: Binding(
                    get: { model.pomodoro.breakMinutes },
                    set: { value in Task { await model.pomodoro.setBreakMinutes(value) } }
                ),
                in: 1 ... 60
            )
            Toggle("Play sounds at phase changes", isOn: Bindable(model.settings).pomodoroSounds)
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Long-running entry reminder", isOn: Bindable(model.settings).longRunningEnabled)
                .accessibilityIdentifier("settings.longRunning")
            Stepper("After \(model.settings.longRunningHours) h", value: Bindable(model.settings).longRunningHours, in: 1 ... 12)
                .disabled(!model.settings.longRunningEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            if notificationsDenied {
                VStack(alignment: .leading) {
                    Text("Notifications are off for TimeTracking. The Pomodoro buttons still work.")
                    Button("Open Settings") {
                        if let url = DeviceInfo.settingsURL {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .onChange(of: model.settings.longRunningEnabled) { model.rescheduleLongRunning() }
        .onChange(of: model.settings.longRunningHours) { model.rescheduleLongRunning() }
    }

    private var widgetSection: some View {
        Section("Widgets") {
            ForEach(pinned?.rows ?? []) { row in
                HStack {
                    AreaDot(color: row.area?.color)
                    Text(row.project.name)
                }
            }
            .onMove { source, destination in Task { await pinned?.move(from: source, to: destination) } }
            .onDelete { offsets in Task { await pinned?.remove(at: offsets) } }
            Button("Add Pinned Project…") {
                picker = ProjectPickerModel(store: model.store, currentProject: nil, taskMatching: false)
            }
            .accessibilityIdentifier("settings.addPinned")
            Picker("Task on pinned buttons", selection: Bindable(model.settings).pinnedTaskMode) {
                Text("The project's last task").tag(PinnedTaskMode.latest)
                Text("None").tag(PinnedTaskMode.blank)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
            ShortcutsLink()
        }
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
