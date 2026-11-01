// TrackerPane: the Tracker settings pane (spec_activity_tracking.md §7.4,
// spec_timer.md §8.2, spec_design.md §7).

import SwiftUI
import TimeTrackingCore

/// Status, setup, sources, and the settings file and logs.
struct TrackerPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var tracker = app.tracker
        Form {
            statusSection
            setupSection
            sourcesSection
            PendingExclusionSection()
            FilesSection()
        }
        .settingsForm()
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
                    Image(systemName: SymbolName.statusDot)
                        .imageScale(.small)
                        .foregroundStyle(dotColor)
                        .accessibilityHidden(true)
                }
            }
            if let version = app.tracker.state?.health.version {
                LabeledContent("Tracker version", value: version)
            }
            if let error = app.tracker.lastError {
                ErrorLine(text: error)
            }
        } footer: {
            Text(
                "The tracker is a login item that records which apps, sites, and terminal sessions you work in, "
                    + "for Activity and the Calendar."
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
        Section("Setup") {
            ForEach(app.tracker.setupSteps) { step in
                SetupStepRow(step: step) { action in
                    actionButton(action, step: step)
                }
            }
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
        case .askAutomation:
            Button(action.title) { Task { await app.tracker.askForAutomation() } }.accessibilityIdentifier(identifier)
        case .openAtLogin:
            Button(action.title) { app.tracker.setOpensAtLogin(true) }.accessibilityIdentifier(identifier)
        case let .copySnippet(snippet):
            CopyButton(title: action.title, text: snippet, showsIcon: false).accessibilityIdentifier(identifier)
        case .noAction:
            EmptyView()
        }
    }

    private var sourcesSection: some View {
        Section("Recording") {
            if let sources = app.tracker.state?.health.sources, !sources.isEmpty {
                ForEach(sources) { source in
                    LabeledContent(source.displayName) {
                        Text(source.statusText)
                            .foregroundStyle(source.status == .active ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                    }
                }
            } else {
                Text("The tracker hasn't reported yet.").foregroundStyle(.secondary)
            }
        }
    }
}

/// One setup step: its mark and title, the on or off line, the numbered
/// guidance while it is not done, its buttons below the text, and the info
/// button at the trailing edge.
private struct SetupStepRow<Actions: View>: View {
    var step: TrackerSetupStep
    @ViewBuilder var action: (TrackerSetupStep.Action) -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.small) {
            mark
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text(step.title)
                if let detail = step.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tracker.detail.\(step.id)")
                }
                if step.mark != .done {
                    ForEach(Array(step.guidance.enumerated()), id: \.offset) { index, line in
                        Text("\(index + 1). \(line)").font(.caption)
                    }
                    if !step.note.isEmpty {
                        Text(step.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                buttons
                if let outcome = step.outcome {
                    Text(outcome).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tracker.outcome.\(step.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let info = step.info {
                InfoButton(info: info).accessibilityIdentifier("tracker.info.\(step.id)")
            }
        }
    }

    /// The row's buttons in one line, in the small control size.
    @ViewBuilder private var buttons: some View {
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

    /// The mark as a symbol over its text, which stays the accessible element.
    private var mark: some View {
        let (symbol, style): (String, AnyShapeStyle) = switch step.mark {
        case .done: (SymbolName.done, AnyShapeStyle(Color.startTint))
        case .attention: (SymbolName.warningFill, AnyShapeStyle(.orange))
        case .unknown: (SymbolName.notChecked, AnyShapeStyle(.tertiary))
        }
        return Text(step.mark.rawValue)
            .foregroundStyle(.clear)
            .frame(width: 18)
            .overlay {
                Image(systemName: symbol)
                    .foregroundStyle(style)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(step.mark.accessibilityLabel)
            .accessibilityIdentifier("tracker.mark.\(step.id)")
    }
}

/// The settings file and the activity logs: where they are, and buttons to
/// open them. Everything the tracker can be told lives in the file.
private struct FilesSection: View {
    @Environment(AppModel.self) private var app

    private var model: TrackerSettingsModel {
        app.trackerSettings
    }

    var body: some View {
        Section {
            settingsFileRow
            logsRow
        } header: {
            Text("Files")
        } footer: {
            Text(
                "Exclusions, watched folders, the idle threshold, and site categories are set in the settings file, "
                    + "each with a comment that explains it. The tracker picks up a change within 30 seconds."
            )
        }
    }

    private var settingsFileRow: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.tight) {
            Text("Settings file")
            path(TrackerSettingsModel.displayPath(model.settingsURL))
            HStack(spacing: Design.Spacing.small) {
                Button("Open in Editor") {
                    if model.ensureFile() {
                        SystemSettings.openInEditor(model.settingsURL)
                    }
                }
                .accessibilityIdentifier("tracker.settingsFile.open")
                Button("Show in Finder") {
                    if model.ensureFile() {
                        SystemSettings.showFolder(model.settingsURL?.deletingLastPathComponent())
                    }
                }
                .accessibilityIdentifier("tracker.settingsFile.finder")
            }
            .controlSize(.small)
            .padding(.top, Design.Spacing.tight)
            .disabled(model.settingsURL == nil)
            if let added = model.lastAdded {
                Label("Added \(added.value) to the \(added.list.displayNameWithKey).", systemImage: SymbolName.checkmark)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tracker.settingsFile.added")
            }
            if let message = model.message {
                ErrorLine(text: message)
            }
        }
    }

    private var logsRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.small) {
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text("Activity logs")
                path(TrackerSettingsModel.displayPath(model.logsURL))
                Button("Show in Finder") { SystemSettings.showFolder(model.logsURL) }
                    .controlSize(.small)
                    .padding(.top, Design.Spacing.tight)
                    .disabled(model.logsURL.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
                    .accessibilityIdentifier("tracker.logs.finder")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            InfoButton(info: logsInfo).accessibilityIdentifier("tracker.info.logs")
        }
    }

    private func path(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    /// The maintenance commands, with today's date in the examples.
    private var logsInfo: SettingsInfo {
        let today = TrackingCalendar(timeZone: .current).day(containing: app.clock.now).description
        let januaryFirst = String(today.prefix(4)) + "-01-01"
        return SettingsInfo(
            title: "Activity logs",
            paragraphs: [
                "The tracker writes your activity to one file per month in this folder in iCloud Drive, where iPhone "
                    + "and iPad read it.",
                "To remove a day from the logs, or to apply the current exclusions to activity already recorded, "
                    + "run these commands in Terminal with your dates. Both rewrite the logs here and in iCloud Drive, "
                    + "and cannot be undone.",
            ],
            snippet: "tracker-event forget-day \(today)\ntracker-event reapply-exclusions \(januaryFirst) \(today)"
        )
    }
}

/// The exclusion drafted in the Activity section, focused, until it is
/// added to the settings file or cancelled (spec_activity.md §4).
private struct PendingExclusionSection: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = app.trackerSettings
        if let pending = model.pendingExclusion {
            Section {
                LabeledContent(pending.list.entryName) {
                    TextField(pending.list.entryName, text: Binding {
                        model.pendingExclusion?.value ?? ""
                    } set: { value in
                        model.pendingExclusion?.value = value
                    })
                    .labelsHidden()
                    .focused($focused)
                    .accessibilityIdentifier("tracker.pendingExclusion")
                }
                if let message = model.message {
                    ErrorLine(text: message)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { model.pendingExclusion = nil }
                    Button("Add to Settings File") { model.addPendingExclusion() }
                        .disabled(pending.value.trimmed.isEmpty)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("tracker.pendingExclusion.add")
                }
            } header: {
                Text("Exclude from Tracking")
            } footer: {
                Text(
                    "Adds the entry to the \(pending.list.displayNameWithKey) in the settings file, "
                        + "which keeps everything else as it is."
                )
            }
            .onAppear { focused = true }
        }
    }
}
