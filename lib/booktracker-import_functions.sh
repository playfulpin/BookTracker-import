#!/usr/bin/env bash
# =============================================================================
# booktracker-import — shared functions
#
# Sourced by bin/booktracker-import.sh (and by the test suite).  Contains the
# reusable building blocks:
#
#   logging          log, log_info, log_warn, log_error, debug
#   session          login
#   torrent          get_torrent_timestamp, is_valid_timestamp, is_valid_torrent
#   downloads        get_inpx_fb2, get_inpx_all, get_dump,
#                    get_monthly_fb2, get_monthly_usr
#
# Requires: bash >= 4, curl, grep, sed, date (GNU), head
# =============================================================================

# Allow being sourced multiple times without redefining everything.
[[ -n "${_BOOKTRACKER_FUNCTIONS_LOADED:-}" ]] && return 0 2>/dev/null || true
_BOOKTRACKER_FUNCTIONS_LOADED=1

# Sensible fallbacks so the library is usable even if config.sh was not sourced.
: "${BOOKTRACKER_BASE_URL:=https://booktracker.org}"
: "${COOKIE_JAR:=${TMPDIR:-/tmp}/booktracker-cookies.txt}"
: "${LOG_LEVEL:=info}"
: "${HTTP_USER_AGENT:=booktracker-import/0.1}"
: "${CURL_CONNECT_TIMEOUT:=15}"
: "${CURL_MAX_TIME:=120}"
: "${DATA_DIR:=${PROJECT_ROOT:-.}/data}"
: "${TORRENT_DIR:=${DATA_DIR}/torrents}"
: "${DRY_RUN:=0}"
: "${VERIFY_TORRENT:=1}"
: "${FORCE:=0}"
: "${MONTH_OFFSET:=1}"
: "${FORUM_FULL_COLLECTIONS_TITLE:=Полные сборки библиотеки Флибуста}"
: "${FORUM_MONTHLY_TITLE:=Ежемесячные архивы (Флибуста)}"
: "${TOPIC_INPX_ALL_TITLE:=inpx}"
: "${TOPIC_INPX_FB2_TITLE:=Дополнительные данные}"
: "${TOPIC_DUMP_TITLE:=Дампы базы данных библиотеки Флибуста}"
: "${TORRENT_NAME_PREFIX:=flibusta}"
: "${ARCHIVE_DIR:=${DATA_DIR}/archive}"
: "${ARCHIVE_TORRENTS:=1}"
: "${TORRENT_RETENTION_DAYS:=0}"
: "${STATE_FILE:=${DATA_DIR}/downloads.tsv}"

# =============================================================================
# Logging
# =============================================================================

_log_level_num() {
    case "${1:-info}" in
        debug) printf '0\n' ;;
        info)  printf '1\n' ;;
        warn)  printf '2\n' ;;
        error) printf '3\n' ;;
        *)     printf '1\n' ;;
    esac
}

# log <level> <message...>
# Emit a timestamped, leveled log line to stderr and (optionally) LOG_FILE.
log() {
    local level="${1:-info}"; shift
    local msg="$*" ts cur threshold
    cur=$(_log_level_num "$level")
    threshold=$(_log_level_num "${LOG_LEVEL:-info}")
    if (( cur < threshold )); then
        return 0
    fi
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] [%-5s] %s\n' "$ts" "$level" "$msg" >&2
    if [[ -n "${LOG_FILE:-}" ]]; then
        printf '[%s] [%-5s] %s\n' "$ts" "$level" "$msg" >>"$LOG_FILE" 2>/dev/null || true
    fi
}

log_info()  { log info  "$@"; }
log_warn()  { log warn  "$@"; }
log_error() { log error "$@"; }

# debug <message...> — only emitted when LOG_LEVEL=debug.
debug() { log debug "$@"; }

# =============================================================================
# HTTP helpers
# =============================================================================

# _curl [curl opts...] url
# Every site request goes through this wrapper so the cookie jar, user agent
# and timeouts stay consistent.
_curl() {
    curl -sS -L \
        --connect-timeout "${CURL_CONNECT_TIMEOUT}" \
        --max-time "${CURL_MAX_TIME}" \
        -A "${HTTP_USER_AGENT}" \
        -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
        "$@"
}

_http_get() {
    local url="$1"; shift
    _curl "$@" "$url"
}

# =============================================================================
# Session / login
# =============================================================================

