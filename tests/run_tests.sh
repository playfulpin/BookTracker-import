#!/usr/bin/env bash
# =============================================================================
# booktracker-import — test suite
#
# Exercises the pure (network-free) functions.  Run with:
#     bash tests/run_tests.sh
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Isolated test state ----------------------------------------------------
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

export BOOKTRACKER_BASE_URL="https://example.invalid"
export LOG_FILE="$TMPDIR_TEST/test.log"
export LOG_LEVEL="info"
export DRY_RUN=0

source "$PROJECT_ROOT/config/config.sh"
source "$PROJECT_ROOT/lib/booktracker-import_functions.sh"
source "$PROJECT_ROOT/lib/booktracker-stage_functions.sh"

# --- Tiny assertion helpers -------------------------------------------------
PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1)); printf 'ok   - %s\n' "$desc"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL - %s\n       expected: %q\n       actual:   %q\n' "$desc" "$expected" "$actual"
    fi
}

assert_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1)); printf 'ok   - %s\n' "$desc"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL - %s (command should succeed: %s)\n' "$desc" "$*"
    fi
}

assert_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        FAIL=$((FAIL + 1)); printf 'FAIL - %s (command should fail: %s)\n' "$desc" "$*"
    else
        PASS=$((PASS + 1)); printf 'ok   - %s\n' "$desc"
    fi
}

# --- Fixtures ---------------------------------------------------------------
# Use a reference epoch derived from the local date parser so comparisons are
# independent of the machine's timezone.
REF_EPOCH="$(_date_to_epoch '2026-01-01')"

make_valid_torrent() {
    local ts="${1:-$REF_EPOCH}"
    printf 'd8:announce31:http://tracker.example/announce13:creation datei%se4:infod6:lengthi1e4:name8:test.txt12:piece lengthi16384e6:pieces20:abcdefghijklmnopqrstee' "$ts"
}

FIXTURE_DIR="$TMPDIR_TEST"
make_valid_torrent "$REF_EPOCH" > "$FIXTURE_DIR/valid.torrent"

# =============================================================================
# get_torrent_timestamp
# =============================================================================
assert_eq "get_torrent_timestamp extracts creation date" \
    "$REF_EPOCH" \
    "$(get_torrent_timestamp "$FIXTURE_DIR/valid.torrent" 2>/dev/null)"

printf 'd8:announce31:http://tracker.example/announcee' > "$FIXTURE_DIR/no-date.torrent"
assert_fail "get_torrent_timestamp fails when creation date is absent" \
    get_torrent_timestamp "$FIXTURE_DIR/no-date.torrent"

# =============================================================================
# is_valid_torrent
# =============================================================================
assert_ok "is_valid_torrent accepts a valid torrent" \
    is_valid_torrent "$FIXTURE_DIR/valid.torrent"

printf 'this is not a torrent\n' > "$FIXTURE_DIR/junk.torrent"
assert_fail "is_valid_torrent rejects junk" \
    is_valid_torrent "$FIXTURE_DIR/junk.torrent"

printf 'd8:announce31:http://tracker.example/announce4:infode' > "$FIXTURE_DIR/no-pieces.torrent"
assert_fail "is_valid_torrent rejects a torrent without pieces" \
    is_valid_torrent "$FIXTURE_DIR/no-pieces.torrent"

# =============================================================================
# _date_to_epoch
# =============================================================================
assert_eq "_date_to_epoch parses YYYY-MM-DD" \
    "$(date -u -d '2026-01-01' +%s)" \
    "$(_date_to_epoch '2026-01-01')"
assert_eq "_date_to_epoch parses YYYYMMDD" \
    "$(date -u -d '2026-01-01' +%s)" \
    "$(_date_to_epoch '20260101')"
assert_eq "_date_to_epoch passes epoch through" \
    "1767225600" \
    "$(_date_to_epoch '1767225600')"

# =============================================================================
# is_valid_timestamp
# =============================================================================
assert_ok "is_valid_timestamp: torrent at reference date is valid" \
    is_valid_timestamp "$FIXTURE_DIR/valid.torrent" "2026-01-01"
