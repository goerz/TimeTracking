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

    /// The status line's summary of the iPhone's last import.
    func readHealthImport() async throws {
        var shown: Set<HealthPeriod.Kind> = []
        if showSleep {
            shown.insert(.sleep)
        }
        if showWorkouts {
            shown.insert(.workout)
        }
        healthImport = try await HealthImportStatus.summary(
            store.value(.calendarHealthImport),
            shown: shown,
            found: shown.isEmpty ? [] : store.healthKinds()
        )
    }

    /// The status line: "Read from Alex's iPhone today at 7:12." and the like.
    var healthImportText: String? {
        healthImport.map { summary in
            switch summary {
            case .never:
                "No iPhone has read Apple Health yet. Open the app on your iPhone to start."
            case let .waiting(device, kinds):
                "Waiting for \(device) to read \(Self.names(kinds)). Open the app there."
            case let .empty(device, date, kinds):
                "\(device) found no \(Self.names(kinds)) in Apple Health (\(when(date))). "
                    + "If you have some, allow access on the iPhone in Settings › Privacy & Security › Health."
            case let .imported(device, date):
                "Read from \(device) \(when(date))."
            }
        }
    }

    /// "sleep", "workouts", or "sleep and workouts".
    private static func names(_ kinds: [HealthPeriod.Kind]) -> String {
        kinds.map { $0 == .sleep ? "sleep" : "workouts" }.joined(separator: " and ")
    }

    /// "today at 7:12", "yesterday at 7:12", or "on Oct 30 at 7:12".
    private func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: date),
            to: Calendar.current.startOfDay(for: clock.now)
        ).day
        return switch days {
        case 0: "today at \(time)"
        case 1: "yesterday at \(time)"
        default: "on \(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
        }
    }

    /// The same, for a change while the settings are open.
    func loadHealthImport() async {
        do {
            try await readHealthImport()
        } catch {
            report(error)
        }
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
