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

    /// Every live area as "Client" (a general area) or "Client · Area",
    /// by client and area order.
    func loadHealthAreaChoices() async {
        do {
            let clients = try await store.clients(includeRetired: true)
            let names = Dictionary(clients.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let areas = try await store.areas(of: nil, includeRetired: true)
            healthAreaChoices = clients.flatMap { client in
                areas.filter { $0.clientID == client.id }.map { area in
                    let clientName = names[area.clientID] ?? ""
                    return (area.id, area.isGeneral ? clientName : "\(clientName) · \(area.name)")
                }
            }
        } catch {
            report(error)
        }
    }

    /// Counts `kind` in the reports of `area`, or nowhere.
    func setHealthArea(_ kind: HealthPeriod.Kind, _ area: AreaID?) async {
        do {
            switch kind {
            case .sleep: try await store.set(.calendarSleepAreaID, area)
            case .workout: try await store.set(.calendarWorkoutAreaID, area)
            }
            healthAreas[kind] = area
        } catch {
            report(error)
        }
    }
}
