# Spec: Planner Window and Projects Section

This spec covers the Mac app's Planner window shell and its Projects section: the projects table, the project dialog, Clients & Areas with the area colors, and the shared project picker. Entities and their store rules are in [spec_data_and_sync.md](spec_data_and_sync.md) §1.

## 1. The Planner window

### 1.1 Layout

There is at most one Planner window: a two-column split view with a sidebar and the selected section. The sidebar entries are Projects (`folder`), Calendar (`calendar`), Reports (`chart.bar`), and Activity (`waveform.path.ecg`), with no headings and no other items. The window title is the section's name. Each section owns its toolbar items, placed by the one scheme of [spec_design.md](spec_design.md) §4, so the period arrows and Today of Calendar, Reports, and Activity keep their place when the section changes; the shell adds only the sidebar toggle. The Planner has no running-timer controls.

| Property | Value |
|---|---|
| Default size | 1360 x 840 pt |
| Minimum size | 820 x 560 pt |
| Sidebar width | 200 pt, resizable from 160 to 280 |
| At launch | Never opened, even if it was open at quit |
| Remembered per device | Frame, sidebar visibility and width, selected section, each section's view state |

Window > Planner (⌥⌘P) opens the window on the last selected section, or brings it forward. For Projects the view state is the state selector, filters, grouping, sort, column visibility and widths, and the collapsed groups; the search text is not kept.

### 1.2 Commands

| Menu | Command | Shortcut | Availability |
|---|---|---|---|
| Window | Planner | ⌥⌘P | Always; also the key equivalent of the menu bar item's "Open Planner" |
| View | Projects, Calendar, Reports, Activity | ⌘1 to ⌘4 | Planner window is key |
| View | Clients & Areas | ⌥⌘1 | Planner key; selects Projects and shows Clients & Areas (4) |
| View | Show/Hide Sidebar | ⌃⌘S | Planner key |
| Edit | Find | ⌘F | Planner key; focuses the section's search field |

The Timer window's selection commands (⌘P, ⌘E, ⌘⌫, ⌘F) act only while it is key ([spec_timer_window.md](spec_timer_window.md) §9); Planner sections define their own.

### 1.3 Router

The `PlannerRouter` opens the window if needed, selects a section, and passes it a request; no section changes another's state directly.

| Request | Effect |
|---|---|
| `showProjects()` | Selects Projects with its current view state |
| `showProject(id)` | Selects Projects, clears the search, sets the state selector to "All" if the project's state is hidden, clears filters that hide it, selects and scrolls to its row. Target of `timetracking://project/<uuid>` |
| `showClientsAndAreas(client:)` | Selects Projects, shows Clients & Areas, selects the client if given |
| `showCalendar(day:hour:highlight:)` | Selects Calendar ([spec_planner_calendar.md](spec_planner_calendar.md) defines the arguments) |
| `showReports(range:filter:)` | Selects Reports ([spec_planner_reports.md](spec_planner_reports.md) §9) |
| `showActivity(range:)` | Selects Activity with the shared Reports/Activity range |
| `showTrackerSettings(exclusion:)` | Opens Settings on the Tracker pane, with an exclusion prefilled if given |

### 1.4 iPad

The sections are tabs ([spec_ios.md](spec_ios.md) §10). In Projects, the Sort and Group menu replaces header clicks, long press opens context menus, rows swipe to Archive or Restore, and Clients & Areas is pushed from a toolbar button. The router maps onto tab selection.

## 2. The projects table

The window title is "Projects" with no leading toolbar items. The trailing items are, in order: Filters (the symbol fills and the title reads "Filters (2)" while filters are active), the state selector (segmented: Active, Archived, All), the Sort and Group menu (Group By, Sort By, and Ascending or Descending, each with a check mark), Clients & Areas, New Project (`plus`), and the search field. Below is a `Table` with group header rows, a ⋯ button on the hovered row at the trailing edge of the Project cell, and a status row.

### 2.1 Columns

| Column | Content | Default |
|---|---|---|
| Project | 10 pt dot in the area's color, then the name. Archived: name in secondary label color, dot at 50% opacity | 280 pt, cannot be hidden |
| Client | The area's client | 140 pt |
| Area | The area's name; a general area (4.1) shows the client's name in secondary label color | 140 pt |
| State | "Active" or "Archived" | 90 pt; hidden while the state selector is "Active" or "Archived" |
| Created | `createdAt` | 100 pt |
| Last tracked | Start of the most recent entry, running entry included; "Never" if none | 120 pt |
| Total tracked | Sum of all entries in the `XhYYm` format of [spec_design.md](spec_design.md) §2 with unbounded hours ("432h 21m"); the running entry counts to now, refreshed once a minute | 120 pt |

