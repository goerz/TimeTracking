#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Prints line counts of the tracked files, by area and by language.

    scripts/stats.py [--root DIR] [--cloc COMMAND]

The counting is cloc's, over the output of `git ls-files`, so build products
and untracked files don't count. Identical files count separately: cloc would
otherwise drop all but one of them.
"""

import argparse
import csv
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

PRODUCT_AREAS = {
    "Library": ("Packages/",),
    "Shared views": ("Shared/",),
    "Mac app": ("TimeTracking/",),
    "Agent": ("TimeTrackingAgent/",),
    "Tools": ("TimeTrackingCLI/", "TrackerEvent/"),
    "iOS app": ("TimeTrackingiOS/",),
    "iOS extensions": (
        "TimeTrackingWidgets/",
        "TimeTrackingIntents/",
        "TimeTrackingMonitor/",
        "TimeTrackingWebExtension/",
        "WidgetShared/",
        "CollectionShared/",
    ),
}
TESTS = "Tests"
BUILD = "Build and tooling"
DOCS = "Documentation"
DATA = "Data"
DOC_FILES = ("README.md", "CONTRIBUTING.md", "CLAUDE.md", "LICENSE")


def area(path):
    """The area of a tracked file; what no rule claims is build and tooling."""
    top = path.split("/")[0]
    if path.startswith(("Fixtures/", "AppResources/")) or ".xcassets/" in path:
        return DATA
    if (
        top.endswith("Tests")
        or top == "AppTestSupport"
        or path.startswith("Packages/TimeTrackingCore/Tests/")
    ):
        return TESTS
    if top == "docs" or path in DOC_FILES:
        return DOCS
    for name, prefixes in PRODUCT_AREAS.items():
        if path.startswith(prefixes):
            return name
    return BUILD


def count(root, cloc):
    """The rows (language, path, blank, comment, code), one per counted file."""
    tracked = subprocess.run(
        ["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True, text=True
    ).stdout
    result = subprocess.run(
        [cloc, "--list-file=-", "--quiet", "--by-file", "--csv", "--skip-uniqueness"],
        cwd=root,
        check=True,
        input=tracked.replace("\0", "\n"),
        capture_output=True,
        text=True,
    )
    rows = []
    for row in list(csv.reader(result.stdout.splitlines()))[1:]:
        if not row or row[0] == "SUM":
            continue
        language, *name, blank, comment, code = row
        rows.append((language, ",".join(name), int(blank), int(comment), int(code)))
    return rows


def add(totals, key, row):
    entry = totals[key]
    entry[0] += 1
    for index, value in enumerate(row[2:], start=1):
        entry[index] += value


def line(label, values):
    numbers = "".join(f"{value:>10,}" for value in values)
    return f"{label:<20}{numbers}"


def header(title):
    return f"{title:<20}" + "".join(
        f"{name:>10}" for name in ("Files", "Blank", "Comment", "Code")
    )


def report(rows):
    areas = defaultdict(lambda: [0, 0, 0, 0])
    languages = defaultdict(lambda: [0, 0, 0, 0])
    for row in rows:
        add(areas, area(row[1]), row)
        add(languages, row[0], row)

    def subtotal(names):
        return [sum(areas[name][i] for name in names) for i in range(4)]

    output = [header("Area")]
    output += [line(name, areas[name]) for name in PRODUCT_AREAS if name in areas]
    output.append(line("Product subtotal", subtotal(PRODUCT_AREAS)))
    output += [line(name, areas[name]) for name in (TESTS, BUILD, DOCS, DATA) if name in areas]
    output.append(line("Total", subtotal(list(areas))))
    output += ["", header("Language")]
    ranked = sorted(languages.items(), key=lambda item: -item[1][3])
    output += [line(name, values) for name, values in ranked]
    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).parent.parent)
    parser.add_argument("--cloc", default="cloc")
    args = parser.parse_args()
    cloc = shutil.which(args.cloc)
    if cloc is None:
        sys.exit(f"{args.cloc} not found; install it with `brew install cloc`")
    print(report(count(args.root, cloc)))


if __name__ == "__main__":
    main()
