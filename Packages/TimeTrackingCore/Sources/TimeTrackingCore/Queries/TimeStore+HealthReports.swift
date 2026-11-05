// Sleep and workouts in reports: the health periods of a kind the Calendar
// shows and maps to an area count as the project "Sleep" or "Workouts" of
// that area (spec_reports.md §1.1, spec_data_and_sync.md §7.3).

import Foundation
import GRDB

extension TimeStore {
    /// One row per kind and day: the mapped periods' time on each day (a
    /// period across midnight is cut there), each piece counted once, with
    /// no task; filtered like entries.
    func healthReportRows(_ query: ReportQuery) throws -> [ReportRow] {
        let filter = query.filter
        // Health time has no task, so a task filter leaves it out.
        guard (filter.taskContains ?? "").isEmpty, !filter.noProjectOnly else {
            return []
        }
        let projects = try healthReportProjects()
        guard !projects.isEmpty else {
            return []
        }
        let calendar = displayCalendar(timeZone: timeZone())
        let days = calendar.interval(of: query.days)
        let range = query.bounds.flatMap { $0.intersection(with: days) } ?? days
        let periods = try healthPeriods(in: range).filter { projects[$0.kind] != nil }
        var sums: [HealthDayKey: (seconds: Int, count: Int)] = [:]
        for period in periods {
            var day = calendar.day(containing: max(period.start, range.start))
            while day <= query.days.upperBound {
                guard let piece = period.interval.intersection(with: calendar.interval(of: day))?.intersection(with: range),
                      piece.start < range.end
                else {
                    break
                }
                if piece.duration > 0 {
                    let key = HealthDayKey(kind: period.kind, day: day)
                    sums[key, default: (0, 0)].seconds += Int(piece.duration)
                    sums[key, default: (0, 0)].count += 1
                }
                day = day.adding(days: 1)
            }
        }
        return sums.compactMap { key, sum -> ReportRow? in
            guard let project = projects[key.kind],
                  Self.passes(project, projectID: project.id, filter: filter),
                  Self.matches(filter.search, task: "", project: project)
            else {
                return nil
            }
            return ReportRow(
                projectID: project.id,
                project: project,
                task: "",
                day: key.day,
                period: TrackingPeriod(query.granularity, containing: key.day, rangeStart: query.days.lowerBound),
                seconds: sum.seconds,
                count: sum.count,
                running: false
            )
        }
    }

    /// The report project of each kind the settings show and map to a live area.
    private func healthReportProjects() throws -> [HealthPeriod.Kind: ReportProject] {
        try read { database in
            var projects: [HealthPeriod.Kind: ReportProject] = [:]
            for kind in HealthPeriod.Kind.allCases {
                let (shown, area) = switch kind {
                case .sleep: try (
                        StoreQueries.settingValue(.calendarShowSleep, in: database),
                        StoreQueries.settingValue(.calendarSleepAreaID, in: database)
                    )
                case .workout: try (
                        StoreQueries.settingValue(.calendarShowWorkouts, in: database),
                        StoreQueries.settingValue(.calendarWorkoutAreaID, in: database)
                    )
                }
                if shown, let area {
                    projects[kind] = try Self.reportProject(kind, area: area, in: database)
                }
            }
            return projects
        }
    }

    /// `kind`'s project in `area`; nil when the area is gone.
    private static func reportProject(_ kind: HealthPeriod.Kind, area: AreaID, in database: Database) throws -> ReportProject? {
        let row = try Row.fetchOne(
            database,
            sql: """
            SELECT a.name, a.color, a.sort_order, c.id AS client_id, c.name AS client_name
            FROM area a LEFT JOIN client c ON c.id = a.client_id
            WHERE a.id = ? AND a.deleted_at IS NULL
            """,
            arguments: [area.rawValue]
        )
        return row.map { row in
            ReportProject(
                id: kind.reportProjectID,
                name: kind.reportName,
                archived: false,
                areaID: area,
                areaName: row["name"],
                areaColor: row["color"],
                areaOrder: row["sort_order"] ?? 0,
                clientID: row.uuid("client_id"),
                clientName: row["client_name"]
            )
        }
    }
}

/// A kind's time on one day.
private struct HealthDayKey: Hashable {
    var kind: HealthPeriod.Kind
    var day: TrackingDay
}
