// PrivacyScreen: Settings > Privacy, the read-only exclusions of
// `Activity/settings.toml` (spec_ios.md §2.9).

import SwiftUI
import TimeTrackingCore

struct PrivacyScreen: View {
    var privacy: TrackerPrivacySettings

    var body: some View {
        Form {
            Section {
                row("Excluded domains", privacy.excludeDomains)
                row("Domain only", privacy.privateDomains)
            } header: {
                Text("Websites")
            }
            Section("Apps") {
                row("Excluded apps", privacy.excludeApps)
                row("App name only", privacy.nameOnlyApps)
                row("Excluded title words", privacy.excludeTitleKeywords)
            }
            Section {
                row("Excluded paths", privacy.excludePaths)
                row("Excluded keywords", privacy.excludeKeywords)
                row("Excluded tmux sessions", privacy.excludeTmuxSessions)
                row("Private agent folders", privacy.privateAgentPaths)
            } header: {
                Text("Files and terminals")
            } footer: {
                Text("Edited in the Tracker pane of TimeTracking's settings on the Mac.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The list's entries under its title, or "None".
    private func row(_ title: String, _ values: [String]) -> some View {
        LabeledContent(title) {
            Text(values.isEmpty ? "None" : values.joined(separator: ", "))
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
        }
    }
}
