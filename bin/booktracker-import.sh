#!/usr/bin/env bash
# =============================================================================
# booktracker-import.sh
#
# Command-line front-end for downloading Флибуста (Flibusta) .torrent files
# from booktracker.org into a local library staging area.
#
# Site-specific logic lives in lib/booktracker-import_functions.sh.
# This script only:
#   1. Loads configuration and optional .env overrides
#   2. Parses CLI options / command
#   3. Dispatches to the corresponding library function
#
# Version:  0.1.1
# Updated:  2026-08-20 15:18 CDT
# Requires: bash >= 4, curl, GNU grep, GNU date, coreutils
#
# Examples:
#   ./bin/booktracker-import.sh login
#   ./bin/booktracker-import.sh get-inpx-fb2
#   ./bin/booktracker-import.sh get-monthly-fb2 /path/to/torrents
#   ./bin/booktracker-import.sh --dry-run --debug all
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# shellcheck source=../config/config.sh
source "$PROJECT_ROOT/config/config.sh"

# Optional gitignored .env (credentials / path overrides).
# BOOKTRACKER_NO_ENV=1 skips it so explicit environment variables win.
if [[ -f "$PROJECT_ROOT/.env" && "${BOOKTRACKER_NO_ENV:-0}" != 1 ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env"
    set +a
fi

# ---------------------------------------------------------------------------
# Library functions
# ---------------------------------------------------------------------------
# shellcheck source=../lib/booktracker-import_functions.sh
source "$PROJECT_ROOT/lib/booktracker-import_functions.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
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
  check <torrent> [date]   Validate a torrent; print and optionally compare
                           its creation timestamp (date: YYYY-MM-DD, YYYYMMDD,
                           epoch, or 'now')
  prune                    Remove archived torrents older than retention days
  history                  Show the download state/history (TSV)
  all [dir]                Run all five get-* targets in sequence

Options:
  -d, --debug              Enable debug logging
  -n, --dry-run            Print actions without downloading
  -f, --force              Re-download even if already recorded
  -h, --help               Show this help

Options may appear before or after the command (e.g. `all -f`).

Credentials: BOOKTRACKER_USERNAME / BOOKTRACKER_PASSWORD
  (environment variables or a gitignored .env in the project root).

Torrent files are saved under STAGING_DIR/torrents/
  (default: /Downloads/flibusta_snapshot/torrents).
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local arg cmd=""
    local -a pos=()

    DRY_RUN="${DRY_RUN:-0}"
    FORCE="${FORCE:-0}"

    # Accept options before or after the command.
    # First non-option becomes the command; the rest are positional args.
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
                printf 'timestamp: %s (%s UTC)\n' \
                    "$ts" "$(date -u -d "@$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
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