Dates read "Today", "Yesterday", the weekday within the last 7 days, "Oct 27" within the current year, "2024" otherwise; the tooltip shows the full date. The header's context menu toggles column visibility; column order is fixed. Last tracked and Total tracked come from the library's cached project rows.

### 2.2 Sorting

Clicking a header sorts by it, a second click reverses (State is not sortable); the Sort by menu is the same setting. Default: Name ascending. With grouping, the sort applies within groups.

| Key | Order |
|---|---|
| Name | Case- and diacritic-insensitive |
| Client | Client name, then project name |
| Area | Client name, area order (4.3), project name |
| Created, Last tracked | By instant; "Never" last in both directions |
| Total tracked | By seconds |

The project name breaks every remaining tie.

### 2.3 Grouping

Group by: None, Client (default), Area.

| Grouping | Header row | Group order |
|---|---|---|
| Client | "Consulting · 3 projects", summed Total tracked | Client name |
| Area | "Consulting · Research · 2 projects" ("Consulting · 2 projects" for a general area), swatch, summed Total tracked | Client name, then area order |

Empty groups are hidden. Groups collapse with their triangle, with ← and → on a selected row, and all at once with ⌥-click; the collapsed set is remembered per grouping. Header rows are not selectable; their context menu offers "Edit Client…" and "Edit Area…".

### 2.4 Filtering

The state selector (Active, Archived, All; default Active), the Filters popover, and the search combine with AND.

Filters popover: Clients and Areas as check-box lists (areas indented under clients, retired areas in secondary label color); a project passes if its client or its area is checked, and nothing checked means no restriction. Checking a client clears its areas' checks; checking an area clears its client's check. "Last tracked": Any time (default), In the last 30 days, In the last 90 days, Not in the last 90 days, Not in the last year, Never. "Clear" resets the popover. The count in the Filters title counts each checked client or area and a Last tracked choice other than Any time.

Search (⌘F): every word of the query must occur, case- and diacritic-insensitively, as a substring of the project, area, or client name. Escape clears; a second Escape returns focus to the table.

Empty states: "No projects match" with "Clear Filters"; with no projects at all, "No projects yet" with "New Project". The status row reads "N projects shown (A active, B archived)" (N after filtering, A and B over all projects), plus "N selected" with several rows selected.

### 2.5 Actions

Rows support extended selection and ⌘A. Right-click or ⋯ opens the context menu for the selection; the same commands form a "Project" menu while Projects is active.

| Action | Applies to | Effect | Shortcut |
|---|---|---|---|
| New Project… | | Project dialog (3) | ⌥⌘N |
| Start Timer | One active project | Starts an entry on it with an empty task (stopping a running one); the Planner stays key | ⌘↩ |
| Edit… | One project | Dialog in edit mode | ↩, double-click |
| Rename | One project | In-place edit; ↩ commits, Escape reverts; validation of 3.1 | ⌥↩ |
| Archive | Active projects | Archives them; entries untouched; a running entry keeps running | ⌫ |
| Restore | Archived projects | Activates them; if an area is retired, a confirmation names it and un-retires it | ⌫ on archived rows |
| Merge Into… | One project | Picker of all other projects (any state, any client), then "Move N entries of “X” to “Y” and delete “X”?"; calls `merge(project:into:)` | |
| Delete… | Projects without entries | "Delete “X”? This cannot be undone."; disabled with tooltip "Has N entries; archive it instead" otherwise | ⌘⌫ |
| Show in Reports | One project | `showReports` with this project as the only filter and range "All time" | ⇧⌘R |
| Copy Name | Selection | Names, one per line | ⌘C |

A mixed selection offers both Archive and Restore, each applying to the rows it fits. Archive, Restore, Rename, and dialog edits are undoable (⌘Z) while the Planner is key; the window's undo stack is cleared when it closes. Delete and Merge Into are not undoable.

### 2.6 Irregular rows from sync

Two live projects of one client with the same name (created offline on two devices) both appear with a ⚠ after the name, tooltip "Another project of Consulting has this name"; Merge Into… or Rename resolves it. A project whose area was deleted elsewhere shows "–" for Client and "(deleted area)" for Area, sorts and groups after everything else, and Edit… lets the user pick a client and area.

