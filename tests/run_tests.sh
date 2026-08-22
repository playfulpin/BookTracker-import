#!/usr/bin/env bash
# =============================================================================
# booktracker-import — test suite
#
# Exercises the pure (network-free) functions of booktracker-import and
# booktracker-extract, plus the CLI argument parsing of both scripts. Run with:
#     bash tests/run_tests.sh
#
# Version:  0.1.4
# Updated:  2026-08-22 11:32 CDT
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
source "$PROJECT_ROOT/lib/booktracker-extract_functions.sh"
source "$PROJECT_ROOT/lib/booktracker-ingest_functions.sh"

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

FAKE_FORUM_HTML='<a href="./viewtopic.php?t=46979" class="torTopic"><b>Библиотека Flibusta (только FB2) на 01.08.2026 (702461 книга) (локальная коллекция, пополняемая ежемесячно) + MyHomeLib + inpx</b></a>
<a href="./viewtopic.php?t=64690" class="torTopic"><b>inpx для библиотеки Flibusta &quot;расшире<wbr>нный&quot; (сортированн<wbr>ый список) (01.08.2026)</b></a>
<a href="viewtopic.php?t=27203">Inpx для библиотеки Flibusta.Net (только FB2) по состоянию на 1.04.2014</a>
<a href="./viewtopic.php?t=104536" class="torTopic"><b>Дополнительн<wbr>ые данные библиотеки Flibusta [FB2] для FLibrary, 01.08.2026</b></a>
<a href="./viewtopic.php?t=104183" class="torTopic"><b>Флибуста (Flibusta) & Либрусек (lib.rus.ec)<wbr> 7z + FLibrary + inpx (2009-2026) [FB2+EPUB] на 01.08.2026 [локальная коллекция, ежемесячно пополняемая]</b></a>
<a href="viewtopic.php?t=73862">Дампы базы данных библиотеки Флибуста по состоянию на 01.08.2026</a>
<a href="./viewtopic.php?t=67944" class="torTopic"><b>INPX для библиотеки Flibusta (только FB2) по состоянию на 01.08.2026</b></a>
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

assert_eq "get_topicid finds the extended INPX topic by title" \
    "64690" \
    "$(get_topicid 256 'расширенный')"
assert_eq "get_topicid finds the FB2-only INPX topic by title" \
    "67944" \
    "$(get_topicid 256 'INPX для библиотеки Flibusta (только FB2)')"
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
_archive_superseded "dump" "$RET_DIR/flibusta-dump-2026-08-01.torrent" 2>/dev/null
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
_archive_superseded "inpx-fb2" "$RET_DIR/flibusta-inpx-fb2-2026-08-01.torrent" 2>/dev/null
assert_fail "retire deletes superseded when ARCHIVE_TORRENTS=0" \
    test -f "$RET_DIR/flibusta-inpx-fb2-2026-07-01.torrent"
assert_ok "retire (delete mode) keeps the new torrent" \
    test -f "$RET_DIR/flibusta-inpx-fb2-2026-08-01.torrent"

# Other types must not be touched.
touch "$RET_DIR/flibusta-monthly-fb2-2026-07.torrent"
_archive_superseded "dump" "$RET_DIR/flibusta-dump-2026-08-01.torrent" 2>/dev/null
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
# Extraction (booktracker-extract_functions.sh)
# =============================================================================
assert_eq "extract_type_from_name parses dump" \
    "dump" \
    "$(extract_type_from_name 'flibusta-dump-2026-08-01.torrent')"
assert_eq "extract_type_from_name parses inpx-fb2" \
    "inpx-fb2" \
    "$(extract_type_from_name 'flibusta-inpx-fb2-2026-08-01.torrent')"
assert_eq "extract_type_from_name parses inpx-all" \
    "inpx-all" \
    "$(extract_type_from_name 'flibusta-inpx-all-2026-08-01.torrent')"
assert_eq "extract_type_from_name parses monthly-fb2" \
    "monthly-fb2" \
    "$(extract_type_from_name 'flibusta-monthly-fb2-2026-07.torrent')"
assert_eq "extract_type_from_name parses monthly-usr" \
    "monthly-usr" \
    "$(extract_type_from_name 'flibusta-monthly-usr-2026-07.torrent')"
assert_fail "extract_type_from_name rejects an unknown type" \
    extract_type_from_name 'flibusta-foo-2026-08-01.torrent'

