# Keep projects in line with a description file

If you keep your structure elsewhere, for example in a planning document, a description file states what the store should hold.

## Write the file

The file is TOML. It lists each client, its areas with their colors, and the standing projects that must be active. An area named like its client is the general area.

```toml
version = 1

[[client]]
name = "University"

  [[client.area]]
  name = "Research"
  color = "#0A9396"
  projects = ["Noise paper", "Grant renewal"]
```

## Check the store

```sh
timetracking check structure.toml
```

A matching store prints nothing and exits 0. Otherwise each difference prints as a line and the exit code is 6.

```text
color mismatch: University / Research is #2A9D8F, expected #0A9396
missing project: University / Research / Grant renewal
```

Add `--client University` to look at one client. Add `--strict` to also report active projects that the file doesn't list, which helps when a generator writes the file from another system.

## Fix what can be fixed

```sh
timetracking check structure.toml --fix
```

This creates missing clients, areas, and projects, sets colors, and reactivates retired areas and archived standing projects. It never archives, moves, renames, or deletes anything, so what remains prints afterward for you to settle by hand. The [rules](../reference/automation.md#4-the-description-file-and-check) are in the reference.
