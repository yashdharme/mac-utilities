#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release

APP="$ROOT/MacSpeed.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/MacSpeed" "$APP/Contents/MacOS/MacSpeed"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf 'Built %s\n' "$APP"
