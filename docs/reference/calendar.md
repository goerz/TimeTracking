# Spec: Calendar Section

The Calendar section shows days side by side on one time axis, so activity, entries, and plans compare at a glance. Each day has up to three columns: Activity (the tracker's blocks), Tracked (time entries), and Calendar (time blocks and events from system calendars the user selects). Entries are drawn, moved, and resized here, and made from activity blocks, time blocks, and calendar events. The iPad's Calendar tab is the same view with the touch equivalents of [ios.md](ios.md) §10.2, without the open activity block, gap labels, or "Delete This Activity…"; the iPhone has no calendar view and never requests calendar access.

## 1. Layout

### 1.1 Toolbar and summary strip

The subtitle names the shown days with their ISO 8601 week, "Mon, Oct 26 – Fri, Oct 30 · W44"; a day counts as shown while at least half of it is in view. The toolbar ([design.md](design.md) §4) has ‹ › (one day back or forward, snapped so that a day starts at the left edge; with ⌥ by the whole days in view), a date menu, and the Filters and search of Reports (1.6). The date menu reads "Today" while today is shown, else the shown days ("Oct 19 – 23", "Oct 30 – Nov 3", "Oct 19"), and holds Go to Today and Go to Date…, a month picker whose chosen day goes to the left edge.

Below the filter bar, a summary strip covers the shown days: "Tracked" with its total and a bar stacked by project in area colors, "Time blocks 6h 20m", "Activity 34h 10m" (the tracker's active time), and at the trailing end the day width slider.

### 1.2 Days and scrolling

A day column runs from Midnight to Midnight ([data_and_sync.md](data_and_sync.md) §8), 00:00 by default, in the device's current time zone, so it is 23 or 25 hours tall on daylight-saving days. The hour labels start at that hour, and today is the shown day that contains now: with Midnight at 04:00, 02:00 on Tuesday still belongs to Monday. Weeks run Monday to Sunday.

Anything that crosses the day change (an entry, an activity block when Midnight is not 00:00, an external event, a time block) is drawn as one piece per day. Dragging a piece of an entry or time block moves the whole; an entry's edges resize it within the piece's column, and its totals count each piece on its own day. An activity block counts whole on the day of its start.

The strip has no first or last day and loads the days around the view as it moves. Every day is `dayWidth` points wide, from 96 to 1600 (default 260), so the window's width decides how many days show, and the days at either edge may be cut off. The logarithmic slider, ⌥⌘[ and ⌥⌘] (a factor of 1.25), and a horizontal pinch on the iPad change it, keeping the time at the viewport's center in place.

A trackpad's sideways swipe, ⇧ with a mouse wheel, a drag on the day headers, and on the iPad a sideways swipe move through time without snapping; a trackpad gesture that starts mostly up or down scrolls the hours only. The arrows and ← → snap: forward to the next day start, back to the start of a cut-off leftmost day, else to the day before, and a trackpad's momentum stops there. ⇧← ⇧→ and ⌥ with the arrows step by the whole days in view.

Today (⌘T), and every launch, puts today at position ⌈n / 2⌉ from the left of the `n` whole days in view, with a day starting at the left edge. A new window width keeps the left edge. A click on a day header's weekday and date slides that day to the left edge, and ⌥-click shows it alone, as wide as the viewport. The URL `timetracking://planner/calendar?date=YYYY-MM-DD` moves that day to the left edge. Today has a highlighted header and a tint; Saturday and Sunday are shaded. All days share one vertical scroll position; on opening, the current time sits one third down the viewport from the first frame, so nothing scrolls when the data arrives.

The router's `showCalendar(day:hour:highlight:)` ([projects.md](projects.md) §1.3) moves `day` to the left edge, scrolls `hour` to the top (the day's first activity block when nil, else 08:00), turns the Activity column on, and pulses the block cards of `highlight` (one hour of that day, or one context on that day) for 1.5 s. Both zooms stay as they are.

### 1.3 Vertical zoom

Zoom is `pointsPerHour`, 24 to 480, default 72. ⌘+, ⌘−, and the zoom buttons over the columns multiply or divide it by 1.25, a pinch changes it continuously, and ⌘0 restores 72. A zoom keeps one time where it was on screen: under the fingers for a pinch, else the now-line while it is in view, else the time at the viewport's center; only the end of the day can stop it.

Hour labels appear every two hours below 36 points per hour, every hour up to 120, every 30 minutes up to 240, and every 15 minutes above. A card under 14 points high is a bare color bar, under 28 points one line (title and duration); an entry card also keeps to the one line while its three lines don't fit. No card draws outside its time range.

### 1.4 Columns

The day's width is split among its visible columns by weight: Activity 1, Tracked 2, Calendar 1.5. Tracked always shows; Activity and Calendar are toggles, default on. Each column's glyph in the day header is its toggle, and a hidden column leaves its glyph, struck through, at its edge of the Tracked cell ("Show Calendar Column"). View › Show Activity Column (⌥⌘A) and Show Calendar Column (⌥⌘K) do the same.

A day header shows weekday and date, an overlap warning (2.6), and above each visible column its total, led by the column's glyph so every number names its column: "6h 38m", "2h 21m", "1h". A column under 72 points rounds its total to whole hours ("4h"; "45m" below one hour) and draws activity cards without text; one under 50 points shows only the glyph, and the exact total is in the tooltip. Column names follow while the day is at least 240 points wide and the column at least 120. All-day events sit in a strip under the header: a column named D shows the all-day events of date D, whatever Midnight is.

### 1.5 The now-line

Today's columns carry an accent line at the current time, with the time in a bubble in the axis gutter, updated every 30 seconds. The running entry and the open activity block end on it, and the Tracked column below it is faintly hatched.

### 1.6 Filters and search

The Filters, the filter bar, and the search field are those of Reports ([reports.md](reports.md) §3, §3.1). The Calendar keeps its own filters (per device; the search is not stored). An entry they leave out stays in place, faded to 25% opacity, and still selectable, editable, and in the overlap checks; the tracked totals count only the entries they let through. Activity blocks, time blocks, and events are unaffected. While the search field has the focus, the view's plain keys are off.

## 2. Tracked column

### 2.1 Cards

An entry card is filled with its area color, text in the contrasting color of [projects.md](projects.md) §4.4, and has three lines: task, "Project · Client", and a stopwatch glyph with the duration ("1h 33m"; the running entry "1:35:00"). Without a project the card is neutral gray with "No project"; an empty task reads "No task" in placeholder style. Hovering shows continue (▶) and edit (…), space permitting. The running entry has a border in its text color and stop (■) instead of continue, and its time updates every second.

### 2.2 No entries in the future

No part of an entry can lie after now. Gestures clamp at the now-line. A drop on a day where the entry cannot fit before now is refused, and a press below the now-line draws nothing; both show "Entries can't be in the future" for 3 seconds.

### 2.3 Drawing

Dragging vertically in empty space draws a provisional entry. Both ends snap to `snapMinutes` (default 5), or 1 minute with ⌥, counted from the column's start, and stop at the now-line and the column's ends. Under 1 minute creates nothing and deselects. Otherwise the entry stays with a dashed border and a popover opens on it, showing its times with the project chip, the task field, Cancel, and Save. Return commits (empty task and no project allowed); Escape removes it; a click elsewhere commits if a project or task was given and cancels otherwise. A draft is stored once, also when several of these come together. The minimum entry length everywhere is 1 minute.

### 2.4 Moving and resizing

Dragging a card's body moves it with its duration, the start snapping like drawing, with a time label showing the new start while the pointer is over a Tracked column; dropping on another day's Tracked column moves it there, outside any Tracked column cancels. The top and bottom 6 points resize, down to 1 minute and snapping the same way; the running entry has no bottom handle, and its start can move up to 1 minute before now. Cards cannot pass the column's ends or the now-line, except that an entry crossing the day change, which no column holds, moves whole and only the now-line limits it. An entry dragged across the real midnight inside a column stays one entry. Escape during a drag restores the card, and the rest of the drag does nothing. Each move or resize is one undo step.

### 2.5 Selecting, editing, deleting

A click selects at once, by the keys held for that click; ⇧-click or ⌘-click extends, on every kind of card; Tab and ⇧Tab step through entries by start. Return or a double-click opens the Timer's edit popover ([timer.md](timer.md) §4). Delete or ⌫ deletes the selection, undoable, with the notice "Deleted 'Clarify noise model' (1h 33m). Undo" for 8 seconds. Deleting the running entry asks "Discard the running entry?" first; undo restores it stopped at the deletion time.

Duplicate to Next Day (⌘D) copies an entry to the same time next day as a stopped entry, refused unless that interval is entirely past. Split Here splits at the entry's snapped midpoint, refused within 1 minute of either end; on the running entry the later part keeps running.

### 2.6 Overlaps

Overlaps are allowed but confirmed, so every stored overlap is deliberate. A drawing, move, resize, or duplicate that would overlap another entry leaves the card in place with a popover:

```
Overlaps "Standup" (11:00 to 11:30) by 12 min.
[Trim]   [Overlap]   [Cancel]
```

Trim (default) shortens the changed entry to abut the neighbor; Overlap forces the change; Cancel (Escape) restores. An overlap of 1 minute or less is trimmed silently. Overlapping entries from any source are drawn side by side in start order, each with a ⚠ badge whose tooltip names the others and the minutes; the day header shows "⚠ 2 overlaps" ("⚠ 1 overlap" for one), and clicking it selects them.

## 3. Activity column

### 3.1 Blocks

The column shows the day's blocks, plus on the Mac today's open block. A card is a light neutral tint, the same for every context: context colors ([activity.md](activity.md) §1.3) would mostly repeat the terminal's or the browser's color and compete with the entries' area colors beside them. Line 1 is the dominant workspace as the Activity section names it ("paper (tmux)"), line 2 the dominant item's subject and detail. Background items add a "+1" badge. A block mostly reconstructed from macOS app usage history (`rec` over half of `a`) is hatched, one with time on an iPhone or iPad carries a phone glyph, and one with `remote` time a cloud glyph. Parts covered by entries are dimmed to 50% opacity. On the Mac, a gap over 15 minutes between blocks of any device shows its duration as a faint label ("22m").

Background stretches ([activity_tracking.md](activity_tracking.md) §2.7) are thin strips at the column's trailing edge over their time, in a gap and never on a block. The tooltip names their items ("In the background while away: Claude refactor-parser 38m"); they have no popover and make no entry.

With Sleep or Workouts on (section 6), the health periods ([data_and_sync.md](data_and_sync.md) §1.9) are thin lines centered in the column over their time, sleep dark blue and workouts dark green. A period that crosses Midnight shows on both days. A line lies under the blocks and over a gap's thin lines. A period's whole duration is a label ("7h 10m") centered on its line on the day it ends, so a night is labeled on the morning it ends; a gap label within 16 points of it is left out. The tooltip reads "Sleep 7h 10m" or "Workout 45m".

### 3.2 Block popover

A click selects the block and opens a popover beside it; ⇧-click or ⌘-click extends the selection (2.5) without one. It shows the time range, duration, and device ("09:10 – 09:44 · 34m · MacBook"; with several devices each with its time; `remote` reads "Other devices (Safari)"), the dominant workspace's share ("paper (tmux), 71% of this time"), "34m, 31m active" when `a` is less than the span, and any reconstructed time ("12m reconstructed from macOS app usage history"). Below come the items in log order, the background items, and "Create Entry…".

### 3.3 Entries from a block

The hover "+" button, a drag into the Tracked column (vertical position ignored), "Create Entry…", and Space on a selected block create a provisional entry over the block's longest untracked stretch, clamped at now, and open its popover (2.3) with project and task empty.

### 3.4 Delete This Activity

Blocks are shown as recorded, and deleting one goes through the agent, the log's only writer. On the Mac, a closed block's context menu has "Delete This Activity…". It asks "Delete this activity?" with the block's range and workspace name and "This removes it on every device and cannot be undone.", with Cancel as the default. Delete sends `delete-block <s> <e>` with the shown range to the tracker agent ([activity_tracking.md](activity_tracking.md) §7.3); the card disappears when the rewritten month file arrives, and an `error` answer shows in an alert titled "Couldn't Delete This Activity" with the app's sentence for the reply, never the reply itself. Entries are untouched.

## 4. Calendar column

### 4.1 Access and the time-block calendar

The Mac and the iPad request full EventKit access the first time the Calendar column is shown. Without it the column shows a one-line notice with "Open System Settings" and the rest works; granting access fills the column without relaunch.

Time blocks are events in one calendar of the store's iCloud (CalDAV) source, so they sync and can be scripted without app code: "Time Blocks" unless the user chooses another (section 6). The synced settings `calendar.timeBlockCalendarID` and `calendar.timeBlockCalendarTitle` name it. A device resolves it by identifier, else by that title in the iCloud source, else by the identifier it resolved before; only when all fail does it create "Time Blocks" and write both settings. Without an iCloud calendar account the column says "Time blocks need an iCloud calendar account", drawing there is disabled, and external events still show. The view reloads on `EKEventStoreChanged`.

### 4.2 Time blocks

A time block is an informational plan: the app creates, moves, resizes, edits, and deletes blocks, and nothing else (no done state, no comparison with tracked time). Scripts create blocks with any calendar tool. The store has no time-block entity and the CLI no block command.

The event's `title` is the block title, and its `startDate` and `endDate` the interval. A `url` of `timetracking://project/<uuid>` naming an existing project links it, and wins because it survives renames. Otherwise the first `notes` line `Project: <name>` (key case-insensitive, trimmed) links the single active project with that name, ignoring case and diacritics. Otherwise the block is unlinked, with the reason in its tooltip ("No project named “Admin”", "Several projects are named “Admin”", or "The linked project no longer exists"). The app writes only the URL and never rewrites notes.

A block card is a light tint of its area color with a dashed area-color border, showing title, "Project · Client", and a calendar glyph with duration; unlinked blocks are gray. Drawing in empty space (as 2.3, not limited to the past) opens the block editor (title, project, start, end, notes); Return in the title saves, and Escape or a click outside cancels. Blocks move and resize like entries (2.4), with the time label, ⌥, and Escape, across days, unlimited by the now-line; a block crossing the day change moves whole, and a drop outside any Calendar or Tracked column cancels. Return or double-click opens the editor, which has Delete; Delete or ⌫ removes selected blocks, and ⌘Z saves an identical event again. Changes to a recurring event apply to that occurrence. Overlapping blocks and events sit side by side without warning.

### 4.3 External events

Events of the checked calendars (section 6) are pale cards in the calendar's color, showing title, time range, and location. The checked calendars are a synced list of (account title, calendar title) pairs, which name the same calendar on every device that has it: a device shows the checked calendars it has, and checking or unchecking one leaves the others in the list. External events are read-only; a double-click opens one in Calendar.app; the tooltip shows notes and attendee count.

### 4.4 Entries from blocks and events

Dragging a time block or event into the Tracked column, or its hover "+", creates a provisional entry over its part on the day of its start, clamped at now (refused when entirely future), and opens the popover (2.3) with the title as task; a time block also supplies its linked project. The source is unchanged.

## 5. Context menus and keyboard

| Right-click on | Items |
|---|---|
| Entry | Continue, Edit…, Split Here, Duplicate to Next Day, Delete |
| Activity block | Create Entry…, Delete This Activity… (Mac, closed block) |
| Time block | Create Entry…, Edit…, Delete |
| External event | Create Entry…, Open in Calendar, Hide This Calendar |

The navigation keys (← → ⇧← ⇧→, Tab and ⇧Tab, Escape) are the view's own, as on every Mac, and are off while a popover, editor, or sheet takes text input. Every other key is an item of the Entry menu, of the View menu's Calendar header, or of its shared period commands ([timer.md](timer.md) §9), enabled while the Calendar is shown.

| Key | Effect |
|---|---|
| ⌘T | Today |
| ⌥⌘← / ⌥⌘→ | Previous / Next Period, by the whole days in view |
| ⇧⌘D | Go to Date… |
| ⌘+ / ⌘− / ⌘0 | Zoom in / out / reset |
| ⌥⌘[ / ⌥⌘] | Narrower / wider days |
| ← / → | Previous / next day, snapped |
| ⇧← / ⇧→ | Back / forward by the whole days in view |
| ⌥⌘A / ⌥⌘K | Toggle the Activity / Calendar column |
| ⌘F | Focus the search field |
| ⌥⌘F / ⌥⇧⌘F | Filters… / Clear Filters |
| Tab / ⇧Tab | Next / previous entry by start |
| Return | Editor of the selected entry or block |
| Space | Entry from the selected activity block, time block, or event |
| ⌘↑ / ⌘↓ | Move the selection by one snap step |
| ⌥⌘↓ / ⌥⌘↑ | Lengthen / shorten the selection at its end by one snap step |
| Delete, ⌫ | Delete the selection (undoable) |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘D | Duplicate the selected entry to the next day |
| ⌘O | Continue the one selected entry |
| Escape | Close a popover or editor, deselect |

## 6. Settings and view state

The Calendar's settings are synced ([data_and_sync.md](data_and_sync.md) §1.6), so the Mac and the iPad show the same calendars without a per-device setup. They are the Calendar pane of the Mac's settings window ([timer.md](timer.md) §8) and the Calendar screen of the iPad's Settings ([ios.md](ios.md) §2.9), with four sections:

- Snap to: 1, 5, 10, or 15 minutes.
- Time blocks: a Calendar menu of the iCloud account's writable calendars, then "New Calendar…" ("Time Blocks", or "Time Blocks 2" and so on when the title is taken). Choosing a calendar moves every device's time blocks to it, and events already in it become time blocks. Without an iCloud account or access the row says so.
- Apple Health: toggles "Sleep" and "Workouts", each with an "In Reports" menu ("Not counted", then every area, retired ones included) that makes Reports count that kind as a project of the area ([reports.md](reports.md) §1.1). The iPhone has the same toggles and imports while either is on ([ios.md](ios.md) §7 item 6).
- Calendars to show (4.3): every event calendar except the time-block calendar, with its account, none checked by default.

While either health toggle is on, a line reports the iPhone's last import from `calendar.healthImport` ([data_and_sync.md](data_and_sync.md) §1.9): that no iPhone has read Apple Health yet; "Waiting for Alex's iPhone to read workouts. Open the app there." for a shown kind the last import did not read; "Alex's iPhone found no workouts in Apple Health (today at 7:12). If you have some, allow access on the iPhone in Settings › Privacy & Security › Health." for a read kind with no periods in the store, since HealthKit reports a denied read as no data; otherwise "Read from Alex's iPhone today at 7:12."

The settings read the calendars without asking for access; like the Calendar column, they resolve the time-block calendar (4.1), creating it when no device has. Per device the view keeps `pointsPerHour`, `dayWidth`, the column toggles, the Filters, and the resolved time-block calendar.

## 7. Testable behaviors

1. At 72 points per hour a 09:00 to 10:30 entry is 108 points high; after ⌘+ it is 135, with the now-line in place while in view, else the center time, else the time under a pinch; zoom clamps to [24, 480] and never scrolls past the end of the day.
2. With today Thursday and room for 5 whole days, ⌘T makes the first day Tuesday, Monday for 7, Thursday for 1 and 2, with a day starting at the left edge; a cut-off day does not count. The date menu reads "Today" while Thursday is shown, else "Oct 19 – 23", "Oct 30 – Nov 3", or for one day "Oct 19"; the subtitle names the days at least half visible.
3. A sideways scroll of 1.4 day widths moves 1.4 days without snapping and loads the days that come into view; → then goes to the next day start, ← from a cut-off day to its start; `timetracking://planner/calendar?date=2026-10-29` moves October 29 to the left edge.
4. The column of the day daylight-saving time ends is 25 hours tall; a 23:00 to 01:00 event is drawn in two pieces that move together.
5. The now-line's offset is (now − the column's start) · `pointsPerHour` / 3600 within 1 point, on today only.
6. Drawing 09:02 to 09:58 gives 09:00 to 10:00 (with ⌥, unchanged); under 1 minute creates nothing; Escape writes no record.
7. No draw, move, resize, or drop puts any part of an entry after now or past the column's end; a press below the now-line shows the notice (2.2).
8. A 7 minute move with 5 minute snapping lands the start on a 5 minute mark with the duration kept; resizing stops at 1 minute.
9. A 12 minute overlap shows Trim / Overlap / Cancel with the 2.6 results; 1 minute or less is trimmed silently; overlapping entries are drawn at half width with "⚠ 2 overlaps".
10. Delete then ⌘Z restores the entry with the same id and fields; the running entry asks first and comes back stopped.
11. Split Here on 09:00 to 11:00 gives two entries abutting at 10:00; a split at 10:59:30 is refused. Duplicate to Next Day is refused when the copy would not be entirely past.
12. A block half covered by entries is dimmed on that half; blocks with iPhone or iPad time show the phone glyph, those with remote time the cloud glyph.
13. The "+" on a 09:10 to 09:44 block with its first 20 minutes covered opens the popover for 09:30 to 09:44.
14. A confirmed "Delete This Activity…" sends one `delete-block <s> <e>`; Cancel sends nothing; the open block and the iPad do not offer it.
15. With no time-block calendar the app creates "Time Blocks" in the iCloud source and writes `calendar.timeBlockCalendarID`; a second device whose identifier lookup fails finds it by title.
16. A drawn time block is saved as an event with title, project URL, start, and end, and no store record; ⌘Z after Delete recreates it with the same fields.
17. Notes "Project: noise model" link the one active "Noise Model"; with two matches the block is unlinked and says "Several projects are named “noise model”"; a URL wins over the notes.
18. Dragging a 09:00 to 11:00 time block into Tracked at 10:00 opens the popover for 09:00 to 10:00 with its project and title; an event uses its title as task; external events cannot be moved or deleted.
19. Without calendar access, or without an iCloud calendar account, the column shows its notice and the rest of the view works.
20. The call `showCalendar(day: Oct 29, hour: 9, highlight: hour)` makes October 29 leftmost with 09:00 at the top, Activity on, the hour's blocks pulsed, zoom and day width unchanged.
21. Every key of section 5 has its effect; the arrows, Tab, and Escape are the view's keys, ⌘T and the period keys View menu items acting on the Calendar (⌥⌘→ by the visible span, ⇧⌘D opening the month picker), the rest items of the Entry menu and of View's Calendar header; ⌘O continues the one selected entry.
22. Snap to and Calendars to show are synced settings: with "Team" (Google) checked on another device, checking "Work" (iCloud) here stores both and unchecking it leaves "Team".
23. The Calendar menu lists the iCloud account's writable calendars and not a read-only one or another account's; choosing "Work" writes its identifier and title, and a device on which that identifier differs resolves "Work" by title; "New Calendar…" with "Time Blocks" taken creates "Time Blocks 2".
24. With Sleep on and Workouts off, a night from 23:00 to 06:30 is drawn on both of its days and a workout is not; turning Workouts on adds it, turning Sleep off removes the night.
25. The Apple Health status line: with both toggles off there is none; with no import status it says no iPhone has read Apple Health; after an import of sleep alone, with Workouts on it waits for workouts; with both read and no workout periods it says none were found; with periods of every shown kind it says when it read them; the status syncs from the iPhone.
26. The activity column has the day's background stretches, each named by its items and their time ("In the background while away: Claude refactor-parser 38m").
27. With a day width of 250 points, a 1000 point viewport shows 4 days and a 1100 point one 5, the fifth cut off, with the left edge kept; doubling the day width keeps the center time; the width clamps to [96, 1600]; ⌥-click makes one day as wide as the viewport; the slider is logarithmic; Saturday and Sunday are the shaded days.
28. With "Noise Model" checked in Filters, the other entries are faded and the tracked totals count only Noise Model's, with its token in the filter bar; the search "draft" lets through only entries with "draft" in the task or the project, area, or client name; while the search field has the focus the plain keys are off.
29. A night from 23:00 to 06:30 is labeled "7h 30m" on the day it ends; a workout from 23:15 to midnight is labeled "45m" on its own day.
30. At 72 points per hour a 33-minute entry's card spans exactly its interval and shows its title and duration on one line; a 25-minute running entry's card ends on the now-line.
31. Two commits of one draft arriving together (Return and Save, or Return and a click elsewhere) store one entry.
32. A reload that finishes after a later one changes nothing, and the days count as loaded only once their data is in.
33. With Midnight at 04:00, a column starts at 04:00; an entry from 03:00 to 05:00 is in the columns of both days, each total counting its hour; a drag of the later piece down an hour moves the entry to 04:00 to 06:00; a block from the night reaches both columns and counts on the day of its start; a heatmap click at 09:00 scrolls five hours below the column's top.
34. With Midnight at 04:00, dragging an entry across the real midnight inside a column keeps one entry, and one undo restores it.
35. With Midnight at 04:00 or at 22:00, an all-day event on March 14 is in the strip of the column named March 14 and no other; an event spanning March 14 and 15 is in both.
36. With Midnight at 04:00, a block from 03:30 to 04:30 with an entry over 04:10 to 04:20 is dimmed 10 minutes below the top of its card in the later column and not at all in the earlier one.
37. A click on a card selects it alone; ⇧-click and ⌘-click add a card of any kind to the selection and take a selected one out; ⌥-click selects like a plain click; a block's popover opens on a plain click only.
38. A 7 minute move with ⌥ moves the start 7 minutes; the time label shows the start the drop would give; Escape during a drag leaves the entry and the selection as they were, and the next drag works; a drop on an Activity or Calendar column, on the time axis, or above the columns in view changes nothing; a drop on the next day's Tracked column moves the entry there.
39. A time block linked to "Noise Model" of "University" shows "Noise Model · University" in its area's color with no entry of the project loaded; an unlinked block has no project line.
40. Dragging a 14:00 to 15:00 block onto the next day's Calendar column one hour down gives 15:00 to 16:00 there, also past the now-line, in one undo step; a 7 minute move snaps to 5 minutes, with ⌥ to the minute; its piece after the day change moves it whole; its edges resize it within the piece's column, down to 1 minute; Escape during a drag changes nothing.
41. The hover "+" of a time block or event opens the popover of 4.4, and a time block dropped on a Tracked column does the same.
42. An entry from 23:00 to 01:00 is in the columns of both days; dragging either piece moves it whole, ⌘↓ moves it one snap step, and ⌥⌘↓ lengthens it at its end.
