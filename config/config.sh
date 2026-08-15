#!/usr/bin/env bash
# =============================================================================
# booktracker-import — configuration
#
# Site-specific settings and local paths live here so that application logic
# (in lib/) stays generic.  Every value can be overridden via the environment
# or a gitignored .env file, so no private data needs to be committed.
#
# This file is sourced (it defines variables only; it performs no actions).
# =============================================================================

# --- Project paths ----------------------------------------------------------
# PROJECT_ROOT is derived from this file's location, so the scripts can be
# invoked from any working directory.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

DATA_DIR="${DATA_DIR:-$PROJECT_ROOT/data}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
TORRENT_DIR="${TORRENT_DIR:-$DATA_DIR/torrents}"
COOKIE_JAR="${COOKIE_JAR:-$DATA_DIR/cookies.txt}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/booktracker-import.log}"
export DATA_DIR LOG_DIR TORRENT_DIR COOKIE_JAR LOG_FILE

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
HTTP_USER_AGENT="${HTTP_USER_AGENT:-booktracker-import/0.1 (+https://booktracker.org)}"
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

TOPIC_INPX_ALL_TITLE="${TOPIC_INPX_ALL_TITLE:-inpx}"                  # full collection ("7z + FLibrary + inpx")
TOPIC_INPX_FB2_TITLE="${TOPIC_INPX_FB2_TITLE:-Дополнительные данные}" # FB2-only data release
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

# --- Behavior ---------------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"            # 1 = print actions, do not download
VERIFY_TORRENT="${VERIFY_TORRENT:-1}" # 1 = validate downloaded torrents
export DRY_RUN VERIFY_TORRENT
