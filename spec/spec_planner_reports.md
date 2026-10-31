# Spec: Planner Window, Reports Section

The Reports section of the main window shows where the time went in a date range. It reads through the library's report queries ([spec_data_and_sync.md](spec_data_and_sync.md) §7.3) and never writes; entries change only through the Timer's edit popover and continue command.

## 1. Layout

From top to bottom: the filter bar while filters are active (3), four tiles, the chart card (fixed 280 pt high), and a card holding either the breakdown table or the entry list, chosen by a segmented control. The lower card fills the rest and scrolls. Below 700 pt of content height the tiles collapse into one line and the chart shrinks to 180 pt. Tiles and cards are filled cards of [spec_design.md](spec_design.md) §3; tile values use the metric style (§1 there).

The window title is "Reports" and its subtitle the range label ("This week · W44"). Toolbar ([spec_design.md](spec_design.md) §4): leading the previous- and next-period arrows and the range menu (2.2); trailing Filters, the granularity menu ("Show Totals By"), Print, and Export. The chart card's header holds "Logged time" and "Stack by"; the lower card's header the segmented control (Breakdown | Entries), the level chain, and Expand All / Collapse All.

## 2. Date range

### 2.1 Days

Days run midnight to midnight; each entry counts whole for its day, the running entry up to now ([spec_data_and_sync.md](spec_data_and_sync.md) §8). Weeks run Monday to Sunday, numbered per ISO 8601.

### 2.2 Presets and the date popover

The range menu's title names the selection: the preset's name ("This month") while the range equals a preset, else the range by kind ("Wed 10/28", "Week 43", "August 2026", "2025", "Oct 5 – 18"). The menu lists the presets, the current one checked, then "Choose Dates…", which opens the date popover (⇧⌘D opens it too): the presets and a two-month calendar. The range is shared with the Activity section ([spec_planner_activity.md](spec_planner_activity.md) adds its 366-day cap), stored per device, default This week.

| Preset | Range (inclusive days) | Subtitle |
|---|---|---|
| Today | Today | "Today · Thu 10/29" |
| Yesterday | Yesterday | "Yesterday · Wed 10/28" |
| This week | Monday to Sunday of the current week | "This week · W44" |
| Last week | The previous Monday to Sunday | "Last week · W43" |
| This month | The current calendar month | "This month · October 2026" |
| Last month | The previous calendar month | "Last month · September 2026" |
| This year | January 1 to December 31 | "This year · 2026" |
| Last year | The previous calendar year | "Last year · 2025" |
| Week to date | Monday of the current week to today | "Week to date · W44" |
| Month to date | The first of the month to today | "Month to date · October 2026" |
| Last 7 days | Today and the 6 days before | "Last 7 days · Oct 23 – 29" |
| Last 30 days | Today and the 29 days before | "Last 30 days · Sep 30 – Oct 29" |
| All time | The day of the earliest live entry to today (today alone in an empty store) | "All time · since Mar 4, 2019" |
| Custom | Any first and last day | "Oct 19 – Nov 1, 2026" |

This week, This month, and This year include future days: the chart draws them as empty slots, and every per-day figure (averages, "of N days") counts only days up to today.

The calendar shows the month of the range's last day and the one before. A click sets the first day, a second click the last day (swapped if earlier), and the range applies at once.

### 2.3 Previous and next period

The arrows shift the range by its own unit and keep its kind.

| Current range | Previous / next |
|---|---|
| A single day | The day before / after |
| A Monday-to-Sunday week | The week before / after |
| Week to date | The full previous / next week |
| A calendar month | The month before / after |
| Month to date | The full previous / next month |
| A calendar year | The year before / after |
| Any other n days | The n days before its first day / after its last day |
| All time | Arrows disabled |

After a shift the label names the range by kind ("Week 43 · Oct 19 – 25", "September 2026", "2025", "Oct 5 – 18, 2026"), and the preset lists (the range menu, the popover) mark a preset only when the range equals it. View › Go to Today (⌘T; there is no toolbar button) applies the current kind to today: a shifted week becomes This week, a shifted month This month, n days the n days ending today.

## 3. Filters

The Filters button's title counts active filter kinds ("Filters (2)") and its symbol fills while any is active. Each checked client, area, or project, "No project", the task, and archived exclusion is a removable token in the filter bar above the tiles ("Consulting", "University · Research", "University · Research · Grant", "No project", "Task: noise", "Archived excluded", each with `xmark`), followed by "Clear All"; the bar is hidden without filters. The kinds combine with AND, and filters apply to tiles, chart, table, list, and exports.

