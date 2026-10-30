// WidgetSnapshot: what the Now, Recent, Pinned, and Lock Screen widgets show,
// and when their timeline ends (spec_ios.md §3). The widget extension's
// providers only wrap a snapshot in a WidgetKit entry.

public import Foundation

/// The content of every widget kind at one moment.
public struct WidgetSnapshot: Hashable, Sendable {
    /// A project and task as a widget row or button shows it.
    public struct Row: Hashable, Sendable, Identifiable {
        public var projectID: ProjectID?
        public var task: String
        public var projectName: String?
        public var clientName: String?
        public var areaColor: String?

        public init(projectID: ProjectID?, task: String, projectName: String?, clientName: String?, areaColor: String?) {
            self.projectID = projectID
            self.task = task
            self.projectName = projectName
            self.clientName = clientName
            self.areaColor = areaColor
        }

        public var id: String {
            "\(projectID?.rawValue ?? "-")|\(task)"
        }
    }

    /// The running entry, from `LiveState` (it may not be in the store yet).
    public struct Running: Hashable, Sendable {
        public var entryID: EntryID
        public var row: Row
        /// The chain's earliest start: elapsed times count from here.
        public var chainStart: Date
    }

    /// A Pinned widget button.
    public struct PinnedButton: Hashable, Sendable, Identifiable {
        public var projectID: ProjectID
        public var name: String
        public var areaColor: String?
        /// The task a tap starts with ("last task" mode), else empty.
        public var task: String
        public var isArchived: Bool
        /// The running entry's project: the button stops it.
        public var isRunning: Bool

        public init(projectID: ProjectID, name: String, areaColor: String?, task: String, isArchived: Bool, isRunning: Bool) {
            self.projectID = projectID
            self.name = name
            self.areaColor = areaColor
            self.task = task
            self.isArchived = isArchived
            self.isRunning = isRunning
        }

        public var id: ProjectID {
            projectID
        }
    }

    public var date: Date
    /// Before the first sync delivered the store: "Open TimeTracking to finish setup".
    public var needsSetup: Bool
    public var running: Running?
    /// The most recent entry other than the running one (idle states).
    public var latest: Row?
    /// The latest entry's id, which Continue continues.
    public var latestEntryID: EntryID?
    /// Today's stopped seconds, the running entry excluded.
    public var todayStoppedSeconds: Int
    /// While running, the start of a live timer that shows today's total:
    /// `todayStoppedSeconds` before the later of the running start and midnight.
    public var todayTimerStart: Date?
    /// This device's Pomodoro.
    public var pomodoro: PomodoroState
    /// The Mac activity lines (spec_ios.md §2.3).
    public var macLines: [String]
    /// Recent distinct (task, project) pairs without the running pair.
    public var recent: [Row]
    public var pinned: [PinnedButton]
    /// The end of the one-entry timeline.
    public var reloadAt: Date
    /// Smart Stack relevance: 100 while running, 60 for an hour after a stop, 10 otherwise.
    public var relevance: Int

    /// The widget gallery's sample: a running entry of 0:42:27.
    public static func placeholder(at now: Date) -> Self {
        let row = Row(
            projectID: nil,
            task: "Clarify noise model",
            projectName: "Noise Model",
            clientName: "University",
            areaColor: "#2A9D8F"
        )
        return Self(
            date: now,
            needsSetup: false,
            running: Running(entryID: EntryID(), row: row, chainStart: now - 2547),
            latest: row,
            latestEntryID: nil,
            todayStoppedSeconds: 5898,
            todayTimerStart: now - 8445,
            pomodoro: .off,
            macLines: [],
            recent: [row],
            pinned: [],
            reloadAt: now + 3600,
            relevance: 10
        )
    }

    /// Today's total at `now` (tests and the inline family).
    public func todaySeconds(at now: Date) -> Int {
        guard let todayTimerStart else {
            return todayStoppedSeconds
        }
        return max(0, Int(now.timeIntervalSince(todayTimerStart)))
    }
}

/// Which task a pinned button starts with (spec_ios.md §2.9, §3.4).
public enum PinnedTaskMode: String, Codable, Sendable, CaseIterable {
    /// The project's most recent task.
    case latest
    /// An empty task.
    case blank
}
