# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.10.0.html).

## [Unreleased]

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
  - downloads `.torrent` payloads into a local `STAGING_DIR` with `aria2c`,
  - selective download per type — `dump` fetches only the 12 `DUMP_ALLOWLIST`
    tables and `inpx-fb2`/`inpx-all` fetch only `*.inpx`,
  - decompresses dump `.gz` files to `.sql`,
  - records results in `data/staged.tsv` (skip by default; `--force` re-runs).
- Staging helper functions (`stage_type_from_name`, `stage_destination`,
  `stage_is_allowed`, `stage_select_indexes`, `stage_is_done`, `stage_record`,
  `stage_place`).

### Changed

- Replaced the hardcoded INPX/dump topic ids and the monthly forum id with
  live title-based discovery (`get_forumid` / `get_topicid`).

### Fixed

- CLI options (`-f`, `-n`, `-d`) are now accepted after the command as well as
  before it (`all -f` no longer treats `-f` as the output directory).
- Updated the INPX topic search fragments to match the current release titles
  (the "расширенный"/"только FB2" wording was replaced by "…FLibrary + inpx"
  and "Дополнительные данные…").
- Torrent link extraction now targets the anchor labeled "Скачать .torrent"
  (`download.php?id=…`) so helper attachments are ignored.
- Torrent `creation date` parsing and UTC-consistent date comparisons.
- Verified live on 2026-08-14: a full `all -f` run resolved and downloaded all
  five release types successfully.
