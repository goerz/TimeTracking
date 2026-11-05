// DateRangeModel: a section's date range with its presets, arrows, Go to
// Today, and the popover's calendar clicks: one shared by Reports and
// Activity, one of Projects (reports.md §2,
// activity.md §1.1, projects.md §2.4).

import Foundation
import Observation
import TimeTrackingCore

/// The stored range and what the range control shows. Reports and
/// Activity read the same instance, so a change in one section shows in the
/// other; Projects has its own.
@Observable
final class DateRangeModel {
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings
    @ObservationIgnored let key: DeviceSettingKey<ReportRange>

    /// Stored per device as its kind (presets resolve against today).
    private(set) var range: ReportRange {
        didSet { device[key] = range }
    }

    /// The day of the earliest live entry (All time).
    var earliest: TrackingDay?
    /// The first click in the popover's calendar, waiting for the second.
    private(set) var pendingFirstDay: TrackingDay?
    /// Bumped on every change, so sections reload.
    private(set) var revision = 0
    /// The zone's calendar with the synced Midnight (rebuilt on a zone
    /// change by the view, and by `refreshCalendar` on every reload).
    var calendar = TrackingCalendar(timeZone: .current)

    init(clock: any Clock, device: DeviceSettings, key: DeviceSettingKey<ReportRange> = .sharedRange) {
        self.clock = clock
        self.device = device
        self.key = key
        self.range = device[key]
    }

    /// All time: Projects then lists every project, also never-tracked ones.
    var isAllTime: Bool {
        range == .preset(.allTime)
    }

    var today: TrackingDay {
        calendar.day(containing: clock.now)
    }

    /// The inclusive days.
    var days: ClosedRange<TrackingDay> {
        range.days(today: today, earliest: earliest)
    }

    /// "This week · W44".
    var label: String {
        range.label(today: today, earliest: earliest)
    }

    /// The range menu's title: "This month", "Week 43".
    var menuTitle: String {
        range.menuTitle(today: today, earliest: earliest)
    }

    var canShift: Bool {
        range.canShift
    }

    /// The presets the popover highlights.
    var matchingPresets: [RangePreset] {
        range.matchingPresets(today: today, earliest: earliest)
    }

    /// Activity's view: the last 366 days of the selection.
    var activityDays: (days: ClosedRange<TrackingDay>, clipped: Bool) {
        range.capped(to: DayRange.maximumDays, today: today, earliest: earliest)
    }

    func set(_ range: ReportRange) {
        pendingFirstDay = nil
        self.range = range
        revision += 1
    }

    func select(_ preset: RangePreset) {
        set(.preset(preset))
    }

    /// ⌥⌘← and the left arrow.
    func previous() {
        if let shifted = range.shifted(by: -1, today: today) {
            set(shifted)
        }
    }

    /// ⌥⌘→ and the right arrow.
    func next() {
        if let shifted = range.shifted(by: 1, today: today) {
            set(shifted)
        }
    }

    /// ⌘T.
    func goToToday() {
        set(range.goingToToday(today: today))
    }

    /// A click in the popover's calendar: the first sets the first day, the
    /// second the last day (swapped if earlier) and applies the range.
    func pick(_ day: TrackingDay) {
        if let first = pendingFirstDay {
            set(.days(first, day))
        } else {
            pendingFirstDay = day
        }
    }

    /// Re-reads the earliest entry day.
    func refreshEarliest(_ store: TimeStore) async {
        refreshCalendar(store)
        earliest = try? await store.earliestEntryDay()
    }

    /// The Midnight setting, which another device may have changed.
    func refreshCalendar(_ store: TimeStore) {
        let current = store.displayCalendar(timeZone: calendar.timeZone)
        if current.midnightHour != calendar.midnightHour {
            calendar = current
        }
    }
}
