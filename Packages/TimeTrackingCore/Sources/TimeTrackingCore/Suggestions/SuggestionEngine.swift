// SuggestionEngine: builds and keeps the index, throttles rebuilds, and
// spares the launch rebuild with a cache file (spec_calendar.md §5.5).

public import Foundation
import GRDB
import os

/// The in-memory index with its rebuild policy.
public actor SuggestionEngine {
    /// Rebuilds after entry changes happen at most this often.
    public static let rebuildInterval: TimeInterval = 300
    private static let logger = Logging.logger(category: "Suggestions")

    private let store: TimeStore
    private let activity: any ActivityReading
    private let timeZone: TimeZone
    private let cacheURL: URL?
    public private(set) var index = SuggestionIndex(examples: [])
    private var builtAt: Date?

    /// `cacheURL` is a file in the app's support folder, or `nil` for none.
    public init(store: TimeStore, activity: any ActivityReading, timeZone: TimeZone = .current, cacheURL: URL? = nil) {
        self.store = store
        self.activity = activity
        self.timeZone = timeZone
        self.cacheURL = cacheURL
    }

    /// The cache's key: the newest entry's `modifiedAt` and the newest block's end.
    public func cacheKey() async throws -> String {
        let now = store.clock.now
        let modified = try await store.newestEntryModification()
        let blocks = try await activity.blocks(in: DateInterval(start: now - 7 * 86_400, end: now + 86_400), devices: nil)
        let newestBlock = blocks.filter { !$0.isOpen }.map(\.end).max()
        return "\(modified?.timeIntervalSince1970 ?? 0)|\(newestBlock?.timeIntervalSince1970 ?? 0)"
    }

    /// At launch: the cached index when its key matches, else a rebuild.
    public func load(titles: [SuggestionCalendarTitle]) async {
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data),
           let key = try? await cacheKey(), cache.key == key
        {
            index = cache.index
            builtAt = store.clock.now
            return
        }
        await rebuild(titles: titles)
    }

    /// "Relearn Suggestions", a changed month file, and the daily rebuild.
    public func rebuild(titles: [SuggestionCalendarTitle]) async {
        do {
            let now = store.clock.now
            let trainDays = try await store.value(.trainDays)
            let window = DateInterval(start: now - Double(trainDays) * 86_400, end: now)
            let entries = try await store.entries(in: window, includeDeleted: false)
            let blocks = try await activity.blocks(in: window, devices: nil)
            let feedback = try await store.feedback(in: DateInterval(start: window.start, end: now + 1))
            let examples = SuggestionTraining.examples(
                entries: entries,
                blocks: blocks,
                titles: titles,
                feedback: feedback,
                now: now,
                trainDays: trainDays,
                timeZone: timeZone
            )
            index = SuggestionIndex(examples: examples)
            builtAt = now
            try await writeCache()
        } catch {
            Self.logger.error("Suggestions index: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After entry changes: rebuilds at most every five minutes; returns
    /// whether it rebuilt now.
    @discardableResult
    public func entriesChanged(titles: [SuggestionCalendarTitle]) async -> Bool {
        let now = store.clock.now
        if let builtAt, now.timeIntervalSince(builtAt) < Self.rebuildInterval {
            return false
        }
        await rebuild(titles: titles)
        return true
    }

    public func suggest(_ query: SuggestionQuery, rules: [SuggestionRule]) -> [SuggestionCandidate] {
        index.suggest(query, rules: rules)
    }

    private func writeCache() async throws {
        guard let cacheURL else {
            return
        }
        let key = try await cacheKey()
        let data = try JSONEncoder().encode(Cache(key: key, index: index))
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
    }

    private struct Cache: Codable {
        var key: String
        var index: SuggestionIndex
    }
}

extension TimeStore {
    /// The newest `modifiedAt` of any entry, deleted ones included.
    public func newestEntryModification() throws -> Date? {
        try read { database in
            try Int64.fetchOne(database, sql: "SELECT MAX(modified_at) FROM time_entry")
                .map { Date(timeIntervalSince1970: Double($0) / 1000) }
        }
    }
}
