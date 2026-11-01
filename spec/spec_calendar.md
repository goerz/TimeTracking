# Spec: Calendar Section

The Calendar section of the main window shows one to seven days side by side. Each day has up to three columns: Activity (the tracker's blocks), Tracked (time entries), and Calendar (time blocks and events from system calendars the user selects). Entries are drawn, moved, and resized here, and made from activity blocks, time blocks, and calendar events. The iPad's Calendar tab is the same view with the touch equivalents of [spec_ios.md](spec_ios.md) §10.2, without the open activity block, gap labels, or "Delete This Activity…"; the iPhone has no calendar view and never requests calendar access.

## 1. Layout

### 1.1 Toolbar and summary strip

The window title is "Calendar" and its subtitle the visible range, "Mon, Oct 26 – Fri, Oct 30 · W44" (ISO 8601 week; weeks run Monday to Sunday). The toolbar follows [spec_design.md](spec_design.md) §4, leading items first:

| Control | Behavior |
|---|---|
| ‹ › | Scroll by one day (with ⌥: by the number of visible days) |
| Date menu | Titled by what is shown: "Today" while today is visible, else the visible days ("Oct 19 – 23", "Oct 30 – Nov 3", "Oct 19"), like the range menu of Reports; holds Go to Today, which centers today (1.2), and Go to Date…, which opens a month picker whose chosen day becomes the first visible day |
| Days | Segmented control 1, 3, 5, 7; a count of 2, 4, or 6 (from ⌥⌘[ and ⌥⌘] or a pinch) shows as an extra segment |
| Columns | Menu (`rectangle.split.3x1`) with check-marked Activity Column and Calendar Column; Tracked has none |
| Zoom − + | Vertical zoom (1.3) |

In a narrow window Columns and zoom move into the toolbar's overflow menu first. The Calendar's settings are in the settings window and the iPad's Settings (section 6), not in the toolbar.

Below the toolbar a summary strip shows the visible days' tracked time as a bar stacked by project in area colors with its total, then "Time blocks 6h 20m" and "Activity 34h 10m" (the tracker's active time). Hovering a segment shows the project and its time.

### 1.2 Days and scrolling

A day column runs from midnight to midnight in the device's current time zone (23 or 25 hours on daylight-saving days). Entries and activity blocks never cross midnight. An external event or time block that does is drawn as one piece per day; dragging either piece moves the whole event.

The view is a horizontal strip of `visibleDays` (1 to 7, default 5) equal-width day columns filling the viewport, loaded as it moves, with no first or last day. Sideways scrolling snaps so that a day boundary meets the left edge. Today's header has a highlighted date and a tinted background. Today (⌘T) puts today at position ⌈visibleDays / 2⌉ from the left. Changing `visibleDays` keeps the leftmost day. A click on a day header makes it the first visible day; ⌥-click shows that day alone. The URL `timetracking://planner/calendar?date=YYYY-MM-DD` makes that day the first visible day. All days share one time axis and vertical scroll position; on opening, the current time sits one third down the viewport.

The router call `SectionRouter.showCalendar(day:hour:highlight:)` ([spec_projects.md](spec_projects.md) §1.3) selects this section, makes `day` leftmost, scrolls `hour` to the top (the day's first activity block when nil), turns the Activity column on, and pulses the block cards named by `highlight` (`BlockHighlight`: one hour of that day, or one context on that day) for 1.5 s. Nothing else changes, including `pointsPerHour` and `visibleDays`.

### 1.3 Vertical zoom

Zoom is `pointsPerHour`, 24 to 480, default 72. ⌘+ and ⌘− multiply or divide it by 1.25, a pinch changes it continuously, and ⌘0 restores 72. The time under the pointer (pinch) or at the viewport's center (keys, buttons) stays in place. Hour labels appear every two hours below 36 points per hour, every hour up to 120, every 30 minutes up to 240, and every 15 minutes above. A card under 14 points high is a bare color bar, under 28 points one line (title and duration).

### 1.4 Columns

| Column | Shown | Content | Width weight |
|---|---|---|---|
| Activity | Toggle, default on | Tracker blocks (section 3) | 1 |
| Tracked | Always | Time entries (section 2) | 2 |
| Calendar | Toggle, default on | Time blocks and external events (section 4) | 1.5 |

Each day gets the viewport width divided by `visibleDays`, split among its visible columns by weight. A column under 72 points draws its cards as bars with text on hover. The window's minimum width is 720 points. A day header shows weekday and date (`.headline`; today's date white on an accent-colored capsule), and an overlap warning (2.6). Below them each visible column's total sits above that column in `.caption` with monospaced digits, e.g. "6h 38m", "2h 21m", "1h", each led by its column's glyph (monitor, stopwatch, calendar) so every number names its column; a column under 72 points rounds its total to whole hours ("4h", "45m" below one hour) with the exact total in the tooltip; column names follow while the day is at least 240 points wide and the column at least 120. The Tracked total is in the primary color, the others in secondary. All-day events sit in a strip under the header over the Calendar column.

