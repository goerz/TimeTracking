// LadderSetState: the per-set ledger of the DeviceActivity ladder
// (spec_ios.md §9.2, "Early callbacks").

public import Foundation

/// What the ladder knows about one set today: the registered window, the
/// registration generation (part of every event name, so callbacks of
/// replaced registrations are recognized), and the last counted step.
public struct LadderSetState: Sendable, Hashable, Codable {
    /// The local day, `YYYY-MM-DD`.
    public var day: String
    /// 0 for the day's first registration (absolute thresholds including
    /// past activity); each re-registration increments it and measures the
    /// remaining minutes from then on.
    public var generation: Int
    /// The thresholds (minutes) of the registered window.
    public var window: [Int]
    /// The last counted step and when its callback came.
    public var countedStep: Int?
    public var countedAt: Date?

    public init(day: String, generation: Int = 0, window: [Int], countedStep: Int? = nil, countedAt: Date? = nil) {
        self.day = day
        self.generation = generation
        self.window = window
        self.countedStep = countedStep
        self.countedAt = countedAt
    }

    /// The window's steps not yet counted.
    public var pendingSteps: [Int] {
        window.filter { $0 > (countedStep ?? 0) }
    }
}

/// One `DeviceActivityEvent` to register: its name, threshold, and whether
/// the day's earlier use counts.
public struct LadderEventSpec: Sendable, Hashable {
    public var name: String
    public var minutes: Int
    public var includesPastActivity: Bool

    public init(name: String, minutes: Int, includesPastActivity: Bool) {
        self.name = name
        self.minutes = minutes
        self.includesPastActivity = includesPastActivity
    }
}

/// The events of one set's repeating midnight-to-midnight schedule.
public struct LadderRegistration: Sendable, Hashable {
    public var setID: String
    public var events: [LadderEventSpec]

    public init(setID: String, events: [LadderEventSpec]) {
        self.setID = setID
        self.events = events
    }
}

/// The parts of a ladder event name, `<set>.<yyyymmdd>.<generation>.<step>`.
public struct LadderEventName: Sendable, Hashable {
    public var setID: String
    /// `yyyymmdd`.
    public var day: String
    public var generation: Int
    public var step: Int

    public init(setID: String, day: String, generation: Int, step: Int) {
        self.setID = setID
        self.day = day
        self.generation = generation
        self.step = step
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, let generation = Int(parts[parts.count - 2]), let step = Int(parts[parts.count - 1]) else {
            return nil
        }
        self.init(
            setID: parts.dropLast(3).joined(separator: "."),
            day: parts[parts.count - 3],
            generation: generation,
            step: step
        )
    }

    public var text: String {
        "\(setID).\(day).\(generation).\(step)"
    }
}