# _is_logged_in — returns 0 when the stored session is authenticated.
_is_logged_in() {
    local page
    page="$(_curl "$BOOKTRACKER_BASE_URL/index.php" 2>/dev/null)" || return 1
    # A logged-in page includes the logout link and omits the guest login form.
    if printf '%s' "$page" | grep -qi 'logout' \
       && ! printf '%s' "$page" | grep -q 'login_username'; then
        return 0
    fi
    return 1
}

# login [redirect]
# Authenticate against booktracker.org and persist the session cookie.
login() {
    local username password redirect err
    username="${BOOKTRACKER_USERNAME:-}"
    password="${BOOKTRACKER_PASSWORD:-}"
    redirect="${1:-index.php}"

    if [[ -z "$username" || -z "$password" ]]; then
        log_error "credentials missing: set BOOKTRACKER_USERNAME and BOOKTRACKER_PASSWORD (env or .env)"
        return 1
    fi

    mkdir -p "$(dirname "$COOKIE_JAR")" 2>/dev/null || true
    rm -f "$COOKIE_JAR" 2>/dev/null || true   # drop any stale session

    log_info "logging in to $BOOKTRACKER_BASE_URL as '$username'"

    err="$(
        _curl -X POST "$BOOKTRACKER_BASE_URL/login.php" \
            --data-urlencode "login_username=$username" \
            --data-urlencode "login_password=$password" \
            --data-urlencode "redirect=$redirect" \
            --data-urlencode "autologin=1" \
            --data-urlencode "login=1" \
            2>&1 >/dev/null
    )"

    if [[ -n "$err" ]]; then
        log_error "login request failed: $err"
        return 1
    fi

    if _is_logged_in; then
        log_info "login successful"
        return 0
    fi

    log_error "login failed (check credentials or account status)"
    return 1
}

# =============================================================================
# Torrent file inspection
# =============================================================================

# get_torrent_timestamp <torrent_file>
# Print the torrent's bencoded `creation date` (unix epoch) to stdout.
# Returns 0 when the field is present, 1 otherwise.
get_torrent_timestamp() {
    local file="$1" raw ts
    [[ -f "$file" ]] || { log_error "torrent file not found: $file"; return 1; }

    raw="$(grep -aoE '13:creation datei-?[0-9]+e' "$file" | head -n1)"
    if [[ -z "$raw" ]]; then
        log_warn "no 'creation date' field in torrent: $file"
        return 1
    fi
    ts="${raw#13:creation datei}"   # strip the literal bencoded key prefix
    ts="${ts%e}"                     # strip the trailing bencoded 'e'
    printf '%s\n' "$ts"
    return 0
}

# is_valid_torrent <torrent_file>
# Basic structural validation of a bencoded .torrent file.
# Returns 0 when the file looks like a usable torrent, 1 otherwise.
is_valid_torrent() {
    local file="$1" head
    [[ -f "$file" ]] || { log_error "torrent file not found: $file"; return 1; }
    [[ -s "$file" ]] || { log_warn "torrent file is empty: $file"; return 1; }

    # A bencoded torrent is a dictionary.
    head="$(head -c 1 "$file")"
    [[ "$head" == "d" ]] || { log_warn "not a bencoded dictionary (does not start with 'd'): $file"; return 1; }

    grep -aq '8:announce'        "$file" || { log_warn "missing 'announce' field: $file"; return 1; }
    grep -aq '4:info'            "$file" || { log_warn "missing 'info' dictionary: $file"; return 1; }
    grep -aq '12:piece length'   "$file" || { log_warn "missing 'piece length' field: $file"; return 1; }
    grep -aq '6:pieces'          "$file" || { log_warn "missing 'pieces' field: $file"; return 1; }

    return 0
}

# _date_to_epoch <date>
# Normalize a date argument to unix epoch seconds.  Accepts:
#   - unix epoch seconds (9+ digits)
#   - YYYYMMDD (8 digits)
#   - any GNU `date -d` string (e.g. "2026-07-01", "last month")
#   - "" or "now" for the current time
# Date strings are interpreted as UTC so that comparisons against torrent
# `creation date` epochs are deterministic regardless of the local timezone.
_date_to_epoch() {
    local d="$1" len
    case "$d" in
        ''|now)
            date +%s
            ;;
        *)
            len="${#d}"
            if [[ "$d" =~ ^[0-9]{8}$ ]]; then
                date -u -d "${d:0:4}-${d:4:2}-${d:6:2}" +%s 2>/dev/null
            elif [[ "$d" =~ ^-?[0-9]{9,}$ ]]; then
                printf '%s\n' "$d"
            else
                date -u -d "$d" +%s 2>/dev/null
            fi
            ;;
    esac
}

