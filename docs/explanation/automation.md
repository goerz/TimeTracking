# Automation

Everything you can do with a timer you can also do from a script. Three surfaces reach your data without the app's windows: the command-line tool `timetracking` on the Mac, App Intents for Shortcuts, Siri, and Spotlight on all devices, and links with the `timetracking://` scheme.

All three call the same code as the apps, against the local store. There is no web API, and the tool works without the app running.

## The command-line tool

The tool does what you would expect from the words.

```console
$ timetracking start "Clarify noise model" --project "Noise paper"
Started "Clarify noise model" on Noise paper at 09:15.
$ timetracking status
$ timetracking stop
$ timetracking report --week last-week --group-by client,project
```

Every listing has a `--json` form and, where tabular, `--csv`, and those shapes change only with a format version bump, so scripts can rely on them. Dates are forgiving: `today`, `-3d`, `2026-W44`, and `2026-10` all work. Commands return meaningful exit codes, for example 3 when a name isn't found and 4 when a rule refuses the change, such as an overlap.

The tool writes through the same library as the apps, and the Mac app then sends your change to iCloud, so a start from a script shows in the menu bar within a second. It can also manage projects, areas, and clients, but it never deletes them, and it deletes an entry only one at a time with `--yes`.

[Track time from the command line](../howto/command-line.md) has more examples, and [Read your data from a script](../howto/scripts.md) covers JSON, CSV, and direct database access.

## Shortcuts, Siri, and Spotlight

The app offers actions for Shortcuts, such as Start Timer, Stop Timer, Continue, and Today's Total, on the Mac and on iOS. App Shortcuts add phrases for Siri. No intent deletes, archives, or edits anything. Active projects appear in Spotlight. See [Use Siri, Shortcuts, and links](../howto/shortcuts.md).

## Links

A link can start or stop an entry, or open a view: `timetracking://start?project=Household&task=Laundry` starts an entry, `timetracking://planner/reports?from=2026-10-19&to=2026-10-26` opens Reports on a range. Links work from any app, note, or launcher. They never create projects, and on the Mac the start, stop, and continue links act without bringing the app to the front.

## Keeping a structure in line

If your projects come from somewhere else, such as a task manager or a yearly plan, a TOML description file can state which clients, areas, and standing projects should exist. The command `timetracking check` compares it with the store, and `--fix` repairs whatever it can repair without losing anything. See [Keep projects in line with a description file](../howto/check.md).

## Moving data in and out

The command `timetracking export` writes everything as one JSON document, and `timetracking import` reads that format back. Import is safe to repeat, since records are matched by identifier. Migrating from another tracker means writing a small converter into this format; see [Import data from another tracker](../howto/import.md).

The [scripting spec](../reference/automation.md) documents every command, option, format, and exit code.