assert_eq "extract_destination maps inpx-fb2" "inpx" "$(extract_destination inpx-fb2)"
assert_eq "extract_destination maps inpx-all" "inpx" "$(extract_destination inpx-all)"
assert_eq "extract_destination maps dump" "FlibustaSQL" "$(extract_destination dump)"
assert_eq "extract_destination maps monthly-fb2" "book_archives" "$(extract_destination monthly-fb2)"
assert_eq "extract_destination maps monthly-usr" "book_archives" "$(extract_destination monthly-usr)"
assert_fail "extract_destination rejects an unknown type" extract_destination foo

# Output basename rules (inpx-fb2 uses a canonical local name).
FB2_INPX_NAME="$(extract_inpx_fb2_output_name)"
assert_ok "extract_inpx_fb2_output_name returns a canonical name" \
    test -n "$FB2_INPX_NAME"
assert_eq "extract_inpx_fb2_output_name matches the expected pattern" \
    "1" \
    "$(printf '%s' "$FB2_INPX_NAME" | grep -cE '^flibusta_fb2_local-[0-9]{4}-[0-9]{2}-01_original\.inpx$')"
assert_eq "extract_output_basename (inpx-fb2) uses the canonical name" \
    "$FB2_INPX_NAME" \
    "$(extract_output_basename inpx-fb2 'fb2.Flibusta.Net.inpx')"
assert_eq "extract_output_basename (dump) keeps the torrent basename" \
    "lib.libbook.sql.gz" \
    "$(extract_output_basename dump './lib.libbook.sql.gz')"
assert_eq "extract_output_basename (inpx-all) keeps the torrent basename" \
    "lib.inpx" \
    "$(extract_output_basename inpx-all 'lib.inpx')"
assert_eq "extract_output_basename (monthly) keeps the torrent basename" \
    "books.fb2.7z" \
    "$(extract_output_basename monthly-fb2 './books.fb2.7z')"

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

assert_eq "extract_select_indexes (dump) selects only allowed files" \
    "7,8,9,10,11,12,13,14,15,16,17,18" \
    "$(extract_select_indexes dump <<< "$ARIA2_DUMP_FILES")"

assert_ok "extract_is_allowed (dump) allows lib.libbook.sql.gz" \
    extract_is_allowed dump "lib.libbook.sql.gz"
assert_fail "extract_is_allowed (dump) rejects lib.md5.txt.gz" \
    extract_is_allowed dump "lib.md5.txt.gz"
assert_fail "extract_is_allowed (dump) rejects a .zip archive" \
    extract_is_allowed dump "lib.a.attached.zip"

ARIA2_INPX_FILES='Files:
idx|path/length
===+===========
  1|lib.inpx
  2|books.fb2.7z
  3|books.epub.7z'

assert_eq "extract_select_indexes (inpx-fb2) selects only *.inpx" \
    "1" \
    "$(extract_select_indexes inpx-fb2 <<< "$ARIA2_INPX_FILES")"
assert_eq "extract_select_indexes (inpx-all) selects only *.inpx" \
    "1" \
    "$(extract_select_indexes inpx-all <<< "$ARIA2_INPX_FILES")"
assert_ok "extract_is_allowed (inpx-fb2) allows .inpx" \
    extract_is_allowed inpx-fb2 "lib.inpx"
assert_fail "extract_is_allowed (inpx-fb2) rejects .7z" \
    extract_is_allowed inpx-fb2 "books.7z"
assert_eq "extract_select_indexes (full) selects nothing (download all)" \
    "" \
    "$(extract_select_indexes monthly-fb2 <<< "$ARIA2_INPX_FILES")"

# extract_download_files returns the download set as idx|path lines.
assert_eq "extract_download_files (dump) lists only allowed files" \
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
    "$(extract_download_files dump <<< "$ARIA2_DUMP_FILES")"
assert_eq "extract_download_files (inpx-fb2) lists only the .inpx" \
    "1|lib.inpx" \
    "$(extract_download_files inpx-fb2 <<< "$ARIA2_INPX_FILES")"
assert_eq "extract_download_files (full) lists every file" \
    "1|lib.inpx
2|books.fb2.7z
3|books.epub.7z" \
    "$(extract_download_files monthly-fb2 <<< "$ARIA2_INPX_FILES")"

# extract_sql_destination + size helpers.
assert_eq "extract_sql_destination returns the decompress folder" \
    "mysql_feeds" \
    "$(extract_sql_destination)"

# extract_torrent_name + extract_stale_dir (stale-folder safeguard).
assert_eq "extract_torrent_name extracts the torrent Name" \
    "FlibustaSQL" \
    "$(extract_torrent_name <<< $'Files:\nName: FlibustaSQL\nidx|path/length')"
