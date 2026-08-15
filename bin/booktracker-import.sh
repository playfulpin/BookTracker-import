#!/usr/bin/env bash
# =============================================================================
# booktracker-import — main executable
#
# Command-line front end for importing Флибуста (Flibusta) book torrents from
# booktracker.org.  Site logic lives in lib/booktracker-import_functions.sh;
# this script only parses arguments and dispatches.
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

usage() {
    cat <<'EOF'
Usage: booktracker-import.sh [options] <command> [args]

Commands:
  login                    Log in to booktracker.org and store the session
  get-inpx-fb2 [dir]       Download the INPX (FB2 only) torrent
  get-inpx-all [dir]       Download the INPX (full / "расширенный") torrent
  get-dump      [dir]      Download the database dump torrent
  get-monthly-fb2 [dir]    Download the monthly FB2 archive torrent
  get-monthly-usr [dir]    Download the monthly non-FB2 archive torrent
  check <torrent> [date]   Validate a torrent; print and compare its timestamp
                           (date: YYYY-MM-DD, YYYYMMDD, epoch, or 'now')
  prune                    Remove archived torrents older than retention days
  history                  Show the download state/history (TSV)
  all [dir]                Run all five get-* targets in sequence

Options:
  -d, --debug              Enable debug logging
  -n, --dry-run            Do not download; only print what would happen
  -f, --force              Re-download even if already recorded
  -h, --help               Show this help

Options may appear before or after the command (e.g. `all -f`).

Credentials are read from BOOKTRACKER_USERNAME / BOOKTRACKER_PASSWORD
(environment variables or a gitignored .env file in the project root).
EOF
}

main() {
    local arg cmd=""
    local -a pos=()
    DRY_RUN="${DRY_RUN:-0}"
    FORCE="${FORCE:-0}"

    # Options are accepted before or after the command; every non-option is
    # either the command (first) or a positional argument to it.
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
                if [[ -z "$cmd" ]]; then
                    cmd="$arg"
                else
                    pos+=("$arg")
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$cmd" ]]; then
        usage >&2
        return 2
    fi

    case "$cmd" in
        login)
            login
            ;;
        get-inpx-fb2)
            get_inpx_fb2 "${pos[0]:-}"
            ;;
        get-inpx-all)
            get_inpx_all "${pos[0]:-}"
            ;;
        get-dump)
            get_dump "${pos[0]:-}"
            ;;
        get-monthly-fb2)
            get_monthly_fb2 "${pos[0]:-}"
            ;;
        get-monthly-usr)
            get_monthly_usr "${pos[0]:-}"
            ;;
        prune)
            prune
            ;;
        history)
            list_downloads
            ;;
        all)
            all "${pos[0]:-}"
            ;;
        check)
            local file="${pos[0]:-}" ref_date="${pos[1]:-}" ts
            if [[ -z "$file" ]]; then
                log_error "check requires a torrent file argument"
                return 2
            fi
            if ! is_valid_torrent "$file"; then
                return 1
            fi
            if ts="$(get_torrent_timestamp "$file")"; then
                printf 'timestamp: %s (%s UTC)\n' "$ts" "$(date -u -d "@$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
            fi
            if [[ -n "$ref_date" ]]; then
                is_valid_timestamp "$file" "$ref_date"
                return $?
            fi
            return 0
            ;;
        *)
            log_error "unknown command: $cmd"
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
exit $?
