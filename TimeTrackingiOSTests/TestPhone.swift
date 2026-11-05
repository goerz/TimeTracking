// TestPhone: a PhoneModel over an in-memory store at a fixed time, with
// recording services, for the iOS view-model tests (architecture.md §3).

import Foundation
import Testing
import TimeTrackingCore
@testable import TimeTrackingiOS

/// The iOS app's models with a `ManualClock` at 2024-03-14T10:00 local time.
@MainActor
struct TestPhone {
    let model: PhoneModel
    let store: TimeStore
    let clock: ManualClock
    let scheduler: RecordingScheduler
    let widgets: RecordingWidgetReloader
    let shortcuts: RecordingShortcuts
    let settings: PhoneSettings
    let shared: WidgetSharedState

    init(
        now: String = "2024-03-14T10:00",
        store existing: TimeStore? = nil,
        settings: PhoneSettings = .ephemeral(),
        scheduler: RecordingScheduler = RecordingScheduler(),
        sync: (TimeStore) -> SyncDriving? = { _ in nil },
        collection: (ManualClock, WidgetSharedState) -> CollectionFlushing = { _, _ in NoCollection() },
        pad: (TimeStore, ManualClock, DeviceSettings) -> PadSections? = { _, _, _ in nil }
    ) async throws {
        let clock = try ManualClock(Self.date(now))
        self.clock = clock
        let store: TimeStore = if let existing {
            existing
        } else {
            try await TimeStore.inMemory(clock: clock, timeZone: .current)
        }
        self.store = store
        self.scheduler = scheduler
        self.widgets = RecordingWidgetReloader()
        self.shortcuts = RecordingShortcuts()
        self.settings = settings
        self.shared = WidgetSharedState(defaults: UserDefaults(suiteName: "TimeTrackingiOSTests." + UUID().uuidString) ?? .standard)
        shared.setupComplete = true
        self.model = PhoneModel(
            store: store,
            clock: clock,
            settings: settings,
            notifications: scheduler,
            widgets: widgets,
            shortcuts: shortcuts,
            shared: shared,
            collection: collection(clock, shared),
            pad: pad(store, clock, settings.device)
        )
        model.sync = sync(store)
        model.timer.debounce = { _ in }
        model.boundedFetch = { fetch in await fetch() }
        model.pomodoro.sleepUntil = { _ in throw CancellationError() }
        await model.start(observing: false)
    }

    /// A local time `yyyy-MM-dd'T'HH:mm[:ss]` in the current zone.
    static func date(_ text: String) throws -> Date {
        try TestDates.date(text)
    }

    func date(_ text: String) throws -> Date {
        try Self.date(text)
    }

    /// A client, an area, and projects named `names`.
    func projects(_ names: [String]) async throws -> [Project] {
        try await TestSeed.projects(names, in: store, client: "Personal", area: "Home", color: "#2E8B57")
    }

    /// The next change the store reports after `action`.
    func change(after action: () async throws -> Void) async throws -> StoreChange? {
        var iterator = store.changes.makeAsyncIterator()
        try await action()
        return await iterator.next()
    }
}
