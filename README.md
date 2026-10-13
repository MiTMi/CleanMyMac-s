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
| **Mac integration** | Finder Services (Uninstall / Map Folder / Find Clutter / Shred with Spruce), drops on the Dock icon and on module windows (apps, folders to map, Clutter locations), `spruce://open/<module>` links, Dock menu, full main menu with keyboard shortcuts and a local Help window. |

## Safety model

* **Review before anything is removed.** Only items rated *safe* (regenerable caches,
  logs, temp files) are pre-selected; anything else needs your explicit choice.
* **Open apps are quit first.** Caches of apps that are open are selected (as in
  CleanMyMac), but Clean asks to quit those apps first, and nothing of an app is removed
  while it's still open.
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
  are still there (Put Back All on the completion screen); the in-app Notification
  Center (the bell) keeps alerts you missed.
* **Ignore list** for paths, apps and individual items; **operations log** at
  `~/Library/Logs/Spruce/operations.log` (rotated at 5 MB).
* **No telemetry.** Network access is used only for app update checks (when you open the
  Updater; while update alerts are on, also in Checkup and once a day in the background)
  and for downloading an update you choose to install.

## Install on your Mac

### Option A — download the CI build

1. Open the repository's **Actions** tab, pick the latest green **Build** run on the
   `claude/brave-ptolemy-jnm0it` branch, and download the **Spruce-app** artifact.
2. Unzip it and drag **Spruce.app** to `/Applications`.
3. CI builds are ad-hoc signed (not notarized), so macOS blocks the first launch. Try to
   open it once, then go to **System Settings › Privacy & Security** and click **Open
   Anyway** (on macOS 14 you can also right-click **Spruce.app → Open**). Or run
   `xattr -dr com.apple.quarantine /Applications/Spruce.app` before opening it.

### Option B — build it yourself

Requires Xcode 16 (or its Command Line Tools) on macOS 14+.

```bash
git clone https://github.com/MiTMi/CleanMyMac-s.git
cd CleanMyMac-s
./scripts/build-app.sh          # → build/Spruce.app (+ build/Spruce.zip)
open build/Spruce.app
```

### Signed builds on your Mac (Apple Developer account)

With an Apple Developer membership, `build-app.sh` signs Spruce with your **Developer ID**
certificate, has Apple **notarize** it and **staples** the ticket. The result opens without
any Gatekeeper warning, and Full Disk Access and other permissions **survive every rebuild
and update** (macOS recognises the app by your Team ID). Nothing is uploaded except the app
itself, to Apple's notary service; your certificate never leaves your Mac.

**One-time setup** (about 10 minutes):

1. **Certificate** — Xcode › Settings › Accounts › select your team › **Manage
   Certificates…** › **+** › **Developer ID Application**. This needs the *Account
   Holder* role (an individual membership is). If you already have a Developer ID
   Application certificate on another Mac, export it there as a `.p12` and import it here
   instead of creating a new one (Apple allows only a few), and keep a backup of the
   `.p12`. Check it is there:
   ```bash
   security find-identity -v -p codesigning     # shows "Developer ID Application: …"
   ```
2. **Notarization credentials**, saved in your keychain under the name `spruce-notary`.
   Pick one:
   * **App-specific password** (simplest): create one at account.apple.com › Sign-In and
     Security › App-Specific Passwords, then run (it asks for that password):
     ```bash
     xcrun notarytool store-credentials spruce-notary --apple-id "you@example.com" --team-id "TEAMID"
     ```
   * **App Store Connect API key**: App Store Connect › Users and Access › Integrations ›
     App Store Connect API › **+** (role *Developer*), download the `.p8`, then:
     ```bash
     xcrun notarytool store-credentials spruce-notary --key ~/Downloads/AuthKey_KEYID.p8 --key-id KEYID --issuer ISSUER-ID
     ```
   Your Team ID is on developer.apple.com › Account › Membership details.

**Every build** after that:

```bash
./scripts/build-app.sh      # signs, notarizes (1–3 min), staples → build/Spruce.app
```

Then drag `build/Spruce.app` to `/Applications`, replacing the previous copy. The first
time, macOS asks whether `codesign` may use your signing key: choose **Always Allow**.

Signing and notarizing need an internet connection. Options: `NOTARIZE=0` signs with
your certificate but skips the timestamp and notarization (works offline; fine for builds
you only run yourself); `SIGN_IDENTITY=<SHA-1>` picks a certificate when you have several
— use the 40-character hash that `security find-identity -v -p codesigning` prints, since
a renewed certificate has the same name as the old one; `SIGN_IDENTITY=-` forces an
ad-hoc signature; `NOTARY_PROFILE=name` uses differently named credentials. Without a developer account
you can still keep permissions across rebuilds with a self-signed certificate (Keychain
Access › Certificate Assistant › Create a Certificate…, type *Code Signing*) and
`SIGN_IDENTITY="<its name>" ./scripts/build-app.sh` — it just won't be notarized.

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
