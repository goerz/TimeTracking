// PomodoroButton: the Pomodoro button of the Timer bar and the iOS Timer
// card (design.md §7, timer.md §5.1, ios.md §2.8).

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

/// A circle with the apple glyph (`SymbolName.pomodoro`) while off; while on, a capsule with a
/// progress ring and the phase's countdown; while a confirmation is
/// pending, an accent capsule reading "Start Break" or "Start Focus" that
/// confirms on click (⌘↩ on the Mac). Its menu holds every Pomodoro action.
struct PomodoroButton: View {
    var state: PomodoroButtonState
    var diameter: CGFloat
    var now: () -> Date
    var perform: (PomodoroAction) -> Void
    var openSettings: () -> Void

    // The light fill of the off circle and the running capsule.
    #if os(macOS)
        private static let fill = AnyShapeStyle(.quaternary)
    #else
        private static let fill = AnyShapeStyle(.fill.tertiary)
    #endif

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
        let label = Label {
            Text("Pomodoro")
        } icon: {
            Image(symbol: SymbolName.pomodoro)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: diameter * 0.45))
        .foregroundStyle(.primary)
        .frame(width: diameter, height: diameter)
        .background(Circle().fill(Self.fill))
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
            capsule(fill: Self.fill) {
                PomodoroRing(progress: progress, tint: tint)
            } text: {
                Text(pomodoro.countdownText(at: now) ?? "").foregroundStyle(.primary)
            }
        }
        .modifier(PomodoroMenuStyle())
        .help(title)
        .accessibilityLabel("Pomodoro")
        .accessibilityValue(title)
        .accessibilityIdentifier("timer.pomodoroButton")
    }

    /// The confirmation in the same capsule: the next phase's glyph and
    /// name on an accent tint.
    private func confirmation(_ title: String, _ action: PomodoroAction) -> some View {
        let isBreak = action == .startBreak
        #if os(macOS)
            let help = "\(title) (⌘↩)"
        #else
            let help = title
        #endif
        return Button {
            perform(action)
        } label: {
            capsule(fill: AnyShapeStyle(Color.accentColor.opacity(0.18))) {
                Image(symbol: SymbolName.phase(isFocus: !isBreak))
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
            } text: {
                Text(isBreak ? "Break" : "Focus").fontWeight(.semibold)
            }
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        // ⌘↩ while the Timer shows (Mac window, iPad tab).
        .keyboardShortcut(.return, modifiers: .command)
        .help(help)
        .contextMenu { menuItems }
        .accessibilityLabel(help)
        .accessibilityValue(pomodoro.buttonTitle(at: now()))
        .accessibilityIdentifier("timer.pomodoroConfirm")
    }

    /// The capsule of the on and pending states: a glyph and a text in a
    /// fixed width that fits the longest countdown, so the task field next
    /// to it stays put through focus, break, overtime, and confirmation.
    private func capsule(
        fill: AnyShapeStyle,
        @ViewBuilder glyph: () -> some View,
        @ViewBuilder text: () -> some View
    ) -> some View {
        HStack(spacing: Design.Spacing.tight + 2) {
            glyph()
                .frame(width: diameter * 0.42, height: diameter * 0.42)
            ZStack(alignment: .leading) {
                Text(widestCountdown).hidden()
                text()
            }
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
        }
        .padding(.leading, diameter * 0.29)
        .padding(.trailing, diameter * 0.36)
        .frame(height: diameter)
        .background(Capsule().fill(fill))
        .contentShape(Capsule())
    }

    /// The widest countdown the durations can show: `+88:88`, or `8:88:88`
    /// with a phase of an hour or more.
    private var widestCountdown: String {
        max(state.focusMinutes, state.breakMinutes) >= 60 ? "8:88:88" : "+88:88"
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
