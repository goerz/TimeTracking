// LaunchArguments: the launch arguments and environment every process
// understands (spec_architecture.md §2.5, spec_automation.md §1,
// spec_activity_tracking.md §5).

public import Foundation

/// The parsed launch arguments and test-related environment of a process.
///
/// The apps understand `-UITesting YES`, `-Fixture <name>`,
/// `-ResetState YES`, `-CalendarAccess YES`, `-RealAgent YES`, and
/// `-LoginItemLaunch YES` (the `-Key value` form of
/// `UserDefaults`); the agent
/// understands `--record <folder>`, `--replay <file>`, and `--unregister`,
/// which it hands to the Mac app's own `--unregister`;
/// the tool reads `TIMETRACKING_STORE`, `TIMETRACKING_NOW`,
/// `TIMETRACKING_BUSY_TIMEOUT`, `TIMETRACKING_BUSY_MARKER`, and
/// `TIMETRACKING_CHANGE_NOTIFICATION` (the last four in Debug builds). Unknown
/// arguments are ignored, so the system's own launch arguments pass through.
public struct LaunchArguments: Sendable, Equatable {
    /// `-UITesting YES`: in-memory store and transport, fixture, no animations.
    public var uiTesting: Bool
    /// `-Fixture <name>`: the `Fixtures/Store/<name>.json` to load.
    public var fixture: String?
    /// `-ResetState YES`: forget window frames and other device-local state.
    public var resetState: Bool
    /// `-CalendarAccess YES`: under `-UITesting`, the in-memory calendar
    /// store has an iCloud account and grants access, so time blocks work.
    public var calendarAccess: Bool
    /// `-RealAgent YES`: under `-UITesting`, the Mac app registers the real
    /// Debug agent instead of an in-memory one (the ARCH-8 UI tests).
    public var realAgent: Bool
    /// `-LoginItemLaunch YES`: under `-UITesting`, the Mac app launches as
    /// if opened as a login item.
    public var loginItemLaunch: Bool
    /// `--record <folder>` (agent).
    public var recordFolder: URL?
    /// `--replay <file>` (agent).
    public var replayFile: URL?
    /// `--unregister` (agent, and the Mac app on the agent's behalf).
    public var unregister: Bool
    /// `TIMETRACKING_STORE`: the store file to open instead of the default.
    public var storePath: String?
    /// `TIMETRACKING_NOW`, if set and valid. Only Debug builds honor it.
    public var fixedNow: Date?
    /// `TIMETRACKING_BUSY_TIMEOUT` in seconds, if set and valid: the store's
    /// busy timeout, for tests. Only Debug builds honor it.
    public var busyTimeout: TimeInterval?
    /// `TIMETRACKING_BUSY_MARKER`: a file the tool creates when a write
    /// starts waiting for another process's lock (tests). Debug only.
    public var busyMarker: String?
    /// `TIMETRACKING_CHANGE_NOTIFICATION`: the change notification's name
    /// instead of `<APP_ID>.changed`, so a test counts only its own posts.
    /// Debug only.
    public var changeNotificationName: String?

    public init(
        uiTesting: Bool = false,
        fixture: String? = nil,
        resetState: Bool = false,
        calendarAccess: Bool = false,
        realAgent: Bool = false,
        loginItemLaunch: Bool = false,
        recordFolder: URL? = nil,
        replayFile: URL? = nil,
        unregister: Bool = false,
        storePath: String? = nil,
        fixedNow: Date? = nil,
        busyTimeout: TimeInterval? = nil
    ) {
        self.uiTesting = uiTesting
        self.fixture = fixture
        self.resetState = resetState
        self.calendarAccess = calendarAccess
        self.realAgent = realAgent
        self.loginItemLaunch = loginItemLaunch
        self.recordFolder = recordFolder
        self.replayFile = replayFile
        self.unregister = unregister
        self.storePath = storePath
        self.fixedNow = fixedNow
        self.busyTimeout = busyTimeout
    }

    /// Parses `arguments` (including the program name at index 0) and
    /// `environment`. Relative paths resolve against `currentDirectory`.
    public init(
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory),
        timeZone: TimeZone = .current
    ) {
        self.init()
        var index = arguments.startIndex == arguments.endIndex ? arguments.endIndex : arguments.startIndex + 1
        func value(after position: Int) -> String? {
            let next = position + 1
            return next < arguments.endIndex ? arguments[next] : nil
        }
        self.calendarAccess = arguments.firstIndex(of: "-CalendarAccess").map { Self.bool(value(after: $0)) } ?? false
        while index < arguments.endIndex {
            let argument = arguments[index]
            var consumed = 1
            switch argument {
            case "-UITesting":
                self.uiTesting = Self.bool(value(after: index))
                consumed = 2
            case "-Fixture":
                self.fixture = value(after: index)
                consumed = 2
            case "-ResetState":
                self.resetState = Self.bool(value(after: index))
                consumed = 2
            case "-RealAgent":
                self.realAgent = Self.bool(value(after: index))
                consumed = 2
            case "-LoginItemLaunch":
                self.loginItemLaunch = Self.bool(value(after: index))
                consumed = 2
            case "--record":
                self.recordFolder = value(after: index).map { URL(filePath: $0, relativeTo: currentDirectory) }
                consumed = 2
            case "--replay":
                self.replayFile = value(after: index).map { URL(filePath: $0, relativeTo: currentDirectory) }
                consumed = 2
            case "--unregister":
                self.unregister = true
            default:
                break
            }
            index += consumed
        }
        readEnvironment(environment, timeZone: timeZone)
    }

    private mutating func readEnvironment(_ environment: [String: String], timeZone: TimeZone) {
        if let path = environment["TIMETRACKING_STORE"], !path.isEmpty {
            storePath = path
        }
        if let now = environment["TIMETRACKING_NOW"] {
            fixedNow = Self.parseInstant(now, timeZone: timeZone)
        }
        if let seconds = environment["TIMETRACKING_BUSY_TIMEOUT"].flatMap(TimeInterval.init), seconds >= 0 {
            busyTimeout = seconds
        }
        if let path = environment["TIMETRACKING_BUSY_MARKER"], !path.isEmpty {
            busyMarker = path
        }
        if let name = environment["TIMETRACKING_CHANGE_NOTIFICATION"], !name.isEmpty {
            changeNotificationName = name
        }
    }

    /// The arguments of the running process.
    public static var current: Self {
        Self(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    }

    /// The clock for this process: fixed at `fixedNow` when `honorFixedNow`
    /// and `TIMETRACKING_NOW` is set, the system clock otherwise.
    public func clock(honorFixedNow: Bool) -> any Clock {
        if honorFixedNow, let fixedNow {
            return ManualClock(fixedNow)
        }
        return SystemClock()
    }

    /// Parses an ISO 8601 instant: with an offset or `Z`, or without one as
    /// local time in `timeZone`; seconds are optional.
    public static func parseInstant(_ string: String, timeZone: TimeZone = .current) -> Date? {
        let text = string.trimmingCharacters(in: .whitespaces)
        let withOffset = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        if let date = try? withOffset.parse(text) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mmXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }

    /// Reads a `UserDefaults`-style boolean argument value.
    private static func bool(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return ["yes", "true", "1"].contains(value.lowercased())
    }
}
