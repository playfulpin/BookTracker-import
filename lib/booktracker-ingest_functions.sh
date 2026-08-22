#!/usr/bin/env bash
# =============================================================================
# booktracker-ingest_functions.sh
#
# Shared library for booktracker-ingest.
# Sourced by bin/booktracker-ingest.sh and by the test suite.
#
# Loads decompressed Flibusta dump .sql files into a local MySQL/MariaDB
# instance and runs MultiLib's transform SQL to rebuild its catalog.
#
# Public API
# ----------
#   state        ingest_is_done  ingest_record
#   discovery    ingest_list_sql
#   validation   ingest_validate_sql
#   backup       ingest_backup
#   stages       ingest_load  ingest_convert  ingest_base  ingest_rating
#                ingest_check  ingest_cleanup  ingest
#
# Private helpers (prefixed with _): _ingest_mysql_cmd, _ingest_run_sql_file,
# _ingest_run_query, _ingest_normalize_sql, _ingest_run_files.
#
# Connection: `-h 127.0.0.1 --protocol=TCP` (WSL2 mirrored networking shares
# the Windows host loopback; `localhost` would try a Unix socket on Linux).
# The password is passed via MYSQL_PWD, never on the command line.
#
# The transform/base/rating SQL is bundled under sql/ (SQL_DIR).  Those files
# were authored on Windows, so each is passed through _ingest_normalize_sql
# (strips a leading UTF-8 BOM and CRLF line endings) before it reaches the
# client.
#
# Version:  0.1.2
# Updated:  2026-08-21 20:23 CDT
# Requires: bash >= 4, mysql/mariadb client
# Shell style: quote expansions; prefer local; return not exit; shellcheck-friendly.
# =============================================================================

# Guard against double-sourcing.
[[ -n "${_BOOKTRACKER_INGEST_FUNCTIONS_LOADED:-}" ]] && return 0 2>/dev/null || true
_BOOKTRACKER_INGEST_FUNCTIONS_LOADED=1

# ---------------------------------------------------------------------------
# Sensible defaults (fallbacks when config.sh has not been sourced)
# ---------------------------------------------------------------------------
: "${MYSQL_CLIENT:=mysql}"
: "${MYSQL_HOST:=127.0.0.1}"
: "${MYSQL_PORT:=3306}"
: "${MYSQL_USER:=root}"
: "${MYSQL_PASSWORD:=}"
: "${MYSQL_DATABASE:=flibusta}"
: "${MYSQL_EXTRA_ARGS:=--default-character-set=utf8}"
: "${SQL_DIR:=/mnt/c/MultiLib/plugins}"
: "${MULTILIB_DATA_DIR:=/mnt/c/MultiLib/data}"
: "${INGEST_STATE_FILE:=${DATA_DIR:-.}/ingested.tsv}"
: "${INGEST_STRICT:=1}"
: "${INGEST_CLEANUP_TABLES:=librating librate libjoinedbooks librecs libtranslator}"
: "${DRY_RUN:=0}"
: "${FORCE:=0}"
: "${STAGING_DIR:=/Downloads/flibusta_snapshot}"
: "${MYSQL_FEEDS_SUBDIR:=mysql_feeds}"

# =============================================================================
# State
# =============================================================================

# ingest_is_done <stage> [state_file]
# Return 0 when the stage is already recorded in the ingest state file.
ingest_is_done() {
    local stage="$1" state="${2:-${INGEST_STATE_FILE:-}}"
    [[ -n "$state" && -f "$state" ]] || return 1
    awk -F '\t' -v s="$stage" '$2 == s { found = 1 } END { exit (found ? 0 : 1) }' "$state"
}

# ingest_record <stage> <status> [detail]
# Append one row to the ingest state file (TSV).
ingest_record() {
    local stage="$1" status="$2" detail="${3:-}" state ts
    state="${INGEST_STATE_FILE:-}"
    [[ -n "$state" ]] || return 1
    mkdir -p "$(dirname "$state")" 2>/dev/null || true
    if [[ ! -f "$state" ]]; then
        printf 'ingested_at\tstage\tdatabase\tstatus\tdetail\n' > "$state"
    fi
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$stage" "${MYSQL_DATABASE:-}" "$status" "$detail" >> "$state"
}

# =============================================================================
# Discovery & validation
# =============================================================================

