#!/bin/sh
# Build phase of the apps, Debug only (architecture.md §2.5, §3.4):
# copies Fixtures/Store/*.json into the bundle's Resources/Fixtures/Store, so
# `-UITesting YES -Fixture <name>` finds them without reading the source tree
# (which a protected folder such as ~/Documents may put behind a prompt).
set -eu

[ "${CONFIGURATION:-}" = Debug ] || exit 0

dir="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/Fixtures/Store"
mkdir -p "$dir"
for file in "${SRCROOT:?}"/Fixtures/Store/*.json; do
    cp -p "$file" "$dir/"
done
