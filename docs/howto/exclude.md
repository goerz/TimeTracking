# Keep something out of the activity record

## Exclude an app, session, or site

1. Open Activity (⌘5) and find the row in the Apps panel, or a site in "Where the time went".
2. Right-click it and choose "Exclude <name> from Tracking…".
3. The Tracker pane opens with the value filled in. Click "Add to Settings File".

An excluded app records nothing from now on, and its time becomes a gap. An excluded tmux session keeps its time and hides its name. An excluded site shows as a private browser window. Past data disappears from all totals at once, while the log files stay as they are.

## Hide a folder, or keep only an app's name

Other kinds of exclusions are edited in the settings file. In Settings, Tracker, under Files, click "Open in Editor". The file is `settings.toml`, and the lists are in its `[privacy]` table.

```toml
[privacy]
exclude_paths = ["~/Documents/Taxes"]
exclude_keywords = ["secret"]
name_only_apps = ["com.example.diary"]
private_domains = ["bank.example.com"]
exclude_title_keywords = ["Private"]
```

A path in `exclude_paths`, or a folder whose name starts with an entry in `exclude_keywords`, keeps its time and shows as `(private)`. An app in `name_only_apps` is recorded by name only. A domain in `private_domains` is recorded as the bare domain, everywhere. A window title containing an entry of `exclude_title_keywords` is dropped.

The tracker picks up the change within 30 seconds.

## Remove past records for good

Exclusions hide old data when it is shown; the log files keep it. To rewrite the files, run this for the dates in question.

```sh
tracker-event reapply-exclusions 2026-10-01 2026-10-31
```

To delete a whole day from the record:

```sh
tracker-event forget-day 2026-10-29
```

To delete one stretch, right-click its card in the Calendar and choose "Delete This Activity…". All of these remove the data on every device and can't be undone. Your time entries are not affected.
