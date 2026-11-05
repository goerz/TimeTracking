# Projects

The Projects section is where the [tree of clients, areas, and projects](concepts.md) is edited. You won't visit it daily: most projects are created in passing from the picker, and this view is for tidying up. Press ⌘4 on the Mac, or use the Projects tab on the iPad.

```{figure} /images/mac-projects.png
:alt: The Projects table, grouped by client and area, with columns for client, area, creation date, last tracked date, and total tracked time.

Grouped by client and area, the table holds the whole structure.
```

The table lists projects under their clients and areas, with columns for when each was created, when it was last tracked, and its total time. "Group by" in the bar below the table switches between Client and Area, Client, and no grouping, and a click on a column header sorts within the groups. The date range in the toolbar is this section's own and defaults to All time; any other range shows only projects with entries in it and totals just those. Sorting by Last tracked is a quick way to find what has gone quiet.

## Changing things

Select a row and use the Project menu, the context menu, or the ⋯ button on the row. Double-click or Return edits it, in a dialog for a project and a sheet for a client or area. ⌘O starts a timer on the selected project, and Show in Reports (⇧⌘R) opens Reports filtered to the row.

Archive with ⌫ when a project is finished. Delete works only for a project without entries; for one that has them, Merge Into… moves its entries to another project. New projects, areas, and clients are in the File menu and behind the New button below the table.

"Include archived projects" in Filters brings archived projects back into the table. Areas have their own order within a client, which Move Up and Move Down change, and that order then applies everywhere areas appear.

## The project picker

Wherever you assign a project, the same picker appears: from the chip in the Timer, in the editor, in the Calendar, and on iOS. It shows "No Project", your five most recent projects, and then every client with its active projects. Typing searches names, and with the Timer also tasks you tracked in the last 90 days, so "noise" finds the project you last used for "Clarify noise model". If no project has that name, "+ Create Project" offers to make it on the spot.

[Set up clients, areas, and projects](../howto/projects.md) shows the usual steps. The [Projects spec](../reference/projects.md) covers the rules, for example which names must be unique.
