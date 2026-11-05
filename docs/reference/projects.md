# Sections and Projects

This spec covers the four sections of the main window after the Timer (Calendar, Reports, Projects, Activity) and their router, and the Projects section: the projects table with its clients and areas, the project dialog, the area colors, and the shared project picker. Entities and their store rules are in [data_and_sync.md](data_and_sync.md) §1.

## 1. The sections

### 1.1 Layout

The sections are the main window's sidebar items after the Timer ([timer.md](timer.md) §1), in the order Calendar, Reports, Projects, Activity: the views used daily first, then the rarely edited projects, clients, and areas, then the tracker's log. Each section owns its toolbar items, placed by the scheme of [design.md](design.md) §4, so the period arrows keep their place when the section changes. The sections have no running-timer controls, and a section's minimum size is 620 × 560 pt.

At launch the main window shows the Timer. Per device the app remembers the window's frame, the last selected section, and each section's view state: for Projects its date range, filters, grouping, sort, columns, and collapsed groups, but not the search text.

### 1.2 Commands

View has the sidebar's items (⌘1 to ⌘5, always available), Show/Hide Sidebar (⌃⌘S), and each section's display options under its header. Go to Today (⌘T), Previous and Next Period (⌥⌘← ⌥⌘→; in the Calendar by the visible span), and Date Range… (⇧⌘D; in the Calendar Go to Date…) apply in the Calendar, Reports, and Activity, and on the Mac in Projects. Edit › Find (⌘F) focuses the search field of the Calendar, Reports, or Projects. The Entry menu acts on the selected entry in the Calendar and the Reports entry list, the Project menu on the selected row in Projects (2.5).

The menus are the same in every window and view ([timer.md](timer.md) §9): a section's command is listed while another view is shown, disabled and without its key equivalent, so the Timer's commands on the same keys (⌘E, ⌘⌫, ⌘F) reach the Timer, and the reverse.

### 1.3 Router

The `SectionRouter` shows the main window if needed, selects a section, and passes it a request; no section changes another's state directly.

| Request | Effect |
|---|---|
| `showProjects()` | Selects Projects with its current view state. Target of `timetracking://planner/projects` |
| `showProject(id)` | Selects Projects, clears the search, turns "Include archived projects" on for an archived project, clears filters that hide it, selects All time when the range hides it, selects and scrolls to its row. Target of `timetracking://project/<uuid>` |
| `showCalendar(day:hour:highlight:)` | [calendar.md](calendar.md) §1.2 |
| `showReports(range:filter:)` | [reports.md](reports.md) §9 |
| `showActivity(range:)` | Selects Activity with the shared Reports/Activity range |
| `showTrackerSettings(exclusion:)` | Opens Settings on the Tracker pane, with an exclusion prefilled if given |

### 1.4 iPad

The sections are tabs ([ios.md](ios.md) §10). In Projects, a Sort menu after Filters replaces header clicks, and long press opens context menus.

## 2. The projects table

The subtitle is the range label ("All time · since Mar 4, 2019"), and the toolbar is that of Reports on the section's own range (2.4). Below is a table with client, area, or group rows above their projects, and a ⋯ button on the hovered project row. The bar below the table holds New (a click is New Project…, its menu adds New Area… and New Client…), the status text, the selection count, and "Group by".

### 2.1 Columns

Project shows a dot in the area's color and the name; an archived project is in secondary label color with its dot at 50% opacity. Client and Area follow, a general area (4.1) showing the client's name in secondary label color. State ("Active" or "Archived") shows only while archived projects are included. Created is `createdAt`. Last tracked is the start of the most recent entry, running entry included, or "Never". Total tracked sums the entries in the range in unbounded hours ("432h 21m"; on a client, area, or group row, of its projects shown), the running entry counting to now, refreshed once a minute.

A client row shows the client's name in semibold, an area row a swatch, the name, and a "general" or "retired" tag. Dates read "Today", "Yesterday", the weekday within the last 7 days, "Oct 27" within the current year, "2024" otherwise, by the shown days of the Midnight setting ([data_and_sync.md](data_and_sync.md) §8); the tooltip shows the full date. The header's context menu toggles every column but Project; column order is fixed.

