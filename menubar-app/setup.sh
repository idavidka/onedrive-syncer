#!/bin/bash
# Sets up the OneDrive Sync menubar app by installing Python dependencies
# into a local vendor/ directory — no system-wide installation required.
set -e

cd "$(dirname "$0")"

echo "=== OneDrive Sync — Menubar App Setup ==="
echo ""

# Check python3
if ! command -v python3 &>/dev/null; then
  echo "Error: python3 not found."
  echo "Install Xcode Command Line Tools and try again:"
  echo "  xcode-select --install"
  exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print(sys.version)')
echo "Python: $PY_VERSION"
echo ""

# Install rumps and pyobjc into local vendor/
echo "Installing dependencies into ./vendor/ ..."
python3 -m pip install \
  --target ./vendor \
  --quiet \
  --disable-pip-version-check \
  rumps

echo ""
echo "All done!"
echo ""
echo "To start the menubar app:"
echo "  bash menubar-app/start.sh"
echo ""
echo "To launch automatically at login, see the README."
