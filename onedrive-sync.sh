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
echo "Select filter file (or press Enter for no filter):"
FILTER_FILES=()
for f in filter*.txt; do
  [ -f "$f" ] && FILTER_FILES+=("$f")
done
for i in "${!FILTER_FILES[@]}"; do
  echo "$((i+1)) - ${FILTER_FILES[$i]}"
done
echo "0 - No filter"
read -p "Enter choice [default: 0]: " FILTER_CHOICE
FILTER_CHOICE=${FILTER_CHOICE:-0}
FILTER_FLAG=()
if [[ "$FILTER_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$FILTER_CHOICE" -le "${#FILTER_FILES[@]}" ]; then
  SELECTED_FILTER="${FILTER_FILES[$((FILTER_CHOICE-1))]}"
  echo "Using filter: $SELECTED_FILTER"
  FILTER_FLAG=(--filter-from "$SELECTED_FILTER")
else
  echo "No filter selected."
fi

echo ""
echo "Select listing strategy:"
echo "A - Delta (lists ALL files first ~8-10min, then transfers without interruption)"
echo "B - Classic (starts transferring immediately, may hit rate limits)"
read -p "Enter choice (A/B): " STRATEGY
STRATEGY=$(echo "$STRATEGY" | tr '[:lower:]' '[:upper:]')

echo ""
echo "Select mode:"
echo "1 - Mirror (sync: local will match cloud, local deletions allowed)"
echo "2 - Safe copy (no deletions, only downloads)"
echo "3 - Force re-download (overwrite everything locally)"
read -p "Enter choice (1/2/3): " MODE

echo ""

COMMON_FLAGS=(
  --progress
  --log-file=rclone.log
  --log-level=INFO
  "${FILTER_FLAG[@]}"
  --onedrive-chunk-size 25M
  --multi-thread-streams 4
  --multi-thread-cutoff 25M
  --buffer-size 32M
  --timeout=60s
  --contimeout=30s
  --retries=10
  --retries-sleep=15s
  --low-level-retries=10
  --onedrive-no-versions
  --ignore-size
  --modify-window=1m
  --local-unicode-normalization
)

if [[ "$STRATEGY" == "A" ]]; then
  DEFAULT_TRANSFERS=16
  DEFAULT_CHECKERS=4
else
  DEFAULT_TRANSFERS=8
  DEFAULT_CHECKERS=16
fi

read -p "Transfers (parallel downloads) [default: ${DEFAULT_TRANSFERS}]: " INPUT_TRANSFERS
read -p "Checkers (parallel metadata checks) [default: ${DEFAULT_CHECKERS}]: " INPUT_CHECKERS
TRANSFERS=${INPUT_TRANSFERS:-$DEFAULT_TRANSFERS}
CHECKERS=${INPUT_CHECKERS:-$DEFAULT_CHECKERS}

echo ""

if [[ "$STRATEGY" == "A" ]]; then
    echo "Running with DELTA listing strategy..."
  COMMON_FLAGS+=(
    --transfers="${TRANSFERS}"
    --checkers="${CHECKERS}"
    --fast-list
    --onedrive-delta
    --tpslimit=25
  )
else
  echo "Running with CLASSIC listing strategy..."
  COMMON_FLAGS+=(
    --transfers="${TRANSFERS}"
    --checkers="${CHECKERS}"
    --tpslimit=20
  )
fi

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
        --ignore-size=false \
        --checksum

else
    echo "Invalid option."
    exit 1
fi

echo ""
echo "Done."

