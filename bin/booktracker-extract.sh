#!/usr/bin/env bash
# =============================================================================
# booktracker-extract.sh
#
# Download torrent *payloads* produced by booktracker-import.sh into a local
# STAGING_DIR using aria2c. Selective types (dump, inpx-*) fetch only allowed
# files. Dump .gz files are decompressed into a sibling mysql_feeds/ folder.
#
# Pure helpers live in lib/booktracker-extract_functions.sh.
# Logging is reused from lib/booktracker-import_functions.sh.
#
# Based on: Examples/single-torrent-extractor.sh,
#           Examples/multifile-torrent-extractor.sh,
#           torrent-staging-spec.md
#
# CLI command style matches booktracker-import.sh.
#
# Exit codes:
#   0  success
#   1  operational failure
#   2  usage error
#
# Version:  0.1.3
# Updated:  2026-08-21 17:18 CDT
# Requires: bash >= 4, aria2c, gzip, GNU coreutils
#
# Examples:
#   ./bin/booktracker-extract.sh
#   ./bin/booktracker-extract.sh --dry-run
#   ./bin/booktracker-extract.sh flibusta-dump-2026-08-01.torrent
#   ./bin/booktracker-extract.sh --force --debug
# =============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# shellcheck source=../config/config.sh
source "$PROJECT_ROOT/config/config.sh"

