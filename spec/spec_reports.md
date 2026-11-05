# Spec: Reports Section

The Reports section of the main window shows where the time went in a date range. It never writes; corrections go through the Timer's edit popover and continue command. The iPad's Reports tab uses this layout, with touch for hover.

## 1. Layout

From top to bottom: the filter bar while filters are active, four tiles, the chart card (280 pt high), and a card holding either the breakdown table or the entry list, chosen by a segmented control, which fills the rest. Below 700 pt of content height the tiles collapse into one line and the chart shrinks to 180 pt. The subtitle is the range label ("This week · W44"). The toolbar ([spec_design.md](spec_design.md) §4) has the period arrows and the range menu, then Filters and the search field.

### 1.1 Sleep and workouts

With Sleep or Workouts on and an area chosen under "In Reports" in the Calendar settings ([spec_calendar.md](spec_calendar.md) §6), Reports count that kind's health periods ([spec_data_and_sync.md](spec_data_and_sync.md) §1.9) as a project "Sleep" or "Workouts" of that area, without a task: in the tiles, the chart, the breakdown, and the Breakdown CSV, and in the tool's `report` with `--health` ([spec_automation.md](spec_automation.md) §3.7). A period counts on each day it touches with its part of that day, as one entry per day. The project has no record, so the Projects section and the filter tree do not list it: a checked area or client covers it, while a checked project, "No project", and a task filter leave it out; the search finds it by "Sleep" or "Workouts" and by its area and client names. The entry list and the Entries CSV hold only entries, so double-clicking its breakdown row shows an empty list.

## 2. Date range

### 2.1 Days

Days run from Midnight to Midnight ([spec_data_and_sync.md](spec_data_and_sync.md) §8), 00:00 by default, and today is the shown day that contains now. Each entry counts for the days it lies on, the running entry up to now; an entry across Midnight counts its part on each day and as one entry on each. The entry list shows those parts as rows with their times, and editing a row edits the stored entry. Weeks run Monday to Sunday, numbered per ISO 8601; weeks, months, and years are whole shown days, so with Midnight at 04:00 a week starts on Monday at 04:00.

### 2.2 Presets and the date popover

The presets are Today, Yesterday, This week, Last week, This month, Last month, This year, Last year, Week to date, Month to date, Last 7 days and Last 30 days (each ending today), and All time (the day of the earliest live entry to today; today alone in an empty store). A range can also be any first and last day. The subtitle is the preset's name with its period ("Last month · September 2026", "Last 7 days · Oct 23 – 29", "All time · since Mar 4, 2019"); a custom range reads "Oct 19 – Nov 1, 2026".

This week, This month, and This year include future days: the chart draws them as empty slots, and every per-day figure counts only days up to today.

The range menu's title is the preset's name while the range equals a preset, else the range by kind ("Wed 10/28", "Week 43", "August 2026", "2025", "Oct 5 – 18"). "Choose Dates…" (or ⇧⌘D) opens the date popover: the presets and a two-month calendar ending with the month of the range's last day. A click sets the first day, a second click the last day (swapped if earlier), and the range applies at once. The range is shared with the Activity section ([spec_activity.md](spec_activity.md) adds its 366-day cap), stored per device, default This week.

### 2.3 Previous and next period

The arrows shift the range by its own unit and keep its kind: a single day, week, calendar month, or calendar year moves to the one before or after, and any other n days by n days. Week to date and Month to date go to the full previous or next week or month. All time disables the arrows. After a shift the label names the range by kind ("Week 43 · Oct 19 – 25"), and a preset is marked only when the range equals it. View › Go to Today (⌘T) applies the current kind to today: a shifted week becomes This week, a shifted month This month, n days the n days ending today.

## 3. Filters

Clients, areas, and projects are checked in the filter tree of [spec_projects.md](spec_projects.md) §2.4, with the areas' projects folded below them; an entry matches when its project, area, or client is checked. "No project" matches entries without a project. "Include archived projects", on by default, excludes archived projects' entries when off and removes them, with their checks, from the tree. A check that leaves the tree (deleted, or archived while excluded) is cleared.

The Filters button's title counts the active kinds ("Filters (2)"). Each check, "No project", and "Archived excluded" is a removable token in the filter bar, named by its path ("University · Research · Grant"), followed by "Clear All", which resets every kind and turns "Include archived projects" on. The kinds and the search combine with AND and apply to tiles, chart, table, list, and exports.

### 3.1 Search

The toolbar's search field (⌘F) narrows the report to entries where every word of the query occurs, case- and diacritic-insensitively, in the task or in the project, area, or client name. It applies 150 ms after the last keystroke; Escape clears it. The search is not a filter: it has no token, does not count in the Filters title, and is not stored.

## 4. Tiles and chart

### 4.1 Tiles

