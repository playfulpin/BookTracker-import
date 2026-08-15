# Torrent Staging — Specification

**Short name:** `torrent-staging`
**Status:** Implemented (script + functions + tests; pending a live run)
**Date:** 2026-08-14

## 1. Overview

Add a standalone script that consumes the `.torrent` metadata files produced by
`bin/booktracker-import.sh` and downloads their **contents** into a local
staging environment using **aria2c**. For most torrent types the whole torrent
is downloaded; the database-dump (explicit allowlist) and INPX (`*.inpx`)
torrents download only their **allowed** files via aria2c's per-file selection.

The feature is a separate tool, not a change to the existing downloader.

## 2. Background & current state

`bin/booktracker-import.sh` already:

- discovers forum/topic ids at runtime (`get_forumid` / `get_topicid`),
- downloads the `.torrent` **metadata** files (not the payloads) via `curl`,
- stores them as `data/torrents/flibusta-<type>-<stamp>.torrent`,
- records downloads in `data/downloads.tsv`.

The five torrent types and their observed payloads:

| Type | `.torrent` name | Expected payload (from the torrent) |
| --- | --- | --- |
| `inpx-fb2` | `flibusta-inpx-fb2-<date>.torrent` | `.inpx` (FB2-only FLibrary index) |
| `inpx-all` | `flibusta-inpx-all-<date>.torrent` | `.inpx` (full index) **+** `.7z` book archives (FB2+EPUB) |
| `dump` | `flibusta-dump-<date>.torrent` | `*.gz` SQL dumps, directly (no outer archive) |
| `monthly-fb2` | `flibusta-monthly-fb2-<YYYY-MM>.torrent` | `.zip` FB2 book archive |
| `monthly-usr` | `flibusta-monthly-usr-<YYYY-MM>.torrent` | `.zip` non-FB2 book archive |

The trackers are self-contained/public — no extra authentication is needed to
connect to peers (the `.torrent` has the announce passkey baked in; public
trackers are also listed).

### Confirmed dump torrent structure (inspected 2026-08-14)

The `dump` torrent is named **`FlibustaSQL`** and contains **20 files**:

- **18 `*.gz` files** — the SQL dumps plus one `lib.md5.txt.gz` checksum, e.g.
  `lib.libbook.sql.gz`, `lib.libavtor.sql.gz`, `lib.reviews.sql.gz`,
  `lib.a.annotations.sql.gz`, `lib.b.annotations.sql.gz`, `lib.md5.txt.gz`.
- **2 `*.zip` files** that must be **excluded** (large attached-file archives,
  not SQL dumps):
  - `lib.a.attached.zip` (~1.0 GB)
  - `lib.b.attached.zip` (~4.4 GB)

Of the 18 `*.gz` files, only **12 core library tables** are wanted (the
`DUMP_ALLOWLIST` list). The 2 `.zip` archives (~5.4 GB), the annotations
tables (`lib.a.annotations*.sql.gz`, `lib.b.annotations*.sql.gz`),
`lib.md5.txt.gz`, and `lib.reviews.sql.gz` are all skipped. Each downloaded
`.gz` decompresses to a `.sql` file.

## 3. Interview decisions (record of answers)

| Topic | Decision |
| --- | --- |
| Engine | **aria2c for everything** (started as `transmission-cli`, but it has no per-file selection; settled on aria2c). |
| Selective download | `aria2c --select-file=<index>` — `dump`, `inpx-fb2`, and `inpx-all` are selective. |
| Staging environment | A **local directory** (`STAGING_DIR`, an **absolute path** env var). |
| Integration | A **separate standalone script** (e.g. `bin/booktracker-stage.sh`). |
| Allowed-files rule | **Per-type allowlist**; `dump` (explicit 12-file list) and `inpx-fb2`/`inpx-all` (`*.inpx`). |
| Allowed format | `dump`: the 12 files in `DUMP_ALLOWLIST`; `inpx-fb2`/`inpx-all`: `*.inpx`. |
| Dump payload | Dump torrent directly contains `*.gz` files; decompressed to `.sql` when staged. |
| `inpx-all` `.7z` archives | **Not downloaded** — `inpx-all` downloads only its `.inpx` files. |
| Monthly payloads | Both `.zip` archives are staged **as-is** (not unpacked). |
| Layout | `STAGING/inpx/`, `STAGING/Latest/`, `STAGING/flibusta_gz/` (see §7). |
| Trigger | **Manual command only** (no cron/auto-hook). |
| Seeding | **Stop immediately** after download (aria2c `--seed-time=0`). |
| Re-runs | **Skip by default**; `--force` re-processes. Tracked in a state file. |
| State | **New state file** `data/staged.tsv`. |
| Cleanup | **Archive** leftover working-dir files (mostly aria2c logs/control files) to `data/archive/`. |
| Verification | **Trust the client's piece hash-checking** (no extra checksum step). |
| Tracker auth | Self-contained — the `.torrent` works as-is. |

