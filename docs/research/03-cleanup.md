# 03 — Cleanup / System Junk module: every category, concrete macOS paths, safety rules

> Track: Cleanup / System Junk. Target: an original, functionally equivalent cleaner for an Apple-Silicon Mac mini on macOS 14 Sonoma, 15 Sequoia and 26 Tahoe. Date of research: 2026-10-12.
> Companion reports: `01-overview.md` (product map, editions, helper architecture) and `02-smart-care.md` (one-click scan, selection tiers). This file goes deeper on **what each Cleanup category targets on disk and how to do it safely**.

---

## 0. Method, evidence labels, caveats

**Sandbox limits during this session (important for weighing the evidence).**
- `macpaw.com`, `cleanmymac.com`, the review sites (TidBITS, Macworld, 9to5Mac, etc.) and Apple Support were **unreachable**. The egress proxy refused the CONNECT, and WebFetch returned DNS errors.
- The shared web-search budget for this workflow ran out after my first two searches.
- So I relied on these sources:
  1. **MacPaw primary material I could read directly:**
     - the **CleanMyMac 3 in-app Help book** (MacPaw-authored, mirrored on GitHub);
     - MacPaw's own **CleanMyMac CLI** repository, README and wiki.
  2. **MacPaw knowledge-base facts verified by the sibling research tracks** (reports 01/02). I cite those with the original MacPaw URL.
  3. One **search-result excerpt** of the current (5.x) System Junk KB page.
  4. **Source code I read directly** from open-source cleaners and clones: tw93/Mole, mac-cleanup-py, mac-cleanup-sh, Tencent Lemon, Monolingual, Pearcleaner, DevCleaner for Xcode, MacSai, MacOptimizer.
  5. **Apple developer documentation** (JSON endpoints on developer.apple.com, read directly).

**Labels used on every claim**

| Label | Meaning |
|---|---|
| **VERIFIED-V** | Vendor-primary MacPaw material that I read in this session (CMM3 Help book, MacPaw CLI repo/wiki). |
| **VERIFIED-K** | MacPaw knowledge-base fact verified by a sibling track (reports 01/02). The original MacPaw URL is cited. I did not re-fetch it, because macpaw.com was blocked here. |
| **VERIFIED-S** | Taken from a search-engine excerpt of a MacPaw page (URL given). |
| **VERIFIED-OSS** | Read directly in open-source code or docs (URL given). Shows how *other* tools do it, not how CleanMyMac does it. |
| **VERIFIED-APPLE** | Read in Apple developer documentation in this session. The fact-check pass also used TN2206 and the WWDC22/23 privacy session transcripts. |
| **VERIFIED-APPLE-OSS** | (added in fact-check) Read in Apple's own open-source code at github.com/apple-oss-distributions (Security, diskdev_cmds). |
| **INFERRED** | My reasoning, platform knowledge or recommendation for our implementation. Everything without a VERIFIED tag is INFERRED. Items marked "verify on device" should be tested on the Mac mini before shipping. |

**Short source keys used below** (full URLs in §14):
- `[CMM3-Help/1..7]`: CleanMyMac 3 Help topics. 1 Smart Cleanup, 2 System Junk, 3 Photo Junk, 4 Mail Attachments, 5 iTunes Junk, 6 Trash Bins, 7 Large & Old Files.
- `[CLI]`: MacPaw/cleanmymac-cli README and wiki.
- `[Mole]`: tw93/Mole.
- `[Lemon]`: Tencent lemon-cleaner `garbage1_en.xml`.
- `[Mono]`: Monolingual.
- `[Pear]`: Pearcleaner.
- `[DevC]`: DevCleaner for Xcode.
- `[MCpy]`/`[MCsh]`: mac-cleanup-py / mac-cleanup-sh.
- `[MacSai]`, `[MacOpt]`: two open-source CleanMyMac-style clones.

---

## 1. Executive summary (decisions for our build)

1. **Category set to implement.** Use the union across versions, with a modern safety policy. VERIFIED-V/K, details in §2.
   - **System Junk groups:**
     - User Cache Files, System Cache Files
     - User Log Files, System Log Files
     - Language Files, Universal Binaries
     - Xcode Junk, Development Junk
     - Document Versions
     - Broken Preferences, Broken Login Items
     - iOS Device Backups
     - Old Updates, Unused Disk Images
     - Downloads (broken/incomplete)
     - Deleted Users
     - Temporary Files
   - **Separate Cleanup sections:** Mail Attachments, Trash Bins, and "iTunes/Music & iOS junk". Photo Junk is legacy; offer it only as the low-risk subset.
2. **CleanMyMac's safety model** has four parts:
   - (a) a **Safety Database** of rules and exceptions consulted on every scan (VERIFIED-V `[CMM3-Help/1,2]`; VERIFIED-K safety-database KB);
   - (b) **Smart Selection**, which auto-checks only regenerable items, with documented per-category rules;
   - (c) an **Ignore List** (Control-click → "Add to Ignore List"; Settings tab);
   - (d) a **privileged helper** for root-owned locations.
   We replicate all four. Our Safety DB is a versioned JSON rules file (schema in §4.1).
3. **Default selection (VERIFIED where cited).**
   - **CMM3:** "most" System Junk is auto-added, but **Leftovers** are never default, and **Xcode Module Cache and Archives** are never automatic `[CMM3-Help/2]`.
   - **Document Versions:** the earliest and latest are never offered; only versions saved less than 4 h apart are auto-selected, keeping the latest in each range `[CMM3-Help/2]`.
   - **iOS backups:** the latest backup is never auto-selected `[CMM3-Help/5]`.
   - **Photo Junk:** only Photos Cache and Faces Cache are smart-selected `[CMM3-Help/3]`.
   - **Mail:** only recoverable, unmodified attachments `[CMM3-Help/4]`.
   - **Trash:** everything `[CMM3-Help/6]`.
   - **CMM 5.x:** "all types" are auto-selected except listed exceptions, with **Spotify and Gradle caches** named as user-cache exceptions. VERIFIED-S: macpaw.com/support/cleanmymac/knowledgebase/system-junk.
4. **Our deviations for macOS 14–26 (INFERRED, strongly recommended):**
   - **Language Files and Universal Binaries default to unchecked.** (corrected) The original reason given here, that these edits break code-signature seals, is **wrong** for the normal case:
     - Apple's TN2206 says that removing files from `.lproj` folders inside `Contents/Resources` does not invalidate the signature, and neither does removing one architecture's slice from a universal binary. Adding or changing files does invalidate it. VERIFIED-APPLE: https://developer.apple.com/library/archive/technotes/tn2206/_index.html
     - `codesign`'s default resource rules mark `*.lproj/` content `optional`, "except for Base.lproj which really isn't optional at all". VERIFIED-APPLE-OSS (Security `bundlediskrep.cpp`).
     - Monolingual's seal blocklist **skips `optional` entries**, so it blocks only resources that must be present (VERIFIED-OSS `[Mono]`, §5.6).
     - The reasons to keep both groups unchecked are different:
       - Since macOS 13, changing another team's app needs the *App Management* permission, and root alone does not grant it.
       - Sparkle delta updates break.
       - The savings disappear at the next app update.
       - Plug-in hosts may need Intel slices.
       - A buggy implementation (one that touches `Base.lproj` or non-`.lproj` files) *would* break the seal.
   - **iOS backups, Xcode Archives, Deleted Users and Document Versions outside the 4-h rule** are review-only.
   - **Caches of running apps are skipped.** Deleting live SQLite caches can make helpers loop writing to unlinked files (VERIFIED-OSS `[Mole]` SECURITY_AUDIT).
5. **Deletion semantics.**
   - **Junk is unlinked permanently.** This is INFERRED for CleanMyMac. The CLI says `--force` "removes detected items immediately" (VERIFIED-V `[CLI]`).
   - **Trash Bins "Empty"** removes files "in an ordinary way", with an optional zero-overwrite "Remove Securely" (VERIFIED-V `[CMM3-Help/6]`). We should **not** offer secure erase: it is meaningless on APFS/SSD. INFERRED.
   - **Personal-ish items** (backups, disk images, downloads) should go to the Trash, or ask first. INFERRED.
6. **Sizes.**
   - Report **allocated** size (`totalFileAllocatedSize`).
   - De-duplicate hard links.
   - Flag APFS clones (`mayShareFileContent` / `fileContentIdentifier`, macOS 11+, VERIFIED-APPLE). Deleting a clone may free nothing.
   - Measure real "freed" space by sampling volume free space before and after. Local Time Machine snapshots can keep deleted blocks pinned.
7. **Permissions needed.**
   - **Full Disk Access:** Mail, Safari, MobileSync, `~/.Trash` listing, other apps' containers (Sonoma "App Data" protection).
   - **Admin helper** (SMAppService daemon, VERIFIED-APPLE): `/Library/Caches`, `/Library/Logs`, `/private/var/log`, Deleted Users, root-owned app bundles, Document Versions DB.
   - **App Management** TCC: bundle modification (language/binaries). VERIFIED-APPLE (WWDC22 session 10096): macOS blocks a change to an app made by a process from a different team and not allowed by the app's `NSUpdateSecurityPolicy`, and notifies the user that "an app wants to manage other apps". A 2026 field report says the block also applies to root processes (VERIFIED-OSS, §4.9). (corrected: added evidence)
   - Details in §4.9.

---

## 2. Category structure across product generations

### 2.1 CleanMyMac 3 (2015–2018): modules and System Junk sub-types (VERIFIED-V `[CMM3-Help/1,2]`)

**Cleaning modules:**
- Smart Cleanup
- System Junk
- Photo Junk
- Mail Attachments
- iTunes Junk
- Trash Bins
- Large & Old Files

These were followed by Uninstaller, Maintenance, Privacy, Extensions, Shredder, Dashboard and Menu `[CMM3-Help/1]`.

**System Junk sub-types (alphabetical in the help, paraphrased):**

| Sub-type (exact label) | What it targets (paraphrase) | Default |
|---|---|---|
| Broken Login Items | Login-item links left after the app or service was removed | auto |
| Broken Preferences | Corrupted preference files that cause misbehaviour | auto |
| Document Versions | Auto/manual saved versions of documents | auto by the 4-h rule; never earliest/latest |
| Development Junk | Supporting files created during installation/configuration that become useless | auto |
| iOS Photo Cache | Photos cached on the Mac after syncing photos to iOS devices | auto |
| Language Files | Unused app localizations | auto (CMM3) |
| Leftovers | Junk left by uninstalled apps | **not** selected by default |
| macOS Localizations | OS language files | auto (CMM3; impossible on macOS 11+ sealed system volume, see §5.7) |
| Old Updates | Old versions of app updates that apps did not clean up | auto |
| System Cache Files | Caches of system apps | auto |
| System Log Files | Logs of system apps/services, useful only for debugging | auto |
| Universal Binaries | Extra architecture code; "your Mac only needs one copy" | auto (CMM3) |
| User Cache Files | App caches | auto |
| User Log Files | App logs, rarely used, worthless when old | auto |
| Xcode Junk | Intermediate build info and project index; **Module Cache and Archives not removed automatically** | auto except those |

Sources: the labels and descriptions in all rows come from `[CMM3-Help/2]`. The help adds that CleanMyMac automatically adds *most* System Junk items to the cleanup list, and any item can be deselected `[CMM3-Help/2]`.

(corrected) I re-read topic-2 during fact-checking. It gives explicit defaults for only three cases:
- Leftovers: not offered by default.
- Xcode Module Cache and Archives: not removed automatically.
- Document Versions: the 4-hour rule.

The "auto" entries in the Default column for the other rows are an inference from "most". The Language Files and Universal Binaries entries rest on the TidBITS review below, not on the help. VERIFIED-V: https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-2.html

