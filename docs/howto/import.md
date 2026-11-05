# Import data from another tracker

The app imports one format, its own JSON export, so moving from another tracker means writing a small converter.

1. Look at the format with `timetracking export | head`, and read the [export format](../reference/data_and_sync.md#51-export).
2. Write a script that turns your old data into that document. Derive every id as a UUID version 5, in a namespace of your choosing, from a name such as `client:<source id>` or `entry:<source id>`. Rerunning the converter on a later dump then updates records instead of duplicating them.
3. Try it without writing anything.

   ```sh
   timetracking import converted.json --dry-run
   ```

   A document that fails validation exits with code 7 and names the path and the reason.

4. Import it.

   ```sh
   timetracking import converted.json
   ```

The tool prints one line per kind of record, such as `entries: 1520 created, 3 updated, 41 unchanged, 1 skipped (deleted here)`. Import validates the whole document first, runs in one transaction, and never deletes. If the Mac app runs, it sends the new records to iCloud.

To restore a backup including settings, add `--include-settings`.
