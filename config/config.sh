#!/usr/bin/env bash
# =============================================================================
# config.sh — booktracker-import configuration
#
# Site-specific settings and local paths live here so that application logic
# (in lib/) stays generic.  Every value can be overridden via the environment
# or a gitignored .env file, so no private data needs to be committed.
#
# This file is sourced (it defines variables only; it performs no actions).
#
# Version:  0.1.3
# Updated:  2026-08-20 20:21 CDT
# =============================================================================

# --- Project paths ----------------------------------------------------------
# PROJECT_ROOT is derived from this file's location, so the scripts can be
# invoked from any working directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

DATA_DIR="${DATA_DIR:-$PROJECT_ROOT/data}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
COOKIE_JAR="${COOKIE_JAR:-$DATA_DIR/cookies.txt}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/booktracker-import.log}"
export DATA_DIR LOG_DIR COOKIE_JAR LOG_FILE

# --- Download root / staging area -------------------------------------------
# All Flibusta downloads — the .torrent files and the payloads they fetch —
# live under a single download root so the heavy multi-GB archives stay
# isolated from the small metadata/catalog updates.  Defaults to the
# "flibusta_snapshot" staging area under /Downloads (see README "Download
# folder structure").  Override via the environment or .env.
STAGING_DIR="${STAGING_DIR:-/Downloads/flibusta_snapshot}"
export STAGING_DIR

# .torrent files (downloaded by booktracker-import.sh, consumed by
# booktracker-stage.sh) live in the download root's torrents/ folder.
TORRENT_DIR="${TORRENT_DIR:-$STAGING_DIR/torrents}"
export TORRENT_DIR

# Subfolders of STAGING_DIR where staged payloads land.  Names are relative to
# STAGING_DIR so each can be relocated independently.
INPX_SUBDIR="${INPX_SUBDIR:-inpx}"                            # *.inpx catalog/index files
FLIBUSTA_SQL_SUBDIR="${FLIBUSTA_SQL_SUBDIR:-FlibustaSQL}"     # *.sql.gz database dumps
MYSQL_FEEDS_SUBDIR="${MYSQL_FEEDS_SUBDIR:-mysql_feeds}"       # decompressed *.sql
BOOK_ARCHIVES_SUBDIR="${BOOK_ARCHIVES_SUBDIR:-book_archives}" # monthly *.zip bundles
export INPX_SUBDIR FLIBUSTA_SQL_SUBDIR MYSQL_FEEDS_SUBDIR BOOK_ARCHIVES_SUBDIR

# --- Site -------------------------------------------------------------------
BOOKTRACKER_BASE_URL="${BOOKTRACKER_BASE_URL:-https://booktracker.org}"
export BOOKTRACKER_BASE_URL

# --- Credentials ------------------------------------------------------------
# Prefer environment variables; they may also be set in a gitignored .env file
# (sourced by bin/booktracker-import.sh).  Never commit real credentials.
BOOKTRACKER_USERNAME="${BOOKTRACKER_USERNAME:-}"
BOOKTRACKER_PASSWORD="${BOOKTRACKER_PASSWORD:-}"
export BOOKTRACKER_USERNAME BOOKTRACKER_PASSWORD

# --- HTTP -------------------------------------------------------------------
HTTP_USER_AGENT="${HTTP_USER_AGENT:-booktracker-import/0.1.3 (+https://booktracker.org)}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-15}"
CURL_MAX_TIME="${CURL_MAX_TIME:-120}"
export HTTP_USER_AGENT CURL_CONNECT_TIMEOUT CURL_MAX_TIME

# --- Logging ----------------------------------------------------------------
# One of: debug | info | warn | error
LOG_LEVEL="${LOG_LEVEL:-info}"
export LOG_LEVEL

# --- Flibusta forums / topics ----------------------------------------------
# Forum and topic ids change over time, so the scripts resolve them at runtime
# from the live site HTML rather than relying on fixed ids.  These are the
# stable text fragments used to identify each section/release (matched
# case-insensitively as literal substrings).
FORUM_FULL_COLLECTIONS_TITLE="${FORUM_FULL_COLLECTIONS_TITLE:-Полные сборки библиотеки Флибуста}"
FORUM_MONTHLY_TITLE="${FORUM_MONTHLY_TITLE:-Ежемесячные архивы (Флибуста)}"

TOPIC_INPX_ALL_TITLE="${TOPIC_INPX_ALL_TITLE:-расширенный}"                                # full/extended ("расширенный") INPX index
TOPIC_INPX_FB2_TITLE="${TOPIC_INPX_FB2_TITLE:-INPX для библиотеки Flibusta (только FB2)}" # FB2-only INPX index
TOPIC_DUMP_TITLE="${TOPIC_DUMP_TITLE:-Дампы базы данных библиотеки Флибуста}"