assert_ok "is_valid_timestamp: torrent newer than reference is valid" \
    is_valid_timestamp "$FIXTURE_DIR/valid.torrent" "2025-06-01"
assert_fail "is_valid_timestamp: torrent older than reference is stale" \
    is_valid_timestamp "$FIXTURE_DIR/valid.torrent" "2026-06-01"

# =============================================================================
# _monthly_target
# =============================================================================
expected_ym="$(date -d "$(date +%Y-%m-01) -1 month" +%Y-%m)"
read -r m_year m_month m_ru <<< "$(_monthly_target)"
assert_eq "_monthly_target computes previous month" \
    "$expected_ym" "$m_year-$m_month"
assert_ok "_monthly_target returns a Russian month name" \
    test -n "$m_ru"

# =============================================================================
# _extract_torrent_link
# =============================================================================
assert_eq "_extract_torrent_link handles dl.php?id=" \
    "https://example.invalid/dl.php?id=12345" \
    "$(_extract_torrent_link '<a href="./dl.php?id=12345" class="dl-link">Скачать</a>')"
assert_eq "_extract_torrent_link handles dl.php?t=" \
    "https://example.invalid/dl.php?t=999" \
    "$(_extract_torrent_link '<a href="dl.php?t=999">Скачать</a>')"

# Realistic booktracker.org topic page: helper attachments + the torrent anchor.
REAL_TOPIC_HTML='<a href="./download.php?id=111788" ><b>metagenres.zip</b></a>
<a href="download.php?id=113872" class="">
<p><img src="images/icon_dn.gif" alt="" border="0" /></p><p><b>Скачать .torrent</b></p></a>'
assert_eq "_extract_torrent_link picks the torrent anchor on a real page" \
    "https://example.invalid/download.php?id=113872" \
    "$(_extract_torrent_link "$REAL_TOPIC_HTML")"

assert_fail "_extract_torrent_link fails when no link present" \
    _extract_torrent_link '<html>no links here</html>'

# =============================================================================
# get_forumid / get_topicid (with a mocked _http_get)
# =============================================================================
FAKE_INDEX_HTML='<span class="sf_title"><a href="./viewforum.php?f=256">Полные сборки библиотеки Флибуста</a></span>
<a href="./viewforum.php?f=253">Ежедневные обновления (Флибуста)</a>
<a href="./viewforum.php?f=255">Ежемесячные архивы (Флибуста)</a>
<a href="./viewforum.php?f=254">Еженедельные архивы (Флибуста)</a>'

FAKE_FORUM_HTML='<a href="./viewtopic.php?t=104183" class="torTopic"><b>Флибуста (Flibusta) & Либрусек (lib.rus.ec)<wbr> 7z + FLibrary + inpx (2009-2026) [FB2+EPUB] на 01.08.2026 [локальная коллекция, ежемесячно пополняемая]</b></a>
<a href="./viewtopic.php?t=104536" class="torTopic"><b>Дополнительн<wbr>ые данные библиотеки Flibusta [FB2] для FLibrary, 01.08.2026</b></a>
<a href="viewtopic.php?t=73862">Дампы базы данных библиотеки Флибуста по состоянию на 01.08.2026</a>
<a href="./viewtopic.php?t=105053" class="torTopic"><b>Архив книг за июль 2026 года (FB2, 879582-88339<wbr>4)</b></a>
<a href="./viewtopic.php?t=105052" class="torTopic"><b>Архив книг за июль 2026 года [не-FB2, 123-456]</b></a>'

_http_get() {
    case "$1" in
        *index.php) printf '%s' "$FAKE_INDEX_HTML" ;;
        *)          printf '%s' "$FAKE_FORUM_HTML" ;;
    esac
}

assert_eq "get_forumid resolves the full-collections forum by title" \
    "256" \
    "$(get_forumid 'Полные сборки библиотеки Флибуста')"
