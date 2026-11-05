// PomodoroNotificationText: the phase-end notifications' text
// (timer.md §10, ios.md §8).

/// The title and body of a Pomodoro notification, the same on both platforms.
struct PomodoroNotificationText: Equatable {
    static let breakOver = Self(title: "Break over", body: "Ready for the next focus?")

    var title: String
    var body: String

    /// "25 minutes on Clarify noise model. Time for a break."; without a
    /// task, "25 minutes. Time for a break."
    static func focusDone(minutes: Int, task: String) -> Self {
        let subject = task.isEmpty ? "" : " on \(task)"
        return Self(title: "Focus done", body: "\(minutes) minutes\(subject). Time for a break.")
    }
}
