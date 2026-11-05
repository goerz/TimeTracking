# Clients, areas, projects, and tasks

Every tracked minute hangs on a small tree. Understanding it takes a minute and makes the rest of the app obvious.

A client is who the work is for: an employer, a customer, or simply "Home". An area is an ongoing part of life or line of work inside one client, such as "Research" or "Teaching" at a university. A project is a unit of work inside one area, such as "Grant renewal". A task is the free text you type when you start an entry, such as "Clarify noise model".

```{figure} /images/mac-projects.png
:alt: The Projects section, a table of projects grouped under clients and areas, with colored dots, dates, and total hours.

The Projects section shows the whole tree in one table.
```

Each client comes with a general area, named like the client, for projects that need no finer grouping. If you never think about areas, your projects simply live there.

Color belongs to the area. Every project in an area, and every entry in those projects, takes that color, in the Calendar as well as in the Reports chart. Colors can be any RGB value, and you can change one whenever you like.

## Entries point at projects and nothing else

A time entry stores its start, its end, its task, and which project it belongs to. It stores no color, area, or client. Those come from the project at the moment you look.

This has a visible consequence. Move a project to another area and its whole history moves with it: past entries take the new color, and last year's report shows them under the new area. Rename a project and the new name appears everywhere. The app confirms a move to another client, because that changes past reports, but it rewrites no entry to do so.

An entry may have no project. It then appears in gray and reports under "No project". You can always assign one later.

## Projects end, entries stay

When a project is finished, you archive it. It disappears from the pickers and from autocompletion, while its entries stay in your reports. An archived project can be restored at any time, and the app offers that when you try to continue one of its entries.

Deleting a project works only while it has no entries. To get rid of a project that has them, you merge it into another one, which moves the entries over. Areas retire rather than archive; a retired area leaves the pickers and keeps its history.

Tasks have no such life of their own. They are text on an entry. The app remembers them for autocompletion, and typing a few letters offers earlier tasks together with the project they belonged to, so most entries start with two or three keystrokes.

## What is not in the tree

Three other things appear next to entries and are not entries. An activity block is the tracker's record of a stretch of attention. A time block is a plan, stored as a calendar event. A calendar event is anything else from a calendar you chose to show. Only entries count as tracked time, and [Tracked time and recorded activity](tracked-and-recorded.md) explains why.

The [vocabulary in the reference](../reference/components.md#vocabulary) defines each of these terms exactly.
