// SuggestionIndex: the weighted nearest-neighbor model with the rules in
// front (spec_planner_calendar.md §5.3, §5.4).

import Foundation

/// One past entry as the model sees it (§5.1).
public struct SuggestionExample: Sendable, Hashable, Codable {
    public var entryID: EntryID?
    public var projectID: ProjectID?
    /// The task as last written.
    public var task: String
    public var features: SuggestionFeatures
    /// 2 for examples from accepted suggestions, else 1.
    public var weight: Double

    public init(entryID: EntryID?, projectID: ProjectID?, task: String, features: SuggestionFeatures, weight: Double) {
        self.entryID = entryID
        self.projectID = projectID
        self.task = task
        self.features = features
        self.weight = weight
    }

    /// The label's task: trimmed, case-folded, inner white space collapsed.
    public static func taskKey(_ task: String) -> String {
        task.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The model: examples, token document frequencies, and normalized vectors.
public struct SuggestionIndex: Sendable, Codable {
    /// k of k-nearest-neighbors.
    public static let neighborCount = 9
    /// Below this many examples the model answers nothing.
    public static let minimumExamples = 5
    /// The distance weights of §5.3, pinned by the fixtures.
    public static let weights = (
        groupKeys: 0.30,
        tokens: 0.25,
        contexts: 0.10,
        hour: 0.10,
        title: 0.10,
        weekday: 0.05,
        previous: 0.05,
        recency: 0.05
    )

    public private(set) var examples: [SuggestionExample]
    private var documentFrequency: [String: Int]
    private var tokenVectors: [[String: Double]]
    private var groupVectors: [[String: Double]]

    public init(examples: [SuggestionExample]) {
        self.examples = examples
        var frequency: [String: Int] = [:]
        for example in examples {
            for token in example.features.tokens.keys {
                frequency[token, default: 0] += 1
            }
        }
        self.documentFrequency = frequency
        self.tokenVectors = []
        self.groupVectors = []
        self.tokenVectors = examples.map { normalized($0.features.tokens) }
        self.groupVectors = examples.map { groupVector($0.features.groupKeys) }
    }

    public var count: Int {
        examples.count
    }

    private func idf(_ token: String) -> Double {
        log(Double(examples.count + 1) / Double((documentFrequency[token] ?? 0) + 1))
    }

    /// Seconds × idf, scaled to sum 1 (so long and short stretches compare).
    private func normalized(_ vector: [String: Double]) -> [String: Double] {
        let weighted = vector.mapValues { $0 }.reduce(into: [String: Double]()) { $0[$1.key] = $1.value * idf($1.key) }
        let total = weighted.values.reduce(0, +)
        return total > 0 ? weighted.filter { $0.value > 0 }.mapValues { $0 / total } : [:]
    }

    private func groupVector(_ groups: [String: Double]) -> [String: Double] {
        let weighted = groups
            .reduce(into: [String: Double]()) { $0[$1.key] = $1.value * max(idf(SuggestionTokens.groupToken($1.key)), 0.01) }
        let total = weighted.values.reduce(0, +)
        return total > 0 ? weighted.mapValues { $0 / total } : [:]
    }

    /// The composite distance in [0, 1] of the query to example `index`.
    func distance(_ query: QueryVectors, to index: Int) -> Double {
        let example = examples[index].features
        let weights = Self.weights
        let previous = query.features.previousKnown && example.previousKnown
            ? (query.features.previousProject == example.previousProject ? 0.0 : 1.0) : 0.5
        let days = max(0, query.features.start.timeIntervalSince(example.start) / 86_400)
        let titleDistance: Double = switch (query.features.titleTokens.isEmpty, example.titleTokens.isEmpty) {
        case (true, true): 0
        case (false, false): jaccardDistance(query.features.titleTokens, example.titleTokens)
        default: 0.5
        }
        var total = weights.groupKeys * weightedJaccardDistance(query.groups, groupVectors[index])
        total += weights.tokens * weightedJaccardDistance(query.tokens, tokenVectors[index])
        total += weights.contexts * jaccardDistance(query.features.contexts, example.contexts)
        total += weights.hour * cyclicDistance(query.features.hour, example.hour)
        total += weights.title * titleDistance
        total += weights.weekday * cyclicDistance(query.features.weekday, example.weekday)
        total += weights.previous * previous
        total += weights.recency * (1 - exp(-log(2.0) * days / 60))
        return total
    }

    /// A query's normalized vectors.
    struct QueryVectors {
        var features: SuggestionFeatures
        var tokens: [String: Double]
        var groups: [String: Double]
    }

    /// Up to five candidates, best first; a matching project rule comes
    /// first at confidence 1.0; nothing below five examples but a rule.
    public func suggest(_ query: SuggestionQuery, rules: [SuggestionRule] = []) -> [SuggestionCandidate] {
        let query = query.applying(rules)
        let features = query.features
        let vectors = QueryVectors(features: features, tokens: normalized(features.tokens), groups: groupVector(features.groupKeys))
        var model: [SuggestionCandidate] = []
        if examples.count >= Self.minimumExamples {
            var neighbors: [(Int, Double)] = examples.indices.map { index in (index, distance(vectors, to: index)) }
            neighbors.sort { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 < rhs.1 }
            model = candidates(Array(neighbors.prefix(Self.neighborCount)), query: vectors)
        }
        guard let rule = Self.matchingRule(rules, query: query, features: features), let project = rule.projectID else {
            return Array(model.prefix(5))
        }
        let task = rule.task ?? model.first { $0.projectID == project && $0.task != nil }?.task
        let top = SuggestionCandidate(projectID: project, task: task, confidence: 1, reasons: [.rule])
        return [top] + model.filter { $0.projectID != project }.prefix(4)
    }

    /// The first project rule matching the dominant group key, context,
    /// subject, or a title keyword, in that order.
    static func matchingRule(_ rules: [SuggestionRule], query: SuggestionQuery, features: SuggestionFeatures) -> SuggestionRule? {
        let projectRules = rules.filter { !$0.ignore && $0.projectID != nil }
        let group = features.groupKeys.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        let items = query.parts.flatMap { part in part.items.map { (part.groupKey, $0) } }
        let context = Dictionary(grouping: items, by: \.1.context).mapValues { $0.reduce(0) { $0 + $1.1.seconds } }
            .max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        let dominant = items.max { ($0.1.seconds, $1.1.subject) < ($1.1.seconds, $0.1.subject) }
        for kind in SuggestionRule.Kind.allCases {
            for rule in projectRules where rule.kind == kind {
                let matched = switch kind {
                case .groupKey: group == rule.pattern
                case .context: context == rule.pattern
                case .subjectPrefix: dominant.map { rule.matches($0.1, groupKey: $0.0) } ?? false
                case .titleKeyword: rule.matches(titleTokens: features.titleTokens)
                }
                if matched {
                    return rule
                }
            }
        }
        return nil
    }
}
