# Tracked time and recorded activity

TimeTracking keeps two records of your day, and the difference between them shapes the whole app.

Tracked time is what you state: time entries, each with a task and usually a project. It is the only thing that reaches the Timer list, the Reports totals, and the exports. You can edit it freely, because it is your account of your own work.

Recorded activity is what the tracker observes on your Mac, and more coarsely on your iPhone and iPad. Every 30 seconds it notes which app, terminal session, or website has your attention, and it groups those notes into activity blocks. A block says, for example, that from 09:10 to 09:44 you were mostly in a terminal session named "paper". It doesn't know that this was thesis work, and it never guesses: the tracker never assigns a project, area, or client, and never opens your time entries.

Keeping the record neutral is the point. If the tracker tried to classify your work, it would be wrong some of the time, and you could no longer trust either number. Because it only reports, you can compare the two records freely.

## Where they meet

The two records meet in the [Calendar](calendar.md). Each day shows activity in the left column and entries in the middle. Parts of a block that an entry already covers are dimmed, so the bright stretches are the ones you have not accounted for. Hover over a block and click "+", and the app offers an entry over its longest uncovered stretch. You supply the task and project.

The [Activity section](activity.md) is the other view of the record, built for looking back: how much of each day was active, at which hours, in which apps, and on which sites. Reports and Activity share one date range, so you can flip between tracked and recorded time for the same week.

The two totals are expected to differ. Reading a printed paper is tracked work and no activity at all; a video call you never tracked is activity and no tracked work. The app shows both and leaves the comparison to you.

## Background work is not attention

The tracker separates what has your attention from what merely runs. A build or a busy coding agent counts as background work. It shows up in its own panel of the Activity section, labeled as not counting toward active time, and as thin strips in the Calendar when it ran while you were away. A video or a call without typing counts as passive presence, which also keeps the idle prompt from appearing.

For what the tracker does and doesn't record, see [What the tracker records](privacy.md).
