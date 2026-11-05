// TerminalResolver+Editor: the editor chain of a pane: title, Neovim RPC,
// arguments, cwd (activity_tracking.md §3.1).

import Foundation
import TimeTrackingCore

extension TerminalResolver {
    /// The editor's file: the pane title through `title_patterns` while the
    /// pane's command is that editor, then Neovim RPC (200 ms), then the
    /// editor's arguments, then nothing (cwd only).
    func editorFile(
        _ facts: PaneFacts,
        program: String,
        snapshot: TerminalSnapshot,
        context: ResolveContext
    ) async -> (String?, [SourceReport]) {
        let now = environment.clock.now
        if let pattern = context.settings.terminal.titlePatterns[program], let fromTitle = Self.match(pattern, facts.title) {
            let path = context.expand(fromTitle)
            if program == "nvim", now.timeIntervalSince(lastCrossCheck[facts.key] ?? .distantPast) >= Self.crossCheckInterval {
                lastCrossCheck[facts.key] = now
                if let socket = neovimSocket(forPaneOf: facts.pid, snapshot: snapshot),
                   let fromRPC = await environment.editorRPC.currentFile(socket: socket, timeout: Self.rpcTimeout), fromRPC != path
                {
                    return (path, [SourceReport(.editor, .fallback, Self.titleDisagreesReason)])
                }
            }
            return (path, [SourceReport(.editor, .active)])
        }
        let report = SourceReport(
            .editor,
            .fallback,
            "\(program) doesn't show its file in the terminal title; the file is asked for or guessed"
        )
        if program == "nvim", let socket = neovimSocket(forPaneOf: facts.pid, snapshot: snapshot),
           now.timeIntervalSince(silentSockets[socket] ?? .distantPast) >= Self.silentBackoff
        {
            if let fromRPC = await environment.editorRPC.currentFile(socket: socket, timeout: Self.rpcTimeout) {
                return (fromRPC, [report])
            }
            silentSockets[socket] = environment.clock.now
        }
        return (argumentFile(facts, program: program, snapshot: snapshot, context: context), [report])
    }

    /// The `editor` reason when the pane title and Neovim name different files.
    static let titleDisagreesReason = "The terminal title names a different file than Neovim has open; the title may be out of date"

    /// The last file argument of the editor process in the pane.
    private func argumentFile(_ facts: PaneFacts, program: String, snapshot: TerminalSnapshot, context: ResolveContext) -> String? {
        let tree = (snapshot.processes[facts.pid].map { [$0] } ?? []) + snapshot.processes.descendants(of: facts.pid)
        guard let editor = tree.first(where: { $0.name == program }) ?? tree.first,
              let arguments = environment.processes.arguments(of: editor.pid),
              let file = arguments.dropFirst().last(where: { !$0.hasPrefix("-") && !$0.hasPrefix("+") })
        else {
            return nil
        }
        return file.hasPrefix("/") || file.hasPrefix("~") ? context.expand(file) : facts.cwd + "/" + file
    }

    /// The server socket of the `nvim --embed` process below the pane.
    private func neovimSocket(forPaneOf pid: Int32, snapshot: TerminalSnapshot) -> String? {
        let embeds = snapshot.processes.descendants(of: pid).filter { $0.name == "nvim" }
        let folder = environment.neovimSocketFolder
        guard !embeds.isEmpty, let groups = environment.files.list(folder) else {
            return nil
        }
        for embed in embeds.reversed() {
            for group in groups.sorted() {
                let candidate = "\(folder)/\(group)/nvim.\(embed.pid).0"
                if environment.files.exists(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// The first capture group of `pattern` in `text`.
    static func match(_ pattern: String, _ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              result.numberOfRanges > 1, let range = Range(result.range(at: 1), in: text)
        else {
            return nil
        }
        let value = String(text[range])
        return value.isEmpty ? nil : value
    }
}
