#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# ///
"""Checks that every citation of a spec names a section that exists
(architecture.md §3.2).

    scripts/check_citations.py [--root DIR] [--count]

A citation is the name of a file in docs/reference/, alone or as a Markdown
link, followed by section numbers: `timer.md §2.1, §5`, or the numbers of a
spec's own prose, `data_and_sync.md 1.5`. A list may wrap to the next comment
line, and "rule 4" or "item 6" may follow a number. Sections are the numbered
headings of the cited file. A `§n` without a file name counts when a spec the
same file cites has that section; a spec also looks in itself, and a file that
names no spec in architecture.md, whose conventions it follows. Exits 1 and
lists every citation that resolves to nothing. Only files git tracks count, so
untracked notes never block a push.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

SPECS = "docs/reference"
NUMBER = r"\d+(?:\.\d+)*"
# The break between two parts of a citation: nothing, or a line wrap with the
# next line's comment marker.
WRAP = r"[ \t]*(?:\n[ \t]*(?:///?|/?\*+|#)?[ \t]*)?"
TAIL = r"(?:[ \t]+(?:rule|item)s?[ \t]+\d+)?"
HEADING = re.compile(rf"^#+\s+({NUMBER})\.?\s", re.MULTILINE)
BARE = re.compile(rf"§({NUMBER})")


def sections_of(root):
    """The numbered sections of each spec, by file name."""
    return {
        path.name: set(HEADING.findall(path.read_text()))
        for path in (root / SPECS).glob("*.md")
        if path.name != "index.md"
    }


def tracked_text_files(root):
    names = subprocess.run(
        ["git", "ls-files", "--cached"],
        cwd=root,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    for name in names:
        path = root / name
        if not path.is_file() or path.is_symlink():
            continue
        try:
            yield name, path.read_text()
        except UnicodeDecodeError:
            continue


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def citations(text, sections):
    """Each (spec, section, offset) that names its file, and the spans of the
    `§n` they cover, and the specs the text names at all."""
    names = "|".join(re.escape(name) for name in sorted(sections, key=len, reverse=True))
    mention = re.compile(rf"(?<![\w/.-])(?:docs/reference/)?({names})(?:\]\([^)\n]*\))?`?")
    first = re.compile(rf"{WRAP}(?:§({NUMBER})|(\d+\.\d+)(?![\w.]))")
    more = re.compile(rf"{TAIL}(?:,|;|,? and|,? to){WRAP}§({NUMBER})")
    found, covered, named = [], [], set()
    for match in mention.finditer(text):
        spec = match.group(1)
        named.add(spec)
        position = match.end()
        head = first.match(text, position)
        if not head:
            continue
        found.append((spec, head.group(1) or head.group(2), head.start()))
        covered.append(head.span())
        position = head.end()
        while follow := more.match(text, position):
            found.append((spec, follow.group(1), follow.start()))
            covered.append(follow.span())
            position = follow.end()
    return found, covered, named


def check(root):
    sections = sections_of(root)
    errors, total = [], 0
    for name, text in tracked_text_files(root):
        if name == "scripts/check_citations.py":
            continue
        found, covered, named = citations(text, sections)
        total += len(found)
        for spec, section, offset in found:
            if section not in sections[spec]:
                errors.append(f"{name}:{line_of(text, offset)}: {spec} has no section {section}")
        own = Path(name).name if name.startswith(f"{SPECS}/") else None
        for match in BARE.finditer(text):
            if any(start <= match.start() < end for start, end in covered):
                continue
            total += 1
            candidates = named | ({own} if own in sections else set()) or {"architecture.md"}
            if not any(match.group(1) in sections[spec] for spec in candidates):
                errors.append(
                    f"{name}:{line_of(text, match.start())}: "
                    f"§{match.group(1)} is in none of {', '.join(sorted(candidates))}"
                )
    return errors, total


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--count", action="store_true", help="print the number of citations checked")
    args = parser.parse_args()
    errors, total = check(args.root)
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if args.count or errors:
        print(f"{total} citations, {len(errors)} unresolved")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
