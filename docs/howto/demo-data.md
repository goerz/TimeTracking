# Try the app with synthetic data

A development build can show the app full of made-up entries, without touching your real data. Debug builds have their own containers, so nothing here reaches the installed app.

```sh
make demo FIXTURE=large
```

This builds the Debug apps, replaces the Debug store on the Mac and on both simulators with a fixture moved to today, and opens them. The fixtures are in `Fixtures/Store/`: `small` has two weeks of entries, `large` two years, and `running` adds an entry running for 25 minutes.

The screenshots on this site show the same synthetic data, and `make screenshots` retakes them; [Contributing](../contributing.md) describes how.
