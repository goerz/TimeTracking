# Export a report as CSV

1. In Reports (⌘3), set the range, filters, and search.
2. Choose the lower card you want: Breakdown for totals, or Entries for one row per entry. In the Breakdown, set the levels first.
3. Click Export in the card's header, or press ⇧⌘E, and choose where to save.

The Breakdown CSV has one row per leaf of the fully expanded tree, and the Entries CSV has one row per listed entry. For a quick paste, select rows and press ⌘C, which copies them as tab-separated text.

The command-line tool writes the same files, byte for byte, for the same range and filters.

```sh
timetracking report --week last-week --group-by client,project --csv
timetracking entries --from 2026-10-01 --to 2026-11-01 --csv
```

For a complete backup in JSON, which `timetracking import` can read again, run `timetracking export -o backup.json`. The [formats](../reference/automation.md#8-formats) are in the reference.
