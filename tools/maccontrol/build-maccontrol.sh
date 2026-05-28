#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/OpenClawTools/MacControl}"
APP="$HOME/Applications/MacControl.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

swiftc "$ROOT/MacControl.swift" \
  -framework AppKit \
  -framework CoreGraphics \
  -o "$APP/Contents/MacOS/MacControl"

chmod +x "$APP/Contents/MacOS/MacControl"

SIGN_IDENTITY="${MACCONTROL_SIGN_IDENTITY:--}"
REQUIREMENT='=designated => identifier "app.openclaw.maccontrol"'

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --requirements "$REQUIREMENT" "$APP" >/dev/null
elif ! codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1; then
  codesign --force --deep --sign - --requirements "$REQUIREMENT" "$APP" >/dev/null
fi

echo "$APP"
