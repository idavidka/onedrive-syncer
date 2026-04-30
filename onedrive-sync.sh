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

# Spinner helper: show_spinner PID [message]
show_spinner() {
  local pid=$1 msg="${2:-Loading...}"
  local spin='|/-\' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s " "$msg" "${spin:$((i % 4)):1}"
    sleep 0.1
    i=$(( i + 1 ))
  done
  printf "\r\033[K"
}

# Interactive remote folder browser
# Sets INTERACTIVE_PATH to the chosen remote path (empty = root)
select_remote_folder() {
  local current_path=""
  while true; do
    echo ""
    if [ -z "$current_path" ]; then
      echo "  Location: (root)"
    else
      echo "  Location: /${current_path}"
    fi
    echo ""
    local tmp_listing
    tmp_listing=$(mktemp)
    rclone lsf --dirs-only "${REMOTE_NAME}:${current_path}" > "$tmp_listing" 2>/dev/null &
    local rclone_pid=$!
    show_spinner "$rclone_pid" "Loading folders..."
    wait "$rclone_pid"
    local rclone_exit=$?
    local dirs=()
    while IFS= read -r line; do
      line="${line%/}"
      [ -n "$line" ] && dirs+=("$line")
    done < "$tmp_listing"
    rm -f "$tmp_listing"
    if [ $rclone_exit -ne 0 ]; then
      echo "  [!] Could not list folders (network/connection error)"
    elif [ ${#dirs[@]} -eq 0 ]; then
      echo "  (no subfolders in this location)"
    fi
    echo "  0 - [Sync this folder]"
    for i in "${!dirs[@]}"; do
      printf "  %d - %s\n" "$((i+1))" "${dirs[$i]}"
    done
    [ -n "$current_path" ] && echo "  b - [Go back]"
    echo "  q - [Cancel]"
    echo ""
    read -p "Select: " DIR_CHOICE
    if [[ "$DIR_CHOICE" == "0" ]]; then
      INTERACTIVE_PATH="$current_path"
      return 0
    elif [[ "$DIR_CHOICE" =~ ^[Bb]$ ]] && [ -n "$current_path" ]; then
      if [[ "$current_path" == */* ]]; then
        current_path="${current_path%/*}"
      else
        current_path=""
      fi
    elif [[ "$DIR_CHOICE" =~ ^[Qq]$ ]]; then
      INTERACTIVE_PATH=""
      return 1
    elif [[ "$DIR_CHOICE" =~ ^[0-9]+$ ]] && [ "$DIR_CHOICE" -ge 1 ] && [ "$DIR_CHOICE" -le "${#dirs[@]}" ]; then
      local selected="${dirs[$((DIR_CHOICE-1))]}"
      if [ -z "$current_path" ]; then
        current_path="$selected"
      else
        current_path="${current_path}/${selected}"
      fi
    else
      echo "  Invalid choice."
    fi
  done
}

# Build a temporary rclone filter file for the given remote path
build_interactive_filter() {
  local path="$1"
  local tmp_filter="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/filter-interactive.txt"
  : > "$tmp_filter"
  echo "- /Personal Vault/**" >> "$tmp_filter"
  if [ -n "$path" ]; then
    local partial="" part
    local parts
    IFS='/' read -ra parts <<< "$path"
    for part in "${parts[@]}"; do
      if [ -z "$partial" ]; then
        partial="$part"
      else
        partial="${partial}/${part}"
      fi
      echo "+ /${partial}/" >> "$tmp_filter"
    done
    echo "+ /${path}/**" >> "$tmp_filter"
  else
    echo "+ */" >> "$tmp_filter"
  fi
  echo "- **" >> "$tmp_filter"
  echo "$tmp_filter"
}

# 4. Last run / new run selection
LAST_RUN_FILE="last-run.conf"
USE_LAST_RUN=false
INTERACTIVE_PATH=""
if [ -f "$LAST_RUN_FILE" ]; then
  LR_FILTER="" LR_INTERACTIVE_PATH="" LR_STRATEGY="" LR_MODE="" LR_TRANSFERS="" LR_CHECKERS="" LR_DEST=""
  while IFS='=' read -r key val; do
    val="${val%\"}"
    val="${val#\"}"
    case "$key" in
      SELECTED_FILTER)  LR_FILTER="$val" ;;
      INTERACTIVE_PATH) LR_INTERACTIVE_PATH="$val" ;;
      STRATEGY)         LR_STRATEGY="$val" ;;
      MODE)             LR_MODE="$val" ;;
      TRANSFERS)        LR_TRANSFERS="$val" ;;
      CHECKERS)         LR_CHECKERS="$val" ;;
      DEST)             LR_DEST="$val" ;;
    esac
  done < "$LAST_RUN_FILE"
  echo ""
  echo "Previous run settings:"
  if [ -n "$LR_INTERACTIVE_PATH" ]; then
    echo "  Filter:    [Interactive] /${LR_INTERACTIVE_PATH}"
  else
    echo "  Filter:    ${LR_FILTER:-none}"
  fi
  echo "  Dest:      ${LR_DEST:-$DEST}"
  echo "  Strategy:  $LR_STRATEGY"
  echo "  Mode:      $LR_MODE"
  echo "  Transfers: $LR_TRANSFERS"
  echo "  Checkers:  $LR_CHECKERS"
  echo ""
  read -p "Use previous settings? [Y/n]: " USE_LAST_INPUT
  if [[ ! "$USE_LAST_INPUT" =~ ^[Nn]$ ]]; then
    USE_LAST_RUN=true
    INTERACTIVE_PATH="$LR_INTERACTIVE_PATH"
    STRATEGY="$LR_STRATEGY"
    MODE="$LR_MODE"
    TRANSFERS="$LR_TRANSFERS"
    CHECKERS="$LR_CHECKERS"
    [ -n "$LR_DEST" ] && DEST="$LR_DEST"
    if [ -n "$INTERACTIVE_PATH" ]; then
      SELECTED_FILTER=$(build_interactive_filter "$INTERACTIVE_PATH")
      echo "Rebuilt interactive filter for: /${INTERACTIVE_PATH:-(root)}"
    else
      SELECTED_FILTER="$LR_FILTER"
    fi
    echo "Using previous settings."
  fi
