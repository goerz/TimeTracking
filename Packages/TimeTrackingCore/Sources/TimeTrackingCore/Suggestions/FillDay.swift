// FillDay: proposals for a day's untracked activity, and logging them in
// one transaction (spec_planner_calendar.md §3.5).

public import Foundation

/// One row of the Fill Day review sheet.
public struct FillDayProposal: Sendable, Hashable, Identifiable {
    public var interval: DateInterval
    /// The blocks the row came from.
    public var blocks: [ActivityBlock]
    public var query: SuggestionQuery
    public var candidates: [SuggestionCandidate]

    public var id: Date {
        interval.start
    }

    public var top: SuggestionCandidate? {
        candidates.first
    }

    /// Rows below `suggestMin` start unchecked and empty.
    public var startsChecked: Bool {
        top?.isConfident ?? false
    }

    /// The items of the blocks in log order (the tooltip).
    public var items: [ActivityItem] {
        blocks.flatMap(\.items)
    }

    /// "tmux:paper 71%" of the first block, plus "+2" for more blocks.
    public var summary: String {
        guard let first = blocks.first else {
            return ""
        }
        let text = "\(first.groupKey) \(Int((first.groupShare * 100).rounded()))%"
        return blocks.count > 1 ? "\(text) +\(blocks.count - 1)" : text
    }
}

/// The Fill Day algorithm.
public enum FillDay {
    /// Neighbors with the same top project and task merge across gaps of this.
    public static let mergeGap: TimeInterval = 300
    /// A segment skipped within this many days is not proposed again that day.
    public static let skipMemoryDays = 30

    /// What Fill Day queries with.
    public struct Context: Sendable {
        public var index: SuggestionIndex
        public var rules: [SuggestionRule]
        public var titles: [SuggestionCalendarTitle]
        /// Recent feedback (skipped segments are not proposed again).
        public var feedback: [SuggestionFeedback]
        public var fillMinMinutes: Int
        public var now: Date
        public var timeZone: TimeZone

        public init(
            index: SuggestionIndex,
            rules: [SuggestionRule],
            titles: [SuggestionCalendarTitle],
            feedback: [SuggestionFeedback],
            fillMinMinutes: Int,
            now: Date,
            timeZone: TimeZone
        ) {
            self.index = index
            self.rules = rules
            self.titles = titles
            self.feedback = feedback
            self.fillMinMinutes = fillMinMinutes
            self.now = now
            self.timeZone = timeZone
        }
    }

    /// Subtracts tracked intervals from the day's closed blocks, keeps
    /// segments of at least `fillMinMinutes`, drops blocks emptied by ignore
    /// rules and segments skipped recently, queries the index, and merges
    /// neighbors with the same top project and task.
    public static func proposals(
        day: DateInterval,
        blocks: [ActivityBlock],
        entries: [DateInterval],
        context: Context
    ) -> [FillDayProposal] {
        var segments: [FillDayProposal] = []
        for block in blocks where !block.isOpen && block.end > day.start && block.start < day.end {
            let probe = SuggestionQuery(
                blocks: [block],
                interval: DateInterval(start: block.start, end: block.end),
                timeZone: context.timeZone
            )
            guard !probe.applying(context.rules).parts.isEmpty else {
                continue
            }
            let start = max(block.start, day.start)
            let clipped = DateInterval(start: start, end: max(start, min(block.end, day.end, context.now)))
            for segment in CalendarCoverage.uncovered(clipped, by: entries) where segment.duration >= Double(context.fillMinMinutes * 60) {
                if !wasSkipped(segment, feedback: context.feedback, now: context.now) {
                    segments.append(proposal(segment, blocks: [block], context: context))
                }
            }
        }
        return merged(segments.sorted { $0.interval.start < $1.interval.start }, context: context)
    }

    static func proposal(_ interval: DateInterval, blocks: [ActivityBlock], context: Context) -> FillDayProposal {
        let query = SuggestionQuery(
            blocks: blocks,
            interval: interval,
            calendarTitle: SuggestionCalendarTitle.covering(interval, in: context.titles),
            timeZone: context.timeZone
        )
        return FillDayProposal(
            interval: interval,
            blocks: blocks,
            query: query,
            candidates: context.index.suggest(query, rules: context.rules)
        )
    }

    private static func merged(_ rows: [FillDayProposal], context: Context) -> [FillDayProposal] {
        var result: [FillDayProposal] = []
        for row in rows {
            if let last = result.last, let top = last.top, let next = row.top, top.projectID == next.projectID,
               SuggestionExample.taskKey(top.task ?? "") == SuggestionExample.taskKey(next.task ?? ""),
               row.interval.start.timeIntervalSince(last.interval.end) <= mergeGap
            {
                var blocks = last.blocks
                blocks += row.blocks.filter { block in !blocks.contains { $0.id == block.id } }
                let interval = DateInterval(start: last.interval.start, end: max(last.interval.end, row.interval.end))
                result[result.count - 1] = proposal(interval, blocks: blocks, context: context)
            } else {
                result.append(row)
            }
        }
        return result
    }

