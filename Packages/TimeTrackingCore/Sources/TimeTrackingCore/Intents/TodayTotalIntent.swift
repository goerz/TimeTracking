// The shared App Intents (automation.md §5, ios.md §6). Each
// resolves its parameters and calls IntentActions; none deletes, archives,
// or edits.

public import AppIntents
public import Foundation

/// A day's total including the running entry.
public struct TodayTotalIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Today's Total"
    public static let description = IntentDescription("Returns the time tracked on a day, the running entry included.")
    public static let supportedModes: IntentModes = .background

    @Parameter(title: "Date") public var date: Date?

    @Dependency private var environment: IntentEnvironment

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<Measurement<UnitDuration>> & ProvidesDialog {
        let outcome = try await IntentActions.total(on: date, service: environment.automation())
        return .result(value: Measurement(value: Double(outcome.value), unit: .seconds), dialog: "\(outcome.dialog)")
    }
}
