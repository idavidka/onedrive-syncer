# onedrive-syncer

An interactive Bash script (+ optional macOS menu bar app) to back up OneDrive to **any local destination** using [rclone](https://rclone.org/).

> **Why not just use the official OneDrive app?**  
> Microsoft's OneDrive client for macOS can only sync to your local user folder — it cannot write to an **external hard drive** or NAS. This tool has no such restriction: point it at any mounted path and it will sync there.

---

## Features

- **Sync to external drives** — back up directly to a USB/Thunderbolt drive or any mounted volume, bypassing the official client's location restriction
- **macOS menu bar app** — one-click sync from the menu bar with a live progress window (no Terminal needed after first setup)
- **Interactive remote folder browser** — navigate your OneDrive tree and pick the folder to sync without editing any config
- **Pre-defined filter files** — create `filter*.txt` files to target specific folders or exclude large ones; the script lists them automatically at startup
- **Last-run memory** — saves your previous settings and offers to reuse them on the next run
- **Strategies** — Delta (fast-list, all files enumerated first) or Classic (starts transferring immediately)
- **Modes** — Mirror (sync, deletions allowed), Safe copy (download only), Force re-download (overwrite everything)
- **Loading spinner** while browsing remote folders
- **Error reporting** — non-zero rclone exit codes surface the last ERROR/CRITICAL log lines on screen

---

## Requirements

- macOS 10.15 Catalina or later
- [rclone](https://rclone.org/) — `brew install rclone`
- An `onedrive` rclone remote configured (`rclone config`)
- Python 3 — already built into macOS (required only for the menu bar app)

---

## Setup

```bash
# Clone the repo
git clone git@github.com:idavidka/onedrive-syncer.git
cd onedrive-syncer

# Make the scripts executable
chmod +x onedrive-sync.sh menubar-app/setup.sh menubar-app/start.sh

# First run — rclone config will launch automatically if the remote is missing
./onedrive-sync.sh
```

---

## Menu bar app (macOS)

A lightweight macOS menu bar companion that lets you start a sync, watch live progress, and stop it — all without opening a Terminal.

![Menu bar app showing ☁ idle icon with Start, Configure, Progress, Log and Quit options]()

### Setup (one-time)

```bash
bash menubar-app/setup.sh
```

This installs `rumps` (and its dependencies) into `menubar-app/vendor/` — **no system-wide pip install, no Homebrew package needed**.

### Start

```bash
bash menubar-app/start.sh
```

A **☁** icon appears in the menu bar. Menu items:

| Item | Action |
|------|--------|
| **▶ Start (last settings)** | Runs sync using `last-run.conf`, shows live progress window |
| **⚙ Configure in Terminal** | Opens Terminal with the full interactive script |
| **📋 Show Progress** | Re-opens the progress window |
| **📄 Open Log** | Opens `rclone.log` in Console.app |
| **⏹ Stop Sync** | Terminates the running rclone process |
| **Quit** | Exits the menu bar app |

The icon changes state:

| Icon | Meaning |
|------|---------|
| ☁ | Idle / ready |
| ⟳ | Sync in progress |
| ✅ | Last sync succeeded |
| ❌ | Last sync failed |
| ⛔ | Stopped manually |

### Launch at login

1. Open **Automator** → New Document → **Application**
2. Add action: **Run Shell Script** → `bash /path/to/onedrive-syncer/menubar-app/start.sh`
3. Save as `OneDrive Sync.app` anywhere
4. System Settings → General → Login Items → add `OneDrive Sync.app`

---

## Usage

```bash
./onedrive-sync.sh
```

On every run the script will ask:

| Prompt | Description |
|--------|-------------|
| **Use previous settings?** | Reuse the last saved configuration |
| **Filter** | Choose a pre-defined filter file, the interactive browser, or no filter |
| **Strategy** | A = Delta (enumerate all first), B = Classic |
| **Mode** | 1 = Mirror, 2 = Safe copy, 3 = Force re-download |
| **Transfers / Checkers** | Parallelism tuning |
| **Destination folder** | Local path to sync into |

Settings are saved to `last-run.conf` after each run.

---

## Filter files

Filter files let you limit what rclone downloads. Any file named `filter*.txt` in the script directory will appear as a numbered option in the filter selection menu.

Filter files are **personal and gitignored** — create your own based on the examples below.

### How rclone filters work

- Lines starting with `+` **include** a path
- Lines starting with `-` **exclude** a path
- Rules are evaluated top-to-bottom; first match wins
- A final `- **` excludes everything not already matched (whitelist mode)
- Without a final `- **`, unmatched files are included (blacklist mode)
- To include a deeply nested folder you must explicitly include every parent directory

See the [rclone filter docs](https://rclone.org/filtering/) for full syntax.

---

### Example 1 — Sync only a top-level Photos folder

> Whitelist a single root folder and skip everything else.

**`filter-photos-only.txt`**
```
- /Personal Vault/**
+ /Photos/
+ /Photos/**
- **
```

---

### Example 2 — Sync everything except large folders

> Blacklist heavy folders you don't want right now; sync the rest.

**`filter-skip-large.txt`**
```
- /Personal Vault/**
- /Photos/
- /Photos/**
- /Photos - old/
- /Photos - old/**
- /Documents/FamilyTree/Documents/BirthRecords/
- /Documents/FamilyTree/Documents/BirthRecords/**
+ */
```

*(No `- **` at the end — everything not explicitly excluded is included.)*

---

### Example 3 — Sync a specific deeply nested subfolder

> To whitelist a deep path, every parent directory in the chain must be listed.

**`filter-birthrecords-only.txt`**
```
- /Personal Vault/**
+ /Documents/
+ /Documents/FamilyTree/
+ /Documents/FamilyTree/Documents/
+ /Documents/FamilyTree/Documents/BirthRecords/
+ /Documents/FamilyTree/Documents/BirthRecords/**
- **
```

---

## Configuration files

| File | Description | Gitignored |
|------|-------------|------------|
| `last-run.conf` | Saved settings from the previous run | Yes |
| `filter*.txt` | Your personal filter files | Yes |
| `filter-interactive.txt` | Temporary filter built by the interactive browser | Yes |
| `rclone.log` | rclone output log | Yes |
| `menubar-app/vendor/` | Python dependencies installed by `setup.sh` | Yes |

---

## Logging

Every run appends a header block to `rclone.log`:

```
================================================================
Started:    2026-05-01 09:35:54
Filter:     [Interactive] /Documents/FamilyTree/BirthRecords
Dest:       /Volumes/My Passport/OneDrive
Strategy:   B
Mode:       1 (Mirror/sync)
Transfers:  8
Checkers:   16
================================================================
```

---

## Tips

- **External drives** — set the destination to any mounted volume, e.g. `/Volumes/My Passport/OneDrive`. The menu bar app will warn you if the drive is not plugged in before starting.
- **Delta strategy (A)** is best for large OneDrive accounts — it lists everything first via the Graph delta API, then transfers without hitting rate limits mid-run. Expect 8–10 minutes of listing before transfers begin.
- **Classic strategy (B)** starts transferring immediately but may hit Microsoft rate limits on large accounts.
- Use **Safe copy (mode 2)** when in doubt — it never deletes local files.
- The interactive folder browser (option `i`) lets you drill into any remote folder without needing a filter file.
