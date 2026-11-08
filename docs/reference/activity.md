# Activity Section

The Activity section of the main window (fifth sidebar item, ⌘5; on the iPad a tab, section 5; the iPhone has none) shows what the tracker recorded over a date range: how much of each day was active, at which hours, in which apps, and on which workspaces. It reads the logs through the shared library ([data_and_sync.md](data_and_sync.md) §6) and never writes them; collection and formats belong to [activity_tracking.md](activity_tracking.md). It does not change blocks, assign projects, create entries, or export.

Items, blocks, and background blocks are those of the tracker ([activity_tracking.md](activity_tracking.md) §2.2, §2.3). This section groups items first by app (the item's `app`), then by workspace, shown as its last component; a workspace's details are its items, labeled as in the block summary ([activity_tracking.md](activity_tracking.md) §2.8). A block's active time is the sum of its foreground item seconds; its background items (busy coding agents, builds) are not attention. A background block is background work while the user was away, between foreground blocks. A block may run past midnight and past the start of day.

## 1. Layout

The window title is "Activity" and its subtitle the range label. The toolbar follows [design.md](design.md) §4: the period arrows and the range menu, then the device popup (1.2). Below it come the header (1.2), the app chips (1.3), the panels, and a fixed health footer (1.10). Panels are cards in two columns above 1100 points of content width and one column below, in the order heatmap, by-day chart, Apps, Workspaces, In the background, Away.

### 1.1 Date range

The range control, its presets, and its shortcuts are those of Reports ([reports.md](reports.md) §2), and the selected range is one state shared by both sections, since comparing tracked and recorded time for one week is the main use. A range over 366 days is clipped to the 366 days ending on its last day, and the header says "Showing the last 366 days of the selection".

Days run from one start of day to the next ([data_and_sync.md](data_and_sync.md) §8), today included. A block, foreground or background, counts whole on the day of its start, because its items cannot be divided, and keeps its recorded date and clock hours. Future days of the range appear as empty rows and bars and are left out of every average.

### 1.2 Header

Line 1: "34h 10m active", the sum of the blocks' active time, so that this section and the Calendar agree. Under an app filter it is the selected apps' item seconds. Line 2, separated by middle dots: "N days with activity", "Xm per day" (the average over those days), and, with more than one device, the total per device (`remote` reads "Other devices (Safari)"). An "All devices" popup, hidden with one device, narrows every panel to one device, each block to its part there, and lists each device's total.

Durations read `Nh MMm` from one hour (`Nh` on the hour), `Mm` below, `Ss` below one minute, and `0h` for none.

### 1.3 App chips and colors

An "All" chip, then one chip per app ranked by time: the first eight, the rest behind "N more…", a popover with a searchable list. A chip shows the app's glyph in its color, its display name, and its duration on hover. Clicking toggles a chip (several may be on); "All" turns the others off. The filter applies to every panel except Away. It resets when the range changes other than by a period arrow and when the main window reopens, and it does not sync.

| App | Display | Glyph |
|---|---|---|
| A terminal (WezTerm, iTerm2, Terminal) | the item's `app` | terminal |
| A browser (Safari, Arc, Chrome, Brave, Edge, Vivaldi, Firefox) | the item's `app` | a compass, the same for every browser |
| A Screen Time set (`appID` `screenTime`, or `screenTime.everything` for "Everything") | the set's label, or the device's name for "Everything" | the device's glyph |
| any other | the item's `app` | a generic app glyph |

A workspace shows as its last component ("MyApp", "arxiv.org"), with its full path or name in the tooltip; the workspace `private` reads "(private)" in gray.

App colors are automatic and separate from area colors; the Calendar's activity column draws every block in one neutral color. An app seen here for the first time gets the index into a fixed sequence of 12 colors used by the fewest apps so far, lowest on ties, stored in the synced, append-only `activity.appColors`. It never changes and the user cannot pick one.

### 1.4 Active time by hour (heatmap)

Twenty-four hour columns, starting at the start of day and labeled with the hour numbers divisible by 3.

| Range | Rows | Label | Cell value |
|---|---|---|---|
| 1 to 7 days | one per day | "Thu 29" | active minutes in that hour, 0 to 60 |
| 8 to 98 days | one per ISO week, up to 15 | "W44" and the Monday's date | average active minutes in that hour per past day of the week within the range |
| 99 to 366 days | one per month, up to 13 | "Oct 2026" | the same per past day of the month within the range |

Shades of the accent color: 0 empty; 1 to 15, 25%; 16 to 30, 50%; 31 to 45, 75%; 46 to 60, full. After each row its total (day rows) or "avg/day" average; days without blocks have a dimmed label. Week and month rows get a footer row "All", the average per past day of the range.

A block's active time (under a filter, each item's seconds) is spread over the hours it covers in proportion to its overlap: 09:40 to 10:20 puts half into 9 and half into 10. Exact minutes would need the Mac-only sample database, so tooltips say "about".