# ingest_list_sql <dir>
# Print the .sql files in <dir> (sorted), one per line. Returns 1 when absent.
ingest_list_sql() {
    local dir="$1" f
    [[ -d "$dir" ]] || return 1
    for f in "$dir"/*.sql; do
        [[ -e "$f" ]] || continue
        printf '%s\n' "$f"
    done
}

# ingest_validate_sql <file>
# Cheap pre-flight: a mysqldump contains DDL/DML statements.  A truncated
# download would lack them.  Returns 0 when the file looks loadable.
ingest_validate_sql() {
    local file="$1"
    [[ -f "$file" && -s "$file" ]] || return 1
    grep -aqE 'CREATE TABLE|DROP TABLE|INSERT|REPLACE INTO' "$file"
}

# =============================================================================
# MySQL client helpers (private)
# =============================================================================

# _ingest_normalize_sql
# Read SQL on stdin; strip a leading UTF-8 BOM and CR from CRLF line endings.
# The bundled MultiLib SQL files are saved from Windows, so this keeps the
# first statement (a `/*!40101 ... */` comment) from being prefixed by a BOM
# and normalizes Windows line endings for the mysql client.
_ingest_normalize_sql() {
    sed -e '1s/^\xef\xbb\xbf//' -e 's/\r$//'
}

# _ingest_mysql_cmd
# Print the mysql client argv (space-joined, password omitted) for logging.
_ingest_mysql_cmd() {
    local -a a=("${MYSQL_CLIENT:-mysql}")
    [[ -n "${MYSQL_HOST:-}" ]] && a+=(-h "${MYSQL_HOST}" --protocol=TCP)
    [[ -n "${MYSQL_PORT:-}" ]] && a+=(-P "${MYSQL_PORT}")
    [[ -n "${MYSQL_USER:-}" ]] && a+=(-u "${MYSQL_USER}")
    [[ -n "${MYSQL_EXTRA_ARGS:-}" ]] && a+=("${MYSQL_EXTRA_ARGS}")
    [[ -n "${MYSQL_DATABASE:-}" ]] && a+=("${MYSQL_DATABASE}")
    printf '%s ' "${a[@]}"
}

# _ingest_run_sql_file <file>
# Run the mysql client with <file> (BOM/CRLF-normalized) as stdin.  Streams
# stderr to the log and terminal; returns the client's exit code.  Password via
# MYSQL_PWD only.
_ingest_run_sql_file() {
    local file="$1" rc=0
    local -a cmd=("${MYSQL_CLIENT:-mysql}")
    [[ -n "${MYSQL_HOST:-}" ]] && cmd+=(-h "${MYSQL_HOST}" --protocol=TCP)
    [[ -n "${MYSQL_PORT:-}" ]] && cmd+=(-P "${MYSQL_PORT}")
    [[ -n "${MYSQL_USER:-}" ]] && cmd+=(-u "${MYSQL_USER}")
    [[ -n "${MYSQL_EXTRA_ARGS:-}" ]] && cmd+=("${MYSQL_EXTRA_ARGS}")
    [[ -n "${MYSQL_DATABASE:-}" ]] && cmd+=("${MYSQL_DATABASE}")

    if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
        _ingest_normalize_sql < "$file" \
            | MYSQL_PWD="${MYSQL_PASSWORD}" "${cmd[@]}" 2>&1 \
            | tee -a "${LOG_FILE:-/dev/null}" >&2
        rc="${PIPESTATUS[1]}"
    else
        _ingest_normalize_sql < "$file" \
            | "${cmd[@]}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" >&2
        rc="${PIPESTATUS[1]}"
    fi
    return "$rc"
}

# _ingest_run_query <sql>
# Run a single SQL statement (or batch) via `-e`.  stdout carries the result
# for the caller; stderr goes to the log.  Returns the client's exit code.
_ingest_run_query() {
    local q="$1" rc=0
    local -a cmd=("${MYSQL_CLIENT:-mysql}")
    [[ -n "${MYSQL_HOST:-}" ]] && cmd+=(-h "${MYSQL_HOST}" --protocol=TCP)
    [[ -n "${MYSQL_PORT:-}" ]] && cmd+=(-P "${MYSQL_PORT}")
    [[ -n "${MYSQL_USER:-}" ]] && cmd+=(-u "${MYSQL_USER}")
    [[ -n "${MYSQL_EXTRA_ARGS:-}" ]] && cmd+=("${MYSQL_EXTRA_ARGS}")
    [[ -n "${MYSQL_DATABASE:-}" ]] && cmd+=("${MYSQL_DATABASE}")

    if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
        MYSQL_PWD="${MYSQL_PASSWORD}" "${cmd[@]}" -N -B -e "$q" 2>"${LOG_FILE:-/dev/null}"
        rc=$?
    else
        "${cmd[@]}" -N -B -e "$q" 2>"${LOG_FILE:-/dev/null}"
        rc=$?
    fi
    return "$rc"
}

# _ingest_run_files <file...>
# Run each SQL file in order.  Honors DRY_RUN; aborts on first failure in
# strict mode.  Returns 0 when every file succeeded.
_ingest_run_files() {
    local f ok=0 fail=0
    local -a failed=()
    for f in "$@"; do
        [[ -f "$f" ]] || {
            log_warn "ingest sql file not found: $f"
            fail=$((fail + 1)); failed+=("$f")
            continue
        }
        if (( DRY_RUN )); then
            log_info "[dry-run] would run: $(_ingest_mysql_cmd)< $f"
            continue
        fi
        log_info "ingesting: $f"
        if _ingest_run_sql_file "$f"; then
            ok=$((ok + 1))
            debug "ingested ok: $f"
        else
            fail=$((fail + 1)); failed+=("$f")
            log_error "ingest failed: $f"
            if (( INGEST_STRICT )); then
                return 1
            fi
        fi
    done
    if (( fail > 0 )); then
        log_warn "ingested $ok ok, $fail failed (${failed[*]})"
        return 1
    fi
    log_info "ingested $ok file(s)"
    return 0
}

# =============================================================================
# Backup
# =============================================================================

# ingest_backup
# Copy MULTILIB_DATA_DIR to a timestamped sibling before any ingest.  Runs on
# every real (non-dry-run) invocation; never skipped.
ingest_backup() {
    local src="${MULTILIB_DATA_DIR:-}" dst ts
    if [[ -z "$src" ]]; then
        log_error "MULTILIB_DATA_DIR is empty"
        return 1
    fi
    if [[ ! -d "$src" ]]; then
        log_error "MultiLib data dir not found: $src"
        return 1
    fi
    ts="$(date '+%Y-%m-%d_%H%M%S')"
    dst="${src}_${ts}"
    if (( DRY_RUN )); then
        log_info "[dry-run] would back up $src -> $dst"
        return 0
    fi
    log_info "backing up MultiLib data: $src -> $dst"
    if ! cp -a "$src" "$dst"; then
        log_error "backup failed: $src -> $dst"
        return 1
    fi
    ingest_record "backup" "ok" "$dst"
    return 0
}

# =============================================================================
# Stages
# =============================================================================

# ingest_load
# Load mysql_feeds/*.sql plus the legacy lib.libfilenameold.sql (from SQL_DIR)
# into MYSQL_DATABASE (creates the raw lib* tables).
ingest_load() {
    local dir="$STAGING_DIR/$MYSQL_FEEDS_SUBDIR" oldfile="$SQL_DIR/lib.libfilenameold.sql"
    local -a files=()
    local f

    if (( ! FORCE )) && ingest_is_done "load"; then
        log_info "load already done (use --force to re-load)"
        return 0
    fi
    if [[ ! -d "$dir" ]]; then
        log_error "dump .sql dir not found: $dir (run booktracker-extract.sh first)"
        return 1
    fi
    for f in "$dir"/*.sql; do
        [[ -e "$f" ]] || continue
        files+=("$f")
    done
    [[ -f "$oldfile" ]] && files+=("$oldfile")
    if (( ${#files[@]} == 0 )); then
        log_warn "no .sql files to load in $dir"
        return 1
    fi

    log_info "load stage: loading ${#files[@]} dump file(s) into $MYSQL_DATABASE"
    _ingest_run_files "${files[@]}" || return 1
    (( DRY_RUN )) || ingest_record "load" "ok" "${#files[@]} files"
    return 0
}

# ingest_convert
# Run lib.convert.sql (from SQL_DIR) to transform lib* -> ml* (rebuilds catalog).
ingest_convert() {
    local cfile="$SQL_DIR/lib.convert.sql"

    if (( ! FORCE )) && ingest_is_done "convert"; then
        log_info "convert already done (use --force to re-convert)"
        return 0
    fi
    if [[ ! -f "$cfile" ]]; then
        log_error "convert sql not found: $cfile (set SQL_DIR)"
        return 1
    fi

    log_info "convert stage: rebuilding ml* catalog (lib* -> ml*)"
    _ingest_run_files "$cfile" || return 1
    (( DRY_RUN )) || ingest_record "convert" "ok" "$(basename "$cfile")"
    return 0
}

# ingest_base
# Run createtable.sql + genre.sql (from SQL_DIR) to create the base tables and
# the genre list.
ingest_base() {
    local bfile="$SQL_DIR/createtable.sql" gfile="$SQL_DIR/genre.sql"
    local -a files=("$bfile")

    if (( ! FORCE )) && ingest_is_done "base"; then
        log_info "base already done (use --force to re-run)"
        return 0
    fi
    if [[ ! -f "$bfile" ]]; then
        log_error "base sql not found: $bfile (set SQL_DIR)"
        return 1
    fi
    [[ -f "$gfile" ]] && files+=("$gfile")

    log_info "base stage: creating base tables (createtable.sql, genre.sql)"
    _ingest_run_files "${files[@]}" || return 1
    (( DRY_RUN )) || ingest_record "base" "ok" "${#files[@]} files"
    return 0
}

# ingest_rating
# Run Flibusta_Load_mlrating.sql (from SQL_DIR) after the catalog is rebuilt.
# Builds mlrating from the raw librate table.
ingest_rating() {
    local rfile="$SQL_DIR/Flibusta_Load_mlrating.sql"

    if (( ! FORCE )) && ingest_is_done "rating"; then
        log_info "rating already done (use --force to re-run)"
        return 0
    fi
    if [[ ! -f "$rfile" ]]; then
        log_error "rating sql not found: $rfile (set SQL_DIR)"
        return 1
    fi

    log_info "rating stage: building mlrating from librate"
    _ingest_run_files "$rfile" || return 1
    (( DRY_RUN )) || ingest_record "rating" "ok" "$(basename "$rfile")"
    return 0
}

# ingest_check
# Read-only verification that the rebuilt catalog and ratings are populated.
# Fails when the counts are missing or zero.
ingest_check() {
    local q out books ratings

    if (( ! FORCE )) && ingest_is_done "check"; then
        log_info "check already done (use --force to re-check)"
        return 0
    fi
    q="SELECT CONCAT(COUNT(*), '|', (SELECT COUNT(*) FROM mlrating)) FROM mlbook;"
    log_info "check stage: verifying catalog is populated"
    if (( DRY_RUN )); then
        log_info "[dry-run] would run: $(_ingest_mysql_cmd)-e \"$q\""
        return 0
    fi
    out="$(_ingest_run_query "$q")" || { log_error "check query failed"; return 1; }
    books="${out%%|*}"; books="${books//[[:space:]]/}"
    ratings="${out##*|}"; ratings="${ratings//[[:space:]]/}"
    log_info "check: mlbook=$books mlrating=$ratings"
    if [[ -z "$books" || "$books" == "0" || -z "$ratings" || "$ratings" == "0" ]]; then
        log_error "check failed: catalog appears empty (mlbook=$books, mlrating=$ratings)"
        return 1
    fi
    ingest_record "check" "ok" "mlbook=$books mlrating=$ratings"
    return 0
}

# ingest_cleanup
# Drop leftover working tables (INGEST_CLEANUP_TABLES): the intermediate
# librating table and the raw lib* dump tables not consumed by lib.convert.sql.
ingest_cleanup() {
    local tables="${INGEST_CLEANUP_TABLES:-}" q t

    if (( ! FORCE )) && ingest_is_done "cleanup"; then
        log_info "cleanup already done (use --force to re-clean)"
        return 0
    fi
    if [[ -z "$tables" ]]; then
        log_info "cleanup stage: nothing to drop (INGEST_CLEANUP_TABLES empty)"
        (( DRY_RUN )) || ingest_record "cleanup" "ok" "nothing to drop"
        return 0
    fi
    for t in $tables; do
        q+="DROP TABLE IF EXISTS \`$t\`;"
    done
    log_info "cleanup stage: dropping leftover tables: $tables"
    if (( DRY_RUN )); then
        log_info "[dry-run] would run: $(_ingest_mysql_cmd)-e \"$q\""
        return 0
    fi
    _ingest_run_query "$q" || { log_error "cleanup failed"; return 1; }
    ingest_record "cleanup" "ok" "$tables"
    return 0
}

# ingest
# Run the full pipeline: load -> convert -> base -> rating -> check -> cleanup.
# Honors INGEST_STRICT.
ingest() {
    local rc=0
    log_info "ingest: load -> convert -> base -> rating -> check -> cleanup into $MYSQL_DATABASE"
    ingest_load    || { rc=1; (( INGEST_STRICT )) && return 1; }
    ingest_convert || { rc=1; (( INGEST_STRICT )) && return 1; }
    ingest_base    || { rc=1; (( INGEST_STRICT )) && return 1; }
    ingest_rating  || { rc=1; (( INGEST_STRICT )) && return 1; }
    ingest_check   || { rc=1; (( INGEST_STRICT )) && return 1; }
    ingest_cleanup || { rc=1; (( INGEST_STRICT )) && return 1; }
    if (( rc )); then
        log_warn "ingest finished with failures"
    else
        log_info "ingest finished"
    fi
    return "$rc"
}