## 3. The project dialog

One dialog serves creation (from Projects or the picker's "Create Project" row) and editing, as a sheet on the invoking window (on iOS also a page pushed inside the picker's sheet). It is a grouped form in the dialog layout of `spec_design.md` §7: the title ("New Project"), a Name section, then Client, Area, and in edit mode Archived. Edit mode is titled "Edit Project", its button reads "Save", and it adds an "Archived" switch.

### 3.1 Fields

| Field | Control | Rules |
|---|---|---|
| Name | Text field, focused | Required, trimmed, unique among the client's projects (any state), case- and diacritic-insensitively |
| Client | Popup: clients alphabetically, separator, "New Client…" | Required. "New Client…" opens the client sheet (4.2) and selects the new client and its general area |
| Area | Popup: the client's non-retired areas in order with swatches, general area first, separator, "New Area…" | Required. Resets to the general area when the client changes. "New Area…" opens the area sheet (4.3) and selects the new area. In edit mode a retired current area is listed as "(retired)" |
| Archived | Switch, edit mode | As Archive and Restore (2.5), including the retired-area confirmation |

Create (or Save) is disabled until Name is valid; a duplicate shows "A project with this name already exists for Consulting" under the field. ↩ confirms from the Name field, ⌘↩ from anywhere, Escape cancels. A client or area created through a sub-sheet persists if the dialog is canceled.

### 3.2 Defaults

| Invoked from | Name | Client and Area |
|---|---|---|
| Projects section | Empty | The one client (and area) the Filters popover restricts to, if exactly one; else those of the last project created this session; else the first client alphabetically and its general area |
| Picker "Create Project" row | The search text, trimmed | As above without the filter rule; on Create the picker's owner assigns the project |
| Edit | The project's values | The project's values |

### 3.3 Effects of editing

Entries store only the project id, so a rename shows everywhere without touching entries, and moving a project to another area changes the color, area, and client of all its entries, past and future. When the project has entries and the client changes, the dialog confirms: "Move “X” and its N entries to University · Teaching? Reports for past dates will show them there." (Move, Cancel). A move within the same client needs no confirmation and is undoable.

## 4. Clients & Areas

The Clients & Areas toolbar button (⌥⌘1) replaces the table with this outline, titled "Clients & Areas"; the leading back button (`chevron.left`, "Projects") or ⌘1 returns, and New Client (`plus`) is the trailing item. Clients are listed alphabetically, each followed by its areas in order (general area first) and an "+ Add Area" row.

Client rows show the name, the number of areas, and "N active · M archived" project counts (a zero archived count is omitted). Area rows show a 16 pt swatch, the name, a "general" or "retired" tag in secondary label color, and the counts. Double-click or ↩ edits. Context menus: on a client, Rename…, New Area…, Show Projects, Remove…; on an area, Edit…, Move Up, Move Down, Retire or Un-retire, Show Projects, Delete…. "Show Projects" returns to the table filtered to that client or area. ⌥⌘N creates a client here.

### 4.1 The general area

Every client has one general area (`general == true`), named after the client, first in order, and not renamable, retirable, or deletable on its own ([spec_data_and_sync.md](spec_data_and_sync.md) §1.2); its color can change. Views display it as the client's name.

### 4.2 Clients