# is_valid_timestamp <torrent_file> <reference_date>
# Compare a torrent's creation timestamp to a reference date.
# Returns 0 when the torrent timestamp is >= the reference date (i.e. the
# torrent is not older than the reference), 1 when it is stale, 2 on bad input.
is_valid_timestamp() {
    local file="$1" ref="${2:-}" tor_ts ref_ts
    if ! tor_ts="$(get_torrent_timestamp "$file")"; then
        return 1
    fi
    ref_ts="$(_date_to_epoch "$ref")"
    if [[ -z "$ref_ts" ]]; then
        log_error "cannot parse reference date: $ref"
        return 2
    fi
    if (( tor_ts >= ref_ts )); then
        log_info "timestamp valid: $tor_ts ($(date -u -d "@$tor_ts" '+%Y-%m-%d' 2>/dev/null)) >= $ref_ts ($(date -u -d "@$ref_ts" '+%Y-%m-%d' 2>/dev/null))"
        return 0
    fi
    log_warn "timestamp stale: $tor_ts ($(date -u -d "@$tor_ts" '+%Y-%m-%d' 2>/dev/null)) < $ref_ts ($(date -u -d "@$ref_ts" '+%Y-%m-%d' 2>/dev/null))"
    return 1
}

# _torrent_stamp <torrent_file>
# Print the torrent's creation date as YYYY-MM-DD (UTC), falling back to the
# current date when the field is absent.  Used to build meaningful file names.
_torrent_stamp() {
    local file="$1" ts stamp
    if ts="$(get_torrent_timestamp "$file" 2>/dev/null)"; then
        stamp="$(date -u -d "@$ts" '+%Y-%m-%d' 2>/dev/null)"
    fi
    printf '%s\n' "${stamp:-$(date -u '+%Y-%m-%d')}"
}

# =============================================================================
# Forum / topic discovery
# =============================================================================

# _html_to_text <html>
# Best-effort conversion of an HTML fragment to searchable plain text: strips
# tags (including <wbr> soft line-breaks) and decodes the entities seen in
# booktracker.org titles.
_html_to_text() {
    printf '%s' "$1" \
        | sed -e 's/<[^>]*>//g' \
              -e 's/&quot;/"/g' \
              -e 's/&nbsp;/ /g'
}

# get_forumid <title>
# Determine a forum's numeric id by searching the main index page for the forum
# link whose (tag-stripped) text contains <title>.  Forum ids are not stable
# across site updates, so they are always resolved from the live HTML.
# Prints the id; returns 0 on success, 1 when not found.
get_forumid() {
    local title="$1" html line fid text
    html="$(_http_get "$BOOKTRACKER_BASE_URL/index.php" 2>/dev/null)" || {
        log_error "failed to fetch index page: $BOOKTRACKER_BASE_URL/index.php"
        return 1
    }

    while IFS= read -r line; do
        [[ "$line" == *"viewforum.php?f="* ]] || continue
        fid="$(printf '%s' "$line" | grep -oE 'viewforum\.php\?f=[0-9]+' | head -n1)"
        fid="${fid#viewforum.php?f=}"
        [[ "$fid" =~ ^[0-9]+$ ]] || continue
        text="$(_html_to_text "$line")"
        if printf '%s' "$text" | grep -qiF -- "$title"; then
            printf '%s\n' "$fid"
            return 0
        fi
    done < <(printf '%s\n' "$html")

    log_warn "forum not found on index page: '$title'"
    return 1
}

# get_topicid <forum_id> <title>
# Determine a topic's numeric id by searching the forum listing for the topic
# link whose (tag-stripped) title contains <title>.  Topic ids change whenever
# a new release is posted, so they are always resolved from the live HTML.
# Prints the id; returns 0 on success, 1 when not found.
get_topicid() {
    local forum_id="$1" title="$2" html line tid text
    html="$(_http_get "$BOOKTRACKER_BASE_URL/viewforum.php?f=$forum_id" 2>/dev/null)" || {
        log_error "failed to fetch forum $forum_id"
        return 1
    }

    while IFS= read -r line; do
        [[ "$line" == *"viewtopic.php?t="* ]] || continue
        tid="$(printf '%s' "$line" | grep -oE 'viewtopic\.php\?t=[0-9]+' | head -n1)"
        tid="${tid#viewtopic.php?t=}"
        [[ "$tid" =~ ^[0-9]+$ ]] || continue
        text="$(_html_to_text "$line")"
        if printf '%s' "$text" | grep -qiF -- "$title"; then
            printf '%s\n' "$tid"
            return 0
        fi
    done < <(printf '%s\n' "$html")

    log_warn "topic not found in forum $forum_id: '$title'"
    return 1
}

