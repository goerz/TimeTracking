// EntryFilter+Listing: one listed entry against the Filters and the search
// of Reports, for the Calendar, which loads its entries by day
// (spec_calendar.md §1.6; spec_reports.md §3).

extension EntryFilter {
    /// Whether `listing` passes the filter's clients, areas, projects,
    /// "No project", archived exclusion, and search, as a report would.
    public func admits(_ listing: EntryListing) -> Bool {
        let project = listing.project.map { project in
            ReportProject(
                id: project.id,
                name: project.name,
                archived: project.isArchived,
                areaID: listing.area?.id ?? project.areaID,
                areaName: listing.area?.name,
                areaColor: listing.area?.color,
                areaOrder: 0,
                clientID: listing.client?.id,
                clientName: listing.client?.name
            )
        }
        return TimeStore.passes(project, projectID: listing.entry.projectID, filter: self)
            && TimeStore.matches(search, task: listing.entry.task, project: project)
    }
}
