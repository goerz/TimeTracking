// TaskFieldModel: autocompletion and the `@` trigger of the task field
// (spec_timer_window.md §2.2, §2.3).

import Foundation
import Observation
import TimeTrackingCore

/// The popup under the task field: task suggestions, or the project picker
/// opened by `@` while focus stays in the field.
@Observable
final class TaskFieldModel {
    /// Suggestions shown at most.
    static let suggestionLimit = 8

    @ObservationIgnored let store: TimeStore

    private(set) var suggestions: [TaskSuggestion] = []
    private(set) var labels: [ProjectID: ProjectLabel] = [:]
    var highlightedSuggestion: Int?
    /// The picker opened by `@`, searching the text after it.
    private(set) var picker: ProjectPickerModel?
    /// The offset of the `@` whose picker was closed with Escape.
    @ObservationIgnored private var dismissedTrigger: Int?
    @ObservationIgnored private var suggestionsDismissed = false

    init(store: TimeStore) {
        self.store = store
    }

    var isShowingSuggestions: Bool {
        picker == nil && !suggestions.isEmpty
    }

    /// The `@` trigger in `text`: an `@` at the start or after a space,
    /// the last one wins; returns its offset and the search after it.
    static func trigger(in text: String) -> (offset: Int, query: String)? {
        let characters = Array(text)
        for index in characters.indices.reversed() where characters[index] == "@" {
            if index == 0 || characters[index - 1].isWhitespace {
                return (index, String(characters[(index + 1)...]))
            }
        }
        return nil
    }

    /// `text` without its `@` trigger and the search after it.
    static func removingTrigger(from text: String) -> String {
        guard let (offset, _) = trigger(in: text) else {
            return text
        }
        return String(String(Array(text)[..<offset]).trimmingTrailingSpaces)
    }

    /// A keystroke changed the field to `text`.
    func userEdited(_ text: String, chipProject: ProjectID?) async {
        if let (offset, query) = Self.trigger(in: text), offset != dismissedTrigger {
            suggestions = []
            if picker == nil {
                picker = ProjectPickerModel(store: store, currentProject: chipProject, taskMatching: true)
            }
            picker?.search = query
            await picker?.reload()
            return
        }
        if Self.trigger(in: text) == nil {
            dismissedTrigger = nil
        }
        picker = nil
        suggestionsDismissed = false
        await loadSuggestions(for: text, chipProject: chipProject)
    }

    private func loadSuggestions(for text: String, chipProject: ProjectID?) async {
        guard !text.trimmed.isEmpty, !suggestionsDismissed else {
            suggestions = []
            highlightedSuggestion = nil
            return
        }
        let found = await (try? store.taskCompletions(containing: text, preferredProject: chipProject, limit: Self.suggestionLimit)) ?? []
        suggestions = found
        highlightedSuggestion = found.isEmpty ? nil : 0
        var labels: [ProjectID: ProjectLabel] = [:]
        for id in Set(found.compactMap(\.projectID)) {
            let probe = TimeEntry(
                projectID: id,
                task: "",
                start: .distantPast,
                end: .distantPast,
                timeZone: "UTC",
                deviceID: DeviceID(),
                createdAt: .distantPast,
                modifiedAt: .distantPast
            )
            if let listing = try? await store.listings(for: [probe]).first {
                labels[id] = ProjectLabel(listing)
            }
        }
        self.labels = labels
    }

    /// ↑ and ↓ move in the suggestions or the picker.
    func move(by offset: Int) {
        if let picker {
            picker.moveHighlight(by: offset)
            return
        }
        guard !suggestions.isEmpty else {
            return
        }
        let current = highlightedSuggestion ?? (offset > 0 ? -1 : suggestions.count)
        highlightedSuggestion = min(max(current + offset, 0), suggestions.count - 1)
    }

    /// Return or Tab with suggestions showing: the highlighted one.
    func acceptSuggestion() -> TaskSuggestion? {
        guard isShowingSuggestions, let index = highlightedSuggestion, suggestions.indices.contains(index) else {
            return nil
        }
        closeSuggestions()
        return suggestions[index]
    }

    /// Return with the picker open: its highlighted choice.
    func choosePickerHighlight() -> ProjectPickerChoice? {
        guard let choice = picker?.chooseHighlighted() else {
            return nil
        }
        picker = nil
        return choice
    }

    /// Escape: closes the popup, leaving the text. Returns whether one was open.
    func escape(text: String) -> Bool {
        if picker != nil {
            picker = nil
            dismissedTrigger = Self.trigger(in: text)?.offset
            return true
        }
        if isShowingSuggestions {
            closeSuggestions()
            return true
        }
        return false
    }

    func closeSuggestions() {
        suggestions = []
        highlightedSuggestion = nil
        suggestionsDismissed = true
    }

    /// Closes everything (focus loss, a choice elsewhere).
    func reset() {
        picker = nil
        suggestions = []
        highlightedSuggestion = nil
        dismissedTrigger = nil
        suggestionsDismissed = false
    }
}

extension String {
    /// The string without trailing spaces.
    var trimmingTrailingSpaces: Substring {
        var text = Substring(self)
        while text.last?.isWhitespace == true {
            text = text.dropLast()
        }
        return text
    }
}