# Russian month names (nominative), indexed 1..12.
_RU_MONTHS=( январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь )

# _monthly_target — print "YEAR MM RU_NAME" for the target (previous) month.
_monthly_target() {
    local ym year month
    ym="$(date -d "$(date +%Y-%m-01) -${MONTH_OFFSET} month" +%Y-%m 2>/dev/null)" || {
        log_error "failed to compute target month"
        return 1
    }
    year="${ym%%-*}"
    month="${ym##*-}"
    month=$((10#$month))    # strip leading zero to avoid octal interpretation
    printf '%s %02d %s\n' "$year" "$month" "${_RU_MONTHS[$((month - 1))]}"
}

# =============================================================================
# Downloading
# =============================================================================

# _extract_torrent_link <html>
# Find the .torrent download link on a topic page and print an absolute URL.
# booktracker.org serves torrents from `download.php?id=<attach_id>` inside the
# anchor labeled "Скачать .torrent" (helper attachments use a different, named
# anchor).  Other TorrentPier schemes (dl.php?id=, dl.php?t=) are also handled.
_extract_torrent_link() {
    local html="$1" link

    # Primary: the download link attached to the "Скачать .torrent" anchor.
    link="$(printf '%s' "$html" | awk '
        /(dl|download)\.php\?[a-zA-Z0-9_=&;]+/ {
            if (match($0, /(dl|download)\.php\?[a-zA-Z0-9_=&;]+/))
                last = substr($0, RSTART, RLENGTH)
        }
        /Скачать \.torrent/ { print last; found = 1; exit }
        END { exit (found ? 0 : 1) }
    ')"

    # Fallback: first download link (used when the anchor text differs).
    [[ -n "$link" ]] || \
        link="$(printf '%s' "$html" | grep -oE '(dl|download)\.php\?[a-zA-Z0-9_=&;]+' | head -n1)"

    [[ -n "$link" ]] || return 1
    case "$link" in
        http*://*) printf '%s\n' "$link" ;;
        *) printf '%s/%s\n' "$BOOKTRACKER_BASE_URL" "$link" ;;
    esac
    return 0
}

# _torrent_name <type> <stamp>
# Build the meaningful file name: `<prefix>-<type>-<stamp>.torrent`.
_torrent_name() {
    local type="${1:-torrent}" stamp="${2:-}"
    printf '%s-%s-%s.torrent\n' "$TORRENT_NAME_PREFIX" "$type" "$stamp"
}

# _retire_superseded <type> <new_file>
# Move (or delete) any other same-type torrent in the new file's directory so
# the active directory keeps only the latest file per type.
_retire_superseded() {
    local type="$1" new_file="$2" dir f
    dir="$(dirname "$new_file")"
    for f in "$dir"/"$TORRENT_NAME_PREFIX"-"$type"-*.torrent; do
        [[ -e "$f" ]] || continue
        [[ "$f" == "$new_file" ]] && continue
        if (( DRY_RUN )); then
            log_info "[dry-run] would retire $f"
            continue
        fi
        if (( ARCHIVE_TORRENTS )); then
            mkdir -p "$ARCHIVE_DIR" 2>/dev/null
            if mv -f "$f" "$ARCHIVE_DIR/$(basename "$f")"; then
                log_info "archived superseded torrent: $f"
            else
                log_warn "failed to archive $f"
            fi
        else
            rm -f "$f" && log_info "removed superseded torrent: $f"
        fi
    done
    return 0
}

# _prune_dir <dir> <days> — delete *.torrent files older than <days> (0 = off).
_prune_dir() {
    local dir="$1" days="$2" f
    (( days > 0 )) || return 0
    [[ -d "$dir" ]] || return 0
    find "$dir" -type f -name '*.torrent' -mtime +"$days" -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            if (( DRY_RUN )); then
                log_info "[dry-run] would prune $f"
            else
                rm -f "$f" && log_info "pruned $f"
            fi
        done
}

# prune — remove archived torrents older than TORRENT_RETENTION_DAYS.
prune() {
    if (( TORRENT_RETENTION_DAYS <= 0 )); then
        log_info "retention disabled (TORRENT_RETENTION_DAYS=$TORRENT_RETENTION_DAYS); nothing to prune"
        return 0
    fi
    log_info "pruning archived torrents older than $TORRENT_RETENTION_DAYS days"
    _prune_dir "$ARCHIVE_DIR" "$TORRENT_RETENTION_DAYS"
}

# _record_download <type> <topic> <stamp> <url> <filename>
# Append one row to the download state file (TSV):
#   downloaded_at, type, topic, stamp, url, filename
_record_download() {
    local type="$1" topic="$2" stamp="$3" url="$4" filename="$5" ts
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    if [[ ! -f "$STATE_FILE" ]]; then
        printf 'downloaded_at\ttype\ttopic\tstamp\turl\tfilename\n' > "$STATE_FILE"
    fi
    ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$type" "$topic" "$stamp" "$url" "$filename" >> "$STATE_FILE"
    log_info "recorded download: $type topic=$topic stamp=$stamp"
}

# list_downloads — print the download state file.
list_downloads() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        log_info "no download history yet ($STATE_FILE)"
        return 0
    fi
}

