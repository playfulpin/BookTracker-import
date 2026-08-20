#!/usr/bin/env bash
# =============================================================================
# booktracker-stage — shared functions (staging feature)
#
# Pure, network-free building blocks for turning the `.torrent` files downloaded
# by booktracker-import.sh into staged payload files under STAGING_DIR.
# Sourced by the staging CLI (bin/booktracker-stage.sh) and by the test suite.
#
#   naming        stage_type_from_name, stage_destination, stage_sql_destination,
#                 stage_torrent_name
#   selection     stage_is_allowed, stage_download_files, stage_select_indexes,
#                 stage_total_size
#   formatting    stage_human_size, stage_bytes_from_human
#   safeguard     stage_stale_dir
#   state         stage_is_done, stage_record
#
# Requires: bash >= 4
# =============================================================================

# Allow being sourced multiple times without redefining everything.
[[ -n "${_BOOKTRACKER_STAGE_FUNCTIONS_LOADED:-}" ]] && return 0 2>/dev/null || true
_BOOKTRACKER_STAGE_FUNCTIONS_LOADED=1

# Sensible fallbacks so the library is usable even if config.sh was not sourced.
: "${STAGED_STATE_FILE:=${DATA_DIR:-.}/staged.tsv}"
: "${STAGING_DIR:=/Downloads/flibusta_snapshot}"
: "${INPX_SUBDIR:=inpx}"
: "${FLIBUSTA_SQL_SUBDIR:=FlibustaSQL}"
: "${MYSQL_FEEDS_SUBDIR:=mysql_feeds}"
: "${BOOK_ARCHIVES_SUBDIR:=book_archives}"
: "${ARIA2C_SEED_TIME:=0}"
: "${ARIA2C_MAX_TRIES:=0}"
: "${ARIA2C_SUMMARY_INTERVAL:=30}"
: "${ARIA2C_EXTRA_TRACKERS:=}"
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
# Print the STAGING_DIR subfolder that a torrent type's payload is downloaded
# into.  Returns 0 on success, 1 for an unknown type.
stage_destination() {
    case "$1" in
        inpx-fb2|inpx-all)       printf '%s\n' "$INPX_SUBDIR" ;;
        dump)                    printf '%s\n' "$FLIBUSTA_SQL_SUBDIR" ;;
        monthly-fb2|monthly-usr) printf '%s\n' "$BOOK_ARCHIVES_SUBDIR" ;;
        *) return 1 ;;
    esac
}

# stage_sql_destination
# Print the STAGING_DIR subfolder where a dump's decompressed `.sql` files go
# (mysql_feeds), sibling to the FlibustaSQL download folder.
stage_sql_destination() {
    printf '%s\n' "$MYSQL_FEEDS_SUBDIR"
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

# stage_download_files <type>
# Read aria2c "--show-files" style "idx|path" lines on stdin and print, one per
# line, the "idx|path" pairs for every file in the download set.  Selective
# types filter via stage_is_allowed; full-download types print every file.
stage_download_files() {
    local type="$1" line idx path selective=0
    case "$type" in
        dump|inpx-fb2|inpx-all) selective=1 ;;
    esac
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*([0-9]+)\|(.+)$ ]] || continue
        idx="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        (( selective )) && ! stage_is_allowed "$type" "$path" && continue
        printf '%s|%s\n' "$idx" "$path"
    done
}

# stage_select_indexes <type>
# Read aria2c "--show-files" style "idx|path" lines on stdin and print the
# comma-separated 1-based indexes to download (for --select-file).  Selective
# types filter via stage_is_allowed; full-download types print nothing (no
# per-file selection).
stage_select_indexes() {
    local type="$1" idx
    local -a sel=()
    case "$type" in
        dump|inpx-fb2|inpx-all) : ;;
        *)                      return 0 ;;   # full download → no per-file selection
    esac
    while IFS='|' read -r idx _; do
        sel+=("$idx")
    done < <(stage_download_files "$type")
    local IFS=,
    printf '%s\n' "${sel[*]}"
}

# stage_bytes_from_human <size>
# Convert an aria2c "--show-files" length (e.g. "99.9MiB", "512B") to a whole
# byte count.  Unknown input yields 0.
stage_bytes_from_human() {
    local s="${1:-}" num unit
    s="${s//[[:space:]]/}"
    if [[ "$s" =~ ^([0-9]+(\.[0-9]+)?)([KMGT]iB|B)$ ]]; then
        num="${BASH_REMATCH[1]}"
        unit="${BASH_REMATCH[3]}"
        case "$unit" in
            B)   awk -v n="$num" 'BEGIN { printf "%.0f", n }' ;;
            KiB) awk -v n="$num" 'BEGIN { printf "%.0f", n * 1024 }' ;;
            MiB) awk -v n="$num" 'BEGIN { printf "%.0f", n * 1048576 }' ;;
            GiB) awk -v n="$num" 'BEGIN { printf "%.0f", n * 1073741824 }' ;;
            TiB) awk -v n="$num" 'BEGIN { printf "%.0f", n * 1099511627776 }' ;;
            *)   printf '0' ;;
        esac
    else
        printf '0'
    fi
}

# stage_total_size <type>
# Read aria2c "--show-files" output on stdin and print the total byte size of
# the download set (the "length" column summed over allowed files).  For a
# torrent, aria2c prints each file as an "idx|path" line followed by a size
# line carrying the exact byte count in parentheses, e.g.
# "   |91MiB (96,397,659)".  That parenthesized count is used (comma-stripped);
# if it is absent (some non-torrent listings), the human-readable size is
# converted as a fallback.
stage_total_size() {
    local type="$1" line prev_path="" total=0 n
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)\|(.+)$ ]]; then
            prev_path="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*\| ]]; then
            if [[ -n "$prev_path" ]] && stage_is_allowed "$type" "$prev_path"; then
                if [[ "$line" =~ \(([0-9][0-9,]*)\) ]]; then
                    n="${BASH_REMATCH[1]//,/}"
                else
                    n="$(stage_bytes_from_human "${line#*|}")"
                fi
                total=$((total + n))
            fi
            prev_path=""
        fi
    done
    printf '%s\n' "$total"
}

# stage_torrent_name
# Read aria2c "--show-files" output on stdin and print the torrent's top-level
# "Name:" (the folder aria2c would nest files under without --index-out).
# Empty output when the line is absent.
stage_torrent_name() {
    local line name
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Name:[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            name="${name//$'\r'/}"                      # tolerate CRLF input
            name="${name%"${name##*[![:space:]]}"}"     # trim trailing whitespace
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}

# stage_stale_dir <dest_dir> <torrent_name>
# Print the path of a stale directory left under <dest_dir> by an older run
# that nested downloaded files under the torrent's name (before --index-out
# pinned them flat).  Prints nothing and returns 1 when there is none.  Names
# containing path separators or "."/".." are rejected so nothing outside the
# destination can ever be touched.
stage_stale_dir() {
    local dest_dir="$1" name="$2" stale
    [[ -n "$name" && "$name" != "." && "$name" != ".." && "$name" != */* ]] || return 1
    stale="$dest_dir/$name"
    [[ -d "$stale" ]] || return 1
    printf '%s\n' "$stale"
}

# stage_human_size <bytes>
# Print a human-readable size (e.g. "7.0GiB") for a byte count.
stage_human_size() {
    awk -v n="${1:-0}" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (n >= 1024 && i < 5) { n /= 1024; i++ }
        printf "%.1f%s", n, u[i]
    }'
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
