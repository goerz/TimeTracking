// TrackerPane: the Tracker settings pane (spec_activity_tracking.md §7.4,
// spec_timer_window.md §8.2, spec_design.md §7).

import SwiftUI
import TimeTrackingCore

/// Status, setup, sources, exclusions, options, and maintenance.
struct TrackerPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var tracker = app.tracker
        Form {
            statusSection
            setupSection
            sourcesSection
            PendingExclusionSection()
            ExclusionsSection()
            OptionsSection()
            MaintenanceSection()
        }
        .formStyle(.grouped)
        .frame(height: 620)
        .task {
            await app.tracker.refreshWhileVisible()
        }
        .alert("Disable the tracker?", isPresented: $tracker.confirmDisable) {
            Button("Disable Tracker", role: .destructive) { Task { await app.tracker.disable() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing is recorded until you enable it again.")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent {
                Button(app.tracker.buttonTitle) { Task { await app.tracker.pressButton() } }
                    .accessibilityIdentifier("tracker.button")
            } label: {
                Label {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(app.tracker.liveness.statusLine(now: app.clock.now)).accessibilityIdentifier("tracker.status")
                    }
                } icon: {
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(dotColor)
                        .accessibilityHidden(true)
                }
            }
            if let version = app.tracker.state?.health.version {
                LabeledContent("Agent version", value: version)
            }
            if let error = app.tracker.lastError {
                SettingsError(text: error)
            }
        } footer: {
            Text(
                "The tracker is a login item that records which apps, sites, and terminal sessions you work in, "
                    + "for Activity and the Calendar's suggestions."
            )
        }
    }

    private var dotColor: Color {
        switch app.tracker.dotColor {
        case "green": .green
        case "yellow": .yellow
        case "red": .red
        default: .gray
        }
    }

    private var setupSection: some View {
        Section {
            ForEach(app.tracker.setupSteps) { step in
                SetupStepRow(step: step) { action in
                    actionButton(action, step: step)
                }
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("Each line says what the step enables, and what you get without it.")
        }
    }

    @ViewBuilder
    private func actionButton(_ action: TrackerSetupStep.Action, step: TrackerSetupStep) -> some View {
        let identifier = "tracker.action.\(step.id).\(action.identifierSuffix)"
        switch action {
        case .enableTracker:
            Button(action.title) { Task { await app.tracker.enable() } }.accessibilityIdentifier(identifier)
        case .openLoginItems:
            Button(action.title) { app.tracker.agent.openLoginItems() }.accessibilityIdentifier(identifier)
        case let .openSettings(anchor):
            Button(action.title) { SystemSettings.openPrivacy(anchor) }.accessibilityIdentifier(identifier)
        case let .showInFinder(_, url):
            Button(action.title) { SystemSettings.reveal(url) }.accessibilityIdentifier(identifier)
        case .restartTracker:
            Button(action.title) { Task { await app.tracker.restartTracker() } }.accessibilityIdentifier(identifier)
        case .openAtLogin:
            Button(action.title) { app.tracker.setOpensAtLogin(true) }.accessibilityIdentifier(identifier)
        case let .copySnippet(snippet):
            Button(action.title) { SystemSettings.copy(snippet) }.accessibilityIdentifier(identifier)
        case .noAction:
            EmptyView()
        }
    }

    private var sourcesSection: some View {
        Section("Sources") {
            if let sources = app.tracker.state?.health.sources, !sources.isEmpty {
                ForEach(sources) { source in
                    LabeledContent(source.name) {
                        Text(source.reason.isEmpty ? source.status.rawValue : "\(source.status.rawValue): \(source.reason)")
                            .foregroundStyle(source.status == .active ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    }
                }
            } else {
                Text("No health record yet.").foregroundStyle(.secondary)
            }
        }
    }
}

/// One setup step: its mark and title, what it enables, the numbered
/// guidance while it is not done, and its buttons below the text.
private struct SetupStepRow<Actions: View>: View {
    var step: TrackerSetupStep
    @ViewBuilder var action: (TrackerSetupStep.Action) -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.small) {
            mark
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text(step.title)
                Text(step.enables).font(.caption).foregroundStyle(.secondary)
                if step.mark != .done {
                    ForEach(Array(step.guidance.enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)").font(.caption)
                    }
                    if !step.note.isEmpty {
                        Text(step.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                let actions = step.actions.filter { $0 != .noAction }
                if !actions.isEmpty {
                    HStack(spacing: Design.Spacing.small) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                            action(item)
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, Design.Spacing.tight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The mark as a symbol over its text, which stays the accessible element.
    private var mark: some View {
        let (symbol, style): (String, AnyShapeStyle) = switch step.mark {
        case .done: ("checkmark.circle.fill", AnyShapeStyle(Color.startTint))
        case .attention: ("exclamationmark.triangle.fill", AnyShapeStyle(.orange))
        case .unknown: ("circle.dashed", AnyShapeStyle(.tertiary))
        }
        return Text(step.mark.rawValue)
            .foregroundStyle(.clear)
            .frame(width: 18)
            .overlay {
                Image(systemName: symbol)
                    .foregroundStyle(style)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("tracker.mark.\(step.id)")
    }
}

/// An error under a control: the warning symbol and the message in red.
struct SettingsError: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
    }
}

/// The nine exclusion lists with + and −.
private struct ExclusionsSection: View {
    @Environment(AppModel.self) private var app
    @State private var drafts: [ExclusionList: String] = [:]

    var body: some View {
        let model = app.trackerSettings
        Section {
            ForEach(ExclusionList.allCases) { list in
                DisclosureGroup {
                    ForEach(model.entries(list), id: \.self) { value in
                        entryRow(value, in: list)
                    }
                    addRow(list)
                } label: {
                    LabeledContent(list.title) {
                        Text(model.entries(list).isEmpty ? "None" : "\(model.entries(list).count)").monospacedDigit()
                    }
                }
            }
            if let list = model.offerReapply {
                LabeledContent("Saved to \(list.title).") {
                    Button("Also Remove from Past Logs…") { Task { await model.reapplyExclusions() } }
                        .accessibilityIdentifier("tracker.reapplyOffer")
                }
            }
        } header: {
            Text("Exclusions")
        } footer: {
            Text("Applied before anything is written, on this Mac and on iPhone and iPad.")
        }
    }

    private func entryRow(_ value: String, in list: ExclusionList) -> some View {
        LabeledContent(value) {
            Button {
                app.trackerSettings.remove(value, from: list)
            } label: {
                Label("Remove", systemImage: "minus.circle").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private func addRow(_ list: ExclusionList) -> some View {
        let prompt = switch list.input {
        case .app: "Bundle identifier"
        case .folder: "~/Path"
        case .text: "Entry"
        }
        let draft = Binding { drafts[list] ?? "" } set: { drafts[list] = $0 }
        return HStack {
            TextField(prompt, text: draft)
                .labelsHidden()
                .onSubmit { add(to: list) }
            Button {
                add(to: list)
            } label: {
                Label("Add", systemImage: "plus.circle").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Add")
            .disabled((drafts[list] ?? "").trimmed.isEmpty)
        }
    }

    private func add(to list: ExclusionList) {
        app.trackerSettings.add(drafts[list] ?? "", to: list)
        drafts[list] = nil
    }
}

/// Watched folders, Idle after, synced Safari history, files.
private struct OptionsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.trackerSettings
        Section {
            LabeledContent("Watched folders") {
                Text(model.roots.joined(separator: ", ")).foregroundStyle(.secondary)
            }
            StepperRow(
                title: "Idle after",
                value: Self.duration(model.idleAfterSeconds),
                amount: $model.idleAfterSeconds,
                range: 30 ... 3600,
                step: 30
            )
            Toggle("Use Safari history synced from other devices", isOn: $model.useSyncedSafariHistory)
            LabeledContent("Settings file") {
                HStack(spacing: Design.Spacing.small) {
                    Button("Edit…") { SystemSettings.open(model.settingsURL) }
                    Button("Show Logs in Finder") { SystemSettings.reveal(model.settingsURL?.deletingLastPathComponent()) }
                }
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Idle after affects activity blocks only; the idle prompt has its own threshold in the Idle pane.")
        }
    }

    /// "5 min", "5 min 30 s".
    static func duration(_ seconds: Int) -> String {
        seconds.isMultiple(of: 60) ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s"
    }
}

/// Forget a Day… and Reapply Exclusions….
private struct MaintenanceSection: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false

    var body: some View {
        @Bindable var model = app.trackerSettings
        Section {
            LabeledContent("Forget a day") {
                HStack(spacing: Design.Spacing.small) {
                    DatePicker("Day", selection: $model.forgetDay, displayedComponents: .date)
                        .labelsHidden()
                    Button("Forget…") { confirmForget = true }
                }
            }
            LabeledContent("Reapply exclusions") {
                HStack(spacing: Design.Spacing.small) {
                    DatePicker("From", selection: $model.reapplyFrom, displayedComponents: .date)
                        .labelsHidden()
                    Text("to")
                    DatePicker("To", selection: $model.reapplyTo, displayedComponents: .date)
                        .labelsHidden()
                    Button("Reapply…") { Task { await model.reapplyExclusions() } }
                }
            }
            if let message = model.message {
                SettingsError(text: message)
            }
        } header: {
            Text("Maintenance")
        } footer: {
            Text("Both change the activity logs on this Mac and in iCloud Drive.")
        }
        .alert("Forget this day?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { Task { await model.forget() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every block of the day is removed from the logs.")
        }
    }
}

/// The unsaved exclusion from the Activity section, focused (spec_planner_activity.md §4).
private struct PendingExclusionSection: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = app.trackerSettings
        if let pending = model.pendingExclusion {
            Section("New Exclusion") {
                LabeledContent(pending.list.title) {
                    TextField(pending.list.title, text: Binding {
                        model.pendingExclusion?.value ?? ""
                    } set: { value in
                        model.pendingExclusion?.value = value
                    })
                    .labelsHidden()
                    .focused($focused)
                    .accessibilityIdentifier("tracker.pendingExclusion")
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.pendingExclusion = nil }
                    Button("Add") { model.addPendingExclusion() }
                        .disabled(pending.value.trimmed.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear { focused = true }
        }
    }
}
