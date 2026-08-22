# NEXT — where to resume

> Updated: 2026-08-21 21:30 CDT
> Last commit: `32c677c feat(ingest): load dumps into MariaDB and rebuild the MultiLib catalog`

## Resume checklist

```bash
cd /home/mike/GIT_ROOT/BookTracker-import
git status             # expect: clean tree, up to date with origin/main
git log --oneline      # expect: 32c677c at the top
bash tests/run_tests.sh # expect: 168 passed, 0 failed
```

If the tree is not up to date with `origin/main`, push (`git push`) before
starting new work so the GitHub copy is current.

## Current state

The pipeline is complete end-to-end:

```
import  →  extract  →  ingest
.torrent    .gz/.sql    .sql → MariaDB → rebuilt ml* catalog
```

| Script | Purpose |
|--------|---------|
| `bin/booktracker-import.sh` | login + download `.torrent` metadata |
| `bin/booktracker-extract.sh` | download torrent payloads (`aria2c`) |
| `bin/booktracker-ingest.sh` | load dumps into MariaDB + rebuild catalog |

Ingest stages (in order): `load → convert → base → rating → check → cleanup`.
It backs up the MultiLib data dir before any real run, connects over TCP to
`127.0.0.1` (WSL2 mirrored networking), and bundles its SQL under `sql/`.

## Next steps (in priority order)

1. **CI via GitHub Actions** — a workflow running `bash tests/run_tests.sh` on
   push/PR for free regression coverage.
2. **Integrity verification** — a `verify` stage that fetches the dump's
   `.md5.txt.gz` checksums and validates `FlibustaSQL/*.gz` (note: the current
   `DUMP_ALLOWLIST` deliberately excludes the checksum file).
3. **Orchestration entrypoint** — a single `sync`/`update` command chaining
   `import → extract → verify → ingest`, plus a cron/systemd timer example for
   unattended monthly updates.

## Open questions / notes carried forward

- `lib.librate.sql` was reported **missing** from `mysql_feeds/` (11 of 12
  `DUMP_ALLOWLIST` tables present). Not a blocker for `convert`, but the
  `rating` stage depends on `librate` — confirm the dump actually ships it.
- `genre.sql` seeds a separate `private` database; `base` currently runs only
  `createtable.sql` for the MultiLib DB. Add `genre.sql`/`private` if that
  database is actually used.
- For a guaranteed-consistent backup, stop MariaDB (`stop__MariaDB.bat`)
  before a real ingest run; a filesystem copy of a running InnoDB datadir can
  be captured mid-write.
