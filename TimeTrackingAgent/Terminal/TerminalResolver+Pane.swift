// TerminalResolver+Pane: the item of one pane, refined by its foreground
// program (spec_activity_tracking.md §2.2, §3.1, §7.2).

import Foundation
import TimeTrackingCore

extension TerminalResolver {
    /// What the pane's foreground program adds to its item.
    struct Refinement {
        var detail: String
        var file: String?
        var agentSession: AgentSession?
        /// Whether a private agent path keeps the cwd out of the subject.
        var hideCwd = false
        var health: [SourceReport] = []
    }

    /// The item of a pane after exclusions, with editor health.
    func paneItem(
        _ facts: PaneFacts,
        snapshot: TerminalSnapshot,
        context: inout ResolveContext
    ) async -> (SampleItem, [SourceReport]) {
        let exclusions = context.exclusions
        let program = Self.programName(facts.command)
        if let session = facts.session, exclusions.excludesTmuxSession(session) {
            let hidden = "tmux:\(ExclusionRules.privateMarker)"
            return (SampleItem(context: hidden, subject: "", groupKey: hidden, app: facts.app), [])
        }
        let refinement = await refine(facts, program: program, snapshot: snapshot, context: context)
        var detail = refinement.detail
        if let file = refinement.file {
            detail = "\(program) \(exclusions.excludesPath(file) ? ExclusionRules.privateMarker : PathText.lastComponent(file))"
        }
        let windowNamesPane = facts.session != nil && !facts.automaticRename && facts.windowName != program && !facts.windowName.isEmpty
        var subject = windowNamesPane ? facts.windowName : context.tilde(facts.cwd)
        if refinement.hideCwd, !windowNamesPane {
            subject = refinement.agentSession?.name ?? ""
        }
        let groupKey = facts.session.map { "tmux:\($0)" } ?? context.workFolder(ofFolder: facts.cwd)
        let contextName = facts.session.map { "tmux:\($0)" } ?? facts.terminalContext
        var item = SampleItem(context: contextName, subject: subject, detail: detail, groupKey: groupKey, app: facts.app)
        if !facts.cwd.isEmpty, exclusions.excludesPath(facts.cwd) {
            item = ResolveContext.privatePath(item, keepGroup: facts.session != nil)
        }
        if exclusions.excludesTitle(item.subject) {
            item.subject = ""
        }
        if exclusions.excludesTitle(item.detail) {
            item.detail = ""
        }
        if TerminalPrograms.isInterpreter(program) {
            ports.remember(item, forPaneOf: facts.pid)
        }
        return (item, refinement.health)
    }

    /// Editors give their file, coding agents their session, interpreters
    /// register their ports, shells a recently modified file of the cwd,
    /// anything else its program name.
    private func refine(_ facts: PaneFacts, program: String, snapshot: TerminalSnapshot, context: ResolveContext) async -> Refinement {
        if TerminalPrograms.editors.contains(program) {
            let (file, health) = await editorFile(facts, program: program, snapshot: snapshot, context: context)
            return Refinement(detail: program, file: file, health: health)
        }
        let isClaude = program == "claude" || program == "node" || facts.command.contains("claude")
        if isClaude, let session = snapshot.session(inTreeOf: facts.pid) {
            let detail = session.name.isEmpty ? "claude" : "claude \(session.name)"
            return Refinement(detail: detail, agentSession: session, hideCwd: context.exclusions.isPrivateAgentPath(session.cwd))
        }
        if TerminalPrograms.isInterpreter(program) {
            if ports.needsScan(paneOf: facts.pid, now: environment.clock.now),
               let found = await PortRegistry.listeningPorts(paneOf: facts.pid, snapshot: snapshot, commands: environment.commands)
            {
                ports.setPorts(found, paneOf: facts.pid)
            }
            return Refinement(detail: program)
        }
        if TerminalPrograms.shells.contains(program) {
            return Refinement(detail: recentFile(facts.cwd).map(PathText.lastComponent) ?? "")
        }
        return Refinement(detail: program)
    }

    /// `nvim` for `/opt/homebrew/bin/nvim` or `-zsh`.
    static func programName(_ command: String) -> String {
        let last = command.split(separator: "/").last.map(String.init) ?? command
        return last.hasPrefix("-") ? String(last.dropFirst()) : last
    }
}