The popover is laid out as the Projects section's ([spec_planner_projects.md](spec_planner_projects.md) §2.4), with the same tree:

| Kind | Control | Matches |
|---|---|---|
| Clients, Areas, and Projects | "No project", then the filter tree of clients, their areas, and the areas' projects (archived projects in secondary label color while included) | Entries of projects that are checked or whose area or client is checked; "No project" matches entries without a project |
| Task | Text field | Task contains the trimmed text, case- and diacritic-insensitively; applied 150 ms after the last keystroke |
| Include archived projects | Check box, on by default | Off excludes archived projects' entries and removes them, with their checks, from the tree |

A checked client, area, or project that leaves the tree (deleted, or archived while excluded) is unchecked. "Clear All" resets every kind and turns "Include archived projects" on.

## 4. Tiles and chart

### 4.1 Tiles

| Tile | Value | Subtitle |
|---|---|---|
| Logged time | Sum of matching entries' durations | None |
| Average per day | Logged time divided by the days with entries; 0h when none | "over D of N days" (D days with entries, N the range's days up to today) |
| Entries | Number of matching entries | "1 running" when the running entry is among them |
| Days with entries | Days with a positive sum | "of N" |

Tile durations round to the minute: "18h 50m", "50m", "0h"; hours never roll into days. With no matching entry the lower card shows "No entries in this range".

### 4.2 Bars

One Swift Charts `BarMark` per bucket and stack segment, x categorical (equal widths), y seconds. Each bucket's total is printed above its bar ("9h 26m"; "0h" for an empty past bucket; nothing for a future one). The y axis shows whole hours with grid lines, up to the next whole hour above the tallest bar, at least 1h. X labels have two lines: "Mon" / "10/26" for days, "W44" / "Oct 26 – Nov 1" for weeks, "Oct" / "2026" for months, "2026" alone for years; above 31 buckets they thin to every n-th so none overlap. In day granularity a dashed rule marks the average per day, labeled "avg 4h 43m" at the right edge.

### 4.3 Granularity

Automatic, Day, Week, Month, Year. Automatic picks Day up to 31 days, Week up to 182, Month up to 1,096, Year beyond. A bucket cut by the range's edge is partial: its label shows the actual span ("Oct 29 – 31") and its tooltip says "partial week (3 days)".

### 4.4 Stacking and colors

"Stack by": None, Client, Area (default), Project. Segments stack from the bottom in key order. The legend lists the keys present in that order; clicking an entry dims the other keys until clicked again.

| Stack key | Color | Order |
|---|---|---|
| None | Accent color; no legend | |
| Client | Eight system colors (blue, orange, green, pink, purple, teal, yellow, brown) assigned in alphabetical client order, cycling | Alphabetical |
| Area | The area's color | Client name, then area order |
| Project | The area's color at the project's lightness step ([spec_planner_projects.md](spec_planner_projects.md) §4.4) by its position in the area; from the seventh project with a diagonal hatch | Area order, then project name |

"No client", "No area", and "No project" sort last in system gray.

### 4.5 Hover and drill-down

Hovering a bar (`chartXSelection`) dims the others and shows a tooltip: the date or period ("Monday, October 26"), one line per non-zero segment in stack order (swatch, name, duration to the second), and "Total". Week, month, and year tooltips add "Average per day".

Double-clicking a bar sets the range to that bucket and remembers the previous range one level deep; "Back to Previous Range" (⌘[) restores it. Single clicks change nothing.

## 5. Breakdown table

### 5.1 Levels

Up to four levels from Client, Area, Project, Task, and Day, in any order, shown as a chain of popups ("Area ▾ › Project ▾ › Task ▾ › +"). Each popup lists the five kinds with used ones disabled, plus "Remove Level" except on the first; "+" adds a level and is hidden at four. Default: Area › Project › Task.

| Level | Name shown | "By name" order |
|---|---|---|
| Client | Client name; "No client" | Alphabetical |
| Area | Area name with a dot (general area: the client's name); "No area" | Area order |
| Project | Project name with a dot, "(archived)" when archived; "No project" | Alphabetical |
| Task | The trimmed text, grouped exactly; "(no task)" when empty | Alphabetical, case-insensitive |
| Day | "Mon 10/26" | Chronological |

### 5.2 Columns

| Column | Content |
|---|---|
| Name | Triangle, indentation, name, and for nodes with children the number of direct children ("Research (3)") |
| Logged time | To the second ("12h 50m 14s", "19m 54s", "4s") |
| Share | Seconds over the report total, one decimal ("68.1%"), never relative to the parent |
| Entries | Entries under the node |
| Bar | Full width is 100% of the total; area color (lightness step for projects) for area and project nodes, accent color otherwise |

A pinned footer row shows "Total", the total time, "100%", and the entry count.

### 5.3 Expanding, sorting, drilling down

The first level starts collapsed unless it has a single node. A triangle toggles a node, ⌥-click its subtree; the header button reads "Expand All" while any node is collapsed, else "Collapse All". Expansion is kept per key path for the session and reset when the levels change.

Clicking a column header sorts within every level (again reverses). Default: Logged time descending. Name sorts by the level's order of 5.1; Bar is not sortable.

Double-click or ↩ on a node switches to the entry list filtered to that node's key path, shown as a chip ("Research › Noise Model › Clarify noise model ×"), removed with its ×, Escape in the list, or switching back to Breakdown.

## 6. Entry list

One row per matching entry, with a footer "Total 18h 50m 14s · 22 entries".

| Column | Content |
|---|---|
| Date | "Thu 10/29"; sorts by start instant |
| Start, Stop | System 12- or 24-hour format; Stop reads "running" for the running entry |
| Duration | To the second; the running entry counts up every second, with a running glyph |
| Client | Client name; "–" without a project |
| Project | Name with its area's dot; "–" without a project |
| Task | Truncated, full text in the tooltip |

Default sort: start descending; every column sorts. ↩ or double-click opens the Timer's edit popover anchored to the row ([spec_timer_window.md](spec_timer_window.md) §4). The context menu offers "Edit…", "Continue" (the Timer's continue command), and "Show in Calendar" (`showCalendar` at the entry's day). There is no delete or bulk action.

## 7. Export and printing

File › Export… (⇧⌘E) opens a save panel with a format popup. Both formats come from the library's `ReportCSVWriter` with the columns and encoding of [spec_automation.md](spec_automation.md) §8.2, so the output is byte-identical to the CLI's for the same range, filters, and levels.

| Format | Content | Default file name |
|---|---|---|
| Breakdown (CSV) | One row per leaf of the fully expanded current tree | "Report 2026-10-26 to 2026-11-01.csv" |
| Entries (CSV) | One row per listed entry | "Entries 2026-10-26 to 2026-11-01.csv" |

⌘C on selected table or list rows copies the visible columns as tab-separated text, tree levels flattened into separate columns.

File › Print… (⌘P) uses the standard print panel (its PDF button saves a PDF), landscape by default, light appearance with area colors. The page carries a header with the range label, the active filters, and the print date; then the tiles, the chart (`ImageRenderer` at the printer's scale), and the breakdown at its current expansion with the column header repeated on each page, or the entry list when it is showing.

## 8. Commands and keyboard

The commands live under the View menu's Report header ([spec_timer_window.md](spec_timer_window.md) §9), enabled while Reports is shown; Go to Today, Previous and Next Period, and Date Range… are the View menu's own items, shared with the Calendar and Activity, Edit Entry… for the one selected row of the entry list is in the Entry menu, and Export and Print are in File, enabled only while Reports is shown in the key main window. Timer › Continue (⌘O) continues the one selected row of the entry list.

| Command | Shortcut |
|---|---|
| Previous Period / Next Period | ⌥⌘← / ⌥⌘→ |
| Go to Today | ⌘T |
| Back to Previous Range | ⌘[ (after a drill-down) |
| Date Range… | ⇧⌘D |
| Filters… | ⌥⌘F (focus on the client chips) |
| Find Task | ⌘F (focus in the Task filter) |
| Clear Filters | ⌥⇧⌘F |
| Show Breakdown / Show Entries | ⌃⌘1 / ⌃⌘2 |
| Show Totals By: Automatic, Day, Week, Month, Year | None |
| Stack By: None, Client, Area, Project | None |
| Expand All / Collapse All | ⇧⌘→ / ⇧⌘← |
| Export… | ⇧⌘E |
| Print… | ⌘P |

In the table: → expands, ← collapses, ⌥→ expands the subtree, Space toggles. Each bar is an accessibility element labeled with its tooltip text.

## 9. View state and updates

Per device, the section stores filters, granularity, stack key, levels, table and list sort, and the segmented control's position. The shared date range is stored as its kind plus, for custom ranges, the dates, so a restored "This week" is the current week. Expansion and drill-down history last for the session.

The report recomputes on every store change and, while the running entry is in the range, every 60 seconds for tiles, chart, and table and every second for the list's running row; otherwise no timer runs. The view keeps the previous result until the new one is ready, showing a thin progress bar at the top of the content after 250 ms.

The router's `showReports(range:filter:)` sets the range, replaces the filters (with "Include archived projects" on), and shows the Breakdown. The URL `timetracking://planner/reports?from=…&to=…` arrives the same way.

## 10. Testable behaviors

- PR-1. Average per day is Logged time divided by the days with a positive sum, 0 when there are none; on Thursday, "This week" reads "over 4 of 4 days" with entries Monday to Thursday and "over 3 of 4 days" when Wednesday has none.
- PR-2. Automatic granularity is Day for 1 to 31 days, Week for 32 to 182, Month for 183 to 1,096, Year beyond; week buckets run Monday to Sunday.
- PR-3. The leaves of a fully expanded tree have shares summing to 100% within rounding; under "Project › Day" a project's Entries equals the sum of its Day nodes'.
- PR-4. Checking a client in the tree restricts tiles, chart, table, list, and both CSV exports to its projects' entries; checking also an area of another client adds that area's; "No project" matches entries without a project; each check is a token named by its path ("University · Research · Grant").
- PR-5. "Include archived projects" off removes an archived project's entries everywhere and its row and check from the tree; on, its node reads "(archived)".
- PR-6. The task filter "noise" matches "Clarify Noise Model"; "grosse" matches "Große".
- PR-7. After a project moves to another area, last year's report by area shows its time under the new area.
- PR-8. The arrows shift as in 2.3: Week to date goes to the full previous week; This month shifted back twice from October is August; Last 7 days shifts by 7 days; All time disables both.
- PR-9. Go to Today from a shifted week selects This week, and from a custom 10-day range the 10 days ending today; the preset list highlights a preset exactly when the range equals it, and the range menu's title is that preset's name, else the range by kind ("Week 41", "August 2026").
- PR-10. Changing the range in Reports changes it in Activity, and the reverse; a stored "This week" restored in a later week shows the later week.
- PR-11. Double-clicking a day bar makes that day the range; ⌘[ restores the previous range and a second ⌘[ does nothing.
- PR-12. "This week" on Thursday draws seven slots, Friday to Sunday without bar or label; the average line's value equals the Average per day tile.
- PR-13. A bar's tooltip lists the non-zero segments in stack order, and its total equals their sum to the second.
- PR-14. Stack by Area colors each segment with its area and orders the legend by area order; with Project the second project of an area uses lightness +0.12; with None there is one accent segment per bar and no legend.
- PR-15. The level chain allows at most four levels of unused kinds; changing a level resets expansion.
- PR-16. Double-clicking a node shows the entry list filtered to its key path with a chip; Escape removes the chip.
- PR-17. The list's footer total equals the Logged time tile to the second; the running entry's Duration increases each second.
- PR-18. Double-clicking a list row opens the edit popover; a saved edit updates tiles, chart, and table. The context menu has Edit…, Continue, and Show in Calendar.
- PR-19. Both CSV exports are byte-identical to the CLI's output for the same range, filters, and levels.
- PR-20. The commands of section 8 are enabled only while Reports is shown in the key main window, under the View menu's "Report" header; ⌃⌘1 and ⌃⌘2 switch the card without changing the section.
- PR-21. With a running entry in the range the Logged time tile changes within 60 seconds; with none, no periodic timer runs.
- PR-22. Calling `showReports` with a project and "All time" sets exactly that filter, turns "Include archived projects" on, and shows the Breakdown.

## 11. Decisions

- Average per day divides by days with entries and shows the denominator, so weekends and partial weeks do not distort it.
- Share is always of the report total, so the bars nest and match the chart.
- Breakdown levels are free in order and include Day, covering a daily log and a per-project calendar with one control.
- Stacking defaults to Area because areas carry the colors; client colors are a fixed fallback.
- The chart's x axis is categorical so empty and future days keep their width.
- The section never writes; corrections go through the Timer's edit popover.
- Show Breakdown and Show Entries use ⌃⌘1 and ⌃⌘2 because ⌘1 to ⌘5 switch the sidebar items.

## 12. Interfaces

Provided:

- `DateRangeSelection`: the shared range with its presets, arrows, popover, and shortcuts (2), used by Activity.
- The `showReports(range:filter:)` handler (9).

Assumed:

- Data library: `Reporting`, `TrackingCalendar`, the earliest live entry's start, `StoreObserving`.
- Automation: `ReportCSVWriter` columns ([spec_automation.md](spec_automation.md) §8.2).
- Timer: the edit popover (anchorable to a row of another view) and the continue command.
- Projects: `PlannerRouter`, area order, general-area display, and `AreaColor` derivations.
- iOS: the iPad Reports tab uses this layout, with touch for hover and the share sheet for printing.
