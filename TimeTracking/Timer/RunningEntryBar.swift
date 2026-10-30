// RunningEntryBar: the bar of the Timer window (spec_timer_window.md §2, §5.1;
// spec_design.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// The title-bar row holds only the traffic lights and the pin. Below it:
/// Pomodoro button, task field, timer, start or stop, discard; then the
/// project chip under the task field's text.
struct RunningEntryBar: View {
    @Environment(AppModel.self) private var app

    /// The height of the title-bar row (the traffic lights' row).
    static let titleRowHeight: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleRow
            HStack(alignment: .top, spacing: Design.Spacing.medium) {
                pomodoroButton
                // The chip shares the task field's column, so it follows the
                // field's leading edge whatever the Pomodoro button's width.
                VStack(alignment: .leading, spacing: Design.Spacing.small) {
                    HStack(spacing: Design.Spacing.medium) {
                        TaskFieldView()
                        timerLabel
                        HStack(spacing: Design.Spacing.tight) {
                            startStopButton
                            if app.timer.isRunning {
                                discardButton
                            }
                        }
                    }
                    .frame(height: Design.CircleDiameter.bar)
                    TimerProjectChip()
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).minX
                } action: { leading in
                    app.presentation.taskFieldLeading = leading
                }
            }
            .padding(.horizontal, Design.Spacing.window)
            Spacer(minLength: 0)
        }
        .frame(height: TimerWindowGeometry.barHeight)
    }

    /// The traffic lights' row: empty (it drags the window) up to the pin.
    private var titleRow: some View {
        HStack {
            Spacer()
            pinButton
        }
        .padding(.trailing, Design.Spacing.medium)
        .frame(height: Self.titleRowHeight)
    }

    private var pomodoroButton: some View {
        PomodoroButton(
            state: PomodoroButtonState(
                pomodoro: app.pomodoro.pomodoro,
                focusMinutes: app.pomodoro.focusMinutes,
                breakMinutes: app.pomodoro.breakMinutes,
                isRunning: app.timer.isRunning
            ),
            diameter: Design.CircleDiameter.bar,
            now: { app.clock.now },
            perform: { app.perform($0) },
            openSettings: { app.router?.openSettings(pane: .pomodoro) }
        )
    }

    /// The chain's elapsed time; a click edits the running entry.
    private var timerLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button {
                app.editEntry()
            } label: {
                Text(app.timer.timerText(at: app.clock.now))
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(app.timer.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .help(app.timer.isRunning ? "Edit Running Entry" : "")
            .accessibilityIdentifier("timer.timerLabel")
            .id(context.date)
        }
        .fixedSize()
    }

    @ViewBuilder private var startStopButton: some View {
        if app.timer.isRunning {
            Button {
                Task { await app.timer.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .stopTint, diameter: Design.CircleDiameter.bar))
            .help("Stop")
            .accessibilityIdentifier("timer.stopButton")
        } else {
            Button {
                Task { await app.timer.start() }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(CircleButtonStyle(color: .startTint, diameter: Design.CircleDiameter.bar))
            .help("Start")
            .accessibilityIdentifier("timer.startButton")
        }
    }

    private var discardButton: some View {
        Button {
            let skip = ModifierKeys.optionIsDown
            Task { await app.timer.requestDiscard(skipAlert: skip) }
        } label: {
            Label("Discard", systemImage: "xmark")
        }
        .buttonStyle(CircleButtonStyle.borderless(diameter: Design.CircleDiameter.bar))
        .help("Discard Running Entry")
        .accessibilityIdentifier("timer.discardButton")
    }

    private var pinButton: some View {
        let pinned = app.settings.timerPinned
        return Button {
            app.setPinned(!pinned)
        } label: {
            Label("Float on Top", systemImage: pinned ? "pin.fill" : "pin")
                .labelStyle(.iconOnly)
                .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin" : "Float on Top")
        .accessibilityIdentifier("timer.pinButton")
        .accessibilityValue(pinned ? "pinned" : "unpinned")
    }
}

/// The bar's project chip with the picker popover.
struct TimerProjectChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var presentation = app.presentation
        ProjectChipButton(label: app.timer.chipLabel) {
            app.openChipPicker()
        }
        .accessibilityIdentifier("timer.projectChip")
        .popover(item: $presentation.pickerModel, arrowEdge: .bottom) { picker in
            ProjectPickerView(model: picker) { choice in
                Task { await app.choose(choice) }
            } onCancel: {
                app.presentation.pickerModel = nil
            }
        }
    }
}
