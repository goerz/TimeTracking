// TaskFieldView: the task field with autocompletion and the `@` trigger
// (spec_timer.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The task field. While an entry runs it edits its task; otherwise it
/// holds the draft. Its suggestions, `@` picker, and focus are its Timer
/// view's own.
struct TaskFieldView: View {
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view
    @FocusState private var focused: Bool

    var body: some View {
        TextField("What are you working on?", text: text)
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($focused)
            .accessibilityIdentifier("timer.taskField")
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            .onKeyPress(.tab) {
                guard let suggestion = view.taskField.acceptSuggestion() else {
                    return .ignored
                }
                Task { await app.timer.accept(suggestion) }
                return .handled
            }
            .onKeyPress(.return) {
                submit()
                return .handled
            }
            .onKeyPress(.escape) {
                escape()
                return .handled
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    view.taskField.reset()
                    Task { await app.timer.commitTask() }
                }
            }
            // Only this view's requests; a request made before the view
            // appeared applies when it does.
            .onChange(of: view.wantsTaskFieldFocus, initial: true) { _, wants in
                if wants {
                    focused = true
                    view.wantsTaskFieldFocus = false
                }
            }
            .onAppear {
                if !app.timer.isRunning {
                    focused = true
                }
            }
    }

    /// User edits go through this binding; programmatic changes do not.
    private var text: Binding<String> {
        Binding {
            app.timer.taskText
        } set: { newValue in
            // AppKit writes the value back on focus; only real edits count.
            guard newValue != app.timer.taskText else {
                return
            }
            app.timer.taskText = newValue
            if TaskFieldModel.trigger(in: newValue) == nil {
                app.timer.taskTextChanged()
            }
            let chip = app.timer.chipProjectID
            view.taskField.textChanged(newValue)
            Task { await view.taskField.userEdited(newValue, chipProject: chip) }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard view.taskField.picker != nil || view.taskField.isShowingSuggestions else {
            return .ignored
        }
        view.taskField.move(by: offset)
        return .handled
    }

    private func submit() {
        app.taskFieldReturn(in: view)
    }

    private func escape() {
        if view.taskField.escape(text: app.timer.taskText) {
            return
        }
        if !app.timer.revertTask() {
            view.focusList()
        }
    }
}

/// The popup under the bar: suggestions or the `@` picker.
struct TaskFieldPopup: View {
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view

    var body: some View {
        if let picker = view.taskField.picker {
            ProjectPickerView(model: picker, showsSearchField: false) { choice in
                app.taskFieldPicked(choice, in: view)
            }
            .popupBackground()
        } else if view.taskField.isShowingSuggestions {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(view.taskField.suggestions.enumerated()), id: \.offset) { index, suggestion in
                    suggestionRow(index, suggestion)
                }
            }
            .padding(.vertical, Design.Spacing.compact)
            .frame(width: 340)
            .popupBackground()
            .accessibilityIdentifier("timer.suggestions")
        }
    }

    private func suggestionRow(_ index: Int, _ suggestion: TaskSuggestion) -> some View {
        SuggestionRow(field: view.taskField, index: index, suggestion: suggestion) {
            view.taskField.closeSuggestions()
            Task { await app.timer.accept(suggestion) }
        }
        .accessibilityIdentifier("timer.suggestion.\(index)")
    }
}

extension View {
    /// The floating panel look of the task field's popup.
    func popupBackground() -> some View {
        background(RoundedRectangle(cornerRadius: Design.Radius.card).fill(.regularMaterial).shadow(radius: 8, y: 2))
    }
}
