booktracker-import
![GitHub release](https://img.shields.io/github/v/release/playfulpin/BookTracker-import?label=version)
![License](https://img.shields.io/badge/license-see%20LICENSE-lightgrey)
booktracker-import is a Unix/Linux command-line tool for importing book
torrents from a book-tracking website into a local home library.
The project automates finding, downloading, and organizing Flibusta-related
torrent metadata so a personal book collection can be maintained locally in a
consistent and reproducible way.
Features
Extract book torrent information from the configured source.
Import torrent files into a local collection.
Stage torrent contents into a local directory, downloading only allowed files
for selective releases.
Organize imported books according to the configured library structure.
Avoid importing files that have already been processed.
Support repeatable / incremental imports.
Provide logging of import operations.
Support dry-run operation before making changes.
Keep site-specific configuration separate from the main application logic.
Designed for automation from the command line.
Project Structure
```text
booktracker-import/
├── bin/
│   ├── booktracker-import.sh      # download .torrent metadata
│   └── booktracker-stage.sh       # download torrent payloads
├── config/
│   └── config.sh                  # paths, titles, behaviour defaults
├── lib/
│   ├── booktracker-import_functions.sh
│   └── booktracker-stage_functions.sh
├── data/                          # runtime state (gitignored content)
├── logs/
├── tests/
├── .gitignore
├── CHANGELOG.md
├── LICENSE
└── README.md
```
`bin/`
Executable scripts:
`booktracker-import.sh` — login and download `.torrent` files
`booktracker-stage.sh` — download torrent contents with `aria2c`
`config/`
Site-specific settings and local paths. Every value can be overridden via the
environment or a gitignored `.env` file.
`lib/`
Reusable shell functions used by the scripts. Private helpers are prefixed with
`_`.
`data/` / `logs/`
Runtime data and log files (not intended for source-controlled book or torrent
files).
`tests/`
Automated tests for pure functions.
Requirements
Unix/Linux (also runs under Git Bash on Windows).
Tool	Notes
Bash 4+	
`curl`	
GNU `grep`	`-o` / `-a`
GNU `date`	`-d` / `-u`
`head`, `cut`, `du`	coreutils
`aria2c`, `gzip`	staging only
Installation
```bash
git clone https://github.com/playfulpin/BookTracker-import.git
cd BookTracker-import

chmod +x bin/booktracker-import.sh bin/booktracker-stage.sh
```
Staging additionally needs `aria2c` (e.g. `sudo apt install aria2`).
Configure credentials and paths:
```bash
# create a gitignored .env
cat > .env <<'EOF'
BOOKTRACKER_USERNAME=
BOOKTRACKER_PASSWORD=
STAGING_DIR=/Downloads/flibusta_snapshot
EOF
```
Or edit `config/config.sh` for non-secret defaults.
Usage
```bash
./bin/booktracker-import.sh --help
```
Login
```bash
./bin/booktracker-import.sh login
```
Stores the session cookie under `data/` (path configurable via `COOKIE_JAR`).
Download torrents
```bash
./bin/booktracker-import.sh get-inpx-fb2      # INPX (FB2 only)
./bin/booktracker-import.sh get-inpx-all      # INPX full / "расширенный"
./bin/booktracker-import.sh get-dump          # database dump
./bin/booktracker-import.sh get-monthly-fb2   # monthly FB2 archive (previous month)
./bin/booktracker-import.sh get-monthly-usr   # monthly non-FB2 archive
```
Fetch all five (each skips if already recorded):
```bash
./bin/booktracker-import.sh all
```
Optional output directory and auto-login when needed:
```bash
./bin/booktracker-import.sh get-inpx-all /path/to/torrents
```
Validate / inspect
```bash
./bin/booktracker-import.sh check /path/to/file.torrent
./bin/booktracker-import.sh check /path/to/file.torrent 2026-07-01
```
Dry-run and debug
```bash
./bin/booktracker-import.sh --dry-run get-dump
./bin/booktracker-import.sh --debug get-inpx-fb2
./bin/booktracker-import.sh all -f          # force re-download
```
Options may appear before or after the command.
Staging (download torrent contents)
After the `.torrent` files are present, stage their payloads:
```bash
export STAGING_DIR=/Downloads/flibusta_snapshot   # optional; this is the default
./bin/booktracker-stage.sh
./bin/booktracker-stage.sh /path/to/one.torrent
```
Type	Downloaded	Staged to
`inpx-fb2` / `inpx-all`	`*.inpx`	`STAGING/inpx/`
`dump`	12 `DUMP_ALLOWLIST` tables (`.gz`)	`STAGING/FlibustaSQL/`, decompressed to `STAGING/mysql_feeds/`
`monthly-fb2` / `monthly-usr`	whole torrent	`STAGING/book_archives/`
```bash
./bin/booktracker-stage.sh --dry-run
./bin/booktracker-stage.sh --force
./bin/booktracker-stage.sh --resume-only
./bin/booktracker-stage.sh --debug
```
Releases can be tens of GB and take hours. For unattended runs, use `tmux` or
`nohup`.
Library functions (`booktracker-import`)
Function	Purpose
`login`	Authenticate and persist the session cookie
`get_torrent_timestamp`	Print a torrent's bencoded creation date (epoch)
`is_valid_timestamp`	Compare torrent timestamp to a reference date (`>=`)
`is_valid_torrent`	Validate bencoded structure
`get_forumid`	Resolve forum id by title on the index page
`get_topicid`	Resolve topic id by title in a forum listing
`get_inpx_fb2`	Download INPX (FB2 only) `.torrent`
`get_inpx_all`	Download INPX (full) `.torrent`
`get_dump`	Download database dump `.torrent`
`get_monthly_fb2`	Discover + download previous month's FB2 archive
`get_monthly_usr`	Discover + download previous month's non-FB2 archive
`prune`	Remove archived torrents older than retention
`list_downloads`	Print download state/history (TSV)
`all`	Run all five `get-*` targets in sequence
`log` / `log_info` / `log_warn` / `log_error` / `debug`	Leveled logging
Staging helpers live in `lib/booktracker-stage_functions.sh` (see source and
`CHANGELOG.md`).
Download folder structure
All Flibusta downloads live under a single root (`STAGING_DIR`, default
`/Downloads/flibusta_snapshot`):
```text
/Downloads
└── flibusta_snapshot
    ├── book_archives/     # monthly *.zip (f.fb2-…, f.usr-…)
    ├── FlibustaSQL/       # *.sql.gz dumps
    ├── inpx/              # *.inpx catalog/index files
    ├── mysql_feeds/       # decompressed *.sql
    └── torrents/          # *.torrent files
```
Subfolder	Contents	Filled by
`torrents/`	`flibusta-<type>-<stamp>.torrent`	`booktracker-import.sh`
`inpx/`	`*.inpx`	`booktracker-stage.sh`
`FlibustaSQL/`	`*.sql.gz`	`booktracker-stage.sh`
`mysql_feeds/`	`*.sql`	`booktracker-stage.sh`
`book_archives/`	monthly `.zip` bundles	`booktracker-stage.sh`
`FlibustaSQL` matches the folder name used by the library's official packages.
Configuration
Primary file: `config/config.sh`.
Credentials and overrides via environment or a gitignored `.env`:
```bash
BOOKTRACKER_USERNAME=
BOOKTRACKER_PASSWORD=
STAGING_DIR=/Downloads/flibusta_snapshot
```
Set `BOOKTRACKER_NO_ENV=1` to ignore `.env` so explicit environment variables
take precedence.
Variable	Default	Description
`BOOKTRACKER_BASE_URL`	`https://booktracker.org`	Tracker base URL
`BOOKTRACKER_USERNAME` / `BOOKTRACKER_PASSWORD`	(empty)	Login credentials
`FORUM_FULL_COLLECTIONS_TITLE`	`Полные сборки библиотеки Флибуста`	Full-collections forum title
`FORUM_MONTHLY_TITLE`	`Ежемесячные архивы (Флибуста)`	Monthly archives forum title
`TOPIC_INPX_ALL_TITLE`	`расширенный`	Full INPX topic fragment
`TOPIC_INPX_FB2_TITLE`	`INPX для библиотеки Flibusta (только FB2)`	FB2-only INPX topic
`TOPIC_DUMP_TITLE`	`Дампы базы данных библиотеки Флибуста`	Dump topic fragment
`MONTH_OFFSET`	`1`	Months back for monthly archives
`DATA_DIR` / `LOG_DIR`	project `data/` / `logs/`	Runtime data / logs
`LOG_LEVEL`	`info`	`debug` | `info` | `warn` | `error`
`DRY_RUN`	`0`	`1` = print actions only
`TORRENT_NAME_PREFIX`	`flibusta`	Prefix for saved torrent names
`ARCHIVE_DIR`	`data/archive/`	Superseded torrents
`ARCHIVE_TORRENTS`	`1`	`1` = archive, `0` = delete
`TORRENT_RETENTION_DAYS`	`0`	Prune archive older than N days (`0` = keep)
`STATE_FILE`	`data/downloads.tsv`	Download history
`STAGING_DIR`	`/Downloads/flibusta_snapshot`	Download root
`TORRENT_DIR`	`$STAGING_DIR/torrents`	Where `.torrent` files are saved
`INPX_SUBDIR`	`inpx`	Subfolder for `*.inpx`
`FLIBUSTA_SQL_SUBDIR`	`FlibustaSQL`	Subfolder for `*.sql.gz`
`MYSQL_FEEDS_SUBDIR`	`mysql_feeds`	Subfolder for decompressed `*.sql`
`BOOK_ARCHIVES_SUBDIR`	`book_archives`	Subfolder for monthly zips
`DUMP_ALLOWLIST`	(12 filenames)	Dump files to fetch (staging)
`ARIA2C_*`	see `config.sh`	Staging download behaviour
Logging
Logs go to the configured log directory / `LOG_FILE`. They record what was
processed, skipped, archived, or failed, at the level set by `LOG_LEVEL`.
License
See LICENSE.
```