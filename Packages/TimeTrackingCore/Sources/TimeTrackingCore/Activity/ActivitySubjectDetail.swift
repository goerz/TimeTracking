// ActivitySubjectDetail: a subject's details from the detail log, on the
// recording Mac (spec_planner_activity.md §1.6).

import Foundation

/// The drill-down of one subject.
public struct ActivitySubjectDetail: Sendable, Hashable {
    /// A detail with its seconds.
    public struct Line: Sendable, Hashable, Identifiable {
        public var detail: String
        public var seconds: Int

        public var id: String {
            detail
        }
    }

    public var subject: String
    /// The breadcrumb's first element, the subject's top context.
    public var context: String
    public var lines: [Line]
    /// Visited pages (site) or modified files (folder); `nil` otherwise.
    public var visitedCount: Int?
    public var isSite: Bool
    /// Blocks with a detail record, of all the subject's blocks.
    public var coveredBlocks: Int
    public var totalBlocks: Int

    /// "details for 31 of 34 blocks", or `nil` when every block has one.
    public var coverageText: String? {
        coveredBlocks < totalBlocks ? "details for \(coveredBlocks) of \(totalBlocks) blocks" : nil
    }

    /// "12 visited pages" or "8 modified files".
    public var visitedText: String? {
        visitedCount.map { count in
            isSite ? "\(count) visited \(count == 1 ? "page" : "pages")" : "\(count) modified \(count == 1 ? "file" : "files")"
        }
    }
}

extension ActivitySummary {
    /// The details of `row` from the detail log's complete items, ranked by
    /// seconds; `nil` without detail records or for a private site.
    public func subjectDetail(_ row: ActivitySubjectRow, homeDirectory: String) -> ActivitySubjectDetail? {
        guard let subject = row.subject, row.hasDetails else {
            return nil
        }
        let details = row.blockIDs.compactMap { input.details[$0] }
        var seconds: [String: Int] = [:]
        for detail in details {
            for item in detail.items where item.subject == subject && (input.contexts.isEmpty || input.contexts.contains(item.context)) {
                seconds[item.detail.isEmpty ? "(no detail)" : item.detail, default: 0] += item.seconds
            }
        }
        let isSite = row.contexts.contains { ActivityContext($0).kind == .browser }
        let isFolder = subject.hasPrefix("/") || subject.hasPrefix("~")
        var visited: Int?
        if isSite {
            visited = Set(details.flatMap(\.urls).map(\.url).filter { Self.url($0, isUnder: subject) }).count
        } else if isFolder {
            let prefixes = [subject, subject.hasPrefix("~") ? homeDirectory + subject.dropFirst() : subject]
            visited = Set(details.flatMap(\.files).map(\.path).filter { path in prefixes.contains { path.hasPrefix($0) } }).count
        }
        return ActivitySubjectDetail(
            subject: subject,
            context: row.contexts.first ?? "",
            lines: seconds.map { ActivitySubjectDetail.Line(detail: $0.key, seconds: $0.value) }
                .sorted { ($1.seconds, $0.detail) < ($0.seconds, $1.detail) },
            visitedCount: visited,
            isSite: isSite,
            coveredBlocks: details.count,
            totalBlocks: row.blockIDs.count
        )
    }

    /// Whether `url` lies under the site subject `github.com/owner`.
    static func url(_ url: String, isUnder subject: String) -> Bool {
        var rest = Substring(url)
        if let scheme = rest.range(of: "://") {
            rest = rest[scheme.upperBound...]
        }
        if rest.hasPrefix("www.") {
            rest = rest.dropFirst(4)
        }
        return rest.hasPrefix(subject)
    }
}
