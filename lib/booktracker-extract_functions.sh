#!/usr/bin/env bash
# =============================================================================
# booktracker-extract_functions.sh
#
# Shared library for booktracker-extract.
# Sourced by bin/booktracker-extract.sh and by the test suite.
#
# Public API
# ----------
#   naming       extract_type_from_name  extract_destination
#                extract_sql_destination  extract_torrent_name
#   selection    extract_is_allowed  extract_download_files
#                extract_select_indexes  extract_total_size
#   formatting   extract_human_size  extract_bytes_from_human
#   safeguard    extract_stale_dir
#   state        extract_is_done  extract_record
#
# Pure helpers (no network): all of the above except callers that invoke aria2c.
#
# Private helpers are not required beyond the public set above.
#
# Based on: Examples/*-torrent-extractor.sh, torrent-staging-spec.md
#
# Version:  0.1.1
# Updated:  2026-08-20 21:18 CDT
# Requires: bash >= 4
# Shell style: quote expansions; prefer local; return not exit; shellcheck-friendly.
# =============================================================================

[[ -n "${_BOOKTRACKER_EXTRACT_FUNCTIONS_LOADED:-}" ]] && return 0 2>/dev/null || true
_BOOKTRACKER_EXTRACT_FUNCTIONS_LOADED=1

# ---------------------------------------------------------------------------
# Fallbacks when config.sh has not been sourced
# ---------------------------------------------------------------------------
: "${STAGED_STATE_FILE:=${DATA_DIR:-.}/staged.tsv}"
: "${STAGING_DIR:=/Downloads/flibusta_snapshot}"
: "${INPX_SUBDIR:=inpx}"
: "${FLIBUSTA_SQL_SUBDIR:=FlibustaSQL}"
: "${MYSQL_FEEDS_SUBDIR:=mysql_feeds}"
: "${BOOK_ARCHIVES_SUBDIR:=book_archives}"
: "${TORRENT_NAME_PREFIX:=flibusta}"
: "${ARIA2C_SEED_TIME:=0}"
: "${ARIA2C_MAX_TRIES:=0}"
: "${ARIA2C_SUMMARY_INTERVAL:=30}"
: "${ARIA2C_EXTRA_TRACKERS:=}"
: "${ARIA2C_BT_MAX_PEERS:=150}"
: "${ARIA2C_BT_MAX_OPEN_FILES:=200}"
: "${ARIA2C_PEER_ID_PREFIX:=}"
: "${DUMP_ALLOWLIST:=lib.libavtor.sql.gz lib.libavtorname.sql.gz lib.libbook.sql.gz lib.libfilename.sql.gz lib.libgenre.sql.gz lib.libgenrelist.sql.gz lib.libjoinedbooks.sql.gz lib.librate.sql.gz lib.librecs.sql.gz lib.libseq.sql.gz lib.libseqname.sql.gz lib.libtranslator.sql.gz}"

# =============================================================================
# Naming
# =============================================================================

# extract_type_from_name <filename>
# Parse <type> from "<prefix>-<type>-<stamp>.torrent". Returns 1 if unknown.
extract_type_from_name() {
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

# extract_destination <type>
# Print STAGING_DIR subfolder for this type's download payload.
extract_destination() {
    case "$1" in
        inpx-fb2|inpx-all)       printf '%s\n' "$INPX_SUBDIR" ;;
        dump)                    printf '%s\n' "$FLIBUSTA_SQL_SUBDIR" ;;
        monthly-fb2|monthly-usr) printf '%s\n' "$BOOK_ARCHIVES_SUBDIR" ;;
        *) return 1 ;;
    esac
}

# extract_sql_destination
# Print subfolder for decompressed dump .sql (mysql_feeds).
extract_sql_destination() {
    printf '%s\n' "$MYSQL_FEEDS_SUBDIR"
}


# extract_inpx_fb2_output_name
# Canonical local name for the FB2-only INPX index:
#   flibusta_fb2_local-YYYY-MM-01_original.inpx
# YYYY/MM = current calendar year/month; day is always 01.
extract_inpx_fb2_output_name() {
    local ym
    ym="$(date '+%Y-%m')" || ym="$(date -u '+%Y-%m')"
    printf 'flibusta_fb2_local-%s-01_original.inpx\n' "$ym"
}