fi

if [ "$USE_LAST_RUN" = false ]; then
  echo ""
  echo "Select filter:"
  FILTER_FILES=()
  for f in filter*.txt; do
    [ -f "$f" ] && FILTER_FILES+=("$f")
  done
  echo "  i - Interactive folder browser"
  for i in "${!FILTER_FILES[@]}"; do
    echo "  $((i+1)) - ${FILTER_FILES[$i]}"
  done
  echo "  0 - No filter"
  read -p "Enter choice [default: 0]: " FILTER_CHOICE
  FILTER_CHOICE=${FILTER_CHOICE:-0}
  if [[ "$FILTER_CHOICE" =~ ^[Ii]$ ]]; then
    if select_remote_folder; then
      SELECTED_FILTER=$(build_interactive_filter "$INTERACTIVE_PATH")
      echo "Filter built for: /${INTERACTIVE_PATH:-(root)}"
    else
      echo "Cancelled. No filter selected."
      SELECTED_FILTER=""
      INTERACTIVE_PATH=""
    fi
  elif [[ "$FILTER_CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$FILTER_CHOICE" -le "${#FILTER_FILES[@]}" ]; then
    SELECTED_FILTER="${FILTER_FILES[$((FILTER_CHOICE-1))]}"
    INTERACTIVE_PATH=""
    echo "Using filter: $SELECTED_FILTER"
  else
    echo "No filter selected."
    SELECTED_FILTER=""
    INTERACTIVE_PATH=""
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
  read -p "Destination folder [default: ${DEST}]: " INPUT_DEST
  DEST=${INPUT_DEST:-$DEST}
fi

# 3. Check destination
if [ ! -d "$DEST" ]; then
  echo "Error: destination path does not exist:"
  echo "$DEST"
  exit 1
fi

# Save settings for next run
{
  echo "SELECTED_FILTER=\"${SELECTED_FILTER}\""
  echo "INTERACTIVE_PATH=\"${INTERACTIVE_PATH}\""
  echo "DEST=\"${DEST}\""
  echo "STRATEGY=\"${STRATEGY}\""
  echo "MODE=\"${MODE}\""
  echo "TRANSFERS=\"${TRANSFERS}\""
  echo "CHECKERS=\"${CHECKERS}\""
} > "$LAST_RUN_FILE"

# Build filter flag
FILTER_FLAG=()
if [ -n "$SELECTED_FILTER" ] && [ -f "$SELECTED_FILTER" ]; then
  FILTER_FLAG=(--filter-from "$SELECTED_FILTER")
fi

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

# Log selected options before run
LOG_FILE="rclone.log"
{
  echo "================================================================"
  echo "Started:    $(date '+%Y-%m-%d %H:%M:%S')"
  if [ -n "$INTERACTIVE_PATH" ]; then
    echo "Filter:     [Interactive] /${INTERACTIVE_PATH}"
  else
    echo "Filter:     ${SELECTED_FILTER:-none}"
  fi
  echo "Dest:       ${DEST}"
  echo "Strategy:   ${STRATEGY}"
  echo "Mode:       ${MODE} ($([ "$MODE" == "1" ] && echo "Mirror/sync" || ([ "$MODE" == "2" ] && echo "Safe copy" || echo "Force re-download")))"
  echo "Transfers:  ${TRANSFERS}"
  echo "Checkers:   ${CHECKERS}"
  echo "================================================================"
} >> "$LOG_FILE"

# 4. Execute based on mode
if [ "$MODE" == "1" ]; then
    echo "Running MIRROR mode (sync)..."
    rclone sync "$REMOTE_NAME": "$DEST" "${COMMON_FLAGS[@]}"
    RCLONE_EXIT=$?

elif [ "$MODE" == "2" ]; then
    echo "Running SAFE COPY mode..."
    rclone copy "$REMOTE_NAME": "$DEST" "${COMMON_FLAGS[@]}"
    RCLONE_EXIT=$?

elif [ "$MODE" == "3" ]; then
    echo "Running FORCE RE-DOWNLOAD mode..."
    rclone copy "$REMOTE_NAME": "$DEST" \
        "${COMMON_FLAGS[@]}" \
        --ignore-existing=false \
        --ignore-size=false \
        --checksum
    RCLONE_EXIT=$?

else
    echo "Invalid option."
    exit 1
fi

echo ""
if [ $RCLONE_EXIT -ne 0 ]; then
  echo "Error: rclone exited with code $RCLONE_EXIT"
  echo ""
  echo "Last errors from log:"
  grep -E "ERROR|CRITICAL" "$LOG_FILE" | tail -5
else
  echo "Done."
fi

