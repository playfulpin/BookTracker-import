# Flibusta Archive Monthly Snapshot

This directory serves as the centralized storage and staging area for downloading, archiving, and indexing a local mirror of the Flibusta library. It organizes massive book zip archives, tracking indexes, and raw database dumps into a script-friendly layout.

---

## 📂 Directory Structure

```text
/Downloads                    # ROOT for all downloads
    └── flibusta_snapshot     # STAGIMG / collecting area for flibusta library downloads
       ├── book_archives      # Heavy, multi-book zip bundles containing raw text files
       ├── FlibustaSQL        # Fixed torrent download destination for compressed .gz files
       ├── inpx               # Small collection catalog and update index files
       ├── mysql_feeds        # Uncompressed .sql source files ready to be loaded into MySQL
       └── torrents           # torrent files to download everything from above.

```

---

## 📁 Folder Breakdown

### 📚 `book_archives/`
* **File Pattern:** `f.fb2-[start]-[end].zip`, `f.usr-[start]-[end].zip`
* **Purpose:** Houses the core library storage. These are large zip bundles holding thousands of individual compressed book files. This dedicated directory keeps heavy assets isolated from quick metadata backups.

### 📥 `FlibustaSQL/`
* **File Pattern:** `*.sql.gz`
* **Purpose:** This folder name is explicitly preserved to match the hardcoded file structure of the library's official torrent packages. It functions as the direct download target for the compressed database dumps.

### 📦 `inpx/`
* **File Pattern:** `fb2-yyyy-mm-dd.inpx`, `usr-yyyy-mm-dd.inpx`
* **Purpose:** Stores the library's metadata indices. These files act as the data catalog for offline catalogers and readers (such as MyHomeLib or TinyLib) to map titles, authors, and genres without extracting the massive book archives.

### 🔌 `mysql_feeds/`
* **File Pattern:** `*.sql`
* **Purpose:** The final staging area for database ingestion. Raw `.gz` files from `FlibustaSQL/` are extracted into this directory as plain-text SQL files. This provides a clean, dedicated space for files that are structurally verified and ready to be piped directly into your local MySQL instance.

### 🧲 `torrents/`
* **File Pattern:** `*.torrent`
* **Purpose:** The placeholder for torrent files.
---

## ⚡ Automation Quick Start

### 1. Extract to MySQL Feed Directory
To unpack the `.gz` dumps into your feed directory without deleting or modifying your seeding torrent files, run this command from the root folder:

```bash
gunzip -c FlibustaSQL/*.gz > mysql_feeds/flibusta_dump.sql
```

### 2. Load Data into MySQL
Once the text dump is prepared inside `mysql_feeds/`, execute the following to import the schema and data into your active MySQL instance:

```bash
mysql -u your_username -p your_database_name < mysql_feeds/flibusta_dump.sql
```