assert_eq "get_forumid resolves the monthly forum by title" \
    "255" \
    "$(get_forumid 'Ежемесячные архивы (Флибуста)')"
assert_fail "get_forumid fails when no forum matches" \
    get_forumid 'Несуществующий раздел'

assert_eq "get_topicid finds the INPX (full) topic by title" \
    "104183" \
    "$(get_topicid 256 'inpx')"
assert_eq "get_topicid finds the INPX (FB2 only) topic by title" \
    "104536" \
    "$(get_topicid 256 'Дополнительные данные')"
assert_eq "get_topicid finds the dump topic (no torTopic class) by title" \
    "73862" \
    "$(get_topicid 256 'Дампы базы данных библиотеки Флибуста')"
assert_eq "get_topicid finds the FB2 monthly topic by title" \
    "105053" \
    "$(get_topicid 255 'Архив книг за июль 2026 года (FB2,')"
assert_eq "get_topicid finds the non-FB2 monthly topic by title" \
    "105052" \
    "$(get_topicid 255 'Архив книг за июль 2026 года [не-FB2,')"
assert_fail "get_topicid fails when nothing matches" \
    get_topicid 255 'Ничего подобного'

# =============================================================================
# Logging levels
# =============================================================================
assert_eq "log suppresses info at error level" \
    "" \
    "$(LOG_LEVEL=error log_info 'hidden message' 2>&1)"
assert_eq "log emits error at info level" \
    "1" \
    "$(LOG_LEVEL=info log_error 'boom' 2>&1 | grep -c 'boom')"

# =============================================================================
# Naming & retention
# =============================================================================
assert_eq "_torrent_name builds a meaningful name" \
    "flibusta-inpx-fb2-2026-08-01.torrent" \
    "$(_torrent_name 'inpx-fb2' '2026-08-01')"

make_valid_torrent "$REF_EPOCH" > "$FIXTURE_DIR/dated.torrent"
assert_eq "_torrent_stamp derives YYYY-MM-DD from creation date" \
    "2026-01-01" \
    "$(_torrent_stamp "$FIXTURE_DIR/dated.torrent")"

RET_DIR="$TMPDIR_TEST/ret"
ARCH_DIR="$TMPDIR_TEST/arch"
mkdir -p "$RET_DIR" "$ARCH_DIR"

TORRENT_NAME_PREFIX=flibusta
ARCHIVE_DIR="$ARCH_DIR"

# Archive mode (default): superseded file is moved, the new file stays.
ARCHIVE_TORRENTS=1
touch "$RET_DIR/flibusta-dump-2026-07-01.torrent"
touch "$RET_DIR/flibusta-dump-2026-08-01.torrent"
_retire_superseded "dump" "$RET_DIR/flibusta-dump-2026-08-01.torrent" 2>/dev/null
assert_ok "retire archives the superseded torrent" \
    test -f "$ARCH_DIR/flibusta-dump-2026-07-01.torrent"
assert_ok "retire keeps the new torrent" \
    test -f "$RET_DIR/flibusta-dump-2026-08-01.torrent"
assert_fail "retire removes the superseded torrent from the active dir" \
    test -f "$RET_DIR/flibusta-dump-2026-07-01.torrent"

# Delete mode: superseded file is removed outright.
ARCHIVE_TORRENTS=0
touch "$RET_DIR/flibusta-inpx-fb2-2026-07-01.torrent"
touch "$RET_DIR/flibusta-inpx-fb2-2026-08-01.torrent"
_retire_superseded "inpx-fb2" "$RET_DIR/flibusta-inpx-fb2-2026-08-01.torrent" 2>/dev/null
assert_fail "retire deletes superseded when ARCHIVE_TORRENTS=0" \
    test -f "$RET_DIR/flibusta-inpx-fb2-2026-07-01.torrent"
assert_ok "retire (delete mode) keeps the new torrent" \
    test -f "$RET_DIR/flibusta-inpx-fb2-2026-08-01.torrent"

