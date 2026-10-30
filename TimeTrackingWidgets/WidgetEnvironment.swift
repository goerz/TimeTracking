// WidgetEnvironment: what every widget and control provider builds from
// (spec_ios.md §3.1, §4 item 2): the store opened read-only, the resolved
// LiveState, and this device's Pomodoro. The extension never writes the store.

import Foundation
import os
import TimeTrackingCore
import WidgetKit

/// A widget timeline entry: one snapshot at the current time.
nonisolated struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot

    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: Float(snapshot.relevance))
    }
}

// swiftlint:disable discouraged_optional_collection - `nil` pinned IDs mean the synced list

/// Opens the shared state and the store, resolves `LiveState`, and builds snapshots.
nonisolated struct WidgetEnvironment {
    let identity = AppIdentity.main

    var shared: WidgetSharedState {
        WidgetSharedState(identity: identity)
    }

    /// The store, read-only; `nil` before the app has created it.
    func openStore() async -> TimeStore? {
        guard let identity, let url = TimeStore.Location.defaultFile(for: identity),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else {
            return nil
        }
        let device = DeviceSettings(identity: identity)
        return try? await TimeStore.open(
            arguments: LaunchArguments(),
            identity: identity,
            deviceID: device.deviceID,
            clock: SystemClock(),
            readOnly: true
        )
    }

    /// The resolver of spec_ios.md §4 item 2.
    var resolver: WidgetLiveResolver {
        let reader = identity.map { LiveStateReader(transport: CloudKitTransport(containerIdentifier: $0.cloudKitContainer)) }
        return WidgetLiveResolver(shared: shared, reader: reader, clock: SystemClock())
    }

    /// A snapshot for now; reloads the timer control when the running entry changed.
    func snapshot(
        pinnedIDs: [ProjectID]? = nil,
        taskMode: PinnedTaskMode? = nil
    ) async -> WidgetSnapshot {
        let store = await openStore()
        var local: LiveState?
        if let store {
            local = try? await store.liveState()
        }
        let resolution = await resolver.resolve(local: local)
        if resolution.runningChanged {
            ControlCenter.shared.reloadControls(ofKind: WidgetKind.timerToggle)
        }
        let device = DeviceSettings(identity: identity)
        return await WidgetSnapshotBuilder(store: store, timeZone: .current).build(
            at: .now,
            live: resolution.liveState,
            setupComplete: shared.setupComplete,
            pomodoro: device[.pomodoroState].state,
            pinnedIDs: pinnedIDs,
            taskMode: taskMode ?? device[.pinnedTaskMode]
        )
    }

    /// The timeline of one entry with the snapshot's end.
    func timeline(
        pinnedIDs: [ProjectID]? = nil,
        taskMode: PinnedTaskMode? = nil
    ) async -> Timeline<SnapshotEntry> {
        let snapshot = await snapshot(pinnedIDs: pinnedIDs, taskMode: taskMode)
        return Timeline(entries: [SnapshotEntry(date: snapshot.date, snapshot: snapshot)], policy: .after(snapshot.reloadAt))
    }

    /// A placeholder snapshot (gallery, redacted states).
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot.placeholder(at: .now)
    }
}

// swiftlint:enable discouraged_optional_collection

/// The Now and Recent widgets' provider.
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetEnvironment.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        guard !context.isPreview else {
            completion(placeholder(in: context))
            return
        }
        Task {
            let snapshot = await WidgetEnvironment().snapshot()
            completion(SnapshotEntry(date: snapshot.date, snapshot: snapshot))
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        Task {
            await completion(WidgetEnvironment().timeline())
        }
    }
}
