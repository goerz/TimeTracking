// TrackerCommand: the lines of the agent's socket (spec_activity_tracking.md
// §3.1, §7.3).

import Foundation

/// One line sent to the tracker agent's socket `tracker.sock`.
///
/// A line is words separated by spaces; a word containing a space, a
/// quote, or a backslash is written in double quotes with `\"` and `\\`
/// escapes. The agent answers every line with one line: `ok` or
/// `error <reason>`.
public enum TrackerCommand: Sendable, Hashable {
    /// `tick`: take a sample now.
    case tick
    /// `tmux <hook> [<argument>...]`: a tmux hook fired (`client-session-changed`,
    /// `after-select-window`, `after-select-pane`, `pane-focus-in`); advances the tick.
    case tmuxEvent(hook: String, arguments: [String])
    /// `agent <hook> [<argument>...]`: a coding agent hook fired
    /// (`UserPromptSubmit`, `Stop`, `SessionEnd`); advances the tick.
    case agentEvent(hook: String, arguments: [String])
    /// `delete-block <dev> <s>`: removes the block of device `dev` starting at
    /// the local time `s` from both logs and the samples.
    case deleteBlock(device: String, start: String)
    /// `forget-day <date>`: removes everything of the local date `YYYY-MM-DD`.
    case forgetDay(String)
    /// `reapply-exclusions <from> <to>`: applies the current exclusions to the
    /// local dates `from` through `to`.
    case reapplyExclusions(from: String, to: String)

    /// Why a line is not a command.
    public enum ParseError: Error, Hashable {
        case empty
        case unknownCommand(String)
        case wrongArguments(String)
        case unbalancedQuote
    }

    /// Parses one line (without or with its newline).
    public static func parse(_ line: String) throws(ParseError) -> Self {
        let words = try split(line)
        guard let name = words.first else {
            throw .empty
        }
        let arguments = Array(words.dropFirst())
        switch name {
        case "tick":
            guard arguments.isEmpty else {
                throw .wrongArguments(name)
            }
            return .tick
        case "tmux", "agent":
            guard let hook = arguments.first, !hook.isEmpty else {
                throw .wrongArguments(name)
            }
            let rest = Array(arguments.dropFirst())
            return name == "tmux" ? .tmuxEvent(hook: hook, arguments: rest) : .agentEvent(hook: hook, arguments: rest)
        case "delete-block":
            guard arguments.count == 2 else {
                throw .wrongArguments(name)
            }
            return .deleteBlock(device: arguments[0], start: arguments[1])
        case "forget-day":
            guard arguments.count == 1, isDate(arguments[0]) else {
                throw .wrongArguments(name)
            }
            return .forgetDay(arguments[0])
        case "reapply-exclusions":
            guard arguments.count == 2, isDate(arguments[0]), isDate(arguments[1]), arguments[0] <= arguments[1] else {
                throw .wrongArguments(name)
            }
            return .reapplyExclusions(from: arguments[0], to: arguments[1])
        default:
            throw .unknownCommand(name)
        }
    }

    /// The words of the command.
    public var words: [String] {
        switch self {
        case .tick:
            ["tick"]
        case let .tmuxEvent(hook, arguments):
            ["tmux", hook] + arguments
        case let .agentEvent(hook, arguments):
            ["agent", hook] + arguments
        case let .deleteBlock(device, start):
            ["delete-block", device, start]
        case let .forgetDay(day):
            ["forget-day", day]
        case let .reapplyExclusions(from, to):
            ["reapply-exclusions", from, to]
        }
    }

    /// The line without the newline, words quoted where needed.
    public var line: String {
        Self.join(words)
    }

    /// Whether the command rewrites the logs (the Mac app's commands).
    public var isRewrite: Bool {
        switch self {
        case .deleteBlock, .forgetDay, .reapplyExclusions:
            true
        case .tick, .tmuxEvent, .agentEvent:
            false
        }
    }

    // MARK: Words

    /// Joins words into a line, quoting those that need it.
    public static func join(_ words: [String]) -> String {
        words.map { word in
            guard word.isEmpty || word.contains(where: { $0 == " " || $0 == "\"" || $0 == "\\" || $0 == "\t" }) else {
                return word
            }
            let escaped = word.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " ")
    }

    /// Splits a line into words, honoring double quotes.
    public static func split(_ line: String) throws(ParseError) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quoted = false
        var escaping = false
        for character in line where character != "\n" && character != "\r" {
            if escaping {
                current.append(character)
                escaping = false
            } else if quoted {
                switch character {
                case "\\":
                    escaping = true
                case "\"":
                    quoted = false
                default:
                    current.append(character)
                }
            } else if character == " " || character == "\t" {
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            } else if character == "\"" {
                quoted = true
                inWord = true
            } else {
                current.append(character)
                inWord = true
            }
        }
        guard !quoted, !escaping else {
            throw .unbalancedQuote
        }
        if inWord {
            words.append(current)
        }
        return words
    }

    private static func isDate(_ text: String) -> Bool {
        ActivityTimestamp.date(text + "T00:00:00", utcOffset: 0) != nil
    }
}

/// The agent's answer to a line.
public enum TrackerReply: Sendable, Hashable {
    case ok
    case error(String)

    /// Parses `ok` or `error <reason>`.
    public init(line: String) {
        let text = line.trimmingCharacters(in: .newlines)
        if text == "ok" {
            self = .ok
        } else if text.hasPrefix("error") {
            self = .error(String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        } else {
            self = .error("unexpected reply: \(text)")
        }
    }

    /// The reply line without the newline.
    public var line: String {
        switch self {
        case .ok:
            "ok"
        case let .error(reason):
            reason.isEmpty ? "error" : "error \(reason.replacing("\n", with: " "))"
        }
    }
}
