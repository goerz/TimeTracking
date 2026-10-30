#!/bin/sh
# Build phase of the Mac app: writes the agent's launchd plist into
# Contents/Library/LaunchAgents/<APP_ID>.agent.plist (spec_architecture.md §1.4).
# Runs before the app is signed, so the plist is sealed in the signature.
set -eu

label="${TT_APP_ID:?}.agent"
# The agent is TimeTrackingAgent.app, in Debug TimeTrackingAgent Debug.app (§2.2).
program="Contents/Library/LoginItems/${TT_AGENT_NAME:?}.app/Contents/MacOS/TimeTrackingAgent"
dir="${TARGET_BUILD_DIR:?}/${CONTENTS_FOLDER_PATH:?}/Library/LaunchAgents"
plist="$dir/$label.plist"

mkdir -p "$dir"
# Remove plists of other identities (e.g. after a BUNDLE_ID change).
find "$dir" -name '*.plist' ! -name "$label.plist" -delete

tmp="$plist.tmp"
cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>${TT_APP_ID}</string>
	</array>
	<key>BundleProgram</key>
	<string>${program}</string>
	<key>KeepAlive</key>
	<true/>
	<key>Label</key>
	<string>${label}</string>
	<key>MachServices</key>
	<dict>
		<key>${label}</key>
		<true/>
	</dict>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
PLIST
plutil -lint -s "$tmp"
mv "$tmp" "$plist"