if [[ -f "$PROJECT_ROOT/.env" && "${BOOKTRACKER_NO_ENV:-0}" != 1 ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
    set +a
fi

# ---------------------------------------------------------------------------
# Libraries (logging from import; extract helpers)
# ---------------------------------------------------------------------------
# shellcheck source=../lib/booktracker-import_functions.sh
source "$PROJECT_ROOT/lib/booktracker-import_functions.sh"
# shellcheck source=../lib/booktracker-extract_functions.sh
source "$PROJECT_ROOT/lib/booktracker-extract_functions.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<'USAGE_EOF'
Usage: booktracker-extract.sh [options] [torrent-file...]

Extract (download) contents of booktracker-import .torrent files into
STAGING_DIR using aria2c. With no arguments, every un-extracted .torrent in
TORRENT_DIR is processed.

Options:
  -f, --force        Re-extract even if already recorded in staged.tsv
  -n, --dry-run      Print what would happen without downloading
      --resume-only  Skip torrents whose files are already fully downloaded
  -d, --debug        Enable debug logging
  -h, --help         Show this help

Exit codes:
  0  success
  1  operational failure
  2  usage error

Environment:
  STAGING_DIR     download root (default: /Downloads/flibusta_snapshot)
  TORRENT_DIR     where .torrent files live (default: $STAGING_DIR/torrents)
USAGE_EOF
}

# usage_error [message]
usage_error() {
    [[ -n "${1:-}" ]] && log_error "$1"
    usage >&2
    return 2
}

# ---------------------------------------------------------------------------
# extract_one <torrent_file>
# Download one torrent's allowed files into the right STAGING_DIR subfolder.
# ---------------------------------------------------------------------------
extract_one() {
    local torrent_file="$1" name type dest dest_dir sql_dir select files_list
    local torrent_name stale_dir record_dest files_csv="" n=0 total_size=0
    local idx path base dst
    local i ctrl has_control all_present
    local -a aria_args=()
    local -a dl_idxs=() dl_names=()

    name="$(basename "$torrent_file")"
    type="$(extract_type_from_name "$name")" || {
        log_warn "unrecognized torrent name, skipping: $name"
        return 1
    }

    if (( ! FORCE )) && extract_is_done "$name"; then
        log_info "already extracted: $name (use --force to re-extract)"
        return 0
    fi

    dest="$(extract_destination "$type")" || {
        log_error "no destination for type '$type'"
        return 1
    }
    dest_dir="$STAGING_DIR/$dest"
    sql_dir=""
    [[ "$type" == dump ]] && sql_dir="$STAGING_DIR/$(extract_sql_destination)"

    local stamp
    stamp="${name#"${TORRENT_NAME_PREFIX}-${type}-"}"
    stamp="${stamp%.torrent}"

    files_list="$(aria2c --show-files "$torrent_file" 2>/dev/null)" || {
        log_error "aria2c --show-files failed: $name"
        return 1
    }
    files_list="${files_list//$'\r'/}"

    torrent_name="$(extract_torrent_name <<< "$files_list")"

    # Parse the download set once into parallel arrays: aria2c's 1-based file
    # index and the on-disk name each file is pinned to (inpx-fb2 uses a
    # canonical local name; every other type keeps its torrent basename).
    while IFS='|' read -r idx path; do
        dl_idxs+=("$idx")
        dl_names+=("$(extract_output_basename "$type" "$path")")
    done < <(extract_download_files "$type" <<< "$files_list")

    n="${#dl_names[@]}"
    if (( n == 0 )); then
        log_warn "no files to download in $name; skipping"
        return 1
    fi

    total_size="$(extract_total_size "$type" <<< "$files_list")"

    # Recorded names: a dump's .gz is recorded as its decompressed .sql (the
    # record points at the mysql_feeds output), so strip the .gz suffix there.
    for base in "${dl_names[@]}"; do
        [[ "$type" == dump ]] && base="${base%.gz}"
        files_csv="${files_csv:+$files_csv,}$base"
    done

    record_dest="$dest"
    [[ "$type" == dump ]] && record_dest="$(extract_sql_destination)"

    if (( RESUME_ONLY )); then
        has_control=0
        all_present=1
        for ctrl in "$dest_dir"/*.aria2; do
            [[ -e "$ctrl" ]] && { has_control=1; break; }
        done
        for base in "${dl_names[@]}"; do
            [[ -s "$dest_dir/$base" ]] || { all_present=0; break; }
        done
        if (( all_present )) && (( ! has_control )); then
            log_info "already present: $name (--resume-only, skipping)"
            return 0
        fi
    fi

    # aria2c flags (Examples + staging-spec style)
    aria_args=(
        --seed-time="${ARIA2C_SEED_TIME}"
        --max-tries="${ARIA2C_MAX_TRIES}"
        --summary-interval="${ARIA2C_SUMMARY_INTERVAL}"
        --check-integrity=true
        --enable-dht=true
        --enable-peer-exchange=true
        --bt-enable-lpd=true
        --bt-max-peers="${ARIA2C_BT_MAX_PEERS:-150}"
        --bt-max-open-files="${ARIA2C_BT_MAX_OPEN_FILES:-200}"
        --file-allocation=none
        --allow-overwrite=true
        --dir="$dest_dir"
    )
    if [[ -n "${ARIA2C_EXTRA_TRACKERS:-}" ]]; then
        aria_args+=(--bt-tracker="$ARIA2C_EXTRA_TRACKERS")
    fi
    if [[ -n "${ARIA2C_PEER_ID_PREFIX:-}" ]]; then
        aria_args+=(--peer-id-prefix="$ARIA2C_PEER_ID_PREFIX")
    fi

    case "$type" in
        dump|inpx-fb2|inpx-all)
            select="$(IFS=,; printf '%s' "${dl_idxs[*]}")"
            aria_args+=(--select-file="$select" --bt-remove-unselected-file=true)
            for (( i = 0; i < n; i++ )); do
                aria_args+=(--index-out="${dl_idxs[$i]}=${dl_names[$i]}")
            done
            ;;
    esac

    stale_dir="$(extract_stale_dir "$dest_dir" "$torrent_name")"
    if [[ -n "$stale_dir" ]]; then
        if (( DRY_RUN )); then
            log_warn "[dry-run] would remove stale torrent-named dir: $stale_dir"
        else
            log_warn "removing stale torrent-named dir from a previous run: $stale_dir"
            rm -rf -- "$stale_dir" || {
                log_error "failed to remove stale dir: $stale_dir"
                return 1
            }
        fi
    fi

    if (( DRY_RUN )); then
        log_info "[dry-run] would run: aria2c ${aria_args[*]} $torrent_file"
        log_info "[dry-run] would download $n file(s), $(extract_human_size "$total_size") total"
        log_info "[dry-run] would record: $type $name stamp=$stamp dest=$record_dest files=$files_csv"
        return 0
    fi

    mkdir -p "$dest_dir" || {
        log_error "cannot create extract dir: $dest_dir"
        return 1
    }
    log_info "extracting $name ($n file(s), $(extract_human_size "$total_size")) into $dest_dir"

    # Run aria2c directly so exit status is reliable (Examples filter is optional noise reduction).
    if ! aria2c "${aria_args[@]}" "$torrent_file"; then
        log_error "aria2c download failed: $name"
        return 1
    fi

    if [[ "$type" == dump ]]; then
        mkdir -p "$sql_dir" || {
            log_error "cannot create decompress dir: $sql_dir"
            return 1
        }
        for (( i = 0; i < n; i++ )); do
            src="$dest_dir/${dl_names[$i]}"
            dst="$sql_dir/${dl_names[$i]%.gz}"
            if gzip -dc "$src" > "$dst"; then
                log_info "decompressed: $dst"
            else
                log_error "failed to decompress $src"
                return 1
            fi
        done
    fi

    # Optional: remove leftover .aria2 control file next to dest (Examples cleanup)
    local trace
    for trace in "$dest_dir"/*.aria2; do
        [[ -e "$trace" ]] || continue
        rm -f -- "$trace" && debug "removed aria2 control file: $trace"
    done

    extract_record "$type" "$name" "$stamp" "$record_dest" "$files_csv"
    log_info "extracted $name: $files_csv -> $STAGING_DIR/$record_dest"
    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local arg f t ok=0 fail=0
    local -a torrents=()
    DRY_RUN="${DRY_RUN:-0}"
    FORCE="${FORCE:-0}"
    RESUME_ONLY="${RESUME_ONLY:-0}"

    while (( $# )); do
        arg="$1"
        case "$arg" in
            -h|--help)
                usage
                return 0
                ;;
            -d|--debug)
                LOG_LEVEL=debug
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            -f|--force)
                FORCE=1
                ;;
            --resume-only)
                RESUME_ONLY=1
                ;;
            -*)
                usage_error "unknown option: $arg"
                return $?
                ;;
            *)
                torrents+=("$arg")
                ;;
        esac
        shift
    done

    if [[ -z "${STAGING_DIR:-}" ]]; then
        usage_error "STAGING_DIR is empty (set it to the download root, e.g. /Downloads/flibusta_snapshot)"
        return $?
    fi
    if [[ "${STAGING_DIR:0:1}" != "/" ]]; then
        usage_error "STAGING_DIR must be an absolute path: $STAGING_DIR"
        return $?
    fi
    if ! command -v aria2c >/dev/null 2>&1; then
        log_error "aria2c not found; install it (e.g. 'sudo apt install aria2')"
        return 1
    fi

    if (( ${#torrents[@]} == 0 )); then
        for f in "$TORRENT_DIR"/*.torrent; do
            [[ -e "$f" ]] || continue
            torrents+=("$f")
        done
    fi

    if (( ${#torrents[@]} == 0 )); then
        log_info "no .torrent files to extract in $TORRENT_DIR"
        return 0
    fi

    log_info "extracting ${#torrents[@]} torrent(s) into $STAGING_DIR"
    for t in "${torrents[@]}"; do
        [[ -f "$t" ]] || t="$TORRENT_DIR/$t"
        if [[ ! -f "$t" ]]; then
            log_warn "torrent not found: $t"
            fail=$((fail + 1))
            continue
        fi
        if extract_one "$t"; then
            ok=$((ok + 1))
            log_info "target ok: $(basename "$t")"
        else
            fail=$((fail + 1))
            log_warn "target failed: $(basename "$t")"
        fi
    done

    if (( fail > 0 )); then
        log_warn "finished extracting: $ok ok, $fail failed"
    else
        log_info "finished extracting: $ok ok, $fail failed"
    fi
    return $(( fail > 0 ))
}

main "$@"
exit $?
