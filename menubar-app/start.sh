#!/bin/bash
# Launches the OneDrive Sync menubar app in the background.
# Double-click this file in Finder, or run it from Terminal.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$SCRIPT_DIR/menubar-app/onedrive-menubar.py"
VENDOR="$SCRIPT_DIR/menubar-app/vendor"

if [ ! -d "$VENDOR" ]; then
  echo "Dependencies not installed. Running setup first..."
  bash "$SCRIPT_DIR/menubar-app/setup.sh"
fi

echo "Starting OneDrive Sync menubar app..."
exec python3 "$APP"
