# Use Siri, Shortcuts, and links

## Talk to Siri

After installing the app, these phrases work on the iPhone, iPad, and Mac with no setup. Each ends in "in TimeTracking" or "with TimeTracking", using your app's name.

| Say | Effect |
|---|---|
| "Start tracking Household in TimeTracking" | Starts the project |
| "Start a timer in TimeTracking" | Asks what you are working on; the answer becomes the task |
| "Stop tracking in TimeTracking" | Stops the running entry |
| "Continue in TimeTracking" | Continues your latest entry |
| "What am I tracking in TimeTracking" | Tells you what runs |
| "How much have I tracked today in TimeTracking" | Tells today's total |

When a name matches two projects, Siri asks which one.

## Build a shortcut

In the Shortcuts app, search for the app's actions: Start Timer, Stop Timer, Continue, Get Running Entry, Get Today's Total, Find Entries, Create Project, and Show Timer. Use them in your own shortcuts and automations. The actions start, stop, read, and create, but never delete, archive, or edit.

## Use a link

Links work from a note, a launcher, or a calendar event.

```text
timetracking://start?project=Household&task=Laundry
timetracking://stop
timetracking://continue
timetracking://show
timetracking://planner/calendar?date=2026-10-29
timetracking://planner/reports?from=2026-10-19&to=2026-10-26
timetracking://planner/projects
timetracking://planner/activity?date=2026-10-29
timetracking://project/<uuid>
```

In the Reports link, `to` is the first day left out. A link with an unknown, archived, or ambiguous project name starts nothing and shows an alert, and links never create projects. On an iPhone, the `planner` and `project` links open the Timer.
