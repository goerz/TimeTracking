// LaunchArguments: the launch arguments and environment every process
// understands (spec_architecture.md §2.5, spec_automation.md §1,
// spec_activity_tracking.md §5).

public import Foundation

/// The parsed launch arguments and test-related environment of a process.
///
/// The apps understand `-UITesting YES`, `-Fixture <name>`, and
/// `-ResetState YES` (the `-Key value` form of `UserDefaults`); the agent
/// understands `--record <folder>`, `--replay <file>`, and `--unregister`,
/// which it hands to the Mac app's own `--unregister`;
/// the tool reads `TIMETRACKING_STORE`, `TIMETRACKING_NOW`, and
/// `TIMETRACKING_BUSY_TIMEOUT`. Unknown
/// arguments are ignored, so the system's own launch arguments pass through.
public struct LaunchArguments: Sendable, Equatable {
    /// `-UITesting YES`: in-memory store and transport, fixture, no animations.
    public var uiTesting: Bool
    /// `-Fixture <name>`: the `Fixtures/Store/<name>.json` to load.
    public var fixture: String?
    /// `-ResetState YES`: forget window frames and other device-local state.
    public var resetState: Bool
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

    public init(
        uiTesting: Bool = false,
        fixture: String? = nil,
        resetState: Bool = false,
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
