# Track time from the command line

The tool `timetracking` is linked into `~/.local/bin` by `make install`. It works without the app running. For completions, run `timetracking --generate-completion-script zsh`, or `bash` or `fish`.

## Start, stop, and look

```sh
timetracking start "Clarify noise model" --project "Noise paper"
timetracking status
timetracking stop
```

A start stops whatever runs. Add `--at 2026-10-29T09:15` for something you began earlier, up to 24 hours back. The tool never guesses a project, so without `--project` the entry has none.

## Continue something

```sh
timetracking continue                       # the latest entry
timetracking continue --project "Noise paper"
timetracking continue --task "noise"        # the latest entry whose task contains this
```

## Name things unambiguously

Names match without regard to case or accents. If two clients have a project with the same name, the tool exits with code 3 and lists them. Use `--client University`, or write `University/Admin`.

## List and sum

```sh
timetracking entries                        # today
timetracking entries --from -7d --project "Noise paper"
timetracking report                         # this week by client, area, and project
timetracking report --month last-month --group-by project,task --hours
```

Ranges are half-open: `--from A --to B` stops before day B. Dates can be `2026-10-29`, `2026-W44`, `2026-10`, `today`, `yesterday`, `last-week`, `last-month`, or relative such as `-3d`.

## Add or change entries

```sh
timetracking entry create "Standup" --start 2026-10-29T09:00 --end 2026-10-29T09:15 --project Admin
timetracking entry edit <id> --task "Standup and planning"
timetracking entry delete <id> --yes
```

The commands refuse overlaps unless you add `--force`, and they refuse times in the future. To get an entry's id, list entries with `--json`.

## Manage projects

```sh
timetracking projects
timetracking project create "Grant renewal" --area Research --client University
timetracking project archive "Grant renewal"
timetracking area set-color Research --color "#0A9396"
```

No command deletes a project, area, or client. Every command has `--help`, and the [scripting spec](../reference/automation.md#3-the-command-line-tool) lists them all.