# Other types must not be touched.
touch "$RET_DIR/flibusta-monthly-fb2-2026-07.torrent"
_retire_superseded "dump" "$RET_DIR/flibusta-dump-2026-08-01.torrent" 2>/dev/null
assert_ok "retire leaves other types untouched" \
    test -f "$RET_DIR/flibusta-monthly-fb2-2026-07.torrent"

# Pruning by age.
PRUNE_DIR="$TMPDIR_TEST/prune"
mkdir -p "$PRUNE_DIR"
touch "$PRUNE_DIR/old.torrent"
touch -d '100 days ago' "$PRUNE_DIR/old.torrent"
touch "$PRUNE_DIR/new.torrent"
_prune_dir "$PRUNE_DIR" 30 2>/dev/null
assert_fail "prune removes files older than N days" \
    test -f "$PRUNE_DIR/old.torrent"
assert_ok "prune keeps recent files" \
    test -f "$PRUNE_DIR/new.torrent"

# Download state file.
STATE_FILE="$TMPDIR_TEST/state.tsv"
_record_download "inpx-fb2" "67944" "2026-08-01" "https://example.invalid/dl?id=1" \
    "flibusta-inpx-fb2-2026-08-01.torrent" 2>/dev/null
assert_eq "record writes a header row" \
    "downloaded_at" "$(head -1 "$STATE_FILE" | cut -f1)"
row="$(tail -1 "$STATE_FILE")"
assert_eq "record writes the type" \
    "inpx-fb2" "$(printf '%s' "$row" | cut -f2)"
assert_eq "record writes the topic" \
    "67944" "$(printf '%s' "$row" | cut -f3)"
assert_eq "record writes the stamp" \
    "2026-08-01" "$(printf '%s' "$row" | cut -f4)"
assert_eq "record writes the url" \
    "https://example.invalid/dl?id=1" "$(printf '%s' "$row" | cut -f5)"
assert_eq "record writes the filename" \
    "flibusta-inpx-fb2-2026-08-01.torrent" "$(printf '%s' "$row" | cut -f6)"

# _already_downloaded (skip logic).
assert_ok "_already_downloaded matches type+url" \
    _already_downloaded "inpx-fb2" "https://example.invalid/dl?id=1"
assert_fail "_already_downloaded rejects a different url" \
    _already_downloaded "inpx-fb2" "https://example.invalid/dl?id=2"
assert_fail "_already_downloaded rejects a different type" \
    _already_downloaded "dump" "https://example.invalid/dl?id=1"

STATE_FILE="$TMPDIR_TEST/nonexistent.tsv"
assert_fail "_already_downloaded returns false without a state file" \
    _already_downloaded "inpx-fb2" "https://example.invalid/dl?id=1"

# =============================================================================
# login (fails fast without credentials, no network)
# =============================================================================
assert_fail "login fails without credentials" login

# =============================================================================
# all (orchestration)
# =============================================================================
_call_count=0
get_inpx_fb2()   { _call_count=$((_call_count + 1)); return 0; }
get_inpx_all()   { _call_count=$((_call_count + 1)); return 0; }
get_dump()       { _call_count=$((_call_count + 1)); return 1; }  # simulate one failure
get_monthly_fb2(){ _call_count=$((_call_count + 1)); return 0; }
get_monthly_usr(){ _call_count=$((_call_count + 1)); return 0; }
all 2>/dev/null
all_rc=$?
assert_eq "all invokes all five targets" "5" "$_call_count"
assert_eq "all returns non-zero when any target fails" "1" "$all_rc"

# =============================================================================
# CLI argument parsing (bin/booktracker-import.sh)
# =============================================================================
make_valid_torrent "$REF_EPOCH" > "$FIXTURE_DIR/cli.torrent"

cli_rc="$(bash "$PROJECT_ROOT/bin/booktracker-import.sh" check "$FIXTURE_DIR/cli.torrent" -f >/dev/null 2>&1; echo $?)"
assert_eq "CLI: -f after 'check' is a flag, not a date" "0" "$cli_rc"