### 1.5 The now-line

Today's columns carry a 2 point accent line at the current time, with the time in a bubble in the axis gutter, updated every 30 seconds and when the window becomes key. The running entry and the open activity block end on it. The Tracked column below it is faintly hatched.

## 2. Tracked column

### 2.1 Cards

An entry card spans the column less 2 points per side, filled with its area color, text in the contrasting color of [spec_projects.md](spec_projects.md) §4.4. Lines (`.caption`, the task semibold): task, "Project · Client", stopwatch glyph with duration ("1h 33m"; the running entry "1:35:00"). Without a project the card is neutral gray with "No project"; an empty task reads "No task" in placeholder style. Minimum height 4 points. Hovering shows continue (▶) and edit (…) top right, in a space of their own so the text truncates before them; a card narrower than 140 points shows them bottom right when it is at least 64 points tall, else not at all. The running entry has a pulsing border and stop (■) instead of continue; its elapsed time updates every second while the window is key, else every 30 seconds, and its card follows the now-line and any library change at once.

### 2.2 No entries in the future

No part of an entry can lie after now. Gestures clamp at the now-line; a drop that would put an entry after now is refused (not-allowed badge, card returns); a press below the now-line draws nothing and shows "Entries can't be in the future" for 3 seconds.

### 2.3 Drawing

Dragging vertically in empty space draws a provisional entry. Both ends snap to `snapMinutes` (default 5), or 1 minute with ⌥, and stop at the now-line and midnight. Under 1 minute creates nothing (and deselects). Otherwise the entry stays with a dashed border and the Timer's edit popover ([spec_timer.md](spec_timer.md) §4) opens on it with the times filled in. Return commits (empty task and no project allowed); Escape removes it; a click elsewhere commits if a project or task was given and cancels otherwise. The minimum entry length everywhere is 1 minute.

### 2.4 Moving and resizing

Dragging a card's body moves it with its duration, the start snapping like drawing, with a time label showing the new start; dropping on another day's Tracked column moves it there, outside any Tracked column cancels. The top and bottom 6 points resize, down to 1 minute; the running entry has no bottom handle, and its start can move up to 1 minute before now. Cards cannot pass midnight or the now-line. Escape restores. Each move (`move(_:by:)`) or resize (`update(_:_:)`) is one undo step.

### 2.5 Selecting, editing, deleting

A click selects (2 point accent ring); ⇧-click or ⌘-click extends; Tab and ⇧Tab step through entries by start. Return or a double-click opens the edit popover, with its own overlap handling. Delete or ⌫ deletes the selection, undoable ("Undo Delete Entry"), with a notice "Deleted 'Clarify noise model' (1h 33m). Undo" for 8 seconds. Deleting the running entry asks "Discard the running entry?" first; undo restores it stopped at the deletion time. Duplicate to Next Day (⌘D) copies an entry to the same time next day as a stopped entry, refused unless that interval is entirely past. Split Here (context menu) splits at the pointer's snapped time with `split(_:at:)`, refused within 1 minute of either end; on the running entry the later part keeps running. Continuing an entry here stops the running one, as every library start does.

### 2.6 Overlaps

A drawing, move, resize, or duplicate that would overlap another entry (checked with `overlaps(for:excluding:)`) leaves the card in place with a warning badge and a popover:

```
Overlaps "Standup" (11:00 to 11:30) by 12 min.
[Trim]   [Overlap]   [Cancel]
```

Trim (default) shortens the changed entry to abut the neighbor; Overlap forces the change; Cancel (Escape) restores. An overlap of 1 minute or less is trimmed silently. Overlapping entries from any source are drawn side by side in start order, each with a ⚠ badge whose tooltip names the others and the minutes; the day header shows "⚠ 2 overlaps" ("⚠ 1 overlap" for one), and clicking it selects them.

## 3. Activity column

### 3.1 Blocks