# _already_downloaded <type> <url>
# Return 0 when the state file already records this type + download url.
_already_downloaded() {
    local type="$1" url="$2"
    [[ -f "$STATE_FILE" ]] || return 1
    awk -F '\t' -v t="$type" -v u="$url" '$2 == t && $5 == u { found = 1 } END { exit (found ? 0 : 1) }' "$STATE_FILE"
}

# _download_and_verify <topic_id> <output_dir> [reference_date] [type] [stamp]
# Fetch a topic, extract its .torrent link, download it and (optionally)
# validate the torrent structure and timestamp.  The saved file is named
# meaningfully: `<prefix>-<type>-<stamp>.torrent` (stamp defaults to the
# torrent's creation date).  Superseded same-type files are then retired.
_download_and_verify() {
    local tid="$1" out_dir="$2" ref_date="${3:-}" type="${4:-torrent}" stamp="${5:-}"
    local html dl_url tmp_file out_file

    mkdir -p "$out_dir" 2>/dev/null || { log_error "cannot create directory: $out_dir"; return 1; }

    # Ensure we have a working session before fetching protected pages.
    if ! _is_logged_in; then
        log_info "not logged in; attempting login"
        login || return 1
    fi

    html="$(_http_get "$BOOKTRACKER_BASE_URL/viewtopic.php?t=$tid" 2>/dev/null)" || {
        log_error "failed to fetch topic $tid"
        return 1
    }

    dl_url="$(_extract_torrent_link "$html")" || {
        log_error "no .torrent download link found in topic $tid (not logged in or topic has no torrent)"
        return 1
    }

    # Idempotent re-runs: skip if this exact version was already downloaded.
    if (( ! FORCE )) && _already_downloaded "$type" "$dl_url"; then
        log_info "already downloaded ($type, topic $tid); skipping (use --force to re-download)"
        return 0
    fi

    if (( DRY_RUN )); then
        out_file="$out_dir/$(_torrent_name "$type" "${stamp:-YYYY-MM-DD}")"
        log_info "[dry-run] would download $dl_url to $out_file"
        return 0
    fi

    tmp_file="$(mktemp "$out_dir/.torrent-XXXXXX")" || { log_error "cannot create temp file in $out_dir"; return 1; }
    debug "download url: $dl_url -> $tmp_file (temp)"

    if ! _curl -o "$tmp_file" "$dl_url"; then
        rm -f "$tmp_file" 2>/dev/null || true
        log_error "failed to download torrent from $dl_url"
        return 1
    fi

    if (( VERIFY_TORRENT )) && ! is_valid_torrent "$tmp_file"; then
        rm -f "$tmp_file" 2>/dev/null || true
        log_error "downloaded file is not a valid torrent: $tmp_file"
        return 1
    fi

    if [[ -n "$ref_date" ]] && ! is_valid_timestamp "$tmp_file" "$ref_date"; then
        rm -f "$tmp_file" 2>/dev/null || true
        log_warn "torrent timestamp check failed for $tmp_file"
        return 1
    fi

    # Resolve the stamp from the torrent's creation date when not provided.
    [[ -z "$stamp" ]] && stamp="$(_torrent_stamp "$tmp_file")"

    out_file="$out_dir/$(_torrent_name "$type" "$stamp")"
    mv -f "$tmp_file" "$out_file" || { log_error "failed to move torrent to $out_file"; return 1; }

    _retire_superseded "$type" "$out_file"
    _record_download "$type" "$tid" "$stamp" "$dl_url" "$(basename "$out_file")"

    log_info "downloaded torrent: $out_file ($(du -h "$out_file" | cut -f1))"
    return 0
}

