#!/bin/bash

#  multifile-torrent-extractor.sh
# from project root call will look like:
# ./bin/multifile-torrent-extractor.sh ./data/torrents/flibusta_FullDump.torrent
#

# --- CONFIGURATION ---
ARIA2_BIN="aria2c"
ROOT_DIR="/Downloads/flibusta_snapshot"
OUT_DIR="$ROOT_DIR"  # Updated target base directory

WANTED_PATTERNS=(
    "lib.libavtor.sql.gz"
    "lib.libavtorname.sql.gz"
    "lib.libbook.sql.gz"
    "lib.libfilename.sql.gz"
    "lib.libgenre.sql.gz"
    "lib.libgenrelist.sql.gz"
    "lib.libjoinedbooks.sql.gz"
    "lib.librate.sql.gz"
    "lib.librecs.sql.gz"
    "lib.libseq.sql.gz"
    "lib.libseqname.sql.gz"
    "lib.libtranslator.sql.gz"
)
# ---------------------

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_torrent_file>"
    exit 1
fi

LINUX_TORRENT_FILE="$1"

if [ ! -f "$LINUX_TORRENT_FILE" ]; then
    echo "Error: Torrent file not found at: $LINUX_TORRENT_FILE"
    exit 1
fi

echo "Step 1: Reading torrent map and extracting root folder..."
TORRENT_STRUCTURE=$("$ARIA2_BIN" -S "$LINUX_TORRENT_FILE")

# Dynamically extract TORRENT_ROOT from the 'Name:' property line
TORRENT_ROOT=$(echo "$TORRENT_STRUCTURE" | grep -E "^Name:" | awk '{print $2}' | tr -d '[:space:]\r')

if [ -z "$TORRENT_ROOT" ]; then
    echo "❌ Error: Could not determine the root folder name from the torrent file."
    exit 1
fi

echo "=========================================================="
echo " Launching WSL2 aria2c for Static Multi-File Extraction"
echo " Target Location: $OUT_DIR/$TORRENT_ROOT"
echo "=========================================================="

SELECTED_INDEXES=""
for pattern in "${WANTED_PATTERNS[@]}"; do
    MATCHES=$(echo "$TORRENT_STRUCTURE" | grep -F "/$pattern" | cut -d'|' -f1 | tr -d '[:space:]\r')
    for idx in $MATCHES; do
        if [[ "$idx" =~ ^[0-9]+$ ]]; then
            if [ -z "$SELECTED_INDEXES" ]; then
                SELECTED_INDEXES="$idx"
            else
                SELECTED_INDEXES="$SELECTED_INDEXES,$idx"
            fi
        fi
    done
done

if [ -z "$SELECTED_INDEXES" ]; then
    echo "❌ Error: No matching SQL files found inside this torrent."
    exit 1
fi

echo "Step 2: Commencing high-performance selective retrieval..."
ARIA_FLAGS=(
    --file-allocation=none
    --bt-max-peers=150
    --summary-interval=10
    --enable-dht=true
    --bt-enable-lpd=true
    --seed-time=0
    --max-overall-download-limit=0
    --bt-max-open-files=200
    --peer-id-prefix=-TR2940-
    --dir="$OUT_DIR"
    --select-file="$SELECTED_INDEXES"
    --allow-overwrite=true
)

GREP_FLAGS=(
    -v
    -E
    "booktracker|Tracker returned null data|Exception:.*DefaultBtAnnounce"
)

# Run the download pipeline
"$ARIA2_BIN" "${ARIA_FLAGS[@]}" "$LINUX_TORRENT_FILE" 2>&1 | grep "${GREP_FLAGS[@]}"

echo "----------------------------------------------------------"
echo "Step 3: Running Post-Download Cleanup..."
echo "----------------------------------------------------------"

TARGET_DIR="$OUT_DIR/$TORRENT_ROOT"

if [ -d "$TARGET_DIR" ]; then
    # Loop through files physically written to the dynamically resolved directory
    for full_path in "$TARGET_DIR"/*; do
        if [ -e "$full_path" ]; then
            filename=$(basename "$full_path")
            
            is_wanted=false
            for pattern in "${WANTED_PATTERNS[@]}"; do
                if [ "$filename" = "$pattern" ]; then
                    is_wanted=true
                    break
                fi
            done
            
            if [ "$is_wanted" = false ]; then
                echo "Removing unwanted boundary file: $filename"
                rm -f "$full_path"
            fi
        fi
    done
fi

## clean the Area2 trace file .$TARGET_DIR.aria2
TRACE_FILE="$TARGET_DIR.aria2"
if [ -s "$TRACE_FILE" ]; then
    rm -rf "$TRACE_FILE" && echo  "Aria2 trace file removed"
fi

echo "=========================================================="
echo " Selective Multi-File Extraction complete!"
echo " folder verified and cleaned successfully."
echo "=========================================================="
