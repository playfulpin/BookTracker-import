# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `lib/booktracker-extract_functions.sh`: canonical inpx-fb2 output name
  (`extract_inpx_fb2_output_name`, `extract_output_basename`) so the FB2-only
  INPX index lands as `flibusta_fb2_local-YYYY-MM-01_original.inpx`.

### Changed

- `bin/booktracker-extract.sh`: `extract_one` now parses each torrent's
  download set once into parallel index/name arrays and derives `--select-file`
  from them, removing the repeated `idx|path`-splitting loops.
- `tests/run_tests.sh`: rewritten to cover the extract functions (`extract_*`)
  and the `bin/booktracker-extract.sh` CLI (canonical inpx-fb2 output name,
  aria2c flags, dump decompress, stale-dir removal, `--resume-only`), replacing
  the deprecated `stage_*` references.
- Script version headers bumped (Updated 2026-08-21 17:18 CDT):
  `bin/booktracker-extract.sh` 0.1.3, `lib/booktracker-extract_functions.sh`
  0.1.2, `lib/booktracker-import_functions.sh` 0.1.4.

### Fixed

- `lib/booktracker-import_functions.sh`: removed a stray Markdown code fence at
  the end of the file that made `bash -n` report an "unexpected EOF" error.
- `tests/run_tests.sh`: the retention tests called the removed
  `_retire_superseded` helper; they now call `_archive_superseded`.

## [0.2.0] - 2026-08-20

### Added

- `bin/booktracker-extract.sh` and `lib/booktracker-extract_functions.sh` —
  download torrent payloads with aria2c (selective allowlists, destinations,
  dump decompress to `mysql_feeds/`, state in `data/staged.tsv`).
  Built from Examples prototypes + torrent-staging-spec behaviour; styled like
  the import CLI (`usage_error`, exit codes, logging).
- `config/config.sh`: `STAGED_STATE_FILE`, `ARIA2C_BT_MAX_PEERS`,
  `ARIA2C_BT_MAX_OPEN_FILES`, `ARIA2C_PEER_ID_PREFIX`.

### Changed

- Preferred payload tool is **extract** (not stage).
- README documents extract usage and the `deprecated/` folder.
- `HTTP_USER_AGENT` default → `booktracker-import/0.1.3`.

### Deprecated

- `booktracker-stage.sh` and `booktracker-stage_functions.sh` moved under
  `deprecated/` for reference only. Prefer `booktracker-extract` for new work.
  State file `data/staged.tsv` remains compatible with both.

## [0.1.3] - 2026-08-20

### Changed

- `bin/booktracker-import.sh`:
  - enable `set -o pipefail` (without `set -e`)
  - centralize usage failures via `usage_error` (unknown option/command,
    missing args) → exit code 2
  - keep the script thin: load config → parse args → dispatch only
- `lib/booktracker-import_functions.sh`:
  - document pure / test-friendly helpers in the file header
  - shell-style notes (quote expansions, `local`, return not exit, shellcheck)
- Version headers set to **0.1.3** (Updated: 2026-08-20 18:46 CDT).

## [0.1.2] - 2026-08-20

### Changed

- `bin/booktracker-import.sh` and `lib/booktracker-import_functions.sh`:
  - clearer section layout and CLI → function mapping in the main script header
  - rename `_retire_superseded` → `_archive_superseded`
  - rename `list_downloads` → `history` (matches the CLI command `history`)
  - extract shared `_get_by_topic` helper; `get_inpx_fb2`, `get_inpx_all`, and
    `get_dump` are thin wrappers around it
  - document exit codes (`0` success, `1` operational failure, `2` usage error)
    in headers and `--help`
  - `all` continues on failure and reports failed target names in the summary
  - more consistent start / success / skip / fail log lines; `debug` logs forum
    id, topic id, and download URL
- Version headers set to **0.1.2** (Updated: 2026-08-20 17:51 CDT).
- `config/config.sh`: version header; `HTTP_USER_AGENT` default bumped to `booktracker-import/0.1.2`.
- No changes to staging scripts.

## [0.1.1] - 2026-08-20

### Changed

- Improved readability of `bin/booktracker-import.sh` and
  `lib/booktracker-import_functions.sh`:
  - consistent file headers with **Version** and **Updated** (date + time)
  - uniform section banners (Logging, HTTP helpers, Session, Torrent
    inspection, Forum / topic discovery, Download helpers, Public download
    commands, Housekeeping)
  - short, consistent function doc-comments for the public API and private
    helpers
- No functional or behavioural changes.

## [0.1.0] - 2026-08-14

### Added

- `login` — authenticate against booktracker.org (TorrentPier) and persist the
  session cookie.
- Torrent inspection helpers:
  - `get_torrent_timestamp` — extract a torrent's bencoded `creation date`.
  - `is_valid_timestamp` — compare a torrent timestamp to a reference date.
  - `is_valid_torrent` — validate a torrent's bencoded structure.
- Download commands for the Флибуста releases: `get-inpx-fb2`, `get-inpx-all`,
  `get-dump`, `get-monthly-fb2`, and `get-monthly-usr`.
- `check` command to validate a torrent file and print/compare its timestamp.
- `history` command to show the download state/history (TSV).
- `prune` command to delete archived torrents older than the retention window.
- Automatic discovery of the previous month's archive topics by Russian month
  name (`Архив книг за <месяц> <год> года (FB2,` / `[не-FB2,`).