cli_rc="$(bash "$PROJECT_ROOT/bin/booktracker-import.sh" check -f "$FIXTURE_DIR/cli.torrent" >/dev/null 2>&1; echo $?)"
assert_eq "CLI: -f before 'check' still works" "0" "$cli_rc"

# =============================================================================
# Staging (booktracker-stage_functions.sh)
# =============================================================================
assert_eq "stage_type_from_name parses dump" \
    "dump" \
    "$(stage_type_from_name 'flibusta-dump-2026-08-01.torrent')"
assert_eq "stage_type_from_name parses inpx-fb2" \
    "inpx-fb2" \
    "$(stage_type_from_name 'flibusta-inpx-fb2-2026-08-01.torrent')"
assert_eq "stage_type_from_name parses inpx-all" \
    "inpx-all" \
    "$(stage_type_from_name 'flibusta-inpx-all-2026-08-01.torrent')"
assert_eq "stage_type_from_name parses monthly-fb2" \
    "monthly-fb2" \
    "$(stage_type_from_name 'flibusta-monthly-fb2-2026-07.torrent')"
assert_eq "stage_type_from_name parses monthly-usr" \
    "monthly-usr" \
    "$(stage_type_from_name 'flibusta-monthly-usr-2026-07.torrent')"
assert_fail "stage_type_from_name rejects an unknown type" \
    stage_type_from_name 'flibusta-foo-2026-08-01.torrent'

assert_eq "stage_destination maps inpx-fb2" "inpx" "$(stage_destination inpx-fb2)"
assert_eq "stage_destination maps inpx-all" "inpx" "$(stage_destination inpx-all)"
assert_eq "stage_destination maps dump" "flibusta_gz" "$(stage_destination dump)"
assert_eq "stage_destination maps monthly-fb2" "Latest" "$(stage_destination monthly-fb2)"
assert_eq "stage_destination maps monthly-usr" "Latest" "$(stage_destination monthly-usr)"
assert_fail "stage_destination rejects an unknown type" stage_destination foo

# Dump file list — mirrors the real FlibustaSQL torrent inspected 2026-08-14.
ARIA2_DUMP_FILES='Files:
idx|path/length
===+===========================================================================
  1|lib.a.annotations.sql.gz
  2|lib.a.annotations_pics.sql.gz
  3|lib.a.attached.zip
  4|lib.b.annotations.sql.gz
  5|lib.b.annotations_pics.sql.gz
  6|lib.b.attached.zip
  7|lib.libavtor.sql.gz
  8|lib.libavtorname.sql.gz
  9|lib.libbook.sql.gz
 10|lib.libfilename.sql.gz
 11|lib.libgenre.sql.gz
 12|lib.libgenrelist.sql.gz
 13|lib.libjoinedbooks.sql.gz
 14|lib.librate.sql.gz
 15|lib.librecs.sql.gz
 16|lib.libseq.sql.gz
 17|lib.libseqname.sql.gz
 18|lib.libtranslator.sql.gz
 19|lib.md5.txt.gz
 20|lib.reviews.sql.gz'

assert_eq "stage_select_indexes (dump) selects only allowed files" \
    "7,8,9,10,11,12,13,14,15,16,17,18" \
    "$(stage_select_indexes dump <<< "$ARIA2_DUMP_FILES")"

assert_ok "stage_is_allowed (dump) allows lib.libbook.sql.gz" \
    stage_is_allowed dump "lib.libbook.sql.gz"
assert_fail "stage_is_allowed (dump) rejects lib.md5.txt.gz" \
    stage_is_allowed dump "lib.md5.txt.gz"
assert_fail "stage_is_allowed (dump) rejects a .zip archive" \
    stage_is_allowed dump "lib.a.attached.zip"

ARIA2_INPX_FILES='Files:
idx|path/length
===+===========
  1|lib.inpx
  2|books.fb2.7z
  3|books.epub.7z'

assert_eq "stage_select_indexes (inpx-fb2) selects only *.inpx" \
    "1" \
    "$(stage_select_indexes inpx-fb2 <<< "$ARIA2_INPX_FILES")"