| Action | Rule |
|---|---|
| New (New Client in the toolbar, ⌥⌘N here, "New Client…" in the dialog) | Sheet with Name (required, unique among clients case- and diacritic-insensitively) and Color (the general area's color, prefilled with the default of 4.4). Creates client and general area in one transaction |
| Rename | Sheet with Name only, same rule; renames the general area |
| Remove | Only without areas besides the general area and without projects in any state; otherwise disabled with tooltip "Has N areas and M projects". Confirmed |

Clients are not archived; a client leaves the picker when it has no active project.

### 4.3 Areas

| Action | Rule |
|---|---|
| Add ("+ Add Area", ⇧⌥⌘N with a client or its area selected) | Area sheet: Name (required, unique within the client case- and diacritic-insensitively, not the client's name) and Color, prefilled with the default (4.4). Goes last in the client's order |
| Edit | Same sheet; for the general area Name is disabled with the note "Named after the client". Recoloring recolors every entry of the area's projects at once |
| Reorder | Drag within the client, or ⌥⌘↑ / ⌥⌘↓ (Move Up, Move Down); the general area stays first. This order applies in the picker, Group by Area, and Reports |
| Retire | Only without active projects. Hidden from the Area popup and the picker; archived projects keep area and color. Restoring one of its projects un-retires it |
| Un-retire | Always available on a retired area |
| Delete | Only without projects in any state; otherwise disabled with tooltip "Has N projects". Never for the general area. Confirmed |

Areas do not move between clients; projects do (3.3). Rename, recolor, reorder, retire, and un-retire are undoable. Retired areas still appear in the Filters popover, for archived projects in the table, and in Reports.

### 4.4 Area colors

The Color field is a system color well (`ColorPicker` without opacity). A chosen color is converted to sRGB, clamped to 0 to 1 per component, rounded to 8 bits, and stored as uppercase `#RRGGBB`. The default color of a new area is the library's rule (`AreaColor.defaultColor(existing:)`, [spec_data_and_sync.md](spec_data_and_sync.md) §1.2), shared with the CLI and `check --fix`. Colors may repeat; the client is always shown beside the area.

Display forms, derived from the stored value by `AreaColor`, the same in light and dark mode unless stated:

| Use | Derivation |
|---|---|
| Dot | 8 pt solid circle (table, picker, Timer list, chips, Reports); "No project" is a hollow circle with a 1 pt secondary stroke |
| Swatch | 16 pt solid rounded square (Clients & Areas, popups, sheets) |
| Background for text | The color at 22% opacity (light) or 30% (dark), 4 pt solid leading bar, primary label text (Calendar cards, report rows) |
| Text on the solid color | Black or white, whichever has the higher WCAG contrast ratio |
| Lightness step i (0-based) | Adds the i-th value of [0, +0.12, −0.12, +0.24, −0.24, +0.36] to the HSL lightness, clamped to 0.15 to 0.90; from the seventh step the values repeat (Reports adds a hatch) |

## 5. The project picker

Every place that assigns a project to an entry or a time block uses this picker (Timer window, Calendar editors and Fill Day rows, iOS Timer); the owner decides where it opens and what the choice does. On the Mac it is a popover 340 pt wide and at most 440 pt tall, scrolling; on iOS a sheet (iPhone) or popover (iPad).

Contents, top to bottom:

1. Search field with a `magnifyingglass` glyph on a filled rounded background, placeholder "Search projects".
2. "No Project", with an empty circle (hidden while searching).
3. With an empty search, "Recent": the five active projects with the most recent entry starts (running entry included, via `recentProjects`), newest first; archived ones are skipped and the next fills in; shorter or absent with less history. Rows: dot, name, trailing "Client · Area" in secondary label color ("Client" alone for a general area).
4. One group per client with an active project, alphabetically, header in small uppercase secondary text; projects by area order, then name. Rows: dot, name, trailing area name (omitted for the general area). Recent projects appear here too.
5. When the search is non-empty and equals no active project's name (case- and diacritic-insensitively, trimmed), a row below a separator: "+ Create Project “<search text>”", opening the dialog (3) with the name prefilled.

Archived projects and retired areas never appear. The entry's current project has a check mark; with an empty search its Recent row (else its client row) is highlighted on open, otherwise the first Recent row. Searching uses the word match of 2.4 over project, area, and client names, hides Recent, drops empty client groups, and highlights the first match. An owner may add task matching (tasks tracked under a project in the last 90 days) and its own placeholder; the Timer window and iOS Timer do ([spec_timer_window.md](spec_timer_window.md) §2.3). ↑ ↓ move the highlight, ↩ chooses, Escape closes, ⌘↩ creates from the search text.

## 6. Testable behaviors

- PP-1. ⌘1 to ⌘4 select Projects, Calendar, Reports, Activity while the Planner is key and do nothing while the Timer window is key.
- PP-2. Launch never opens the Planner, even if it was open at quit; ⌥⌘P opens it on the last section and frame.
- PP-3. State selector "Archived", Group by Area, and sort Last tracked descending survive close and relaunch; the search is empty. With no stored state the table groups by Client and sorts Name ascending.
- PP-4. Every column but Project can be hidden from the header menu, persistently; State shows only on "All".
- PP-5. Total tracked descending orders by summed duration, ties by name ascending; Last tracked puts "Never" last in both directions.
- PP-6. A client group header's count and total equal its rows' count and summed Total tracked; Group by Area orders by client name then area order, and reordering an area in Clients & Areas reorders the groups at once.
- PP-7. Checking client "Consulting" shows its projects; adding area "University · Teaching" adds that area's; checking "Consulting · Research" clears the "Consulting" check and narrows it to Research; "Clear" removes all checks and the count.
- PP-8. "Not in the last 90 days" shows a project last tracked 91 days ago and hides one tracked 89 days ago and one never tracked; "Never" shows only the latter.
- PP-9. The search "noise consulting" matches "Noise Model" under Consulting and not "Noise Model" under another client.
- PP-10. Archiving three projects removes them while the selector is "Active"; ⌘Z restores all three.
- PP-11. Delete… is disabled for a project with one entry, with the tooltip of 2.5.
- PP-12. Start Timer while another entry runs stops it, starts an entry on the project with an empty task, and leaves the Planner key; it is disabled for an archived project.
- PP-13. Show in Reports selects Reports with the project as the only filter and range "All time".
- PP-14. Opening `timetracking://project/<uuid>` for an archived project while the selector is "Active" and a search is set selects Projects, sets "All", clears the search, and selects and scrolls to the row.
- PP-15. Moving a project with entries to another client shows the confirmation, and afterwards last year's report by client shows its time under the new client; a move between areas of one client shows no confirmation and ⌘Z undoes it.
- PP-16. A project name differing from another of the same client only in case or diacritics is rejected with the inline message; under another client it is accepted.
- PP-17. "Create Project" from the picker with search "noise" opens the dialog with Name "noise"; Create assigns the project to the owner's entry.
- PP-18. A general area offers no Rename, Retire, or Delete and cannot be dragged from first place.
- PP-19. Retire is disabled for an area with an active project and enabled after archiving it; retiring hides the area from the Area popup and the picker. Restoring a project in a retired area asks for confirmation and un-retires the area.
- PP-20. The client and area sheets prefill the color of `AreaColor.defaultColor(existing:)`; a Display P3 color outside sRGB is stored clamped as uppercase `#RRGGBB`.
- PP-21. Text on an area color is white for `#1F3A93` and black for `#F5D76E`.
- PP-22. The picker lists "No Project", then with an empty search Recent (five active projects by latest entry, newest first, an archived one skipped and replaced by the sixth, two rows with two tracked projects), then client groups alphabetically, projects by area order then name, without a trailing name for general-area projects.
- PP-23. Typing in the picker hides Recent; "Create Project “x”" appears for a query matching no active project's name and not for "noise model" when "Noise Model" exists.
- PP-24. With task matching on, "clarify" finds the project of "Clarify noise model" tracked 30 days ago and not one tracked 100 days ago.

## 7. Decisions

- Editing reuses the creation dialog, so one component serves every caller.
- Clients & Areas is a view inside Projects (⌥⌘1), keeping four sections and four iPad tabs.
- New Project is ⌥⌘N because ⌘N is the app-wide "New" entry command.
- A client is removable only when empty, since its general area cannot be removed alone.
- Areas never move between clients; moving one would silently regroup all its projects.
- Delete is limited to projects without entries; archive and Merge Into cover the rest.
- Entries store no color, area, or client, so history follows the current catalog.
- No favorites, templates, tags, billable flags, or project colors; pinned projects are an iOS widget setting.

## 8. Interfaces

Provided:

- `PlannerRouter` (1.3): section switching for sections, URL handlers, and the menu bar item.
- Project picker (5): takes the current project and an optional task-match source; returns a project id, "No Project", or a new project.
- Project dialog (3) and client and area sheets (4), shared by Mac and iOS.
- `AreaColor` display parameters (4.4).

Assumed of the data library ([spec_data_and_sync.md](spec_data_and_sync.md)):

- `Client {id, name}`, `Area {id, clientID, name, general, color, sortOrder, retired}`, `Project {id, areaID, name, archived, createdAt, archivedAt}` with the uniqueness and general-area rules of §1.
- `projects(filter:)` rows with last-tracked, total seconds, and entry count, cached and observable; `recentProjects(limit:)`; `merge(project:into:)`; client, area, and project writes, undoable by issuing the inverse write; `consistencyIssues()` for duplicates and orphans.
- `AreaColor.defaultColor(existing:)`.

Assumed of other components:

- Timer window, Calendar, iOS: host the picker and dialog.
- Reports, Calendar, Activity: implement their router requests.
- Automation: `timetracking://planner/projects` and `timetracking://project/<uuid>` map to the router.
