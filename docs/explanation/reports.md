# Reports

Reports shows where the time went in a date range. It only reads: to correct something you open the entry's editor, and everything recalculates. Press ⌘3 on the Mac, or use the Reports tab on the iPad.

```{figure} /images/mac-reports.png
:alt: The Reports section with four summary tiles, a stacked bar chart with one bar per day, and a breakdown table by area, project, and task.

Tiles, the chart, and the breakdown for one range.
```

## The range

The menu in the toolbar offers presets such as This week, Last month, and All time, and "Choose Dates…" opens a calendar for any first and last day. The arrows step by the range's own unit: a week to the previous week, a month to the previous month. ⌘T brings the current kind of range back to today, and the default is This week.

The Activity section shares this range, so you can compare tracked and recorded time for the same period by switching between them. This week also shows its future days as empty slots in the chart, but they stay out of every per-day figure.

## Tiles and chart

Four tiles sum up the range. Logged time adds up the matching entries. Average per day divides that by the days that have entries, so weekends and half-finished weeks don't pull it down, and it says "over D of N days". The other two count the entries and the days with entries.

The chart draws one bar per day for up to 31 days, then one per week, month, or year, chosen automatically. "Stack by" colors the bars by area (the default, because areas carry the colors), client, or project, or leaves them plain. Hover over a bar for the exact figures, and double-click it to zoom into that day or period; ⌘[ takes you back.

## Breakdown and entry list

The lower card has two faces. The breakdown is a tree with up to four levels, which you pick from Client, Area, Project, Task, and Day in any order, by default Area, then Project, then Task. Each row shows its time to the second, its share of the whole report, its number of entries, and a bar. Double-click a row to see the entries behind it.

The entry list shows one row per entry, sorted however you like, with a footer total. Double-click a row to edit it. The context menu also offers Continue and Show in Calendar. There is no delete here.

## Narrowing it down

Filters narrows the report to clients, areas, and projects, which appear as removable tokens above the tiles. The search field (⌘F) keeps only entries where every word occurs in the task or in the project, area, or client name. Filters and search apply to the tiles, the chart, the lists, and the exports alike.

## How time is counted

Entries that cross the day change count their part on each day, as described in [The start of day](start-of-day.md), so the days add up to the total. The running entry counts up to now. If you chose to, [sleep and workouts](../howto/health.md) count as a project of an area you pick.

Export gives you a CSV of whichever card is showing; see [Export a report as CSV](../howto/export.md). The output is byte for byte what the command-line tool writes for the same range and filters. The [Reports spec](../reference/reports.md) has the details.
