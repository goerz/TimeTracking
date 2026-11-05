# Show sleep and workouts

The Calendar's Activity column can show sleep and workouts from Apple Health as thin lines, which helps to explain the gaps in a day. Only the iPhone can read Apple Health.

1. On the iPhone, open Settings in the app, and under Apple Health turn on Sleep, Workouts, or both.
2. Allow access in the sheet that appears. The first import reads the last 60 days.
3. On the Mac, the periods appear in the Calendar once they have synced. The same toggles are in Settings, Calendar, because the setting syncs.

Each night is labeled with its length on the morning it ends. A status line under the toggles says when the iPhone last read Apple Health, or what it is waiting for. A line "found no workouts" with data you know exists usually means read access is off: iOS reports a denied read as no data, so check Settings, Privacy & Security, Health on the iPhone.

## Count them in Reports

By default, sleep and workouts stay out of your totals. To count one, open Settings, Calendar on the Mac or iPad, and choose an area under its "In Reports" menu. Reports then counts that kind as a project "Sleep" or "Workouts" of the area, without a task.

The command-line tool leaves them out of `report` unless you add `--health`, so a script's totals stay tracked time. The command `timetracking health` lists the periods themselves.
