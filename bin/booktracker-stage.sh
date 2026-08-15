#!/usr/bin/env bash
# =============================================================================
# booktracker-stage — main executable
#
# Downloads the contents of the .torrent files produced by
# bin/booktracker-import.sh directly into a local STAGING_DIR using aria2c,
# fetching only the allowed files for selective torrent types (dump, inpx-*).
# Dump .gz files are decompressed into a sibling "flibusta" folder.  Pure logic
# lives in lib/booktracker-stage_functions.sh; this script orchestrates
# discovery, download, in-place decompression, and state tracking.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Load configuration -----------------------------------------------------
# shellcheck source=../config/config.sh
source "$PROJECT_ROOT/config/config.sh"

# Load optional gitignored .env (credentials / overrides), if present.
# BOOKTRACKER_NO_ENV=1 skips it so explicitly-set environment variables win.
if [[ -f "$PROJECT_ROOT/.env" && "${BOOKTRACKER_NO_ENV:-0}" != 1 ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
    set +a
fi

# --- Load functions ---------------------------------------------------------
# shellcheck source=../lib/booktracker-import_functions.sh
source "$PROJECT_ROOT/lib/booktracker-import_functions.sh"
# shellcheck source=../lib/booktracker-stage_functions.sh
source "$PROJECT_ROOT/lib/booktracker-stage_functions.sh"

usage() {
    cat <<'EOF'
Usage: booktracker-stage.sh [options] [torrent-file...]

Stage the contents of booktracker-import.sh's .torrent files into STAGING_DIR
using aria2c.  With no arguments, every un-staged .torrent in TORRENT_DIR is
processed.

Options:
  -f, --force       Re-stage even if already recorded in data/staged.tsv
  -n, --dry-run     Print what would happen without downloading
      --resume-only  Skip torrents whose files are already fully downloaded
  -d, --debug       Enable debug logging
  -h, --help        Show this help

Environment:
  STAGING_DIR     (required) absolute path to the staging root
EOF
}

# stage_one <torrent_file>
# Download one torrent's allowed files directly into the right STAGING_DIR
# subfolder (no intermediate working directory), decompress dump .gz files into
# the sibling "flibusta" folder, and record the result.  Returns 0 on success,
# 1 on failure.
stage_one() {
    local torrent_file="$1" name type dest dest_dir sql_dir select files_list
    local entry idx path base dst record_dest files_csv="" n=0 total_size=0
    local -a download_files=()

    name="$(basename "$torrent_file")"
    type="$(stage_type_from_name "$name")" || {
        log_warn "unrecognized torrent name, skipping: $name"
        return 1
    }

    if (( ! FORCE )) && stage_is_done "$name"; then
        log_info "already staged: $name (use --force to re-stage)"
        return 0
    fi

    dest="$(stage_destination "$type")" || { log_error "no destination for type '$type'"; return 1; }
    dest_dir="$STAGING_DIR/$dest"
    # dump downloads its .gz into flibusta_gz and decompresses into the sibling
    # "flibusta" folder.
    sql_dir=""
    [[ "$type" == dump ]] && sql_dir="$STAGING_DIR/$(stage_sql_destination)"

    stamp="${name#"${TORRENT_NAME_PREFIX}-${type}-"}"
    stamp="${stamp%.torrent}"

    # List the torrent's files and compute the download set + total size.
    files_list="$(aria2c --show-files "$torrent_file" 2>/dev/null)" || {
        log_error "aria2c --show-files failed: $name"
        return 1
    }
    # aria2c may emit CRLF on Windows; normalize so parsing is portable.
    files_list="${files_list//$'\r'/}"
    while IFS='|' read -r idx path; do
        download_files+=("$idx|$path")
    done < <(stage_download_files "$type" <<< "$files_list")

    if (( ${#download_files[@]} == 0 )); then
        log_warn "no files to download in $name; skipping"
        return 1
    fi

    total_size="$(stage_total_size "$type" <<< "$files_list")"

    # Expected output names (dump: decompressed .sql).
    for entry in "${download_files[@]}"; do
        path="${entry#*|}"
        base="$(basename "$path")"
        [[ "$type" == dump ]] && base="${base%.gz}"
        files_csv="${files_csv:+$files_csv,}$base"
        n=$((n + 1))
    done

    # The record's destination: dump's .sql land in "flibusta", everything else
    # lands in its download directory.
    record_dest="$dest"
    [[ "$type" == dump ]] && record_dest="$(stage_sql_destination)"

    # --resume-only: skip torrents whose download already completed (every file
    # present and no leftover .aria2 control file).
    if (( RESUME_ONLY )); then
        local ctrl has_control=0 all_present=1
        for ctrl in "$dest_dir"/*.aria2; do
            [[ -e "$ctrl" ]] && { has_control=1; break; }
        done
        for entry in "${download_files[@]}"; do
            path="${entry#*|}"
            [[ -s "$dest_dir/$(basename "$path")" ]] || { all_present=0; break; }
        done
        if (( all_present )) && (( ! has_control )); then
            log_info "already present: $name (--resume-only, skipping)"
            return 0
        fi
    fi

    # Build the aria2c command.  Files download directly into the destination
    # directory, so there is no copy/move step afterwards.  Large releases can
    # be tens of GB and take hours, so aria2c retries indefinitely and prints a
    # progress summary every ARIA2C_SUMMARY_INTERVAL seconds.  DHT, peer
    # exchange, and local peer discovery are enabled so a public torrent can
    # still find peers if its original tracker is down; extra fallback trackers
    # (ARIA2C_EXTRA_TRACKERS) are announced too.
    local -a aria_args=(
        --seed-time="${ARIA2C_SEED_TIME}"
        --max-tries="${ARIA2C_MAX_TRIES}"
        --summary-interval="${ARIA2C_SUMMARY_INTERVAL}"
        --check-integrity=true
        --enable-dht=true
        --enable-peer-exchange=true
        --bt-enable-lpd=true
        --dir="$dest_dir"
    )
    if [[ -n "${ARIA2C_EXTRA_TRACKERS:-}" ]]; then
        aria_args+=(--bt-tracker="$ARIA2C_EXTRA_TRACKERS")
    fi
    case "$type" in
        dump|inpx-fb2|inpx-all)
            select="$(stage_select_indexes "$type" <<< "$files_list")"
            # Pin each selected file to its basename (flat under dest_dir) and
            # avoid preallocating the large adjacent unselected files that
            # share a piece boundary (e.g. the dump's multi-GB .zip archives).
            aria_args+=(--select-file="$select" --bt-remove-unselected-file=true --file-allocation=none)
            for entry in "${download_files[@]}"; do
                idx="${entry%%|*}"
                path="${entry#*|}"
                aria_args+=(--index-out="$idx=$(basename "$path")")
            done
            ;;
    esac

    if (( DRY_RUN )); then
        log_info "[dry-run] would run: aria2c ${aria_args[*]} $torrent_file"
        log_info "[dry-run] would download $n file(s), $(stage_human_size "$total_size") total"
        log_info "[dry-run] would record: $type $name stamp=$stamp dest=$record_dest files=$files_csv"
        return 0
    fi

    mkdir -p "$dest_dir" || { log_error "cannot create staging dir: $dest_dir"; return 1; }
    log_info "downloading $name ($n file(s), $(stage_human_size "$total_size")) into $dest_dir (may take a long time)"
    if ! aria2c "${aria_args[@]}" "$torrent_file"; then
        log_error "aria2c download failed: $name"
        return 1
    fi

    # Decompress dump .gz files into the sibling "flibusta" folder, keeping the
    # raw .gz in flibusta_gz.
    if [[ "$type" == dump ]]; then
        mkdir -p "$sql_dir" || { log_error "cannot create decompress dir: $sql_dir"; return 1; }
        for entry in "${download_files[@]}"; do
            path="${entry#*|}"
            base="$(basename "$path")"
            src="$dest_dir/$base"
            dst="$sql_dir/${base%.gz}"
            if gzip -dc "$src" > "$dst"; then
                log_info "decompressed: $dst"
            else
                log_error "failed to decompress $src"
                return 1
            fi
        done
    fi

    stage_record "$type" "$name" "$stamp" "$record_dest" "$files_csv"
    log_info "staged $name: $files_csv -> $STAGING_DIR/$record_dest"
    return 0
}

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
                log_error "unknown option: $arg"
                usage >&2
                return 2
                ;;
            *)
                torrents+=("$arg")
                ;;
        esac
        shift
    done

    # Validate the environment.
    if [[ -z "${STAGING_DIR:-}" ]]; then
        log_error "STAGING_DIR is not set (required; absolute path to the staging root)"
        return 2
    fi
    if [[ "${STAGING_DIR:0:1}" != "/" ]]; then
        log_error "STAGING_DIR must be an absolute path: $STAGING_DIR"
        return 2
    fi
    if ! command -v aria2c >/dev/null 2>&1; then
        log_error "aria2c not found; install it (e.g. 'sudo apt install aria2')"
        return 1
    fi

    # Default to every .torrent in TORRENT_DIR.
    if (( ${#torrents[@]} == 0 )); then
        for f in "$TORRENT_DIR"/*.torrent; do
            [[ -e "$f" ]] || continue
            torrents+=("$f")
        done
    fi

    if (( ${#torrents[@]} == 0 )); then
        log_info "no .torrent files to stage in $TORRENT_DIR"
        return 0
    fi

    for t in "${torrents[@]}"; do
        [[ -f "$t" ]] || t="$TORRENT_DIR/$t"
        if [[ ! -f "$t" ]]; then
            log_warn "torrent not found: $t"
            fail=$((fail + 1))
            continue
        fi
        if stage_one "$t"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done

    log_info "finished staging: $ok ok, $fail failed"
    return $(( fail > 0 ))
}

main "$@"
exit $?
