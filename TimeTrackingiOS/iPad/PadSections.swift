// PadSections: the iPad's section tabs over the shared SectionRouter
// (ios.md §10; calendar.md §4.1; activity.md
// §5). The iPhone has none, so it never creates a calendar store.

import Foundation
import Observation
import TimeTrackingCore

/// The sections of the iPad's tabs, the iPad's wiring of Calendar
/// and Activity, and which tabs have opened.
@Observable
final class PadSections {
    let router: SectionRouter
    /// Tabs opened at least once. A tab's view, and so the Calendar's
    /// calendar-access request, waits for its first opening.
    private(set) var opened: Set<MainSection> = []
    @ObservationIgnored let store: TimeStore
    @ObservationIgnored let events: any CalendarEventStore
    /// The block log in the iCloud container (`nil` under `-UITesting`).
    @ObservationIgnored let blockLog: FileActivityStore?
    /// Whether the current month's block file has not arrived from iCloud.
    @ObservationIgnored var todayFileMissing: () async -> Bool = { false }

    init(
        store: TimeStore,
        clock: any Clock,
        device: DeviceSettings,
        activity: any ActivityReading,
        events: any CalendarEventStore,
        blockLog: FileActivityStore? = nil
    ) {
        self.store = store
        self.events = events
        self.blockLog = blockLog
        self.router = SectionRouter(
            store: store,
            clock: clock,
            device: device,
            activity: activity,
            events: events
        )
        wire()
    }

    /// The iPad reads the synced block log and never changes it, never
    /// runs the tracker, and shows the Macs' trackers from `LiveState`.
    private func wire() {
        let store = store
        let calendar = router.calendar
        calendar.isMac = false
        calendar.sendTrackerCommand = nil
        let activity = router.activity
        activity.isMac = false
        activity.trackerSetUp = { false }
        activity.remoteActivity = {
            let state = await (try? store.liveState()) ?? LiveState()
            return state.activity.values.max { $0.updatedAt < $1.updatedAt }
        }
        activity.waitingForICloud = { [weak self] in
            await self?.todayFileMissing() ?? false
        }
    }

    /// A section tab was selected.
    func open(_ section: MainSection) {
        if !opened.contains(section) {
            opened.insert(section)
        }
        if router.section != section {
            router.select(section)
        }
    }

    /// Entries or structure changed: the opened tabs re-read (the Calendar
    /// only once it has opened, so no change asks for calendar access).
    /// The synced start of day changed: every section shows other days.
    func startOfDayChanged() async {
        await storeChanged()
        if opened.contains(.activity) {
            await router.activity.reload()
        }
    }

    func storeChanged() async {
        if opened.contains(.projects) {
            await router.projects.reload()
        }
        if opened.contains(.reports) {
            await router.reports.reload()
        }
        if opened.contains(.calendar) {
            await router.calendar.reload()
        }
    }
}

extension PadSections {
    /// The live iPad: EventKit and the block log in the iCloud container,
    /// polled like the Mac's and downloaded as it changes.
    static func live(store: TimeStore, clock: any Clock, device: DeviceSettings, identity: AppIdentity?) async -> PadSections {
        let folders: ActivityFolders? = if let identity {
            await Task.detached { ActivityFolders.resolve(identity: identity) }.value
        } else {
            nil
        }
        let blockLog = folders.map { FileActivityStore(folders: $0) }
        let sections = PadSections(
            store: store,
            clock: clock,
            device: device,
            activity: blockLog ?? InMemoryActivityStore(),
            events: EventKitCalendarStore(),
            blockLog: blockLog
        )
        if let folders, !folders.isFallback {
            let calendar = TrackingCalendar(timeZone: .current)
            sections.todayFileMissing = {
                let today = calendar.day(containing: clock.now)
                return await Task.detached { !ICloudBlockDownloads.request(folder: folders.sharedBlocks, day: today) }.value
            }
        }
        await blockLog?.startWatching()
        Task {
            while !Task.isCancelled {
                _ = await sections.todayFileMissing()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        return sections
    }

    /// `-UITesting`: in-memory activity and calendars; never EventKit.
    static func testing(store: TimeStore, clock: any Clock, device: DeviceSettings) -> PadSections {
        PadSections(
            store: store,
            clock: clock,
            device: device,
            activity: InMemoryActivityStore(),
            events: InMemoryCalendarEventStore(access: .notDetermined)
        )
    }
}
