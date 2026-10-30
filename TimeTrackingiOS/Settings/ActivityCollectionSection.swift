// ActivityCollectionSection: the "Activity Collection" and "Privacy"
// sections of the iOS Settings (spec_ios.md §2.9, §9, §11 item 3).

import AppIntents
import SwiftUI
import TimeTrackingCore

/// The master switch, Screen Time, app sets, setup steps with their check
/// marks, and the flush.
struct ActivityCollectionSection: View {
    @Bindable var collection: CollectionModel

    var body: some View {
        Section {
            Toggle("Collect activity on this device", isOn: Binding(
                get: { collection.isEnabled },
                set: { collection.setEnabled($0) }
            ))
            .accessibilityIdentifier("collection.enabled")
        } header: {
            Text("Activity Collection")
        } footer: {
            Text(
                "Records labeled events (app sets, Focus, automations, Safari sites, this app) for the Mac's activity log. " +
                    "Nothing is assigned to projects, and the exclusions apply before anything is written."
            )
        }
        if collection.isEnabled {
            screenTimeSection
            setupSection
            flushSection
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
                ForEach(collection.sets) { set in
                    NavigationLink(set.label) {
                        LadderSetEditor(collection: collection, set: set)
                    }
                }
                .onDelete { offsets in
                    for index in offsets where !collection.sets[index].isEverything {
                        collection.removeSet(id: collection.sets[index].id)
                    }
                }
                Menu("Add App Set") {
                    ForEach(LadderSet.suggestedLabels, id: \.self) { label in
                        Button(label) { collection.addSet(label: label) }
                    }
                    Button("Other…") { collection.addSet(label: "Apps") }
                }
            }
            if let error = collection.ladderError {
                Text(error).foregroundStyle(.red)
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

    private var screenTimeText: String {
        switch collection.screenTime {
        case .approved: "Allowed"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        }
    }

    private var setupSection: some View {
        Section("Setup") {
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
            ShortcutsLink()
            SetupStep(
                title: "Safari extension",
                done: collection.state.lastWebEventAt != nil,
                detail: "In Settings > Apps > Safari > Extensions, turn on TimeTracking and allow All Websites. "
                    + "The exclusions of the Mac's Tracker pane decide what is kept."
            )
        }
    }

    private var flushSection: some View {
        Section("Upload") {
            LabeledContent("Last upload", value: collection.lastFlushAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
            LabeledContent("Pending events", value: "\(collection.pendingCount)")
                .accessibilityIdentifier("collection.pending")
            Button("Flush Now") {
                Task { await collection.flush() }
            }
            .accessibilityIdentifier("collection.flush")
            if let error = collection.flushError {
                Text(error).foregroundStyle(.red)
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
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .primary)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The read-only exclusions of `Activity/settings.toml`.
struct PrivacySection: View {
    var privacy: TrackerPrivacySettings

    var body: some View {
        Section {
            row("Excluded domains", privacy.excludeDomains)
            row("Domain only", privacy.privateDomains)
            row("Excluded apps", privacy.excludeApps)
            row("App name only", privacy.nameOnlyApps)
            row("Excluded paths", privacy.excludePaths)
            row("Excluded keywords", privacy.excludeKeywords)
            row("Excluded tmux sessions", privacy.excludeTmuxSessions)
            row("Private agent folders", privacy.privateAgentPaths)
            row("Excluded title words", privacy.excludeTitleKeywords)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Edited in the Tracker pane of TimeTracking's settings on the Mac.")
        }
    }

    private func row(_ title: String, _ values: [String]) -> some View {
        LabeledContent(title, value: values.isEmpty ? "None" : values.joined(separator: ", "))
    }
}
