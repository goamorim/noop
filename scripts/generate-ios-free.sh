#!/usr/bin/env bash
# Generate the NOOP iOS Xcode project in FREE-signing mode so it can be
# sideloaded onto an iPhone with a free Apple ID (no paid Apple Developer
# Program). Mirrors Vital Relay's generate-xcodeproj.sh FREE path.
#
# The committed project.yml stays the pristine paid/CI source. This script
# patches a TEMP copy and points xcodegen at it, so git stays clean.
#
# Changes vs project.yml:
#   - NOOPiOS bundle id  -> com.goncalo.noop      (com.noopapp.noop is the real
#                                                  project's id and would conflict)
#   - DEVELOPMENT_TEAM    -> $VR_TEAM_ID (default 757M2JFL73)
#   - entitlements        -> StrandiOS/Resources/NOOP.free.entitlements
#                            (no HealthKit, no App Group)
#   - removes the NOOPiOSWidgets target + its dependency (needs an App Group)
#
# Usage:  bash scripts/generate-ios-free.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${VR_TEAM_ID:-757M2JFL73}"
BUNDLE_ID="${NOOP_BUNDLE_ID:-com.goncalo.noop}"

python3 - "$TEAM_ID" "$BUNDLE_ID" <<'PY'
import sys, re, pathlib
team, bundle = sys.argv[1], sys.argv[2]
src = pathlib.Path("project.yml").read_text()

# Remove the entire NOOPiOSWidgets target block (from its header to the next
# top-level sibling target, or to a line that dedents back to 2 spaces and is
# not part of the block). We slice from "  NOOPiOSWidgets:" to the next
# "\n  <Name>:\n" sibling at 2-space indent, else to EOF.
def next_sibling(text, after):
    m = re.search(r"\n  [A-Za-z0-9_]+:\n", text[after:])
    return after + m.start() + 1 if m else len(text)

w = src.index("\n  NOOPiOSWidgets:\n") + 1
w_end = next_sibling(src, w + 1)
src = src[:w] + src[w_end:]

# Patch the NOOPiOS block.
start = src.index("\n  NOOPiOS:\n") + 1
end = next_sibling(src, start + 1)
head, block, tail = src[:start], src[start:end], src[end:]

block = block.replace("PRODUCT_BUNDLE_IDENTIFIER: com.noopapp.noop",
                      f"PRODUCT_BUNDLE_IDENTIFIER: {bundle}")
block = block.replace('DEVELOPMENT_TEAM: ""', f'DEVELOPMENT_TEAM: "{team}"')
block = re.sub(
    r"    entitlements:\n      path: StrandiOS/Resources/NOOP\.entitlements\n"
    r"      properties:\n(?:        .*\n|          .*\n)*",
    "    entitlements:\n      path: StrandiOS/Resources/NOOP.free.entitlements\n",
    block,
)
block = block.replace("      - target: NOOPiOSWidgets\n", "")

out = head + block + tail
out = out.replace('    DEVELOPMENT_TEAM: ""', f'    DEVELOPMENT_TEAM: "{team}"', 1)
out = out.replace("  bundleIdPrefix: com.noopapp", "  bundleIdPrefix: com.goncalo")

pathlib.Path("project-ios-free.yml").write_text(out)
print(f"wrote project-ios-free.yml (team={team}, bundle={bundle}, no HealthKit/App-Group, no widgets)")
PY

echo "▶ xcodegen generate (spec: project-ios-free.yml)…"
xcodegen generate --spec project-ios-free.yml
echo "✔ Strand.xcodeproj generated — NOOPiOS FREE (team $TEAM_ID, bundle $BUNDLE_ID)."
