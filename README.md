# Spruce

An original macOS utility that keeps a Mac clean, fast and safe — built for a personal
Mac mini (Apple Silicon, macOS 14 Sonoma or later). Its feature set and premium feel
are modelled on MacPaw's CleanMyMac, researched in depth in [`docs/research`](docs/research);
the name, design system ("Prism"), artwork and copy are our own. Spruce is not
affiliated with MacPaw.

## What it does

| Module | What you get |
|---|---|
| **Checkup** | One scan across Cleanup, Protection, Performance, Applications and Clutter; a tile per area, review sheets, one Run button. |
| **Cleanup** | User/system caches and logs, temp files, Xcode and developer junk, iOS backups and updates, broken preferences and login items, Mail attachment copies, Trash bins. |
| **Protection** | Malware & persistence scan (quick/balanced/deep) with signature and hash checks, real-time watch of launch agents/daemons, browser & macOS privacy traces, app permissions review/reset. |
| **Performance** | Maintenance tasks (free RAM, purgeable space, DNS, Spotlight, Mail, fonts…) behind one admin prompt, login & background items with reversible on/off, heavy consumers. |
| **Applications** | Full uninstaller with Reset, leftovers of removed apps, old installers, updater (Sparkle, App Store, Homebrew), extensions manager. |
| **Clutter** | Large & old files, duplicates (with smart selection), similar images, Downloads review. |
| **Space Map** | Interactive bubble/sunburst map of any disk or folder; drill down, select, remove. |
| **Cloud Storage** | See which iCloud Drive / File Provider files are stored locally and free local copies (never deletes from the cloud). |
| **Toolbox** | Every tool in one searchable hub with favourites, plus Shredder, Screen Cleaning mode, Empty Trash, Free Up RAM, Flush DNS. |
| **Activity** | Health score with recommendations, monthly stats and charts, timeline, operations log. |
| **Menu bar monitor** | Health, storage, memory, CPU, network, battery and connected devices, with alerts. |
| **Mac integration** | Finder Services (Uninstall / Map Folder / Shred with Spruce), drops on the Dock icon, `spruce://open/<module>` links, Dock menu, full main menu with keyboard shortcuts and a local Help window. |

## Safety model

* **Review before anything is removed.** Only items rated *safe* (regenerable caches,
  logs, temp files) are pre-selected; anything else needs your explicit choice.
* **Trash first.** Personal files, apps and leftovers go to the Trash. Permanent
  deletion only happens inside regenerable cache/log/temp/Trash locations.
* **A hard guard on every deletion** (`PathGuard`) refuses system folders, the Signed
  System Volume, volume roots, your home's top-level folders, keychains, iCloud Drive,
  password-manager/wallet data and other users' files — even if a scanner had a bug.
* **Never modifies app bundles** (no language-file or universal-binary stripping, which
  breaks code signatures).
* **No root daemon.** The few tasks that need administrator rights run as fixed,
  audited commands behind a single macOS password prompt. Root only acts in app,
  vendor, cache, log and temp locations, re-checks each item by inode inside the
  privileged script, and never changes file ownership; root-owned items go to a
  separate "Spruce Admin Trash" folder in the Trash.
* **Undo.** Items moved to the Trash are recorded, so a run can be put back while they
  are still there; the in-app Notification Center (the bell) keeps alerts you missed.
* **Ignore list** for paths, apps and individual items; **operations log** at
  `~/Library/Logs/Spruce/operations.log` (rotated at 5 MB).
* **No telemetry.** Network access is used only for update checks you start.

## Install on your Mac

### Option A — download the CI build

1. Open the repository's **Actions** tab, pick the latest green **Build** run on the
   `claude/brave-ptolemy-jnm0it` branch, and download the **Spruce-app** artifact.
2. Unzip it and drag **Spruce.app** to `/Applications`.
3. The build is ad-hoc signed (not notarized), so the first launch needs:
   right-click **Spruce.app → Open → Open**, or run
   `xattr -dr com.apple.quarantine /Applications/Spruce.app`.

### Option B — build it yourself

Requires Xcode 16 (or its Command Line Tools) on macOS 14+.

```bash
git clone https://github.com/MiTMi/CleanMyMac-s.git
cd CleanMyMac-s
./scripts/build-app.sh          # → build/Spruce.app (+ build/Spruce.zip)
open build/Spruce.app
```

**Tip — keep permissions across rebuilds.** macOS ties Full Disk Access to the app's
signature, and an ad-hoc signature changes on every build. Create a self-signed
code-signing certificate once (Keychain Access › Certificate Assistant › Create a
Certificate…, type *Code Signing*, e.g. named "Spruce Local") and build with:

```bash
SIGN_IDENTITY="Spruce Local" ./scripts/build-app.sh
```

### First launch

The onboarding guide walks you through:

1. **Full Disk Access** — System Settings › Privacy & Security › Full Disk Access →
   enable Spruce. Needed for Mail attachments, Safari data, iOS backups, the Trash and
   app containers. Spruce works without it, but those categories are skipped.
2. **Notifications** — for low-disk, threat and memory alerts.
3. **Menu bar monitor / launch at login** — optional.

Some actions ask for more: removing apps may need **App Management** permission
(Privacy & Security › App Management), managing legacy login items asks to control
**System Events**, and maintenance tasks ask for your administrator password.

## Development

```
Sources/SpruceCore   platform-independent logic (builds & tests on Linux)
Sources/SpruceMac    macOS system layer and module engines
Sources/Spruce       SwiftUI app: window, modules, menu bar monitor, settings
Tests/SpruceCoreTests unit tests
```

```bash
swift build && swift test         # macOS
./scripts/test-core-linux.sh      # SpruceCore on Linux via Docker
./scripts/build-app.sh            # release .app bundle
```

Engineering rules, contracts and safety requirements are in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). CI (GitHub Actions) builds and tests
on macOS 15 and Linux for every push and uploads the signed `.app`.
