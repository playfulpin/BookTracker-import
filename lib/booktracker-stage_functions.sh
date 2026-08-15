#!/usr/bin/env bash
# =============================================================================
# booktracker-stage — shared functions (staging feature)
#
# Pure, network-free building blocks for turning the `.torrent` files downloaded
# by booktracker-import.sh into staged payload files under STAGING_DIR.
# Sourced by the staging CLI (bin/booktracker-stage.sh) and by the test suite.
#
#   naming        stage_type_from_name, stage_destination
#   selection     stage_is_allowed, stage_select_indexes
#   state         stage_is_done, stage_record
#   placement     stage_place
#
# Requires: bash >= 4
# =============================================================================

# Allow being sourced multiple times without redefining everything.
[[ -n "${_BOOKTRACKER_STAGE_FUNCTIONS_LOADED:-}" ]] && return 0 2>/dev/null || true
_BOOKTRACKER_STAGE_FUNCTIONS_LOADED=1

# Sensible fallbacks so the library is usable even if config.sh was not sourced.
: "${STAGED_STATE_FILE:=${DATA_DIR:-.}/staged.tsv}"
: "${STAGING_DIR:=}"
: "${ARIA2C_SEED_TIME:=0}"
: "${DUMP_ALLOWLIST:=lib.libavtor.sql.gz lib.libavtorname.sql.gz lib.libbook.sql.gz lib.libfilename.sql.gz lib.libgenre.sql.gz lib.libgenrelist.sql.gz lib.libjoinedbooks.sql.gz lib.librate.sql.gz lib.librecs.sql.gz lib.libseq.sql.gz lib.libseqname.sql.gz lib.libtranslator.sql.gz}"

# stage_type_from_name <filename>
# Parse the torrent <type> out of a "<prefix>-<type>-<stamp>.torrent" filename.
# Prints the type; returns 0 on success, 1 when the name is not recognized.
stage_type_from_name() {
    local name="$1" t
    name="$(basename "${name%.torrent}")"
    for t in inpx-fb2 inpx-all dump monthly-fb2 monthly-usr; do
        if [[ "$name" == "${TORRENT_NAME_PREFIX:-flibusta}-$t-"* ]]; then
            printf '%s\n' "$t"
            return 0
        fi
    done
    return 1
}

# stage_destination <type>
# Print the STAGING_DIR subfolder that a torrent type's payload goes into.
# Returns 0 on success, 1 for an unknown type.
stage_destination() {
    case "$1" in
        inpx-fb2|inpx-all)       printf 'inpx\n' ;;
        dump)                    printf 'flibusta_gz\n' ;;
        monthly-fb2|monthly-usr) printf 'Latest\n' ;;
        *) return 1 ;;
    esac
}

# stage_is_allowed <type> <path>
# Return 0 when <path> belongs to the type's allowlist:
#   dump            — explicit DUMP_ALLOWLIST filenames (core library tables)
#   inpx-fb2/inpx-all — *.inpx
#   others          — everything (full download)
stage_is_allowed() {
    local type="$1" path="$2" base f
    case "$type" in
        dump)
            base="${path##*/}"
            for f in ${DUMP_ALLOWLIST:-}; do
                [[ "$base" == "$f" ]] && return 0
            done
            return 1
            ;;
        inpx-fb2|inpx-all) [[ "$path" == *.inpx ]] ;;
        *)                 return 0 ;;
    esac
}

# stage_select_indexes <type>
# Read aria2c "--show-files" style "idx|path" lines on stdin and print the
# comma-separated 1-based indexes to download.  Selective types filter via
# stage_is_allowed; full-download types print nothing (no per-file selection).
stage_select_indexes() {
    local type="$1" line idx path
    local -a sel=()
    case "$type" in
        dump|inpx-fb2|inpx-all) : ;;
        *)                      return 0 ;;   # full download → no per-file selection
    esac
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*([0-9]+)\|(.+)$ ]] || continue
        idx="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        stage_is_allowed "$type" "$path" || continue
        sel+=("$idx")
    done
    local IFS=,
    printf '%s\n' "${sel[*]}"
}

# stage_is_done <torrent> [state_file]
# Return 0 when the torrent is already recorded in the staging state file.
stage_is_done() {
    local torrent="$1" state="${2:-${STAGED_STATE_FILE:-}}"
    [[ -n "$state" && -f "$state" ]] || return 1
    awk -F '\t' -v t="$torrent" '$3 == t { found = 1 } END { exit (found ? 0 : 1) }' "$state"
}

# stage_record <type> <torrent> <stamp> <destination> <files>
# Append one row to the staging state file (TSV):
#   staged_at, type, torrent, stamp, destination, files
stage_record() {
    local type="$1" torrent="$2" stamp="$3" dest="$4" files="$5" ts state
    state="${STAGED_STATE_FILE:-}"
    [[ -n "$state" ]] || return 1
    mkdir -p "$(dirname "$state")" 2>/dev/null || true
    if [[ ! -f "$state" ]]; then
        printf 'staged_at\ttype\ttorrent\tstamp\tdestination\tfiles\n' > "$state"
    fi
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$type" "$torrent" "$stamp" "$dest" "$files" >> "$state"
}

# stage_place <type> <src> <dest_dir>
# Copy <src> into <dest_dir> honoring the collision rules: `inpx` types
# overwrite an identical filename; every other type never clobbers (keeps
# existing names).
stage_place() {
    local type="$1" src="$2" dir="$3" dst
    [[ -f "$src" ]] || return 1
    mkdir -p "$dir" 2>/dev/null || return 1
    dst="$dir/$(basename "$src")"
    case "$type" in
        inpx-fb2|inpx-all) cp -f "$src" "$dst" ;;
        *)                 cp -n "$src" "$dst" ;;
    esac
}
