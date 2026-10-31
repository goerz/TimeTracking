// RunningEntryCard: the Timer window's running-entry bar in rows
// (spec_ios.md §2.2): task field; project chip; Pomodoro button, time,
// Discard while running, and Start or Stop.

import SwiftUI
import TimeTrackingCore

struct RunningEntryCard: View {
    @Bindable var model: PhoneModel

    @FocusState private var taskFocused: Bool

    private var timer: TimerModel {
        model.timer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.medium) {
            taskField
            if taskFocused, !model.taskField.suggestions.isEmpty {
                suggestions
            }
            projectChip
            HStack(spacing: Design.Spacing.small) {
                pomodoroButton
                timeLabel
                Spacer(minLength: Design.Spacing.small)
                if timer.isRunning {
                    Button {
                        Task { await timer.requestDiscard(skipAlert: false) }
                    } label: {
                        Label("Discard", systemImage: "xmark")
                    }
                    .buttonStyle(CircleButtonStyle.borderless(diameter: Design.CircleDiameter.bar))
                    .accessibilityIdentifier("timer.discardButton")
                }
                StartStopButton(isRunning: timer.isRunning, diameter: Design.CircleDiameter.bar) {
                    taskFocused = false
                    Task { await timer.start() }
                } stop: {
                    Task { await timer.stop() }
                }
            }
        }
        .padding(.vertical, Design.Spacing.small)
        .onChange(of: timer.focusTaskFieldRequest) { taskFocused = true }
    }

    private var pomodoroButton: some View {
        let pomodoro = model.pomodoro
        let isRunning = timer.isRunning
        return PomodoroButton(
            state: PomodoroButtonState(
                pomodoro: pomodoro.pomodoro,
                focusMinutes: pomodoro.focusMinutes,
                breakMinutes: pomodoro.breakMinutes,
                isRunning: isRunning
            ),
            diameter: Design.CircleDiameter.bar,
            now: { model.clock.now },
            perform: { pomodoro.perform($0, isRunning: isRunning) },
            openSettings: { model.sheet = .settings }
        )
    }

    private var taskField: some View {
        TextField("What are you working on?", text: Bindable(timer).taskText)
            .font(.title2)
            .focused($taskFocused)
            .submitLabel(timer.isRunning ? .done : .go)
            .accessibilityIdentifier("timer.taskField")
            .onSubmit {
                taskFocused = false
                Task { await timer.submitTask() }
            }
            .onChange(of: timer.taskText) { _, text in
                guard taskFocused else {
                    return
                }
                if let trigger = TaskFieldModel.trigger(in: text) {
                    if case let .picker(picker) = model.sheet {
                        picker.search = trigger.query
                    } else {
                        model.openPicker(search: trigger.query)
                    }
                    return
                }
                timer.taskTextChanged()
                Task { await model.taskField.userEdited(text, chipProject: timer.chipProjectID) }
            }
            .onChange(of: taskFocused) { _, focused in
                if !focused {
                    model.taskField.reset()
                    Task { await timer.commitTask() }
                }
            }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.taskField.suggestions.prefix(4).enumerated()), id: \.offset) { _, suggestion in
                Button {
                    taskFocused = false
                    model.taskField.reset()
                    Task { await timer.accept(suggestion) }
                } label: {
                    SuggestionLabel(suggestion: suggestion, label: suggestion.projectID.flatMap { model.taskField.labels[$0] })
                        .padding(.vertical, Design.Spacing.small)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timer.suggestion")
            }
        }
    }

    private var projectChip: some View {
        ProjectChipButton(label: timer.chipLabel) {
            model.openPicker()
        }
        .accessibilityIdentifier("timer.projectChip")
        .popover(item: padPicker) { picker in
            PickerSheet(model: model, picker: picker)
                .frame(minWidth: 340, idealWidth: 360, minHeight: 440, idealHeight: 520)
        }
    }

    /// The iPad's picker popover (spec_ios.md §10.1).
    private var padPicker: Binding<ProjectPickerModel?> {
        Binding {
            if model.settings.isPad, case let .picker(picker) = model.sheet {
                return picker
            }
            return nil
        } set: { value in
            if value == nil, case .picker = model.sheet {
                model.sheet = nil
            }
        }
    }

    /// The chain's elapsed time; a Pomodoro shows on its button instead.
    private var timeLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(timer.timerText(at: model.clock.now))
                .font(.title2.weight(.medium).monospacedDigit())
                .foregroundStyle(timer.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .accessibilityIdentifier("timer.time")
        }
    }
}