assert_eq "extract_torrent_name returns nothing when Name is absent" \
    "" \
    "$(extract_torrent_name <<< $'Files:\nidx|path/length')"
assert_eq "extract_torrent_name trims trailing whitespace and CR" \
    "FlibustaSQL" \
    "$(extract_torrent_name <<< $'Name: FlibustaSQL  \r')"

mkdir -p "$TMPDIR_TEST/stdir/FlibustaSQL"
assert_eq "extract_stale_dir finds a stale torrent-named dir" \
    "$TMPDIR_TEST/stdir/FlibustaSQL" \
    "$(extract_stale_dir "$TMPDIR_TEST/stdir" 'FlibustaSQL')"
assert_fail "extract_stale_dir misses an absent dir" \
    extract_stale_dir "$TMPDIR_TEST/stdir" 'Nope'
assert_fail "extract_stale_dir rejects a path-traversal name" \
    extract_stale_dir "$TMPDIR_TEST/stdir" '../etc'
assert_fail "extract_stale_dir rejects an empty name" \
    extract_stale_dir "$TMPDIR_TEST/stdir" ''

ARIA2_SIZED_FILES='Files:
idx|path/length
===+===========
  1|./lib.inpx
   |100B (100)
  2|./books.fb2.7z
   |300B (300)
  3|./books.epub.7z
   |5.0KiB (5,120)'

assert_eq "extract_total_size (inpx-fb2) sums only allowed files" \
    "100" \
    "$(extract_total_size inpx-fb2 <<< "$ARIA2_SIZED_FILES")"
assert_eq "extract_total_size (full) sums every file" \
    "5520" \
    "$(extract_total_size monthly-fb2 <<< "$ARIA2_SIZED_FILES")"
assert_eq "extract_total_size uses exact parenthesized bytes" \
    "96397659" \
    "$(extract_total_size inpx-fb2 <<< 'idx|path/length
===+===========
  1|./lib.inpx
   |91MiB (96,397,659)')"
assert_eq "extract_bytes_from_human converts bytes" \
    "100" \
    "$(extract_bytes_from_human '100B')"
assert_eq "extract_bytes_from_human converts KiB" \
    "5120" \
    "$(extract_bytes_from_human '5.0KiB')"
assert_eq "extract_bytes_from_human converts MiB" \
    "1048576" \
    "$(extract_bytes_from_human '1.0MiB')"
assert_eq "extract_bytes_from_human converts GiB" \
    "1073741824" \
    "$(extract_bytes_from_human '1.0GiB')"
assert_eq "extract_bytes_from_human returns 0 for junk" \
    "0" \
    "$(extract_bytes_from_human 'nope')"
assert_eq "extract_human_size formats bytes" \
    "1.0KiB" \
    "$(extract_human_size 1024)"
assert_eq "extract_human_size formats a large value" \
    "129.5MiB" \
    "$(extract_human_size 135805014)"

# Extract state file (skip logic).
STAGED_STATE_FILE="$TMPDIR_TEST/staged.tsv"
extract_record dump "flibusta-dump-2026-08-01.torrent" "2026-08-01" \
    "mysql_feeds" "lib.libbook.sql,lib.libavtor.sql" 2>/dev/null
assert_ok "extract_is_done finds a recorded torrent" \
    extract_is_done "flibusta-dump-2026-08-01.torrent" "$STAGED_STATE_FILE"
assert_fail "extract_is_done misses an unrecorded torrent" \
    extract_is_done "flibusta-inpx-fb2-2026-08-01.torrent" "$STAGED_STATE_FILE"
assert_fail "extract_is_done returns false without a state file" \
    extract_is_done "flibusta-dump-2026-08-01.torrent" "$TMPDIR_TEST/nonexistent-staged.tsv"

# =============================================================================
# Extraction CLI (bin/booktracker-extract.sh)
# =============================================================================
extract_rc="$(bash "$PROJECT_ROOT/bin/booktracker-extract.sh" --help >/dev/null 2>&1; echo $?)"
assert_eq "extract: --help exits 0" "0" "$extract_rc"

extract_rc="$(STAGING_DIR=relative/path BOOKTRACKER_NO_ENV=1 bash "$PROJECT_ROOT/bin/booktracker-extract.sh" >/dev/null 2>&1; echo $?)"
assert_eq "extract: relative STAGING_DIR exits non-zero" "2" "$extract_rc"

