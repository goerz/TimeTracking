// The stable name a workout's activity type is stored under
// (spec_data_and_sync.md §1.9).

import HealthKit

nonisolated extension HKWorkoutActivityType {
    /// The Swift case name ("running", "traditionalStrengthTraining"), or
    /// "other-" and the raw value for a type this table doesn't name.
    var storedName: String {
        Self.names[self] ?? "other-\(rawValue)"
    }

    /// Every current case; deprecated ones fall back to their raw value.
    static let names: [Self: String] = [
        .americanFootball: "americanFootball", .archery: "archery", .australianFootball: "australianFootball",
        .badminton: "badminton", .barre: "barre", .baseball: "baseball", .basketball: "basketball", .bowling: "bowling",
        .boxing: "boxing", .cardioDance: "cardioDance", .climbing: "climbing", .cooldown: "cooldown",
        .coreTraining: "coreTraining", .cricket: "cricket", .crossCountrySkiing: "crossCountrySkiing",
        .crossTraining: "crossTraining", .curling: "curling", .cycling: "cycling", .discSports: "discSports",
        .downhillSkiing: "downhillSkiing", .elliptical: "elliptical", .equestrianSports: "equestrianSports",
        .fencing: "fencing", .fishing: "fishing", .fitnessGaming: "fitnessGaming", .flexibility: "flexibility",
        .functionalStrengthTraining: "functionalStrengthTraining", .golf: "golf", .gymnastics: "gymnastics",
        .handCycling: "handCycling", .handball: "handball", .highIntensityIntervalTraining: "highIntensityIntervalTraining",
        .hiking: "hiking", .hockey: "hockey", .hunting: "hunting", .jumpRope: "jumpRope", .kickboxing: "kickboxing",
        .lacrosse: "lacrosse", .martialArts: "martialArts", .mindAndBody: "mindAndBody", .mixedCardio: "mixedCardio",
        .other: "other", .paddleSports: "paddleSports", .pickleball: "pickleball", .pilates: "pilates", .play: "play",
        .preparationAndRecovery: "preparationAndRecovery", .racquetball: "racquetball", .rowing: "rowing",
        .rugby: "rugby", .running: "running", .sailing: "sailing", .skatingSports: "skatingSports",
        .snowSports: "snowSports", .snowboarding: "snowboarding", .soccer: "soccer", .socialDance: "socialDance",
        .softball: "softball", .squash: "squash", .stairClimbing: "stairClimbing", .stairs: "stairs",
        .stepTraining: "stepTraining", .surfingSports: "surfingSports", .swimBikeRun: "swimBikeRun",
        .swimming: "swimming", .tableTennis: "tableTennis", .taiChi: "taiChi", .tennis: "tennis",
        .trackAndField: "trackAndField", .traditionalStrengthTraining: "traditionalStrengthTraining",
        .transition: "transition", .underwaterDiving: "underwaterDiving", .volleyball: "volleyball",
        .walking: "walking", .waterFitness: "waterFitness", .waterPolo: "waterPolo", .waterSports: "waterSports",
        .wheelchairRunPace: "wheelchairRunPace", .wheelchairWalkPace: "wheelchairWalkPace", .wrestling: "wrestling",
        .yoga: "yoga",
    ]
}
