// ToolContext: opening the store and writing output for one command
// (automation.md §2, §3.1, §3.3, §3.11).

import Darwin
import Foundation
import TimeTrackingCore

/// The store, clock, and output of one tool invocation.
nonisolated struct ToolContext {
    let options: GlobalOptions
    let identity = AppIdentity.main
    let arguments: LaunchArguments

    init(_ options: GlobalOptions) {
        self.options = options
        var arguments = LaunchArguments(arguments: [], environment: ProcessInfo.processInfo.environment)
        if let store = options.store {
            arguments.storePath = store
        }
        self.arguments = arguments
    }

    var timeZone: TimeZone {
        .current
    }

    /// `--store`, then `TIMETRACKING_STORE`, then the App Group store.
    var storeURL: URL? {
        guard case let .file(url) = TimeStore.Location.resolve(arguments: arguments, identity: identity) else {
            return nil
        }
        return url
    }

    /// The context of one subcommand and the service of its store.
    static func open(
        _ options: GlobalOptions,
        writing: Bool,
        csvMessage: String = "Write commands have no CSV form."
    ) async throws(AutomationError) -> (Self, AutomationService) {
        let context = Self(options)
        return try await (context, context.service(writing: writing, csvMessage: csvMessage))
    }

    /// Opens the store (read-only for read commands) and returns its service.
    /// A writing command rejects `--csv` with `csvMessage` before the store
    /// opens, so the usage error writes nothing.
    private func service(writing: Bool, csvMessage: String) async throws(AutomationError) -> AutomationService {
        if writing, options.csv {
            throw .usage(csvMessage)
        }
        guard let url = storeURL else {
            throw .storeUnavailable("No store: the App Group container is unavailable; pass --store.")
        }
        if !writing, !FileManager.default.fileExists(atPath: url.path) {
            throw .storeUnavailable("No store at \(url.path).")
        }
        // TIMETRACKING_NOW and TIMETRACKING_BUSY_TIMEOUT apply in Debug builds only.
        let isDebug = identity?.isDebug ?? false
        let clock = arguments.clock(honorFixedNow: isDebug)
        do {
            let store = try await TimeStore.open(
                arguments: arguments,
                identity: identity,
                deviceID: deviceID(for: url),
                clock: clock,
                readOnly: !writing,
                busyTimeout: isDebug ? arguments.busyTimeout ?? TimeStore.defaultBusyTimeout : TimeStore.defaultBusyTimeout,
                observesOtherProcesses: false,
                onBusy: (isDebug ? arguments.busyMarker : nil).map { marker in
                    { _ = FileManager.default.createFile(atPath: marker, contents: nil) }
                }
            )
            return AutomationService(store: store, timeZone: timeZone)
        } catch {
            throw AutomationError(wrapping: error)
        }
    }

    /// The device's id for the live store (shared with the app); for
    /// another store file one derived from its path, so the tool never
    /// touches the App Group defaults for it.
    private func deviceID(for url: URL) -> DeviceID {
        if let identity, arguments.storePath == nil {
            return DeviceSettings(identity: identity).deviceID
        }
        let namespace = UUID(uuidString: "6F1B7E5A-4C1E-4C4B-9C59-2D1A4C7B8E10") ?? UUID()
        return DeviceID(UUID.version5(namespace: namespace, name: "tool:" + url.standardizedFileURL.path))
    }

    // MARK: Activity and calendars

    /// The activity folders: `TIMETRACKING_ACTIVITY` (one folder holding
    /// `blocks/`, `current.json`, and `settings.toml`), else the shared
    /// folder in iCloud Drive and the local one in the App Group.
    var activityFolders: ActivityFolders? {
        if let path = ProcessInfo.processInfo.environment["TIMETRACKING_ACTIVITY"], !path.isEmpty {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            return ActivityFolders(shared: folder, local: folder, isFallback: true)
        }
        return identity.flatMap { ActivityFolders.resolveWithoutEntitlement(identity: $0) }
    }

    /// The reader of the block log and `current.json`.
    func activityReader() throws(AutomationError) -> FileActivityStore {
        guard let folders = activityFolders else {
            throw .storeUnavailable("No activity folder: the App Group container is unavailable.")
        }
        return FileActivityStore(folders: folders)
    }

    /// EventKit, or in Debug builds the file `TIMETRACKING_CALENDAR`
    /// names; with the identifier the app resolved on this Mac.
    func timeBlockContext() throws(AutomationError) -> TimeBlockContext {
        let scheme = identity?.urlScheme ?? "timetracking"
        if identity?.isDebug ?? false, let path = ProcessInfo.processInfo.environment["TIMETRACKING_CALENDAR"], !path.isEmpty {
            do {
                return try TimeBlockContext(events: FixtureCalendarStore(url: URL(filePath: path)), deviceCalendarID: nil, scheme: scheme)
            } catch {
                throw .failure("Can't read \(path): \(error.localizedDescription)")
            }
        }
        // Another store file has no device state of its own.
        let resolved = arguments.storePath == nil ? DeviceSettings(identity: identity)[.calendarTimeBlockCalendar] : ""
        return TimeBlockContext(events: EventKitCalendarStore(), deviceCalendarID: resolved.isEmpty ? nil : resolved, scheme: scheme)
    }

    // MARK: Output

    /// Whether to write ANSI colors: stdout is a terminal, and neither
    /// `--no-color` nor `NO_COLOR` is set.
    var colors: Bool {
        !options.noColor && ProcessInfo.processInfo.environment["NO_COLOR"] == nil && isatty(STDOUT_FILENO) != 0
    }

    /// Writes `text` to stdout like `ToolContext.write(_:)`, except that an
    /// empty text writes nothing.
    func write(_ text: String) {
        if !text.isEmpty {
            Self.write(text)
        }
    }

    /// The output of a read command: JSON, CSV, or the table.
    func emit(json: () -> JSONValue, csv: (() -> String)? = nil, text: () -> String) throws(AutomationError) {
        if options.json {
            write(json().text())
        } else if options.csv {
            guard let csv else {
                throw .usage("This command has no CSV form.")
            }
            write(csv())
        } else {
            write(text())
        }
    }

    /// The output of a write command: the changed record with `--json`,
    /// else the line; nothing with `--quiet`. Opening the store for writing
    /// has already rejected `--csv`.
    func changed(_ line: String, json: () -> JSONValue) {
        guard !options.quiet else {
            return
        }
        write(options.json ? json().text() : line)
    }

    /// Writes an error to stderr as `error: …`, or as JSON with `--json`.
    static func report(_ error: AutomationError, json: Bool) {
        let text = json ? AutomationRecords.error(error).text(pretty: false) : "error: " + error.message
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// Writes `text` to stdout, adding a newline unless it ends with one;
    /// help and other clean-exit messages go here, an empty one as a newline.
    static func write(_ text: String) {
        print(text, terminator: text.hasSuffix("\n") ? "" : "\n")
    }

    /// Writes `text` to stderr, adding a newline unless it ends with one.
    static func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
    }
}