The column shows the day's blocks from `ActivityReading`, plus on the Mac today's open block, which grows with the now-line. A card is a light neutral tint (`Color.activityBlock`, the secondary label color) with a 3 point left border in that color, the same for every context: the context colors of [spec_activity.md](spec_activity.md) §1.3 would mostly repeat the terminal's or the browser's color while line 1 names the project, and they would compete with the entries' area colors beside them. Line 1 is the group key as the Activity section names it ("paper (tmux)", "github.com/owner"; [spec_activity.md](spec_activity.md) §1.3), never the raw key; line 2 is the dominant item's subject and detail. Secondaries add a "+1" badge; `src` `knowledge` blocks are hatched; `src` `device` blocks carry a phone or tablet glyph by the platform of the `Device` named by `dev`; `dev` `remote` blocks carry a cloud glyph. Parts covered by entries are dimmed to 50% opacity. On the Mac, a gap over 15 minutes between blocks of any device shows its duration as a faint label ("22m", "1h 10m"), centered in the gap, with a thin vertical line above and below it to the gap's ends.

With Sleep or Workouts on (section 6), the health periods of the day ([spec_data_and_sync.md](spec_data_and_sync.md) §1.9) are 4 point lines centered in the column over their time, rounded at the ends: sleep dark blue, workouts dark green, on the Mac and the iPad. A night that crosses midnight shows on both days. A line lies under the blocks and over a gap's thin lines, and the gap's label stays readable on a background of its own over it. Its tooltip reads "Sleep 7h 10m" or "Workout 45m".

### 3.2 Hover popover

After 400 ms of hover a popover opens beside the block (left of it in the rightmost day):

- Time range, duration, device ("09:10 – 09:44 · 34m · MacBook"; `remote` reads "Other devices (Safari)"), the group key's name and share ("paper (tmux), 71% of this time"), "34m, 31m active" when `a` is less than the span, and for `src` `knowledge` "Reconstructed from macOS app usage history";
- Items in log order (app by name, a session as "paper (tmux)"; subject and detail; minutes), then secondaries ("In the background: Claude refactor-parser, 12m");
- "Create Entry…" (3.3).

It closes on Escape or when the pointer leaves block and popover. A click selects the block and keeps the popover open; Space on a selected block equals "Create Entry…".

### 3.3 Entries from a block

The hover "+" button, a drag into the Tracked column (vertical position ignored), "Create Entry…", and Space create a provisional entry over the block's longest untracked stretch, clamped at now, and open the edit popover with project and task empty.

### 3.4 Delete This Activity

On the Mac, a closed block's context menu has "Delete This Activity…". It asks "Delete this activity?" with the block's range and group key name ("09:10 – 09:44 · paper (tmux)") and "This removes it on every device and cannot be undone.", buttons Delete (destructive) and Cancel (default). Delete sends `delete-block <dev> <s>` to the tracker agent ([spec_activity_tracking.md](spec_activity_tracking.md) §7.3); the card disappears when the rewritten month file arrives, and an `error` answer shows in an alert titled "Couldn't Delete This Activity" with the app's sentence for the reply, never the reply itself. Entries are untouched.

## 4. Calendar column

### 4.1 Access and the time-block calendar

The Mac and the iPad request full EventKit access the first time the Calendar column is shown (usage text and entitlement: [spec_architecture.md](spec_architecture.md)). Without it the column shows a one-line notice with "Open System Settings", the rest works, and granting access fills the column without relaunch.

Time blocks are events in one calendar of the store's iCloud (CalDAV) source, so iCloud Calendar syncs them: "Time Blocks" unless the user chooses another (section 6). The synced settings `calendar.timeBlockCalendarID` and `calendar.timeBlockCalendarTitle` hold its identifier and title (no title means "Time Blocks"). A device resolves it by identifier, else by that title in the iCloud source, else by the identifier it resolved before, keeping the result in device state; only when all fail does it create "Time Blocks" (neutral gray; the user may recolor it) and write both settings. Without an iCloud calendar account the column says "Time blocks need an iCloud calendar account", drawing there is disabled, and external events still show. The view refetches the visible range plus one day on each side on `EKEventStoreChanged`, deduplicating its own writes.

### 4.2 Time blocks

A time block is an informational plan: the app creates, moves, resizes, edits, and deletes blocks, and nothing else (no done state, no comparison with tracked time). Scripts create blocks with any calendar tool. The store has no time-block entity and the CLI no block command.

| Event field | Meaning |
|---|---|
| `title` | Block title (shown like a task) |
| `url` | `timetracking://project/<uuid>` links a project |
| `notes` | Free notes; a line `Project: <name>` links by name |
| `startDate`, `endDate` | The interval |