Third-party corroboration: a TidBITS review of CMM3 says Language Files and Universal Binaries were pre-selected. VERIFIED-K (cited in 02-smart-care.md: https://tidbits.com/2015/08/28/save-space-and-uninstall-apps-with-cleanmymac-3/).

**Other CMM3 cleanup modules** `[CMM3-Help/3–6]`:
- **Photo Junk:**
  - RAW Originals, replaced by their JPEGs;
  - Faces Cache;
  - Photos Cache;
  - iCloud Local Copies.
  - Only Photos Cache and Faces Cache are smart-selected. A **Change Library** button picks the library. "Ignore RAW photos" lives in Preferences → Ignore List → Photo Junk.
- **Mail Attachments:** local copies of attachments opened or viewed in Mail. Smart-selects only recoverable copies, ignoring ones the user modified. Results can be grouped by *Mail account*, *Last view date* or *File kind*.
- **iTunes Junk:**
  - iOS Applications;
  - iOS Device Backups (latest never auto);
  - iOS Software Updates;
  - iTunes Broken Downloads;
  - iTunes Cache (album artwork).
  - Smart-selects "broken and iOS-related files you no longer need".
- **Trash Bins:**
  - Local Mail Trash;
  - Aperture Trash, iPhoto Trash, Photos Trash;
  - Gemini Duplicates;
  - Startup Drive Trash (includes items removed from iCloud);
  - External Drive Trash (one per external drive).
  - All items are auto-selected. **Empty**, or **Remove Securely**, which overwrites with zeroes.

### 2.2 CleanMyMac X (4.x, 2018–2024)

- **Cleanup sidebar section:** System Junk, Photo Junk (not in the App Store edition), Mail Attachments, iTunes Junk, Trash Bins. VERIFIED-K (02-smart-care.md §3; https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features).
- **Smart-selection rules documented in the X System Junk KB.** VERIFIED-K: https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk.
  - Document Versions: the 4-h rule; never earliest/latest.
  - iOS backups: most recent never auto.
  - **Downloads:** Safari, only broken downloads; Slack, broken downloads plus files at least 1 month old.
- **Mail attachments.** Only re-downloadable attachments are smart-selected. User-edited ones are labelled **"changed by user"** and left unselected. VERIFIED-K: https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments.
- **The X System Junk group list** as mirrored by an open-source "SystemJunkReplicaView" clone, with English and Chinese strings that match MacPaw's localisation. VERIFIED-OSS `[MacOpt]`; secondary evidence only.
  - Unused Disk Images, User Cache Files, Downloads
  - Universal Binaries, System Cache Files
  - User Log Files, System Log Files
  - Deleted Users, iOS Device Backups
  - Old Updates, Broken Login Items, Broken Preferences
  - Xcode Junk, Document Versions, Language Files
  - The MacSai clone uses almost the same list, plus Broken/Incomplete Downloads (VERIFIED-OSS `[MacSai]` `ScanCategory.swift`).
- **Scheduled cleanup (CleanMyMac Business, discontinued).** Selectable junk types: System log files, Broken login items, User cache files, Language files, Broken preferences, Xcode junk, Mail attachments, Trash bins. VERIFIED-K: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation. MacPaw considered these safe to run unattended. Note that **iOS backups and Document Versions are absent** from that list. INFERRED: MacPaw judged the listed types safe to clean unattended.

### 2.3 CleanMyMac (5.x, Oct 2024 → 5.7.x in 2026)

- **Cleanup module contents.** VERIFIED-K (01-overview.md §5.2; https://macpaw.com/support/cleanmymac/knowledgebase/missing-features):
  - **System Junk groups:**
    - User Cache Files, System Cache Files
    - User Log Files, System Log Files
    - Language Files, Universal Binaries, Xcode Junk
    - Document Versions, iOS Device Backups
    - Broken Preferences, Broken Login Items, Deleted Users
  - **Mail Attachments.**
  - **Trash Bins.** Its categories: Mail, Photos, Gemini Duplicates, Startup drive (incl. items removed from iCloud), External drives (one per drive). VERIFIED-K: https://macpaw.com/support/cleanmymac/knowledgebase/trash-bins.
- **App Store edition limits.**
  - "Broken login items" is listed as not available from the App Store. VERIFIED-S (system-junk KB excerpt).
  - Smart Care in the App Store edition lacks Broken Login Items and Deleted Users, and has no Photos/Gemini trash categories. VERIFIED-K (missing-features / feature-plans KB).
- **Where X's other groups went (INFERRED from the 5.x module map in 01-overview.md):**
  - Unused Disk Images and installers → Applications › *Installation files*, and My Clutter › *Downloads* (old DMGs, archives).
  - Leftovers → Applications › *Leftovers*.
  - Old Updates → probably merged into caches or installers.
  - X's Downloads group → My Clutter › Downloads.
  - Fact-check: still INFERRED. The replica that lists these groups is explicitly a CleanMyMac **X** reconstruction (§3, §5.12).
- **Smart Care scope.** It runs only the "basics" of Cleanup: system junk (logs, caches, broken login items "and other"), mail attachments and Trash bins. One reviewer saw 6.1 GB in Smart Care versus 7.1 GB in the full module. VERIFIED-K (02-smart-care.md; Smart Care KB; softwarehow review).
- **Smart Insights (Tahoe + Apple Intelligence).** Puts an on-device "what is this / is it safe" explainer button on unfamiliar Cleanup items. VERIFIED-K (01-overview.md; https://macpaw.com/news/introducing-smart-insights).

### 2.4 CleanMyMac CLI (2026 public beta) — the clearest look at MacPaw's current rule engine (VERIFIED-V `[CLI]`)

- **Commands:**
  - `clean` covers all categories. Re-checked during fact-checking: the README says it runs "system junk, dev-tools junk, and trash". The CLI is v1.0.0 public beta, needs macOS 11+, installs as a Homebrew cask (`cmm` is an alias), and also offers `optimize` / `optimize ram` / `optimize purgeable`. VERIFIED-V https://github.com/MacPaw/cleanmymac-cli
  - `clean junk` covers "system and Xcode-related junk": user logs, DerivedData, Device Support, Module Cache, Documentation Cache.
  - `clean dev` covers Homebrew, npm, Yarn, pnpm, pip, Poetry, uv, Cargo, Go, CocoaPods, Docker, VS Code, JetBrains, Maven, Gradle, Bun, Deno, mise.
  - `clean ai` covers junk from AI tools; the mock-up shows a "Claude" row.
  - `clean trash` covers "the system and mounted-volume Trash".
- **Scan-result screen** groups results into **System Junk / Dev Tools / AI Junk**, each with a size and a drill-down arrow. In the README mock-up, AI Junk is shown **unchecked** while the other two are checked, which suggests AI Junk is off by default. The footer reads "N items selected (size)".
- **Completion screen:** "Cleanup complete!", per-category ✓ rows with sizes, total space recovered, and the number of items removed.
- **Rules are shared with the desktop app.** The wiki says detection is "based on cleanup rules shared with CleanMyMac". Protected system locations are excluded. Nothing is deleted until the user confirms. `--force` skips confirmation.
- **Ignore list:** `ignore add|list|remove <path>`. Ignored paths stay out of `clean`, `purge` and `analyze`.
- **`purge`:** the default roots are `~/Projects ~/Code ~/dev ~/GitHub ~/Workspace`. Artifacts older than 7 days are pre-selected; newer ones are shown unchecked with a "recent" tag.

### 2.5 Our category tree (INFERRED; IDs used in code and in the Safety DB)

```
cleanup
├─ systemJunk
│  ├─ userCaches            (User Cache Files)
│  ├─ systemCaches          (System Cache Files)          [helper]
│  ├─ userLogs              (User Log Files)
│  ├─ systemLogs            (System Log Files)            [helper]
│  ├─ tempFiles             (Temporary Files)
│  ├─ languageFiles         (Language Files)              [helper, AppMgmt]  default OFF
│  ├─ universalBinaries     (Universal Binaries)          [helper, AppMgmt]  default OFF
│  ├─ xcodeJunk             (Xcode Junk)
│  ├─ devJunk               (Development Junk / Dev Tools)
│  ├─ aiJunk                (AI Tools Junk)                default OFF (CLI parity)
│  ├─ documentVersions      (Document Versions)           [helper, FDA]
│  ├─ brokenPreferences     (Broken Preferences)
│  ├─ brokenLoginItems      (Broken Login Items)          [helper for /Library]
│  ├─ oldUpdates            (Old Updates)
│  ├─ unusedDiskImages      (Unused Disk Images)          default OFF
│  ├─ brokenDownloads       (Downloads: incomplete/broken)
│  ├─ iosBackups            (iOS Device Backups)          [FDA] default OFF except old/archived
│  ├─ iosSoftware           (iOS Software Updates & iOS apps & iOS photo cache)
│  ├─ mediaJunk             (Music/TV/Podcasts caches & broken downloads)
│  └─ deletedUsers          (Deleted Users)               [helper] default OFF
├─ mailAttachments                                        [FDA]
├─ trashBins (per-trash rows: Startup Drive, each external volume, Mail, Photos)
└─ photoJunk (legacy-compatible, caches only)             default OFF
```

---

## 3. UI flow and labels (what to mirror, in our own words)

**VERIFIED-V (CMM3 Help) interaction vocabulary for System Junk and the other cleanup modules** `[CMM3-Help/2–7]`:
- **Scan** starts the analysis. The result shows a total and a per-module amount.
- **Review Details**, or **Review Files**, opens the list.
- Rows are grouped by type, with group checkboxes and item checkboxes.
- **Deselect All / Select All** sits in the upper-left.
- Results can be sorted with the **"Sort by" menu** and filtered with a **search field** (✕ clears it).
- A **magnifier icon** on hover reveals the item in Finder; a **Quick Look icon** previews it.
- **Action ▸ Rescan** discards the results.
- **Control-click → Add to Ignore List**.
- The primary button is **Clean** (Trash Bins uses **Empty**), and the completion screen has **Start Over**.
- Large & Old Files offers **Move to Folder / Move to Trash / Remove Immediately / Remove Securely**.

**Preferences scoping semantics (VERIFIED-V `[CMM3-Help/1,2]`).** On the Smart Cleanup tab of Preferences:
- Deselecting a *submodule* (e.g. User Cache Files) excludes it from **both** the standalone System Junk scan and Smart Cleanup.
- Deselecting the *whole module* excludes it only from Smart Cleanup.

X and 5.x renamed this tab to **Scanning** (VERIFIED-K 01-overview.md §10).

**X-era labels seen in the replica clone** (VERIFIED-OSS `[MacOpt]`, secondary). (corrected) This heading used to say "5.x". The clone's own doc comment calls it a "Pixel-led reconstruction of CleanMyMac X's System Junk module", so these are **CleanMyMac X** labels. 5.x may word them differently. Its group order is: Unused Disk Images, User Cache Files, Downloads, Universal Binaries, System Cache Files, User Log Files, System Log Files, Deleted Users, iOS Device Backups, Old Updates, Broken Login Items, Broken Preferences, Xcode Junk, Document Versions, Language Files. Source: https://github.com/ddlmanus/MacOptimizer/blob/main/AppUninstaller/SystemJunkReplicaView.swift. Labels:
- "Scan Complete", "Smart Selection", "Includes"
- "Review Details", "Deselect All / Select All"
- "Sort by Size/Name"
- "Cleanup Complete", "Review Remaining", "Start Over"
- an alert titled "Some Files Require Admin Privileges"

**Our UI spec (INFERRED):**
1. **Landing:** module title, one-line promise, three benefit bullets, big **Scan** button. A banner appears when FDA or the helper is missing.
2. **Scanning:** an animated orb with the current location ("Scanning ~/Library/Caches…", throttled to about 10 Hz) and a running total. **Stop** is available.
3. **Results summary:** a large "X GB of junk found" figure, a "Smart Selection: Y GB selected" caption, and an "Includes" list of the top groups with sizes. Buttons: **Review Details** and **Clean**.
4. **Review (two-pane):**
   - **Left pane:** groups with tri-state checkboxes, sizes and an info (i) popover. The popover explains what the group is, why it is safe, and whether it needs the helper or FDA.
   - **Right pane:** items showing icon, name, middle-truncated path, size and last modified date, plus a **reason badge** on unchecked items: `in use`, `recent`, `latest backup`, `changed by user`, `protected`, `needs admin`, `needs Full Disk Access`, `code-signed (seal)`.
   - **Toolbar:** Select All / Deselect All, Sort by (Size / Name / Date), search.
   - **Context menu:** Reveal in Finder, Quick Look, Copy Path, **Ignore**, and "Explain" (an optional on-device LLM, like Smart Insights).
5. **Confirm sheet**, shown only when the selection includes irreversible personal items: backups, disk images, deleted users, document versions, archives.
6. **Cleaning:** progress per group. Root work is delegated to the helper.
7. **Completion:** "Cleanup complete", the freed amount (measured), per-group ✓ rows, a **Review Remaining** link for skipped or failed items with reasons, and **Start Over**.

---

## 4. Engine-wide rules (apply to every category)

### 4.1 The "Safety Database" — what CleanMyMac says, and our schema

- **VERIFIED-V:** CleanMyMac "includes a built-in Safety Database" that keeps vital items from being selected by default `[CMM3-Help/1,2]`.
- **VERIFIED-K:** the Safety Database is a list of items, rules and exceptions consulted on every scan.
  - Example exception: Spotify keeps offline music inside its cache folder.
  - The Shredder refuses critical folders.
  - Source: https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database (via 02-smart-care.md §4).
- **VERIFIED-S:** the 5.x KB names Spotify and Gradle caches as exceptions to auto-selection.
- **Where Spotify actually keeps offline music (corrected).** Open-source cleaners agree on the split:
  - offline downloads go by default to `~/Library/Application Support/Spotify/PersistentCache/Storage`;
  - the streaming cache is `~/Library/Caches/com.spotify.client/Data`;
  - old updater archives sit in `…/Spotify/PersistentCache/Update/*.tbz`.
  - Sources (VERIFIED-OSS): https://github.com/JonnyBurger/make-space/blob/master/docs/spotify-cache.md, https://github.com/jithin-sabu/purge-app (`DeletionSafetyPolicy.swift`), https://github.com/SpotX-Official/SpotX-Bash (`spotx.sh`).
  - MacPaw's "offline music lives in its cache folder" fits this, because Spotify calls the folder `PersistentCache`. Protect **both** paths. The `Update/*.tbz` archives are a safe Old Updates candidate when Spotify is not running (INFERRED).

**Prior art for a rules file:**
- Tencent Lemon ships its rules as XML (VERIFIED-OSS `[Lemon]`):
  - `<filters>` with id, column (`filename`/`filepath`/`bundleid`/`filesize`/`time`/`app`), relation (`is`/`begin with`/`contains`/`match`/`greater`) and action (`include`/`exclude`);
  - `<category>` → `<item recommend="YES|NO">` → `<action type="file|dir|language|appcache|archive|mail">` → `<path type="abs|special" level="0|1|-1" value="…">`;
  - items are combined with boolean filter expressions such as `(7+68+69+72)`.
- Mole uses a default whitelist, a hard "safety whitelist" that always merges in, critical-root deny rules, and per-bundle protection lists (VERIFIED-OSS `[Mole]` `lib/core/base.sh`, `file_ops.sh`, `app_protection.sh`).

**Our Safety DB (INFERRED):** a JSON file bundled with the app and versioned (it could later be signed and updated online).

```json
{
  "schema": 1,
  "version": "2026.10.12",
  "denyRoots": ["/", "/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db",
                "/private/var/root", "/private/var/audit", "/Library/Apple", "/Library/Extensions",
                "/Library/Keychains", "/Applications/Safari.app", "/Applications/Finder.app",
                "~/Library/Keychains", "~/Library/Mobile Documents", "~/Library/Messages/Attachments",
                "~/Library/Group Containers/group.com.apple.notes", "~/Library/Application Support/AddressBook",
                "/private/var/db/receipts", "/private/var/vm"],
  "protectedGlobs": [
    {"glob": "~/Library/Caches/com.spotify.client/**", "reason": "Vendor exception (5.x KB); streaming cache"},
    {"glob": "~/Library/Application Support/Spotify/PersistentCache/Storage/**", "reason": "Default Spotify offline-music store (corrected)"},
    {"glob": "~/.gradle/caches/modules-2/**",           "reason": "Dependency store"},
    {"glob": "~/Library/Caches/CloudKit*/**",            "reason": "iCloud sync state"},
    {"glob": "~/Library/Caches/com.apple.FontRegistry*", "reason": "Font rendering"},
    {"glob": "~/Library/Caches/com.apple.Spotlight*",    "reason": "Search"},
    {"glob": "~/Library/Caches/com.apple.nsurlsessiond/**", "reason": "In-flight background downloads"}
  ],
  "rules": [
    {
      "id": "systemJunk.userCaches",
      "roots": ["~/Library/Caches"],
      "enumerate": "children",               // each top-level child is one row
      "selection": "auto",                   // auto | review | never
      "skipIfOwnerRunning": true,            // bundle-id owner match
      "skipIfOpen": true,                    // lsof / proc_pidfdinfo probe
      "minAgeHours": 1,
      "privilege": "user",                   // user | helper
      "needsFDA": false,
      "deleteMode": "permanent",             // permanent | trash | api
      "exclude": ["com.spotify.client", "JetBrains*", "ms-playwright*", "com.apple.appstoreagent",
                  "Metadata", "com.apple.iconservices*", "com.apple.akd"],
      "review":  ["Google/Chrome", "com.apple.Safari"]   // shown unchecked
    }
  ]
}
```

The app and the helper each load the same DB. The helper **re-validates every path against `denyRoots`, `protectedGlobs` and its own compiled-in list**. It never trusts the app's list alone. Lesson from the Talos CVEs, see 02-smart-care.md §9.

### 4.2 Selection tiers

| Tier | Meaning | Examples |
|---|---|---|
| **auto** | Regenerable or already discarded; checked by default | user caches (minus exceptions, minus running owners), logs older than 7 days, Trash contents, `.ipsw`, DerivedData when Xcode is closed, Mail Downloads not modified, broken downloads, broken prefs, broken launch agents |
| **review** | Shown **unchecked**, needs a deliberate tick | Language Files, Universal Binaries, iOS backups (latest per device), Xcode Archives, Device Support newest version, Document Versions outside the rule, Deleted Users, Unused Disk Images, AI-tool data, `/private/var/db/diagnostics`, Photos library caches |
| **never** | Never listed (or listed as information only) | `denyRoots`, `protectedGlobs`, ignore-list items, SIP/SSV paths, other users' trash |

### 4.3 Running-app and open-file gates (INFERRED, based on Mole VERIFIED-OSS)

- **Owner mapping.** Map each candidate to an owner bundle ID:
  - a reverse-DNS folder name under `~/Library/Caches`, `Containers`, `Group Containers`, `HTTPStorages`, `Saved Application State`;
  - a known app-name folder (e.g. `Google/Chrome` → `com.google.Chrome`).
- **Running check.** Use `NSWorkspace.shared.runningApplications` plus `proc_listallpids`/`proc_pidpath` for helpers and agents. If the owner is running, skip with reason `in use`.
- **Tri-state rule.** "Could not determine" counts as running. Mole's owner probe is tri-state and denies on unknown (VERIFIED-OSS Mole SECURITY_AUDIT).
- **SQLite families.** For `*.db`, `*.sqlite`, `*-wal` and `*-shm` files, check every family member for open handles before deleting any of them (Mole, same source).
- **Re-check immediately before unlinking.** Apps launch between scan and clean. Watch `NSWorkspace.didLaunchApplicationNotification` during Review and flip affected rows to `in use`.

### 4.4 Age thresholds (INFERRED defaults; Mole's constants are VERIFIED-OSS `[Mole]` `base.sh`)

**Mole's constants:**
- temp files: 7 days
- logs: 7 days
- crash reports: 7 days
- saved state: 30 days
- Mail downloads: 30 days and ≥ 5 MB
- rebuildable GPU caches: 1 day
- orphaned data: 30 days

**MacPaw's own constants:**
- CLI `purge` pre-selects only artifacts older than 7 days (VERIFIED-V).
- Document Versions uses 4 h clusters (VERIFIED-V).
- Slack downloads ≥ 1 month (VERIFIED-K).

**Ours:**

| Category | Auto-select if older than |
|---|---|
| Caches | 1 h (avoid files being written right now) |
| Logs and crash reports | 7 d |
| Temp (`T/`, `/tmp`) | 3–7 d and not open |
| Broken downloads | 1 d and not open |
| Mail Downloads | 30 d *or* any age if unmodified (CMM selects all recoverable) |
| Unused disk images | 7 d |
| Saved state | 30 d |

### 4.5 Ignore List

- **VERIFIED-V:** Control-click → "Add to Ignore List". Preferences → Ignore List has per-module sections, e.g. Photo Junk "Ignore RAW photos" and Uninstaller "Ignore system applications" `[CMM3-Help/2,3,8]`.
- **VERIFIED-K (5.x):** the Ignore List categories are:
  - Cleanup (System Junk, Mail Attachments);
  - Protection (Malware Removal);
  - Applications (Uninstaller, Updater);
  - My Clutter (Duplicates, Similar Images, Downloads).
  - Source: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety.
- **VERIFIED-V (CLI):** path-based; applies to clean, purge and analyze.
- **Ours (INFERRED):**
  - **Storage.** Entries are `{scope: "cleanup.systemJunk"|…, kind: path|prefix|glob|bundleID, value, addedAt}`. Paths are stored canonicalised: `realpath`, with case-folding applied to the *comparison* on case-insensitive APFS.
  - **When applied.** Before results are shown (filter) **and** again at deletion time.
  - **Matching.** Prefix matches respect path-component boundaries. Monolingual fixed exactly this bug: "/bin" must not exclude "/binary" (VERIFIED-OSS `[Mono]` `HelperContext.swift`).

### 4.6 Hard deny list (never touch)

- **Mole's `_mole_is_critical_deletion_path`** (VERIFIED-OSS `[Mole]` `lib/core/file_ops.sh`):
  - `/`, `/bin`, `/sbin`, `/usr`, `/dev`, `/System`;
  - `/Library` itself, `/Library/Apple`, the `/Library/Application Support` root, `/Library/Extensions`, `/Library/Keychains`;
  - the `/Applications` root, `Finder.app`, `Safari.app`;
  - `/Volumes`, the `/opt` and `/opt/homebrew` roots, `/Users`, `/Users/Shared`, `/Users/Guest`, any `/Users/<name>` home root;
  - the `/private`, `/private/tmp`, `/private/var`, `/private/var/tmp` and `/private/var/folders` *roots*, and `/etc`;
  - `/var/db` and `/var/audit` trees, `/var/root`.
  - It also compares inode identity to defeat case aliases like `/SYSTEM` on case-insensitive APFS.
- **Mole's always-merged "safety whitelist"** (VERIFIED-OSS `base.sh`):
  - `~/Library/Caches/com.apple.FontRegistry*`, `com.apple.spotlight*`/`Spotlight*`, `CloudKit*`;
  - `~/Library/Caches/pypoetry/virtualenvs*`;
  - the R `renv` cache;
  - Finder metadata.
  - **Default** (user-removable) whitelist: Playwright browsers, Gradle caches and daemon, Ollama models, Surge, JetBrains caches and support, tealdeer pages, `com.apple.finder` cache, `~/Library/Mobile Documents*`.
- **Mole's protected categories** (VERIFIED-OSS SECURITY_AUDIT):
  - keychains and password managers;
  - VPN/proxy tools;
  - AI tools' app data;
  - OrbStack live data;
  - browser history and cookies;
  - Apple-owned group containers (e.g. `group.com.apple.notes`);
  - Time Machine data during backup;
  - `com.apple.*` LaunchAgents/Daemons;
  - user-owned `~/Library/LaunchAgents` configuration;
  - iCloud `Mobile Documents`;
  - `~/Library/Messages/Attachments`.
- **Mole's protected cache paths** (VERIFIED-OSS `app_protection.sh`):
  - System Settings, Control Center, Finder and Dock caches (blank-panel bug);
  - CoreAudio caches (audio loss on Intel);
  - NetworkExtension state;
  - Bluetooth/Wi-Fi ByHost prefs;
  - wallpaper and aerial assets;
  - Shortcuts sandbox cache;
  - Google Clearcut queue;
  - the `iLok` license manager cache under `/private/var/folders/*/C/`;
  - EDR/endpoint-security agents' cache and temp folders (deleting them trips tamper alarms).
- **Lemon's exclusions** (VERIFIED-OSS `[Lemon]`):
  - `com.apple.dock`, `com.apple.appstore`, `com.apple.dock.iconcache`, `com.apple.FontRegistry`, `com.apple.LaunchServices-*`, `com.apple.Safari`, `com.apple.Spotlight`, `com.apple.IconServices`;
  - `~/Library/Caches/Metadata/`;
  - `/Library/Caches/Desktop Pictures/`, `/Library/Caches/ColorSync/`, anything containing `Aerial`;
  - Logic Pro paths;
  - `com.apple.appstoreagent`. Their XML comment notes that cleaning it on macOS 15 hid the pending-updates list.
- **Platform (INFERRED, platform knowledge):**
  - The **Signed System Volume** (macOS 11+) makes `/System` read-only and sealed, so `/System/Library/Caches` and `/System/Applications/*.app` cannot be modified.
  - **SIP** protects paths that carry the `com.apple.rootless` xattr. Monolingual checks this xattr and skips such paths (VERIFIED-OSS `[Mono]` `Helper.swift`).

### 4.7 How sizes are computed

- **API.** Per file, use `URLResourceKey.totalFileAllocatedSizeKey`: "the total allocated size of the file… includes the size of any file metadata" (VERIFIED-APPLE). Fall back to `fileAllocatedSizeKey`, then `fileSizeKey`. Directory sizes are the sum over a `FileManager.enumerator` with prefetched keys `[.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .linkCountKey, .fileResourceIdentifierKey, .mayShareFileContentKey]`. The enumerator **does not follow symlinks**.
- **Hard links.** If `linkCount > 1`, count a `(volume, fileResourceIdentifier)` pair only once. *Freed* space for a hard-linked file is zero unless every link is removed (INFERRED).
- **APFS clones.** `mayShareFileContentKey` says whether "cloned files and their original files may share data blocks", and `fileContentIdentifierKey` "identifies a file's content data stream" (VERIFIED-APPLE, macOS 11+). Show a "may be a clone, actual savings may be lower" badge when it is true. Mole uses physical size (`du -skP` / `st_blocks`) and avoids mixing logical sizes into totals (VERIFIED-OSS `get_path_size_kb`).
- **App bundles.** Use `mdls -name kMDItemPhysicalSize` as Mole does, or the same enumerator.
- **Bounded scanning.** Each root gets a time budget (Mole caps every `du`/`find` with timeouts). If a budget is exceeded, report "size unknown" rather than blocking (VERIFIED-OSS).
- **Freed vs found.**
  - Measure `volumeAvailableCapacityForImportantUsage` (VERIFIED-APPLE, "available capacity for storing important resources") and `volumeAvailableCapacity` before and after.
  - Explain the gap if **local Time Machine snapshots** still hold the deleted blocks. `tmutil listlocalsnapshots /`; thinning belongs to the Performance module.
  - Also explain purgeable space (INFERRED).

### 4.8 Deletion method per category

| Mode | Used for | Implementation (INFERRED) |
|---|---|---|
| **permanent** | caches, logs, temp, broken prefs, broken downloads, ipsw, DerivedData, trash contents | `unlinkat`/`removefile(3)` (with `REMOVEFILE_RECURSIVE`) or `FileManager.removeItem`; through the helper for root-owned files. Clear `uchg`/`schg` flags only on trash items (as Finder asks) |
| **trash** | iOS backups (optional), unused disk images, downloads, deleted-user DMGs, archives | `FileManager.trashItem(at:resultingItemURL:)` ("Moves an item to the trash", VERIFIED-APPLE). Warn that moving to Trash frees **nothing** until the Trash is emptied (same volume = rename) |
| **api** | Document Versions → `NSFileVersion.remove()` or `removeOtherVersionsOfItem(at:)` inside a coordinated write (VERIFIED-APPLE; re-checked: Apple says `remove()` must not be called on the current version and should run "in a block passed to a file coordinator's write operation"; use plain write coordination, not `.forDeleting`, because the document itself is not being deleted); simulators → `xcrun simctl delete unavailable`; Homebrew → `brew cleanup`; npm → `npm cache clean --force`; Mail trash → Mail scripting; login items → System Events / `launchctl bootout` | per §5 |
| **modify-in-place** | language files (remove `*.lproj` dirs), universal binaries (`lipo -thin`) | via the helper, on a **staged copy plus verify plus atomic swap** (§5.6, §5.8). (corrected) Neither operation needs re-signing when done correctly (TN2206); `codesign --verify` is a check, not a repair step |

**No secure erase.** CleanMyMac 3 offered zero-overwrite "Remove Securely" (VERIFIED-V `[CMM3-Help/6,7]`), and the Shredder was removed in 5.0 (VERIFIED-K). On APFS/SSD, overwriting does not guarantee erasure. INFERRED: skip it, or label it honestly.

### 4.9 Privileges by category

| Need | Why | Categories |
|---|---|---|
| **Full Disk Access** | TCC-protected locations | Mail Attachments (`~/Library/Mail`, Mail container), Safari caches, iOS backups (`MobileSync`), Trash listing (Mole notes that `~/.Trash` cannot be listed without FDA, VERIFIED-OSS `user.sh`), Messages caches, Photos library, Document Versions, and other apps' containers. **macOS 14+ App-Data protection** (corrected: now VERIFIED-APPLE, WWDC23 session 10053): Sonoma asks permission when an app accesses a file in another developer's app data container. The grant lasts only until the app quits. Apps already granted Full Disk Access get no extra prompt. So a cleaner should require FDA rather than rely on per-access prompts |
| **Admin helper** (`SMAppService.daemon(plistName:)`: plist in `Contents/Library/LaunchDaemons`, macOS 13+, VERIFIED-APPLE) | root-owned files | `/Library/Caches`, `/Library/Logs`, `/private/var/log`, `/private/var/db/diagnostics`, root's `/private/var/folders/zz/...`, `/Library/LaunchAgents|LaunchDaemons` broken items, Deleted Users, root-owned app bundles (language/binaries), Document Versions DB, `/Volumes/*/.Trashes/<other uid>` |
| **App Management** TCC (macOS 13+; TCC service `kTCCServiceSystemPolicyAppBundles`) | modifying or deleting other apps' bundles | Language Files, Universal Binaries, Old Updates inside bundles (Chrome old versions). (corrected: upgraded from INFERRED)<br>• VERIFIED-APPLE (WWDC22 10096): Ventura blocks app changes made by a process from another team that the app's `NSUpdateSecurityPolicy` does not allow. Clicking the notification takes the user to System Settings to "allow an app to update and modify other apps". Gatekeeper also checks the integrity of *all* notarized apps, not only quarantined ones, and blocks one at first launch if its signature is no longer valid.<br>• VERIFIED-OSS (field report, Sep 2026): TCC charged a failed app-bundle write to a root process under `kTCCServiceSystemPolicyAppBundles`; "root authentication alone does not supply that permission" (https://github.com/Reedtrullz/Vifty/blob/main/docs/reviews/2026-09-15-app-management-replacement.md).<br>• INFERRED: our SMAppService daemon will be charged to our app, so the user must turn on App Management for **our app**. There is no API to check it beforehand (another 2026 project notes "macOS exposes no probe"), so attempt the change and treat `EPERM` as "needs App Management" |
| **Automation** (Apple Events) | scripting other apps | System Events login items; Mail trash; Finder (if we ever use "empty trash") |

The vendor's helper is installed on first need via an admin-password prompt. It deletes system files, removes launch agents and clears system caches. VERIFIED-K (01-overview.md §8; cleanmymac-agent / background-items KB).

### 4.10 Path-safety rules (INFERRED; Mole and Monolingual VERIFIED-OSS)

- **Path validation.** Reject paths that are:
  - empty or relative;
  - contain a `..` component or control characters;
  - symlinks when deleting as root;
  - under a symlinked *ancestor* (canonicalise the parent and re-run the deny checks).
  Mole does all of these (SECURITY_AUDIT §"Symlink and Path Traversal").
- **Never follow symlinks while enumerating.** Monolingual "never removes a symbolic link, whatever it resolves to", because root ownership changes follow links (VERIFIED-OSS).
- **TOCTOU.** Record `(dev, ino, mtime)` at scan time. Re-stat right before deletion and skip on mismatch. Mole re-validates at the "sink" (VERIFIED-OSS).
- **Helper API is intent-level only** (`cleanSystemCaches(ids:)`, never `remove(path:)`). The helper re-derives paths from IDs and its own rules, and verifies the caller's code-signing requirement. This is the lesson of Talos 2018 (CVE-2018-4032…4042), VERIFIED-K 02-smart-care.md §9.

### 4.11 Logging and "undo"

- **Operation log.** Write an append-only log with timestamp, category, path, size, mode and result, for example `~/Library/Logs/<OurApp>/operations.log`. Mole writes `~/Library/Logs/mole/operations.log` and protects it from its own cleaner (VERIFIED-OSS).
- **Undo.** Only Trash-mode items can be undone ("Put Back"). Permanent junk deletion is explained upfront.
- **Partial failures.** Show them as "Review Remaining" with a reason. Vendor users have reported "This item was cleaned partially", VERIFIED-K 02-smart-care.md.

---

## 5. Category-by-category specification

Each entry below covers: **What** · **Paths** · **Detection** · **Default** · **Exclusions** · **Privilege** · **Delete mode** · **Edge cases**. The catalog in §6 lists every path once, with a safety rating.

### 5.1 User Cache Files (`systemJunk.userCaches`)

- **What.**
  - Vendor wording: app caches meant to speed things up, which pile up over time (VERIFIED-V `[CMM3-Help/2]`).
  - 5.x auto-selects them, except that **Spotify and Gradle caches** are named exceptions (VERIFIED-S system-junk KB). Spotify keeps offline music in its cache (VERIFIED-K safety-database KB). (corrected) On disk, the offline store is `~/Library/Application Support/Spotify/PersistentCache/Storage`, not `~/Library/Caches` (VERIFIED-OSS, §4.1). Our Application Support rules must exclude it too.
- **Paths.**
  - `~/Library/Caches/*`: one row per top-level child.
  - `~/Library/Containers/<bundle-id>/Data/Library/Caches/*`: sandboxed apps.
  - `~/Library/Group Containers/<group-id>/Library/Caches/*`.
  - Chromium/Electron app caches: `~/Library/Application Support/<App>/{Cache,Code Cache,GPUCache,DawnGraphiteCache,DawnWebGPUCache,ShaderCache}` and browser profiles `…/Default/{Cache,Code Cache,GPUCache}`. Mole cleans these per profile; mac-cleanup-py does so for Teams, Obsidian and the EA app (VERIFIED-OSS).
  - WebKit networking caches, e.g. `~/Library/Caches/com.apple.WebKit.Networking/*`, and Safari's `~/Library/Caches/com.apple.Safari/*` (VERIFIED-OSS Mole/Lemon).
  - Firefox: `~/Library/Caches/Firefox/Profiles/<p>/cache2`. Lemon targets `~/Library/Caches/Firefox/` (VERIFIED-OSS).
  - **Mole's per-app list** (≈170 `~/Library/Caches` entries plus ≈30 container entries, VERIFIED-OSS; sample):
    - `~/Library/Caches/Google/Chrome/*`, `com.microsoft.edgemac/*`, `BraveSoftware/Brave-Browser/*`;
    - `com.spotify.client/*` (we treat this as an exception);
    - `us.zoom.xos/*`, `ru.keepcoder.Telegram/*`, `net.whatsapp.WhatsApp/*`, `com.microsoft.teams2/*`;
    - `com.figma.Desktop/*`, `notion.id/*`, `md.obsidian/*`, `com.openai.chat/*`, `com.anthropic.claudefordesktop/*`;
    - `Homebrew/downloads/*`, `CocoaPods/*`, `pip`, `Yarn/*`;
    - `com.apple.Music`, `com.apple.podcasts`, `com.apple.TV/*`, `GeoServices/*` (Maps tiles), `com.apple.QuickLook.thumbnailcache`, `com.apple.helpd/*`, `com.apple.parsecd/*`, `com.apple.iWork.*`;
    - Apple container caches: `~/Library/Containers/com.apple.AppStore/Data/Library/Caches/*`, `com.apple.mediaanalysisd/...`, `com.apple.wallpaper.agent/...`, `com.apple.stocks/...`, `com.apple.CoreDevice.CoreDeviceService/...`.
- **Detection.**
  1. Enumerate children.
  2. Resolve the owner bundle ID.
  3. Apply the Safety DB exceptions.
  4. Apply the running-owner and open-file gates (§4.3) and the age gate (≥ 1 h).
  5. Size each row.
- **Default.** Auto (checked), except exceptions (`never`) and these review-only rows (unchecked):
  - very large caches that may hold user-relevant content: browsers' `Service Worker/CacheStorage`, Adobe media caches, DaVinci CacheClip, Steam shader caches;
  - caches of apps not installed (they belong to Leftovers).
- **Exclusions (built-in).**
  - Spotify, Gradle, `CloudKit*`, `com.apple.FontRegistry*`, `com.apple.Spotlight*`.
  - `com.apple.nsurlsessiond` (in-flight background downloads; INFERRED).
  - `com.apple.appstoreagent` (Lemon note: breaks the pending-updates list on macOS 15).
  - `Metadata`, `com.apple.iconservices*`, `com.apple.dock.iconcache`.
  - JetBrains, Playwright, pypoetry `virtualenvs`, R `renv`.
  - EDR vendors.
  - Containers of `com.apple.Settings*`, `com.apple.systempreferences*`, `com.apple.controlcenter*` (Mole).
  - Our own app's caches.
  - Sources: VERIFIED-S/K/OSS as cited in §4.6; INFERRED where noted.
- **Privilege.** User. FDA or App-Data consent is needed for other apps' containers on macOS 14+ (INFERRED).
- **Delete mode.** Permanent. Delete the *contents* of each cache folder and keep the folder itself. Some apps crash if their cache root vanishes (INFERRED; Mole targets `dir/*`, VERIFIED-OSS).
- **Edge cases.**
  - Huge folders: bound the enumeration time.
  - Cache folders that are symlinks: skip.
  - Dropbox, Google Drive and OneDrive file-provider caches are content caches that can force re-download. Mark them review (`~/Library/Application Support/Google/DriveFS/*/content_cache` is in mac-cleanup-py, VERIFIED-OSS).
  - `~/Library/Caches/com.apple.akd` (Apple ID): review only.

### 5.2 System Cache Files (`systemJunk.systemCaches`)

- **What.** Caches generated by system apps and services (VERIFIED-V `[CMM3-Help/2]`).
- **Paths.**
  - `/Library/Caches/*`: root-owned and shared.
    - Lemon's "System Caches" rule scans `/Library/Caches` at depth 1, excluding Spotlight, Desktop Pictures, ColorSync and Aerial (VERIFIED-OSS `[Lemon]`).
    - (corrected) Mole deletes only **files** under `/Library/Caches`: `*.cache` and `*.tmp` older than `MOLE_TEMP_FILE_AGE_DAYS` (7), and `*.log` older than `MOLE_LOG_AGE_DAYS` (7). It also removes `/Library/Caches/com.apple.iconservices.store` outright as a rebuildable cache. VERIFIED-OSS `system.sh`, re-read 2026-10-12.
  - Per-user Darwin cache dir `/private/var/folders/<2ch>/<hash>/C/`. Find it with `getconf DARWIN_USER_CACHE_DIR`, as Mole's `mole_darwin_user_cache_root` does (VERIFIED-OSS `base.sh`). In Swift, call `confstr(_CS_DARWIN_USER_CACHE_DIR, …)` directly, and use `_CS_DARWIN_USER_TEMP_DIR` for `T/`. Apple's own daemons do this (VERIFIED-APPLE-OSS: apple-oss-distributions/Security `OSX/utilities/SecFileLocations.c`, `supd/main.m`). Mole's GPU-cache sweep in `system.sh` instead walks every user's `/private/var/folders/*/*/C/` as root and excludes `T/`.
    - It holds `com.apple.QuickLook.thumbnailcache`, Metal shader caches (`*/com.apple.metal`, `com.apple.metalfe`, `com.apple.gpuarchiver`), `mds`, `com.apple.LaunchServices-*` and others.
    - Mole cleans **only** rebuildable GPU/Metal caches older than 1 day, and protects EDR/iLok/Native Instruments/Avid entries (VERIFIED-OSS).
  - Root-owned Darwin dirs (`/private/var/folders/zz/...`): only specific rebuildable items. Mole removes aborted Aerial wallpaper downloads `CFNetworkDownload_*.tmp` inside `com.apple.idleassetsd`'s temp dir, older than the temp window. Those can reach hundreds of GB and show up in "System Data" (VERIFIED-OSS `system.sh`, issue #1253).
  - **Not** `/System/Library/Caches`: the Signed System Volume makes it immutable. `[MCsh]` naively lists it (VERIFIED-OSS), which is an anti-pattern.
- **Default.** Auto for `/Library/Caches/*` children older than 7 days, minus exclusions. Review for Darwin `C/` subfolders other than the known-rebuildable GPU and QuickLook caches.
- **QuickLook.** Prefer the API reset `qlmanage -r cache` over deleting files (INFERRED).
- **Privilege.** The helper for `/Library/Caches` and root `var/folders`. The user's own `C/` dir is user-owned.
- **Edge cases.**
  - `/Library/Caches/com.apple.iconservices.store`: deleting it blanks icons until rebuilt. Mark risky; never auto. (Mole does delete it as rebuildable, so this is our own conservative choice, INFERRED.)
  - `com.apple.amsengagementd`-style caches regenerate instantly, so they save little.
  - Never delete the `C` dir itself.

### 5.3 User Log Files (`systemJunk.userLogs`)

- **What.** Logs of user apps, rarely used and worthless when old (VERIFIED-V `[CMM3-Help/2]`).
- **Paths.**
  - `~/Library/Logs/*`. Mole keeps the `DiagnosticReports` directory itself and sweeps its old reports. It refuses symlinked roots (VERIFIED-OSS `user.sh`).
  - `~/Library/Logs/DiagnosticReports/*.{ips,crash,diag,spin,hang,cpu_resource.diag}`.
  - (added) `~/Library/DiagnosticReports/*`, if present. Mole cleans this second location with the same log routine (`_clean_user_log_directory "$HOME/Library/DiagnosticReports"`, VERIFIED-OSS `user.sh`). Since issue #1689 it keeps the `~/Library/Logs/DiagnosticReports` folder itself and cleans only its contents.
  - `~/Library/Containers/*/Data/Library/Logs/*`, e.g. the Mail logs path `~/Library/Containers/com.apple.mail/Data/Library/Logs/Mail/*` (VERIFIED-OSS `[MCpy]`/`[MCsh]`).
  - `~/Library/Application Support/CrashReporter/*` (VERIFIED-OSS `[MacOpt]`).
  - App-specific: `~/Library/Logs/JetBrains/*`, `~/Library/Logs/CoreSimulator/*`, `~/Library/Logs/Claude/*`, `~/Library/Logs/Zed/*` (VERIFIED-OSS Mole/mac-cleanup).
- **Default.** Auto for files older than 7 days (Mole uses 7 d for logs and crash reports, VERIFIED-OSS). Newer files are shown unchecked with the reason `recent`.
- **Exclusions.** Our own log dir. Any log whose owning process holds it open (append-mode files). We truncate nothing.
- **Privilege.** User. **Delete mode.** Permanent.

### 5.4 System Log Files (`systemJunk.systemLogs`)

- **What.** Logs of system apps and services, useful only for debugging (VERIFIED-V `[CMM3-Help/2]`).
- **Paths.** Lemon's "System Logs" item (VERIFIED-OSS):
  - `/Library/Logs/` at depth 1, files > 10 KB, skipping the `DiagnosticReports` dir;
  - `/Library/Logs/DiagnosticReports`;
  - `/private/var/log/asl/`;
  - `/private/var/log/DiagnosticMessages/`;
  - `/private/var/log/cups/` (`access_log*`, `page_log*`, `error_log*`);
  - `/private/var/log/` files matching `*.out`, `*.log.*` or ending in `log`;
  - `/private/var/db/diagnostics`.
- **Mole's extra system-log areas, all older than 7 days** (VERIFIED-OSS `system.sh`):
  - `/Library/Logs/DiagnosticReports/*`;
  - `/private/var/log/*.log`, `*.gz`, `*.asl` (corrected: Mole's pattern set is all three);
  - `/Library/Logs/Adobe`, `/Library/Logs/CreativeCloud`, `adobegc.log`;
  - `/private/var/db/diagnostics/*`, `/private/var/db/DiagnosticPipeline/*`, `/private/var/db/powerlog/*` (skipping the active database);
  - `/private/var/db/reportmemoryexception/MemoryLimitViolations/*` (30 days).
- **Default (ours).**
  - Auto: `/Library/Logs/**` (except the DiagnosticReports dir itself), rotated `/private/var/log/*.{gz,bz2}` and `*.log.N`, `*.log` older than 7 d, `/private/var/log/asl/*.asl` (legacy), and CUPS logs.
  - **Review:** `/private/var/db/diagnostics` (the unified log store, tracev3). `logd` manages its own size and TTL. Deleting files loses history and the space returns quickly. Prefer advising `sudo log erase --all` only on explicit request (INFERRED).
    - `sudo log erase --ttl` removes only time-to-live content and is gentler.
    - Both forms are catalogued as an attacker "indicator removal / clear macOS logs" technique. Atomic Red Team ships them as a test, currently in `atomics/T1685.006/`, which older references cite as T1070.002 (https://github.com/redcanaryco/atomic-red-team). Threat-hunting keyword lists flag `sudo log erase --all`. EDR products may alert when our helper runs these commands, so **never run them unattended** (VERIFIED-OSS for the catalogue entries; the alerting risk is INFERRED).
  - **Never:** `/private/var/db/uuidtext` (needed to decode logs) and `install.log` (useful for history; review at most).
- **Privilege.** Helper (root). **Delete mode.** Permanent.
- **Edge cases.** `newsyslog`/`aslmanager` may hold the active `system.log` and `wifi.log` open. Skip open files.

### 5.5 Temporary Files (`systemJunk.tempFiles`)

- **What.** Not a named CleanMyMac group in the KB lists I could see. The task brief asks for it, and CMM3 maintenance scripts covered "deletion of temporary files" (VERIFIED-V `[CMM3-Help/9]`).
- **Paths.**
  - Per-user `$TMPDIR` = `getconf DARWIN_USER_TEMP_DIR` → `/private/var/folders/<2ch>/<hash>/T/`.
  - `/private/tmp` (= `/tmp`).
  - `/private/var/tmp`.
- **Policy.** Mole deliberately does **not** sweep generic `/private/tmp` or `/private/var/tmp`, because "age and a bounded scan do not prove third-party runtime state is disposable" (VERIFIED-OSS `system.sh` comment).
- **Ours (INFERRED):** only regular files that are:
  - owned by the current user;
  - older than 3 days (atime, mtime **and ctime**, matching Apple's `tmp_cleaner`);
  - not open (lsof/proc probe);
  - not sockets, FIFOs or lock files;
  - not inside a directory whose name matches a running bundle ID.
  Directories are reported as review.
- **Default.** Auto only for the narrow file set above.
- **Context.**
  - macOS's `dirhelper` already purges old items in the per-user `T/` at boot (INFERRED platform knowledge; not re-verified).
  - (added) macOS also ships its own `/tmp` janitor. Apple's open-source `diskdev_cmds/tmp_cleaner/tmp_cleaner` deletes files under `/tmp` that are older than **3 days on all three timestamps** (`-atime +3 -mtime +3 -ctime +3`), then removes empty directories older than 3 days. It stays on local file systems (`find -dx … -fstype local`) and ignores X11/ICE lock and socket names and `quota.user`/`quota.group`. VERIFIED-APPLE-OSS: https://github.com/apple-oss-distributions/diskdev_cmds/blob/main/tmp_cleaner/tmp_cleaner
  - So sweeping `/tmp` gains little. If we keep the T2 rule, use the same triple-timestamp test, not mtime alone.
- **Privilege.** User for `T/` and own files in `/tmp`. Helper only for root-owned `/private/var/tmp` items (review).

### 5.6 Language Files (`systemJunk.languageFiles`)

- **What.** Localizations bundled with apps that the user doesn't use. MacPaw describes them as safe to remove to save space (VERIFIED-V `[CMM3-Help/2]`). Pre-selected in CMM3 (VERIFIED-K, TidBITS).
- **Paths.**
  - `/Applications/**/*.app/Contents/Resources/*.lproj` and `~/Applications/**/*.app/...`.
  - The same inside nested bundles: `Contents/Frameworks/*.framework/Versions/*/Resources/*.lproj`, plugins, helpers.
  - Never under `/System` (sealed volume).
  - Monolingual's default roots are `/Applications` and `/Library`, and it always excludes `/System` and `/bin` (VERIFIED-OSS `[Mono]` `Root.swift`, `MainView.swift`).
- **Keep set** (INFERRED, built on Monolingual's logic, VERIFIED-OSS):
  - every language in `Locale.preferredLanguages`, both as base and full forms (`pt-BR` → `pt`, `pt_BR`);
  - the current locale identifier and language code;
  - **`en`**: Monolingual makes English non-removable because removing it "breaks a macOS installation beyond repair";
  - **`Base.lproj`**: holds base-internationalised NIBs and storyboards;
  - the app's `CFBundleDevelopmentRegion`;
  - legacy display-name folders for kept languages (`English.lproj`, `German.lproj`, …);
  - per-app overrides from `defaults read <bundle-id> AppleLanguages`.
  - Monolingual maps each locale to the folder names `xx.lproj`, `xx-YY.lproj`, `xx_YY.lproj`, `xx-Script.lproj`, `xx_Script_YY.lproj` and `DisplayName.lproj` (VERIFIED-OSS `MainView.swift`).
- **Bundle exclusions (VERIFIED-OSS `[Lemon]` filters 48–52, 71, 83):**
  - `com.apple*` bundles and `com.apple.dt.Xcode`;
  - `com.microsoft*` (Office validates its own bundle);
  - paths containing `1Password` (Lemon's note: language cleanup broke its plugin);
  - `IINA` (Safari-extension breakage).
  - Lemon also always keeps `en` and `zh*`.
- **Additional bundle exclusions (INFERRED):**
  - Mac App Store apps (`Contents/_MASReceipt/receipt` exists);
  - iOS/iPadOS apps on Mac (`WrappedBundle`);
  - running apps;
  - apps on read-only or external volumes;
  - apps in the Ignore List.
- **Code-signature seal (the crucial modern caveat). (corrected; this whole sub-section was rewritten during fact-checking)**
  - **Apple's rule (VERIFIED-APPLE).** TN2206 *macOS Code Signing In Depth*, section "Changes That Don't Invalidate a Code Signature", says that removing files from `.lproj` folders inside `Contents/Resources` does not invalidate the code signature, but adding or changing files does. https://developer.apple.com/library/archive/technotes/tn2206/_index.html
  - **Why (VERIFIED-APPLE-OSS).** `codesign`'s default resource rules, in apple-oss-distributions/Security `OSX/libsecurity_codesigning/lib/bundlediskrep.cpp` `defaultResourceRules`, declare:
    - `^Resources/.*\.lproj/` as `{optional=#T, weight=1000}`, with the comment "make localizations optional";
    - `^Resources/Base\.lproj/` as `{weight=1010}`, with the comment "except for Base.lproj which really isn't optional at all";
    - `.lproj/locversion.plist` as `omit`.
    - An optional sealed file may be **absent**. If it is present, it must be **unmodified**.
  - **Monolingual's helper (VERIFIED-OSS, re-read).**
    - It reads each bundle's signing info (`SecStaticCodeCreateWithPath` → `SecCodeCopySigningInformation` with internal-information flags → the `"ResourceDirectory"` dictionary's `files`/`files2`).
    - `addFileDictionaryToBlocklist` **skips entries marked `optional`** and blocklists the rest by exact URL. In practice it protects `Base.lproj` and non-localization resources, and still removes ordinary `xx.lproj` content from signed apps.
    - It also skips SIP-protected items (`com.apple.rootless` xattr). Sources: `HelperContext.swift` `addCodeResourcesToBlocklist`, `Helper.swift` `shouldProcessItemAtURL`.
  - **The old claim was wrong.** This section used to say that removing `.lproj` folders from modern notarized apps makes `codesign --verify` fail. That does not happen for optional localization resources.
  - **What *does* break the seal (INFERRED from the rules above):**
    - touching `Base.lproj`;
    - deleting non-`.lproj` resources;
    - editing (rather than deleting) a `.strings` file;
    - apps signed with custom (pre-10.9) resource rules that mark nothing optional;
    - adding anything to the bundle.
  - **Still risky even with a valid seal (INFERRED):**
    - Sparkle **binary-delta** updates expect the exact old bundle. Sparkle falls back to a full download.
    - Apps that hash their own bundle at runtime may complain.
    - Mac App Store apps are root-owned and need App Management.
    - Ventura and later re-check the integrity of notarized apps at first launch (VERIFIED-APPLE WWDC22 10096). This is harmless if the seal is valid, but fatal if our code has a bug.
  - **Nested bundles** (`Contents/Frameworks/*.framework/Versions/*/Resources/*.lproj`, plug-ins, XPC services) carry their own `CodeResources` built from the same default rules. Removing optional localizations there should also keep the nested signature valid, but TN2206 only spells this out for `Contents/Resources` (INFERRED; verify on device).
- **Our policy (INFERRED, corrected):**
  - **Default unchecked**, for the App Management, update-churn and Sparkle reasons above, not because of the seal.
  - **The one engine** removes only `.lproj` *files* whose seal entry is marked `optional`, or that are not sealed at all, and that are outside the keep set. It never touches `Base.lproj`. It deletes the then-empty `.lproj` directory, because directories are not sealed.
  - **Verify in staging, then swap atomically:**
    1. Make an APFS clone of the bundle (`clonefile`).
    2. Remove the files in the clone.
    3. Run `codesign --verify --deep --strict` on the clone.
    4. If it passes, swap the clone in with `renamex_np(RENAME_SWAP)`. If it fails, drop the app with reason `sealed`.
  - **No ad-hoc re-sign mode (corrected).** The earlier draft proposed re-signing with `codesign --force --deep --sign -`. That is unnecessary given TN2206, and harmful: it replaces the Developer ID signature, breaks notarization and the designated requirement, resets TCC grants and Keychain ACLs, and makes Sparkle reject updates.
- **Privilege.** Helper (many apps are root-owned) plus the **App Management** permission (macOS 13+). **Delete mode.** Modify-in-place via the helper. Monolingual can trash instead of delete (`Trash` preference), and it changes ownership so items can be moved to the user's Trash (VERIFIED-OSS).
- **Size estimate.** Sum of allocated sizes of removable files only, after the seal filter. Show a per-app breakdown and a per-language breakdown.

### 5.7 macOS Localizations (legacy CMM3 group)

- **What.** OS language files (VERIFIED-V `[CMM3-Help/2]`).
- **Status on our targets (INFERRED, platform knowledge).** Impossible and unwise. `/System` lives on the Signed System Volume (read-only, sealed snapshot) from macOS 11. Do **not** implement it. If shown at all, show it as an info row saying it is protected by macOS.

### 5.8 Universal Binaries (`systemJunk.universalBinaries`)

- **What.** Extra architecture code in apps. MacPaw: the Mac "only needs one copy" (VERIFIED-V `[CMM3-Help/2]`).
- **Target on an Apple-Silicon Mac mini.**
  - Remove the `x86_64`, `x86_64h`, `i386` and `ppc*` slices from fat Mach-O files.
  - Keep `arm64`/`arm64e`.
  - Never remove *all* slices. Monolingual alerts "Removing all architectures will make macOS inoperable" (VERIFIED-OSS).
- **Detection.**
  - Walk app bundles and examine regular, executable, non-symlink files.
  - Read the first 4 bytes and treat `FAT_MAGIC/FAT_CIGAM/FAT_MAGIC_64/FAT_CIGAM_64` as candidates. Skip `.class` files (VERIFIED-OSS `[Mono]` `Helper.swift`).
  - Compute savings from the `fat_arch` table: the sum of the sizes of the slices to drop. Pearcleaner computes this in dry-run mode (VERIFIED-OSS `[Pear]` `Lipo.swift`).
  - If an app's main executable has only one architecture, **exclude its Frameworks**, because universal frameworks may be needed (Monolingual issue #67, VERIFIED-OSS).
- **Exclusions (INFERRED):**
  - Mac App Store apps;
  - Apple apps;
  - running apps;
  - apps the user set to **"Open using Rosetta"**;
  - plug-in hosts (DAWs, Final Cut/Logic, Adobe, Unity/Unreal editors) that may need x86_64 for Intel-only plug-ins;
  - apps with a Sparkle feed that serves delta updates (a modified bundle breaks the delta and forces a full download; Sparkle falls back, so this is a minor issue);
  - anything under `/System` or `/Library/Apple`;
  - files that carry `com.apple.rootless`.
- **Signature. (corrected: upgraded from INFERRED)**
  - TN2206 states that removing the Mach-O slice for one architecture from a universal binary does not invalidate the code signature (VERIFIED-APPLE, https://developer.apple.com/library/archive/technotes/tn2206/_index.html).
  - Mechanism (INFERRED): each slice carries its own `LC_CODE_SIGNATURE`, and the kept arm64 slice's bytes and cdhash are unchanged. The outer bundle seals nested code by designated requirement plus cdhash, so the outer seal also still verifies.
  - Still run `codesign --verify --deep --strict` on the staged copy as a safety net.
  - Monolingual refuses to `strip` signed binaries ("do not modify executables with code signatures", checked via `SecCodeCopyDesignatedRequirement`), but thins them with no signature check. It does so in-process (`LipoCore`), not with `/usr/bin/lipo`. VERIFIED-OSS `Helper.swift`.
  - Pearcleaner's in-process thinner keeps only the slice whose cputype matches the build (arm64 `0x0100000C`, which also matches arm64e). It has no signature verification or App Store/Apple-app exclusions, and it reports *logical* sizes. VERIFIED-OSS `Lipo.swift`. Do not copy those gaps.
- **Implementation (INFERRED):**
  1. Write `lipo <in> -thin arm64 -output <tmp>` (or `-remove x86_64 -remove …` to keep arm64e+arm64). Pearcleaner does it in-process by parsing `fat_header`/`fat_arch` (VERIFIED-OSS).
  2. Preserve owner, group, mode and xattrs.
  3. Verify the **whole bundle** with `codesign --verify --deep --strict`, in a staged clone.
  4. On success, swap atomically with `renamex_np(RENAME_SWAP)`. On failure, discard the staged copy and mark the app "not thinnable (signature)".
- **Default.** **Unchecked** (review). Savings vanish on the next app update.
- **Privilege.** Helper plus App Management.

### 5.9 Broken Login Items (`systemJunk.brokenLoginItems`)

- **What.**
  - A login-item link that remains after its app or service was removed (VERIFIED-V `[CMM3-Help/2]`).
  - Not available in the App Store edition (VERIFIED-S/K).
  - In the Smart Care basics (VERIFIED-K).
  - Part of Business auto-clean (VERIFIED-K).
- **Where login items live on macOS 13+ (INFERRED platform knowledge):**
  1. **"Open at Login" items**, managed by `backgroundtaskmanagementd` (BTM). Inspect them read-only with `sfltool dumpbtm` (root). The DB lives in `/private/var/db/com.apple.backgroundtaskmanagement/`. Re-checked: the file is `BackgroundItems-v*.btm`, introduced in macOS 13 (`-v7` on 13.1, higher numbers later). Reading it directly needs **Full Disk Access**. Objective-See's open-source DumpBTM parses it and documents `sfltool dumpbtm` as Apple's equivalent. VERIFIED-OSS: https://github.com/objective-see/DumpBTM User-visible removal goes through System Settings, or AppleScript `tell application "System Events" to delete login item "<name>"`, which needs Automation permission.
  2. **Launch agents and daemons:** `~/Library/LaunchAgents/*.plist` (user), `/Library/LaunchAgents/*.plist`, `/Library/LaunchDaemons/*.plist` (root).
  3. **Legacy SMLoginItem helpers** inside app bundles (`Contents/Library/LoginItems`). They disappear with the app, but BTM records may linger.
- **Detection (INFERRED; Mole's orphaned-service logic VERIFIED-OSS SECURITY_AUDIT):**
  - Parse each plist and read `Program` or `ProgramArguments[0]`.
  - An item is **broken** when that path is **absolute and missing**, or when a `/Library/PrivilegedHelperTools` helper's parent app is uninstalled.
  - For `BundleProgram`/`AssociatedBundleIdentifiers`, check whether the app still exists via `NSWorkspace.urlForApplication(withBundleIdentifier:)`.
  - Skip `com.apple.*`.
  - Treat unreadable plists as "unknown" and fail closed (Mole: "an unreadable plist is never misread as a missing binary").
  - For BTM entries, parse `sfltool dumpbtm` output from the helper and flag items whose URL/path does not exist.
- **Removal.**
  - User agent: `launchctl bootout gui/$(id -u) <plist>`, then unlink the plist.
  - System agent/daemon: from the helper, `launchctl bootout system <plist>`, then unlink. Before deleting any helper binary, re-scan to confirm no remaining plist references it (Mole does this, VERIFIED-OSS).
  - "Open at Login" item: System Events delete. **Never** `sfltool resetbtm`, which wipes everything (INFERRED).
- **Default.** Auto for user agents and Open-at-Login entries with missing targets. Review for `/Library` ones.
- **Note.** Do not count user-authored agents (custom scripts with relative paths) as broken.

### 5.10 Broken Preferences (`systemJunk.brokenPreferences`)

- **What.** Preference files that became corrupted and make apps misbehave or fail to launch (VERIFIED-V `[CMM3-Help/2]`). In the App Store edition's Smart Care (VERIFIED-K). In Business auto-clean (VERIFIED-K).
- **Paths.**
  - `~/Library/Preferences/*.plist`
  - `~/Library/Preferences/ByHost/*.plist`
  - `~/Library/Containers/*/Data/Library/Preferences/*.plist`
  - `~/Library/Group Containers/*/Library/Preferences/*.plist`
  - optional with the helper: `/Library/Preferences/*.plist` (review)
- **Detection (INFERRED).** A plist is broken if it is:
  - (a) zero bytes;
  - (b) unparseable by `PropertyListSerialization.propertyList(from:options:format:)` (both binary and XML);
  - (c) an orphaned atomic-write temp file (`<name>.plist.<random>`) older than 1 day;
  - (d) a stale `*.plist.lockfile` older than 1 day.
  "Orphaned prefs of uninstalled apps" are **Leftovers**, not broken preferences.
- **Exclusions.**
  - `.GlobalPreferences*.plist`;
  - `com.apple.*` critical domains (Dock, Finder, loginwindow, Bluetooth/Wi-Fi ByHost; Mole protects these, VERIFIED-OSS);
  - `org.cups.*`;
  - keyboard and input-method prefs;
  - password managers;
  - VPN tools.
  If a protected one is corrupt, report it read-only.
- **Removal.** Unlink, then nudge `cfprefsd` (`killall -u $USER cfprefsd`) so it does not re-write cached contents (INFERRED; verify on device). Skip a domain whose app is running.
- **Default.** Auto.

### 5.11 Document Versions (`systemJunk.documentVersions`)

- **What.** Versions that apps save automatically or on Save (Auto Save / Versions), which can add up to gigabytes (VERIFIED-V `[CMM3-Help/2]`).
- **Rule (VERIFIED-V `[CMM3-Help/2]`; VERIFIED-K X KB):**
  - Never offer the **earliest** or the **latest** version of a document.
  - Auto-select only versions made **less than 4 hours apart**, keeping the **latest in each range**.
- **Storage. (corrected: upgraded to VERIFIED-OSS, with detail added)**
  - The per-volume store is `/.DocumentRevisions-V100/` (on the Data volume: `/System/Volumes/Data/.DocumentRevisions-V100`), root-owned and managed by `revisiond`.
  - The forensic tool mac_apt (`plugins/documentrevisions.py`, VERIFIED-OSS https://github.com/ydkhatri/mac_apt) reads it as follows:
    - It probes `/.DocumentRevisions-V100`, then `/System/Volumes/Data/.DocumentRevisions-V100`.
    - Revisions DB: `<root>/db-V1/db.sqlite`.
      - Table `files` has `file_inode`, `file_path`, `file_last_seen`, `file_storage_id`.
      - Table `generations` has `generation_id`, `generation_storage_id`, `generation_add_time`, `generation_path`, `generation_size`.
      - Join on `generations.generation_storage_id = files.file_storage_id`.
      - The generation file lives at `<root>` + `generation_path`. The path is stored in the DB; do not build it yourself. In practice it sits under a `PerUID/<uid>/…` tree (INFERRED).
    - Chunk store: `<root>/.cs/ChunkStoreDatabase` (tables `CSStorageChunkListTable`, `CSChunkTable`) and chunk files under `<root>/.cs/ChunkStorage/…`.
  - INFERRED: because a chunk store exists, `generation_size` can overstate the space actually freed. Some generations are deduplicated chunks. Measure free space before and after the deletion.
  - The MacSai clone wrongly points at `~/.DocumentRevisions-V100` (VERIFIED-OSS `[MacSai]` `Constants.swift`). Do not copy that.
  - Mole prunes `.DocumentRevisions-V100` from external-volume sweeps (VERIFIED-OSS).
  - Tencent Lemon has a "Sketch Cache Data" item that points straight at `/.DocumentRevisions-V100/` (`recommend="NO"`). That is direct deletion inside the store, an anti-pattern we do not copy (VERIFIED-OSS `[Lemon]` item 21023).
- **Correct API (VERIFIED-APPLE):**
  - `NSFileVersion.otherVersionsOfItem(at:)` returns all versions except the current one.
  - `NSFileVersion.remove()` "Remove this version object and its associated file from the version store". It must not be called on the current version and should run inside a coordinated write.
  - `removeOtherVersionsOfItem(at:)` removes everything except the current version.
  - Versions also carry `isDiscardable` and `modificationDate`.
- **Enumeration (INFERRED).** NSFileVersion needs a file URL, so discover which files have versions in one of two ways:
  - (a) The helper (root plus FDA) copies `db.sqlite` read-only to a temp file, together with its `-wal`/`-shm` files if present. It runs `SELECT f.file_path, COUNT(g.generation_id), SUM(g.generation_size), MIN(g.generation_add_time), MAX(g.generation_add_time) FROM files f JOIN generations g ON g.generation_storage_id = f.file_storage_id GROUP BY f.file_storage_id HAVING COUNT(*) > 1`. It returns only paths inside the requesting user's home, filtered against the deny list. Schema per mac_apt above.
  - (b) Fall back to a Spotlight or known-locations walk of document types, calling `otherVersionsOfItem` on each.

  For each file, the app (running as the user) applies the rule and calls `remove()` on each chosen version inside `NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], …)`. (corrected) The earlier draft used `.forDeleting`. That option tells presenters the *document* is being deleted, which it is not. Apple's docs ask only for a coordinated write. Size per version comes from the version's `url` resource values.
- **Never** delete files inside `.DocumentRevisions-V100` directly; the `revisiond` DB would become inconsistent (INFERRED).
- **Default.** Auto only for the rule-selected versions. Other versions are review.
- **Privilege.** FDA, and the helper for DB discovery.

```swift
// INFERRED pseudocode for the vendor rule
func autoSelect(_ all: [Version]) -> Set<Version> {          // all = others + current, any order
    let v = all.sorted { $0.date < $1.date }
    guard v.count >= 3 else { return [] }
    var picked = Set<Version>()
    var cluster: [Version] = [v[1]]                          // index 0 (earliest) is never offered
    for i in 2..<(v.count - 1) {                             // last (latest/current) is never offered
        if v[i].date.timeIntervalSince(cluster.last!.date) < 4*3600 { cluster.append(v[i]) }
        else { picked.formUnion(cluster.dropLast()); cluster = [v[i]] }
    }
    // close the final cluster; if its next neighbour (the latest) is < 4h away the whole cluster is superseded
    if v.last!.date.timeIntervalSince(cluster.last!.date) < 4*3600 { picked.formUnion(cluster) }
    else { picked.formUnion(cluster.dropLast()) }
    return picked
}
```

### 5.12 Unused Disk Images (`systemJunk.unusedDiskImages`)

- **What.** DMG (and ISO/sparse) images left after installing software. Present in the X-era group list (VERIFIED-OSS `[MacOpt]` replica, which calls itself a CleanMyMac **X** reconstruction). The replica's description says disk images "most often exist as DMG files", and that many unused images remain after installing software. In 5.x the equivalent is Applications › Installation files and My Clutter › Downloads ("old DMGs, archives"), VERIFIED-K 01-overview.md.
- **5.x status (fact-check, still INFERRED).**
  - The 5.x missing-features KB lists exactly 12 System Junk groups (01-overview.md §4.3/§5.2). Unused Disk Images, Downloads and Old Updates are not among them.
  - Two of the three X groups map onto new 5.x homes: installers go to Applications › Installation files, and downloads go to My Clutter › Downloads (VERIFIED-K).
  - So the best reading is that 5.x **moved** Unused Disk Images and Downloads out of System Junk, and either dropped Old Updates or folded it into caches.
  - Not confirmed from a 5.x screen: macpaw.com was unreachable again in this pass.
- **Paths.**
  - `~/Downloads/**/*.{dmg,iso,sparseimage,sparsebundle,img}`;
  - optionally `~/Desktop` and `~/Documents` (review).
  - MacSai scans `.dmg`, `.iso` and `.sparseimage` older than 7 days (VERIFIED-OSS).
- **Detection (INFERRED).**
  - Exclude mounted images: parse `hdiutil info -plist` → `images[].image-path`.
  - Determine "unused" from `kMDItemLastUsedDate` and `kMDItemDateAdded` (> 7 d).
  - Raise confidence if the image name or volume name matches an installed app in `/Applications` (e.g. `Foo-1.2.dmg` ↔ `Foo.app`). Optionally attach the image read-only with `hdiutil attach -nobrowse -readonly -noverify` to read the `.app` bundle ID inside. That is expensive, so do it on demand.
- **Default.** Unchecked, unless the contained app is installed and the image is older than 30 days. **Delete mode.** Trash.

### 5.13 Old Updates (`systemJunk.oldUpdates`)

- **What (CMM3).** Old versions of app updates that apps don't clean up; "removing old application updates is safe" (VERIFIED-V `[CMM3-Help/2]`).
- **Paths (INFERRED unless cited).**
  - **Sparkle 2 staging. (corrected: now VERIFIED-OSS from Sparkle's source)**
    - Path: `~/Library/Caches/<host-bundle-id>/org.sparkle-project.Sparkle/`, with subfolders `PersistentDownloads/` (downloaded archives) and `Installation/`.
    - `SPULocalCacheDirectory cachePathForBundleIdentifier:` builds it as user Caches + bundle ID + `org.sparkle-project.Sparkle`. If the bundle ID ends in `.app`/`.xpc`/`.appex`/`.bundle`/etc., `.sparkle` is appended.
    - Sandboxed hosts resolve it inside their container's Caches.
    - Sparkle itself prunes top-level items older than **10 days** (`OLD_ITEM_DELETION_INTERVAL = 86400 * 10`). Its installer refuses download paths that lack `PersistentDownloads`.
    - Source: https://github.com/sparkle-project/Sparkle (`Sparkle/SPULocalCacheDirectory.m`, `Downloader/SPUDownloader.m`, `Autoupdate/AppInstaller.m`).
    - INFERRED gate: skip items younger than 10 days, and skip while the host app or Sparkle's `Autoupdate`/`Updater` is running. A fresh `PersistentDownloads` item can be an update queued for "install on quit".
    - The earlier `~/Library/Application Support/<bundle-id>/.Sparkle*` path was unverified and is dropped (corrected).
  - **Microsoft AutoUpdate (corrected; VERIFIED-OSS).**
    - MAU 4.50+ stages updates as full app clones in `/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex`. MAU 4.35–4.49 used `…/Clones`. Source: `MAU_Pending_Updates.sh` in https://github.com/pbowden-msft/ExtensionAttributes.
    - Community-maintained Office/MAU reset scripts also remove `/Library/Caches/com.microsoft.autoupdate.fba/` and `$TMPDIR/MSauClones` (https://github.com/cocopuff2u/MOFA).
    - These clones are **pending updates** and APFS clones, so deleting them cancels the update and may free little. List them as **review**, never auto, and gate on MAU not running (INFERRED).
    - `~/Library/Caches/com.microsoft.autoupdate2` is ordinary user cache.
  - **Spotify updater archives:** `~/Library/Application Support/Spotify/PersistentCache/Update/*.tbz`. Auto when Spotify is not running (VERIFIED-OSS path, §4.1).
  - **Chromium old framework versions** inside the app bundle. Mole keeps the `Current` symlink target and any newer staged update, and removes older `Contents/Frameworks/<X> Framework.framework/Versions/<ver>` for Chrome, Edge and Brave. Edge's updater keeps the latest by version sort (VERIFIED-OSS `user.sh`).
  - **macOS installer apps.** `/Applications/Install macOS *.app`, only if older than 14 days, not running and not matching the installed macOS version (Mole, VERIFIED-OSS).
  - `.pkg`/`.mpkg` installers in `~/Downloads` older than 7 days (MacSai, VERIFIED-OSS). We route these to Unused Disk Images/Installers instead.
- **Never.** `/Library/Updates` and `/macOS Install Data`. Software Update owns these staging trees, and Mole never removes them (VERIFIED-OSS `system.sh`).
- **Default.** Auto for Sparkle and MAU caches when the owner app is not running. Review for installer apps and Chromium versions (App Management plus helper).

### 5.14 Xcode Junk (`systemJunk.xcodeJunk`)

- **What.** Intermediate build info and project indexes. CleanMyMac does not remove **Module Cache** and **Archives** automatically (VERIFIED-V `[CMM3-Help/2]`). In Business auto-clean (VERIFIED-K). The CLI's `clean junk` covers DerivedData, Device Support, Module Cache and Documentation Cache (VERIFIED-V `[CLI]`).
- **Paths and defaults (VERIFIED-OSS where cited):**

| Path | What | Default (ours) | Notes / source |
|---|---|---|---|
| `~/Library/Developer/Xcode/DerivedData/*` (custom location: `defaults read com.apple.dt.Xcode IDECustomDerivedDataLocation`, INFERRED) | build intermediates and index per project | **auto** if Xcode, `xcodebuild` and `SourceKitService` are not running | Mole cleans only on a conclusive "no Xcode process" (VERIFIED-OSS `app_caches.sh`). DevCleaner lists per project using `info.plist` `WorkspacePath` (VERIFIED-OSS) |
| `…/DerivedData/ModuleCache.noindex` | clang/Swift module cache | **review** | CMM3 excludes Module Cache from auto (VERIFIED-V). DevCleaner ignores the `ModuleCache` folder (VERIFIED-OSS) |
| `~/Library/Developer/Xcode/Archives/**/*.xcarchive` | shipped builds and dSYMs | **review** | Needed for crash symbolication. DevCleaner warns. Mole only reports them (VERIFIED-OSS). Lemon marks them `recommend="NO"` |
| `~/Library/Developer/Xcode/{iOS,watchOS,tvOS,visionOS,macOS} DeviceSupport/*` | debug symbols per device OS (1–5 GB each) | **auto except the newest per platform** | DevCleaner deselects the first (newest) entry per OS (VERIFIED-OSS `XcodeFiles.swift`). Mole cleans old versions (VERIFIED-OSS). Lemon: `recommend="NO"` |
| `~/Library/Developer/Xcode/iOS Device Logs/*`, `…/DeviceLogs/*` | device logs and crash DBs | auto except the latest | DevCleaner keeps the newest (VERIFIED-OSS). Lemon covers both paths |
| `~/Library/Developer/Xcode/DocumentationCache/*` | per-Xcode doc cache | auto except the current Xcode version | DevCleaner (VERIFIED-OSS). Mole also checks `/Library/Developer/Xcode/DocumentationCache` |
| `~/Library/Developer/Shared/Documentation/DocSets/*` | old offline docs | review | DevCleaner "Old Documentation" (VERIFIED-OSS) |
| `~/Library/Developer/Xcode/UserData/IB Support/*` | Interface Builder support cache | auto (Xcode closed) | Mole (VERIFIED-OSS) |
| `~/Library/Developer/Xcode/UserData/Previews/*` | SwiftUI preview simulators | auto (Xcode closed) | MacSai constant (VERIFIED-OSS) |
| `~/Library/Developer/Xcode/Products/*` | build products | auto (Xcode closed) | Mole (VERIFIED-OSS) |
| `~/Library/Caches/com.apple.dt.Xcode/*` + Darwin temp `…/T/com.apple.dt.Xcode` | Xcode app caches | auto | Lemon "Xcode app Caches" incl. the SystemTempDir special path (VERIFIED-OSS) |
| `~/Library/Developer/CoreSimulator/Caches/*` | simulator dyld caches | auto (no sim booted) | INFERRED |
| Unavailable simulators | devices for removed runtimes | auto via `xcrun simctl delete unavailable` | Mole uses simctl with a `DEVELOPER_DIR` resolver and retry (VERIFIED-OSS `dev.sh`). mac-cleanup-py offers `xcrun simctl erase all` behind a prompt, which is too aggressive (VERIFIED-OSS) |
| `~/Library/Developer/CoreSimulator/Devices/*` (all) | simulator app data | **review** | Mole reports it as "Simulator data" (VERIFIED-OSS) |
| `~/Library/Developer/CoreSimulator/Profiles/Runtimes/*/Contents/Resources/RuntimeRoot/System/Library/Caches/*` | runtime caches | auto (no sim booted) | Mole (VERIFIED-OSS) |
| `/Library/Developer/CoreSimulator/Profiles/Runtimes/*`, `/Library/Developer/CoreSimulator/Volumes/*` | simulator runtimes (GBs) | **review**; remove with `xcrun simctl runtime delete <id>` | Lemon lists both, the second as `/Library/Developer/CoreSimulator/Volumes/(.+)/Library/Developer/CoreSimulator/Profiles/Runtimes/` (VERIFIED-OSS). Mole flags "orphaned runtime · no devices" and suggests the simctl command (VERIFIED-OSS) |
| `/Library/Developer/CoreSimulator/Images/*` (runtime disk images plus `images.plist`), `/Library/Developer/CoreSimulator/Cryptex/Images/bundle/SimRuntimeBundle-*` | Xcode 15+ simulator runtime images; `Volumes/` holds their mounts | **review; never delete files directly**, only via `xcrun simctl runtime delete <id>` | (added) Xcode 15+ keeps runtimes as images in `Images/` and mounts them under `Volumes/` (VERIFIED-OSS, simctl reference notes in public repos). The .NET MAUI CI scripts `rm -rf` these only on throwaway CI machines, and note the side effects: runtimes stuck in "(Deleting)" and same-UUID collisions (https://github.com/dotnet/maui `eng/pipelines/common/provision.yml`). Treat that as an anti-pattern for end-user Macs |
| `~/Library/Developer/XCTestDevices/*` | test clones | auto | Mole (VERIFIED-OSS) |
| `~/Library/Logs/CoreSimulator/*` | sim logs | auto | mac-cleanup (VERIFIED-OSS) |
| `~/Library/Caches/org.swift.swiftpm/*`, `~/.cache/swift-package-manager/*` | SwiftPM caches | auto | Mole (VERIFIED-OSS) |

- **Process gate.** Skip the whole category (reason "Xcode is running") if any of these is running: `Xcode`, `xcodebuild`, `xctest`, `XCTRunner`, `XCBBuildService`, `swift-frontend`, `SourceKitService`, or `CoreSimulatorService` with a booted device (`xcrun simctl list devices booted -j`). Mole checks exactly these build-tool processes (`app_protection.sh` `xcode_build_tooling_process_state`, `dev.sh`) plus booted simulators before touching Xcode data (VERIFIED-OSS).

### 5.15 Development Junk / Dev Tools (`systemJunk.devJunk`)

- **What.** CMM3 described Development Junk as supporting files created during installation or configuration that become useless (VERIFIED-V `[CMM3-Help/2]`). In 2026 MacPaw's CLI defines Dev Tools as Homebrew, npm, Yarn, pnpm, pip, Poetry, uv, Cargo, Go, CocoaPods, Docker, VS Code, JetBrains, Maven, Gradle, Bun, Deno, mise (VERIFIED-V `[CLI]`).
- **Prefer each tool's own cleaner when installed. Fall back to file deletion.**

| Tool | Command (preferred) | Paths | Default |
|---|---|---|---|
| Homebrew | `brew cleanup --prune=30` (Mole runs a `--dry-run` preview with the same args, VERIFIED-OSS `brew.sh`) | `~/Library/Caches/Homebrew/downloads/*` | auto |
| npm | `npm cache clean --force` (Mole, mac-cleanup) | `~/.npm/_cacache` | auto |
| Yarn | `yarn cache clean` | `~/Library/Caches/Yarn/*` (v1), `~/.yarn/berry/cache` | auto |
| pnpm | `pnpm store prune` | `~/Library/pnpm/store` (Mole reports only) | review (store is hard-linked into projects) |
| pip | `pip3 cache purge` (Mole) | `~/Library/Caches/pip` | auto |
| Poetry | `poetry cache clear --all <repo>` | `~/Library/Caches/pypoetry/{cache,artifacts}`; **never** `pypoetry/virtualenvs` (Mole safety rule) | auto |
| uv | `uv cache clean` | `uv cache dir` | auto |
| Cargo | (cargo-cache) | `~/.cargo/registry/{cache,src}`; never `~/.cargo/bin`, `~/.rustup` (Mole protected) | auto/review |
| Go | `go clean -cache` / `go clean -modcache` (Mole) | `~/Library/Caches/go-build`, `$(go env GOMODCACHE)` | build cache auto; modcache review |
| CocoaPods | `pod cache clean --all` | `~/Library/Caches/CocoaPods/*` | auto |
| Docker | `docker system df` (review only); prune only on explicit action | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` — **never delete directly** | review |
| VS Code | — | `~/Library/Application Support/Code/{Cache,CachedData,CachedExtensionVSIXs,Code Cache,GPUCache,logs}` | auto (app closed) |
| JetBrains | — | `~/Library/Caches/JetBrains/<IDE><ver>` (old versions only; Mole's whitelist protects JetBrains caches by default and reports stale version dirs) | review |
| Maven | — | `~/.m2/repository` (Mole: report only, never delete) | review |
| Gradle | — | `~/.gradle/{daemon,notifications,workers}/*`, `~/.gradle/caches/build-cache-*/*` auto **only when no Gradle daemon is running** (`pgrep -f GradleDaemon`); `~/.gradle/caches` (modules-2) **never auto**, CMM exception (VERIFIED-S). (corrected) Mole's *default* whitelist protects both `~/.gradle/caches/*` and `~/.gradle/daemon/*` (VERIFIED-OSS `base.sh`), so the daemon/build-cache auto rule is our own INFERRED choice, not Mole's | mixed |
| Bun / Deno / mise | `bun pm cache rm`; `deno clean` (Mole notes it removes all of `DENO_DIR` — review); mise cache | `~/.bun/install/cache`, Deno dir, `~/Library/Caches/mise` | auto/review |
| Android | — | `~/.android/cache/*`, `~/.android/build-cache/*`, `~/Library/Caches/Google/AndroidStudio*/*` | auto |
| Misc (Mole list) | — | `~/.cache/{pre-commit,ruff,mypy,eslint,prettier,typescript,vite,webpack,node-gyp,bazel,terraform,prisma,zig,flutter}`, `~/.pub-cache`, `~/.gem/ruby/*/cache/*.gem`, `~/.bundle/cache`, `~/.composer/cache`, `~/Library/Caches/composer`, `~/.kube/cache`, `~/.aws/cli/cache`, `~/.turbo/cache`, `~/.parcel-cache` | auto (tools closed) |
| Conda | `conda clean --yes --index-cache --tarballs --logfiles` (Mole) | `~/.conda/pkgs`, `~/anaconda3/pkgs` (reported) | review |

- **Project artifacts** (`node_modules`, `target`, `.build`, `DerivedData`, `.venv`, `Pods`, `vendor`, `cmake-build-*`, `.next`, `.turbo`, `__pycache__`) belong to a separate **Purge** tool, matching MacPaw's CLI split between `clean` and `purge` (VERIFIED-V `[CLI]`). Use the CLI's default roots and the 7-day rule.

### 5.16 AI Tools Junk (`systemJunk.aiJunk`)

- **What.** The MacPaw CLI has `clean ai`, and its mock-up shows a "Claude" row. The group is unchecked by default in the scan screen (VERIFIED-V `[CLI]`).
- **Paths (VERIFIED-OSS Mole/MacSai; treat everything else as protected):**
  - `~/Library/Caches/com.anthropic.claudefordesktop/*`, `~/Library/Logs/Claude/*`;
  - `~/Library/Caches/com.openai.chat/*`;
  - `~/Library/Caches/com.lmstudio.lmstudio/*`;
  - `~/.claude/{cache,paste-cache,shell-snapshots}`, `~/.codex/{.tmp,cache}`. MacSai excludes "history and sessions"; Mole protects Codex app-directory state.
- **Never.**
  - Conversation history, projects and settings: `~/.claude/projects`, `~/.codex/sessions`, app Application Support.
  - Model stores: `~/.ollama/models`, `~/.lmstudio/models`. Mole whitelists or reports these only.
- **Default.** Unchecked.

### 5.17 iOS Device Backups (`systemJunk.iosBackups`)

- **What.** Backups of iPhone/iPad stored on the Mac. "The latest backup is never selected for removal automatically" (VERIFIED-V `[CMM3-Help/5]`; VERIFIED-K X KB). Absent from Business auto-clean (VERIFIED-K).
- **Path.** `~/Library/Application Support/MobileSync/Backup/<UDID>/`. Archived copies are `<UDID>-YYYYMMDD-HHMMSS/` (INFERRED). Lemon marks the item `recommend="NO"` (VERIFIED-OSS, re-read: item 1008 "iOS Device Backup"). Mole only *reports* this folder in its large-item review and never deletes it (VERIFIED-OSS `user.sh`). mac-cleanup-sh/-py delete `Backup/*` wholesale, an anti-pattern (VERIFIED-OSS).
- **Metadata.** Read `Info.plist` (`Device Name`, `Product Type`, `Product Version`, `Last Backup Date`, `Target Identifier`), `Manifest.plist` (`IsEncrypted`) and `Status.plist`. (corrected: the `Info.plist` key names are now VERIFIED-OSS, e.g. https://github.com/avibrazil/iOSbackup README and WechatExporter `ITunesParser.cpp`; the `Manifest.plist`/`Status.plist` usage stays INFERRED.) Show device name, OS, date, encrypted badge and size. Mole notes backups reach "100GB+ with millions of small files" and need a longer size budget (VERIFIED-OSS).
- **Default (ours).** Group by device.
  - Newest backup per device: **unchecked** with the badge "latest backup".
  - Older and archived backups: unchecked too (review). Optionally pre-check backups older than 180 days of devices not seen for 180 days.
- **Delete mode.** Ask: move to Trash (safer, no immediate space) or delete permanently. If `Backup` is a symlink to an external drive (a common user hack), follow it **for display only** and confirm the target path explicitly.
- **Privilege.** FDA.

### 5.18 iOS Software Updates, iOS Apps, iOS Photo Cache, Music/TV junk (`iosSoftware`, `mediaJunk`)

- **iOS Software Updates (.ipsw).** Firmware files left after cable updates; "removing these files is safe" (VERIFIED-V `[CMM3-Help/5]`).
  - Paths: `~/Library/iTunes/iPhone Software Updates/*.ipsw`, `~/Library/iTunes/iPad Software Updates/*.ipsw`, `~/Library/iTunes/iPod Software Updates/*.ipsw`.
  - Apple Configurator: `~/Library/Group Containers/*.group.com.apple.configurator/**/*.ipsw`.
  - Mole: 5–8 GB each, re-downloaded on demand, never touches backups (VERIFIED-OSS `user.sh`). Lemon recursively matches `.+\.ipsw` under `~/Library/iTunes/`, `recommend="YES"` (VERIFIED-OSS).
  - **Default:** auto.
- **iOS Applications (.ipa).** Copies of iOS apps saved by old iTunes; keep them only if you sync old devices (VERIFIED-V `[CMM3-Help/5]`).
  - Path: `~/Music/iTunes/iTunes Media/Mobile Applications/*.ipa` (VERIFIED-OSS `[MCpy]`/`[MCsh]`).
  - **Default:** review (CMM3 smart-selected "iOS-related files you no longer need"; we are more cautious).
- **iOS Photo Cache.** Photos cached after syncing to iOS devices (VERIFIED-V `[CMM3-Help/2]`).
  - Path: `~/Pictures/iPod Photo Cache/` (when it contains more than one file and `Photo Database`; Lemon, `recommend="YES"`, VERIFIED-OSS).
  - **Default:** auto.
- **Music/iTunes cache (artwork) and broken downloads** (VERIFIED-V `[CMM3-Help/5]`: artwork caches regenerate; broken downloads are incomplete podcasts/movies/audio).
  - Modern paths: `~/Library/Containers/com.apple.AMPArtworkAgent/Data/Library/Caches/*` ("Music album art cache"), `~/Library/Caches/com.apple.Music`, `~/Library/Caches/com.apple.TV/*`, `~/Library/Caches/com.apple.podcasts`, `~/Library/Containers/com.apple.podcasts/Data/tmp/{StreamedMedia,*.heic,*.img,*CFNetworkDownload*.tmp}` (VERIFIED-OSS Mole).
  - Legacy: `~/Music/iTunes/Album Artwork/Cache` (INFERRED). Backup-exclusion lists commonly drop `*/iTunes/Album Artwork` as regenerable (VERIFIED-OSS, e.g. https://github.com/ArloL/dotfiles `macos-backups/arq-excludes.txt`).
  - **Broken downloads (corrected: paths now found, VERIFIED-OSS, secondary):**
    - **Music (macOS 10.15+):** `~/Music/Music/Media.localized/Downloads-Music/`. One 2026 open-source cleaner reports "Abandoned partial download … This download never finished" items there (https://github.com/Shivansh2703/orphan README). Another project names it as Music's local default download folder (https://github.com/swizzlevixen/Mac-Server-Reliability).
    - **TV:** `~/Movies/TV/Media.localized/Downloads-TV/`. Interrupted purchases appear as `<Title>.tmp` items (seen in a user's command allow-list, https://github.com/Arcadesys/arcadetoolbox `.codex/rules/default.rules`).
    - **Legacy iTunes:** `~/Music/iTunes/iTunes Media/Downloads/`. iTunes wrote downloads there as `*.tmp`, then moved finished files into the library; the iTunes app-download case is documented in https://github.com/attheodo/cherrypick (`cherrypick.js`). Backup tools routinely exclude it (borg/Arq exclude lists).
    - **Detection (INFERRED):** items ending in `.tmp`, or zero-progress files, older than 1 day, with Music/TV not running. If the media folder was moved, read its location from the app's preferences, and verify on device.
  - **Podcasts episode store (added):** `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/` holds downloaded episode assets and transcripts (`Assets/TTML`). The library DB is `…/Documents/MTLibrary.sqlite` (VERIFIED-OSS, https://github.com/mattdanielmurphy/apple-podcast-transcript-extractor). Downloaded episodes are **user content**: review only, never auto. Let Podcasts' own "Remove Download" handle them where possible.
  - **Default:** auto when the app is not running, for caches and `.tmp` partial downloads only.

### 5.19 Downloads — broken and incomplete (`systemJunk.brokenDownloads`)

- **Vendor rule (VERIFIED-K X KB):**
  - **Safari:** only broken downloads are auto-selected.
  - **Slack:** broken downloads plus files at least 1 month old.
- **Paths and patterns.** `~/Downloads/**/*.download` (Safari bundle), `*.crdownload` (Chrome/Chromium), `*.part` (Firefox), `*.partial`. Mole scans the first three with a complete open-file probe, repeated at the deletion boundary (VERIFIED-OSS `user.sh`). MacSai also uses `*.partial`/`*.tmp` (VERIFIED-OSS).
- **"Slack downloads" detection (INFERRED).** Read the `com.apple.metadata:kMDItemWhereFroms` xattr (or `mdls -name kMDItemWhereFroms`) and match `files.slack.com` / `slack-edge.com`. Auto-select at age ≥ 30 days, per the vendor rule. Generalise this to other chat apps as review.
- **Default.** Auto for incomplete downloads older than 1 day that are not open.
- **Delete mode.** Permanent for incomplete downloads; **Trash** for complete Slack files.

### 5.20 Deleted Users (`systemJunk.deletedUsers`)

- **What.** Data left from removed user accounts. Not in the App Store edition (VERIFIED-K). The replica says it is data left after deleting an account (VERIFIED-OSS `[MacOpt]`).
- **Paths. (corrected: partly upgraded)**
  - `/Users/Deleted Users/<name>.dmg`, created when a user is deleted with "save the home folder in a disk image". VERIFIED-OSS:
    - Jamf Pro's policy schema uses `/Users/Deleted Users/<user>.dmg` as the example archive target (https://github.com/deploymenttheory/go-api-sdk-jamfpro, `CreateDeleteAccountPolicy.go`);
    - admin scripts recreate the same layout with `hdiutil create -format UDZO -srcfolder /Users/$USERNAME "/Users/Deleted Users/$USERNAME.dmg"` (https://github.com/Cloudxtreme/macosadmin `deleteuser.sh`).
  - **Also scan non-DMG content in `/Users/Deleted Users/`** (added). A 2026 release runbook warns that unless "Delete the home folder" is chosen, the deleted account's files "stay in `/Users/Deleted Users`" (https://github.com/russellgordon/plantoir `RELEASING.md`). A DFIR note mentions `.<user>.<UID>` shadow folders there (https://github.com/spatel-DFIR/Everything-DFIR). VERIFIED-OSS, secondary. So list every child of `/Users/Deleted Users/`, both `.dmg` files and folders, as review rows.
  - Home folders renamed `/Users/<name> (Deleted)` (INFERRED; the classic "Don't change the home folder" result; not re-verified on 14–26).
  - Any `/Users/<dir>` with no matching `dscl . -list /Users` record and no `NFSHomeDirectory` pointing to it. Skip `Shared`, `Guest`, `Deleted Users` itself and `.localized`.
- **Default.** Review (unchecked). **Privilege.** Helper. **Delete mode.** Trash (the user's own Trash via the helper) or permanent after a typed confirmation.

### 5.21 Leftovers (CMM3 System Junk; moved to Applications in 5.x)

- **What.** Junk left by uninstalled apps; not selected by default (VERIFIED-V `[CMM3-Help/2]`). In 5.x it lives under Applications › Leftovers (VERIFIED-K 01-overview.md).
- **Ownership.** Handled by the Applications/Uninstaller track. Keep the category ID so System Junk can link to it.

### 5.22 Photo Junk (legacy; optional)

- **Vendor categories (VERIFIED-V `[CMM3-Help/3]`).** RAW Originals, Faces Cache, Photos Cache, iCloud Local Copies. Only Photos Cache and Faces Cache are smart-selected. Photo Junk is not in the App Store edition of X (VERIFIED-K) and was dropped as a module in 5.x (VERIFIED-K 01-overview.md).
- **Our scope (INFERRED; modern Photos libraries are SQLite-backed packages, so editing their internals is risky):**
  - **Review, Photos must be quit:**
    - `~/Library/Containers/com.apple.Photos/Data/Library/Caches/*`
    - `~/Library/Containers/com.apple.photolibraryd/Data/Library/Caches/*`
    - `~/Library/Caches/com.apple.photoanalysisd` (Mole lists it as "Photo analysis cache", VERIFIED-OSS)
    - `~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/*` (Mole, VERIFIED-OSS)
  - **Risky, off by default:** inside `~/Pictures/*.photoslibrary`, the `resources/caches/*` and `private/com.apple.photoanalysisd/caches/*` trees. The daemons may hold them open even when Photos is closed.
  - **Not implemented as file deletion:**
    - "iCloud Local Copies": instead deep-link to Photos ▸ Settings ▸ iCloud ▸ *Optimize Mac Storage*;
    - "RAW Originals": destructive.

### 5.23 Mail Attachments (`mailAttachments`)

- **What (VERIFIED-V `[CMM3-Help/4]`).**
  - Local copies of attachments that were opened or viewed. Mail keeps them until the message is deleted.
  - CleanMyMac smart-selects only locally stored, recoverable attachments and Mail downloads, ignoring modified ones. They can be brought back by opening the email.
  - It never removes attachments from the online mailbox.
  - Results group by Mail account, Last view date or File kind.
- **More vendor detail.**
  - Edited copies are labelled "changed by user" (VERIFIED-K DE KB).
  - In Business auto-clean (VERIFIED-K).
  - Part of the Smart Care basics (VERIFIED-K).
- **Paths.**
  - `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*`: the "opened attachment" copies, and the safest part. Lemon and Mole both target it. Mole also checks legacy `~/Library/Mail Downloads`, with ≥ 5 MB and ≥ 30 days as its own thresholds (VERIFIED-OSS).
  - `~/Library/Mail/V*/<account-UUID>/**/<mailbox>.mbox/**/Attachments/<message-id>/<part>/<file>`: downloaded parts. Use the highest `V*` directory present (INFERRED). Lemon has a `type="mail"` action over `~/Library/Mail/` (VERIFIED-OSS).
  - (added) **The Mail store is `V10` from macOS 13 Ventura through 26 Tahoe.** Probe `V11` → `V10` → `V9` to survive a future bump. VERIFIED-OSS, secondary: the design doc of a 2026 Apple-Mail integration says "V10 is current from Ventura through Tahoe; V11 guards against a future bump" (https://github.com/tacogips/apple-gateway `design-docs/specs/design-apple-mail.md`).
- **Recoverability (INFERRED rule; detection method now VERIFIED-OSS).**
  - Only attachments of **server-backed accounts** (IMAP, iCloud, Exchange) are re-downloadable.
  - **Never** select attachments under `~/Library/Mail/V*/Mailboxes/` (On My Mac) or POP accounts.
  - **How to detect account type (added).** Each `~/Library/Mail/V10/<UUID>` folder name is an Internet Accounts identifier.
    - Look it up in `~/Library/Accounts/Accounts4.sqlite` (needs FDA; open a read-only copy).
    - Query: `SELECT ZACCOUNTTYPE FROM ZACCOUNT WHERE ZIDENTIFIER = ?`, then `SELECT ZIDENTIFIER FROM ZACCOUNTTYPE WHERE Z_PK = ?`.
    - Type identifiers: `com.apple.account.IMAP` (or `…IMAPMail`), `com.apple.account.POP`, `com.apple.account.Exchange`, and the local "On My Mac" type (`com.apple.account.LocalOnMyMac` in one test fixture).
    - iCloud Mail is an IMAP account. One implementation tells it apart by a `ZACCOUNTPROPERTY` row with `ZKEY = 'UseMailDrop'`, and labels that a heuristic, not an Apple contract.
    - Sources (VERIFIED-OSS): https://github.com/tylern91/apple-mail-mcp `crates/amx-store/src/account.rs`; https://github.com/like-a-freedom/rusty_apple_mail_mcp `src/accounts.rs`; forensic schema in https://github.com/ydkhatri/mac_apt `plugins/inetaccounts.py`.
  - Treat a UUID with no row, an unknown type, or `POP` as **non-recoverable** (unchecked, reason `local only`). IMAP, iCloud and Exchange count as recoverable (INFERRED).
  - "Changed by user" means file mtime is later than its creation/download time, or a `kMDItemLastUsedDate` edit marker. Leave those unselected with that label.
- **Exclusions.** `Envelope Index*`, `MailData`, `.emlx` messages themselves.
- **Privilege and gates.** FDA required. (corrected) Mole **skips** Mail Downloads entirely while Mail is running (`_mail_process_state`, VERIFIED-OSS `user.sh`). Warning is not enough: skip with reason `in use` until Mail quits (INFERRED).
- **Delete mode.** Permanent.
- **Other clients (later).** Spark (`~/Library/Group Containers/*.com.readdle.smartemail*/…`) and Outlook (`~/Library/Group Containers/UBF8T346G9.Office/Outlook/…`). The X KB notes Spark mail is recoverable by reopening and Outlook via "Repair Folders" (VERIFIED-K 02-smart-care.md).

### 5.24 Trash Bins (`trashBins`)

- **What.**
  - CMM3: Local Mail Trash, Aperture Trash, iPhoto Trash, Photos Trash, Gemini Duplicates, Startup Drive Trash (incl. items removed from iCloud), and External Drive Trash (one per drive). Everything is auto-selected (VERIFIED-V `[CMM3-Help/6]`).
  - 5.x: Mail, Photos, Gemini Duplicates, Startup drive and External drives (VERIFIED-K trash-bins KB).
  - The CLI cleans "the system and mounted-volume Trash" (VERIFIED-V `[CLI]`).
  - **Do one-click scans empty *every* trash, including external drives? (gap, partly answered)**
    - CMM3 Smart Cleanup scans trash "on your Mac, on external drives, and in the Photos and Mail apps" (VERIFIED-V topic-1).
    - The Trash Bins module "smart-selects all trashed items in all trash bins" (VERIFIED-V topic-6).
    - The 2026 CLI's plain `clean` includes system **and mounted-volume** trash (VERIFIED-V README).
    - So MacPaw's historical and current default is "all trashes, external drives included".
    - Whether 5.x Smart Care's Cleanup tile pre-checks external-drive trash is still not confirmed from a 5.x source.
    - Our choice stays as in 02-smart-care.md: startup-disk trash checked; external-volume trash listed but unchecked in the one-click scan (it may be a backup disk) and checked in the dedicated Trash Bins view.
- **Paths and mechanisms.**

| Row | Path / mechanism | Default | Notes |
|---|---|---|---|
| Startup Drive Trash | `~/.Trash/*` | auto | Needs FDA to list (Mole prints "skipped, grant Full Disk Access", VERIFIED-OSS). Mole deletes directly instead of via Finder AppleScript, to avoid Finder's "empty Trash?" dialog (VERIFIED-OSS) |
| External drive "<Volume>" | `/Volumes/<vol>/.Trashes/<uid>/*` | auto | One row per mounted volume (mac-cleanup-py/-sh use `/Volumes/*/.Trashes/*`, VERIFIED-OSS; we limit to **our uid**). Skip read-only volumes and network shares |
| Other users' trash | `/Volumes/<vol>/.Trashes/<other-uid>`, `/Users/<other>/.Trash` | never (unless admin opt-in) | INFERRED |
| Mail Trash | Mail's trash mailboxes (local `Deleted Messages`) | review | Empty via Mail scripting, not the file system (Envelope Index consistency). INFERRED |
| Photos "Recently Deleted" | inside the Photos library DB | review | No safe FS route. Show size if detectable and deep-link the user to the album. INFERRED |
| App trash folders | e.g. third-party apps' internal trash | review | Gemini Duplicates is a MacPaw-specific category we don't need. INFERRED |

- **Emptying details (INFERRED).**
  - Delete children, never the `.Trash` folder itself.
  - Clear `uchg` with `chflags -R nouchg` on locked items after confirmation, as Finder does.
  - Root-owned items go through the helper.
  - Respect the Finder "Remove items from the Trash after 30 days" setting only as information.
  - The CMM3 "Remove Securely" mode is not reproduced (§4.8).

### 5.25 Other junk worth covering (INFERRED, sourced where noted)

- **Saved Application State.** `~/Library/Saved Application State/*.savedState` older than 30 days, owner not running. Review (Mole's saved-state age is 30 d, VERIFIED-OSS).
- **QuickLook thumbnails.** Use `qlmanage -r cache`. Auto, low value.
- **`.DS_Store` files.** Not default. Mole caps them at 500 per scan (VERIFIED-OSS). Pointless for space.
- **AppleDouble `._*` files on non-Mac volumes.** Review per external volume. Mole prunes `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.DocumentRevisions-V100` and `.TemporaryItems` while scanning (VERIFIED-OSS).
- **Privacy items, not cleanup.** Recent items (`~/Library/Application Support/com.apple.sharedfilelist/*.sfl*`), `QuarantineEventsV2` (Lemon's "Download Logs"). Leave them to the Protection › Privacy track.
- **Items added by the fact-check pass** (details in the sections cited):
  - Spotify updater archives (§5.13, C31);
  - Microsoft AutoUpdate pending clones (§5.13, C30b);
  - Podcasts downloaded episodes (§5.18, M5);
  - Music `Downloads-Music` and TV `Downloads-TV` partial downloads (§5.18, M4);
  - Xcode 15+ simulator runtime images (§5.14, X14);
  - non-DMG leftovers in `/Users/Deleted Users/` (§5.20, U1);
  - `~/Library/DiagnosticReports` (§5.3, L2b);
  - Apple's built-in `/tmp` janitor (§5.5);
  - Mail account typing via `Accounts4.sqlite` (§5.23).
- **iCloud Drive state (added; INFERRED, verify on device).** Keep `~/Library/Application Support/CloudDocs/**` and `~/Library/Caches/com.apple.bird*` out of every rule, next to the verified `CloudKit*` exclusion. They hold iCloud Drive sync state, and deleting them can force a full re-sync or eviction confusion.
- **Never, though users often ask.** `/private/var/vm/sleepimage` and swap files, `/private/var/db/receipts`, `/Library/Application Support` wholesale, `~/Library/Mobile Documents` (iCloud Drive), Time Machine backups (the Performance module thins local snapshots).

---

## 6. Definitive path catalog with safety ratings

**How to read the table.**

- **Rating:**
  - **safe**: regenerable or already discarded; auto-select allowed.
  - **review**: list it unchecked.
  - **risky**: off by default, advanced only.
  - **never**: protected; never list as removable.
- **Priv:**
  - U = user;
  - H = root helper;
  - F = Full Disk Access;
  - A = App Management TCC;
  - Auto = Apple-Events automation.
- **Gate:**
  - R = skip if the owner app is running;
  - O = skip if a file is open;
  - Age = age threshold.
- **Evidence:**
  - V = vendor (CMM3 Help, CLI);
  - K = vendor KB via sibling reports;
  - Mo = Mole;
  - Le = Lemon;
  - Mc = mac-cleanup-py/sh;
  - DC = DevCleaner;
  - Mn = Monolingual;
  - Pe = Pearcleaner;
  - MS = MacSai;
  - MO = MacOptimizer;
  - I = INFERRED.
- Unless stated otherwise, "Default" is **ours**.

### 6.1 Caches

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| C1 | `~/Library/Caches/<child>/*` | userCaches | ✔ | safe | U | R,O,≥1h | V(CMM3-2), K, Mo, Mc, MS |
| C2 | `~/Library/Containers/<id>/Data/Library/Caches/*` | userCaches | ✔ | safe | U (+F on 14+) | R,O | Mo, I |
| C3 | `~/Library/Containers/<id>/Data/tmp/*` (Apple utility containers listed by Mole) | userCaches | ✔ | safe | U | R,O | Mo |
| C4 | `~/Library/Group Containers/<grp>/Library/Caches/*` | userCaches | ✔ (non-Apple) / review (Apple) | safe/review | U | R,O | Mo |
| C5 | `~/Library/Application Support/<Chromium/Electron app>/{Cache,Code Cache,GPUCache,DawnGraphiteCache,DawnWebGPUCache,ShaderCache}` | userCaches | ✔ | safe | U | R | Mo, Mc |
| C6 | `…/<browser profile>/Service Worker/CacheStorage` | userCaches | ☐ | review | U | R | I |
| C7 | `~/Library/Caches/com.apple.Safari/*`, `~/Library/Caches/com.apple.WebKit.Networking/*` | userCaches | ✔ | safe | U (+F) | R | Mo, Le |
| C8 | `~/Library/Caches/Google/Chrome/*`, `…/BraveSoftware/Brave-Browser/*`, `…/com.microsoft.edgemac/*`, `…/Firefox/Profiles/*/cache2` | userCaches | ✔ | safe | U | R | Mo, Le |
| C9 | `~/Library/Caches/com.spotify.client/**`, `~/Library/Application Support/Spotify/PersistentCache/Storage/**` (corrected: the offline store) | — | — | **never** | — | — | K (Safety DB), S (5.x KB), OSS (path) |
| C10 | `~/Library/Caches/CloudKit*`, `com.apple.FontRegistry*`, `com.apple.Spotlight*`/`spotlight*` | — | — | **never** | — | — | Mo (safety whitelist), Le |
| C11 | `~/Library/Caches/com.apple.appstoreagent` | — | — | **never** | — | — | Le (macOS 15 updates-list issue) |
| C12 | `~/Library/Caches/Metadata/` | — | — | **never** | — | — | Le |
| C13 | `~/Library/Caches/com.apple.nsurlsessiond/` | — | — | **never** | — | — | I |
| C14 | `~/Library/Caches/com.apple.iconservices*`, `/Library/Caches/com.apple.iconservices.store`, `com.apple.dock.iconcache` | systemCaches | ☐ | risky | U/H | — | Le (excluded), I |
| C15 | `~/Library/Caches/JetBrains*`, `ms-playwright*`, `pypoetry/virtualenvs*`, `org.R-project.R/R/renv/*` | — | — | **never** (default) | — | — | Mo |
| C16 | `~/Library/Caches/com.apple.QuickLook.thumbnailcache` / `qlmanage -r cache` | systemCaches | ✔ | safe | U | — | Mo, I |
| C17 | `~/Library/Caches/GeoServices/*` (Maps tiles) | userCaches | ✔ | safe | U | R | Mo |
| C18 | `~/Library/Caches/com.apple.akd`, `~/Library/IdentityCaches/*` | userCaches | ☐ | review | U | R | Mo (cleans), I (caution) |
| C19 | `~/Library/Suggestions/*` | userCaches | ☐ | review | U | — | Mo, I |
| C20 | `~/Library/Messages/Caches/Previews/{Attachments,StickerCache}/*` | userCaches | ✔ | safe | U+F | R(Messages) | Mo |
| C21 | `/Library/Caches/<child>` (older than 7 d; Mole: only `*.cache`/`*.tmp`/`*.log` files, corrected) | systemCaches | ✔ | safe/review | H | Age 7d | V(CMM3-2), Le, Mo |
| C22 | `/Library/Caches/{Desktop Pictures,ColorSync}/`, `*Aerial*` | — | — | **never** | — | — | Le |
| C23 | `/System/Library/Caches/*` | — | — | **never** (SSV/SIP) | — | — | I (Mc tries it — anti-pattern) |
| C24 | `$(getconf DARWIN_USER_CACHE_DIR)` → `/private/var/folders/<2>/<h>/C/*/com.apple.{metal,metalfe,gpuarchiver}` | systemCaches | ✔ | safe | U | Age 1d | Mo |
| C25 | `/private/var/folders/<2>/<h>/C/*` (other) | systemCaches | ☐ | review | U | R,O | I |
| C26 | `/private/var/folders/*/C/com.paceap.eden.iLokLicenseManager*`, `…/com.native-instruments*`, `…/com.avid.mediacomposer*`, EDR vendors | — | — | **never** | — | — | Mo |
| C27 | `/private/var/folders/<2>/<h>/X/*.code_sign_clone` (browser clones) | systemCaches | ☐ | review | U | R | Mo |
| C28 | root `…/com.apple.idleassetsd/**/CFNetworkDownload_*.tmp` (aborted Aerials) | systemCaches | ✔ | safe | H | Age 7d | Mo |
| C29 | `~/Library/Caches/<bundle-id>/org.sparkle-project.Sparkle/{PersistentDownloads,Installation}/*` older than 10 d | oldUpdates | ✔ | safe | U | R, Age 10d | OSS (Sparkle source; Sparkle self-prunes at 10 d) |
| C30 | `~/Library/Caches/com.microsoft.autoupdate2` (plain cache) | oldUpdates | ✔ | safe | U | R | I |
| C30b | `/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex/*` (pending-update app clones), `/Library/Caches/com.microsoft.autoupdate.fba/`, `$TMPDIR/MSauClones` (corrected: split from C30) | oldUpdates | ☐ | review | H | MAU not running | OSS (pbowden-msft, MOFA) |
| C31 | `~/Library/Application Support/Spotify/PersistentCache/Update/*.tbz` | oldUpdates | ✔ | safe | U | R(Spotify) | OSS |

### 6.2 Logs and temporary files

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| L1 | `~/Library/Logs/*` (keep the `DiagnosticReports` dir) | userLogs | ✔ | safe | U | O, Age 7d | V(CMM3-2), Mo |
| L2 | `~/Library/Logs/DiagnosticReports/*.{ips,crash,diag,spin,hang}` | userLogs | ✔ | safe | U | Age 7d | Mo |
| L2b | `~/Library/DiagnosticReports/*` (if present; added) | userLogs | ✔ | safe | U | Age 7d | Mo |
| L3 | `~/Library/Containers/*/Data/Library/Logs/*` (e.g. `com.apple.mail/Data/Library/Logs/Mail/*`) | userLogs | ✔ | safe | U | O | Mc, Mo |
| L4 | `~/Library/Application Support/CrashReporter/*` | userLogs | ✔ | safe | U | — | MO |
| L5 | `~/Library/Logs/{JetBrains,CoreSimulator,Claude,Zed}/*` | userLogs | ✔ | safe | U | O | Mo, Mc |
| L6 | `~/Library/Logs/<our app>/` | — | — | **never** | — | — | Mo (protects own log) |
| L7 | `/Library/Logs/*` (files > 10 KB per Lemon) | systemLogs | ✔ | safe | H | O | V(CMM3-2), Le |
| L8 | `/Library/Logs/DiagnosticReports/*` | systemLogs | ✔ | safe | H | Age 7d | Le, Mo, Mc |
| L9 | `/Library/Logs/{Adobe,CreativeCloud}/*`, `/Library/Logs/adobegc.log` | systemLogs | ✔ | safe | H | O | Mo, Mc |
| L10 | `/private/var/log/*.log` (age), `*.gz`, `*.bz2`, `*.log.N`, `*.out` | systemLogs | ✔ | safe | H | O, Age 7d | Le, Mo |
| L11 | `/private/var/log/install.log` | systemLogs | ☐ | review | H | — | I |
| L12 | `/private/var/log/asl/*.asl`, `/private/var/log/DiagnosticMessages/*` (legacy) | systemLogs | ✔ | safe | H | — | Le, Mc |
| L13 | `/private/var/log/cups/{access_log*,page_log*,error_log*}` | systemLogs | ✔ | safe | H | — | Le |
| L14 | `/private/var/db/diagnostics/**` (unified log) | systemLogs | ☐ | review | H | Age 7d | Le, Mo, I (`log erase` alternative) |
| L15 | `/private/var/db/uuidtext/**` | — | — | **never** | — | — | I |
| L16 | `/private/var/db/DiagnosticPipeline/*`, `/private/var/db/powerlog/*` (not the active DB) | systemLogs | ☐ | review | H | Age 7d | Mo |
| L17 | `/private/var/db/reportmemoryexception/MemoryLimitViolations/*` | systemLogs | ☐ | review | H | Age 30d | Mo |
| T1 | `$(getconf DARWIN_USER_TEMP_DIR)` → `/private/var/folders/<2>/<h>/T/*` (files) | tempFiles | ✔ (narrow) | review | U | O, Age 3d | I (Mo avoids generic sweeps) |
| T2 | `/private/tmp/*` (own regular files only) | tempFiles | ☐ | risky | U | O, Age 3d | I, Mo (refuses generic sweep) |
| T3 | `/private/var/tmp/*` | tempFiles | ☐ | risky | H | O | I, Mo |

### 6.3 App bundles (Language Files and Universal Binaries)

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| B1 | `/Applications/**/*.app/**/Resources/<lang>.lproj` files that are unsealed **or sealed as `optional`** (the codesign default for `*.lproj`), not in the keep set | languageFiles | ☐ | review | H+A | R | V(CMM3-2), APPLE (TN2206, codesign rules), Mn, Le (corrected) |
| B2 | `.lproj` files sealed as **required** (custom resource rules) | — | — | **never** (corrected: no re-sign mode) | — | — | Mn (blocklists non-optional sealed files), APPLE |
| B3 | `Base.lproj`, `en.lproj`, `English.lproj`, the dev-region lproj, user-language lproj | — | — | **never** | — | — | Mn, Le |
| B4 | `com.apple.*` apps, MAS apps (`_MASReceipt`), `com.microsoft.*`, 1Password, IINA, iOS-on-Mac apps | — | — | **never** | — | — | Le, I |
| B5 | `/System/**` (`/System/Applications`, `/System/Library/**/*.lproj`) | — | — | **never** (SSV) | — | — | Mn (`/System` excluded), I |
| B6 | Fat Mach-O slices `x86_64`/`x86_64h`/`i386`/`ppc*` in `/Applications/*.app` | universalBinaries | ☐ | risky (seal stays valid per TN2206; risk is plug-ins, Rosetta and updates) | H+A | R | V(CMM3-2), APPLE (TN2206), Mn, Pe |
| B7 | Frameworks of single-arch apps | — | — | **never** (thinning) | — | — | Mn (#67) |

### 6.4 Login items and preferences

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| P1 | `~/Library/LaunchAgents/*.plist` with missing absolute `Program`/`ProgramArguments[0]` | brokenLoginItems | ✔ | safe | U | — | V(CMM3-2), Mo, I |
| P2 | `/Library/LaunchAgents/*.plist`, `/Library/LaunchDaemons/*.plist` (non-`com.apple`) with missing target | brokenLoginItems | ☐ | review | H | — | Mo |
| P3 | `/Library/PrivilegedHelperTools/*` whose parent app is gone and no plist references it | brokenLoginItems | ☐ | review | H | — | Mo |
| P4 | BTM "Open at Login" items whose URL is missing (`sfltool dumpbtm` to read; System Events to delete) | brokenLoginItems | ✔ | safe | U+Auto | — | I |
| P5 | `com.apple.*` launch items; BTM reset (`sfltool resetbtm`) | — | — | **never** | — | — | Mo, I |
| P6 | `~/Library/Preferences/*.plist`, `ByHost/*.plist`, container prefs: zero-byte or unparseable | brokenPreferences | ✔ | safe | U | R | V(CMM3-2), I |
| P7 | `~/Library/Preferences/*.plist.<random>` orphan temps / stale `*.lockfile` (> 1 d) | brokenPreferences | ✔ | safe | U | — | I |
| P8 | `.GlobalPreferences*`, `com.apple.{dock,finder,loginwindow}.plist`, ByHost Bluetooth/Wi-Fi, `org.cups.*`, input methods | — | — | **never** | — | — | Mo |

### 6.5 Documents, downloads and updates

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| D1 | `/.DocumentRevisions-V100` via `NSFileVersion` (4-h rule) | documentVersions | ✔ (rule only) | review | F (+H for discovery) | doc not open | V(CMM3-2), K, APPLE |
| D2 | direct file deletion inside `.DocumentRevisions-V100` | — | — | **never** | — | — | I |
| D3 | `~/Downloads/**/*.{dmg,iso,sparseimage,sparsebundle}` not mounted, > 7 d | unusedDiskImages | ☐ (✔ if app installed and > 30 d) | review | U | mounted? | MO, MS, I |
| D4 | `~/Downloads/**/*.{download,crdownload,part,partial}` | brokenDownloads | ✔ | safe | U | O, Age 1d | K (Safari rule), Mo, MS |
| D5 | Slack-sourced files in `~/Downloads` (`kMDItemWhereFroms`), ≥ 30 d | brokenDownloads | ✔ (vendor rule) → Trash | review | U | — | K, I |
| D6 | `/Applications/Install macOS *.app` (> 14 d, not current OS, not running) | oldUpdates | ☐ | review | H+A | R | Mo |
| D7 | Chromium `…/Frameworks/<X> Framework.framework/Versions/<old>` | oldUpdates | ☐ | review | H+A | R | Mo |
| D8 | `/Library/Updates/*`, `/macOS Install Data` | — | — | **never** | — | — | Mo |
| D9 | `~/Downloads/*.{pkg,mpkg}` > 7 d | unusedDiskImages (installers) | ☐ | review | U | — | MS |

### 6.6 Developer tools

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| X1 | `~/Library/Developer/Xcode/DerivedData/*` | xcodeJunk | ✔ | safe | U | Xcode not running | V(CMM3-2, CLI), Mo, DC, Le, Mc |
| X2 | `…/DerivedData/ModuleCache.noindex` | xcodeJunk | ☐ | review | U | Xcode | V(CMM3-2: not auto), DC |
| X3 | `~/Library/Developer/Xcode/Archives/**` | xcodeJunk | ☐ | risky | U | — | V(CMM3-2: not auto), DC, Le, Mo(report) |
| X4 | `~/Library/Developer/Xcode/*OS DeviceSupport/*` except newest per OS | xcodeJunk | ✔ | safe | U | — | V(CLI), DC, Mo |
| X5 | newest DeviceSupport per OS | xcodeJunk | ☐ | review | U | — | DC |
| X6 | `~/Library/Developer/Xcode/{iOS Device Logs,DeviceLogs}/*` except latest | xcodeJunk | ✔ | safe | U | — | DC, Le, Mc |
| X7 | `~/Library/Developer/Xcode/DocumentationCache/*` except current | xcodeJunk | ✔ | safe | U | — | V(CLI), DC, Le |
| X8 | `~/Library/Developer/Shared/Documentation/DocSets/*` | xcodeJunk | ☐ | review | U | — | DC |
| X9 | `~/Library/Developer/Xcode/UserData/{IB Support,Previews}/*`, `~/Library/Developer/Xcode/Products/*` | xcodeJunk | ✔ | safe | U | Xcode | Mo, MS |
| X10 | `~/Library/Caches/com.apple.dt.Xcode/*` | xcodeJunk | ✔ | safe | U | Xcode | Le, Mo |
| X11 | `xcrun simctl delete unavailable` | xcodeJunk | ✔ | safe | U | no booted sim | Mo |
| X12 | `~/Library/Developer/CoreSimulator/Caches/*`; runtime `RuntimeRoot/System/Library/Caches/*` | xcodeJunk | ✔ | safe | U | no booted sim | Mo, I |
| X13 | `~/Library/Developer/CoreSimulator/Devices/*` (all) | xcodeJunk | ☐ | review | U | — | Mo(report), Le |
| X14 | `/Library/Developer/CoreSimulator/{Profiles/Runtimes,Volumes,Images,Cryptex/Images/bundle}/*` → only via `xcrun simctl runtime delete` (never direct `rm`) | xcodeJunk | ☐ | review | H | — | Le, Mo, OSS (Images path added) |
| X15 | `~/Library/Developer/XCTestDevices/*`, `~/Library/Logs/CoreSimulator/*` | xcodeJunk | ✔ | safe | U | — | Mo, Mc |
| V1 | Homebrew (`brew cleanup --prune=30`), `~/Library/Caches/Homebrew/downloads/*` | devJunk | ✔ | safe | U | brew idle | V(CLI), Mo, Mc |
| V2 | npm `~/.npm/_cacache` (`npm cache clean --force`) | devJunk | ✔ | safe | U | — | V(CLI), Mo, Mc |
| V3 | Yarn `~/Library/Caches/Yarn/*`; pip `~/Library/Caches/pip`; uv; Bun `~/.bun/install/cache`; CocoaPods `~/Library/Caches/CocoaPods/*` | devJunk | ✔ | safe | U | — | V(CLI), Mo, Mc |
| V4 | pnpm store `~/Library/pnpm/store` (`pnpm store prune`) | devJunk | ☐ | review | U | — | V(CLI), Mo(report) |
| V5 | Poetry `~/Library/Caches/pypoetry/{cache,artifacts}` | devJunk | ✔ | safe | U | — | Mo |
| V6 | Cargo `~/.cargo/registry/{cache,src}` | devJunk | ✔ | safe | U | — | V(CLI), MS |
| V7 | `~/.cargo/bin`, `~/.rustup`, `~/.mix/archives`, `~/.stack/programs` | — | — | **never** | — | — | Mo |
| V8 | Go build cache (`go clean -cache`) / module cache (`go clean -modcache`) | devJunk | ✔ / ☐ | safe/review | U | — | V(CLI), Mo, Mc |
| V9 | Gradle `~/.gradle/{daemon,notifications,workers}/*`, `caches/build-cache-*/*` | devJunk | ✔ | safe | U | Gradle idle | I (corrected: Mole *whitelists* `~/.gradle/daemon/*` and `~/.gradle/caches/*` by default) |
| V10 | Gradle `~/.gradle/caches` (modules-2) | devJunk | ☐ | review | U | — | S (vendor exception), Mo |
| V11 | Maven `~/.m2/repository`, Ivy `~/.ivy2/cache`, NuGet `~/.nuget/packages` | devJunk | ☐ | review | U | — | Mo(report), Mc(prompt) |
| V12 | Docker `Docker.raw` | — | — | **never** (direct) → `docker system df` / prune on request | U | — | V(CLI lists Docker), Mo(report), Mc(prompt) |
| V13 | VS Code `~/Library/Application Support/Code/{Cache,CachedData,CachedExtensionVSIXs,Code Cache,GPUCache,logs}` | devJunk | ✔ | safe | U | R | V(CLI), I |
| V14 | JetBrains old-version cache dirs | devJunk | ☐ | review | U | R | V(CLI), Mo |
| V15 | `~/.android/{cache,build-cache}/*`, `~/Library/Caches/Google/AndroidStudio*/*` | devJunk | ✔ | safe | U | R | Mo, Mc |
| V16 | `~/.cache/{pre-commit,ruff,mypy,eslint,prettier,typescript,vite,webpack,node-gyp,bazel,terraform,prisma,zig}/*` | devJunk | ✔ | safe | U | — | Mo |
| V17 | `~/.cache/puppeteer/*`, `~/Library/Caches/ms-playwright*` (browser binaries) | devJunk | ☐ | review | U | — | Mo (Playwright whitelisted) |
| A1 | `~/Library/Caches/com.anthropic.claudefordesktop/*`, `~/Library/Logs/Claude/*`, `~/Library/Caches/com.openai.chat/*` | aiJunk | ☐ | safe | U | R | V(CLI "AI Junk"), Mo |
| A2 | `~/.claude/{cache,paste-cache,shell-snapshots}`, `~/.codex/{.tmp,cache}` | aiJunk | ☐ | review | U | R | MS |
| A3 | AI history/sessions/settings; `~/.ollama/models`, `~/.lmstudio/models` | — | — | **never** | — | — | Mo, MS |

### 6.7 iOS devices and media

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| I1 | `~/Library/Application Support/MobileSync/Backup/<UDID>[-date]/` — latest per device | iosBackups | ☐ | review | F | — | V(CMM3-5: latest never auto), K |
| I2 | same — older/archived | iosBackups | ☐ (optional ✔ if > 180 d, device unseen) | review | F | — | V, Le (`recommend=NO`), Mo(report) |
| I3 | `~/Library/iTunes/{iPhone,iPad,iPod} Software Updates/*.ipsw` | iosSoftware | ✔ | safe | U | — | V(CMM3-5), Le, Mo |
| I4 | `~/Library/Group Containers/*.group.com.apple.configurator/**/*.ipsw` | iosSoftware | ✔ | safe | U | — | Mo |
| I5 | `~/Music/iTunes/iTunes Media/Mobile Applications/*.ipa` | iosSoftware | ☐ | review | U | — | V(CMM3-5), Mc |
| I6 | `~/Pictures/iPod Photo Cache/` | iosSoftware | ✔ | safe | U | — | V(CMM3-2), Le |
| M1 | `~/Library/Containers/com.apple.AMPArtworkAgent/Data/Library/Caches/*` (album art) | mediaJunk | ✔ | safe | U | R(Music) | V(CMM3-5 "iTunes Cache"), Mo |
| M2 | `~/Library/Caches/{com.apple.Music,com.apple.TV,com.apple.podcasts}` | mediaJunk | ✔ | safe | U | R | Mo |
| M3 | `~/Library/Containers/com.apple.podcasts/Data/tmp/{StreamedMedia,*.heic,*.img,*CFNetworkDownload*.tmp}` | mediaJunk | ✔ | safe | U | R | Mo |
| M4 | Music/TV incomplete downloads: `~/Music/Music/Media.localized/Downloads-Music/*`, `~/Movies/TV/Media.localized/Downloads-TV/*.tmp`, legacy `~/Music/iTunes/iTunes Media/Downloads/*` (corrected: paths found) | mediaJunk | ✔ (`.tmp`/partial only, > 1 d) | safe | U | R(Music/TV), O | V(CMM3-5 "Broken Downloads"), OSS (paths) |
| M5 | Podcasts downloaded episodes `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache/*` | mediaJunk | ☐ | review (user content) | U(+F) | R(Podcasts) | OSS (path), I |

### 6.8 Deleted users, photos, mail and trash

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| U1 | `/Users/Deleted Users/*` (`<name>.dmg` archives **and** leftover folders) | deletedUsers | ☐ | review | H | — | K (group exists), OSS (DMG path: Jamf schema, admin scripts; folders: 2026 runbook, DFIR note) (corrected) |
| U2 | `/Users/<name> (Deleted)` / orphan homes with no `dscl` record | deletedUsers | ☐ | review | H | — | I |
| F1 | `~/Library/Containers/com.apple.Photos/Data/Library/Caches/*`, `…/com.apple.photolibraryd/Data/Library/Caches/*`, `~/Library/Caches/com.apple.photoanalysisd` | photoJunk | ☐ | review | U+F | Photos quit | V(CMM3-3 Photos Cache), Mo, I |
| F2 | `~/Pictures/*.photoslibrary/{resources/caches,private/com.apple.photoanalysisd/caches}/*` | photoJunk | ☐ | risky | U+F | Photos quit | V(CMM3-3 Faces/Photos cache), I |
| F3 | Photos library originals / `database/` / iCloud local copies | — | — | **never** (FS) | — | — | I |
| E1 | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*` (unmodified) | mailAttachments | ✔ | safe | U+F | — | V(CMM3-4), K, Le, Mo |
| E2 | `~/Library/Mail Downloads/*` (legacy) | mailAttachments | ✔ | safe | U+F | — | Mo |
| E3 | `~/Library/Mail/V*/<account>/**/Attachments/**` (IMAP/iCloud/Exchange) | mailAttachments | ✔ | safe/review | U+F | Mail quit (warn) | V(CMM3-4), K, Le |
| E4 | `~/Library/Mail/V*/Mailboxes/**/Attachments/**` (On My Mac), POP accounts (type from `~/Library/Accounts/Accounts4.sqlite`) | mailAttachments | ☐ | risky | U+F | — | I, OSS (detection method) |
| E5 | modified attachments ("changed by user") | mailAttachments | ☐ | review | U+F | — | K |
| E6 | `~/Library/Mail/V*/MailData/**`, `Envelope Index*`, `*.emlx` | — | — | **never** | — | — | I |
| R1 | `~/.Trash/*` | trashBins | ✔ | safe | U+F | — | V(CMM3-6), K, Mo, Mc |
| R2 | `/Volumes/<vol>/.Trashes/<our uid>/*` | trashBins | ✔ | safe | U | — | V(CMM3-6), K, Mc, Le |
| R3 | `/Volumes/<vol>/.Trashes/<other uid>`, other users' `~/.Trash` | — | — | **never** (default) | H | — | I |
| R4 | Mail trash (via Mail scripting) | trashBins | ☐ | review | Auto | Mail running | V(CMM3-6), K |
| R5 | Photos "Recently Deleted" (deep-link only) | trashBins | ☐ | review | — | — | V(CMM3-6), K |

### 6.9 Miscellaneous

| # | Path / pattern | Group | Default | Rating | Priv | Gate | Evidence |
|---|---|---|---|---|---|---|---|
| S1 | `~/Library/Saved Application State/*.savedState` > 30 d | other | ☐ | review | U | R | Mo |
| S2 | `.DS_Store` (capped) / `._*` on external volumes | other | ☐ | review | U | — | Mo |
| N1 | `~/Library/Mobile Documents/**`, `~/Library/Keychains/**`, `/Library/Keychains/**`, `~/Library/Messages/Attachments/**`, `~/Library/Group Containers/group.com.apple.notes/**`, `~/Library/Application Support/AddressBook/**`, `/private/var/db/receipts/**`, `/private/var/vm/**`, `/Library/Application Support` (root) | — | — | **never** | — | — | Mo, I |

---

## 7. Consolidated built-in exception list (ship in Safety DB v1)

These are **never auto-selected**. Most are never shown either.

- **Media and user content inside caches:**
  - Spotify `~/Library/Caches/com.spotify.client` (VERIFIED-K/S) **and** `~/Library/Application Support/Spotify/PersistentCache/Storage` (the default offline store, VERIFIED-OSS; corrected);
  - Podcasts downloaded episodes (`243LU875E5.groups.com.apple.podcasts/Library/Cache`) → review;
  - Adobe Premiere/After Effects media caches → review;
  - DaVinci `~/Movies/CacheClip` → review (Mole cleans it, but it can be huge, active project data);
  - Steam shader caches → review.
- **Dependency stores:**
  - Gradle `~/.gradle/caches` (VERIFIED-S);
  - Maven `~/.m2`, Ivy, NuGet, pnpm store, Go modcache, Conda pkgs (review);
  - Poetry virtualenvs;
  - R renv (never);
  - Playwright browsers.
- **System-critical caches:**
  - `CloudKit*`, `com.apple.FontRegistry*`, `com.apple.Spotlight*`;
  - `Metadata`, `com.apple.iconservices*`, `com.apple.dock*`, `com.apple.finder` (Mole default);
  - `com.apple.appstoreagent` (Lemon);
  - `com.apple.nsurlsessiond` (INFERRED);
  - `com.apple.siriactionsd.ShortcutsSandboxCache`, `CCTClearcutLogger` (Mole);
  - CoreAudio caches (Mole);
  - Settings, Control Center and Finder containers (Mole).
- **Security software:** EDR/MDM agents' caches and temp (CrowdStrike, SentinelOne, ESET, Jamf, GlobalProtect, Cisco); iLok license manager (Mole).
- **Licenses and accounts:** password managers (1Password, Bitwarden, LastPass, Dashlane), keychains, VPN/proxy apps (Mole's `should_protect_data`).
- **Live runtimes:** OrbStack data, Docker raw disk, VMs (UTM/Parallels/VMware disk images; only their caches are cleanable).
- **AI tool state:** histories, sessions, model stores.
- **Our own app's** caches, logs, settings and quarantine.

---

## 8. What the open-source cleaners teach (comparison)

| Tool | What it is | What to copy | What to avoid |
|---|---|---|---|
| **tw93/Mole** (bash/Go CLI, very active 2025–26) | The most rigorous OSS macOS cleaner | Critical-root deny list with inode alias checks; safety vs default whitelists; tri-state running-owner gate; SQLite-family open-handle probe; bounded scans with timeouts; per-category age constants; op-log; dry-run; review-only reporting of big stores (Archives, sim data, backups, Docker, Maven) | — (very conservative; note it does not do language files, binaries, document versions or deleted users) |
| **MacPaw cleanmymac-cli** (proprietary; docs on GitHub) | MacPaw's own rules engine in CLI form | Category names (System Junk / Dev Tools / AI Junk); scan → review → confirm; `--force` semantics; ignore list; purge 7-day rule | — |
| **Tencent Lemon** (open source, GPL-style licence) | Chinese CleanMyMac-like suite | Declarative XML rule format (filters plus items plus actions, `recommend` flags); app-specific junk items (Xcode, Sketch); language-removal exclusions | Loose regex filters; some rules are now stale |
| **Monolingual** | Language and architecture remover | Code-signature seal blocklist that skips `optional` entries (so signed apps' localizations stay removable, corrected); SIP xattr check; never follow symlinks; English never removable; single-arch app framework exclusion; helper via SMAppService plus caller validation; Trash option | Default roots include `/Library` (too broad for a cleaner) |
| **Pearcleaner** (Apache-2.0 + Commons Clause) | Uninstaller with Lipo feature | In-process fat-header parsing for size estimates; search-location list (useful for leftovers) | No re-sign or verify step visible in `Lipo.swift`; licence forbids commercial reuse |
| **DevCleaner for Xcode** | Xcode junk GUI | Category set and "deselect newest" logic for Device Support/Doc cache/Logs; Archive metadata parsing (name, version, upload state) | Hard-codes internal Xcode folders (fragile) |
| **mac-cleanup-py / mac-cleanup-sh** | Simple scripts | Module list as a checklist | Deletes **all** iOS backups and Xcode Archives without review; sweeps `/System/Library/Caches`; hard-coded `/private/var/folders/bh/*` — anti-patterns |
| **MacSai / MacOptimizer** (CleanMyMac-style clones) | Category taxonomy mirrors | Confirms X/5.x group names | MacSai's `~/.DocumentRevisions-V100` path is wrong; MacOptimizer treats `~/Library/Cookies` as "user cache" (privacy data!) |

All rows VERIFIED-OSS from the cited repositories (§14).

---

## 9. Implementation sketch (Swift, macOS 14+)

### 9.1 Data model (INFERRED)

```swift
enum Selection { case auto, review, never }
enum DeleteMode { case permanent, trash, api(ApiAction), modifyInPlace(BundleOp) }
enum Privilege: Hashable { case user, helper, fullDiskAccess, appManagement, automation(String) }
enum SkipReason { case inUse, recent, latestBackup, changedByUser, protected, needsHelper,
                  needsFDA, sealed, mounted, ignored, unknownOwner, timedOut }

struct CleanupRule: Codable, Identifiable {      // one row in the Safety DB
    let id: String                                 // "systemJunk.userCaches"
    let roots: [String]                            // "~/Library/Caches"
    let enumerate: Enumeration                     // .children, .glob("*.ipsw"), .recursive(maxDepth)
    let selection: Selection
    let minAge: TimeInterval?
    let skipIfOwnerRunning: Bool
    let skipIfOpen: Bool
    let privileges: Set<Privilege>
    let deleteMode: DeleteMode
    let exclude: [String]; let review: [String]
}

struct JunkItem: Identifiable, Hashable {
    let id: UUID; let ruleID: String; let url: URL
    let allocatedBytes: Int64; let mayBeClone: Bool
    let modified: Date?; let ownerBundleID: String?
    var isSelected: Bool; var skipReason: SkipReason?
    let identity: (dev: dev_t, ino: ino_t, mtime: timespec)   // TOCTOU re-check
}
```

### 9.2 Pipeline (INFERRED)

1. **Preflight.**
   - FDA probe: try to list `~/Library/Mail` or `~/.Trash`.
   - Helper status: `SMAppService.daemon(plistName:).status`.
   - App Management status: attempt is deferred.
   - Running-apps snapshot; mounted volumes; Xcode/simctl availability.
2. **Scan** (concurrent `TaskGroup`, bounded to roughly CPU count; I/O-bound).
   - Each rule enumerates its roots with a deadline, yields candidates, applies exclusions, the ignore list, gates and the age filter, then sizes the item.
   - Root-only roots are requested from the helper with `scan(ruleIDs:)`. The helper returns `[path,size,mtime,identity]` for paths it derived itself.
3. **Selection** follows `Selection` plus category-specific selectors (document-version clusters, newest Device Support, latest backup, the "changed by user" check).
4. **Review UI.**
5. **Clean** in this order:
   1. `api` actions (simctl, brew, npm, Mail scripting, NSFileVersion);
   2. user-level permanent deletes;
   3. helper batch (`cleanSystemItems(ids:)`);
   4. Trash moves;
   5. modify-in-place (one app at a time, staged, verified).
   Re-check identity and gates before each delete.
6. **Measure and report.** Volume free space before and after; per-group results; failures with reasons; append to the op-log.

### 9.3 Helper XPC surface for Cleanup (INFERRED; no generic file operations)

```swift
@objc protocol CleanupHelper {
    func scanSystemJunk(ruleIDs: [String], reply: @escaping (Data /*[ScanRecord] JSON*/) -> Void)
    func cleanSystemJunk(itemTokens: [String], reply: @escaping (Data /*[Result]*/) -> Void) // tokens issued by the helper's own scan
    func listDocumentRevisionFiles(volume: String, reply: @escaping ([String]) -> Void)        // read-only DB copy
    func listBrokenLaunchItems(reply: @escaping (Data) -> Void)
    func removeLaunchItem(token: String, reply: @escaping (Bool, String?) -> Void)             // bootout + unlink, non-com.apple only
    func stripLocalizations(appToken: String, keep: [String], dryRun: Bool, reply: @escaping (Data) -> Void) // optional/unsealed .lproj files only; never Base.lproj; no re-sign (corrected)
    func thinApp(appToken: String, keepArchs: [String], reply: @escaping (Data) -> Void)       // stage → lipo → codesign --verify → swap
    func listDeletedUsers(reply: @escaping (Data) -> Void)
}
```

The listener uses `setConnectionCodeSigningRequirement` with our Team ID and bundle ID (see 02-smart-care.md §9). The helper only accepts **tokens it minted during its own scan**, never raw paths from the app.

### 9.4 Key algorithms (INFERRED)

**Device Support "keep newest per OS"** (as in DevCleaner):
1. Parse folder names like `iPhone15,2 17.5.1 (21F90)` or `17.5.1 (21F90) arm64e` into (device?, version, build, arch?).
2. Merge arch variants.
3. Sort descending by version and build.
4. Leave the first entry unchecked; check the rest.

**iOS backups:**
1. Group by `Target Identifier` from `Info.plist`.
2. Sort by `Last Backup Date`.
3. Leave the newest unchecked with the "latest backup" badge.
4. Older entries are unchecked and listed as review.

**Language keep set.** The union of:
- `Locale.preferredLanguages` expanded (`xx`, `xx-YY`, `xx_YY`, script forms);
- `Locale.current` identifiers;
- `en`, `Base`, the app's `CFBundleDevelopmentRegion`;
- per-app `AppleLanguages`;
- legacy display names (`English`, …).

Remove only files in `<x>.lproj` where x is not in the keep set **and** each file is either unsealed or sealed with `optional = true` in the bundle's `CodeResources` (`files2`). (corrected: the earlier wording said "not sealed", which would skip almost everything; codesign seals localizations as optional by default.)

**Universal thinning:**
1. Check the fat magic.
2. Compute the slices to drop.
3. `clonefile()` the bundle into staging.
4. `lipo -remove <arch>…` on each eligible binary in staging.
5. Run `codesign --verify --deep --strict --verbose=2` on the staged bundle.
6. Swap with `renamex_np(RENAME_SWAP)`.
7. Keep the original in the backup area for N days, or move it to the Trash.

**Broken plist:**
1. Treat `size == 0` as broken.
2. Otherwise, a failed `PropertyListSerialization.propertyList(from:data, options:[], format:nil)` means broken.
3. Also flag temp-suffix files and lockfiles older than 1 d.
4. Skip protected domains and running owners.

**Broken launch item:**
1. Load the plist.
2. Take `Program ?? ProgramArguments?.first`.
3. If the path is absolute and missing, the item is broken.
4. If it uses `BundleProgram` plus `AssociatedBundleIdentifiers`, check `NSWorkspace.urlForApplication(withBundleIdentifier:)`.
5. An unreadable plist is unknown, so keep it.

---

## 10. Test plan and edge cases (INFERRED)

- **Running apps.** Open Chrome, Slack, Xcode or Music during Review and confirm their rows flip to `in use` and are skipped at clean time.
- **SQLite caches.** Create a dummy cache DB held open by a process; it must not be deleted.
- **Symlink attacks.** Make `~/Library/Caches/evil → /Library/Keychains`. The scan must not follow it, and the helper must refuse.
- **Case aliases.** Paths like `/SYSTEM`, `/Users/SHARED` must be rejected.
- **FDA off.** Mail, Trash, MobileSync and container rows show "needs Full Disk Access". The scan does not crash and totals are labelled "partial".
- **Helper not approved.** System rows show `needs admin` and are unchecked.
- **External drives.** One Trash row per mounted writable volume. Disconnecting during the scan must be tolerated. Ignore network and read-only volumes.
- **Huge trees.** A 100 GB iOS backup with millions of files must report within its budget or show "size unknown" (Mole's lesson).
- **APFS clones.** A cloned 5 GB file in a cache shows the clone badge, and measured freed space is ≈ 0.
- **Snapshots.** With Time Machine local snapshots present, the completion screen explains the found-versus-freed difference.
- **Language/binaries.** After processing a test app (an unsigned sample and a notarized sample), run `codesign --verify --deep --strict`. The app must launch and keep its TCC grants, or else the item must have been skipped.
- **Document Versions.** Create a TextEdit doc with versions 10 min, 30 min, 5 h and 6 h apart. Check the selection matches the 4-h rule, and that the earliest and the current are never selected.
- **Xcode.** With Xcode open, the Xcode Junk group is skipped. `xcrun simctl delete unavailable` works when several Xcode versions are installed (`DEVELOPER_DIR` resolution).
- **Ignore list.** Ignoring `~/Library/Caches/com.foo` hides it in Cleanup and in Smart Scan, and prefix matches respect component boundaries.
- **Mail.** An On-My-Mac mailbox attachment is never selected; an IMAP one is. A modified attachment is labelled "changed by user".

---

## 11. Deliberate differences from CleanMyMac (INFERRED; document in-app)

1. **Language Files and Universal Binaries are unchecked by default**, with a seal-aware engine that removes only optional or unsealed `.lproj` files, never `Base.lproj`, and never re-signs. Vendor CMM3 pre-selected them. (corrected) The reason is App Management, update churn and Sparkle deltas, not seal breakage, because TN2206 says both operations keep the signature valid.
2. **No "macOS Localizations"** (sealed system volume).
3. **No secure erase.**
4. **Photo Junk is limited to container caches.** No RAW replacement or iCloud local-copy deletion; we deep-link to Optimize Mac Storage instead.
5. **iOS backups never auto-checked at all** in v1. The vendor only protects the latest.
6. **Dev Tools and AI Junk** are first-class groups, matching MacPaw's 2026 CLI.
7. **Personal-ish items go to the Trash**: disk images, Slack downloads, deleted-user DMGs, optionally backups.

---

## 12. Gaps and open questions

Each gap has a fact-check status (2026-10-12) at the end.

1. The **exact current (5.7.x) list of System Junk auto-selection exceptions**. I only have "Spotify and Gradle" from a search excerpt, plus the X-era rules. Fetch https://macpaw.com/support/cleanmymac/knowledgebase/system-junk when the network allows.
   - *Status: STILL OPEN.* macpaw.com, cleanmymac.com, apps.apple.com and setapp.com all failed DNS from this sandbox, and the shared search budget was exhausted. What was added: Spotify's real offline path (`PersistentCache/Storage`) for our rules.
2. How CleanMyMac 5 handles **code-signature seals** for Language Files and Universal Binaries: does it skip signed or MAS apps, or re-sign? Not documented in anything I could read.
   - *Status: PLATFORM QUESTION ANSWERED; VENDOR BEHAVIOUR STILL UNKNOWN.* Apple TN2206 says removing `.lproj` files from `Contents/Resources` and removing architecture slices both keep the signature valid. codesign's default rules mark localizations `optional` except `Base.lproj`. So no re-signing is needed, and CleanMyMac very likely does not re-sign (INFERRED). See §5.6 and §5.8.
3. **Document Versions discovery.** Does CleanMyMac read the `revisiond` DB, or walk files? (Likely the helper reads the DB.) Also whether it uses `NSFileVersion` or deletes store files.
   - *Status: VENDOR METHOD UNKNOWN; OUR METHOD NOW CONCRETE.* The DB schema (`files`, `generations`, the `.cs` chunk store) is verified from mac_apt, and the NSFileVersion contract is re-verified from Apple's docs. See §5.11.
4. **5.x status of Unused Disk Images, Old Updates and Downloads**: removed or merged? Inferred from the 5.x module map only.
   - *Status: STILL INFERRED, better argued.* The replica that lists them is explicitly a CleanMyMac **X** reconstruction. The 5.x 12-group list omits them. 5.x has Installation files (Applications) and Downloads (My Clutter). See §5.12.
5. Whether **Smart Care's Trash Bins step** empties every trash (including external drives) by default. Flagged UNVERIFIED in 02-smart-care.md as well.
   - *Status: PARTLY ANSWERED.* CMM3 Smart Cleanup scanned trash on external drives, and Trash Bins smart-selected everything. The 2026 CLI `clean` includes mounted-volume trash. No 5.x Smart Care source. See §5.24.
6. **Mail account-type detection** on current Mail versions (V10+ layout), and the exact location of Music/TV "broken downloads" on macOS 15/26. Verify on device.
   - *Status: ANSWERED (secondary OSS), still verify on device.* V10 runs from Ventura through Tahoe. Account type comes from `~/Library/Accounts/Accounts4.sqlite`. Music uses `~/Music/Music/Media.localized/Downloads-Music/`, TV uses `~/Movies/TV/Media.localized/Downloads-TV/` (`*.tmp`), and legacy iTunes used `~/Music/iTunes/iTunes Media/Downloads/`.
7. **Deleted Users artefact names** on macOS 14–26 (`/Users/Deleted Users/*.dmg`, `"<name> (Deleted)"`). Verify on device.
   - *Status: PARTLY ANSWERED.* `/Users/Deleted Users/<name>.dmg` is corroborated by the Jamf schema and admin scripts. Non-DMG leftovers inside `/Users/Deleted Users/` are reported by a 2026 runbook. The `(Deleted)` suffix is unverified.
8. Whether a root helper is still blocked by **App Management TCC** when modifying other apps' bundles on macOS 15/26. Verify on device.
   - *Status: LIKELY YES.* A September 2026 field report shows TCC denying a root process under `kTCCServiceSystemPolicyAppBundles`: "root authentication alone does not supply that permission". The Apple mechanism is from WWDC22. The user must grant App Management to our app. Verify on device.
9. **OnyX**: its cleaning categories could not be reviewed (titanium-software.fr was unreachable, and it is closed source). BleachBit has negligible macOS coverage. Neither changes the catalog above.
   - *Status: STILL OPEN* (same network limits). No new reviewer data points either: TidBITS, Macworld and 9to5Mac were unreachable, and search was exhausted.

---

## 13. Quick reference: commands and APIs used above

| Purpose | Command / API | Root? |
|---|---|---|
| Per-user Darwin dirs | `getconf DARWIN_USER_CACHE_DIR`, `getconf DARWIN_USER_TEMP_DIR` | no |
| QuickLook cache reset | `qlmanage -r cache` | no |
| Open-file check | `lsof -Fn +D <dir>` (bounded) or `proc_pidinfo`/`proc_pidfdinfo` | partly |
| Mounted images | `hdiutil info -plist` | no |
| Where-from metadata | `mdls -name kMDItemWhereFroms <file>` / xattr `com.apple.metadata:kMDItemWhereFroms` | no |
| Physical size | `URLResourceKey.totalFileAllocatedSizeKey`; `mdls -name kMDItemPhysicalSize` (bundles); `du -skP` | no |
| Clone detection | `URLResourceKey.mayShareFileContentKey`, `.fileContentIdentifierKey` (macOS 11+) | no |
| Free space | `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` | no |
| Local snapshots | `tmutil listlocalsnapshots /` | no |
| Unified log wipe (explicit only) | `log erase --all` | yes |
| Simulators | `xcrun simctl list devices booted -j`, `xcrun simctl delete unavailable`, `xcrun simctl runtime list -j`, `xcrun simctl runtime delete <id>` | no / runtimes may prompt |
| Homebrew / npm / pip / go / pod / pnpm / bun / conda | `brew cleanup --prune=30 [--dry-run]`, `npm cache clean --force`, `pip3 cache purge`, `go clean -cache`, `go clean -modcache`, `pod cache clean --all`, `pnpm store prune`, `bun pm cache rm`, `conda clean --yes --index-cache --tarballs --logfiles` | no |
| Docker (review only) | `docker system df` | no |
| Launch items | `launchctl bootout gui/$(id -u) <plist>`; `launchctl bootout system <plist>`; `sfltool dumpbtm` (read-only) | user / root |
| Login items (Open at Login) | `osascript -e 'tell application "System Events" to delete login item "<name>"'` | no (Automation) |
| Prefs cache flush | `killall -u $USER cfprefsd` | no |
| Document versions | `NSFileVersion.otherVersionsOfItem(at:)`, `.remove()`, `removeOtherVersionsOfItem(at:)` inside `NSFileCoordinator` | no (FDA) |
| Trash move | `FileManager.trashItem(at:resultingItemURL:)` | no |
| Thinning | `lipo <bin> -remove x86_64 -output <tmp>` / `lipo -thin arm64`; `codesign --verify --deep --strict` | helper |
| ~~Ad-hoc re-sign (advanced)~~ (corrected: **do not use**) | `codesign --force --deep --sign - <App.app>` destroys the Developer ID/notarized signature, and TN2206 makes it unnecessary | — |
| Darwin per-user dirs in-process | `confstr(_CS_DARWIN_USER_CACHE_DIR, …)`, `confstr(_CS_DARWIN_USER_TEMP_DIR, …)` | no |
| Gentler unified-log trim (explicit only) | `log erase --ttl` | yes |
| Document-revision discovery (helper, read-only DB copy) | `sqlite3 -readonly <copy of /System/Volumes/Data/.DocumentRevisions-V100/db-V1/db.sqlite> "SELECT f.file_path, COUNT(*), SUM(g.generation_size) FROM files f JOIN generations g ON g.generation_storage_id=f.file_storage_id GROUP BY f.file_storage_id HAVING COUNT(*)>1"` | yes (+FDA) |
| Mail account type | read-only copy of `~/Library/Accounts/Accounts4.sqlite`: `ZACCOUNT.ZIDENTIFIER` (= Mail folder UUID) → `ZACCOUNTTYPE.ZIDENTIFIER` | no (FDA) |
| BTM DB (read-only) | `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` (FDA), or `sfltool dumpbtm` | FDA / root |
| Simulator runtimes | `xcrun simctl runtime list -j`, `xcrun simctl runtime delete <id>` (never `rm` under `/Library/Developer/CoreSimulator/{Images,Cryptex,Volumes}`) | may prompt |
| Local users | `dscl . -list /Users`, `dscl . -read /Users/<u> NFSHomeDirectory` | no |
| Helper registration | `SMAppService.daemon(plistName:)` (plist in `Contents/Library/LaunchDaemons`, macOS 13+) | approval |

---

## 14. Sources

**MacPaw primary (read in this session).**
- CleanMyMac 3 in-app Help book (MacPaw-authored), mirrored at github.com/auspham/mac-essential:
  - topic-1 Smart Cleanup: https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-1.html
  - topic-2 System Junk: …/topic-2.html
  - topic-3 Photo Junk: …/topic-3.html
  - topic-4 Mail Attachments: …/topic-4.html
  - topic-5 iTunes Junk: …/topic-5.html
  - topic-6 Trash Bins: …/topic-6.html
  - topic-7 Large & Old Files: …/topic-7.html
  - topic-8 Uninstaller: …/topic-8.html
  - topic-9 Maintenance: …/topic-9.html
- MacPaw CleanMyMac CLI:
  - README: https://github.com/MacPaw/cleanmymac-cli
  - wiki Commands: https://github.com/MacPaw/cleanmymac-cli/wiki/Commands
  - Safety-and-Privacy: https://github.com/MacPaw/cleanmymac-cli/wiki/Safety-and-Privacy
  - FAQ: https://github.com/MacPaw/cleanmymac-cli/wiki/FAQ

**MacPaw knowledge base.** Verified by sibling tracks (see `01-overview.md`, `02-smart-care.md`); macpaw.com was not reachable from this sandbox.
- https://macpaw.com/support/cleanmymac/knowledgebase/system-junk (also a search excerpt this session: Spotify/Gradle exceptions; broken login items not in the App Store edition)
- https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk
- https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety
- https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-safety
- https://macpaw.com/support/cleanmymac/knowledgebase/missing-features
- https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features
- https://macpaw.com/support/cleanmymac/knowledgebase/trash-bins
- https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments
- https://macpaw.com/support/cleanmymac/knowledgebase/smart-care
- https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access
- https://macpaw.com/support/cleanmymac/knowledgebase/background-items
- https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation
- https://macpaw.com/news/introducing-smart-insights
- TidBITS CMM3 review (via 02): https://tidbits.com/2015/08/28/save-space-and-uninstall-apps-with-cleanmymac-3/
- Talos helper CVEs (via 01/02): https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716

**Open-source code (read directly).**
- tw93/Mole:
  - https://github.com/tw93/Mole (README)
  - `lib/core/base.sh` (age constants, whitelists)
  - `lib/core/file_ops.sh` (critical-path deny list, sizing, guarded delete)
  - `lib/core/app_protection.sh` (protected data/paths)
  - `lib/clean/user.sh` (trash, user caches/logs, mail downloads, incomplete downloads, ipsw, large-item review)
  - `lib/clean/system.sh` (system caches/logs, idleassetsd, GPU caches, installers)
  - `lib/clean/app_caches.sh` (DerivedData)
  - `lib/clean/dev.sh` (Xcode, simulators, Gradle, dev tools)
  - `lib/clean/brew.sh`
  - `SECURITY_AUDIT.md`
- mac-cleanup-py: https://github.com/mac-cleanup/mac-cleanup-py/blob/main/mac_cleanup/default_modules.py
- mac-cleanup-sh: https://github.com/mac-cleanup/mac-cleanup-sh/blob/main/mac-cleanup
- Tencent Lemon rules: https://github.com/Tencent/lemon-cleaner/blob/master/LemonClener/LemonClener/libcleaner/garbage1_en.xml
- Monolingual:
  - https://github.com/IngmarStein/Monolingual
  - `Sources/MainView.swift`, `Sources/Root.swift`, `Sources/BlocklistEntry.swift`
  - `Helper/Sources/Helper.swift`, `Helper/Sources/HelperContext.swift`
- Pearcleaner:
  - https://github.com/alienator88/Pearcleaner
  - `Pearcleaner/Logic/Lipo.swift`, `Pearcleaner/Logic/Locations.swift`
- DevCleaner for Xcode:
  - https://github.com/vashpan/xcode-dev-cleaner
  - `DevCleaner/Model/XcodeFiles.swift`
- MacSai:
  - https://github.com/iliyami/MacSai
  - `Sources/MacCleanKit/Models/ScanCategory.swift`, `Sources/MacCleanKit/Categories/SimpleCategories.swift`, `Sources/MacCleanKit/Constants.swift`
- MacOptimizer:
  - https://github.com/ddlmanus/MacOptimizer
  - `AppUninstaller/SystemJunkReplicaView.swift`, `AppUninstaller/JunkCleaner.swift`

**Added by the fact-check pass (2026-10-12; all fetched or read directly).**
- Apple TN2206 *macOS Code Signing In Depth* (`.lproj` removal and slice removal do not invalidate signatures; resource rules obsolete since 10.9): https://developer.apple.com/library/archive/technotes/tn2206/_index.html
- Apple Security source, codesign default resource rules (`optional` localizations, `Base.lproj` required): https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/bundlediskrep.cpp
- Apple Security source, `confstr(_CS_DARWIN_USER_CACHE_DIR)` usage: `OSX/utilities/SecFileLocations.c`, `supd/main.m` in the same repo
- Apple diskdev_cmds `tmp_cleaner` (3-day `/tmp` janitor): https://github.com/apple-oss-distributions/diskdev_cmds/blob/main/tmp_cleaner/tmp_cleaner
- WWDC22 session 10096 *What's new in privacy* (App Management / `NSUpdateSecurityPolicy`, Gatekeeper integrity checks of notarized apps): https://developer.apple.com/videos/play/wwdc2022/10096/
- WWDC23 session 10053 *What's new in privacy* (app-data-container prompts; FDA exempt): https://developer.apple.com/videos/play/wwdc2023/10053/
- NSFileVersion `remove()` and `removeOtherVersionsOfItem(at:)` doc JSON (re-read): https://developer.apple.com/documentation/foundation/nsfileversion/remove() ; SMAppService `daemon(plistName:)` (plist must be in `Contents/Library/LaunchDaemons`, macOS 13+): https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)
- mac_apt Document Revisions plugin (DB schema, chunk store): https://github.com/ydkhatri/mac_apt/blob/master/plugins/documentrevisions.py ; Internet Accounts plugin: `plugins/inetaccounts.py`
- Objective-See DumpBTM (BTM file path, FDA): https://github.com/objective-see/DumpBTM
- Sparkle 2 source (cache layout, 10-day pruning): https://github.com/sparkle-project/Sparkle (`Sparkle/SPULocalCacheDirectory.m`, `Downloader/SPUDownloader.m`)
- MAU staging: https://github.com/pbowden-msft/ExtensionAttributes (`MAU_Pending_Updates.sh`); https://github.com/cocopuff2u/MOFA
- Mail account typing: https://github.com/tylern91/apple-mail-mcp (`crates/amx-store/src/account.rs`); https://github.com/like-a-freedom/rusty_apple_mail_mcp ; Mail V10 Ventura→Tahoe: https://github.com/tacogips/apple-gateway (`design-docs/specs/design-apple-mail.md`)
- Spotify paths: https://github.com/JonnyBurger/make-space (`docs/spotify-cache.md`); https://github.com/jithin-sabu/purge-app
- Music/TV partial downloads: https://github.com/Shivansh2703/orphan ; https://github.com/swizzlevixen/Mac-Server-Reliability ; https://github.com/attheodo/cherrypick
- Podcasts container: https://github.com/mattdanielmurphy/apple-podcast-transcript-extractor
- Deleted Users: https://github.com/deploymenttheory/go-api-sdk-jamfpro ; https://github.com/Cloudxtreme/macosadmin ; https://github.com/russellgordon/plantoir (`RELEASING.md`)
- App Management vs root (field report): https://github.com/Reedtrullz/Vifty/blob/main/docs/reviews/2026-09-15-app-management-replacement.md
- Simulator runtime images: https://github.com/dotnet/maui (`eng/pipelines/common/provision.yml`)
- `log erase` threat catalogue: https://github.com/redcanaryco/atomic-red-team

**Apple developer documentation (read directly via developer.apple.com JSON).**
- NSFileVersion: https://developer.apple.com/documentation/foundation/nsfileversion
  - `otherVersionsOfItem(at:)`, `remove()`, `removeOtherVersionsOfItem(at:)`, `isDiscardable`
- FileManager `trashItem(at:resultingItemURL:)`: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- URLResourceKey:
  - `totalFileAllocatedSizeKey`
  - `fileContentIdentifierKey`
  - `mayShareFileContentKey`
  - (https://developer.apple.com/documentation/foundation/urlresourcekey/…)
- URLResourceValues `volumeAvailableCapacityForImportantUsage`
- SMAppService:
  - https://developer.apple.com/documentation/servicemanagement/smappservice
  - `daemon(plistName:)`

---

## Verification notes

Adversarial fact-check pass, 2026-10-12.

**Environment limits for this pass.**
- DNS failed for these hosts: macpaw.com, cleanmymac.com, support.apple.com, apps.apple.com, setapp.com, ss64.com, support.spotify.com.
- The shared WebSearch budget was already used up, so no search-engine queries were possible.
- Reachable sources were github.com, raw.githubusercontent.com (including Apple's own `apple-oss-distributions` repositories) and developer.apple.com (documentation JSON, TN2206 and WWDC transcripts). GitHub code search was used in place of web search.
- Archive and reader services were deliberately not used to get around blocked hosts.
- Consequence: every MacPaw knowledge-base claim (VERIFIED-K/-S) is unchanged and was **not** re-fetched. Only the CMM3 Help book and the CLI repository (VERIFIED-V) could be re-read at the vendor-primary level.

**Claims checked, in order of implementation impact.**

| # | Claim (as originally written) | Result | Evidence |
|---|---|---|---|
| 1 | Removing `.lproj` from modern signed apps breaks the seal; Monolingual blocklists every sealed resource | **Refuted, corrected** (§1.4, §5.6, §6.3 B1/B2, §9.4, §11, §13) | TN2206: removing `.lproj` files from `Contents/Resources` keeps the signature valid. codesign `defaultResourceRules`: localizations `optional`, `Base.lproj` required. Monolingual skips `optional` entries |
| 2 | Thinning universal binaries "usually" keeps the signature (INFERRED) | **Confirmed, upgraded to VERIFIED-APPLE** (§5.8, B6) | TN2206: removing one architecture's slice does not invalidate the signature |
| 3 | An ad-hoc re-sign "aggressive" mode as an option | **Removed** (§5.6, §13) | Unnecessary per #1 and #2. Replaces the Developer ID signature and breaks notarization, the designated requirement, TCC and Sparkle |
| 4 | NSFileVersion `remove()` / `removeOtherVersionsOfItem(at:)` semantics | **Confirmed**; coordination option **corrected** from `.forDeleting` to a plain coordinated write (§4.8, §5.11) | Apple doc JSON: never call on the current version; call from a file-coordinator write block |
| 5 | `/.DocumentRevisions-V100/db-V1/db.sqlite` plus `PerUID` generation files | **Confirmed, detailed** (DB tables, `generation_path`, `.cs` chunk store); upgraded to VERIFIED-OSS | mac_apt `documentrevisions.py` |
| 6 | BTM DB in `/private/var/db/com.apple.backgroundtaskmanagement/` | **Confirmed**; file name `BackgroundItems-v*.btm` and the FDA requirement added | Objective-See DumpBTM |
| 7 | `SMAppService.daemon(plistName:)`, plist in `Contents/Library/LaunchDaemons`, macOS 13+ | **Confirmed** | Apple doc JSON |
| 8 | `FileManager.trashItem`, `mayShareFileContentKey` (macOS 11+) | **Confirmed** | Apple doc JSON |
| 9 | App Management TCC needed for bundle edits (INFERRED) | **Upgraded**: WWDC22 mechanism; root not exempt per a 2026 field report | WWDC22 10096; Vifty review doc |
| 10 | Sonoma App-Data container prompts (INFERRED) | **Upgraded to VERIFIED-APPLE**; FDA exempts; the grant resets when the app quits | WWDC23 10053 |
| 11 | `getconf DARWIN_USER_CACHE_DIR` (Mole) | **Confirmed**; in-process `confstr(_CS_DARWIN_USER_CACHE_DIR)` added | Mole `base.sh`; Apple Security source |
| 12 | Mole `/Library/Caches` deletes only `*.cache`/`*.log` | **Corrected** to `*.cache` and `*.tmp` (temp age) plus `*.log` (log age); Mole also removes `com.apple.iconservices.store`; `/private/var/log` patterns are `*.log`, `*.gz`, `*.asl` | Mole `system.sh` (re-read) |
| 13 | Mole default whitelist / Gradle daemon as Mole-sourced auto | **Corrected**: Mole whitelists `~/.gradle/daemon/*` and `~/.gradle/caches/*` by default, so V9's auto rule is ours (INFERRED) | Mole `base.sh` |
| 14 | "5.x labels seen in the replica clone" | **Corrected** to X-era: the clone calls itself a CleanMyMac **X** reconstruction | MacOptimizer `SystemJunkReplicaView.swift` |
| 15 | CMM3 per-row defaults (Language Files, Universal Binaries "auto") sourced to Help topic-2 | **Corrected attribution**: topic-2 gives explicit defaults only for Leftovers, Xcode Module Cache/Archives and Document Versions; the other rows rest on "most" plus TidBITS | CMM3 Help topic-2 (re-read) |
| 16 | CMM3 Trash Bins auto-selects everything; iOS latest backup never auto | **Confirmed** | CMM3 Help topic-6, topic-5 (re-read) |
| 17 | MacPaw CLI command set, purge roots, 7-day rule, AI Junk unchecked in mock-up | **Confirmed**; `clean` = system junk + dev tools + trash; `optimize` commands and macOS 11+ added | CLI README and wiki (re-read) |
| 18 | Spotify exception path `~/Library/Caches/com.spotify.client` | **Incomplete, corrected**: the default offline store is `~/Library/Application Support/Spotify/PersistentCache/Storage`; both are protected | Several OSS cleaners and scripts |
| 19 | Sparkle staging path (INFERRED); `~/Library/Application Support/<id>/.Sparkle*` | **First confirmed** from Sparkle source (`PersistentDownloads`, `Installation`, 10-day self-prune); **second dropped** as unverified | Sparkle repo |
| 20 | MAU cache `~/Library/Caches/com.microsoft.autoupdate*` and `/Library/Caches/com.microsoft.autoupdate*` as safe auto | **Corrected**: `/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex` holds pending-update app clones, so it is review only | pbowden-msft `MAU_Pending_Updates.sh`; MOFA |
| 21 | Mail: "warn if Mail is running" | **Tightened** to skip while Mail runs, as Mole does | Mole `user.sh` |
| 22 | `qlmanage -r cache`, `log erase --all` | **Confirmed** as real commands (Mole and many OSS uses). Added: `log erase` is catalogued as an attacker log-clearing technique, so it may raise EDR alerts | Mole `optimize/tasks.sh`; Atomic Red Team |

**Gaps filled (details in §12):**
- the platform side of seal handling (#2);
- a concrete Document Versions discovery method (#3);
- Mail account typing via `Accounts4.sqlite` and Mail V10 from Ventura through Tahoe (#6);
- Music `Downloads-Music`, TV `Downloads-TV` and iTunes `iTunes Media/Downloads` partial-download locations (#6);
- `/Users/Deleted Users/<name>.dmg` corroborated, plus non-DMG leftovers (#7);
- App Management vs root (#8, likely blocked);
- the Smart Care trash question, partly answered (CMM3 and CLI include external drives) (#5).

**New items added to the catalog:** C30b, C31, L2b, M4 paths, M5, X14 runtime images, U1 folders, Apple's `tmp_cleaner`, and the iCloud Drive state exclusion (INFERRED).

**Still uncertain (verify on device or when macpaw.com is reachable):**
- the exact 5.7.x System Junk exception list and smart-selection rules beyond Spotify and Gradle;
- whether 5.x System Junk still has Unused Disk Images, Downloads or Old Updates;
- CleanMyMac 5's own method for Document Versions and language/binary removal;
- whether 5.x Smart Care pre-checks external-drive trash;
- the `/Users/<name> (Deleted)` suffix on 14–26;
- `dirhelper`'s per-user `T/` purge;
- whether `codesign --verify --deep --strict` stays green after removing optional `.lproj` files from **nested** frameworks (TN2206 only covers `Contents/Resources`);
- whether our SMAppService daemon is charged to our app for App Management;
- Music/TV media-folder relocation handling;
- OnyX's categories and fresh reviewer data points: still not collected, for the same network reasons.