export FORUM_FULL_COLLECTIONS_TITLE FORUM_MONTHLY_TITLE
export TOPIC_INPX_ALL_TITLE TOPIC_INPX_FB2_TITLE TOPIC_DUMP_TITLE

# --- Monthly archives -------------------------------------------------------
# How many months back the "monthly" archives refer to (1 = previous month).
MONTH_OFFSET="${MONTH_OFFSET:-1}"
export MONTH_OFFSET

# --- Torrent file naming & retention ----------------------------------------
# Downloaded torrents are named `<prefix>-<type>-<stamp>.torrent`, where the
# stamp is the torrent creation date (INPX/dump) or the coverage month
# (monthly archives).  See README "Torrent files & retention".
TORRENT_NAME_PREFIX="${TORRENT_NAME_PREFIX:-flibusta}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$DATA_DIR/archive}"
ARCHIVE_TORRENTS="${ARCHIVE_TORRENTS:-1}"   # 1 = move superseded to archive, 0 = delete
TORRENT_RETENTION_DAYS="${TORRENT_RETENTION_DAYS:-0}"  # prune archive older than N days (0 = keep)
STATE_FILE="${STATE_FILE:-$DATA_DIR/downloads.tsv}"    # download state/history log
export TORRENT_NAME_PREFIX ARCHIVE_DIR ARCHIVE_TORRENTS TORRENT_RETENTION_DAYS STATE_FILE

# State file for payload extraction (booktracker-extract.sh). Same TSV is
# compatible with the older booktracker-stage.sh naming (staged.tsv).
STAGED_STATE_FILE="${STAGED_STATE_FILE:-$DATA_DIR/staged.tsv}"
export STAGED_STATE_FILE

# --- Behavior ---------------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"            # 1 = print actions, do not download
VERIFY_TORRENT="${VERIFY_TORRENT:-1}" # 1 = validate downloaded torrents
export DRY_RUN VERIFY_TORRENT

# --- Staging ----------------------------------------------------------------
# aria2c download options.  Releases can be tens of GB and take hours, so
# downloads retry indefinitely and print a progress summary periodically.
ARIA2C_SEED_TIME="${ARIA2C_SEED_TIME:-0}"                   # minutes to seed after download (0 = stop)
ARIA2C_MAX_TRIES="${ARIA2C_MAX_TRIES:-0}"                   # download attempts (0 = retry forever)
ARIA2C_SUMMARY_INTERVAL="${ARIA2C_SUMMARY_INTERVAL:-30}"    # aria2c progress-summary interval (seconds)
# Extra BitTorrent trackers (comma-separated) announced in addition to the
# torrent's own trackers.  Fallback public trackers find peers when the
# original tracker is down or stale but the torrent is public.  Empty = none.
ARIA2C_EXTRA_TRACKERS="${ARIA2C_EXTRA_TRACKERS:-udp://tracker.opentrackr.org:1337/announce,udp://open.stealth.si:80/announce,udp://tracker.torrent.eu.org:451/announce,udp://tracker.moeking.me:6969/announce,udp://explodie.org:6969/announce,udp://tracker.birkenfeld.org:6969/announce,udp://open.demonii.com:1337/announce,udp://exodus.desync.com:6969/announce,udp://tracker.openbittorrent.com:6969/announce,http://tracker.opentrackr.org:1337/announce}"
export ARIA2C_SEED_TIME ARIA2C_MAX_TRIES ARIA2C_SUMMARY_INTERVAL ARIA2C_EXTRA_TRACKERS

# Optional peer tuning (from Examples/*-torrent-extractor.sh).
ARIA2C_BT_MAX_PEERS="${ARIA2C_BT_MAX_PEERS:-150}"
ARIA2C_BT_MAX_OPEN_FILES="${ARIA2C_BT_MAX_OPEN_FILES:-200}"
# Empty = omit --peer-id-prefix (aria2c default).
ARIA2C_PEER_ID_PREFIX="${ARIA2C_PEER_ID_PREFIX:-}"
export ARIA2C_BT_MAX_PEERS ARIA2C_BT_MAX_OPEN_FILES ARIA2C_PEER_ID_PREFIX

# Which files to download from the database dump torrent.  Only these core
# library tables are fetched; the .zip attached archives, the annotations
# tables, lib.md5.txt.gz, and lib.reviews.sql.gz are skipped.
DUMP_ALLOWLIST="${DUMP_ALLOWLIST:-lib.libavtor.sql.gz lib.libavtorname.sql.gz lib.libbook.sql.gz lib.libfilename.sql.gz lib.libgenre.sql.gz lib.libgenrelist.sql.gz lib.libjoinedbooks.sql.gz lib.librate.sql.gz lib.librecs.sql.gz lib.libseq.sql.gz lib.libseqname.sql.gz lib.libtranslator.sql.gz}"
export DUMP_ALLOWLIST
