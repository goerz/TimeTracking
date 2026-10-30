// Task autocompletion of the task field (spec_timer_window.md §2.2).

import Foundation
import GRDB

extension TimeStore {
    /// Up to `limit` distinct (task, project) pairs whose task contains
    /// `text` (case- and diacritic-insensitive): pairs of `preferredProject`
    /// first, then the most recently used. Archived and deleted projects are
    /// skipped; each pair carries its most recent spelling.
    public func taskCompletions(containing text: String, preferredProject: ProjectID?, limit: Int = 8) throws -> [TaskSuggestion] {
        let needle = text.folded
        guard !needle.isEmpty, limit > 0 else {
            return []
        }
        let pattern = "%" + Self.escapeLike(needle) + "%"
        return try read { database in
            try Row.fetchAll(
                database,
                sql: """
                SELECT e.task_key, e.project_id, MAX(e.start) AS last_used, COUNT(*) AS uses,
                  (SELECT task FROM time_entry t WHERE t.task_key = e.task_key AND t.deleted_at IS NULL
                     AND t.project_id IS e.project_id ORDER BY t.start DESC LIMIT 1) AS task
                FROM time_entry e LEFT JOIN project p ON p.id = e.project_id
                WHERE e.deleted_at IS NULL AND e.task_key != '' AND e.task_key LIKE ? ESCAPE '\\'
                  AND (e.project_id IS NULL OR (p.id IS NOT NULL AND p.archived = 0 AND p.deleted_at IS NULL))
                GROUP BY e.task_key, e.project_id
                ORDER BY (e.project_id IS ?) DESC, last_used DESC, e.task_key
                LIMIT ?
                """,
                arguments: [pattern, preferredProject?.rawValue, limit]
            ).map { row in
                TaskSuggestion(
                    task: row["task"],
                    projectID: row.uuid("project_id"),
                    lastUsed: Time.date(row["last_used"] as Int64),
                    useCount: row["uses"]
                )
            }
        }
    }
}
