// ActivityCollectionScreen: Settings > Activity collection (spec_ios.md
// §2.9, §9, §11 item 3): the master switch, Screen Time and app groups, the
// setup steps with their check marks, and sending to iCloud.

import AppIntents
import SwiftUI
import TimeTrackingCore

struct ActivityCollectionScreen: View {
    @Bindable var collection: CollectionModel
    /// A group made by "Custom…", whose editor opens at once.
    @State private var newGroup: LadderSet?

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
                    "Records how long you use your app groups, when a Focus turns on or off, your automations, the Safari sites you visit, "
                        + "and when you use the app, so they appear in Activity. Nothing is added to your projects, and the Privacy "
                        + "exclusions are applied first."
                )
            }
            if collection.isEnabled {
                screenTimeSection
                setupSection
                iCloudSection
            }
        }
        .navigationTitle("Activity Collection")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newGroup) { group in
            LadderSetEditor(collection: collection, set: group)
        }
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
                appGroups
            }
            if let error = collection.ladderError {
                ErrorLine(text: error)
            }
        } header: {
            Text("App Groups")
        } footer: {
            if collection.screenTime == .denied {
                Text("Screen Time access is off. Focus changes, automations, Safari sites, and your use of the app are still recorded.")
            } else {
                Text("The app records daily minutes for each group. Activity shows only the group's name, never the apps in it.")
            }
        }
    }

    /// The app groups, each opening its editor, and the Add menu.
    @ViewBuilder private var appGroups: some View {
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
            Button("Custom…") { newGroup = collection.addSet(label: "New Group") }
        } label: {
            Label("Add App Group", systemImage: "plus")
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
                detail: "In Settings > Focus, choose a Focus, then Add Filter > \(AppDisplayName.orGeneric), and give it a name."
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
                detail: "In Settings > Apps > Safari > Extensions, turn on \(AppDisplayName.orGeneric) and allow All Websites. "
                    + "Sites listed under Privacy are left out."
            )
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Setup")
        } footer: {
            Text("A step gets a check mark once the app receives something from it.")
        }
    }

    private var iCloudSection: some View {
        Section("iCloud") {
            LabeledContent("Last sent", value: collection.lastFlushAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            LabeledContent("Waiting to send", value: "\(collection.pendingCount)")
                .accessibilityIdentifier("collection.pending")
            Button("Send Now") {
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
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.medium) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? AnyShapeStyle(Color.startTint) : AnyShapeStyle(.tertiary))
                .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: Design.Spacing.tight) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
