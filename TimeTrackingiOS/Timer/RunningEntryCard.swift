// RunningEntryCard: the Timer window's running-entry bar in rows
// (spec_ios.md §2.2): task field, project chip, Pomodoro button, time,
// Start or Stop, and Discard while running.

import SwiftUI
import TimeTrackingCore

struct RunningEntryCard: View {
    @Bindable var model: PhoneModel

    @FocusState private var taskFocused: Bool

    private var timer: TimerModel {
        model.timer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            taskField
            if taskFocused, !model.taskField.suggestions.isEmpty {
                suggestions
            }
            HStack(spacing: 10) {
                projectChip
                Spacer(minLength: 0)
                PomodoroButton(model: model)
            }
            HStack(spacing: 14) {
                timeLabel
                Spacer(minLength: 0)
                if timer.isRunning {
                    Button {
                        Task { await timer.requestDiscard(skipAlert: false) }
                    } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 30, weight: .light))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Discard")
                    .accessibilityIdentifier("timer.discardButton")
                }
                startStopButton
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .onChange(of: timer.focusTaskFieldRequest) { taskFocused = true }
    }

    private var taskField: some View {
        TextField("What are you working on?", text: Bindable(timer).taskText)
            .font(.title3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill)))
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
                    HStack {
                        Text(suggestion.task).lineLimit(1)
                        Spacer()
                        if let id = suggestion.projectID, let label = model.taskField.labels[id] {
                            AreaDot(color: label.color, size: 8)
                            Text(label.name).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timer.suggestion")
            }
        }
    }

    private var projectChip: some View {
        Button {
            model.openPicker()
        } label: {
            HStack(spacing: 6) {
                AreaDot(color: timer.chipLabel.color)
                Text(timer.chipLabel.name).lineLimit(1)
                if let client = timer.chipLabel.client {
                    Text("· \(client)").foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
        }
        .buttonStyle(.plain)
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

    private var timeLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = model.clock.now
            Text(model.pomodoro.pomodoro.countdownText(at: now) ?? timer.timerText(at: now))
                .font(.system(size: 56, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("timer.time")
        }
    }

    @ViewBuilder private var startStopButton: some View {
        if timer.isRunning {
            Button {
                Task { await timer.stop() }
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .stopRed, diameter: 64, halo: true))
            .accessibilityLabel("Stop")
            .accessibilityIdentifier("timer.stopButton")
        } else {
            Button {
                taskFocused = false
                Task { await timer.start() }
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .startGreen, diameter: 64, halo: true))
            .accessibilityLabel("Start")
            .accessibilityIdentifier("timer.startButton")
        }
    }
}

/// "Pomodoro" or the phase with its countdown; "Start Break" or "Start
/// Focus" while a confirmation is pending (spec_ios.md §2.8).
struct PomodoroButton: View {
    @Bindable var model: PhoneModel

    var body: some View {
        let pomodoro = model.pomodoro
        let isRunning = model.timer.isRunning
        if let title = pomodoro.pomodoro.confirmationTitle, let action = pomodoro.pomodoro.nextPhaseAction {
            Button(title) {
                pomodoro.perform(action, isRunning: isRunning)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("timer.pomodoroConfirm")
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Menu {
                    if pomodoro.state.isOn {
                        ForEach(pomodoro.actions(isRunning: isRunning), id: \.self) { action in
                            Button(action.title) { pomodoro.perform(action, isRunning: isRunning) }
                        }
                    } else {
                        Button("Start Pomodoro (\(pomodoro.focusMinutes) min)") { pomodoro.perform(.start, isRunning: isRunning) }
                            .disabled(!isRunning)
                    }
                } label: {
                    Label(pomodoro.pomodoro.buttonTitle(at: model.clock.now), systemImage: "timer")
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timer.pomodoroButton")
            }
        }
    }
}
