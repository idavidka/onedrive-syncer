# onedrive-syncer

An interactive Bash script to back up OneDrive to a local drive using [rclone](https://rclone.org/).

---

## Features

- **Interactive remote folder browser** — navigate your OneDrive tree and pick the folder to sync without editing any config
- **Pre-defined filter files** — create `filter*.txt` files to target specific folders or exclude large ones; the script lists them automatically at startup
- **Last-run memory** — saves your previous settings and offers to reuse them on the next run
- **Strategies** — Delta (fast-list, all files enumerated first) or Classic (starts transferring immediately)
- **Modes** — Mirror (sync, deletions allowed), Safe copy (download only), Force re-download (overwrite everything)
- **Loading spinner** while browsing remote folders
- **Error reporting** — non-zero rclone exit codes surface the last ERROR/CRITICAL log lines on screen

---

## Requirements

- macOS (or any Unix shell with Bash 4+)
- [rclone](https://rclone.org/) — `brew install rclone`
- An `onedrive` rclone remote configured (`rclone config`)

---

## Setup

```bash
# Clone the repo
git clone git@github.com:idavidka/onedrive-syncer.git
cd onedrive-syncer

# Make the script executable
chmod +x onedrive-sync.sh

# First run — rclone config will launch automatically if the remote is missing
./onedrive-sync.sh
```

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

- **Delta strategy (A)** is best for large OneDrive accounts — it lists everything first via the Graph delta API, then transfers without hitting rate limits mid-run. Expect 8–10 minutes of listing before transfers begin.
- **Classic strategy (B)** starts transferring immediately but may hit Microsoft rate limits on large accounts.
- Use **Safe copy (mode 2)** when in doubt — it never deletes local files.
- The interactive folder browser (option `i`) lets you drill into any remote folder without needing a filter file.