extract_rc="$(STAGING_DIR=/tmp bash "$PROJECT_ROOT/bin/booktracker-extract.sh" --bogus >/dev/null 2>&1; echo $?)"
assert_eq "extract: unknown option exits non-zero" "2" "$extract_rc"

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
                printf 'Files:\nName: FlibustaSQL\nidx|path/length\n===+===========\n  1|lib.libbook.sql.gz\n   |100B (100)\n  2|lib.a.attached.zip\n   |999B (999)\n'
                ;;
            *)
                printf 'Files:\nName: test\nidx|path/length\n===+===========\n  1|lib.inpx\n   |121KiB (123,904)\n  2|books.7z\n   |639KiB (654,336)\n'
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

EXTRACT_DIR_TEST="$TMPDIR_TEST/staging"
EXTRACT_ENV=(PATH="$MOCK_BIN:$PATH" STAGING_DIR="$EXTRACT_DIR_TEST" \
    BOOKTRACKER_NO_ENV=1 \
    STAGED_STATE_FILE="$TMPDIR_TEST/staged-cli.tsv" \
    TORRENT_DIR="$TMPDIR_TEST/torrents" ARCHIVE_DIR="$TMPDIR_TEST/extract-archive")

# Dry run: builds the aria2c command with per-file selection.
touch "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent"
extract_out="$(env "${EXTRACT_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-extract.sh" -n "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent" 2>&1)"
extract_rc=$?
assert_eq "extract: dry-run exits 0" "0" "$extract_rc"
assert_eq "extract: dry-run builds an aria2c command" "1" \
    "$(printf '%s' "$extract_out" | grep -c 'aria2c')"
assert_eq "extract: dry-run selects only .inpx" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--select-file=1')"
assert_eq "extract: dry-run pins the .inpx to its basename" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--index-out=1=lib.inpx')"
assert_eq "extract: dry-run shows the extracted file name" "1" \
    "$(printf '%s' "$extract_out" | grep -c 'files=lib.inpx')"
assert_eq "extract: dry-run shows the total download size" "1" \
    "$(printf '%s' "$extract_out" | grep -c 'total')"
assert_eq "extract: dry-run enables DHT" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--enable-dht=true')"
assert_eq "extract: dry-run enables peer exchange" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--enable-peer-exchange=true')"
assert_eq "extract: dry-run tunes peer limits" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--bt-max-peers=150')"
assert_eq "extract: dry-run tunes open-file limits" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--bt-max-open-files=200')"
assert_eq "extract: dry-run disables preallocation" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--file-allocation=none')"
assert_eq "extract: dry-run allows overwrite" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--allow-overwrite=true')"
assert_eq "extract: dry-run announces fallback trackers" "1" \
    "$(printf '%s' "$extract_out" | grep -c -- '--bt-tracker=')"
assert_eq "extract: dry-run omits peer-id-prefix by default" "0" \
    "$(printf '%s' "$extract_out" | grep -c -- '--peer-id-prefix=')"
assert_fail "extract: dry-run does not create the staging directory" \
    test -e "$EXTRACT_DIR_TEST"

# inpx-fb2 pins its download to the canonical local name.
touch "$TMPDIR_TEST/flibusta-inpx-fb2-2026-08-01.torrent"
extract_fb2_out="$(env "${EXTRACT_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-extract.sh" -n "$TMPDIR_TEST/flibusta-inpx-fb2-2026-08-01.torrent" 2>&1)"
assert_eq "extract: dry-run pins inpx-fb2 to the canonical name" "1" \
    "$(printf '%s' "$extract_fb2_out" | grep -c -- "--index-out=1=$FB2_INPX_NAME")"
assert_eq "extract: dry-run records the canonical inpx-fb2 name" "1" \
    "$(printf '%s' "$extract_fb2_out" | grep -c "files=$FB2_INPX_NAME")"

# Full run: download directly into staging -> record, all via the mock.
rm -f "$TMPDIR_TEST/staged-cli.tsv"
touch "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent"
extract_out2="$(env "${EXTRACT_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-extract.sh" "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent" 2>&1)"
extract_rc2=$?
assert_eq "extract: full run exits 0" "0" "$extract_rc2"
assert_ok "extract: .inpx downloaded directly into STAGING/inpx" \
    test -f "$EXTRACT_DIR_TEST/inpx/lib.inpx"
assert_eq "extract: extracted file has the mock content" "inpx-data" \
    "$(cat "$EXTRACT_DIR_TEST/inpx/lib.inpx")"
assert_ok "extract: torrent recorded in staged state" \
    grep -q "flibusta-inpx-all-2026-08-01.torrent" "$TMPDIR_TEST/staged-cli.tsv"
assert_eq "extract: records the date stamp (not the full filename)" \
    "2026-08-01" \
    "$(tail -1 "$TMPDIR_TEST/staged-cli.tsv" | cut -f4)"

# Dump: .gz downloads into FlibustaSQL/ and decompresses into the sibling
# mysql_feeds/ folder (keeping the raw .gz).  A stale torrent-named folder left by
# an older nested download is removed before download.
rm -f "$TMPDIR_TEST/staged-cli.tsv"
rm -rf "$EXTRACT_DIR_TEST/FlibustaSQL"
mkdir -p "$EXTRACT_DIR_TEST/FlibustaSQL/FlibustaSQL"
printf 'stale' > "$EXTRACT_DIR_TEST/FlibustaSQL/FlibustaSQL/stale.bin"
touch "$TMPDIR_TEST/flibusta-dump-2026-08-01.torrent"
extract_out4="$(env "${EXTRACT_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-extract.sh" "$TMPDIR_TEST/flibusta-dump-2026-08-01.torrent" 2>&1)"
extract_rc4=$?
assert_eq "extract: dump run exits 0" "0" "$extract_rc4"
assert_ok "extract: dump .gz downloaded into FlibustaSQL" \
    test -f "$EXTRACT_DIR_TEST/FlibustaSQL/lib.libbook.sql.gz"
assert_ok "extract: dump .sql decompressed into mysql_feeds" \
    test -f "$EXTRACT_DIR_TEST/mysql_feeds/lib.libbook.sql"
assert_eq "extract: dump .sql has decompressed content" "sql-data" \
    "$(cat "$EXTRACT_DIR_TEST/mysql_feeds/lib.libbook.sql")"
assert_ok "extract: dump torrent recorded" \
    grep -q "flibusta-dump-2026-08-01.torrent" "$TMPDIR_TEST/staged-cli.tsv"
assert_fail "extract: stale torrent-named dir is removed before download" \
    test -e "$EXTRACT_DIR_TEST/FlibustaSQL/FlibustaSQL"
assert_eq "extract: stale-dir removal is logged" "1" \
    "$(printf '%s' "$extract_out4" | grep -c 'stale torrent-named')"

# --resume-only: skip a torrent whose output file already exists (unrecorded).
rm -f "$TMPDIR_TEST/staged-cli.tsv"
touch "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent"
extract_out5="$(env "${EXTRACT_ENV[@]}" \
    bash "$PROJECT_ROOT/bin/booktracker-extract.sh" --resume-only "$TMPDIR_TEST/flibusta-inpx-all-2026-08-01.torrent" 2>&1)"
extract_rc5=$?
assert_eq "extract: --resume-only skips an already-present torrent" "0" "$extract_rc5"
assert_eq "extract: --resume-only logs the skip" "1" \
    "$(printf '%s' "$extract_out5" | grep -c 'already present')"

# =============================================================================
# Ingestion (booktracker-ingest_functions.sh + bin/booktracker-ingest.sh)
# =============================================================================
mkdir -p "$TMPDIR_TEST/ingest-list"
touch "$TMPDIR_TEST/ingest-list/lib.libbook.sql" "$TMPDIR_TEST/ingest-list/lib.libavtor.sql" \
    "$TMPDIR_TEST/ingest-list/readme.txt"
assert_eq "ingest_list_sql lists .sql files sorted" \
    "$TMPDIR_TEST/ingest-list/lib.libavtor.sql
$TMPDIR_TEST/ingest-list/lib.libbook.sql" \
    "$(ingest_list_sql "$TMPDIR_TEST/ingest-list")"
assert_fail "ingest_list_sql fails for a missing dir" \
    ingest_list_sql "$TMPDIR_TEST/no-such-ingest-dir"

printf -- '-- MySQL dump\nCREATE TABLE `libbook` (`BookId` int);\n' > "$TMPDIR_TEST/good.sql"
printf 'junk\n' > "$TMPDIR_TEST/bad.sql"
: > "$TMPDIR_TEST/empty.sql"
assert_ok "ingest_validate_sql accepts a dump" ingest_validate_sql "$TMPDIR_TEST/good.sql"
assert_fail "ingest_validate_sql rejects junk" ingest_validate_sql "$TMPDIR_TEST/bad.sql"
assert_fail "ingest_validate_sql rejects an empty file" ingest_validate_sql "$TMPDIR_TEST/empty.sql"

# BOM + CRLF normalization (bundled sql/ files are authored on Windows).
assert_eq "ingest: _ingest_normalize_sql strips a BOM and CRLF" \
    $'/* hi */;\nSELECT 1;' \
    "$(printf '\xEF\xBB\xBF/* hi */;\r\nSELECT 1;\r\n' | _ingest_normalize_sql)"

# Ingest state file.
INGEST_STATE_FILE="$TMPDIR_TEST/ingested.tsv"
MYSQL_DATABASE=flibusta
ingest_record "load" "ok" "2 files"
assert_eq "ingest_record writes a header row" \
    "ingested_at" "$(head -1 "$INGEST_STATE_FILE" | cut -f1)"
assert_ok "ingest_is_done finds a recorded stage" \
    ingest_is_done "load" "$INGEST_STATE_FILE"
assert_fail "ingest_is_done misses an unrecorded stage" \
    ingest_is_done "convert" "$INGEST_STATE_FILE"
assert_fail "ingest_is_done returns false without a state file" \
    ingest_is_done "load" "$TMPDIR_TEST/no-such-ingested.tsv"

# Mock mysql: records its argv (password never included) to $MOCK_MYSQL_LOG.
# When run with -e (a query, used by ingest_check / ingest_cleanup), it emits
# canned counts so ingest_check can verify a populated catalog.
cat > "$MOCK_BIN/mysql" <<'EOF'
#!/usr/bin/env bash
printf 'MYSQL %s\n' "$*" >> "${MOCK_MYSQL_LOG:-/dev/null}"
for a in "$@"; do
    if [[ "$a" == "-e" ]]; then
        printf '%s\n' "${MOCK_MYSQL_CHECK_OUT:-866243|340117}"
        break
    fi
done
exit "${MOCK_MYSQL_RC:-0}"
EOF
chmod +x "$MOCK_BIN/mysql"

# password must never appear on the mysql command line (MYSQL_PWD only).
printf 'SELECT 1;\n' > "$TMPDIR_TEST/pw.sql"
rm -f "$TMPDIR_TEST/mysql-pw.log"
( MYSQL_PASSWORD="s3cret" MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-pw.log" \
    PATH="$MOCK_BIN:$PATH" _ingest_run_sql_file "$TMPDIR_TEST/pw.sql" >/dev/null 2>&1 )
assert_eq "ingest: password never appears on the mysql command line" \
    "0" "$(grep -c 's3cret' "$TMPDIR_TEST/mysql-pw.log" 2>/dev/null)"

# ingest_backup copies MULTILIB_DATA_DIR to a timestamped sibling.
mkdir -p "$TMPDIR_TEST/unit-multilib/data"
printf 'ibdata' > "$TMPDIR_TEST/unit-multilib/data/ibdata1"
( MULTILIB_DATA_DIR="$TMPDIR_TEST/unit-multilib/data" \
    INGEST_STATE_FILE="$TMPDIR_TEST/ingested-backup.tsv" \
    ingest_backup >/dev/null 2>&1 )
assert_ok "ingest_backup copies the data dir to a timestamped sibling" \
    test -f "$TMPDIR_TEST/unit-multilib/data_"*/ibdata1
assert_eq "ingest_backup records the backup in state" \
    "backup" "$(tail -1 "$TMPDIR_TEST/ingested-backup.tsv" | cut -f2)"

mkdir -p "$TMPDIR_TEST/ingest-staging/feeds" "$TMPDIR_TEST/sql"
printf 'CREATE TABLE `libbook` (`BookId` int);\n' > "$TMPDIR_TEST/ingest-staging/feeds/lib.libbook.sql"
printf 'CREATE TABLE `libfilenameold` (`BookId` int);\n' > "$TMPDIR_TEST/sql/lib.libfilenameold.sql"
printf 'DROP TABLE IF EXISTS `mlbook`;\n' > "$TMPDIR_TEST/sql/lib.convert.sql"
printf 'CREATE TABLE IF NOT EXISTS `mllbr_main`.`mldownload`;\n' > "$TMPDIR_TEST/sql/createtable.sql"
printf 'CREATE TABLE `mlrating`; SELECT 1;\n' > "$TMPDIR_TEST/sql/Flibusta_Load_mlrating.sql"
mkdir -p "$TMPDIR_TEST/cli-multilib/data"
printf 'ibdata' > "$TMPDIR_TEST/cli-multilib/data/ibdata1"

# Mock tasklist: when MARIA_MOCK_RUNNING=1, prints "mysqld.exe".
cat > "$MOCK_BIN/tasklist.exe" <<'EOF'
#!/usr/bin/env bash
if [[ "${MARIA_MOCK_RUNNING:-0}" == 1 ]]; then
    printf 'mysqld.exe                   26464 Console                    1    123,456 K\n'
fi
exit 0
EOF
chmod +x "$MOCK_BIN/tasklist.exe"

# Mock powershell: records the call and succeeds.
cat > "$MOCK_BIN/powershell.exe" <<'EOF'
#!/usr/bin/env bash
printf 'POWERSHELL %s\n' "$*" >> "${MOCK_PS_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$MOCK_BIN/powershell.exe"

# Mock taskkill: records the call.
cat > "$MOCK_BIN/taskkill.exe" <<'EOF'
#!/usr/bin/env bash
printf 'TASKKILL %s\n' "$*" >> "${MOCK_TK_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$MOCK_BIN/taskkill.exe"

INGEST_ENV=(PATH="$MOCK_BIN:$PATH" BOOKTRACKER_NO_ENV=1 \
    MYSQL_DATABASE=flibusta \
    INGEST_STATE_FILE="$TMPDIR_TEST/ingested-cli.tsv" \
    STAGING_DIR="$TMPDIR_TEST/ingest-staging" MYSQL_FEEDS_SUBDIR=feeds \
    SQL_DIR="$TMPDIR_TEST/sql" \
    MARIA_TASKLIST="$MOCK_BIN/tasklist.exe" \
    MARIA_TASKKILL="$MOCK_BIN/taskkill.exe" \
    MARIA_EXE="mock-mysqld.exe" \
    MARIA_BIN_DIR="mock-dir" \
    MULTILIB_DATA_DIR="$TMPDIR_TEST/cli-multilib/data")

ingest_rc="$(env "${INGEST_ENV[@]}" bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" --help >/dev/null 2>&1; echo $?)"
assert_eq "ingest: --help exits 0" "0" "$ingest_rc"

ingest_rc="$(env "${INGEST_ENV[@]}" MYSQL_CLIENT=definitely-not-mysql bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" >/dev/null 2>&1; echo $?)"
assert_eq "ingest: missing mysql client exits non-zero" "1" "$ingest_rc"

ingest_rc="$(env "${INGEST_ENV[@]}" bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" bogus >/dev/null 2>&1; echo $?)"
assert_eq "ingest: unknown stage exits non-zero" "2" "$ingest_rc"

# Dry run: prints the mysql command, executes nothing, records nothing.
rm -f "$TMPDIR_TEST/mysql-run.log" "$TMPDIR_TEST/ingested-cli.tsv"
ingest_out="$(env "${INGEST_ENV[@]}" MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-run.log" \
    MARIA_MOCK_RUNNING=0 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" -n 2>&1)"
ingest_rc=$?
assert_eq "ingest: dry-run exits 0" "0" "$ingest_rc"
assert_eq "ingest: dry-run prints start attempt when MariaDB not running" "1" \
    "$(printf '%s' "$ingest_out" | grep -c 'would start MariaDB')"
assert_eq "ingest: dry-run prints a mysql command per file" "7" \
    "$(printf '%s' "$ingest_out" | grep -c 'would run: mysql')"
assert_eq "ingest: dry-run prints stop message" "1" \
    "$(printf '%s' "$ingest_out" | grep -c 'would stop MariaDB')"
assert_fail "ingest: dry-run does not execute mysql" \
    test -f "$TMPDIR_TEST/mysql-run.log"
assert_fail "ingest: dry-run does not record state" \
    test -f "$TMPDIR_TEST/ingested-cli.tsv"

assert_fail "ingest: dry-run does not back up MultiLib/data" \
    test -n "$(ls -d "$TMPDIR_TEST/cli-multilib/data_"* 2>/dev/null)"

# Full run: load (2) + convert (1) + base (1) + rating (1) + check (1) +
# cleanup (1) = 7 mysql invocations, 6 stage records.
rm -f "$TMPDIR_TEST/ingested-cli.tsv" "$TMPDIR_TEST/mysql-run.log" \
    "$TMPDIR_TEST/mock-ps.log" "$TMPDIR_TEST/mock-tk.log"
env "${INGEST_ENV[@]}" MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-run.log" \
    MOCK_PS_LOG="$TMPDIR_TEST/mock-ps.log" \
    MOCK_TK_LOG="$TMPDIR_TEST/mock-tk.log" \
    MARIA_MOCK_RUNNING=0 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" >/dev/null 2>&1
ingest_rc=$?
assert_eq "ingest: full run exits 0" "0" "$ingest_rc"
assert_eq "ingest: starts MariaDB when it is not running" "1" \
    "$(grep -c 'POWERSHELL' "$TMPDIR_TEST/mock-ps.log" 2>/dev/null)"
assert_eq "ingest: full run invokes mysql for each file" "7" \
    "$(grep -c 'MYSQL' "$TMPDIR_TEST/mysql-run.log")"
assert_eq "ingest: stops MariaDB when script started it" "1" \
    "$(grep -c 'TASKKILL' "$TMPDIR_TEST/mock-tk.log" 2>/dev/null)"
assert_ok "ingest: records all six stages" \
    awk -F '\t' 'NR>1{a[$2]=1} END{exit !(a["load"]&&a["convert"]&&a["base"]&&a["rating"]&&a["check"]&&a["cleanup"])}' "$TMPDIR_TEST/ingested-cli.tsv"
assert_eq "ingest: cleanup drops the leftover tables" "5" \
    "$(grep -o 'DROP TABLE IF EXISTS' "$TMPDIR_TEST/mysql-run.log" | wc -l)"

assert_ok "ingest: full run backs up MultiLib/data first" \
    test -f "$TMPDIR_TEST/cli-multilib/data_"*/ibdata1

# Re-run without --force skips every done stage.
before="$(grep -c 'MYSQL' "$TMPDIR_TEST/mysql-run.log")"
env "${INGEST_ENV[@]}" MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-run.log" \
    _BOOKTRACKER_STARTED_MARIADB=0 MARIA_MOCK_RUNNING=1 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" >/dev/null 2>&1
after="$(grep -c 'MYSQL' "$TMPDIR_TEST/mysql-run.log")"
assert_eq "ingest: re-run without --force skips done stages" "$before" "$after"
rm -f "$TMPDIR_TEST/mock-tk.log"
# Full run started MariaDB and wrote to mock-tk.log; this re-run (MariaDB
# already running) must NOT call taskkill, so the log should be empty.
assert_eq "ingest: does not stop MariaDB it did not start" "0" \
    "$(grep -c 'TASKKILL' "$TMPDIR_TEST/mock-tk.log" 2>/dev/null || echo 0)"

# --force re-runs every stage.
rm -f "$TMPDIR_TEST/ingested-cli.tsv" "$TMPDIR_TEST/mysql-run.log"
env "${INGEST_ENV[@]}" MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-run.log" \
    _BOOKTRACKER_STARTED_MARIADB=0 MARIA_MOCK_RUNNING=1 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" --force >/dev/null 2>&1
assert_eq "ingest: --force re-runs all stages" "7" \
    "$(grep -c 'MYSQL' "$TMPDIR_TEST/mysql-run.log")"

# A failing mysql aborts in strict mode.
rm -f "$TMPDIR_TEST/ingested-cli.tsv"
env "${INGEST_ENV[@]}" MOCK_MYSQL_RC=1 MOCK_MYSQL_LOG="$TMPDIR_TEST/mysql-run.log" \
    MARIA_MOCK_RUNNING=1 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" load >/dev/null 2>&1
ingest_rc=$?
assert_eq "ingest: failed load exits non-zero (strict)" "1" "$ingest_rc"

# check fails when the rebuilt catalog is empty.
rm -f "$TMPDIR_TEST/ingested-cli.tsv"
ingest_rc="$(env "${INGEST_ENV[@]}" MOCK_MYSQL_CHECK_OUT="0|0" \
    MARIA_MOCK_RUNNING=1 \
    bash "$PROJECT_ROOT/bin/booktracker-ingest.sh" check >/dev/null 2>&1; echo $?)"
assert_eq "ingest: check fails on an empty catalog" "1" "$ingest_rc"

# MariaDB lifecycle unit tests.
MARIA_TASKLIST="$MOCK_BIN/tasklist.exe"

export MARIA_MOCK_RUNNING=1
assert_ok "ingest_mariadb_running succeeds when mysqld.exe is listed" \
    ingest_mariadb_running

MARIA_MOCK_RUNNING=0
assert_fail "ingest_mariadb_running fails when mysqld.exe absent" \
    ingest_mariadb_running

# ingest_mariadb_start (dry run): check it prints the right message.
DRY_RUN=1
ingest_out="$(MARIA_EXE='C:\\test\\mysqld.exe' MARIA_BIN_DIR='C:\\test' \
    ingest_mariadb_start 2>&1)"
DRY_RUN=0
assert_eq "ingest_mariadb_start (dry-run) prints the right message" \
    "1" "$(printf '%s' "$ingest_out" | grep -c 'would start MariaDB')"

# ingest_mariadb_stop is a no-op when the guard is unset.
unset _BOOKTRACKER_STARTED_MARIADB
ingest_out="$(ingest_mariadb_stop 2>&1)"
assert_eq "ingest_mariadb_stop is no-op without guard" "1" \
    "$(printf '%s' "$ingest_out" | grep -c 'already running')"

# --- Summary ----------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