A URL naming an existing project wins. Otherwise the first notes line `Project: <name>` (key case-insensitive, trimmed) links the single active project with that name, ignoring case and diacritics. Otherwise the block is unlinked, with the reason in its tooltip ("No project named “Admin”", "Several projects are named “Admin”", or "The linked project no longer exists" for a URL naming no project). The app writes only the URL, hides the `Project:` line, and never rewrites notes.

A block card is a light tint of its area color with a dashed 1.5 point area-color border, showing title, "Project · Client", and a calendar glyph with duration; unlinked blocks are gray. Drawing in empty space (as 2.3, not limited to the past) opens the block editor (title, project, start, end, notes); Return saves, Escape cancels. Blocks move and resize like entries, across days, unlimited by the now-line, and a block crossing midnight moves whole. Return or double-click opens the editor, which has Delete; Delete or ⌫ removes selected blocks, and ⌘Z saves an identical event again. Changes to a recurring event apply to that occurrence. Overlapping blocks and events sit side by side without warning.

### 4.3 External events

Events of the calendars checked under Calendars to show (section 6) are pale cards with the calendar's color as left border and title color, showing title, time range, and location. The checklist lists every event calendar except the time-block calendar with its account, none checked by default. The checked calendars are a synced list of (account title, calendar title) pairs, which name the same calendar on every device that has it: a device shows the checked calendars it has, and checking or unchecking one leaves the others in the list. External events are read-only; a double-click opens one in Calendar.app; the tooltip shows notes and attendee count.

### 4.4 Entries from blocks and events

Dragging a time block or event into the Tracked column, or its hover "+", creates a provisional entry over its interval clamped at now (refused when entirely future) and opens the edit popover with the title as task; a time block also supplies its linked project. The source is unchanged.

## 5. Context menus and keyboard

| Right-click on | Items |
|---|---|
| Entry | Continue, Edit…, Split Here, Duplicate to Next Day, Delete |
| Activity block | Create Entry…, Delete This Activity… (Mac, closed block) |
| Time block | Create Entry…, Edit…, Delete |
| External event | Create Entry…, Open in Calendar, Hide This Calendar |

The navigation keys (← → ⇧← ⇧→, Tab and ⇧Tab, Escape) are the view's own, as on every Mac, and are no menu items; they are off while a popover, editor, or sheet takes text input. ⌘T is View › Go to Today, and View › Previous Period and Next Period (⌥⌘← ⌥⌘→) and Go to Date… (⇧⌘D, the month picker) act on the Calendar too. Every other key is a menu item ([spec_timer.md](spec_timer.md) §9), enabled while the Calendar is shown: in the Entry menu Edit Selection…, Create Entry from Selection, Duplicate to Next Day, and Delete; and Move Earlier, Move Later, Lengthen, and Shorten; under View's Calendar header the zoom and day-count items and the two column toggles. Timer › Continue (⌘O) continues the one selected entry.

| Key | Effect |
|---|---|
| ⌘T | Today |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / reset |
| ⌥⌘[ / ⌥⌘] | One visible day fewer / more |
| ← / → | Previous / next day |
| ⇧← / ⇧→ | Back / forward by the visible span (Previous Days / Next Days) |
| ⌥⌘A / ⌥⌘K | Toggle the Activity / Calendar column |
| Tab / ⇧Tab | Next / previous entry by start |
| Return | Editor of the selected entry or block |
| Space | Entry from the selected activity block, time block, or event |
| ⌘↑ / ⌘↓ | Move the selection by one snap step |
| ⌥⌘↑ / ⌥⌘↓ | Lengthen / shorten the selection at its end by one snap step |
| Delete, ⌫ | Delete the selection (undoable) |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘D | Duplicate the selected entry to the next day |
| Escape | Cancel a drag, close a popover or editor, deselect |

## 6. Settings and view state

The Calendar's settings are the Calendar pane of the Mac's settings window ([spec_timer.md](spec_timer.md) §8) and the Calendar screen of the iPad's Settings ([spec_ios.md](spec_ios.md) §2.9), with the same four sections:

- Snap to (1, 5, 10, 15 minutes), footer "Entries and time blocks you draw, move, or resize start and end on this step.";
- Time blocks: a Calendar menu of the iCloud account's writable calendars by title, then a divider and "New Calendar…" (a new calendar "Time Blocks" in the iCloud account, "Time Blocks 2" and so on when the title is taken there). Choosing a calendar writes both settings of 4.1, so every device moves its time blocks to it; events already in the chosen calendar become time blocks. Without an iCloud account or access the row is text instead: "Time blocks need an iCloud calendar account" or "No calendar access". Footer "Time blocks are events in this iCloud calendar, so they appear on all your devices and in every calendar app.";
- Apple Health: toggles "Sleep" and "Workouts", each followed by an "In Reports" menu ("Not counted", a divider, then every area as "Client" for a general area and "Client · Area" otherwise, retired ones included), disabled while its toggle is off, which makes Reports count that kind as a project of the area ([spec_reports.md](spec_reports.md) §1.1); footer "Sleep and workouts appear as lines in the Activity column, and in Reports as a project of the area you choose. Your iPhone reads them from the Health app; open the app on your iPhone to allow it." While either toggle is on, a secondary line under the menus reports the iPhone's last import from the synced `calendar.healthImport` ([spec_data_and_sync.md](spec_data_and_sync.md) §1.9): "No iPhone has read Apple Health yet. Open the app on your iPhone to start." before any import; "Waiting for Alex's iPhone to read workouts. Open the app there." for a shown kind the last import did not read; "Alex's iPhone found no workouts in Apple Health (today at 7:12). If you have some, allow access on the iPhone in Settings › Privacy & Security › Health." for a read kind with no periods in the store (HealthKit reports a denied read as no data, so this is as close as the app gets to knowing access was denied); otherwise "Read from Alex's iPhone today at 7:12." ("yesterday at", "on Oct 30 at"). It re-reads when a setting or health period changes. The iPhone has the same toggles in its Settings and imports while either is on ([spec_ios.md](spec_ios.md) §7 item 6);
- Calendars to show (4.3), footer "Events of these calendars appear in the Calendar column." (without access: "The Calendar asks for calendar access the first time it shows its Calendar column."). On the Mac a 150 point list that scrolls, with one checkbox per calendar under a caption with its account, so the pane stays short however many calendars there are; on the iPad one toggle per calendar with its account below the title.

The settings read the calendars without asking for access; like the Calendar column, they resolve the time-block calendar (4.1), creating it when no device has.

| Synced setting | Default | Range |
|---|---|---|
| `calendar.snapMinutes` | 5 | 1, 5, 10, 15 |
| `calendar.shownCalendars` | none | (account title, calendar title) pairs |
| `calendar.timeBlockCalendarID` | unset | written by the app (4.1) |
| `calendar.timeBlockCalendarTitle` | unset ("Time Blocks") | written with the identifier (4.1) |
| `calendar.showSleep` | off | on, off |
| `calendar.showWorkouts` | off | on, off |
| `calendar.sleepAreaID`, `calendar.workoutAreaID` | none (not counted) | an area |
| `calendar.healthImport` | unset | written by the iPhone's import |

Per device: `pointsPerHour` (72), `visibleDays` (5), column toggles (on), the resolved time-block calendar. Each launch starts with today centered.

## 7. Testable behaviors

