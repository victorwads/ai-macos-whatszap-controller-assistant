#!/bin/sh

set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SCHEME="AssistantMCPServer"
PROJECT_FILE="$REPO_DIR/AssistantMCPServer.xcodeproj"
DERIVED_DATA_DIR="$REPO_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/AssistantMCPServer.app"

echo "Closing running AssistantMCPServer instances..."
osascript -e 'tell application "AssistantMCPServer" to quit' >/dev/null 2>&1 || true
pkill -x AssistantMCPServer 2>/dev/null || true
pkill -f 'debugserver.*AssistantMCPServer' 2>/dev/null || true

shutdown_checks=0
while pgrep -x AssistantMCPServer >/dev/null 2>&1; do
  shutdown_checks=$((shutdown_checks + 1))
  if [ "$shutdown_checks" -ge 5 ]; then
    echo "Forcing stuck AssistantMCPServer instances to close..."
    pkill -9 -x AssistantMCPServer 2>/dev/null || true
    pkill -9 -f 'debugserver.*AssistantMCPServer' 2>/dev/null || true
  fi
  if [ "$shutdown_checks" -ge 10 ]; then
    echo "Continuing even though macOS still reports a terminating AssistantMCPServer process."
    break
  fi
  sleep 1
done

echo "Generating Xcode project..."
cd "$REPO_DIR"
xcodegen generate

echo "Building $SCHEME..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

echo "Opening built app..."
open -n "$APP_PATH"
