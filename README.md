# booktracker-import

![GitHub release](https://img.shields.io/github/v/release/playfulpin/BookTracker-import?label=version)
![License](https://img.shields.io/badge/license-see%20LICENSE-lightgrey)

**booktracker-import** is a Unix/Linux command-line tool for importing book
torrents from a book-tracking website into a local home library.

The project automates finding, downloading, and organizing Flibusta-related
torrent metadata so a personal book collection can be maintained locally in a
consistent and reproducible way.

## Features

* Extract book torrent information from the configured source.
* Import torrent files into a local collection.
* Download torrent payloads into a local directory, fetching only allowed files
  for selective releases.
* Organize imported books according to the configured library structure.
* Avoid importing files that have already been processed.
* Support repeatable / incremental imports.
* Provide logging of import operations.
* Support dry-run operation before making changes.
* Keep site-specific configuration separate from the main application logic.
* Designed for automation from the command line.

## Project Structure

```text
booktracker-import/
├── bin/
│   ├── booktracker-import.sh       # download .torrent metadata
│   ├── booktracker-extract.sh      # download torrent payloads (aria2c)
│   └── booktracker-ingest.sh       # load dumps into MySQL + rebuild catalog
├── config/
│   └── config.sh                   # paths, titles, behaviour defaults
├── lib/
│   ├── booktracker-import_functions.sh
│   ├── booktracker-extract_functions.sh
│   └── booktracker-ingest_functions.sh
├── deprecated/                     # retired stage implementation (reference only)
│   ├── booktracker-stage.sh
│   └── booktracker-stage_functions.sh
├── data/                           # runtime state (gitignored content)
├── logs/
├── tests/
├── .gitignore
├── CHANGELOG.md
├── LICENSE
└── README.md
```

### `bin/`

Executable scripts:

* `booktracker-import.sh` — login and download `.torrent` files
* `booktracker-extract.sh` — download torrent contents with `aria2c`
* `booktracker-ingest.sh` — load dump `.sql` files into MySQL/MariaDB and
  rebuild the MultiLib catalog

### `config/`

Site-specific settings and local paths. Every value can be overridden via the
environment or a gitignored `.env` file.

### `lib/`

Reusable shell functions used by the scripts. Private helpers are prefixed with
`_`.

### `deprecated/`

Previous **stage** implementation (`booktracker-stage.sh` and its library).
Kept for reference only; new work uses **extract**. Do not rely on these for
day-to-day runs.

### `data/` / `logs/`

Runtime data and log files (not intended for source-controlled book or torrent
files).

### `tests/`

Automated tests for pure functions.

## Requirements

Unix/Linux (also runs under Git Bash on Windows).

| Tool | Notes |
|------|--------|
| Bash 4+ | |
| `curl` | |
| GNU `grep` | `-o` / `-a` |
| GNU `date` | `-d` / `-u` |
| `head`, `cut`, `du` | coreutils |
| `aria2c`, `gzip` | extract only |
| `mysql` client | ingest only |

## Installation

```bash
git clone https://github.com/playfulpin/BookTracker-import.git
cd BookTracker-import

chmod +x bin/booktracker-import.sh bin/booktracker-extract.sh bin/booktracker-ingest.sh
```

Extract additionally needs `aria2c` (e.g. `sudo apt install aria2`).

Configure credentials and paths:

```bash
# create a gitignored .env
cat > .env <<'ENVEOF'
BOOKTRACKER_USERNAME=
BOOKTRACKER_PASSWORD=
STAGING_DIR=/Downloads/flibusta_snapshot
ENVEOF
```

Or edit `config/config.sh` for non-secret defaults.

## Usage

```bash
./bin/booktracker-import.sh --help
```

### Login

```bash
./bin/booktracker-import.sh login
```

Stores the session cookie under `data/` (path configurable via `COOKIE_JAR`).

### Download torrents

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

### Validate / inspect

```bash
./bin/booktracker-import.sh check /path/to/file.torrent
./bin/booktracker-import.sh check /path/to/file.torrent 2026-07-01
```

### Dry-run and debug

```bash
./bin/booktracker-import.sh --dry-run get-dump
./bin/booktracker-import.sh --debug get-inpx-fb2
./bin/booktracker-import.sh all -f          # force re-download
```

Options may appear before or after the command.

### Extract (download torrent contents)

After the `.torrent` files are present, extract their payloads:

```bash
export STAGING_DIR=/Downloads/flibusta_snapshot   # optional; this is the default
./bin/booktracker-extract.sh
./bin/booktracker-extract.sh /path/to/one.torrent
```

| Type | Downloaded | Extracted to |
|------|------------|--------------|
| `inpx-fb2` / `inpx-all` | `*.inpx` | `STAGING/inpx/` |
| `dump` | 12 `DUMP_ALLOWLIST` tables (`.gz`) | `STAGING/FlibustaSQL/`, decompressed to `STAGING/mysql_feeds/` |
| `monthly-fb2` / `monthly-usr` | whole torrent | `STAGING/book_archives/` |

```bash
./bin/booktracker-extract.sh --dry-run
./bin/booktracker-extract.sh --force
./bin/booktracker-extract.sh --resume-only
./bin/booktracker-extract.sh --debug
```

Releases can be tens of GB and take hours. For unattended runs, use `tmux` or
`nohup`.

> **Note:** The older `booktracker-stage` scripts live under `deprecated/` for
> reference only. Prefer `booktracker-extract` for all new work. Both can share
> the same `data/staged.tsv` state file.

### Ingest (load into MySQL / rebuild the catalog)

After the dump `.sql` files are decompressed into `mysql_feeds/`, load them
into a local MySQL/MariaDB instance and run MultiLib's transform SQL to
rebuild its catalog (`lib*` → `ml*`):

```bash
./bin/booktracker-ingest.sh              # load+convert+base+rating+check+cleanup (default)
./bin/booktracker-ingest.sh load         # only load the raw lib* tables
./bin/booktracker-ingest.sh --dry-run    # print the mysql commands
./bin/booktracker-ingest.sh --force      # re-run even if already recorded
```

| Stage | What it does |
|-------|--------------|
| `load` | Load `mysql_feeds/*.sql` (+ `lib.libfilenameold.sql`) into `MYSQL_DATABASE` |
| `convert` | Run `lib.convert.sql` (`lib*` → `ml*`, destructive rebuild) |
| `base` | Run `createtable.sql` (mllbr_main tables) |
| `rating` | Run `Flibusta_Load_mlrating.sql` (build `mlrating` from `librate`) |
| `check` | Verify the rebuilt catalog/ratings are populated (read-only) |
| `cleanup` | Drop leftover working tables (`librating` + raw `lib*` tables) |

The transform/base/rating SQL is bundled under `sql/` (`SQL_DIR`, default
`<project>/sql`). The bundled files were authored on Windows (CRLF, some with a
UTF-8 BOM), so each is normalized before it reaches the client. It connects
over TCP to `127.0.0.1` (WSL2 mirrored networking), never `localhost`.

Before any non-dry-run ingest, the MariaDB data directory
(`MULTILIB_DATA_DIR`, default `/mnt/c/MultiLib/data`) is copied to a
timestamped sibling (e.g. `/mnt/c/MultiLib/data_2026-08-21_192900`) so the
catalog can be restored if anything goes wrong. `--dry-run` skips the backup.

The ingest script automatically checks whether MariaDB (`mysqld.exe`) is
running via `tasklist.exe` and, if absent, starts it via an elevated
PowerShell process. When the script itself launched MariaDB, it stops the
server (`taskkill.exe`) on exit; when MariaDB was already running, the
script leaves it untouched.

> **Note:** `convert` drops and rebuilds the `ml*` catalog tables. Run
> `--dry-run` first. For a guaranteed-consistent backup, stop MariaDB
> (`stop__MariaDB.bat`) before a real run — a filesystem copy of a running
> InnoDB data directory can be captured mid-write.

## Library functions (`booktracker-import`)

| Function | Purpose |
|----------|---------|
| `login` | Authenticate and persist the session cookie |
| `get_torrent_timestamp` | Print a torrent's bencoded creation date (epoch) |
| `is_valid_timestamp` | Compare torrent timestamp to a reference date (`>=`) |
| `is_valid_torrent` | Validate bencoded structure |
| `get_forumid` | Resolve forum id by title on the index page |
| `get_topicid` | Resolve topic id by title in a forum listing |
| `get_inpx_fb2` | Download INPX (FB2 only) `.torrent` |
| `get_inpx_all` | Download INPX (full) `.torrent` |
| `get_dump` | Download database dump `.torrent` |
| `get_monthly_fb2` | Discover + download previous month's FB2 archive |
| `get_monthly_usr` | Discover + download previous month's non-FB2 archive |
| `prune` | Remove archived torrents older than retention |
| `history` | Print download state/history (TSV) |
| `all` | Run all five `get-*` targets in sequence |
| `log` / `log_info` / `log_warn` / `log_error` / `debug` | Leveled logging |

Extract helpers live in `lib/booktracker-extract_functions.sh` (`extract_type_from_name`,
`extract_destination`, allowlists, size helpers, state, etc.).

## Download folder structure

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

| Subfolder | Contents | Filled by |
|-----------|----------|-----------|
| `torrents/` | `flibusta-<type>-<stamp>.torrent` | `booktracker-import.sh` |
| `inpx/` | `*.inpx` | `booktracker-extract.sh` |
| `FlibustaSQL/` | `*.sql.gz` | `booktracker-extract.sh` |
| `mysql_feeds/` | `*.sql` | `booktracker-extract.sh` |
| `book_archives/` | monthly `.zip` bundles | `booktracker-extract.sh` |

`FlibustaSQL` matches the folder name used by the library's official packages.

## Configuration

Primary file: `config/config.sh`.

Credentials and overrides via environment or a gitignored `.env`:

```bash
BOOKTRACKER_USERNAME=
BOOKTRACKER_PASSWORD=
STAGING_DIR=/Downloads/flibusta_snapshot
```

Set `BOOKTRACKER_NO_ENV=1` to ignore `.env` so explicit environment variables
take precedence.

| Variable | Default | Description |
|----------|---------|-------------|
| `BOOKTRACKER_BASE_URL` | `https://booktracker.org` | Tracker base URL |
| `BOOKTRACKER_USERNAME` / `BOOKTRACKER_PASSWORD` | *(empty)* | Login credentials |
| `FORUM_FULL_COLLECTIONS_TITLE` | `Полные сборки библиотеки Флибуста` | Full-collections forum title |
| `FORUM_MONTHLY_TITLE` | `Ежемесячные архивы (Флибуста)` | Monthly archives forum title |
| `TOPIC_INPX_ALL_TITLE` | `расширенный` | Full INPX topic fragment |
| `TOPIC_INPX_FB2_TITLE` | `INPX для библиотеки Flibusta (только FB2)` | FB2-only INPX topic |
| `TOPIC_DUMP_TITLE` | `Дампы базы данных библиотеки Флибуста` | Dump topic fragment |
| `MONTH_OFFSET` | `1` | Months back for monthly archives |
| `DATA_DIR` / `LOG_DIR` | project `data/` / `logs/` | Runtime data / logs |
| `LOG_LEVEL` | `info` | `debug` \| `info` \| `warn` \| `error` |
| `DRY_RUN` | `0` | `1` = print actions only |
| `TORRENT_NAME_PREFIX` | `flibusta` | Prefix for saved torrent names |
| `ARCHIVE_DIR` | `data/archive/` | Superseded torrents |
| `ARCHIVE_TORRENTS` | `1` | `1` = archive, `0` = delete |
| `TORRENT_RETENTION_DAYS` | `0` | Prune archive older than N days (`0` = keep) |
| `STATE_FILE` | `data/downloads.tsv` | Download history |
| `STAGED_STATE_FILE` | `data/staged.tsv` | Extract/stage history |
| `STAGING_DIR` | `/Downloads/flibusta_snapshot` | Download root |
| `TORRENT_DIR` | `$STAGING_DIR/torrents` | Where `.torrent` files are saved |
| `INPX_SUBDIR` | `inpx` | Subfolder for `*.inpx` |
| `FLIBUSTA_SQL_SUBDIR` | `FlibustaSQL` | Subfolder for `*.sql.gz` |
| `MYSQL_FEEDS_SUBDIR` | `mysql_feeds` | Subfolder for decompressed `*.sql` |
| `BOOK_ARCHIVES_SUBDIR` | `book_archives` | Subfolder for monthly zips |
| `DUMP_ALLOWLIST` | *(12 filenames)* | Dump files to fetch (extract) |
| `MYSQL_HOST` / `MYSQL_PORT` | `127.0.0.1` / `3306` | MySQL server (ingest) |
| `MYSQL_USER` / `MYSQL_PASSWORD` | `root` / *(empty)* | MySQL credentials (ingest) |
| `MYSQL_DATABASE` | `flibusta` | Target database (ingest) |
| `MYSQL_EXTRA_ARGS` | `--default-character-set=utf8` | Extra client option (ingest) |
| `SQL_DIR` | `<project>/sql` | Bundled transform/base/rating SQL source |
| `MULTILIB_DATA_DIR` | `/mnt/c/MultiLib/data` | MariaDB data dir, backed up before ingest |
| `INGEST_STATE_FILE` | `data/ingested.tsv` | Ingest stage history |
| `INGEST_STRICT` | `1` | Abort ingest on first failure |
| `INGEST_CLEANUP_TABLES` | *(5 tables)* | Leftover tables dropped by cleanup |
| `ARIA2C_*` | see `config.sh` | Extract download behaviour |

## Logging

Logs go to the configured log directory / `LOG_FILE`. They record what was
processed, skipped, archived, or failed, at the level set by `LOG_LEVEL`.

## License

See [LICENSE](LICENSE).
