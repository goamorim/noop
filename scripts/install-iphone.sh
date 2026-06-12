#!/usr/bin/env bash
# Build + install the NOOP iOS app on the connected iPhone with a free Apple ID.
# Mirrors Vital Relay's install flow. Run scripts/generate-ios-free.sh first
# (or this script does it for you).
#
#   bash scripts/install-iphone.sh
#
# If signing fails with "No Account for Team", open Xcode → Settings → Accounts
# and re-enter your Apple ID once, then re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

VR_TEAM_ID="${VR_TEAM_ID:-757M2JFL73}"
SCHEME="NOOPiOS"

# Resolve the connected iPhone's hardware UDID (e.g. 00008150-001415260C6A401C).
# xcodebuild's -destination wants this hardware UDID, and devicectl accepts it too
# (it resolves to the CoreDevice internally), so one id drives both steps.
# NB: parse xctrace, not `devicectl list ... | awk '{print $(NF-2)}'` — a device named
# "Goncalo's iPhone 17 Pro" with model "iPhone 17 Pro (...)" shifts the columns and that
# awk grabbed the literal "17", producing `-destination id=17` and a build failure.
DEVICE_ID="$(xcrun xctrace list devices 2>&1 \
  | grep -i 'iphone' | grep -vi 'simulator' \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}' | head -1)"
if [[ -z "$DEVICE_ID" ]]; then
  echo "✗ No connected iPhone found. Plug it in / unlock it and retry."
  exit 1
fi
echo "▶ iPhone: $DEVICE_ID   ·   Team: $VR_TEAM_ID"

if [[ ! -d Strand.xcodeproj ]] || [[ ! -f project-ios-free.yml ]]; then
  echo "▶ Generating free iOS project…"
  VR_TEAM_ID="$VR_TEAM_ID" bash scripts/generate-ios-free.sh >/dev/null
fi

echo "▶ Building + signing $SCHEME for the device…"
xcodebuild -project Strand.xcodeproj -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  ENABLE_DEBUG_DYLIB=NO \
  DEVELOPMENT_TEAM="$VR_TEAM_ID" \
  build

APP_PATH="$(xcodebuild -project Strand.xcodeproj -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/ {print $2; exit}')"

echo "▶ Installing $APP_PATH …"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "✔ Installed. First launch: Settings → General → VPN & Device Management → trust your Apple ID."
echo "  Note: the WHOOP strap holds ONE Bluetooth link — disconnect it from the Mac / Vital Relay"
echo "  before connecting it in NOOP."