### Why aria2c instead of transmission-cli

The original request named `transmission-cli`. Two facts changed that:

1. `transmission-cli` is deprecated upstream and, critically, has **no
   per-file selection** — it always downloads the whole torrent. Its `-f` flag
   is `--finish` (run a script when done), not a file selector.
2. The requirement "**do not download** disallowed files" is therefore
   impossible with `transmission-cli`.

`aria2c` provides `--select-file=<index>` to download only chosen files, and
`--seed-time=0` satisfies "stop immediately". It was chosen for **all**
downloads so there is a single engine.

## 4. Functional requirements

### 4.1 Inputs

- `.torrent` files in `data/torrents/` matching `flibusta-<type>-<stamp>.torrent`.
- The type is parsed from the filename (the `-<type>-` segment).
- `STAGING_DIR` must be set to an absolute path (error if missing/empty).

### 4.2 Outputs

- Allowed files copied into `STAGING_DIR` subfolders (see §7).
- A `data/staged.tsv` row for each successfully staged torrent.
- The raw download working directory moved to `data/archive/`.

### 4.3 Non-goals

- No integration into `booktracker-import.sh` (separate script).
- No scheduling/automation (manual only).
- No seeding beyond "stop immediately".
- No decompression of `.zip`/`.7z` payloads (`.gz` is decompressed to `.sql`; see §7.3).
- No library import (no FLibrary/Calibre integration).

## 5. Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `STAGING_DIR` | *(none — required)* | Absolute path to the staging root. |
| `TORRENT_DIR` | `data/torrents` | Where input `.torrent` files live (reuse existing). |
| `ARCHIVE_DIR` | `data/archive` | Where the working dir is archived after staging. |
| `STATE_FILE` | `data/downloads.tsv` | Existing download state (unchanged). |
| `STAGED_STATE_FILE` | `data/staged.tsv` | New: records staged torrents. |
| `LOG_LEVEL` | `info` | Reuse existing logging. |
| `ARIA2C_SEED_TIME` | `0` | Seconds to seed; `0` = stop immediately. |
| `DUMP_ALLOWLIST` | *(12 filenames)* | Explicit files to download from the `dump` torrent. |

The per-type allowlist is the only hard-coded rule for now and lives in the
script (or a small config block):

```
dump:     [12 explicit filenames]  # DUMP_ALLOWLIST; download only these, then decompress
inpx-fb2, inpx-all: *.inpx         # download ONLY *.inpx (skip any .7z archives)
monthly-fb2, monthly-usr: (full download)
```

## 6. CLI design

Proposed `bin/booktracker-stage.sh`:

```
Usage: booktracker-stage.sh [options] [torrent-file...]

With no arguments, process every un-staged .torrent in TORRENT_DIR.

Options:
  -f, --force     Re-stage even if already recorded in data/staged.tsv
  -n, --dry-run   Print what would happen without downloading
  -d, --debug     Enable debug logging
  -h, --help      Show this help

Environment:
  STAGING_DIR     (required) absolute path to the staging root
```

## 7. Per-type behavior

### 7.1 `inpx-fb2` → `STAGING/inpx/`

- **Selective**: download only `.inpx` files (`aria2c --select-file`).
- Stage the `.inpx` files into `STAGING/inpx/`.

### 7.2 `inpx-all` → `STAGING/inpx/`

- **Selective**: download only `.inpx` files (`aria2c --select-file`).
- Stage the `.inpx` files into `STAGING/inpx/`.
- The `.7z` book archives are **not downloaded** at all.

### 7.3 `dump` → `STAGING/flibusta_gz/`

- **Selective**: inspect the torrent's file list and download only the 12
  `DUMP_ALLOWLIST` files (core library tables) via
  `aria2c --select-file=<indices>`.
