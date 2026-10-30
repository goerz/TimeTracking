// TrackerPane: the Tracker settings pane (spec_activity_tracking.md §7.4,
// spec_timer_window.md §8.2).

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
            ExclusionsSection()
            OptionsSection()
            MaintenanceSection()
        }
        .formStyle(.grouped)
        .frame(minHeight: 520)
        .task {
            // Re-read the status every 5 seconds while visible.
            while !Task.isCancelled {
                await app.tracker.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
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
            HStack {
                Circle().fill(dotColor).frame(width: 10, height: 10)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(app.tracker.liveness.statusLine(now: app.clock.now)).accessibilityIdentifier("tracker.status")
                }
                Spacer()
                Button(app.tracker.buttonTitle) { Task { await app.tracker.pressButton() } }
                    .accessibilityIdentifier("tracker.button")
            }
            if let version = app.tracker.state?.health.version {
                LabeledContent("Agent version", value: version)
            }
            if let error = app.tracker.lastError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
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
                HStack(alignment: .firstTextBaseline) {
                    Text(step.mark.rawValue).frame(width: 14).accessibilityIdentifier("tracker.mark.\(step.id)")
                    VStack(alignment: .leading) {
                        Text(step.title)
                        Text(step.enables).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(Array(step.actions.enumerated()), id: \.offset) { _, action in
                        actionButton(action)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: TrackerSetupStep.Action) -> some View {
        switch action {
        case .enableTracker:
            Button("Enable Tracker") { Task { await app.tracker.enable() } }
        case .openLoginItems:
            Button("Open Login Items") { app.tracker.agent.openLoginItems() }
        case let .openSettings(anchor):
            Button("Open System Settings") { SystemSettings.openPrivacy(anchor) }
            if anchor == "Privacy_AllFiles" {
                Button("Show Tracker in Finder") { SystemSettings.revealAgent() }
            }
        case let .copySnippet(snippet):
            Button("Copy Snippet") { SystemSettings.copy(snippet) }
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

/// The nine exclusion lists with + and −.
private struct ExclusionsSection: View {
    @Environment(AppModel.self) private var app
    @State private var drafts: [ExclusionList: String] = [:]

    var body: some View {
        let model = app.trackerSettings
        Section("Exclusions") {
            ForEach(ExclusionList.allCases) { list in
                DisclosureGroup(list.title) {
                    ForEach(model.entries(list), id: \.self) { value in
                        entryRow(value, in: list)
                    }
                    addRow(list)
                }
            }
            if let list = model.offerReapply {
                HStack {
                    Text("Saved to \(list.title).")
                    Spacer()
                    Button("Also remove it from past logs…") { Task { await model.reapplyExclusions() } }
                        .accessibilityIdentifier("tracker.reapplyOffer")
                }
            }
        }
    }

    private func entryRow(_ value: String, in list: ExclusionList) -> some View {
        HStack {
            Text(value)
            Spacer()
            Button {
                app.trackerSettings.remove(value, from: list)
            } label: {
                Label("Remove", systemImage: "minus").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
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
            Button {
                app.trackerSettings.add(drafts[list] ?? "", to: list)
                drafts[list] = nil
            } label: {
                Label("Add", systemImage: "plus").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Watched folders, Idle after, synced Safari history, files.
private struct OptionsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.trackerSettings
        Section("Options") {
            LabeledContent("Watched folders") {
                Text(model.roots.joined(separator: ", ")).foregroundStyle(.secondary)
            }
            Stepper(value: $model.idleAfterSeconds, in: 30 ... 3600, step: 30) {
                LabeledContent("Idle after", value: "\(model.idleAfterSeconds / 60) min \(model.idleAfterSeconds % 60) s")
            }
            Text("Affects activity blocks only; the idle prompt has its own threshold in the Idle pane")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Use Safari history synced from other devices", isOn: $model.useSyncedSafariHistory)
            HStack {
                Button("Edit Settings File…") { SystemSettings.open(model.settingsURL) }
                Button("Show Logs in Finder") { SystemSettings.reveal(model.settingsURL?.deletingLastPathComponent()) }
            }
        }
    }
}

/// Forget a Day… and Reapply Exclusions….
private struct MaintenanceSection: View {
    @Environment(AppModel.self) private var app
    @State private var confirmForget = false

    var body: some View {
        @Bindable var model = app.trackerSettings
        Section("Maintenance") {
            HStack {
                DatePicker("Forget a Day…", selection: $model.forgetDay, displayedComponents: .date)
                Button("Forget…") { confirmForget = true }
            }
            HStack {
                DatePicker("From", selection: $model.reapplyFrom, displayedComponents: .date)
                DatePicker("To", selection: $model.reapplyTo, displayedComponents: .date)
                Button("Reapply Exclusions…") { Task { await model.reapplyExclusions() } }
            }
            if let message = model.message {
                Text(message).foregroundStyle(.red).font(.caption)
            }
        }
        .alert("Forget this day?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { Task { await model.forget() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every block of the day is removed from the logs.")
        }
    }
}
