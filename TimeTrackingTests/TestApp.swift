// TestApp: an AppModel over an in-memory store at a fixed time, with
// recording services, for the view-model tests (spec_architecture.md §3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTracking

/// The app's models with a `ManualClock` at 2024-03-14T10:00 local time.
@MainActor
struct TestApp {
    let app: AppModel
    let store: TimeStore
    let clock: ManualClock
    let notifier: RecordingNotifier
    let router: RecordingRouter
    let agent: FakeAgentService
    let commands: RecordingTrackerCommands
    let undo = UndoManager()

    /// With `storeFile`, the store is that file and listens to the Debug
    /// app's change notification, as the bundled tool posts it; `observing`
    /// follows the store's changes as the running app does.
    init(
        now: String = "2024-03-14T10:00",
        trackerState: TrackerState? = nil,
        storeFile: URL? = nil,
        observing: Bool = false
    ) async throws {
        let clock = try ManualClock(Self.date(now))
        self.clock = clock
        if let storeFile {
            self.store = try await TimeStore.open(TimeStore.Configuration(
                location: .file(storeFile),
                clock: clock,
                deviceID: DeviceID(),
                timeZone: { .current },
                notifier: AppIdentity.main.map { DarwinChangeNotifier(identity: $0) }
            ))
        } else {
            self.store = try await TimeStore.inMemory(clock: clock, timeZone: .current)
        }
        self.notifier = RecordingNotifier()
        self.router = RecordingRouter()
        self.agent = FakeAgentService()
        self.commands = RecordingTrackerCommands()
        let state = trackerState
        self.app = AppModel(
            store: store,
            clock: clock,
            settings: AppSettings.ephemeral(),
            notifier: notifier,
            agent: agent,
            readTrackerState: { state },
            trackerCommands: commands
        )
        app.router = router
        app.timer.debounce = { _ in }
        app.timer.undoManager = undo
        app.list.undoManager = undo
        await app.start(observing: observing)
    }

    /// A local time `yyyy-MM-dd'T'HH:mm[:ss]` in the current zone.
    static func date(_ text: String) throws -> Date {
        try #require(LaunchArguments.parseInstant(text, timeZone: .current), "bad date \(text)")
    }

    func date(_ text: String) throws -> Date {
        try Self.date(text)
    }

    /// A client "University" with area "Research" and the named projects.
    func projects(_ names: [String], client: String = "University") async throws -> [Project] {
        let (created, _) = try await store.createClient(name: client)
        let area = try await store.createArea(AreaDraft(clientID: created.id, name: "Research"))
        var projects: [Project] = []
        for name in names {
            try await projects.append(store.createProject(ProjectDraft(areaID: area.id, name: name)))
        }
        return projects
    }

    /// A stopped entry from `start` to `end` (local `HH:mm` today unless a full date).
    @discardableResult
    func entry(_ task: String, _ project: Project? = nil, from start: String, to end: String) async throws -> TimeEntry {
        let pieces = try await store.create(EntryDraft(projectID: project?.id, task: task, start: time(start), end: time(end)))
        await app.afterChange()
        return pieces[0]
    }

    /// `HH:mm` today or a full local date.
    func time(_ text: String) throws -> Date {
        try date(text.contains("T") ? text : "2024-03-14T\(text)")
    }

    /// Performs the pending undo and waits for it.
    func undoLast() async {
        undo.undo()
        await app.timer.pendingUndo?.value
        await app.list.pendingUndo?.value
        await app.afterChange()
    }
}