- Everything else is **never downloaded** — the `.zip` attached archives, the
  annotations tables, `lib.md5.txt.gz`, and `lib.reviews.sql.gz`.
- Decompress each `.gz` to `.sql` (e.g. `gzip -dk`), then stage the `.sql`
  files into `STAGING/flibusta_gz/`. (The folder keeps the user-chosen
  `flibusta_gz` name even though it now holds `.sql` files.)

### 7.4 `monthly-fb2` → `STAGING/Latest/`

- Full download.
- Stage the `.zip` archive(s) into `STAGING/Latest/` as-is.

### 7.5 `monthly-usr` → `STAGING/Latest/`

- Full download.
- Stage the `.zip` archive(s) into `STAGING/Latest/` as-is (distinct names from
  `monthly-fb2`).

### Collision rules

- `STAGING/inpx/`: both `inpx-fb2` and `inpx-all` may drop `.inpx` files there;
  **keep both, overwrite on identical filename**.
- `STAGING/Latest/`: both monthly archives coexist; **keep names** (they differ).

## 8. Processing flow (per torrent)

1. Parse `<type>` from the filename; reject unknown names.
2. If the torrent is in `data/staged.tsv` and not `--force`: **skip**.
3. List files (`aria2c --show-files <torrent>` or `aria2c -S`).
4. Determine download set:
   - `dump`: indices of files whose names are in `DUMP_ALLOWLIST`.
   - `inpx-fb2`/`inpx-all`: indices of files whose names match `*.inpx`.
   - others: all files.
5. Download into a working dir (e.g. `data/torrents/work/<name>/`) using
   `aria2c --seed-time=0` (+ `--select-file` for `dump` and `inpx-all`).
6. For `dump`, decompress `.gz` → `.sql` (gzip); then move the allowed files
   into the appropriate `STAGING_DIR` subfolder.
7. Archive the working dir to `data/archive/`.
8. Append a row to `data/staged.tsv`
   (`staged_at`, `type`, `torrent`, `stamp`, `destination`, `files`).
9. Log the outcome (reuse `log`/`log_info`/`log_warn`/`log_error`).

## 9. Error handling & edge cases

- **Missing `STAGING_DIR`** → error and exit non-zero.
- **Unknown/corrupt `.torrent`** → log error, skip that file, continue others.
- **No seeders / stall** → rely on aria2c retry/timeout; log failure; do not
  record in `staged.tsv` so a later run retries.
- **Partial download** → aria2c resume via its `.aria2` control file if the
  working dir still exists; otherwise re-download.
- **Collision** → per §7 collision rules (overwrite in `STAGING/inpx`, keep
  both in `STAGING/Latest`).
- **Disk full / move failure** → log error, leave working dir in place for
  manual recovery, do not mark staged.
- **Dry run** → print the aria2c command + destination without downloading.

## 10. Resolved decisions

| # | Resolution |
| --- | --- |
| OQ-1 | `STAGING_DIR` is **required** — fail fast with a clear error if unset/empty. |
| OQ-2 | `inpx-all` is **selective**: download only `.inpx`, skip the `.7z` books. |
| OQ-3 | Monthly `.zip` archives are kept **as `.zip`** (not unpacked). |
| OQ-4 | Dump `.gz` files are **decompressed to `.sql`** before staging. |
| OQ-5 | Archive the leftover working-dir files (mostly aria2c logs/control files) to `data/archive/`. |
| OQ-6 | `aria2c` is already installed; if it is ever missing, error out with an install hint (no auto-install). |

## 11. Testing plan (no network required where possible)

- Pure logic unit tests (extend `tests/run_tests.sh`):
  - type parsing from filenames (`flibusta-dump-2026-08-01.torrent` → `dump`).
  - `dump` file-list → allowlist index selection (mock `aria2c --show-files` output).
  - destination mapping per type.
  - state-file skip vs `--force`.
  - collision handling (inpx overwrite vs Latest keep-both).
- CLI arg parsing tests (options before/after args, like the existing suite).
- A dry-run test that only prints commands.

## 12. Out of scope (explicit)

- Changing `booktracker-import.sh` behavior.
- Cron/systemd scheduling.
- Seeding to a ratio.
- Import into a reader library (FLibrary/Calibre) — only `.gz → .sql` decompression is performed.
- Remote (NAS/Docker) staging — local directory only for now.
