// HealthImport: the iPhone's import of sleep and workouts from Apple Health
// into the store (data_and_sync.md §1.9, ios.md §7).

public import Foundation

/// Apple Health as the import reads it; the iOS app implements it over
/// HealthKit, tests with fixed samples.
public protocol HealthSampleReading: Sendable {
    /// Sleep samples overlapping `interval`: asleep (any stage) and in bed.
    func sleepSamples(in interval: DateInterval) async throws -> (asleep: [DateInterval], inBed: [DateInterval])
    /// Workouts overlapping `interval`, start to end, with their activity
    /// type and distance.
    func workouts(in interval: DateInterval) async throws -> [HealthPeriodDraft]
}

/// One import run per kind.
public enum HealthImport {
    /// The first import reaches this far back.
    public static let firstDays = 60
    /// Later imports redo this many days, for samples a watch syncs late.
    public static let redoDays = 3

    /// The device setting holding when `kind` was last imported (seconds
    /// since 1970; 0 for never). The workout key changed with schema version
    /// 3, so the first import after the upgrade reaches `firstDays` back
    /// and fills in the activity and distance of recent workouts.
    public static func importedThrough(_ kind: HealthPeriod.Kind) -> DeviceSettingKey<Double> {
        switch kind {
        case .sleep: DeviceSettingKey("health.importedThrough.sleep", default: 0)
        case .workout: DeviceSettingKey("health.importedThrough.workout.3", default: 0)
        }
    }

    /// Imports `kind` from `from(importedThrough:now:)` to `now` and
    /// returns the number of records changed.
    @discardableResult
    public static func run(
        _ kind: HealthPeriod.Kind,
        source: any HealthSampleReading,
        store: TimeStore,
        importedThrough: Date?,
        now: Date
    ) async throws -> Int {
        let start = from(importedThrough: importedThrough, now: now)
        // A day earlier, so a period that began before `start` is whole
        // and is left alone rather than imported again cut short.
        let query = DateInterval(start: start - 86_400, end: max(start, now))
        let drafts: [HealthPeriodDraft]
        switch kind {
        case .sleep:
            let samples = try await source.sleepSamples(in: query)
            drafts = HealthPeriod.sleep(asleep: samples.asleep, inBed: samples.inBed).map { HealthPeriodDraft($0) }
        case .workout:
            drafts = try await HealthPeriod.workouts(source.workouts(in: query))
        }
        return try await store.replaceHealthPeriods(kind, from: start, with: drafts)
    }

    /// The start of the replaced range: `redoDays` before the last import,
    /// or `firstDays` before `now` on the first.
    public static func from(importedThrough: Date?, now: Date) -> Date {
        guard let importedThrough else {
            return now - TimeInterval(firstDays) * 86_400
        }
        return min(now, importedThrough) - TimeInterval(redoDays) * 86_400
    }
}
