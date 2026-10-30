// PomodoroButton: the Pomodoro button of the Timer bar and the iOS Timer
// card (spec_design.md §7, spec_timer_window.md §5.1, spec_ios.md §2.8).

import SwiftUI
import TimeTrackingCore

/// What the Pomodoro button shows and does.
struct PomodoroButtonState {
    var pomodoro: Pomodoro
    /// The synced durations in minutes.
    var focusMinutes: Int
    var breakMinutes: Int
    /// Whether an entry runs (Start Pomodoro needs one).
    var isRunning: Bool
}

/// A circle with the `timer` glyph while off; while on, a capsule with a
/// progress ring and the phase's countdown; while a confirmation is
/// pending, an accent capsule reading "Start Break" or "Start Focus" that
/// confirms on click (⌘↩ on the Mac). Its menu holds every Pomodoro action.
struct PomodoroButton: View {
    var state: PomodoroButtonState
    var diameter: CGFloat
    var now: () -> Date
    var perform: (PomodoroAction) -> Void
    var openSettings: () -> Void

    private var pomodoro: Pomodoro {
        state.pomodoro
    }

    var body: some View {
        if let title = pomodoro.confirmationTitle, let action = pomodoro.nextPhaseAction {
            confirmation(title, action)
        } else if pomodoro.state.isOn {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                running(at: now())
            }
        } else {
            off
        }
    }

    // MARK: States

    @ViewBuilder private var off: some View {
        let label = Label("Pomodoro", systemImage: "timer")
            .labelStyle(.iconOnly)
            .font(.system(size: diameter * 0.45))
            .foregroundStyle(.secondary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.quaternary))
            .contentShape(Circle())
        if state.isRunning {
            Menu {
                menuItems
            } label: {
                label
            } primaryAction: {
                perform(.start)
            }
            .modifier(PomodoroMenuStyle())
            .help("Start Pomodoro (\(state.focusMinutes) min)")
            .accessibilityLabel("Pomodoro")
            .accessibilityHint("Starts a \(state.focusMinutes) minute focus")
            .accessibilityIdentifier("timer.pomodoroButton")
        } else {
            Menu {
                menuItems
            } label: {
                label
            }
            .modifier(PomodoroMenuStyle())
            .help("Pomodoro")
            .accessibilityLabel("Pomodoro")
            .accessibilityIdentifier("timer.pomodoroButton")
        }
    }

    private func running(at now: Date) -> some View {
        let progress = pomodoro.progress(
            at: now,
            focus: TimeInterval(state.focusMinutes * 60),
            break: TimeInterval(state.breakMinutes * 60)
        ) ?? 0
        let tint = pomodoro.state.isFocusPhase ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
        let title = pomodoro.buttonTitle(at: now)
        return Menu {
            Text(title)
            menuItems
        } label: {
            HStack(spacing: Design.Spacing.tight + 2) {
                PomodoroRing(progress: progress, tint: tint)
                    .frame(width: diameter * 0.42, height: diameter * 0.42)
                Text(pomodoro.countdownText(at: now) ?? "")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.leading, diameter * 0.29)
            .padding(.trailing, diameter * 0.36)
            .frame(height: diameter)
            .background(Capsule().fill(.quaternary))
            .contentShape(Capsule())
        }
        .modifier(PomodoroMenuStyle())
        .help(title)
        .accessibilityLabel("Pomodoro")
        .accessibilityValue(title)
        .accessibilityIdentifier("timer.pomodoroButton")
    }

    private func confirmation(_ title: String, _ action: PomodoroAction) -> some View {
        Button {
            perform(action)
        } label: {
            HStack(spacing: Design.Spacing.tight + 1) {
                Image(systemName: "play.fill").imageScale(.small).accessibilityHidden(true)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, diameter * 0.36)
            .frame(height: diameter)
            .background(Capsule().fill(Color.accentColor))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .keyboardShortcut(.return, modifiers: .command)
        #endif
            .help("\(title) (\(pomodoro.buttonTitle(at: now())))")
            .contextMenu { menuItems }
            .accessibilityIdentifier("timer.pomodoroConfirm")
    }

    // MARK: Menu

    @ViewBuilder private var menuItems: some View {
        if pomodoro.state.isOn {
            ForEach(pomodoro.actions(isRunning: state.isRunning), id: \.self) { action in
                Button(action.title) { perform(action) }
            }
        } else {
            Button("Start Pomodoro (\(state.focusMinutes) min)") { perform(.start) }
                .disabled(!state.isRunning)
        }
        Divider()
        Button("Pomodoro Settings…", action: openSettings)
    }
}

/// The phase's progress as a ring.
private struct PomodoroRing: View {
    var progress: Double
    var tint: AnyShapeStyle

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// A menu whose label draws itself, without the menu indicator.
private struct PomodoroMenuStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}
