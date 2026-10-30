#!/usr/bin/env bash
# Render every src/<name>.html to <name>.png with headless Chrome at 2x.
# The canvas size (in points) comes from <meta name="mockup-size" content="W,H"> in each file.
# Usage: ./render.sh [name ...]   (no arguments: render all)
set -euo pipefail

cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [ "$#" -gt 0 ]; then
  files=()
  for n in "$@"; do files+=("src/${n%.html}.html"); done
else
  files=(src/*.html)
fi

for src in "${files[@]}"; do
  name="$(basename "$src" .html)"
  size="$(sed -n 's/.*<meta name="mockup-size" content="\([0-9]*\),\([0-9]*\)".*/\1,\2/p' "$src" | head -n 1)"
  if [ -z "$size" ]; then
    echo "skip $src: no mockup-size meta tag" >&2
    continue
  fi
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size="$size" --screenshot="$PWD/$name.png" "file://$PWD/$src" >/dev/null 2>&1
  echo "$name.png ($size pt)"
done
