// Candidates and confidence from the neighbors' votes (spec_calendar.md §5.4).

import Foundation

extension SuggestionIndex {
    /// The votes of `neighbors` (index, distance) as ranked candidates.
    func candidates(_ neighbors: [(Int, Double)], query: QueryVectors) -> [SuggestionCandidate] {
        var projectVotes: [ProjectID?: Double] = [:]
        var taskVotes: [ProjectID?: [String: Double]] = [:]
        var taskText: [String: (String, Date)] = [:]
        var closest: [LabelKey: Int] = [:]
        for (index, distance) in neighbors {
            let example = examples[index]
            let vote = example.weight / (distance + 0.05)
            let key = SuggestionExample.taskKey(example.task)
            projectVotes[example.projectID, default: 0] += vote
            taskVotes[example.projectID, default: [:]][key, default: 0] += vote
            if example.features.start > taskText[key]?.1 ?? .distantPast {
                taskText[key] = (example.task, example.features.start)
            }
            for label in [LabelKey(project: example.projectID, task: key), LabelKey(project: example.projectID, task: nil)]
                where closest[label] == nil
            {
                closest[label] = index
            }
        }
        let total = projectVotes.values.reduce(0, +)
        guard total > 0 else {
            return []
        }
        var result: [SuggestionCandidate] = []
        for (project, votes) in projectVotes {
            let projectShare = votes / total
            let tasks = (taskVotes[project] ?? [:]).sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            let bestShare = (tasks.first?.value ?? 0) / votes
            if bestShare < 0.5 {
                let reasons = closest[LabelKey(project: project, task: nil)].map { reasons(query, example: $0) } ?? []
                result.append(SuggestionCandidate(projectID: project, task: nil, confidence: 0.6 * projectShare, reasons: reasons))
            }
            for (key, taskVote) in tasks {
                let reasons = closest[LabelKey(project: project, task: key)].map { reasons(query, example: $0) } ?? []
                let task = taskText[key]?.0 ?? key
                result.append(SuggestionCandidate(
                    projectID: project,
                    task: task.isEmpty ? nil : task,
                    confidence: 0.6 * projectShare + 0.4 * taskVote / votes,
                    reasons: reasons
                ))
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return (lhs.projectID?.rawValue ?? "", lhs.task ?? "") < (rhs.projectID?.rawValue ?? "", rhs.task ?? "")
        }
        .reduce(into: [SuggestionCandidate]()) { list, candidate in
            if !list.contains(where: { $0.projectID == candidate.projectID && $0.task == candidate.task }) {
                list.append(candidate)
            }
        }
        .prefix(5)
        .map(\.self)
    }

    /// Matched group keys, tokens, and contexts, and the hour, weekday, and
    /// title matches between the query and one example.
    private func reasons(_ query: QueryVectors, example index: Int) -> [SuggestionReason] {
        let example = examples[index].features
        var reasons: [SuggestionReason] = query.features.groupKeys.keys.filter { example.groupKeys[$0] != nil }.sorted()
            .map { .groupKey($0) }
        let shared = query.tokens.filter { !$0.key.hasPrefix("g:") && example.tokens[$0.key] != nil }
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(3)
        reasons += shared.map { .token($0.key) }
        reasons += query.features.contexts.intersection(example.contexts).sorted().map { .context($0) }
        if cyclicDistance(query.features.hour, example.hour) < 0.2 {
            reasons.append(.hour)
        }
        if cyclicDistance(query.features.weekday, example.weekday) < 0.2 {
            reasons.append(.weekday)
        }
        if !query.features.titleTokens.isDisjoint(with: example.titleTokens) {
            reasons.append(.title)
        }
        return reasons
    }
}

/// A (project, task) label; `nil` task means the project alone.
struct LabelKey: Hashable {
    var project: ProjectID?
    var task: String?
}
