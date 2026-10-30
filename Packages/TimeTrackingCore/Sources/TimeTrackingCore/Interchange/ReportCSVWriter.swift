// ReportCSVWriter: the Entries and Breakdown CSV and the tool's structure
// tables (spec_automation.md §8.1, §8.2). RFC 4180: comma, doubled quotes,
// header row, UTF-8 without BOM, LF.

public import Foundation

/// Writes the CSV formats shared by Reports and the command-line tool.
public enum ReportCSVWriter {
    /// One CSV line (without the line feed).
    public static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// Quotes a field when it contains a comma, quote, or line break.
    public static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// ISO 8601 with the offset of `timeZone` at that instant.
    public static func timestamp(_ date: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let offset = timeZone.secondsFromGMT(for: date)
        func two(_ value: Int?) -> String {
            String(format: "%02d", value ?? 0)
        }
        let sign = offset < 0 ? "-" : "+"
        let date = "\(String(format: "%04d", parts.year ?? 0))-\(two(parts.month))-\(two(parts.day))"
        let time = "\(two(parts.hour)):\(two(parts.minute)):\(two(parts.second))"
        return "\(date)T\(time)\(sign)\(two(abs(offset) / 3600)):\(two(abs(offset) / 60 % 60))"
    }

    /// `h:mm:ss`.
    public static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    /// `start,stop,seconds,client,area,project,task,running`; the running
    /// entry has an empty stop and its elapsed seconds.
    public static func entriesCSV(_ listings: [EntryListing], now: Date, timeZone: TimeZone = .current) -> String {
        var lines = [line(["start", "stop", "seconds", "client", "area", "project", "task", "running"])]
        for listing in listings {
            let entry = listing.entry
            lines.append(line([
                timestamp(entry.start, in: timeZone),
                entry.end.map { timestamp($0, in: timeZone) } ?? "",
                String(entry.seconds(at: now)),
                listing.client?.name ?? "",
                listing.area?.name ?? "",
                listing.project?.name ?? "",
                entry.task,
                entry.isRunning ? "true" : "false",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One column per level, then `seconds,duration,share,entries`; one row
    /// per leaf of the fully expanded tree. With `periods` (non-empty), a first column
    /// `period` and one row per period and leaf with time in it.
    public static func breakdownCSV(_ report: ReportNode, levels: [GroupKey], periods: [TrackingPeriod] = []) -> String {
        let total = max(report.seconds, 0)
        var header = levels.map(\.rawValue) + ["seconds", "duration", "share", "entries"]
        if !periods.isEmpty {
            header.insert("period", at: 0)
        }
        var lines = [line(header)]
        func row(_ path: [ReportNode], seconds: Int, entries: Int) -> [String] {
            let share = total == 0 ? 0 : Double(seconds) * 100 / Double(total)
            return path.map { $0.name ?? "" } + [String(seconds), duration(seconds), String(format: "%.1f", share), String(entries)]
        }
        for path in report.leafPaths {
            guard let leaf = path.last else {
                continue
            }
            if !periods.isEmpty {
                for period in periods {
                    if let seconds = leaf.buckets[period], seconds > 0 {
                        lines.append(line([period.description] + row(path, seconds: seconds, entries: leaf.entryBuckets[period] ?? 0)))
                    }
                }
            } else {
                lines.append(line(row(path, seconds: leaf.seconds, entries: leaf.entryCount)))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `id,name,state,client,area,color,created_at,archived_at,area_id,client_id`.
    public static func projectsCSV(_ rows: [ProjectRow], timeZone: TimeZone = .current) -> String {
        var lines = [line(["id", "name", "state", "client", "area", "color", "created_at", "archived_at", "area_id", "client_id"])]
        for row in rows {
            let project = row.project
            lines.append(line([
                project.id.rawValue, project.name, project.isArchived ? "archived" : "active", row.client?.name ?? "",
                row.area?.name ?? "", row.area?.color ?? "", timestamp(project.createdAt, in: timeZone),
                project.archivedAt.map { timestamp($0, in: timeZone) } ?? "", project.areaID.rawValue, row.client?.id.rawValue ?? "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `id,name,color,retired,client,client_id`.
    public static func areasCSV(_ areas: [Area], clients: [Client]) -> String {
        let names = Dictionary(clients.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var lines = [line(["id", "name", "color", "retired", "client", "client_id"])]
        for area in areas {
            lines.append(line([
                area.id.rawValue, area.name, area.color, area.isRetired ? "true" : "false", names[area.clientID] ?? "",
                area.clientID.rawValue,
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `id,name`.
    public static func clientsCSV(_ clients: [Client]) -> String {
        ([line(["id", "name"])] + clients.map { line([$0.id.rawValue, $0.name]) }).joined(separator: "\n") + "\n"
    }
}
