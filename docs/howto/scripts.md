# Read your data from a script

## Use JSON output

Add `--json` to any listing. Its shape changes only with a format version bump, while the human-readable tables may change at any time.

```sh
timetracking status --json | jq -r '.running.task // "idle"'
timetracking report --week last-week --group-by project --json | jq '.total / 3600'
```

Every record carries its UUID as well as its name. Durations are whole seconds, and times are ISO 8601 with the local offset.

## React to failures

Exit codes say what went wrong, and on an error stdout stays empty.

```sh
timetracking stop --quiet || [ $? = 4 ]   # 4: nothing was running
```

Code 3 means a name was not found or was ambiguous, 4 that a rule refused the change, 5 that the store is unavailable, and 2 a usage error. The [complete table](../reference/automation.md#311-exit-codes) is in the reference.

## Query the database directly

For anything the tool doesn't offer, you may read the SQLite database. Open it read-only, and never write to it; all writes go through the tool.

```sh
sqlite3 "file:$(timetracking --store-path)?mode=ro" \
    "select task, count(*) from entries group by task order by 2 desc limit 10"
```

Use the public `entries` view, whose [columns](../reference/data_and_sync.md#21-store-and-schema) stay stable. Wrap several queries in one transaction, and don't use `immutable=1` on the live file. The system asks once per program before it may open the container.
