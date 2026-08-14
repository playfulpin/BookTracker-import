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
- Automatic discovery of the previous month's archive topics by Russian month
  name (`Архив книг за <месяц> <год> года (FB2,` / `[не-FB2,`).
- Meaningful torrent file naming (`flibusta-<type>-<stamp>.torrent`).
- Archive/retention — superseded torrents are moved to `data/archive/` and can
  be pruned by age via the `prune` command.
- Download state file (`data/downloads.tsv`) with a `history` command.
- Incremental runs — downloads are skipped when already recorded, with a
  `--force` override.
- `all` command to run the five download targets in sequence.
- Leveled logging (`log`, `log_info`, `log_warn`, `log_error`, `debug`).
- Bash test suite (`tests/run_tests.sh`) covering the pure functions.
- `.env.example` template and `.gitignore` rules for credentials and runtime data.

### Fixed

- Torrent link extraction now targets the anchor labeled "Скачать .torrent"
  (`download.php?id=…`) so helper attachments are ignored.
- Torrent `creation date` parsing and UTC-consistent date comparisons.