assert_eq "stage_select_indexes (inpx-all) selects only *.inpx" \
    "1" \
    "$(stage_select_indexes inpx-all <<< "$ARIA2_INPX_FILES")"
assert_ok "stage_is_allowed (inpx-fb2) allows .inpx" \
    stage_is_allowed inpx-fb2 "lib.inpx"
assert_fail "stage_is_allowed (inpx-fb2) rejects .7z" \
    stage_is_allowed inpx-fb2 "books.7z"
assert_eq "stage_select_indexes (full) selects nothing (download all)" \
    "" \
    "$(stage_select_indexes monthly-fb2 <<< "$ARIA2_INPX_FILES")"

# stage_download_files returns the download set as idx|path lines.
assert_eq "stage_download_files (dump) lists only allowed files" \
    "7|lib.libavtor.sql.gz
8|lib.libavtorname.sql.gz
9|lib.libbook.sql.gz
10|lib.libfilename.sql.gz
11|lib.libgenre.sql.gz
12|lib.libgenrelist.sql.gz
13|lib.libjoinedbooks.sql.gz
14|lib.librate.sql.gz
15|lib.librecs.sql.gz
16|lib.libseq.sql.gz
17|lib.libseqname.sql.gz
18|lib.libtranslator.sql.gz" \
    "$(stage_download_files dump <<< "$ARIA2_DUMP_FILES")"
assert_eq "stage_download_files (inpx-fb2) lists only the .inpx" \
    "1|lib.inpx" \
    "$(stage_download_files inpx-fb2 <<< "$ARIA2_INPX_FILES")"
assert_eq "stage_download_files (full) lists every file" \
    "1|lib.inpx
2|books.fb2.7z
3|books.epub.7z" \
    "$(stage_download_files monthly-fb2 <<< "$ARIA2_INPX_FILES")"

# stage_sql_destination + size helpers.
assert_eq "stage_sql_destination returns the decompress folder" \
    "flibusta" \
    "$(stage_sql_destination)"

ARIA2_SIZED_FILES='Files:
idx|path/length
===+===========
  1|./lib.inpx
   |100B (100)
  2|./books.fb2.7z
   |300B (300)
  3|./books.epub.7z
   |5.0KiB (5,120)'

assert_eq "stage_total_size (inpx-fb2) sums only allowed files" \
    "100" \
    "$(stage_total_size inpx-fb2 <<< "$ARIA2_SIZED_FILES")"
assert_eq "stage_total_size (full) sums every file" \
    "5520" \
    "$(stage_total_size monthly-fb2 <<< "$ARIA2_SIZED_FILES")"
assert_eq "stage_total_size uses exact parenthesized bytes" \
    "96397659" \
    "$(stage_total_size inpx-fb2 <<< 'idx|path/length
===+===========
  1|./lib.inpx
   |91MiB (96,397,659)')"
assert_eq "stage_bytes_from_human converts bytes" \
    "100" \
    "$(stage_bytes_from_human '100B')"
assert_eq "stage_bytes_from_human converts KiB" \
    "5120" \
    "$(stage_bytes_from_human '5.0KiB')"
assert_eq "stage_bytes_from_human converts MiB" \
    "1048576" \
    "$(stage_bytes_from_human '1.0MiB')"
assert_eq "stage_bytes_from_human converts GiB" \
    "1073741824" \
    "$(stage_bytes_from_human '1.0GiB')"
assert_eq "stage_bytes_from_human returns 0 for junk" \
    "0" \
    "$(stage_bytes_from_human 'nope')"
assert_eq "stage_human_size formats bytes" \
    "1.0KiB" \
    "$(stage_human_size 1024)"
assert_eq "stage_human_size formats a large value" \
    "129.5MiB" \
    "$(stage_human_size 135805014)"

# Staging state file (skip logic).
STAGED_STATE_FILE="$TMPDIR_TEST/staged.tsv"
stage_record dump "flibusta-dump-2026-08-01.torrent" "2026-08-01" \
    "flibusta_gz" "lib.libbook.sql,lib.libavtor.sql" 2>/dev/null