### 2.2 Sorting

Clicking a header sorts by it, a second click reverses (State is not sortable). Default: Name ascending. With grouping, the sort applies within groups. Names sort case- and diacritic-insensitively, Area by client name and area order (4.3), Created and Last tracked by instant with "Never" last in both directions. The project name breaks every remaining tie.

### 2.3 Grouping

Group by offers Client and Area (default), Client, and None. Client and Area shows a row per client by name, under it a row per area in order (general first), and under each area its projects. Client shows "Consulting · 3 projects" above the client's projects.

Under Client and Area, over All time and without a search or filter, every client and every area is listed, also without projects shown, so a new area can take its first project; a retired area only while archived projects are included. Otherwise, and under Client, only groups with projects shown are listed. Projects whose area was deleted elsewhere follow in a "(deleted area)" group.

Client, area, and group rows collapse with their triangle, with ← and → on a selected row (or the group of selected projects), and all at once with ⌥-click; the collapsed set is remembered per grouping.

### 2.4 Filtering

The date range, the Filters popover, and the search combine with AND.

The range has the presets, arrows, date popover, View commands, and shown days of Reports ([reports.md](reports.md) §2) but is the section's own, stored per device, default All time. All time lists every project, also those never tracked; any other range lists only the projects with an entry in it, and Total tracked sums those entries. Created and Last tracked stay whole-history dates, so sorting by Last tracked finds the projects tracked longest ago.

The Filters popover has the tree, the "Include archived projects" check box, and "Clear All", as in Reports ([reports.md](reports.md) §3). Here "Include archived projects" is off by default and, since it only widens the table, does not count in the title ("Filters (1)").

The filter tree lists clients by name, each with its areas in order (general first, named after the client); Reports adds the projects. Each row is checked, partly checked (some descendants checked), or unchecked. A project passes if its area or its client is checked; nothing checked means no restriction. Checking a client or a partly checked row checks it with everything below it; when that completes its parent's children, the parent is checked instead. Unchecking a row under a checked client or area leaves its siblings checked and the parent partly checked. A checked client or area also covers areas and projects added later. The tree's search matches every word against a row's name and its ancestors' names ("research university" finds University's Research and not Consulting's) and shows the matching rows with their ancestors and descendants. The popover opens with clients unfolded and areas with projects folded, except a partly checked one; a search unfolds the rows it shows, and ⌥-click on a triangle folds or unfolds every row.

Search (⌘F): every word of the query must occur, case- and diacritic-insensitively, in the project, area, or client name. Escape clears; a second Escape returns focus to the table.

Empty states: "No projects match" with "Clear Filters"; with no projects at all, "No projects yet" with "New Project". The bar reads "N projects shown (A active, B archived)" (N after filtering, A and B over all projects), plus "N selected" with several rows selected.

### 2.5 Actions

Project rows support extended selection. A client or area row is selected alone: selecting it clears the selected projects, and a selection extended over such rows keeps only its projects. Right-click or ⋯ opens the context menu; the same commands form the Project menu while Projects is shown, each item titled for the selected row's kind (Edit Area…, Rename Client…, Delete Project…, Remove Client…, Retire Area).

| Action | Applies to | Effect | Shortcut |
|---|---|---|---|
| Start Timer | One active project | Starts an entry on it with an empty task (stopping a running one); Projects stays shown | ⌘O (Timer › Start Timer) |
| Edit… | One row | The dialog or sheet | ↩, double-click |
| Rename | One project | In-place edit; ↩ commits, Escape reverts; validation of 3.1 | ⌥↩ |
| Archive | Active projects | Archives them; entries untouched; a running entry keeps running | ⌫ |
| Restore | Archived projects | Activates them; if an area is retired, a confirmation names it ("Restore and reactivate “Research”?") and reactivates it | ⌫ on archived rows |
| Merge Into… | One project | Picker of all other projects (any state, any client), then "Move N entries of “X” to “Y” and delete “X”?" | |
| Delete… | Projects without entries | "Delete “X”? This cannot be undone."; disabled with tooltip "Has N entries; archive it instead" otherwise, since archive and Merge Into cover those | ⌘⌫ |
| Show in Reports | One row | `showReports` with the row as the only filter and range "All time" | ⇧⌘R |
| Copy Name | Selection | Names, one per line | ⌘C |
| Move Area Up, Down | One area | 4.3 | ⌥⌘↑, ⌥⌘↓ |