A cell's tooltip reads "Thu Oct 29 · 09:00–10:00", then "about 47m active (MacBook)", then up to five items ranked by minutes and "+ N more". The word "about" appears when more than one block overlaps the cell, device names when several devices are present. Week and month rows list the top apps with their average per day. Clicking a cell drills into the Calendar (section 3).

### 1.5 Active time by day

One stacked bar per day up to 31 days, per ISO week up to 53 weeks, per month beyond. Bars stack item seconds per app in the Apps ranking, in app colors; apps beyond the twelfth merge into gray "Other apps", so without a filter a bar equals the day's active time. The y axis has lines every 2 hours, scaled to the tallest bar rounded up to an even hour. Totals sit above bars. On the Mac today's bar includes the open block with a hatched top, and a dot under its label marks today.

Hovering a segment shows "Thu Oct 29 · WezTerm · 4h 12m of 6h 38m"; a label or empty bar area shows the day's total and three largest apps ("Thu Oct 29 · 6h 38m · WezTerm 4h 12m, Mail 1h 10m, Safari 20m"); a future bar shows nothing. Clicking drills into the Calendar.

### 1.6 Apps and workspaces

The Apps panel lists the range's apps by time, each with a bar, item-second duration, and share of the unfiltered total. Clicking a row toggles it like its chip. Right-click offers "Show Only <name>", "Show in Calendar" (first day of the range, this app's blocks highlighted), and "Exclude <name> from Tracking…" (section 4; browsers are excluded per site from a site's Workspaces row).

Workspaces ("Where the time went") lists the selected apps' workspaces under a segmented control All, Folders (workspaces that are paths), Sites (workspaces from URLs); other workspaces appear under All only. When the filter changes and every selected app is a browser, the control switches to Sites, otherwise to All.

A workspace's row has a chevron, which replaces the list with its items from the blocks, ranked by seconds and labeled as in the block summary, under a breadcrumb "WezTerm › MyApp" that gives their count. A workspace of a domain in `private_domains` shows no items.

Both lists show twenty rows and a "Show all (48)" link.

### 1.7 In the background

The background items of the foreground blocks and of the background blocks, ranked by seconds, labeled as in the block summary with the workspace after "in" ("Claude Code refactor-parser in MyApp", "tmux make test in MyApp"), with the part in background blocks ("38m while away"), under the subtitle "Does not count as active time". The filter applies by the item's app. Hidden when there are none.

### 1.8 Away

Away time is a gap longer than the tracker's `idle_close` between consecutive blocks of one shown day, all devices forming one timeline; time before the day's first block and after its last is night, not away. The panel shows the total ("4h 12m during the day"), per cause the time and number of gaps ("idle 1h 10m (3 times)"), a line on background work ("Work went on in the background for 38m of it."; none without), and the note "Time before your first and after your last activity of the day is not counted." A gap's cause is the end reason of the block before it ([activity_tracking.md](activity_tracking.md) §2.2): idle, locked, asleep, another user, Focus, or tracker stopped; after any other reason it is unknown. The filter does not apply.

### 1.9 Live updates and empty states

A new or changed block updates the aggregates within 2 seconds. On the Mac today's figures include the open block until the closed block replaces it. Reconstructed time (`rc`) counts normally. Block times are shown as recorded in the device's time zone. Figures stay until the new ones are ready, and a slow read that finishes after a later one is dropped.

With no blocks, the panels give way to "No activity recorded between Oct 20 and Oct 26" ("on Oct 20" for one day), plus "The tracker was not running." and "Tracker Settings…" when the footer is red. With nothing left after filtering: "Nothing recorded for the selected apps" with "Show All Apps". With an empty block log and the tracker not set up on this Mac (not enabled, no `current.json`, or Accessibility missing), "No Activity Yet" reads "Set up the tracker to see where your time goes. Nothing is recorded until you enable it." with "Open Tracker Settings…"; once a block exists it never returns.

### 1.10 Health footer

On the Mac, one line with the Tracker pane's status dot and line ([activity_tracking.md](activity_tracking.md) §7.4), refreshed every 10 seconds while visible; then, in the warning color, only the sources that are limited or off, by name and reason; and "Tracker Settings…". Hovering shows "Tracker version 1.0", the current foreground item, labeled as in the block summary ([activity_tracking.md](activity_tracking.md) §2.8) with its workspace ("Now: WezTerm · refactor-parser · MyApp"), and the presence ("In use", "In use without typing", "Idle", "Locked", "Asleep", "Another user is logged in").

## 2. Keyboard and menu

| Action | Keys |
|---|---|
| Show the section | ⌘5 |
| Range: previous, next, today, date popover | As in Reports (⌥⌘←, ⌥⌘→, ⌘T, ⇧⌘D) |
| Move between heatmap cells, bars, and a bar's segments | Arrow keys |
| Show a focused cell's or segment's details; toggle a focused chip or row | Space |
| Drill into the Calendar from a focused cell, bar, or segment | Return |
| Leave a workspace drill-down, else clear the filter | Escape |

Tab reaches the heatmap, the chart, and the rows of Apps and Workspaces that act on a click; a click beside the cells or on the y axis also focuses the panel. Chips are buttons, which take the focus when the system's keyboard navigation is on. The heatmap starts on its first cell and the chart on its first bar. Left and right step between bars, keeping the app where the next bar has it; up and down step through a bar's segments, bottom up, and below the lowest back to the whole bar. The focused cell has an outline, and the rest of the chart dims around the focused bar or segment. Space shows or hides the cell's tooltip text under the heatmap and the tooltip over the chart, which then follow the arrow keys; on a Workspaces row with a chevron it opens the items.

The View menu holds the range commands and, under its Activity header ([timer.md](timer.md) §9), Clear Filter or Back (Escape's two steps) and "Exclude from Tracking…" for the selected app or site row.

## 3. Drill-down into the Calendar

A heatmap cell, bar, or segment opens the Calendar ([calendar.md](calendar.md) §1.2) at the shown day (a week or month row's first day) and the cell's hour, highlighting the cell's hour or the segment's app. Range, filter, and scroll position here stay unchanged, and ⌘5 returns to them.

## 4. Exclusions

"Exclude <name> from Tracking…" (Mac only) opens the Tracker pane with an unsaved draft ([activity_tracking.md](activity_tracking.md) §7.4): the bundle identifier (the item's `appID`) under `exclude_apps` for an app, the folder under `exclude_paths` for a folder workspace, or the bare domain under `exclude_domains` for a site. This view saves nothing.

The reader applies the current rules to past data at read time on every device, without rewriting the logs; time removed by a rule leaves every total, and a block left empty is not shown. Items with the workspace `private` show as one gray row per app with their time kept. Rewriting past logs is the tracker's command `reapply-exclusions` (§7.3 there).

## 5. iPad

The Activity tab shows the same panels from the synced block log, without the exclusion shortcut or the open block. Its footer shows the most recently updated Mac's tracker from `LiveState` ([data_and_sync.md](data_and_sync.md) §4.1): "Mac tracker: checked 2 min ago", the presence in the tooltip ("Idle for 5 min"), and the sources with a problem ("iCloud Drive needs attention on the Mac"). The dot is green while `agentRunning` is true, else gray with "Mac tracker: last checked 2 h ago" or "Mac tracker: not checked yet". "Waiting for iCloud · activity up to 14:02" shows while today's date file has not arrived. With no blocks the empty state reads "The tracker runs on your Mac. Set it up in the Mac app's Settings, Tracker pane."

## 6. Testable behaviors

1. Without a filter the header total is the sum of the blocks' active time after exclusions; with one, the selected apps' item seconds; device totals sum to the header total and appear only with more than one device.
2. Durations render per 1.2.
3. A range changed in Reports changes here and the other way; a custom range over 366 days is clipped to its last 366 days with the header note.
4. Chips toggle, "All" clears, and the filter changes every panel but Away; over eight apps, "N more…" lists the rest and filters as the user types.
5. A new app gets the least-used index, lowest on ties, stored in `activity.appColors` and never changed; the workspace `private` is gray.
6. The heatmap has day rows for 1 to 7 days, ISO-week rows for 8 to 98, month rows for 99 to 366, with values and shading per 1.4; only week and month rows have the "All" footer.
7. A 09:40 to 10:20 block with 2400 seconds of active time adds 20 minutes to the 9 cell and 20 to the 10 cell, its items split alike.
8. A cell tooltip lists at most five items, then "+ N more", with "about" when several blocks overlap the cell.
9. In This week on Thursday, Friday to Sunday are empty rows and bars, excluded from the per-day average.
10. Bars merge apps beyond the twelfth into "Other apps" and, without a filter, equal the day's active time.
11. On the Mac today's bar includes the open block, replaced by the closed block within 2 seconds of the append.
12. App shares stay relative to the unfiltered total, and without a filter the Apps rows sum to the header total.
13. Selecting only browsers switches Workspaces to Sites, any other selection or All to All.
14. A workspace's chevron lists its items from the blocks on every device, the Mac and the iPad alike; a workspace of a domain in `private_domains` has none.
15. Away counts only gaps over `idle_close` between consecutive blocks of one day, each classified by the end reason of the block before it, on every device.
16. The Mac footer's dot matches the Tracker pane's status for the same `current.json`; the iPad footer shows `lastTick` from `LiveState` without sources.
17. Clicking a cell opens the Calendar at that day and hour with the hour's blocks pulsed; ⌘5 returns with range, filter, and scroll unchanged.
18. With an empty log and no tracker set up the setup card shows and opens the Tracker pane; after a block exists it does not return.
19. "Exclude <name> from Tracking…" opens the Tracker pane with the right list and value and saves nothing; after saving, past items of that rule disappear from every total while the log files stay byte-identical.
20. The view never modifies the block log, `current.json`, or `settings.toml`.
21. In the background adds the background blocks' items, each with its part while away; the Away panel says how much of the counted gaps background blocks cover, also under an app filter, and has no such line without them.
22. A reload of a long range that finishes after a later reload of a short range leaves the short range's figures and no loading indicator.
23. With the start of day at 04:00, a block at 02:00 on March 14 counts on March 13 while its log date stays March 14, its hour stays 02:00, and a heatmap row's columns run from 04:00 to 03:00.
24. On the Mac today's bar marks the open block's part, hatched, as the top of its stack, also under a filter; a bar without an open block has none.
25. Hovering a bar segment shows its day, display name, and time of the bar's total; hovering a label or the empty area above a bar shows the total and the three largest apps; a future bar shows nothing.
26. Clicking a bar segment opens the Calendar at its day with that app's blocks highlighted; a click beside the stack or on a gray layer opens the day without a highlight.
27. The arrow keys move the focused heatmap cell in the order of the columns and rows, the "All" row included, and stop at the edges; Space shows and hides the cell's details; Return opens the Calendar as a click does.
28. Left and right move between bars, keeping the app where the next bar has it; up and down move through a bar's segments and back to the whole bar; Space shows and hides the tooltip; Return opens the Calendar as a click does.
29. Space on a focused Apps row toggles it as a click does; on a Workspaces row with a chevron it opens the items; a row that acts on no click takes no focus.
