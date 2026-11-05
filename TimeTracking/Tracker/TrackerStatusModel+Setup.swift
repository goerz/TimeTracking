// TrackerStatusModel+Setup: the setup checklist of the Tracker pane, with
// each row's on and off line and info (activity_tracking.md §7.4).

import Foundation
import TimeTrackingCore

extension TrackerStatusModel {
    /// The setup checklist of §7.4.
    var setupSteps: [TrackerSetupStep] {
        let registered = registration == .enabled
        return [
            TrackerSetupStep(
                id: "background",
                title: "Background tracker (required)",
                mark: registered ? .done : .attention,
                actions: [registration == .requiresApproval ? .openLoginItems : registered ? .noAction : .enableTracker]
            ),
            openAtLoginStep,
            accessibilityStep,
            automationStep,
            fullDiskAccessStep,
            iCloudStep,
            editorStep,
            tmuxStep,
            agentHooksStep,
        ]
    }

    /// iCloud Drive; while the tracker cannot write the container, the app
    /// copies its activity there, which counts as done.
    private var iCloudStep: TrackerSetupStep {
        var result = step(
            "icloud",
            "iCloud Drive",
            ["shared_folder"],
            lines: (
                enabled: "this Mac's activity shows on iPhone and iPad, and theirs here.",
                disabled: "activity stays on this Mac."
            ),
            actions: [.noAction]
        )
        if ActivityFolderMirror.isNeeded(for: state) {
            result.mark = .done
            result.detail = "On: this Mac's activity is copied to iCloud Drive while the app is open, and shows on iPhone and iPad."
        }
        return result
    }

    /// The app's own login item; the tracker records without it.
    private var openAtLoginStep: TrackerSetupStep {
        let action: TrackerSetupStep.Action = switch appLoginItem {
        case .enabled: .noAction
        case .requiresApproval: .openLoginItems
        case .notRegistered, .notFound: .openAtLogin
        }
        return TrackerSetupStep(
            id: "openAtLogin",
            title: "Open \(bundles.appName) at login",
            mark: appLoginItem == .enabled ? .done : .attention,
            actions: [action]
        )
    }

    /// Accessibility is checked for the agent process itself.
    private var accessibilityStep: TrackerSetupStep {
        let agent = bundles.agentName
        var result = step(
            "accessibility",
            "Accessibility (required)",
            ["window"],
            lines: (
                enabled: "window titles, open documents, and browser addresses are recorded.",
                disabled: "only the names of apps are recorded."
            ),
            actions: [.openSettings(anchor: "Privacy_Accessibility"), .showInFinder(name: agent, url: bundles.agentOrFolder)]
        )
        result.guidance = [
            "Open System Settings › Privacy & Security › Accessibility.",
            "Drag \(agent) from the Finder window into the list.",
            "Turn \(agent) on.",
        ]
        result.note = "Accessibility belongs to \(agent), the tracker itself, which reads the window titles."
        return result
    }

    /// Automation is asked for at first use, once per browser and terminal.
    private var automationStep: TrackerSetupStep {
        var result = step(
            "automation",
            "Automation",
            ["browser", "terminal"],
            lines: (
                enabled: "the tracker asks your browser for its current tab and your terminal for its front tab.",
                disabled: "the tab is read from the browser window instead, and the terminal tab is guessed."
            ),
            actions: [.askAutomation, .openSettings(anchor: "Privacy_Automation")]
        )
        result.guidance = [
            "Open the browsers and terminals you use, click Ask for Access, and click Allow for each.",
            "If you declined: open System Settings › Privacy & Security › Automation.",
            "Under \(bundles.appName), turn on each browser and terminal.",
        ]
        result.note = "Automation belongs to \(bundles.appName): the tracker runs on its behalf. macOS can ask only for open "
            + "apps; the others are asked the first time the tracker reads their tab or pane."
        result.outcome = automationOutcome
        result.info = SettingsInfo(title: "Automation", paragraphs: [
            "In a browser, the tracker records the page you are on; in a terminal, the tab or tmux pane you work in "
                + "and the program running there.",
            "With Automation, it asks Safari, Chrome, Arc, Brave, Edge, and Vivaldi for the current tab's address and "
                + "title, skipping private windows, and asks iTerm2 and Terminal which tab is in front. WezTerm needs no "
                + "permission.",
            "Without it, the address comes from the browser window's accessibility information, and a private window "
                + "is recognized only by its title. In a terminal, the tracker takes the tab that last showed activity, "
                + "which is wrong while output scrolls by in a tab behind the one you look at.",
        ])
        return result
    }

    /// The line under the Automation buttons after "Ask for Access".
    static func automationOutcomeLine(_ outcomes: [AutomationOutcome]) -> String {
        guard !outcomes.isEmpty else {
            return "None of the browsers and terminals the tracker asks are open."
        }
        func names(_ answer: AutomationAnswer) -> [String] {
            outcomes.filter { $0.answer == answer }.map(\.name)
        }
        func line(_ prefix: String, _ names: [String], _ suffix: String = "") -> String? {
            names.isEmpty ? nil : "\(prefix): \(names.formatted(.list(type: .and)))\(suffix)."
        }
        let declined = names(.declined)
        return [
            line("Allowed", names(.allowed)),
            line("Declined", declined, declined.count == 1 ? "; turn it on in System Settings" : "; turn them on in System Settings"),
            line("Couldn't ask", names(.failed)),
        ].compactMap(\.self).joined(separator: " ")
    }

