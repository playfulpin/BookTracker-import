#!/usr/bin/env bash
# =============================================================================
# booktracker-ingest.sh
#
# Load decompressed Flibusta dump .sql files (produced by booktracker-extract.sh)
# into a local MySQL/MariaDB instance and run MultiLib's transform SQL to
# rebuild its catalog (lib* -> ml*).
#
# Stages:
#   load      load mysql_feeds/*.sql (+ lib.libfilenameold.sql) into MYSQL_DATABASE
#   convert   run lib.convert.sql (lib* -> ml*)
#   base      run createtable.sql (mllbr_main tables)
#   rating    run Flibusta_Load_mlrating.sql (build mlrating from librate)
#   check     verify the rebuilt catalog/ratings are populated (read-only)
#   cleanup   drop leftover working tables (librating + raw lib* tables)
#
# With no stage argument, runs all six in order.
#
# The transform/base/rating SQL is bundled under sql/ (SQL_DIR).
#
# Pure helpers live in lib/booktracker-ingest_functions.sh.
# Logging is reused from lib/booktracker-import_functions.sh.
#
# Connection: 127.0.0.1 via TCP (WSL2 mirrored networking shares the Windows
# host loopback).  Use `-h 127.0.0.1`, never `localhost` (Unix socket).
#
# Exit codes:
#   0  success
#   1  operational failure
#   2  usage error
#
# Version:  0.1.3
# Updated:  2026-08-22 11:32 CDT
# Requires: bash >= 4, mysql/mariadb client
#
# Examples:
#   ./bin/booktracker-ingest.sh --dry-run
#   ./bin/booktracker-ingest.sh load
#   ./bin/booktracker-ingest.sh --force convert
#   ./bin/booktracker-ingest.sh --debug all
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
# Libraries (logging from import; ingest helpers)
# ---------------------------------------------------------------------------
# shellcheck source=../lib/booktracker-import_functions.sh
source "$PROJECT_ROOT/lib/booktracker-import_functions.sh"
# shellcheck source=../lib/booktracker-ingest_functions.sh
source "$PROJECT_ROOT/lib/booktracker-ingest_functions.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<'USAGE_EOF'
Usage: booktracker-ingest.sh [options] [stage...]

Load decompressed dump .sql files into MySQL/MariaDB and rebuild the MultiLib
catalog (lib* -> ml*), then build ratings, verify, and clean up. With no
stage, runs all six in order.

Stages:
  load      Load mysql_feeds/*.sql (+ lib.libfilenameold.sql)
  convert   Run lib.convert.sql (lib* -> ml* transform)
  base      Run createtable.sql (mllbr_main tables)
  rating    Run Flibusta_Load_mlrating.sql (build mlrating from librate)
  check     Verify the rebuilt catalog/ratings are populated (read-only)
  cleanup   Drop leftover working tables (librating + raw lib* tables)
  all       Synonym for running all stages (default)

Every real run first backs up MULTILIB_DATA_DIR to a timestamped sibling.

Options:
  -f, --force    Re-run the stage(s) even if already recorded in ingested.tsv
  -n, --dry-run  Print the mysql commands without executing
  -d, --debug    Enable debug logging
  -h, --help     Show this help

Exit codes:
  0  success
  1  operational failure
  2  usage error

Environment:
  MYSQL_DATABASE         target database (default: flibusta)
  MYSQL_HOST / PORT      server (default: 127.0.0.1 / 3306)
  MYSQL_USER / PASSWORD  credentials (default: root / empty)
  SQL_DIR                bundled transform/base SQL dir (default: <project>/sql)
  MULTILIB_DATA_DIR      MariaDB data dir, backed up before every real run
                         (default: /mnt/c/MultiLib/data)
  INGEST_CLEANUP_TABLES  leftover tables dropped by cleanup (space-separated)
USAGE_EOF
}

# usage_error [message]
usage_error() {
    [[ -n "${1:-}" ]] && log_error "$1"
    usage >&2
    return 2
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local arg stage ok=0 fail=0
    local -a stages=()

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
            load|convert|base|rating|check|cleanup)
                stages+=("$arg")
                ;;
            all)
                stages=()
                ;;
            -*)
                usage_error "unknown option: $arg"
                return $?
                ;;
            *)
                usage_error "unknown stage: $arg"
                return $?
                ;;
        esac
        shift
    done

    if [[ -z "${MYSQL_DATABASE:-}" ]]; then
        usage_error "MYSQL_DATABASE is empty (set it, e.g. flibusta)"
        return $?
    fi
    if ! command -v "${MYSQL_CLIENT:-mysql}" >/dev/null 2>&1; then
        log_error "${MYSQL_CLIENT:-mysql} not found; install a mysql/mariadb client"
        return 1
    fi

    if (( ${#stages[@]} == 0 )); then
        stages=(load convert base rating check cleanup)
    fi

    # Back up MultiLib's data dir first (dry-run only reports the copy).
    ingest_backup || { log_error "aborting: backup failed"; return 1; }

    # Ensure MariaDB is running before touching the database.
    if ! ingest_mariadb_running; then
        log_info "MariaDB is not running; attempting to start it"
        ingest_mariadb_start || { log_error "aborting: cannot start MariaDB"; return 1; }
    else
        debug "MariaDB is already running"
    fi

    log_info "ingesting ${#stages[@]} stage(s) into $MYSQL_DATABASE"
    for stage in "${stages[@]}"; do
        if "ingest_$stage"; then
            ok=$((ok + 1))
            log_info "stage ok: $stage"
        else
            fail=$((fail + 1))
            log_warn "stage failed: $stage"
            if (( INGEST_STRICT )); then
                return 1
            fi
        fi
    done

    # Stop MariaDB if we started it; leave it if it was already running.
    ingest_mariadb_stop

    if (( fail > 0 )); then
        log_warn "finished ingesting: $ok ok, $fail failed"
    else
        log_info "finished ingesting: $ok ok, $fail failed"
    fi
    return $(( fail > 0 ))
}

main "$@"
exit $?
