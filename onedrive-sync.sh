#!/bin/bash

REMOTE_NAME="onedrive"
DEST="/Volumes/My Passport/OneDrive"

echo "=== OneDrive Backup Script ==="

# 1. Check if rclone is installed
if ! command -v rclone &> /dev/null
then
    echo "Error: rclone is not installed."
    echo "Install it with: brew install rclone"
    exit 1
fi

# 2. Check if remote exists
if ! rclone listremotes | grep -q "^${REMOTE_NAME}:"
then
    echo "Remote '${REMOTE_NAME}' is not configured."
    echo "Starting rclone config..."
    rclone config
fi

# 3. Check destination
if [ ! -d "$DEST" ]; then
    echo "Error: destination path does not exist:"
    echo "$DEST"
    exit 1
fi

echo ""
echo "Select mode:"
echo "1 - Mirror (sync: local will match cloud, local deletions allowed)"
echo "2 - Safe copy (no deletions, only downloads)"
echo "3 - Force re-download (overwrite everything locally)"
read -p "Enter choice (1/2/3): " MODE

echo ""

COMMON_FLAGS=(
  --progress
  --transfers=8
  --checkers=16
  --fast-list
  --log-file=rclone.log
  --log-level=INFO
  --exclude "Personal Vault/**"
  --filter-from filter.txt
  --tpslimit=20
  --onedrive-chunk-size 50M
  --multi-thread-streams 4
  --multi-thread-cutoff 25M
  --buffer-size 32M
  --timeout=30s
  --contimeout=30s
  --retries=10
  --retries-sleep=15s
  --low-level-retries=10
  --onedrive-no-versions
)

# 4. Execute based on mode
if [ "$MODE" == "1" ]; then
    echo "Running MIRROR mode (sync)..."
    rclone sync "$REMOTE_NAME": "$DEST" "${COMMON_FLAGS[@]}"

elif [ "$MODE" == "2" ]; then
    echo "Running SAFE COPY mode..."
    rclone copy "$REMOTE_NAME": "$DEST" "${COMMON_FLAGS[@]}"

elif [ "$MODE" == "3" ]; then
    echo "Running FORCE RE-DOWNLOAD mode..."
    rclone copy "$REMOTE_NAME": "$DEST" \
        "${COMMON_FLAGS[@]}" \
        --ignore-existing=false \
        --checksum

else
    echo "Invalid option."
    exit 1
fi

echo ""
echo "Done."