# get_inpx_fb2 [output_dir] — INPX для библиотеки Flibusta (только FB2)
get_inpx_fb2() {
    local out_dir="${1:-$TORRENT_DIR}" forum tid
    forum="$(get_forumid "$FORUM_FULL_COLLECTIONS_TITLE")" || return 1
    log_info "fetching INPX (FB2 only) torrent (searching '$TOPIC_INPX_FB2_TITLE')"
    tid="$(get_topicid "$forum" "$TOPIC_INPX_FB2_TITLE")" || return 1
    _download_and_verify "$tid" "$out_dir" "" "inpx-fb2"
}

# get_inpx_all [output_dir] — inpx для библиотеки Flibusta "расширенный"
get_inpx_all() {
    local out_dir="${1:-$TORRENT_DIR}" forum tid
    forum="$(get_forumid "$FORUM_FULL_COLLECTIONS_TITLE")" || return 1
    log_info "fetching INPX (full) torrent (searching '$TOPIC_INPX_ALL_TITLE')"
    tid="$(get_topicid "$forum" "$TOPIC_INPX_ALL_TITLE")" || return 1
    _download_and_verify "$tid" "$out_dir" "" "inpx-all"
}

# get_dump [output_dir] — Дампы базы данных библиотеки Флибуста
get_dump() {
    local out_dir="${1:-$TORRENT_DIR}" forum tid
    forum="$(get_forumid "$FORUM_FULL_COLLECTIONS_TITLE")" || return 1
    log_info "fetching database dump torrent (searching '$TOPIC_DUMP_TITLE')"
    tid="$(get_topicid "$forum" "$TOPIC_DUMP_TITLE")" || return 1
    _download_and_verify "$tid" "$out_dir" "" "dump"
}

# get_monthly_fb2 [output_dir] — monthly FB2 archive (previous month)
get_monthly_fb2() {
    local out_dir="${1:-$TORRENT_DIR}" forum tid year month ru title ref_date
    read -r year month ru <<< "$(_monthly_target)" || return 1
    title="Архив книг за ${ru} ${year} года (FB2,"
    log_info "looking for monthly FB2 archive: '$title'"
    forum="$(get_forumid "$FORUM_MONTHLY_TITLE")" || return 1
    tid="$(get_topicid "$forum" "$title")" || {
        log_error "monthly FB2 topic not found in forum $forum"
        return 1
    }
    ref_date="${year}-${month}-01"
    _download_and_verify "$tid" "$out_dir" "$ref_date" "monthly-fb2" "${year}-${month}"
}

# get_monthly_usr [output_dir] — monthly non-FB2 archive (previous month)
get_monthly_usr() {
    local out_dir="${1:-$TORRENT_DIR}" forum tid year month ru title ref_date
    read -r year month ru <<< "$(_monthly_target)" || return 1
    title="Архив книг за ${ru} ${year} года [не-FB2,"
    log_info "looking for monthly non-FB2 archive: '$title'"
    forum="$(get_forumid "$FORUM_MONTHLY_TITLE")" || return 1
    tid="$(get_topicid "$forum" "$title")" || {
        log_error "monthly non-FB2 topic not found in forum $forum"
        return 1
    }
    ref_date="${year}-${month}-01"
    _download_and_verify "$tid" "$out_dir" "$ref_date" "monthly-usr" "${year}-${month}"
}

# all [output_dir] — run every get-* target in sequence, skipping anything
# already downloaded.  Continues past failures and returns non-zero if any
# target failed.
all() {
    local out_dir="${1:-}" ok=0 fail=0
    local -a targets=(get_inpx_fb2 get_inpx_all get_dump get_monthly_fb2 get_monthly_usr)
    local t
    for t in "${targets[@]}"; do
        if "$t" "$out_dir"; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
        fi
    done
    log_info "finished: $ok ok, $fail failed"
    return $(( fail > 0 ))
}