assert_ok "stage_is_done finds a recorded torrent" \
    stage_is_done "flibusta-dump-2026-08-01.torrent" "$STAGED_STATE_FILE"
assert_fail "stage_is_done misses an unrecorded torrent" \
    stage_is_done "flibusta-inpx-fb2-2026-08-01.torrent" "$STAGED_STATE_FILE"
assert_fail "stage_is_done returns false without a state file" \
    stage_is_done "flibusta-dump-2026-08-01.torrent" "$TMPDIR_TEST/nonexistent-staged.tsv"

# =============================================================================
# Staging CLI (bin/booktracker-stage.sh)
# =============================================================================
stage_rc="$(bash "$PROJECT_ROOT/bin/booktracker-stage.sh" --help >/dev/null 2>&1; echo $?)"
assert_eq "stage: --help exits 0" "0" "$stage_rc"

stage_rc="$(env -u STAGING_DIR BOOKTRACKER_NO_ENV=1 bash "$PROJECT_ROOT/bin/booktracker-stage.sh" >/dev/null 2>&1; echo $?)"
assert_eq "stage: missing STAGING_DIR exits non-zero" "2" "$stage_rc"

stage_rc="$(STAGING_DIR=/tmp bash "$PROJECT_ROOT/bin/booktracker-stage.sh" --bogus >/dev/null 2>&1; echo $?)"
assert_eq "stage: unknown option exits non-zero" "2" "$stage_rc"

# Mock aria2c: --show-files lists files (with sizes) per torrent type; download
# "creates" the selected files via --index-out.  A mock gzip decompresses.
MOCK_BIN="$TMPDIR_TEST/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/aria2c" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    --show-files)
        case "$2" in
            *dump*)
                printf 'Files:\nidx|path/length\n===+===========\n  1|lib.libbook.sql.gz\n   |100B (100)\n  2|lib.a.attached.zip\n   |999B (999)\n'
                ;;
            *)
                printf 'Files:\nidx|path/length\n===+===========\n  1|lib.inpx\n   |121KiB (123,904)\n  2|books.7z\n   |639KiB (654,336)\n'
                ;;
        esac
        ;;
    *)
        dir=""
        declare -a outs=()
        for a in "$@"; do
            case "$a" in
                --dir=*) dir="${a#--dir=}" ;;
                --index-out=*)
                    spec="${a#--index-out=}"
                    outs+=("${spec#*=}")
                    ;;
            esac
        done
        mkdir -p "$dir"
        for name in "${outs[@]}"; do
            if [[ "$name" == *.gz ]]; then
                printf 'gzip-data' > "$dir/$name"
            else
                printf 'inpx-data' > "$dir/$name"
            fi
        done
        ;;
esac
exit 0
EOF
chmod +x "$MOCK_BIN/aria2c"

cat > "$MOCK_BIN/gzip" <<'EOF'
#!/usr/bin/env bash
# Mock decompressor: `-dc <file>` prints fixed decompressed content to stdout.
printf 'sql-data'
exit 0
EOF
chmod +x "$MOCK_BIN/gzip"

STAGE_DIR_TEST="$TMPDIR_TEST/staging"
STAGE_ENV=(PATH="$MOCK_BIN:$PATH" STAGING_DIR="$STAGE_DIR_TEST" \
    BOOKTRACKER_NO_ENV=1 \
    STAGED_STATE_FILE="$TMPDIR_TEST/staged-cli.tsv" \
    TORRENT_DIR="$TMPDIR_TEST/torrents" ARCHIVE_DIR="$TMPDIR_TEST/stage-archive")

