// RunningEntryBar: the bar of the Timer window (spec_timer_window.md §2, §5.1).

import SwiftUI
import TimeTrackingCore

/// Row 1: traffic lights, task field, timer, start or stop, discard.
/// Row 2: project chip, Pomodoro button, pin.
struct RunningEntryBar: View {
    @Environment(AppModel.self) private var app

    /// Room for the traffic lights.
    static let leadingInset: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TaskFieldView()
                timerLabel
                startStopButton
                if app.timer.isRunning {
                    discardButton
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
            }
            HStack(spacing: 10) {
                ProjectChip()
                PomodoroControl()
                Spacer()
                pinButton
            }
        }
        .padding(.leading, Self.leadingInset)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(height: TimerWindowGeometry.barHeight)
        .background(.bar)
    }

    private var timerLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = app.clock.now
            let elapsed = app.timer.timerText(at: now)
            let countdown = app.pomodoro.pomodoro.countdownText(at: now)
            Button {
                app.editEntry()
            } label: {
                Text(countdown ?? elapsed)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(countdownStyle)
            }
            .buttonStyle(.plain)
            .help(countdown == nil ? "" : elapsed)
            .accessibilityIdentifier("timer.timerLabel")
            .id(context.date)
        }
    }

    private var countdownStyle: AnyShapeStyle {
        switch app.pomodoro.state {
        case .focusOver: AnyShapeStyle(Color.accentColor)
        case .breakOver: AnyShapeStyle(.secondary)
        default: AnyShapeStyle(.primary)
        }
    }

    @ViewBuilder private var startStopButton: some View {
        if app.timer.isRunning {
            Button {
                Task { await app.timer.stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(CircleButtonStyle(color: .stopRed, diameter: 36, halo: true))
            .help("Stop")
            .accessibilityIdentifier("timer.stopButton")
        } else {
            Button {
                Task { await app.timer.start() }
            } label: {
                Label("Start", systemImage: "play.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(CircleButtonStyle(color: .startGreen, diameter: 36, halo: true))
            .help("Start")
            .accessibilityIdentifier("timer.startButton")
        }
    }

    private var discardButton: some View {
        Button {
            let skip = ModifierKeys.optionIsDown
            Task { await app.timer.requestDiscard(skipAlert: skip) }
        } label: {
            Label("Discard", systemImage: "xmark.circle").labelStyle(.iconOnly).font(.title2).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Discard Running Entry")
        .accessibilityIdentifier("timer.discardButton")
    }

    private var pinButton: some View {
        let pinned = app.settings.timerPinned
        return Button {
            app.setPinned(!pinned)
        } label: {
            Label("Float on Top", systemImage: pinned ? "pin.fill" : "pin").labelStyle(.iconOnly).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin" : "Float on Top")
        .accessibilityIdentifier("timer.pinButton")
        .accessibilityValue(pinned ? "pinned" : "unpinned")
    }
}

/// The project chip: area dot, project, " · " client, chevron.
struct ProjectChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var presentation = app.presentation
        let label = app.timer.chipLabel
        Button {
            app.openChipPicker()
        } label: {
            HStack(spacing: 6) {
                AreaDot(color: label.color)
                Text(label.name).lineLimit(1)
                if let client = label.client {
                    Text("· \(client)").foregroundStyle(.secondary).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
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
