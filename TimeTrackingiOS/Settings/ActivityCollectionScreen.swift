// ActivityCollectionScreen: Settings > Activity collection (spec_ios.md
// §2.9, §9, §11 item 3): the master switch, Screen Time and app sets, the
// setup steps with their check marks, and the upload.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct ActivityCollectionScreen: View {
    @Bindable var collection: CollectionModel

    var body: some View {
        Form {
            Section {
                Toggle("Collect activity on this device", isOn: Binding(
                    get: { collection.isEnabled },
                    set: { collection.setEnabled($0) }
                ))
                .accessibilityIdentifier("collection.enabled")
            } footer: {
                Text(
                    "Records labeled events (app sets, Focus, automations, Safari sites, this app) for the Mac's activity log. " +
                        "Nothing is assigned to projects, and the exclusions apply before anything is written."
                )
            }
            if collection.isEnabled {
                screenTimeSection
                setupSection
                uploadSection
            }
        }
        .navigationTitle("Activity Collection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var screenTimeSection: some View {
        Section {
            LabeledContent("Screen Time", value: screenTimeText)
                .accessibilityIdentifier("collection.screenTime")
            if collection.screenTime == .notDetermined {
                Button("Allow Screen Time Access") {
                    Task { await collection.requestAuthorization() }
                }
                .accessibilityIdentifier("collection.requestScreenTime")
            }
            if collection.screenTime == .approved {
                appSets
            }
            if let error = collection.ladderError {
                ErrorLine(text: error)
            }
        } header: {
            Text("App Sets")
        } footer: {
            if collection.screenTime == .denied {
                Text("Screen Time access is off; Focus, automations, Safari, and this app are still collected.")
            } else {
                Text("Minutes of daily use per set. Only the set's label reaches the log, never the apps in it.")
            }
        }
    }

    /// The app sets, each opening its editor, and the Add menu.
    @ViewBuilder private var appSets: some View {
        ForEach(collection.sets) { set in
            NavigationLink(set.label) {
                LadderSetEditor(collection: collection, set: set)
            }
            .deleteDisabled(set.isEverything)
        }
        .onDelete { offsets in
            for index in offsets where !collection.sets[index].isEverything {
                collection.removeSet(id: collection.sets[index].id)
            }
        }
        Menu {
            ForEach(LadderSet.suggestedLabels, id: \.self) { label in
                Button(label) { collection.addSet(label: label) }
            }
            Divider()
            Button("Other") { collection.addSet(label: "Apps") }
        } label: {
            Label("Add App Set", systemImage: "plus")
        }
    }

    private var screenTimeText: String {
        switch collection.screenTime {
        case .approved: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        }
    }

    private var setupSection: some View {
        Section {
            SetupStep(
                title: "Focus filter",
                done: collection.state.lastFocusEventAt != nil,
                detail: "In Settings > Focus, choose a Focus, then Add Filter > TimeTracking, and give it a label."
            )
            SetupStep(
                title: "Automations",
                done: collection.state.lastIntentEventAt != nil,
                detail: "In Shortcuts > Automation, add \"Log Activity Event\" for \"App Is Opened\" and \"Is Closed\" of the two "
                    + "or three apps whose exact times matter, for a charger connected or disconnected, and for arriving or leaving. "
                    + "iOS shows a notification for every run, so keep it to a few."
            )
            SetupStep(
                title: "Safari extension",
                done: collection.state.lastWebEventAt != nil,
                detail: "In Settings > Apps > Safari > Extensions, turn on TimeTracking and allow All Websites. "
                    + "The exclusions of the Mac's Tracker pane decide what is kept."
            )
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Setup")
        } footer: {
            Text("Each step is checked once its first event arrives.")
        }
    }

    private var uploadSection: some View {
        Section("Upload") {
            LabeledContent("Last upload", value: collection.lastFlushAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            LabeledContent("Pending events", value: "\(collection.pendingCount)")
                .accessibilityIdentifier("collection.pending")
            Button("Upload Now") {
                Task { await collection.flush() }
            }
            .accessibilityIdentifier("collection.flush")
            if let error = collection.flushError {
                ErrorLine(text: error)
            }
        }
    }
}

/// One setup step with its check mark.
private struct SetupStep: View {
    var title: String
    var done: Bool
    var detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(Color.startTint) : AnyShapeStyle(.tertiary))
                .accessibilityLabel(done ? "Done" : "Not done")
        }
    }
}

/// An error under a control: the warning symbol and the message in red.
struct ErrorLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.red)
    }
}