Logged time sums the matching entries. Average per day is Logged time divided by the days with entries, subtitled "over D of N days" (N the range's days up to today), so weekends and partial weeks do not distort it. Entries counts them ("1 running" when the running entry is among them), and Days with entries counts days with a positive sum ("of N"). Durations round to the minute ("18h 50m", "50m", "0h"); hours never roll into days. With no matching entry the lower card shows "No entries in this range".

### 4.2 Bars

The x axis is categorical, so empty and future days keep their width. Each bucket's total is printed above its bar ("9h 26m"; "0h" for an empty past bucket; nothing for a future one, whose x label is dimmed). The y axis shows whole hours, up to the next whole hour above the tallest bar, at least 1h. X labels have two lines: "Mon" / "10/26", "W44" / "Oct 26 – Nov 1", "Oct" / "2026", or "2026" alone; above 31 buckets they thin to every n-th. In day granularity a dashed rule marks the average per day, labeled "avg 4h 43m".

### 4.3 Granularity

Granularity is automatic: Day up to 31 days, Week up to 182, Month up to 1,096, Year beyond. A bucket cut by the range's edge is partial: its label shows the actual span ("Oct 29 – 31") and its tooltip says "partial week (3 days)".

### 4.4 Stacking and colors

"Stack by" is None, Client, Area (the default, because areas carry the colors), or Project. Segments and the legend follow key order; clicking a legend entry dims the other keys until clicked again.

| Stack key | Color | Order |
|---|---|---|
| None | Accent color; no legend | |
| Client | Eight system colors (blue, orange, green, pink, purple, teal, yellow, brown) by alphabetical client order, cycling | Alphabetical |
| Area | The area's color | Client name, then area order |
| Project | The area's color at the project's lightness step ([spec_projects.md](spec_projects.md) §4.4) by its position in the area; from the seventh project with a diagonal hatch | Area order, then project name |

"No client", "No area", and "No project" sort last in gray.

### 4.5 Hover and drill-down

Hovering a bar dims the others and shows a tooltip: the date or period, one line per non-zero segment in stack order to the second, and "Total"; week, month, and year tooltips add "Average per day". Double-clicking a bar sets the range to that bucket and remembers the previous range one level deep; "Back to Previous Range" (⌘[) restores it.

## 5. Breakdown table

### 5.1 Levels

Up to four levels from Client, Area, Project, Task, and Day, in any order, shown as a chain of popups ("Area ▾ › Project ▾ › Task ▾ › +"). Each popup disables the kinds in use and has "Remove Level" except on the first; "+" is hidden at four. Default: Area › Project › Task.

| Level | Name shown | "By name" order |
|---|---|---|
| Client | Client name; "No client" | Alphabetical |
| Area | Area name (general area: the client's name); "No area" | Area order |
| Project | Project name, "(archived)" when archived; "No project" | Alphabetical |
| Task | The trimmed text, grouped exactly; "(no task)" when empty | Alphabetical, case-insensitive |
| Day | "Mon 10/26" | Chronological |

### 5.2 Columns

The columns are Name (with the number of direct children, "Research (3)"), Logged time to the second ("12h 50m 14s"), Share ("68.1%"), Entries, and a bar in the area color (lightness step for projects) or else the accent color. Share and the bar are always of the report total, never the parent, so the bars nest and match the chart. A pinned footer row shows the totals.

### 5.3 Expanding, sorting, drilling down

The first level starts collapsed unless it has a single node. A triangle toggles a node, ⌥-click its subtree; the header button reads "Expand All" while any node is collapsed, else "Collapse All". Expansion lasts for the session and resets when the levels change.

Clicking a column header sorts within every level (again reverses). Default: Logged time descending. Name sorts by the level's order of 5.1; Bar is not sortable.

Double-click or ↩ on a node switches to the entry list filtered to that node's key path, shown as a chip ("Research › Noise Model › Clarify noise model ×"), removed with its ×, Escape in the list, or switching back to Breakdown.

## 6. Entry list

One row per matching entry, with Date ("Thu 10/29"), Start, Stop ("running" for the running entry), Duration to the second (counting up on the running entry), Client, Project ("–" without a project for both), and Task, and a footer "Total 18h 50m 14s · 22 entries". Default sort: start descending; every column sorts, Date by start instant. ↩ or double-click opens the Timer's edit popover anchored to the row ([spec_timer.md](spec_timer.md) §4). The context menu offers "Edit…", "Continue", and "Show in Calendar". There is no delete or bulk action.

## 7. Export

The lower card's Export button and File › Export… (⇧⌘E) open a save panel for the card shown: the Breakdown CSV has one row per leaf of the fully expanded tree ("Report 2026-10-26 to 2026-11-01.csv"), the Entries CSV one row per listed entry ("Entries 2026-10-26 to 2026-11-01.csv"). Both have the columns and encoding of [spec_automation.md](spec_automation.md) §8.2, so the output is byte-identical to the tool's for the same range, filters, and levels. There is no printing.

⌘C on selected table or list rows copies the visible columns as tab-separated text, tree levels flattened into separate columns.

## 8. Commands and keyboard

The commands are under the View menu's Report header ([spec_timer.md](spec_timer.md) §9), enabled while Reports is shown in the key main window: Back to Previous Range (⌘[), Filters… (⌥⌘F), Clear Filters (⌥⇧⌘F), Show Breakdown and Show Entries (⌃⌘1, ⌃⌘2, because ⌘1 to ⌘5 switch the sidebar items), Stack By, and Expand All and Collapse All (⇧⌘→, ⇧⌘←). Go to Today (⌘T), Previous and Next Period (⌥⌘← ⌥⌘→), and Date Range… (⇧⌘D) are the View menu's own items, shared with the Calendar and Activity. Edit Entry… and Timer › Continue (⌘O) act on the one selected row of the entry list.

In the table: → expands, ← collapses, ⌥→ expands the subtree, Space toggles. Each bar is an accessibility element labeled with its tooltip text.

## 9. View state and updates

Per device, the section stores filters, stack key, levels, table and list sort, and the segmented control's position. The shared date range is stored as its kind plus, for custom ranges, the dates, so a restored "This week" is the current week.

The report recomputes on every store change and, while the running entry is in the range, every 60 seconds for tiles, chart, and table and every second for the list's running row; otherwise no timer runs. The view keeps the previous result until the new one is ready, showing a thin progress bar after 250 ms.

The router's `showReports(range:filter:)` sets the range, replaces the filters (with "Include archived projects" on), clears the search, and shows the Breakdown. The URL `timetracking://planner/reports?from=…&to=…` (`to` exclusive) arrives the same way.

## 10. Testable behaviors

- PR-1. Average per day is Logged time divided by the days with a positive sum, 0 when there are none; on Thursday, "This week" reads "over 4 of 4 days" with entries Monday to Thursday and "over 3 of 4 days" when Wednesday has none.
- PR-2. Automatic granularity is Day for 1 to 31 days, Week for 32 to 182, Month for 183 to 1,096, Year beyond; week buckets run Monday to Sunday.
- PR-3. The leaves of a fully expanded tree have shares summing to 100% within rounding; under "Project › Day" a project's Entries equals the sum of its Day nodes'.
- PR-4. Checking a client in the tree restricts tiles, chart, table, list, and both CSV exports to its projects' entries; checking also an area of another client adds that area's; "No project" matches entries without a project; each check is a token named by its path ("University · Research · Grant").
- PR-5. "Include archived projects" off removes an archived project's entries everywhere and its row and check from the tree; on, its node reads "(archived)".
- PR-6. The search "noise" matches the task "Clarify Noise Model"; "grosse" matches "Große Aufgabe", and so does "course" through its project "Old Course"; "research" matches every entry of the Research area; "university draft" needs both words.
- PR-7. After a project moves to another area, last year's report by area shows its time under the new area.
- PR-8. The arrows shift as in 2.3: Week to date goes to the full previous week; This month shifted back twice from October is August; Last 7 days shifts by 7 days; All time disables both.
- PR-9. Go to Today from a shifted week selects This week, and from a custom 10-day range the 10 days ending today; the preset list highlights a preset exactly when the range equals it, and the range menu's title is that preset's name, else the range by kind ("Week 41", "August 2026").
- PR-10. Changing the range in Reports changes it in Activity, and the reverse; a stored "This week" restored in a later week shows the later week.
- PR-11. Double-clicking a day bar makes that day the range; ⌘[ restores the previous range and a second ⌘[ does nothing.
- PR-12. "This week" on Thursday draws seven slots, Friday to Sunday without bar or total; the average line's value equals the Average per day tile.
- PR-13. A bar's tooltip lists the non-zero segments in stack order, and its total equals their sum to the second.
- PR-14. Stack by Area colors each segment with its area and orders the legend by area order; with Project the second project of an area uses lightness +0.12; with None there is one accent segment per bar and no legend.
- PR-15. The level chain allows at most four levels of unused kinds; changing a level resets expansion.
- PR-16. Double-clicking a node shows the entry list filtered to its key path with a chip; Escape removes the chip.
- PR-17. Without sleep or workouts counted (1.1), the list's footer total equals the Logged time tile to the second; the running entry's Duration increases each second.
- PR-18. Double-clicking a list row opens the edit popover; a saved edit updates tiles, chart, and table. The context menu has Edit…, Continue, and Show in Calendar.
- PR-19. Both CSV exports are byte-identical to the CLI's output for the same range, filters, and levels.
- PR-20. The commands of section 8 are enabled only while Reports is shown in the key main window, under the View menu's "Report" header; ⌃⌘1 and ⌃⌘2 switch the card without changing the section.
- PR-21. With a running entry in the range the Logged time tile changes within 60 seconds; with none, no periodic timer runs.
- PR-22. Calling `showReports` with a project and "All time" sets exactly that filter, turns "Include archived projects" on, clears the search, and shows the Breakdown.
- PR-23. With Sleep on and mapped to the area Health, a night from 23:00 to 06:30 adds 6h 30m to the second day as the project Sleep under Health; unmapped, with Sleep off, or with a task filter it counts nothing; the search "sleep" finds it; `entries(matching:)` does not list it.
- PR-24. With Midnight at 04:00, reports, the entry list, and the Projects totals cut an entry there: each part counts on its day as one entry, `days(ending:count:)` gives the same totals, and a row keeps the stored entry behind it for editing.
- PR-25. With Midnight at 04:00, a running entry counts up to now on the day it lies on, and a night's sleep is cut at 04:00.
