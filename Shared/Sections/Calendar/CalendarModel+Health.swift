// Sleep and workouts from Apple Health in the Calendar's Activity column
// (spec_calendar.md §3.1).

import Foundation
import TimeTrackingCore

extension CalendarModel {
    /// The periods in `interval` of the kinds the settings show.
    func loadHealthPeriods(in interval: DateInterval) async throws -> [HealthPeriod] {
        guard showSleep || showWorkouts else {
            return []
        }
        return try await store.healthPeriods(in: interval).filter { period in
            switch period.kind {
            case .sleep: showSleep
            case .workout: showWorkouts
            }
        }
    }

    /// The health periods of `day`'s Activity column.
    func healthPeriods(on day: TrackingDay) -> [HealthPeriod] {
        let span = calendar.interval(of: day)
        return healthPeriods.filter { $0.interval.intersects(span) }
    }
}
