// WidgetSnapshot+Actions: what the widgets' buttons do, the live elapsed
// time every family shows, and the Control Center toggle's value
// (spec_ios.md §3.4, §3.5, §5). The widget views only map these onto
// WidgetKit.

public import Foundation

/// The Control Center toggle's value.
public struct WidgetControlValue: Hashable, Sendable {
    /// On exactly while an entry runs.
    public var isRunning: Bool
    /// The running task, else the project name, else "Tracking"; "Start" while off.
    public var label: String

    public init(isRunning: Bool, label: String) {
        self.isRunning = isRunning
        self.label = label
    }
}

extension WidgetSnapshot {
    /// The interval of the running entry's elapsed-time text in every family:
    /// from the chain start, counting up without an end, so the system
    /// advances it without timeline reloads; `nil` while nothing runs.
    public var elapsedTimer: ClosedRange<Date>? {
        running.map { $0.chainStart ... Date.distantFuture }
    }

    /// The Lock Screen button: Stop while running, else Continue the latest.
    public var primaryAction: WidgetAction {
        if let running {
            return .stop(expected: running.entryID)
        }
        return .continueEntry(latestEntryID)
    }

    /// A Pinned button: Stop on the running project, else start the project.
    public func action(of button: PinnedButton) -> WidgetAction {
        if button.isRunning, let running {
            return .stop(expected: running.entryID)
        }
        return .start(project: button.projectID, task: button.task)
    }

    /// The Control Center toggle's value.
    public var control: WidgetControlValue {
        guard let running else {
            return WidgetControlValue(isRunning: false, label: "Start")
        }
        let label = running.row.task.isEmpty ? (running.row.projectName ?? "Tracking") : running.row.task
        return WidgetControlValue(isRunning: true, label: label)
    }
}