1. At 72 points per hour a 09:00 to 10:30 entry is 108 points high; after ⌘+ it is 135 with the center time unchanged; zoom clamps to [24, 480].
2. With today Thursday, ⌘T makes the first day Tuesday for 5 visible days, Monday for 7, Thursday for 1 and 2. The date menu reads "Today" while Thursday is visible, else "Oct 19 – 23", "Oct 30 – Nov 3", or for one day "Oct 19".
3. A sideways scroll of 1.4 day widths snaps one day over; `timetracking://planner/calendar?date=2026-10-29` makes October 29 the first day.
4. The column of the day daylight-saving time ends is 25 hours tall; a 23:00 to 01:00 event is drawn in two pieces that move together.
5. The now-line's offset is (now − midnight) · `pointsPerHour` / 3600 within 1 point, on today only.
6. Drawing 09:02 to 09:58 gives 09:00 to 10:00 (with ⌥, unchanged); under 1 minute creates nothing; Escape writes no record.
7. No draw, move, resize, or drop puts any part of an entry after now or past midnight; a press below the now-line shows the notice (2.2).
8. A 7 minute move with 5 minute snapping lands the start on a 5 minute mark with the duration kept; resizing stops at 1 minute.
9. A 12 minute overlap shows Trim / Overlap / Cancel with the 2.6 results; 1 minute or less is trimmed silently; overlapping entries are drawn at half width with "⚠ 2 overlaps".
10. Delete then ⌘Z restores the entry with the same id and fields; the running entry asks first and comes back stopped.
11. Split Here at 10:00 on 09:00 to 11:00 gives two abutting entries; at 10:59:30 it is refused. Duplicate to Next Day is refused when the copy would not be entirely past.
12. A block half covered by entries is dimmed on that half; device and remote blocks show their glyphs.
13. The "+" on a 09:10 to 09:44 block with its first 20 minutes covered opens the popover for 09:30 to 09:44.
14. A confirmed "Delete This Activity…" sends one `delete-block <dev> <s>`; Cancel sends nothing; the open block and the iPad do not offer it.
15. With no time-block calendar the app creates "Time Blocks" in the iCloud source and writes `calendar.timeBlockCalendarID`; a second device whose identifier lookup fails finds it by title.
16. A drawn time block is saved as an event with title, project URL, start, and end, and no store record; ⌘Z after Delete recreates it with the same fields.
17. Notes "Project: noise model" link the one active "Noise Model"; with two matches the block is unlinked and says "Several projects are named “noise model”"; a URL wins over the notes.
18. Dragging a 09:00 to 11:00 time block into Tracked at 10:00 opens the popover for 09:00 to 10:00 with its project and title; an event uses its title as task; external events cannot be moved or deleted.
19. Without calendar access, or without an iCloud calendar account, the column shows its notice and the rest of the view works.
20. The call `showCalendar(day: Oct 29, hour: 9, highlight: hour)` makes October 29 leftmost with 09:00 at the top, Activity on, the hour's blocks pulsed, zoom and day count unchanged.
21. Every key of section 5 has its effect; the arrows, Tab, and Escape are the view's keys, ⌘T and the period keys View menu items acting on the Calendar (⌥⌘→ by the visible span, ⇧⌘D opening the month picker), the rest items of the Entry menu and of View's Calendar header; ⌘O continues the one selected entry.
22. Snap to and Calendars to show are synced settings: with "Team" (Google) checked on another device, checking "Work" (iCloud) here stores both and unchecking it leaves "Team".
23. The Calendar menu lists the iCloud account's writable calendars and not a read-only one or another account's; choosing "Work" writes its identifier and title, and a device on which that identifier differs resolves "Work" by title; "New Calendar…" with "Time Blocks" taken creates "Time Blocks 2".
24. With Sleep on and Workouts off, a night from 23:00 to 06:30 is drawn on both of its days and a workout is not; turning Workouts on adds it, turning Sleep off removes the night.
25. The Apple Health status line: with both toggles off there is none; with no import status it says no iPhone has read Apple Health; after an import of sleep alone, with Workouts on it waits for workouts; with both read and no workout periods it says none were found; with periods of every shown kind it says when it read them; the status syncs from the iPhone.

## 8. Decisions

- One time axis for activity, entries, and plans, so the three compare at a glance.
- Snap to 5 minutes: drawing sets the shape, the popover the exact times.
- Overlaps are allowed but confirmed, so every stored overlap is deliberate.
- Blocks are shown as recorded; deleting one goes through the agent, the log's only writer.
- Time blocks are iCloud calendar events: synced and scriptable without app code, and informational only.
- The URL is the authoritative project link because it survives renames.
- The Calendar's settings are in the settings window, like every other setting, and synced, so the Mac and the iPad show the same calendars without a per-device setup.

## 9. Interfaces

From [spec_data_and_sync.md](spec_data_and_sync.md): `TimeStoreWriting` (entry writes, `transaction(_:)`, `set(_:_:)`), `TimeStoreReading` (`entries(in:)`, `runningEntry()`, `overlaps(for:excluding:)`, `overlappingEntries(in:)`, `distinctTasks`), `StructureReading`, `StoreObserving`, `ActivityReading` (blocks, the open block, `detail(for:)` on the recording Mac, changes), and the `activity.contextColors` assignment.

From [spec_activity_tracking.md](spec_activity_tracking.md): the log formats and the `delete-block` command.

From [spec_projects.md](spec_projects.md): `SectionRouter`, the project picker, the area color derivations.

From [spec_timer.md](spec_timer.md): the edit popover, opened on a prefilled draft; the settings window, which shows the Calendar pane.

From [spec_ios.md](spec_ios.md): the iPad's Settings, which shows the Calendar screen.

From [spec_activity.md](spec_activity.md): `BlockHighlight`.

From [spec_architecture.md](spec_architecture.md): the calendar usage text and entitlement.

Provided: the `timetracking://planner/calendar?date=` handler and `showCalendar` (1.2).
