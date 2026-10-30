// Import options and report (spec_data_and_sync.md §5.2).

import Foundation

/// How `importDocument(_:options:)` treats a document.
public struct ImportOptions: Hashable, Sendable {
    /// Applies the document's `settings`.
    public var includeSettings: Bool
    /// Validates and counts, then rolls back.
    public var dryRun: Bool
    /// The zone of entries without `timeZone`; the device's zone when `nil`.
    public var defaultTimeZone: String?

    public init(includeSettings: Bool = false, dryRun: Bool = false, defaultTimeZone: String? = nil) {
        self.includeSettings = includeSettings
        self.dryRun = dryRun
        self.defaultTimeZone = defaultTimeZone
    }
}

/// The record kinds an import counts.
public enum ImportEntity: String, Sendable, CaseIterable, Codable {
    case client
    case area
    case project
    case entry
    case setting
}

/// What an import did to one kind of record.
public struct ImportCounts: Hashable, Sendable, Codable {
    public var created = 0
    public var updated = 0
    public var unchanged = 0
    /// Local tombstones the document would have overwritten.
    public var skippedDeleted = 0

    public init(created: Int = 0, updated: Int = 0, unchanged: Int = 0, skippedDeleted: Int = 0) {
        self.created = created
        self.updated = updated
        self.unchanged = unchanged
        self.skippedDeleted = skippedDeleted
    }
}

/// The result of an import.
public struct ImportReport: Hashable, Sendable {
    public var counts: [ImportEntity: ImportCounts]
    /// Pieces created by the midnight split.
    public var splitPieces: Int
    /// What the invariant pass changed.
    public var adjustments: [EntryAdjustment]

    public init(counts: [ImportEntity: ImportCounts] = [:], splitPieces: Int = 0, adjustments: [EntryAdjustment] = []) {
        self.counts = counts
        self.splitPieces = splitPieces
        self.adjustments = adjustments
    }

    public subscript(entity: ImportEntity) -> ImportCounts {
        counts[entity] ?? ImportCounts()
    }

    /// True when the import created or updated nothing.
    public var isNoOp: Bool {
        counts.values.allSatisfy { $0.created == 0 && $0.updated == 0 } && splitPieces == 0
    }
}
