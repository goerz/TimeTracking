// StartStopButton: the green Start or red Stop circle of the Timer window's
// bar and the iPhone's card (spec_timer_window.md §2.1; spec_ios.md §2.2).

import SwiftUI
import TimeTrackingCore

/// Stop while an entry runs, Start otherwise.
struct StartStopButton: View {
    var isRunning: Bool
    var diameter: CGFloat
    var start: () -> Void
    var stop: () -> Void

    var body: some View {
        if isRunning {
            Button(action: stop) {
                Label("Stop", systemImage: SymbolName.stop)
            }
            .buttonStyle(CircleButtonStyle(color: .stopTint, diameter: diameter))
            #if os(macOS)
                .help("Stop")
            #endif
                .accessibilityIdentifier("timer.stopButton")
        } else {
            Button(action: start) {
                Label("Start", systemImage: SymbolName.start)
            }
            .buttonStyle(CircleButtonStyle(color: .startTint, diameter: diameter))
            #if os(macOS)
                .help("Start")
            #endif
                .accessibilityIdentifier("timer.startButton")
        }
    }
}