# Dry run: builds the aria2c command with per-file selection.
touch "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent"
stage_out="$(env "${STAGE_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-stage.sh" -n "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent" 2>&1)"
stage_rc=$?
assert_eq "stage: dry-run exits 0" "0" "$stage_rc"
assert_eq "stage: dry-run builds an aria2c command" "1" \
    "$(printf '%s' "$stage_out" | grep -c 'aria2c')"
assert_eq "stage: dry-run selects only .inpx" "1" \
    "$(printf '%s' "$stage_out" | grep -c -- '--select-file=1')"
assert_eq "stage: dry-run pins the .inpx to its basename" "1" \
    "$(printf '%s' "$stage_out" | grep -c -- '--index-out=1=lib.inpx')"
assert_eq "stage: dry-run shows the staged file name" "1" \
    "$(printf '%s' "$stage_out" | grep -c 'files=lib.inpx')"
assert_eq "stage: dry-run shows the total download size" "1" \
    "$(printf '%s' "$stage_out" | grep -c 'total')"
assert_eq "stage: dry-run enables DHT" "1" \
    "$(printf '%s' "$stage_out" | grep -c -- '--enable-dht=true')"
assert_eq "stage: dry-run enables peer exchange" "1" \
    "$(printf '%s' "$stage_out" | grep -c -- '--enable-peer-exchange=true')"
assert_eq "stage: dry-run announces fallback trackers" "1" \
    "$(printf '%s' "$stage_out" | grep -c -- '--bt-tracker=')"
assert_fail "stage: dry-run does not create the staging directory" \
    test -e "$STAGE_DIR_TEST"

# Full run: download directly into staging -> record, all via the mock.
rm -f "$TMPDIR_TEST/staged-cli.tsv"
touch "$TMPDIR_TEST/flibusta-inpx-fb2-2026-08-01.torrent"
stage_out2="$(env "${STAGE_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-stage.sh" "$TMPDIR_TEST/flibusta-inpx-fb2-2026-08-01.torrent" 2>&1)"
stage_rc2=$?
assert_eq "stage: full run exits 0" "0" "$stage_rc2"
assert_ok "stage: .inpx downloaded directly into STAGING/inpx" \
    test -f "$STAGE_DIR_TEST/inpx/lib.inpx"
assert_eq "stage: staged file has the mock content" "inpx-data" \
    "$(cat "$STAGE_DIR_TEST/inpx/lib.inpx")"
assert_fail "stage: no intermediate work/archive directory is created" \
    test -e "$TMPDIR_TEST/stage-archive"
assert_ok "stage: torrent recorded in staged state" \
    grep -q "flibusta-inpx-fb2-2026-08-01.torrent" "$TMPDIR_TEST/staged-cli.tsv"

# Dump: .gz downloads into flibusta_gz/ and decompresses into the sibling
# flibusta/ folder (keeping the raw .gz).
rm -f "$TMPDIR_TEST/staged-cli.tsv"
touch "$TMPDIR_TEST/flibusta-dump-2026-08-01.torrent"
stage_out4="$(env "${STAGE_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-stage.sh" "$TMPDIR_TEST/flibusta-dump-2026-08-01.torrent" 2>&1)"
stage_rc4=$?
assert_eq "stage: dump run exits 0" "0" "$stage_rc4"
assert_ok "stage: dump .gz downloaded into flibusta_gz" \
    test -f "$STAGE_DIR_TEST/flibusta_gz/lib.libbook.sql.gz"
assert_ok "stage: dump .sql decompressed into flibusta" \
    test -f "$STAGE_DIR_TEST/flibusta/lib.libbook.sql"
assert_eq "stage: dump .sql has decompressed content" "sql-data" \
    "$(cat "$STAGE_DIR_TEST/flibusta/lib.libbook.sql")"
assert_ok "stage: dump torrent recorded" \
    grep -q "flibusta-dump-2026-08-01.torrent" "$TMPDIR_TEST/staged-cli.tsv"

# --resume-only: skip a torrent whose output file already exists (unrecorded).
touch "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent"
stage_out5="$(env "${STAGE_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-stage.sh" --resume-only "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent" 2>&1)"
stage_rc5=$?
assert_eq "stage: --resume-only skips an already-present torrent" "0" "$stage_rc5"
assert_eq "stage: --resume-only logs the skip" "1" \
    "$(printf '%s' "$stage_out5" | grep -c 'already present')"

# --- Summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
