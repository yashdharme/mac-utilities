#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release --product MacClip

APP="$ROOT/MacClip.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/MacClip" "$APP/Contents/MacOS/MacClip"
cp "$ROOT/Info-clip.plist" "$APP/Contents/Info.plist"
printf 'Built %s\n' "$APP"
