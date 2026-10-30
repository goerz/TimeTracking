// The JSON records of the tool's listings (spec_automation.md §3.5 to §3.8,
// §3.10, §8.1). Their shapes change only with a format version bump.

public import Foundation

/// Builds the JSON records of every listing.
public enum AutomationRecords {
    /// The entry record: id, times, duration, running, task, and the nested
    /// project, area, and client (null without a project).
    public static func entry(_ listing: EntryListing, now: Date, timeZone: TimeZone) -> JSONValue {
        let entry = listing.entry
        return .object([
            "id": .string(entry.id.rawValue),
            "start": .string(ReportCSVWriter.timestamp(entry.start, in: timeZone)),
            "end": .optional(entry.end.map { ReportCSVWriter.timestamp($0, in: timeZone) }),
            "duration": .int(entry.seconds(at: now)),
            "running": .bool(entry.isRunning),
            "task": .string(entry.task),
            "project": listing.project.map { .object(["id": .string($0.id.rawValue), "name": .string($0.name)]) } ?? .null,
            "area": listing.area.map(areaReference) ?? .null,
            "client": listing.client.map(clientReference) ?? .null,
        ])
    }

    /// `{"running", "today": {"date", "duration"}, "pendingChanges", "asOf"}`.
    public static func status(_ status: AutomationStatus, timeZone: TimeZone) -> JSONValue {
        .object([
            "running": status.running.map { entry($0, now: status.asOf, timeZone: timeZone) } ?? .null,
            "today": .object(["date": .string(status.today.description), "duration": .int(status.todaySeconds)]),
            "pendingChanges": .int(status.pendingChanges),
            "asOf": .string(ReportCSVWriter.timestamp(status.asOf, in: timeZone)),
        ])
    }

    /// `{"from", "to", "entries", "total"}`.
    public static func entries(_ result: EntriesResult, timeZone: TimeZone) -> JSONValue {
        .object([
            "from": .optional(result.range?.from.description),
            "to": .optional(result.range?.to.description),
            "entries": .array(result.listings.map { entry($0, now: result.now, timeZone: timeZone) }),
            "total": .int(result.totalSeconds),
        ])
    }

    /// `{"entries": [...]}` for the pieces a write produced.
    public static func entryList(_ listings: [EntryListing], now: Date, timeZone: TimeZone) -> JSONValue {
        .object(["entries": .array(listings.map { entry($0, now: now, timeZone: timeZone) })])
    }

    /// A project record of `projects`.
    public static func project(_ row: ProjectRow, timeZone: TimeZone) -> JSONValue {
        .object([
            "id": .string(row.project.id.rawValue),
            "name": .string(row.project.name),
            "state": .string(row.project.isArchived ? "archived" : "active"),
            "area": row.area.map(areaReference) ?? .null,
            "client": row.client.map(clientReference) ?? .null,
            "createdAt": .string(ReportCSVWriter.timestamp(row.project.createdAt, in: timeZone)),
            "archivedAt": .optional(row.project.archivedAt.map { ReportCSVWriter.timestamp($0, in: timeZone) }),
            "lastEntryAt": .optional(row.lastUsed.map { ReportCSVWriter.timestamp($0, in: timeZone) }),
        ])
    }

    public static func projects(_ rows: [ProjectRow], timeZone: TimeZone) -> JSONValue {
        .object(["projects": .array(rows.map { project($0, timeZone: timeZone) })])
    }

    /// A client record of `clients`.
    public static func client(_ summary: ClientSummary) -> JSONValue {
        .object([
            "id": .string(summary.client.id.rawValue),
            "name": .string(summary.client.name),
            "areaCount": .int(summary.areaCount),
            "activeProjectCount": .int(summary.activeProjectCount),
        ])
    }

    public static func clients(_ summaries: [ClientSummary]) -> JSONValue {
        .object(["clients": .array(summaries.map(client))])
    }

    /// An area record of `areas`.
    public static func area(_ summary: AreaSummary) -> JSONValue {
        .object([
            "id": .string(summary.area.id.rawValue),
            "name": .string(summary.area.name),
            "color": .string(summary.area.color.uppercased()),
            "retired": .bool(summary.area.isRetired),
            "general": .bool(summary.area.isGeneral),
            "client": summary.client.map(clientReference) ?? .null,
            "activeProjectCount": .int(summary.activeProjectCount),
        ])
    }

    public static func areas(_ summaries: [AreaSummary]) -> JSONValue {
        .object(["areas": .array(summaries.map(area))])
    }

    /// `{"clients": {"created", "updated", "unchanged", "skipped"}, "areas", "projects", "entries"}`.
    public static func importSummary(_ report: ImportReport) -> JSONValue {
        .object(ImportSummary.kinds.map { kind, entity in
            let counts = report[entity]
            return JSONValue.Member(kind, .object([
                "created": .int(counts.created),
                "updated": .int(counts.updated),
                "unchanged": .int(counts.unchanged),
                "skipped": .int(counts.skippedDeleted),
            ]))
        })
    }

    /// `{"error": {"code", "message", "candidates"}}`.
    public static func error(_ error: AutomationError) -> JSONValue {
        var members = [JSONValue.Member("code", .int(Int(error.exitCode))), JSONValue.Member("message", .string(error.message))]
        if !error.candidates.isEmpty {
            members.append(JSONValue.Member("candidates", .array(error.candidates.map(JSONValue.string))))
        }
        return .object(["error": .object(members)])
    }

    private static func areaReference(_ area: Area) -> JSONValue {
        .object(["id": .string(area.id.rawValue), "name": .string(area.name), "color": .string(area.color.uppercased())])
    }

    private static func clientReference(_ client: Client) -> JSONValue {
        .object(["id": .string(client.id.rawValue), "name": .string(client.name)])
    }
}

/// The lines of an import summary.
public enum ImportSummary {
    /// The listed kinds in output order.
    public static let kinds: [(String, ImportEntity)] = [
        ("clients", .client), ("areas", .area), ("projects", .project), ("entries", .entry),
    ]

    /// `entries: 1520 created, 3 updated, 41 unchanged, 1 skipped (deleted here)`, one per kind.
    public static func lines(_ report: ImportReport) -> [String] {
        kinds.map { kind, entity in
            let counts = report[entity]
            return "\(kind): \(counts.created) created, \(counts.updated) updated, \(counts.unchanged) unchanged, "
                + "\(counts.skippedDeleted) skipped (deleted here)"
        }
    }
}