File has New Project… (⌥⌘N, because ⌘N is the app-wide new entry command), New Area… (⇧⌥⌘N, in the client of the selected row), and New Client….

A mixed selection offers both Archive and Restore, each applying to the rows it fits. Archive, Restore, Rename, and dialog edits are undoable while Projects is shown; the undo stack is cleared when the main window closes. Delete and Merge Into are not undoable.

### 2.6 Irregular rows from sync

Two live projects of one client with the same name (created offline on two devices) both appear with a ⚠ after the name, tooltip "Another project of Consulting has this name"; Merge Into… or Rename resolves it. A project whose area was deleted elsewhere shows "–" for Client and "(deleted area)" for Area, sorts and groups after everything else, and Edit… lets the user pick a client and area.

## 3. The project dialog

One dialog serves creation (from Projects or the picker's "Create Project" row) and editing, as a sheet on the invoking window (on iOS also a page pushed inside the picker's sheet), in the dialog layout of [design.md](design.md) §7.

### 3.1 Fields

Name is required, trimmed, and unique among the client's projects in any state, case- and diacritic-insensitively; a duplicate shows "A project with this name already exists for Consulting" and disables Create. Client lists the clients alphabetically, then "New Client…", which opens the client sheet (4.2) and selects the new client and its general area. Area lists the client's non-retired areas in order, then "New Area…", which opens the area sheet (4.3); it resets to the general area when the client changes, and in edit mode a retired current area is listed as "(retired)". Edit mode adds an Archived switch, which acts as Archive and Restore do (2.5).

↩ confirms from the Name field, ⌘↩ from anywhere, Escape cancels. A client or area created through a sub-sheet persists if the dialog is canceled.

### 3.2 Defaults

From Projects the name is empty and the client and area are, in order: the area of an area row's New Project…, the selected area, the selected client's general area, or the one selected project's area; the one client (and area) the Filters popover restricts to, if exactly one; those of the last project created this session; the first client alphabetically and its general area. From the picker's "Create Project" row the name is the trimmed search text, the same defaults apply without the filter rule, and on Create the picker's owner assigns the project.

### 3.3 Effects of editing

Entries store only the project id, so history follows the current catalog: a rename shows everywhere without touching entries, and moving a project to another area changes the color, area, and client of all its entries, past and future. When the project has entries and the client changes, the dialog confirms: "Move “X” and its N entries to University · Teaching? Reports for past dates will show them there." A move within the same client needs no confirmation and is undoable.

## 4. Clients and areas

Clients and areas are rows of the projects table under Group by Client and Area (2.3), so the whole structure is edited in one place. Double-click or ↩ edits. Context menus: on a client, Rename…, New Area…, New Project…, Show in Reports, Remove…; on an area, Edit…, New Project…, Move Up, Move Down, Retire or Reactivate, Show in Reports, Delete…. A client or area created through New is selected.

### 4.1 The general area

Every client has one general area, named after the client, first in order, and not renamable, retirable, or deletable on its own ([data_and_sync.md](data_and_sync.md) §1.2); its color can change. Views display it as the client's name.

### 4.2 Clients

