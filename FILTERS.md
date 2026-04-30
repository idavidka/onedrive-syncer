# rclone Filter Files

## Overview

There are 4 large folder groups on OneDrive that are managed separately due to their size.
Filters control what each rclone run will synchronize.

The script runs in either `rclone copy` (Safe) or `rclone sync` (Mirror) mode.
`rclone copy` only downloads, never deletes. `rclone sync` mirrors — but folders **excluded by the filter are left completely untouched**.

---

## filter-small.txt

**Purpose:** Syncs everything except the 4 large folder groups.

Excludes:
- `/Képek/**`
- `/Képek - régi/**`
- `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek/**`
- `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek új/**`

Use when: doing everyday sync (documents, misc files) without the large photo and register folders.

---

## filter-kepek.txt

**Purpose:** Selective sync inside `/Képek` — subfolders can be enabled one at a time.

- By default **every subfolder is excluded** (`-`)
- To enable a subfolder: change its two `-` lines to `+` before starting the run
- Only enabled subfolders will be downloaded

Use when: you want to download specific photo albums step by step.

---

## filter-kepek-regi.txt

**Purpose:** Same as `filter-kepek.txt`, but for the `/Képek - régi` folder.

---

## filter-anyakonyvek.txt

**Purpose:** Selective sync inside `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek`.

- By default **every subfolder is excluded** (`-`)
- To enable a subfolder: change its two `-` lines to `+` before starting the run

Use when: you want to download registers for specific localities one at a time.

---

## filter-anyakonyvek-uj.txt

**Purpose:** Same as `filter-anyakonyvek.txt`, but for the `Anyakönyvek új` folder.

---

## filter-kepek-all.txt

**Purpose:** Syncs the entire `/Képek` folder — all subfolders at once.

Use when: you want to download the whole photo library in one run.

---

## filter-kepek-regi-all.txt

**Purpose:** Syncs the entire `/Képek - régi` folder.

---

## filter-anyakonyvek-all.txt

**Purpose:** Syncs the entire `Anyakönyvek` folder — all subfolders at once.

---

## filter-anyakonyvek-uj-all.txt

**Purpose:** Syncs the entire `Anyakönyvek új` folder.

---

## No filter

Syncs the entire OneDrive including all 4 large folder groups.
Only use this if you truly want everything — the listing phase will be very slow.

---

## Technical notes

- All filters exclude `/Personal Vault/**` (OneDrive encrypted vault)
- Instead of `+ */` traversal, explicit path steps are used (e.g. `+ /Dokumentumok/`) — this is faster because rclone does not walk unrelated directories
- Filter files are written with NFC Unicode normalization (macOS uses NFD, OneDrive uses NFC)
- The per-subfolder filters (`filter-kepek.txt`, `filter-anyakonyvek.txt` etc.) have `+ /RootFolder/*` in the footer to allow any root-level files if present