- Runtime discovery of forum/topic ids by title (`get_forumid`, `get_topicid`),
  so releases stay resolvable even as the site's numeric ids change.
- Meaningful torrent file naming (`flibusta-<type>-<stamp>.torrent`).
- Archive/retention — superseded torrents are moved to `data/archive/` and can
  be pruned by age via the `prune` command.
- Download state file (`data/downloads.tsv`) with a `history` command.
- Incremental runs — downloads are skipped when already recorded, with a
  `--force` override.
- `all` command to run the five download targets in sequence.
- Leveled logging (`log`, `log_info`, `log_warn`, `log_error`, `debug`).
- Bash test suite (`tests/run_tests.sh`) covering the pure functions.
- `.gitignore` rules to keep credentials and runtime data out of version control.
- Staging of torrent contents (`bin/booktracker-stage.sh`):
  - downloads `.torrent` payloads directly into a local `STAGING_DIR` with
    `aria2c`,
  - selective download per type — `dump` fetches only the 12 `DUMP_ALLOWLIST`
    tables and `inpx-fb2`/`inpx-all` fetch only `*.inpx`,
  - decompresses dump `.gz` files to `.sql` into a sibling `mysql_feeds/` folder,
  - records results in `data/staged.tsv` (skip by default; `--force` re-runs).
- Staging helper functions (`stage_type_from_name`, `stage_destination`,
  `stage_sql_destination`, `stage_torrent_name`, `stage_stale_dir`,
  `stage_is_allowed`, `stage_download_files`, `stage_select_indexes`,
  `stage_total_size`, `stage_human_size`, `stage_bytes_from_human`,
  `stage_is_done`, `stage_record`).

### Changed

- Consolidated all downloads under a single download root (`STAGING_DIR`,
  default `/Downloads/flibusta_snapshot`): `.torrent` files now live in
  `STAGING_DIR/torrents/` (previously `data/torrents/`), and staged payload
  folders were renamed — `Latest/` → `book_archives/`, `flibusta_gz/` →
  `FlibustaSQL/`, `flibusta/` → `mysql_feeds/`.  The subfolder names are now
  configurable (`INPX_SUBDIR`, `FLIBUSTA_SQL_SUBDIR`, `MYSQL_FEEDS_SUBDIR`,
  `BOOK_ARCHIVES_SUBDIR`).
- Replaced the hardcoded INPX/dump topic ids and the monthly forum id with
  live title-based discovery (`get_forumid` / `get_topicid`).
- Staging now downloads payload files directly into `STAGING_DIR`, eliminating
  the working directory, copy/move step, and archive step.
- aria2c downloads now retry indefinitely (`ARIA2C_MAX_TRIES`), hash-check
  existing files (`--check-integrity`), and print a progress summary every
  `ARIA2C_SUMMARY_INTERVAL` seconds — keeping multi-GB, multi-hour releases
  resilient and visible.
- Staging enables DHT, peer exchange, and local peer discovery, and announces a
  configurable set of fallback public trackers (`ARIA2C_EXTRA_TRACKERS`) so a
  public torrent still finds peers when its original tracker is down or stale.
- Selective downloads pin files flat with `--index-out` and use
  `--file-allocation=none` + `--bt-remove-unselected-file` so large adjacent
  archives (e.g. the dump's multi-GB `.zip`s) are neither preallocated nor
  left behind.
- Dump `.gz` files now decompress into a sibling `STAGING/mysql_feeds/` folder,
  keeping the raw `.gz` in `STAGING/FlibustaSQL/`.
- Added `--resume-only` to skip torrents whose files are already fully
  downloaded, and the script now logs the total download size per torrent
  before starting.
- Staging now detects and removes a stale torrent-named folder in the
  destination (left by an older run that nested files before `--index-out`
  pinned them flat) before downloading, so it can't trigger checksum errors on
  every resume.

### Fixed

- CLI options (`-f`, `-n`, `-d`) are now accepted after the command as well as
  before it (`all -f` no longer treats `-f` as the output directory).
- `--dry-run` performs no filesystem side effects (it no longer creates the
  staging directory).
- The per-torrent download size is now parsed from aria2c's actual torrent
  `--show-files` size lines (`   |91MiB (96,397,659)`), using the exact
  parenthesized byte count, so the dry-run/start log shows a real total rather
  than `0.0B`.
- Added `BOOKTRACKER_NO_ENV=1` to skip the gitignored `.env` file, so
  explicitly set environment variables take precedence (also keeps the test
  suite isolated from a developer's real `.env`).
- Corrected the INPX topic fragments so `get-inpx-fb2` resolves to
  `INPX для библиотеки Flibusta (только FB2)` and `get-inpx-all` to
  `inpx … "расширенный"` (the previous fragments matched the full
  `Дополнительные данные` FLibrary collection and a generic "inpx" topic).
- Torrent link extraction now targets the anchor labeled "Скачать .torrent"
  (`download.php?id=…`) so helper attachments are ignored.
- Torrent `creation date` parsing and UTC-consistent date comparisons.
- Verified live on 2026-08-14: a full `all -f` run resolved and downloaded all
  five release types successfully.

[Unreleased]: https://github.com/playfulpin/BookTracker-import/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/playfulpin/BookTracker-import/compare/v0.1.3...v0.2.0
[0.1.3]: https://github.com/playfulpin/BookTracker-import/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/playfulpin/BookTracker-import/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/playfulpin/BookTracker-import/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/playfulpin/BookTracker-import/releases/tag/v0.1.0
