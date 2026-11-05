// The tool's health listing: sleep and workout periods with the iPhone's
// last import (automation.md §3.8, data_and_sync.md §1.9).

public import Foundation

extension AutomationService {
    /// The live health periods whose start lies in `range` (all time when
    /// `nil`), of `kind` when given, with the last import status.
    public func health(in range: DayRange?, kind: HealthPeriod.Kind? = nil) async throws(AutomationError) -> HealthListing {
        let store = store
        let interval = range.map { $0.interval(in: calendar) }
        let (periods, status) = try await run {
            try await (store.healthPeriods(starting: interval, kind: kind), store.value(.calendarHealthImport))
        }
        return HealthListing(range: range, periods: periods, lastImport: status, timeZone: timeZone)
    }
}

/// The periods `health` lists.
public struct HealthListing: Equatable, Sendable {
    /// `nil` for all time.
    public var range: DayRange?
    public var periods: [HealthPeriod]
    public var lastImport: HealthImportStatus?
    public var timeZone: TimeZone

    /// `{"from", "to", "lastImport": {"device", "at", "kinds"} | null,
    /// "periods": [{"id", "kind", "activity", "start", "end", "duration", "distance"}]}`.
    public var json: JSONValue {
        let zone = timeZone
        return .object([
            "from": .optional(range?.fromText(in: zone)),
            "to": .optional(range?.toText(in: zone)),
            "lastImport": lastImport.map { status in
                .object([
                    "device": .string(status.device),
                    "at": .string(ReportCSVWriter.timestamp(status.date, in: zone)),
                    "kinds": .array(status.kinds.map { .string($0.rawValue) }),
                ])
            } ?? .null,
            "periods": .array(periods.map { period in
                .object([
                    "id": .string(period.id.rawValue),
                    "kind": .string(period.kind.rawValue),
                    "activity": .optional(period.activity),
                    "start": .string(ReportCSVWriter.timestamp(period.start, in: zone)),
                    "end": .string(ReportCSVWriter.timestamp(period.end, in: zone)),
                    "duration": .int(Self.seconds(period)),
                    "distance": period.distance.map { .int($0) } ?? .null,
                ])
            }),
        ])
    }

    /// `id,kind,activity,start,end,seconds,distance`; empty for none.
    public var csv: String {
        var lines = [ReportCSVWriter.line(["id", "kind", "activity", "start", "end", "seconds", "distance"])]
        for period in periods {
            lines.append(ReportCSVWriter.line([
                period.id.rawValue,
                period.kind.rawValue,
                period.activity ?? "",
                ReportCSVWriter.timestamp(period.start, in: timeZone),
                ReportCSVWriter.timestamp(period.end, in: timeZone),
                String(Self.seconds(period)),
                period.distance.map(String.init) ?? "",
            ]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func seconds(_ period: HealthPeriod) -> Int {
        Int(period.interval.duration.rounded(.down))
    }
}
