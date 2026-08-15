#!/usr/bin/env bash
# =============================================================================
# booktracker-stage — main executable
#
# Downloads the contents of the .torrent files produced by
# bin/booktracker-import.sh into a local STAGING_DIR using aria2c, extracting
# only the allowed files for selective torrent types (dump, inpx-*).  Pure
# logic lives in lib/booktracker-stage_functions.sh; this script orchestrates
# discovery, download, staging, archiving, and state tracking.
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Load configuration -----------------------------------------------------
# shellcheck source=../config/config.sh
source "$PROJECT_ROOT/config/config.sh"

# Load optional gitignored .env (credentials / overrides), if present.
if [[ -f "$PROJECT_ROOT/.env" ]]; then
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
  -f, --force     Re-stage even if already recorded in data/staged.tsv
  -n, --dry-run   Print what would happen without downloading
  -d, --debug     Enable debug logging
  -h, --help      Show this help

Environment:
  STAGING_DIR     (required) absolute path to the staging root
EOF
}

# stage_one <torrent_file>
# Download one torrent's allowed files into a working dir, move them into the
# right STAGING_DIR subfolder, archive the working dir, and record the result.
# Returns 0 on success, 1 on failure.
stage_one() {
    local torrent_file="$1" name type dest dest_dir work select files_list stamp
    local f base dst files_csv="" n=0

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

    stamp="${name#"${TORRENT_NAME_PREFIX}-${type}-"}"
    stamp="${stamp%.torrent}"

    work="$TORRENT_DIR/work/${name%.torrent}"
    mkdir -p "$work" || { log_error "cannot create working dir: $work"; return 1; }

    # Determine the aria2c --select-file set for selective types.
    select=""
    case "$type" in
        dump|inpx-fb2|inpx-all)
            files_list="$(aria2c --show-files "$torrent_file" 2>/dev/null)" || {
                log_error "aria2c --show-files failed: $name"
                return 1
            }
            select="$(stage_select_indexes "$type" <<< "$files_list")"
            if [[ -z "$select" ]]; then
                log_warn "no allowed files found in $name; skipping"
                return 1
            fi
            ;;
    esac

    # Download (or print the command in dry-run).
    local -a aria_args=(--seed-time="${ARIA2C_SEED_TIME}" --dir="$work")
    [[ -n "$select" ]] && aria_args+=(--select-file="$select")
    if (( DRY_RUN )); then
        log_info "[dry-run] would run: aria2c ${aria_args[*]} $torrent_file"
    elif ! aria2c "${aria_args[@]}" "$torrent_file"; then
        log_error "aria2c download failed: $name"
        return 1
    fi

    # Stage the allowed files.
    if (( DRY_RUN )); then
        log_info "[dry-run] would stage allowed files into $dest_dir"
    else
        mkdir -p "$dest_dir" || { log_error "cannot create staging dir: $dest_dir"; return 1; }
        case "$type" in
            dump)
                while IFS= read -r -d '' f; do
                    [[ "$f" == *.gz ]] || continue
                    base="${f##*/}"
                    dst="${base%.gz}"
                    if gzip -dkc "$f" > "$dest_dir/$dst"; then
                        log_info "staged: $dest_dir/$dst"
                    else
                        log_error "failed to decompress $f"
                        return 1
                    fi
                    files_csv="${files_csv:+$files_csv,}$dst"
                    n=$((n + 1))
                done < <(find "$work" -type f -print0)
                ;;
            *)
                while IFS= read -r -d '' f; do
                    base="${f##*/}"
                    if stage_place "$type" "$f" "$dest_dir"; then
                        log_info "staged: $dest_dir/$base"
                    else
                        log_error "failed to stage $f"
                        return 1
                    fi
                    files_csv="${files_csv:+$files_csv,}$base"
                    n=$((n + 1))
                done < <(find "$work" -type f -print0)
                ;;
        esac
        (( n > 0 )) || log_warn "no files staged from $name"
    fi

    # Archive the working dir.
    if (( DRY_RUN )); then
        log_info "[dry-run] would archive $work -> $ARCHIVE_DIR/$(basename "$work")"
    else
        mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true
        if mv "$work" "$ARCHIVE_DIR/$(basename "$work")"; then
            log_info "archived working dir: $work"
        else
            log_warn "failed to archive $work"
        fi
    fi

    # Record the result.
    if (( DRY_RUN )); then
        log_info "[dry-run] would record: $type $name stamp=$stamp dest=$dest files=${files_csv:-<none>}"
    else
        stage_record "$type" "$name" "$stamp" "$dest" "$files_csv"
    fi

    return 0
}

main() {
    local arg f t ok=0 fail=0
    local -a torrents=()
    DRY_RUN="${DRY_RUN:-0}"
    FORCE="${FORCE:-0}"

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
