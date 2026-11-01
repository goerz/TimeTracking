// RunningEntryBar: the running-entry bar of the Timer (spec_timer_window.md §2, §5.1;
// spec_design.md §7, §8).

import SwiftUI
import TimeTrackingCore

/// The title-bar row holds only the traffic lights and the pin. Below it:
/// Pomodoro button, task field, timer, start or stop, discard; then the
/// project chip at the content inset.
struct RunningEntryBar: View {
    /// The Mini Timer's title-bar row with the pin; the main window's Timer
    /// tab has neither.
    var showsTitleRow = true
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view

    /// The height of the title-bar row (the traffic lights' row).
    static let titleRowHeight: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitleRow {
                titleRow
            }
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                HStack(spacing: Design.Spacing.medium) {
                    pomodoroButton
                    TaskFieldView()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .global).minX
                        } action: { leading in
                            view.taskFieldLeading = leading
                        }
                    timerLabel
                    HStack(spacing: Design.Spacing.tight) {
                        StartStopButton(isRunning: app.timer.isRunning, diameter: Design.CircleDiameter.bar) {
                            Task { await app.timer.start() }
                        } stop: {
                            Task { await app.timer.stop() }
                        }
                        if app.timer.isRunning {
                            discardButton
                        }
                    }
                }
                .frame(height: Design.CircleDiameter.bar)
                // The chip starts at the content inset, under the Pomodoro
                // button, like the list rows below.
                TimerProjectChip()
            }
            .padding(.horizontal, Design.Spacing.window)
            Spacer(minLength: 0)
        }
        .frame(height: TimerWindowGeometry.barHeight - (showsTitleRow ? 0 : Self.titleRowHeight))
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

    /// The chain's elapsed time; a click edits the running entry. Only the
    /// label's text ticks: a button rebuilt each second reset focus and made
    /// SwiftUI rebuild the main menu, even while a menu was open
    /// (spec_design.md §7.1).
    private var timerLabel: some View {
        Button {
            app.editEntry(in: view)
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(app.timer.timerText(at: app.clock.now))
                    .font(.title3.weight(.medium).monospacedDigit())
                    .foregroundStyle(app.timer.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        .buttonStyle(.plain)
        .help(app.timer.isRunning ? "Edit Running Entry" : "")
        .accessibilityIdentifier("timer.time")
        .fixedSize()
    }

    private var discardButton: some View {
        Button {
            let skip = ModifierKeys.optionIsDown
            Task { await app.timer.requestDiscard(skipAlert: skip) }
        } label: {
            Label("Discard", systemImage: SymbolName.discard)
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
            Label("Float on Top", systemImage: pinned ? SymbolName.pinned : SymbolName.pin)
                .labelStyle(.iconOnly)
                .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Stop Floating on Top" : "Float on Top")
        .accessibilityIdentifier("timer.pinButton")
        .accessibilityValue(pinned ? "pinned" : "unpinned")
    }
}

/// The bar's project chip with its Timer view's picker popover.
struct TimerProjectChip: View {
    @Environment(AppModel.self) private var app
    @Environment(TimerUIState.self) private var view

    var body: some View {
        @Bindable var view = view
        ProjectChipButton(label: app.timer.chipLabel) {
            app.openChipPicker(in: view)
        }
        .accessibilityIdentifier("timer.projectChip")
        .popover(item: $view.pickerModel, arrowEdge: .bottom) { picker in
            ProjectPickerView(model: picker) { choice in
                Task { await app.choose(choice, in: view) }
            } onCancel: {
                view.pickerModel = nil
            }
        }
    }
}
