// CollectionLog: what every iOS collector calls to append a line to the
// collection file (ios.md §9.1, §9.3 to §9.5, §9.7).

public import Foundation

/// Appends `DeviceEvent` lines for this device through a sink, with the
/// rules every collector shares: nothing is logged while the master switch
/// is off, and the Safari and automation collectors are silent while a
/// Focus that suspends collection is on. Collectors never map events to
/// projects; exclusions are applied before a line is written.
public struct CollectionLog: Sendable {
    /// The label of the app's own lines.
    public static let appLabel = "TimeTracking"

    public let state: CollectionSharedState
    public let sink: any DeviceEventSink
    public let deviceID: String
    public let clock: any Clock
    public let timeZone: TimeZone

    public init(
        state: CollectionSharedState,
        sink: any DeviceEventSink,
        deviceID: String,
        clock: any Clock,
        timeZone: TimeZone = .current
    ) {
        self.state = state
        self.sink = sink
        self.deviceID = deviceID
        self.clock = clock
        self.timeZone = timeZone
    }

    /// The collection folder of `identity`'s App Group: `Activity/` in the
    /// support directory (data_and_sync.md §6). Never touches iCloud.
    public static func folder(identity: AppIdentity) -> URL? {
        identity.groupContainerURL.map { identity.supportDirectory(in: $0).appending(path: "Activity", directoryHint: .isDirectory) }
    }

    /// The log an extension uses: the App Group's staging file, which it
    /// only appends to.
    public static func extensionLog(identity: AppIdentity?, clock: any Clock = SystemClock()) -> Self? {
        guard let identity, let folder = folder(identity: identity) else {
            return nil
        }
        return Self(
            state: CollectionSharedState(identity: identity),
            sink: DeviceEventStagingFile(folder: folder),
            deviceID: DeviceSettings(identity: identity).deviceID.rawValue,
            clock: clock
        )
    }

    /// The exclusions of the App Group copy of `settings.toml` in `folder`
    /// (the defaults when it is missing or unreadable).
    public static func exclusions(folder: URL) -> ExclusionRules {
        let url = folder.appending(path: "settings.toml", directoryHint: .notDirectory)
        return ((try? TrackerSettings(contentsOf: url)) ?? .defaults).exclusions()
    }

    // MARK: Appending

    /// Whether `source` may log now.
    public func isCollecting(_ source: DeviceEvent.Source) -> Bool {
        guard state.isEnabled else {
            return false
        }
        switch source {
        case .webext, .intent:
            return !state.focusSuspendsCollection
        case .ladder, .focus, .app:
            return true
        }
    }

    /// Appends one line when `source` is collecting; returns whether it did.
    @discardableResult
    public func append(
        _ source: DeviceEvent.Source,
        label: String,
        kind: String,
        payload: String? = nil,
        at time: Date? = nil
    ) throws -> Bool {
        guard isCollecting(source) else {
            return false
        }
        let time = time ?? clock.now
        try sink.append(DeviceEvent(
            deviceID: deviceID,
            time: time,
            source: source,
            label: label,
            kind: kind,
            payload: payload,
            utcOffset: timeZone.secondsFromGMT(for: time)
        ))
        return true
    }

    /// `LogActivityEventIntent` (§9.4).
    @discardableResult
    public func logIntent(label: String, kind: ActivityEventKind) throws -> Bool {
        let logged = try append(.intent, label: label, kind: kind.rawValue)
        if logged {
            state.lastIntentEventAt = clock.now
        }
        return logged
    }

    /// A message of the Safari extension (§9.5): the reduced URL as a `tab` line.
    @discardableResult
    public func logWeb(url: String, at time: Date?, exclusions: ExclusionRules) throws -> Bool {
        state.lastWebEventAt = clock.now
        guard let label = WebEventReducer.label(for: url, exclusions: exclusions) else {
            return false
        }
        return try append(.webext, label: label, kind: "tab", at: time)
    }

    /// The app's own foreground and background transitions (§9.7).
    @discardableResult
    public func logApp(foreground: Bool) throws -> Bool {
        try append(.app, label: Self.appLabel, kind: foreground ? "foreground" : "background")
    }

    /// The Focus filter (§9.3): performed with a label when a Focus turns
    /// on, and with the default parameters (no label) when it ends. An `on`
    /// for another label first ends the one that is on; the `off` carries
    /// the label last logged. `collect` false suspends the Safari and
    /// automation collectors until the `off` (the `on` line says so in its
    /// payload, so the Mac closes the block there).
    @discardableResult
    public func focusFilterPerformed(label: String?, collect: Bool) throws -> [String] {
        state.lastFocusEventAt = clock.now
        let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let current = state.focusLabel
        var logged: [String] = []
        if let current, current != label {
            if try append(.focus, label: current, kind: "off") {
                logged.append("off")
            }
            state.focusLabel = nil
            state.focusSuspendsCollection = false
        }
        guard !label.isEmpty else {
            return logged
        }
        if current != label {
            let payload = collect ? nil : DeviceEvent.payloadText(["collect": false])
            if try append(.focus, label: label, kind: "on", payload: payload) {
                logged.append("on")
            }
        }
        state.focusLabel = label
        state.focusSuspendsCollection = !collect
        return logged
    }
}