The client sheet has Name (required, unique among clients case- and diacritic-insensitively) and, when new, Color (the general area's color, prefilled with the default of 4.4); it creates client and general area together. Rename also renames the general area. Remove works only without areas besides the general area and without projects in any state, since the general area cannot be removed alone; otherwise it is disabled with the tooltip "Has N areas and M projects". Clients are not archived; a client leaves the picker when it has no active project.

### 4.3 Areas

The area sheet has Name (required, unique within the client case- and diacritic-insensitively, and not the client's name: "This name is used by the client's general area"), Client, and Color, prefilled with the default (4.4). Client starts on the selected row's client, else empty with "Choose a Client" and Create disabled; it is fixed when editing and when the project dialog's "New Area…" opens the sheet. A new area goes last in the client's order. For the general area Name is disabled with the note "Named after the client". Recoloring recolors every entry of the area's projects at once.

Areas of different clients may share a name, and each has its own color. Areas do not move between clients, since that would silently regroup all their projects; projects do (3.3).

Move Up and Move Down reorder areas, the general area staying first; the order applies in the picker, Group by Client and Area, and Reports. Retire works only without active projects: the area leaves the Area popup and the picker, and its archived projects keep area and color. It still appears in the Filters, for archived projects in the table, and in Reports. Restoring one of its projects reactivates it, and Reactivate is always available. Delete works only without projects in any state, otherwise disabled with the tooltip "Has N projects", and never for the general area. Rename, recolor, reorder, retire, and reactivate are undoable.

### 4.4 Area colors

The Color field is a system color well without opacity. A chosen color is converted to sRGB, clamped to 0 to 1 per component, rounded to 8 bits, and stored as uppercase `#RRGGBB`. The default color of a new area is the library's rule ([data_and_sync.md](data_and_sync.md) §1.2), shared with the tool and `check --fix`. Colors may repeat; the client is always shown beside the area.

The display forms are an 8 pt dot ("No project" is a hollow circle), a 16 pt swatch, and a background for text: the color at 22% opacity (30% in dark mode) with a solid leading bar. Text on the solid color is black or white, whichever has the higher WCAG contrast ratio. Lightness step i (0-based) adds the i-th value of [0, +0.12, −0.12, +0.24, −0.24, +0.36] to the HSL lightness, clamped to 0.15 to 0.90; from the seventh step the values repeat, and Reports adds a hatch.

## 5. The project picker

Every place that assigns a project to an entry or a time block uses this picker; the owner decides where it opens and what the choice does. On the Mac it is a popover 340 pt wide and at most 440 pt tall; on iOS a sheet (iPhone) or popover (iPad). From top to bottom:

1. Search field, placeholder "Search projects".
2. "No Project" (hidden while searching).
3. With an empty search, "Recent": the five active projects with the most recent entry starts (running entry included), newest first, with "Client · Area" trailing ("Client" alone for a general area).
4. One group per client with an active project, alphabetically; projects by area order, then name, with the area name trailing (omitted for the general area). Recent projects appear here too.
5. When the search is non-empty and equals no active project's name (case- and diacritic-insensitively, trimmed), "+ Create Project “<search text>”", opening the dialog (3) with the name prefilled.

Archived projects and retired areas never appear. The entry's current project has a check mark; with an empty search its row is highlighted on open, otherwise the first Recent row. Searching uses the word match of 2.4, hides Recent, drops empty client groups, and highlights the first match. An owner may add task matching (tasks tracked under a project in the last 90 days) and its own placeholder; the Mac Timer and the iOS Timer do ([timer.md](timer.md) §2.3). ↑ ↓ move the highlight, ↩ chooses, Escape closes, ⌘↩ creates from the search text.

## 6. Testable behaviors

- PP-1. ⌘2 to ⌘5 select Calendar, Reports, Projects, Activity; their commands are headed by what they act on: Calendar, Report, Project, or Activity.
- PP-2. Launch shows the main window on the Timer, not on a section; the main window remembers its last selected section across launches.
- PP-3. "Include archived projects", Group by Client, and sort Last tracked descending survive close and relaunch; the search is empty. With no stored state the table groups by Client and Area and sorts Name ascending.
- PP-4. Every column but Project can be hidden from the header menu, persistently; State shows only while archived projects are included.
- PP-5. Total tracked descending orders by summed duration, ties by name ascending; Last tracked puts "Never" last in both directions.
- PP-6. Group by Client and Area lists clients by name, each with its areas in order (general first, named after the client) and their projects; without a search or filter it lists areas without projects, a retired one only while archived projects are included; with a search only the matching client and area; reordering an area reorders the rows at once. A client or area row's total and a Client group's count and total sum their projects.
- PP-7. Checking client "Consulting" shows its projects and checks its areas; adding area "University · Teaching" adds that area's and leaves University partly checked; unchecking "Consulting · Research" keeps Consulting's general area checked and Consulting partly checked, and checking it again checks Consulting; the search "research university" shows University and its Research only; "Clear All" removes all checks and the count.
- PP-8. Over the last 7 days only a project tracked yesterday shows, its Total tracked being that range's time; over the last 365 days one tracked 91 days ago joins it with its own range total; All time also lists one never tracked. In Projects, View › Previous Period moves the section's range and leaves the Reports range unchanged.
- PP-9. The search "noise consulting" matches "Noise Model" under Consulting and not "Noise Model" under another client.
- PP-10. Archiving three projects removes them while archived projects are not included; ⌘Z restores all three.
- PP-11. Delete… is disabled for a project with one entry, with the tooltip of 2.5.
- PP-12. Start Timer (⌘O, Timer › Start Timer on the selected project) while another entry runs stops it, starts an entry on the project with an empty task, and leaves Projects shown; it is disabled for an archived project.
- PP-13. Show in Reports selects Reports with the project as the only filter and range "All time".
- PP-14. Opening `timetracking://project/<uuid>` for an archived project while archived projects are not included, the range is Today, and a search is set selects Projects, turns "Include archived projects" on, selects All time, clears the search, and selects and scrolls to the row.
- PP-15. Moving a project with entries to another client shows the confirmation, and afterwards last year's report by client shows its time under the new client; a move between areas of one client shows no confirmation and ⌘Z undoes it.
- PP-16. A project name differing from another of the same client only in case or diacritics is rejected with the inline message; under another client it is accepted.
- PP-17. "Create Project" from the picker with search "noise" opens the dialog with Name "noise"; Create assigns the project to the owner's entry.
- PP-18. A general area offers no Rename, Retire, or Delete, cannot move from first place, and its sheet keeps the name with the note "Named after the client".
- PP-19. Retire is disabled for an area with an active project and enabled after archiving it; retiring hides the area from the Area popup and the picker. Restoring a project in a retired area asks for confirmation and reactivates the area.
- PP-20. The client and area sheets prefill the color of `AreaColor.defaultColor(existing:)`; a Display P3 color outside sRGB is stored clamped as uppercase `#RRGGBB`.
- PP-21. Text on an area color is white for `#1F3A93` and black for `#F5D76E`.
- PP-22. The picker lists "No Project", then with an empty search Recent (five active projects by latest entry, newest first, an archived one skipped and replaced by the sixth, two rows with two tracked projects), then client groups alphabetically, projects by area order then name, without a trailing name for general-area projects.
- PP-23. Typing in the picker hides Recent; "Create Project “x”" appears for a query matching no active project's name and not for "noise model" when "Noise Model" exists.
- PP-24. With task matching on, "clarify" finds the project of "Clarify noise model" tracked 30 days ago and not one tracked 100 days ago.
- PP-25. A client or area row is selected alone and the Project menu (Edit Area…, Delete Area…, Retire Area; Rename Client…, Remove Client…), ↩, and Show in Reports act on it; a selection extended over client and area rows keeps only its projects; New Project… starts in the selected area, or in the area of the one selected project.
- PP-26. New Area… starts its Client popup on the selected row's client, or empty with Create disabled until a client is chosen; the name rule follows the chosen client ("Research" is taken under University, free under Consulting); an existing area's client is fixed.
- PP-27. The filter tree with projects opens with its areas folded, except one with some of its projects checked; unfolding an area shows its projects; a search shows the matching projects of a folded area; a client with areas has a triangle, an area without projects none.
- PP-28. "Include archived projects" off shows only active projects and on shows all; Clear All turns it off, and it does not count toward "Filters (N)"; a view state stored with the former state selector on "Archived" or "All" opens with it on, keeping grouping and sort.
