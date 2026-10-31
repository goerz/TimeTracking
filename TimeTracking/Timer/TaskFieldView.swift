// TaskFieldView: the task field with autocompletion and the `@` trigger
// (spec_timer_window.md §2.2).

import SwiftUI
import TimeTrackingCore

/// The task field. While an entry runs it edits its task; otherwise it
/// holds the draft.
struct TaskFieldView: View {
    /// The Mini Timer's field; otherwise the main window's.
    var inMiniTimer = true
    @Environment(AppModel.self) private var app
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
                guard let suggestion = app.taskField.acceptSuggestion() else {
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
                    app.taskField.reset()
                    Task { await app.timer.commitTask() }
                }
            }
            .onChange(of: app.timer.focusTaskFieldRequest) {
                // A request goes to the Mini Timer while it is on screen,
                // else to the main window's Timer, not to both.
                if inMiniTimer || app.window?.isVisible != true {
                    focused = true
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
            Task { await app.taskField.userEdited(newValue, chipProject: chip) }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        guard app.taskField.picker != nil || app.taskField.isShowingSuggestions else {
            return .ignored
        }
        app.taskField.move(by: offset)
        return .handled
    }

    private func submit() {
        app.taskFieldReturn()
    }

    private func escape() {
        if app.taskField.escape(text: app.timer.taskText) {
            return
        }
        if !app.timer.revertTask() {
            app.presentation.focusList()
        }
    }
}

/// The popup under the bar: suggestions or the `@` picker.
struct TaskFieldPopup: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let picker = app.taskField.picker {
            ProjectPickerView(model: picker, showsSearchField: false) { choice in
                app.taskFieldPicked(choice)
            }
            .popupBackground()
        } else if app.taskField.isShowingSuggestions {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(app.taskField.suggestions.enumerated()), id: \.offset) { index, suggestion in
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
        let label = suggestion.projectID.flatMap { app.taskField.labels[$0] } ?? .noProject
        let highlighted = app.taskField.highlightedSuggestion == index
        return Button {
            app.taskField.closeSuggestions()
            Task { await app.timer.accept(suggestion) }
        } label: {
            SuggestionLabel(
                suggestion: suggestion,
                label: label,
                projectStyle: highlighted ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary)
            )
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Design.Spacing.medium)
            .padding(.vertical, Design.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(highlighted ? Color.accentColor : .clear)
                    .padding(.horizontal, Design.Spacing.compact)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timer.suggestion.\(index)")
    }
}

extension View {
    /// The floating panel look of the task field's popup.
    func popupBackground() -> some View {
        background(RoundedRectangle(cornerRadius: Design.Radius.card).fill(.regularMaterial).shadow(radius: 8, y: 2))
    }
}