    /// Full Disk Access is checked for the app: the agent runs on its behalf.
    private var fullDiskAccessStep: TrackerSetupStep {
        let app = bundles.appName
        var result = step(
            "fullDisk",
            "Full Disk Access (optional)",
            ["history", "knowledge"],
            lines: (
                enabled: "every Safari page is recorded, and times the tracker was not running are filled in.",
                disabled: "Safari pages are recorded by site only, and times the tracker was not running stay empty."
            ),
            actions: [.openSettings(anchor: "Privacy_AllFiles"), .showInFinder(name: app, url: bundles.app)]
        )
        result.guidance = [
            "Open System Settings › Privacy & Security › Full Disk Access.",
            "Drag \(app) from the Finder window into the list, or click + and choose it.",
            "Turn \(app) on.",
        ]
        // A grant reached the running agent only after a restart.
        if registration == .enabled, result.mark != .done {
            result.actions.append(.restartTracker)
            result.guidance.append("Click Restart Tracker, so the running tracker gets the access.")
        }
        result.note = "The tracker runs on behalf of \(app), so macOS checks \(app)'s Full Disk Access, not \(bundles.agentName)'s."
        result.info = SettingsInfo(title: "Full Disk Access", paragraphs: [
            "Full Disk Access lets the tracker read Safari's history and the app usage macOS records on its own.",
            "From Safari's history it lists every page you visited, not only the one on screen when the tracker last "
                + "looked. From the usage records it fills in the apps you used while the tracker was not running, "
                + "for example before you enabled it or while it was updated.",
            "Without it, Safari pages are recorded by site only, and those times stay empty.",
        ])
        return result
    }

    private var editorStep: TrackerSetupStep {
        var result = step(
            "editor",
            "Neovim title (optional)",
            ["editor"],
            lines: (
                enabled: "the file open in Neovim is read from the terminal title.",
                disabled: "the tracker asks Neovim for its file, which is slower, and otherwise knows only the folder."
            ),
            actions: [.copySnippet(TrackerSnippets.editor)]
        )
        result.info = SettingsInfo(
            title: "Neovim title",
            paragraphs: [
                "Neovim can show the path of the open file in the terminal's title, and in tmux in the pane's title. "
                    + "The tracker reads it from there every 30 seconds.",
                "Add this line to your Neovim configuration, ~/.config/nvim/init.vim. "
                    + "In init.lua, write vim.opt.title = true and vim.opt.titlestring = \"nvim %F\" instead.",
            ],
            snippet: TrackerSnippets.editor
        )
        return result
    }

    private var tmuxStep: TrackerSetupStep {
        var result = step(
            "tmux",
            "tmux hooks (optional)",
            ["tmux_events"],
            lines: (
                enabled: "switching tmux sessions, windows, and panes is recorded the moment you switch.",
                disabled: "a switch is noticed within 30 seconds."
            ),
            actions: [.copySnippet(TrackerSnippets.tmux)]
        )
        result.info = SettingsInfo(
            title: "tmux hooks",
            paragraphs: [
                "With these hooks, tmux tells the tracker when you change session, window, or pane, and when the "
                    + "terminal window comes to the front.",
                "Add the lines to ~/.tmux.conf, then run tmux source-file ~/.tmux.conf. The tracker-event command "
                    + "must be on tmux's PATH. Errors stay silent; this row shows ✓ once events arrive.",
            ],
            snippet: TrackerSnippets.tmux
        )
        return result
    }

    private var agentHooksStep: TrackerSetupStep {
        var result = step(
            "agentHooks",
            "Claude Code hooks (optional)",
            ["agent_events"],
            lines: (
                enabled: "when Claude Code starts and stops working is recorded the moment it happens.",
                disabled: "when Claude Code starts and stops working is noticed within 30 seconds."
            ),
            actions: [.copySnippet(TrackerSnippets.agentHooks)]
        )
        result.info = SettingsInfo(
            title: "Claude Code hooks",
            paragraphs: [
                "With these hooks, Claude Code tells the tracker when you submit a prompt, when it stops working, "
                    + "and when a session ends.",
                "Add them to ~/.claude/settings.json. If the file already has a \"hooks\" key, add the three "
                    + "entries to it. The tracker-event command must be on Claude Code's PATH. Each call runs in the "
                    + "background, so Claude Code never waits for the tracker; errors stay silent, and this row "
                    + "shows ✓ once events arrive.",
            ],
            snippet: TrackerSnippets.agentHooks
        )
        return result
    }

    private func step(
        _ id: String,
        _ title: String,
        _ sources: [String],
        lines: (enabled: String, disabled: String),
        actions: [TrackerSetupStep.Action]
    ) -> TrackerSetupStep {
        let statuses = sources.compactMap { source in state?.health.sources.first { $0.id == source }?.status }
        let mark: TrackerSetupStep.Mark = if statuses.isEmpty {
            .unknown
        } else if statuses.allSatisfy({ $0 == .active }) {
            .done
        } else {
            .attention
        }
        let detail = switch mark {
        case .done: "On: \(lines.enabled)"
        case .attention: "Off: \(lines.disabled)"
        case .unknown: lines.enabled.prefix(1).uppercased() + lines.enabled.dropFirst()
        }
        return TrackerSetupStep(id: id, title: title, detail: detail, mark: mark, actions: actions)
    }
}
