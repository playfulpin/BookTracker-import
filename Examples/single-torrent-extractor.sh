#!/bin/bash

#
#  Updated for WSL2 Linux Native aria2c Execution
#  single-torrent-extractor.sh
# from project root call will look like:
# ./bin/single-torrent-extractor.sh ./data/torrents/flibusta_all_local-2026-08-01.torrent xxx_flibusta_all_local-2026-08-01.inpx
#

# --- CONFIGURATION ---
ARIA2_BIN="aria2c" 
ROOT_DIR="/Downloads/flibusta_snapshot"
OUT_DIR="$ROOT_DIR/inpx"
# ---------------------

# Verify both arguments are passed
if [ $# -lt 2 ]; then
    echo "Usage: $0 <path_to_torrent_file> <new_filename>"
    echo "Example: $0 flibusta_all_local-2026-08-01.torrent xxx_flibusta_all_local-2026-08-01.inpx"
    exit 1
fi

LINUX_TORRENT_FILE="$1"
NEW_NAME="$2"

# Verify the torrent file actually exists
if [ ! -f "$LINUX_TORRENT_FILE" ]; then
    echo "Error: Torrent file not found at: $LINUX_TORRENT_FILE"
    exit 1
fi

echo "=========================================================="
echo " Launching WSL2 aria2c for Single-File Torrent Download"
echo " Saving to: $OUT_DIR/$NEW_NAME"
echo "=========================================================="

# High-Performance configuration flags packed cleanly into a Bash Array
ARIA_FLAGS=(
    --file-allocation=none
    --bt-max-peers=150
    --summary-interval=3
    --enable-dht=true
    --bt-enable-lpd=true
    --seed-time=0
    --max-overall-download-limit=0
    --bt-max-open-files=200
    --peer-id-prefix=-TR2940-
    --dir="$OUT_DIR"
    --allow-overwrite=true
    # Force rename the single file (Index 1) to your second argument
    --index-out=1="$NEW_NAME"
)

# Output suppression configuration array
GREP_FLAGS=(
    -v
    -E
    "booktracker|Tracker returned null data|Exception:.*DefaultBtAnnounce"
)

# Execute aria2c and pipe through the clean output filter
"$ARIA2_BIN" "${ARIA_FLAGS[@]}" "$LINUX_TORRENT_FILE" 2>&1 | grep "${GREP_FLAGS[@]}"

echo "=========================================================="
echo " Download finished. Process exited safely."
echo "=========================================================="
