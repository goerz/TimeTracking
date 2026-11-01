// HealthKitAccess: sleep analysis and workouts from HealthKit, read-only
// (spec_ios.md §7 item 6, spec_data_and_sync.md §1.9).

import Foundation
import HealthKit
import os
import TimeTrackingCore

/// HealthKit behind `HealthAccess` and `HealthSampleReading`.
final nonisolated class HealthKitAccess: HealthAccess, HealthSampleReading {
    private let store = HKHealthStore()

    /// `nil` where the device has no health data (HealthKit unavailable).
    static func available() -> HealthKitAccess? {
        HKHealthStore.isHealthDataAvailable() ? HealthKitAccess() : nil
    }

    var source: any HealthSampleReading {
        self
    }

    func authorize(_ kinds: Set<HealthPeriod.Kind>) async {
        let types = Set(kinds.map(Self.type(of:)))
        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            Logging.logger(category: "Health").error("Authorization: \(String(describing: error), privacy: .public)")
        }
    }

    private static func type(of kind: HealthPeriod.Kind) -> HKObjectType {
        switch kind {
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .workout: HKObjectType.workoutType()
        }
    }

    func sleepSamples(in interval: DateInterval) async throws -> (asleep: [DateInterval], inBed: [DateInterval]) {
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: Self.predicate(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var asleep: [DateInterval] = []
        var inBed: [DateInterval] = []
        for sample in try await query.result(for: store) {
            let span = DateInterval(start: sample.startDate, end: max(sample.startDate, sample.endDate))
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed: inBed.append(span)
            case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: asleep.append(span)
            case .awake, nil: continue
            @unknown default: continue
            }
        }
        return (asleep, inBed)
    }

    func workouts(in interval: DateInterval) async throws -> [DateInterval] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(Self.predicate(interval))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
    }

    private static func predicate(_ interval: DateInterval) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
    }
}
