// Tests for the DeviceActivity ladder: plan, ledger, registrations, and
// callbacks (spec_ios.md §9.2; spec_activity_tracking.md §6.2, phase 7).

import Foundation
import Synchronization
import Testing
import TimeTrackingCore

/// Records registrations; can refuse counts above a cap.
final class RecordingLadderMonitor: LadderMonitoring {
    private let registrations = Mutex<[LadderRegistration]>([])
    private let stopped = Mutex<[String]>([])

    var all: [LadderRegistration] {
        registrations.withLock { $0 }
    }

    var stops: [String] {
        stopped.withLock { $0 }
    }

    func startMonitoring(_ registration: LadderRegistration, for _: LadderSet) {
        registrations.withLock { $0.append(registration) }
    }

    func stopMonitoring(_ setIDs: [String]) {
        stopped.withLock { $0 += setIDs }
    }
}

/// A ladder harness: an enabled collection log over a staging file in a
/// temporary folder, a fake monitor, and a ManualClock.
struct LadderHarness {
    let folder: TemporaryFolder
    let clock: ManualClock
    let state: CollectionSharedState
    let staging: DeviceEventStagingFile
    let monitor = RecordingLadderMonitor()
    let controller: LadderController

    init(sets: [LadderSet] = [.everything], cap: Int = 100, at time: String = "2024-03-14T10:00:00") throws {
        self.folder = try TemporaryFolder()
        let zone = ActivityFixture.newYork
        self.clock = try ManualClock(#require(ActivityTimestamp.date(time, timeZone: zone)))
        self.state = try CollectionSharedState(defaults: #require(UserDefaults(suiteName: "LadderTests.\(UUID().uuidString)")))
        state.isEnabled = true
        state.ladderSets = sets
        state.eventCap = cap
        self.staging = DeviceEventStagingFile(folder: folder.url)
        let log = CollectionLog(state: state, sink: staging, deviceID: "phone", clock: clock, timeZone: zone)
        self.controller = LadderController(store: state, monitor: monitor, log: log)
    }

    func at(_ time: String) throws {
        try clock.set(#require(ActivityTimestamp.date(time, timeZone: ActivityFixture.newYork)))
    }

    /// The name of `step` in the current registration of `setID`.
    func name(_ setID: String, step: Int) throws -> String {
        let registration = try #require(monitor.all.last { $0.setID == setID })
        return try #require(registration.events.first { $0.name.hasSuffix(".\(step)") }).name
    }

    /// The `n` and `early` of the logged ladder lines.
    func lines() throws -> [(n: Int, early: Bool)] {
        try staging.readAll().filter { $0.source == .ladder }.map { ($0.payloadInt("n") ?? 0, $0.payloadBool("early", default: false)) }
    }
}

/// Checks, at every registration, whether another process could take the
/// App Group lock at that moment.
final class LockProbingMonitor: LadderMonitoring {
    let lockFile: URL
    private let probes = Mutex<[Bool]>([])

    init(lockFile: URL) {
        self.lockFile = lockFile
    }

    /// For each registration: whether the lock was free.
    var lockWasFree: [Bool] {
        probes.withLock { $0 }
    }

    func startMonitoring(_: LadderRegistration, for _: LadderSet) {
        // A second open file stands for another process.
        let descriptor = open(lockFile.path, O_RDWR | O_CREAT, 0o644)
        defer { close(descriptor) }
        let free = flock(descriptor, LOCK_EX | LOCK_NB) == 0
        if free {
            flock(descriptor, LOCK_UN)
        }
        probes.withLock { $0.append(free) }
    }

    func stopMonitoring(_: [String]) {}
}

struct LadderTests {
    @Test("IOS-47 the app's configuration and the monitor's callback update a set's ledger holding the App Group lock")
    func ledgerUpdatesHoldTheLock() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let lockFile = folder.url.appending(path: "defaults.lock")
        let zone = ActivityFixture.newYork
        let clock = try ManualClock(#require(ActivityTimestamp.date("2024-03-14T10:00:00", timeZone: zone)))
        let defaults = try #require(UserDefaults(suiteName: "LadderTests.\(UUID().uuidString)"))
        let state = CollectionSharedState(defaults: defaults, lockFile: lockFile)
        state.isEnabled = true
        state.ladderSets = [.everything]
        state.eventCap = 100
        let monitor = LockProbingMonitor(lockFile: lockFile)
        let sink = DeviceEventStagingFile(folder: folder.url)
        let log = CollectionLog(state: state, sink: sink, deviceID: "phone", clock: clock, timeZone: zone)
        let controller = LadderController(store: state, monitor: monitor, log: log)
        try controller.configure()
        try controller.intervalDidStart(setID: LadderSet.everythingID)
        #expect(monitor.lockWasFree == [false, false])
        // Outside an update the lock is free again.
        let descriptor = open(lockFile.path, O_RDWR)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    }

    @Test("phase 7: a cap of 100 gives Everything 1 to 60 and 65 to 180, a named set 1 to 10 and 15 to 40")
    func theCapIsDividedByExpectedUse() {
        let mail = LadderSet(id: "mail", label: "Mail")
        let budgets = LadderPlan.budgets(cap: 100, sets: [.everything, mail])
        #expect(budgets == ["everything": 84, "mail": 16])
        let everything = LadderPlan.window(after: nil, budget: 84, everything: true)
        #expect(everything == Array(1 ... 60) + Array(stride(from: 65, through: 180, by: 5)))
        let named = LadderPlan.window(after: nil, budget: 16, everything: false)
        #expect(named == Array(1 ... 10) + Array(stride(from: 15, through: 40, by: 5)))
        #expect(LadderPlan.window(after: 180, budget: 3, everything: true) == [185, 190, 195])
        #expect(LadderPlan.budgets(cap: 100, sets: [.everything]) == ["everything": 100])
        let many = (1 ... 6).map { LadderSet(id: "s\($0)", label: "S\($0)") }
        let shared = LadderPlan.budgets(cap: 100, sets: [.everything] + many)
        #expect(shared["s1"] == 8 && shared["everything"] == 52)
    }

    @Test("phase 7: the cap is the largest accepted count of 1, 2, 4, …, 512")
    func theCapMeasurementKeepsTheLargestAcceptedCount() {
        struct Refused: Error {}
        var tried: [Int] = []
        let cap = LadderPlan.measureCap { count in
            tried.append(count)
            if count > 100 {
                throw Refused()
            }
        }
        #expect(cap == 64)
        #expect(tried == [1, 2, 4, 8, 16, 32, 64, 128])
        #expect(LadderPlan.measureCap { _ in } == 512)
    }

    @Test func eventNamesRoundTrip() {
        let name = LadderEventName(setID: "everything", day: "20240314", generation: 2, step: 65)
        #expect(name.text == "everything.20240314.2.65")
        #expect(LadderEventName(name.text) == name)
        #expect(LadderEventName("nonsense") == nil)
    }

    @Test func theFirstRegistrationOfTheDayCountsPastActivity() throws {
        let harness = try LadderHarness()
        try harness.controller.configure()
        let registration = try #require(harness.monitor.all.first)
        #expect(registration.events.count == 100)
        let withPast = registration.events.filter(\.includesPastActivity)
        #expect(withPast.count == 100)
        #expect(registration.events.first?.minutes == 1)
        #expect(registration.events.first?.name == "everything.20240314.0.1")
    }

    @Test func consecutiveMinutesAreCounted() throws {
        let harness = try LadderHarness()
        try harness.controller.configure()
        try harness.at("2024-03-14T10:00:00")
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 1)) == .counted(step: 1))
        try harness.at("2024-03-14T10:01:00")
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 2)) == .counted(step: 2))
        // A repeated callback for a counted step is ignored.
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 2)) == .ignored)
        let lines = try harness.lines()
        #expect(lines.map(\.n) == [1, 2])
        #expect(lines.allSatisfy { !$0.early })
        let event = try #require(harness.staging.readAll().first)
        #expect(event.label == "Everything")
        #expect(event.kind == "minute")
        #expect(event.payload == #"{"n":1}"#)
        #expect(event.utcOffset == -14_400)
    }

    @Test("IOS-28 a callback earlier than its ledger time is logged early, not counted, and re-registered")
    func anEarlyCallbackIsReregistered() throws {
        let harness = try LadderHarness()
        try harness.controller.configure()
        try harness.at("2024-03-14T10:00:00")
        try harness.controller.thresholdReached(harness.name("everything", step: 1))
        let step2 = try harness.name("everything", step: 2)
        let step3 = try harness.name("everything", step: 3)
        try harness.at("2024-03-14T10:00:20")
        #expect(try harness.controller.thresholdReached(step2) == .early(step: 2, reregistered: true))
        // A callback of the replaced registration is logged early but changes nothing more.
        #expect(try harness.controller.thresholdReached(step3) == .early(step: 3, reregistered: false))
        #expect(try harness.lines().map(\.n) == [1, 2, 3])
        #expect(try harness.lines().map(\.early) == [false, true, true])
        #expect(try harness.staging.readAll()[1].payload == #"{"early":true,"n":2}"#)
        // The new generation measures the remaining minutes without past activity.
        let registration = try #require(harness.monitor.all.last)
        #expect(harness.monitor.all.count == 2)
        #expect(registration.events.first?.name == "everything.20240314.1.2")
        #expect(registration.events.first?.minutes == 1)
        #expect(registration.events.first?.includesPastActivity == false)
        #expect(registration.events.first { $0.name.hasSuffix(".65") }?.minutes == 64)
        // The re-registered step counts once its time has come.
        try harness.at("2024-03-14T10:01:30")
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 2)) == .counted(step: 2))
        #expect(harness.state.ladderState(for: "everything")?.countedStep == 2)
    }

    @Test func fiveMinuteStepsWaitFiveMinutes() throws {
        let harness = try LadderHarness(cap: 62)
        try harness.controller.configure()
        var time = try #require(ActivityTimestamp.date("2024-03-14T09:00:00", timeZone: ActivityFixture.newYork))
        for step in 1 ... 60 {
            harness.clock.set(time)
            #expect(try harness.controller.thresholdReached(harness.name("everything", step: step)) == .counted(step: step))
            time += 60
        }
        harness.clock.set(time)
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 65)) == .early(step: 65, reregistered: true))
        harness.clock.set(time + 240)
        #expect(try harness.controller.thresholdReached(harness.name("everything", step: 65)) == .counted(step: 65))
    }

    @Test func theLastStepOfAWindowRegistersTheNext() throws {
        let harness = try LadderHarness(cap: 3)
        try harness.controller.configure()
        for (step, time) in [(1, "10:00:00"), (2, "10:01:00"), (3, "10:02:00")] {
            try harness.at("2024-03-14T" + time)
            try harness.controller.thresholdReached(harness.name("everything", step: step))
        }
        let next = try #require(harness.monitor.all.last)
        #expect(harness.monitor.all.count == 2)
        #expect(next.events.map(\.name) == ["everything.20240314.1.4", "everything.20240314.1.5", "everything.20240314.1.6"])
        #expect(next.events.map(\.minutes) == [1, 2, 3])
    }

    @Test func aNewDayStartsFreshAndOldCallbacksAreIgnored() throws {
        let harness = try LadderHarness()
        try harness.controller.configure()
        let yesterday = try harness.name("everything", step: 1)
        try harness.at("2024-03-15T00:00:00")
        try harness.controller.intervalDidStart(setID: "everything")
        #expect(harness.monitor.all.last?.events.first?.name == "everything.20240315.0.1")
        try harness.at("2024-03-15T00:00:30")
        #expect(try harness.controller.thresholdReached(yesterday) == .ignored)
        #expect(try harness.lines().isEmpty)
    }

    @Test func reconfiguringKeepsTodaysLedgerAndStopsRemovedSets() throws {
        let mail = LadderSet(id: "mail", label: "Mail")
        let harness = try LadderHarness(sets: [.everything, mail])
        try harness.controller.configure()
        try harness.at("2024-03-14T10:00:00")
        try harness.controller.thresholdReached(harness.name("mail", step: 1))
        #expect(try harness.staging.readAll().last?.label == "Mail")
        harness.state.ladderSets = [.everything]
        try harness.controller.configure(removed: ["mail"])
        #expect(harness.monitor.stops == ["mail"])
        #expect(harness.state.ladderState(for: "mail") == nil)
        let everything = try #require(harness.monitor.all.last)
        #expect(everything.setID == "everything")
        #expect(everything.events.first?.name == "everything.20240314.1.1")
        #expect(everything.events.count == 100)
    }

    @Test func nothingIsLoggedWhileCollectionIsOff() throws {
        let harness = try LadderHarness()
        try harness.controller.configure()
        harness.state.isEnabled = false
        try harness.controller.thresholdReached(harness.name("everything", step: 1))
        #expect(try harness.lines().isEmpty)
    }
}
