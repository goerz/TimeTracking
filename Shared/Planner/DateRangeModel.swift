// DateRangeModel: the date range shared by Reports and Activity, with its
// presets, arrows, Go to Today, and the popover's calendar clicks
// (spec_planner_reports.md §2, spec_planner_activity.md §1.1).

import Foundation
import Observation
import TimeTrackingCore

/// The stored range and what the range control shows. Activity reads the
/// same instance, so a change in one section shows in the other.
@Observable
final class DateRangeModel {
    @ObservationIgnored let clock: any Clock
    @ObservationIgnored let device: DeviceSettings

    /// Stored per device as its kind (presets resolve against today).
    private(set) var range: ReportRange {
        didSet { device[.plannerRange] = range }
    }

    /// The day of the earliest live entry (All time).
    var earliest: TrackingDay?
    /// The first click in the popover's calendar, waiting for the second.
    private(set) var pendingFirstDay: TrackingDay?
    /// Bumped on every change, so sections reload.
    private(set) var revision = 0
    /// The zone's calendar (rebuilt on a zone change by the view).
    var calendar = TrackingCalendar(timeZone: .current)

    init(clock: any Clock, device: DeviceSettings) {
        self.clock = clock
        self.device = device
        self.range = device[.plannerRange]
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
        earliest = try? await store.earliestEntryDay()
    }
}
