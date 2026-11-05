#!/bin/sh
# Prints the path of the SwiftFormat or SwiftLint binary from the package
# checkouts (architecture.md §4.3, §5), building SwiftFormat once.
#
#   scripts/lint_tools.sh swiftformat|swiftlint <SourcePackages folder>
#
# SwiftLint comes as a binary artifact of SwiftLintPlugins; SwiftFormat is
# built from its checkout into <SourcePackages>/../LintTools/.
set -eu

tool="$1"
packages="$2"

case "$tool" in
swiftlint)
    bin=$(find "$packages/artifacts" -path '*SwiftLintBinary*/macos/*' -name swiftlint -type f -perm -u+x 2>/dev/null | head -n 1)
    if [ -z "$bin" ]; then
        echo "error: no SwiftLint binary under $packages/artifacts; resolve packages first" >&2
        exit 1
    fi
    echo "$bin"
    ;;
swiftformat)
    checkout="$packages/checkouts/SwiftFormat"
    if [ ! -f "$checkout/Package.swift" ]; then
        echo "error: no SwiftFormat checkout at $checkout; resolve packages first" >&2
        exit 1
    fi
    scratch="$(dirname "$packages")/LintTools/swiftformat"
    version=$(git -C "$checkout" rev-parse HEAD 2>/dev/null || echo unknown)
    bin="$scratch/release/swiftformat"
    stamp="$scratch/.built-from"
    if [ ! -x "$bin" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$version" ]; then
        mkdir -p "$scratch"
        echo "Building SwiftFormat from $checkout (once per version)..." >&2
        # A clean environment: build phases export SDKROOT and friends for the
        # target platform, which must not leak into this host build.
        /usr/bin/lockf "$scratch.lock" /usr/bin/env -i PATH=/usr/bin:/bin HOME="$HOME" \
            DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            /usr/bin/swift build -c release --package-path "$checkout" --scratch-path "$scratch" \
            --product swiftformat >&2
        echo "$version" > "$stamp"
    fi
    echo "$bin"
    ;;
*)
    echo "usage: $0 swiftformat|swiftlint <SourcePackages folder>" >&2
    exit 64
    ;;
esac
