#!/bin/sh
# Build phase of the two apps, Debug only (spec_architecture.md §4.3):
# SwiftFormat rewrites the sources; SwiftLint fixes what it can and reports
# the rest as build warnings and errors.
set -eu

[ "${CONFIGURATION:-}" = Debug ] || exit 0

root="${SRCROOT:?}"
# BUILD_DIR is <derived data>/Build/Products; packages are next to Build/.
packages="${BUILD_DIR%/Build/*}/SourcePackages"
bin=$("$root/scripts/lint_tools.sh" "$1" "$packages")
. "$root/scripts/lint_paths.sh"

cd "$root"
case "$1" in
swiftformat)
    # shellcheck disable=SC2086
    "$bin" --quiet --config .swiftformat $LINT_PATHS
    ;;
swiftlint)
    # shellcheck disable=SC2086
    "$bin" lint --fix --quiet --config .swiftlint.yml $LINT_PATHS >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    "$bin" lint --quiet --config .swiftlint.yml --reporter xcode $LINT_PATHS
    ;;
esac