# extract_output_basename <type> <torrent_path>
# Final on-disk basename for a downloaded file.
# inpx-fb2 uses a fixed local naming scheme; all other types keep the torrent name.
extract_output_basename() {
    local type="$1" path="$2"
    case "$type" in
        inpx-fb2) extract_inpx_fb2_output_name ;;
        *)        printf '%s\n' "$(basename "$path")" ;;
    esac
}

# extract_torrent_name
# Read aria2c --show-files output on stdin; print top-level Name:.
extract_torrent_name() {
    local line name
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Name:[[:space:]]*(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            name="${name//$'\r'/}"
            name="${name%"${name##*[![:space:]]}"}"
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}

# =============================================================================
# Selection
# =============================================================================

# extract_is_allowed <type> <path>
# Return 0 when path is in the type's allowlist.
extract_is_allowed() {
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

# extract_download_files <type>
# stdin: aria2c show-files lines → stdout: idx|path for the download set.
extract_download_files() {
    local type="$1" line idx path selective=0
    case "$type" in
        dump|inpx-fb2|inpx-all) selective=1 ;;
    esac
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*([0-9]+)\|(.+)$ ]] || continue
        idx="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        (( selective )) && ! extract_is_allowed "$type" "$path" && continue
        printf '%s|%s\n' "$idx" "$path"
    done
}

# extract_select_indexes <type>
# stdin: show-files → stdout: comma-separated indexes for --select-file.
extract_select_indexes() {
    local type="$1" idx
    local -a sel=()
    case "$type" in
        dump|inpx-fb2|inpx-all) : ;;
        *)                      return 0 ;;
    esac
    while IFS='|' read -r idx _; do
        sel+=("$idx")
    done < <(extract_download_files "$type")
    local IFS=,
    printf '%s\n' "${sel[*]}"
}

# extract_bytes_from_human <size>
# Convert aria2c length tokens (e.g. 99.9MiB) to whole bytes.
extract_bytes_from_human() {
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

# extract_total_size <type>
# stdin: show-files → stdout: total bytes of the download set.
extract_total_size() {
    local type="$1" line prev_path="" total=0 n
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([0-9]+)\|(.+)$ ]]; then
            prev_path="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ ^[[:space:]]*\| ]]; then
            if [[ -n "$prev_path" ]] && extract_is_allowed "$type" "$prev_path"; then
                if [[ "$line" =~ \(([0-9][0-9,]*)\) ]]; then
                    n="${BASH_REMATCH[1]//,/}"
                else
                    n="$(extract_bytes_from_human "${line#*|}")"
                fi
                total=$((total + n))
            fi
            prev_path=""
        fi
    done
    printf '%s\n' "$total"
}

# =============================================================================
# Formatting & safeguard
# =============================================================================

# extract_human_size <bytes>
extract_human_size() {
    awk -v n="${1:-0}" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " ");
        i = 1;
        while (n >= 1024 && i < 5) { n /= 1024; i++ }
        printf "%.1f%s", n, u[i]
    }'
}

# extract_stale_dir <dest_dir> <torrent_name>
# Print path of a nested leftover dir under dest_dir, if any.
extract_stale_dir() {
    local dest_dir="$1" name="$2" stale
    [[ -n "$name" && "$name" != "." && "$name" != ".." && "$name" != */* ]] || return 1
    stale="$dest_dir/$name"
    [[ -d "$stale" ]] || return 1
    printf '%s\n' "$stale"
}

# =============================================================================
# State
# =============================================================================

# extract_is_done <torrent> [state_file]
extract_is_done() {
    local torrent="$1" state="${2:-${STAGED_STATE_FILE:-}}"
    [[ -n "$state" && -f "$state" ]] || return 1
    awk -F '\t' -v t="$torrent" '$3 == t { found = 1 } END { exit (found ? 0 : 1) }' "$state"
}

# extract_record <type> <torrent> <stamp> <destination> <files>
extract_record() {
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