    /// Whether `segment` was skipped from Fill Day within 30 days.
    static func wasSkipped(_ segment: DateInterval, feedback: [SuggestionFeedback], now: Date) -> Bool {
        let since = now - Double(skipMemoryDays) * 86_400
        return feedback.contains { record in
            guard record.source == .fill, record.outcome == .skipped, record.deletedAt == nil, record.recordedAt >= since else {
                return false
            }
            let overlap = segment.overlapDuration(start: record.queryStart, end: record.queryEnd)
            return overlap * 2 >= segment.duration
        }
    }
}

extension SuggestionFeedback {
    /// The record of a decision on a proposal: `accepted` when the chosen
    /// project and task equal the top candidate, else `edited`.
    public static func decision( // swiftlint:disable:this function_parameter_count
        query: SuggestionQuery,
        source: Source,
        block: ActivityBlock?,
        top: SuggestionCandidate?,
        chosenProject: ProjectID?,
        chosenTask: String,
        entryID: EntryID?,
        now: Date
    ) -> Self {
        let accepted = top
            .map { $0.projectID == chosenProject && SuggestionExample.taskKey($0.task ?? "") == SuggestionExample.taskKey(chosenTask) }
            ?? false
        return SuggestionFeedback(
            recordedAt: now,
            queryStart: query.interval.start,
            queryEnd: query.interval.end,
            queryItems: query.itemCount,
            source: source,
            blockStart: block?.start,
            blockDevice: block?.device,
            proposedProjectID: top?.projectID,
            proposedTask: top?.task ?? "",
            confidence: top?.confidence ?? 0,
            outcome: accepted ? .accepted : .edited,
            chosenProjectID: accepted ? nil : chosenProject,
            chosenTask: accepted ? nil : chosenTask,
            entryID: entryID
        )
    }

    /// The record of a skipped proposal.
    public static func skipped(
        query: SuggestionQuery,
        source: Source,
        block: ActivityBlock?,
        top: SuggestionCandidate?,
        now: Date
    ) -> Self {
        SuggestionFeedback(
            recordedAt: now,
            queryStart: query.interval.start,
            queryEnd: query.interval.end,
            queryItems: query.itemCount,
            source: source,
            blockStart: block?.start,
            blockDevice: block?.device,
            proposedProjectID: top?.projectID,
            proposedTask: top?.task ?? "",
            confidence: top?.confidence ?? 0,
            outcome: .skipped
        )
    }
}

/// A checked Fill Day row as the user left it.
public struct FillDayChoice: Sendable, Hashable {
    public var proposal: FillDayProposal
    public var projectID: ProjectID?
    public var task: String

    public init(proposal: FillDayProposal, projectID: ProjectID?, task: String) {
        self.proposal = proposal
        self.projectID = projectID
        self.task = task
    }
}

extension TimeStore {
    /// Creates one checked row and records its feedback.
    private static func log(_ choice: FillDayChoice, in transaction: StoreTransaction, now: Date) throws -> [TimeEntry] {
        let proposal = choice.proposal
        let pieces = try transaction.create(EntryDraft(
            projectID: choice.projectID,
            task: choice.task.trimmed,
            start: proposal.interval.start,
            end: proposal.interval.end
        ))
        try transaction.recordSuggestionFeedback(.decision(
            query: proposal.query,
            source: .fill,
            block: proposal.blocks.first,
            top: proposal.top,
            chosenProject: choice.projectID,
            chosenTask: choice.task,
            entryID: pieces.first?.id,
            now: now
        ))
        return pieces
    }

    /// Creates the checked rows and records feedback for every row
    /// (`skipped` for unchecked and removed ones) in one transaction.
    /// Returns the created entries.
    public func logFillDay(checked: [FillDayChoice], skipped: [FillDayProposal]) throws -> [TimeEntry] {
        let now = clock.now
        return try transaction { transaction in
            var created: [TimeEntry] = []
            for choice in checked {
                created += try Self.log(choice, in: transaction, now: now)
            }
            for proposal in skipped {
                try transaction.recordSuggestionFeedback(.skipped(
                    query: proposal.query,
                    source: .fill,
                    block: proposal.blocks.first,
                    top: proposal.top,
                    now: now
                ))
            }
            return created
        }
    }
}

/// The Suggestions sheet's feedback report (§5.5).
public struct SuggestionFeedbackReport: Sendable, Hashable {
    public var accepted: Int
    public var edited: Int
    public var skipped: Int

    public init(_ feedback: [SuggestionFeedback]) {
        self.accepted = feedback.filter { $0.outcome == .accepted }.count
        self.edited = feedback.filter { $0.outcome == .edited }.count
        self.skipped = feedback.filter { $0.outcome == .skipped }.count
    }

    /// Accepted top candidates of all decisions, 0 to 1.
    public var acceptanceRate: Double {
        let total = accepted + edited + skipped
        return total == 0 ? 0 : Double(accepted) / Double(total)
    }
}
