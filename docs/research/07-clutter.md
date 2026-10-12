# 07 — My Clutter (Large & Old Files, Duplicates, Similar Images, Downloads), Space Lens, Shredder, Cloud Cleanup, Photo Junk

> **Track:** Personal-file decluttering and storage visualisation. Covers what CleanMyMac 3 / X / 5.x ("CleanMyMac" 2024+) do in these areas, how they look and behave, and a concrete Swift implementation spec for our own original app (Apple Silicon Mac mini, macOS 14 Sonoma → macOS 26 Tahoe).
> **Date of research:** 2026-10-12.
> **Naming:** MacPaw names ("My Clutter", "Space Lens", "Smart Care", "Cloud Cleanup", "Gemini", "Shredder" as a module name) are used only to describe the reference product. Our product uses its own names. See §13.

---

## 0. How this report was researched, and how to read the labels

**Access limits in this session.** These limits shaped the evidence base, so they are stated up front:

- **Web search was not available.** The shared per-turn WebSearch budget was already used up by sibling agents when this track started, so this track ran **zero** successful web searches.
- **Most news and review sites did not resolve.** That includes macpaw.com, cleanmymac.com, cdn3.macpaw.com, apps.apple.com, setapp.com, macworld.com, tidbits.com, support.apple.com, nvd.nist.gov, eclecticlight.co and daisydiskapp.com.
- **Reachable sources:**
  - github.com and raw.githubusercontent.com;
  - developer.apple.com (its documentation JSON endpoints);
  - Apple open source (`apple-oss-distributions`);
  - MacPaw's DevMate release-notes bucket on S3;
  - SourceForge.

The evidence therefore comes from these places:

1. **MacPaw-authored material read here:**
   - the CleanMyMac 3 in-app Help book and its shipped English `.strings` files (mirrored in a public GitHub repo);
   - CleanMyMac 5 DevMate release notes on S3;
   - the official `MacPaw/cleanmymac-cli` repo and wiki.
2. **MacPaw knowledge-base facts already verified by sibling tracks**, which had web access earlier (`01-overview.md`, `02-smart-care.md`, `03-cleanup.md`, `06-applications.md`). The original macpaw.com URLs are cited.
3. **Apple documentation and Apple open-source headers and man pages** (xnu `attr.h`, `stat.h`, `getattrlist.2`, `getattrlistbulk.2`; file_cmds `rm.1`).
4. **Open-source tools and replica apps** read directly.

| Label | Meaning |
|---|---|
| **VERIFIED-V** | Vendor (MacPaw) primary material read in this session. URL given. |
| **VERIFIED-K** | MacPaw KB, press or release-note fact verified by a sibling track. The original MacPaw URL is cited, plus the sibling report. Not re-fetched here, because macpaw.com was unreachable. |
| **VERIFIED-APPLE** | Apple developer documentation, or Apple open-source code and man pages, read in this session. |
| **VERIFIED-OSS** | Read directly in open-source code or docs. Shows how *other* tools work, not CleanMyMac. |
| **VERIFIED-R** | Relayed / secondary evidence. Either (a) third-party "CleanMyMac-style" replica apps whose strings and layouts appear to mirror the vendor UI, or (b) third-party research notes or measurements. Useful evidence, but not proof of vendor behaviour. |
| **INFERRED** | Our reasoning, platform knowledge, or recommendation. Anything without a VERIFIED tag is INFERRED. Items marked **(verify on device)** must be tested on the Mac mini before shipping. |

**Fact-check pass (2026-10-12).** An adversarial review re-checked about 28 implementation-critical claims against DevMate release notes and appcasts, Apple documentation (including TN3150 and the Developer Forums), xnu and file_cmds sources, and GitHub code. Corrections are marked **(corrected)** in place. New findings are in §17, and the audit trail is in **Verification notes** at the end.

---

## 1. Executive summary: decisions for our build

1. **Module set to implement (union across versions).**
   - **Clutter**, our "My Clutter", with four categories: **Large & Old Files**, **Duplicates**, **Similar Images**, **Downloads**.
   - **Space Map**, our "Space Lens".
   - **Cloud Storage**, our "Cloud Cleanup".
   - **Eraser**, our "Shredder". It was removed by the vendor in 5.0, but we keep it as a tool, with honest SSD caveats.
   - Legacy **Photo Junk** is folded into Cleanup as a review-only, low-risk subset (see `03-cleanup.md` §5.22).
   - Vendor facts:
     - 5.0 shipped My Clutter with Large/Old, Duplicates, Similar Images and Downloads. VERIFIED-K (MacRumors / MacPaw news via `01-overview.md` §6).
     - Shredder was removed in 5.0. VERIFIED-K (`01-overview.md` §5.2).
     - Space Lens returned in 5.1.0. VERIFIED-V (DevMate notes).
     - Cloud Cleanup arrived in 5.2.1. VERIFIED-V (DevMate notes).
2. **The vendor never auto-selects personal files in Large & Old Files.**
   - CMM3 says "nothing is selected automatically". VERIFIED-V (CMM3 Help topic-7).
   - Its summary text says large and old items need review "since it consists of your own files". VERIFIED-V (CMM3 `Localizable.strings`).
   - **Duplicates are the exception.** They get a "smart selection" that keeps one copy, and Smart Care pre-selects duplicates **in ~/Downloads only**. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/smart-care, https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files, via `02-smart-care.md`).
   - We copy this policy exactly.
3. **Space Lens is a *bubble* (circle) map, not a treemap or sunburst.**
   - 5.1.0: "creates a map of your storage, displaying folders as bubbles arranged from largest to smallest", with zoom-in. VERIFIED-V (DevMate 5.1.0 notes).
   - Our Space Map renders a **circle-packing** layout: area ∝ allocated size, largest first. It has a synchronized list on the left, click-to-zoom, a breadcrumb, and an "Other" bubble for the long tail.
   - A treemap or sunburst can be an optional alternate view (INFERRED).
4. **One shared, fast file index feeds Space Map, Large & Old, Duplicates and Downloads.**
   - The scanner uses `getattrlistbulk(2)` with about 8 concurrent directory readers.
   - It stops at mount points, allows only the firmlinks listed in `/usr/share/firmlinks`, counts hard links once by `(dev, ino)`, and never follows symlinks.
   - (corrected) Detect mount points from `ATTR_DIR_MOUNTSTATUS` (`DIR_MNTSTATUS_MNTPOINT`), not by comparing device IDs. For a mount point, `getattrlistbulk` returns the attributes of the *underlying* directory, so its device ID matches the parent. Firmlinks carry `SF_FIRMLINK` (0x00800000) in `ATTR_CMN_FLAGS`. Never descend into `DIR_MNTSTATUS_TRIGGER` (automount trigger) directories. VERIFIED-APPLE (xnu `getattrlistbulk.2`, `attr.h`, `stat.h`; see §8.4).
   - Scanner threads opt out of cloud downloads with `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`. VERIFIED-APPLE (TN3150; see §17.2).
   - Rescans are incremental, driven by FSEvents.
   - Prior art: VERIFIED-OSS (OpenDisk README; Ferail `disk_usage_scanner.rs`; xnu `getattrlistbulk.2`).
5. **Size accounting is APFS-aware.**
   - Show **allocated** ("on disk") size by default.
   - Use `ATTR_CMNEXT_PRIVATESIZE` ("bytes … not trapped inside a clone or snapshot … freed immediately if the file were deleted") for **reclaimable** estimates.
   - Use `ATTR_CMNEXT_CLONEID` / `URLResourceKey.fileContentIdentifierKey` to detect clones.
   - Use `SF_DATALESS` (0x40000000) to recognise cloud-only placeholders.
   - All VERIFIED-APPLE (xnu `getattrlist.2`, `stat.h`; Foundation docs).
6. **The duplicate algorithm is staged.**
   - Stages: size buckets → hard-link and clone collapse → **prehash** (first + last 4 KiB) → full content hash → optional byte-compare before delete.
   - Both czkawka and dupeGuru use size-then-hash. VERIFIED-OSS.
   - **Never read dataless cloud files.** Reading one blocks while it downloads. VERIFIED-R (PortOS measurements on macOS 26).
7. **The keep rule for duplicates is an ordered, explainable ranking.**
   - Order: protected/reference folder → preferred-location score → "clean" filename (no ` copy`/` (1)`) → oldest creation date → shortest path.
   - Enforce **"never select every copy"** both at selection time and again at deletion time.
   - Prior art: Gemini 2 keeper filters "Automatically / Newest / Oldest / Any" and "Always/Never select" folders (VERIFIED-R, relayed from MacPaw's Gemini 2 User Guide). dupeGuru Re-Prioritize criteria (VERIFIED-OSS).
8. **Similar Images uses a two-tier perceptual pipeline.**
   - Tier 1: a 64-bit **dHash/pHash** from ImageIO thumbnails (cheap pre-filter, BK-tree or multi-index lookup).
   - Tier 2: verify candidate pairs with **Vision feature prints** (`VNGenerateImageFeaturePrintRequestRevision2`, macOS 14+) and `computeDistance`. VERIFIED-APPLE.
   - Cluster with guarded union-find. Pick the "best shot" by resolution, sharpness and face quality.
   - **Default: nothing selected.** Offer "Select all but best". Gemini also did not auto-select "similar" (VERIFIED-R).
9. **Photos library items are never deleted at the file level.**
   - Use PhotoKit (`PHAssetChangeRequest.deleteAssets`). VERIFIED-APPLE for the API; system confirmation and Recently Deleted behaviour are INFERRED, verify on device.
   - Or, like CMM3 ("Large Media to Delete" album) and Gemini ("Gemini Duplicates" album), gather items into an album for the user to delete in Photos. VERIFIED-V (CMM3 strings).
10. **Downloads category.**
    - Group by **source app** (from the `com.apple.quarantine` agent field or `kMDItemWhereFroms` host) and by kind (Installers, Archives, Documents, Media, Incomplete).
    - Age comes from `kMDItemDateAdded`, and "opened" from `kMDItemLastUsedDate`.
    - Only **incomplete/broken downloads** are pre-selected. Exact duplicates in Downloads are pre-selected by the Checkup.
    - Vendor: Safari, only broken downloads; Slack, broken or at least 1 month old. VERIFIED-K (https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk via `02-smart-care.md`).
11. **"Old" means last opened.**
    - Primary signal: Spotlight `kMDItemLastUsedDate`, which LaunchServices updates when a file is opened by double-click or LaunchServices open. VERIFIED-APPLE.
    - Fallback: `max(dateAdded, contentModificationDate)`.
    - `atime` (`contentAccessDateKey`) is a weak tie-breaker only. INFERRED.
    - CMM3 grouped by "Access Date" with buckets Today / Last Week / A Week Ago / A Month Ago / One Year Ago. VERIFIED-V (CMM3 strings).
12. **Removal semantics.**
    - Default **Move to Trash** (`FileManager.trashItem(at:resultingItemURL:)`) for every personal file. We keep our own undo log.
    - Options: **Move to Folder…** (archive to an external drive) and **Delete Immediately**, the latter with confirmation.
    - CMM3 offered Move to Folder / Move to Trash / Remove Immediately / Remove Securely. VERIFIED-V (topic-7).
13. **Eraser (Shredder) is honest about SSDs.**
    - Two modes:
      - **Force delete**: handles locked flags, files held by processes, and permission problems, through the helper with an allow-list.
      - **Overwrite then delete**: plain files only, with refusals for clones, snapshots, cloud and dataless files.
    - Apple itself made `rm -P` "have no effect". VERIFIED-APPLE (file_cmds `rm.1`).
    - Apple removed Secure Empty Trash in El Capitan. VERIFIED-V (CMM3 Help topic-6/7/92 mentions it).
    - FileVault / Data Protection is the real guarantee. INFERRED.
14. **Cloud Storage is local-first.**
    - Read `~/Library/Mobile Documents/com~apple~CloudDocs` and the File Provider roots in `~/Library/CloudStorage/*` (Google Drive, OneDrive, Dropbox, Box…). Show per-provider Space Map and Large Files.
    - Actions: **Remove local copy** (evict / "unsync"), **Delete everywhere** (unlink → provider syncs the deletion), and **Download**.
    - Vendor actions: delete cloud-only files, remove from Mac and cloud, unsync. VERIFIED-V (DevMate 5.2.1).
    - Eviction ladder: `FileManager.evictUbiquitousItem(at:)` (VERIFIED-APPLE semantics) → `/usr/bin/brctl evict <path>` run as the user, never root (VERIFIED-R: works on macOS 26; `evictUbiquitousItem` fails with Cocoa error 512 from an unentitled process) → guided Finder "Remove Download" fallback. **(verify on device)**
    - (corrected) `fileproviderctl evict` is **not** a rung. Its `evict` and `materialize` verbs were removed in macOS 14.4. VERIFIED-R (Apple Developer Forums thread 748036; PortOS on macOS 26: "`fileproviderctl` has no `evict`"). `NSFileProviderManager.evictItem` only works from the provider's own app or extension (VERIFIED-APPLE, class abstract). For Google Drive, OneDrive and Dropbox, a third-party app is therefore left with `evictUbiquitousItem` (verify on device) or the Finder fallback.
15. **Permissions.**
    - **Full Disk Access** for whole-disk scans (otherwise TCC folders show as locked bubbles).
    - **Photos** access only when the user opts in to library scanning.
    - **No** network or OAuth by default. Optional provider APIs come later.
    - A privileged helper only for Eraser force-delete of root-owned items, with a strict allow-list. The 2018 Talos CVEs against CleanMyMac X's generic root helper are the cautionary tale. VERIFIED-K (TALOS-2018-0716 via `01-overview.md` §12) and VERIFIED-OSS (GitHub advisories CVE-2018-4032…4037, CVE-2019-5011 list "Privilege escalation flaw in CleanMyMac X").

---

## 2. Where these features live across product generations

| Feature | CleanMyMac 3 (2015–18) | CleanMyMac X (4.x, 2018–24) | CleanMyMac 5.x (Oct 2024 → 5.7.1 Oct 2026) | Sources |
|---|---|---|---|---|
| **Large & Old Files** | Own cleaning module. Scan locations: Home, default or any folder, including external and network. Group by Kind / Size / Access Date. Actions: Move to Folder, Trash, Remove Immediately, Remove Securely | "Files" sidebar section (with Space Lens and Shredder). In the App Store edition's Smart Scan it replaced "Speed". External devices fully supported from **4.2.0**; **"Move to Folder"** added in **4.6.3** (VERIFIED-V DevMate X notes 4.3.1 and 4.6.9 pages) | **My Clutter** category; sort by size / kind / date accessed. "Large Files" also used for cloud drives (5.2.1) | VERIFIED-V CMM3 topic-7 + strings; VERIFIED-K `01-overview.md` §7, `02-smart-care.md` §3.2; VERIFIED-V DevMate 5.2.1 |
| **Duplicates** | Not in CMM (separate app **Gemini**). Large & Old had a "Scan for Duplicates with Gemini" menu item | Gemini separate; Trash Bins had a "Gemini Duplicates" category | **My Clutter › Duplicates** (content comparison, "Apply smart selection"). Smart Care: duplicates in **~/Downloads only**. My Tools lists "Duplicate Finder" | VERIFIED-V CMM3 `LargeOldFilesScanResultsView.strings`, topic-6; VERIFIED-K https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files, …/smart-care, https://macpaw.com/news/my-tools-cleanmymac |
| **Similar Images** | — (Gemini) | — (Gemini) | **My Clutter › Similar Images** (5.0.0) | VERIFIED-K (`01-overview.md` §6, 5.0.0) |
| **Downloads** | System Junk-era handling only | System Junk group "Downloads" (Safari: broken only; Slack: broken or ≥ 1 month) | **My Clutter › Downloads** (old DMGs, archives, documents); also a My Tools entry | VERIFIED-K https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk; `01-overview.md` §5.2 |
| **Space Lens** | — | (corrected/precise) **Beta in 4.3.0** (dedicated to a user who suggested it; "we still call it a Beta feature"); **left beta in 4.4.0** (2019). Later notes: Purgeable Space popover (4.4.3), mounted-volume size fix (4.4.4), Quick Look on double-click (4.4.6), Users folder size fix (4.6.9), **cloud-stored files ignored (4.15.4, 2024-06-19)** | **Absent in 5.0**, **returned 5.1.0 (2025-06-12)** as a sidebar item; bubble map with zoom; Plus plan only (since July 2025) | VERIFIED-V DevMate X notes (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.3.1/releasenotes.html, …/4.4.6/releasenotes.html, …/4.6.9/releasenotes.html, …/41508.0.2409290833/releasenotes.html); VERIFIED-K https://macpaw.com/news/cleanmymac-x-update-4.4.0; VERIFIED-V DevMate 5.1.0 (appcast pubDate 2025-06-12 06:56 UTC); VERIFIED-K https://macpaw.com/support/cleanmymac/knowledgebase/space-lens, …/feature-plans |
| **Shredder** | Module ("EraserGroupScanner"): Select Files / drag-drop; **Shred**; optional **Remove Securely** (zero overwrite) | "Files" section; **not in the App Store edition**; Safety DB makes it refuse critical folders. 4.6.7 fixed "Removal of files following symlinks within Shredder" (VERIFIED-V DevMate X 4.6.9 page), so the bug class is real: never follow symlinks | **Removed** | VERIFIED-V CMM3 topic-92 + strings; VERIFIED-K `01-overview.md` §4.3/§5.2, https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database |
| **Cloud Cleanup** | — | — | **5.2.1 (2025-07-29; the DevMate appcast pubDate is 2025-07-28 15:59 UTC)**: iCloud Drive, Google Drive, OneDrive. (corrected) **5.3.0 (2025-12-17)**: Dropbox + improved OneDrive. Plus only. "Cloud Cleanup improvements" listed as coming next | VERIFIED-V DevMate 5.2.1 and 5.3.0 notes (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html) and appcast (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml); VERIFIED-K `01-overview.md` §6 (https://macpaw.com/cleanmymac/whats-new) |
| **Photo Junk** | Module: RAW Originals, Faces Cache, Photos Cache, iCloud Local Copies; **Change Library** | Cleanup module (not in the App Store edition) | Dropped as a module | VERIFIED-V CMM3 topic-3; VERIFIED-K `01-overview.md` §7 |

INFERRED takeaway: in 5.x MacPaw folded its separate Gemini product's core into the main app as "My Clutter", and rebuilt Space Lens as a "Plus" feature. Our app ships all of it with no tiering.

---

## 3. My Clutter (5.x): flow, UI structure and selection policy

### 3.1 What is verified about the vendor flow

- **Entry and scope.**
  - Choose a location (home folder, a disk, an external drive), then scan, then **Review All Files**.
  - Categories: **Large & Old Files** (sort by size / kind / date accessed), **Duplicates** (content comparison), **Similar Images**, **Downloads** (old DMGs, archives, documents).
  - "Smart Selection" pre-picks the user-side copies and avoids system files.
  - VERIFIED-K (https://cleanmymac.com/blog/duplicate-file-finder-mac, https://macpaw.com/how-to/delete-junk-files-on-mac, https://macpaw.com/support/cleanmymac/knowledgebase/free-up-more-space; via `01-overview.md` §5.2).
- **Smart Care integration.**
  - The Smart Care "My Clutter" routine scans **duplicate files in the Downloads folder only**.
  - Its tile shows the **number of duplicate files**, is selected by default, and "Run" removes the selected duplicates.
  - VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/smart-care via `02-smart-care.md` §1, §3.1).
- **Ignore List** has a **My Clutter** section with Duplicates, Similar Images and Downloads. CMM X's ignore scope included Large & Old Files. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety via `01-overview.md` §10).
- **CMM3 ignore granularity for Large & Old Files.** You could ignore individual files *and whole result groups*. The group labels were prefixed "Kind: ", "Size: ", "Last Accessed: ". The ignore tab is titled "Files, folders, and file groups to ignore:". VERIFIED-V (CMM3 `Localizable.strings`, `CMIgnoreListPreferencesViewController.strings`).
- **Plan tiers (vendor only).** Duplicates and My Clutter features are mentioned under Plus in some reviews. VERIFIED-K (`01-overview.md` §4.2). Not relevant to us.

### 3.2 Secondary evidence of the 5.x screens (replica apps; do not copy wording)

Several independent "CleanMyMac-style" open-source clones reproduce the 5.x My Clutter screens the same way. VERIFIED-R:

- **VaderCleaner** `MyClutterDashboardView.swift`, a header comment:
  - post-scan landing with a centred "files to sort through" header and a **Review All Files** action;
  - above a **four-card recommendation grid**: Duplicates, Similar Images, Large & Old, Downloads.
  - Its `MyClutterManagerView.swift` is a **three-pane "My Clutter Manager"**:
    - categories;
    - groups and facets. Large & Old has "All Files", "Selected", "By Kind" and "By Size". Duplicates and Similar show groups with a thumbnail, the original's name, reclaimable size and a copy-count badge. Downloads groups by **source app** with app icons;
    - files and preview, with a large preview, metadata rows (Modified, Created, Size, File type) and a "Select:" menu (All Copies / None);
    - a footer showing "N Items Selected · size" and **Remove**.
  - https://github.com/jayvicsanantonio/VaderCleaner
- **PristineCleaner** `assets/translations/en.i18n.json` keys:
  - `filesToSort` ("You have {count} files to sort through."), `quickRecommendations`, `reviewAllFiles`;
  - per-tile headlines for duplicates, similar images and large files, plus "No … found" empty states;
  - tool descriptions for Large and Old Files, Duplicate Finder, Similar Images and Downloads ("one-time use files").
  - https://github.com/RabinApps/PristineCleaner
- **VaderCleaner's selection seed.**
  - Redundant duplicate and near-duplicate copies are pre-selected.
  - Large/old files and downloads are never pre-selected, "so removing them is an explicit choice".

INFERRED from the above: the 5.x My Clutter has three layers.

1. A **scan landing** with a location picker.
2. A **results dashboard**: a total count, plus four recommendation tiles, each with a one-line headline and **Review**, plus a global **Review All Files**.
3. A **three-pane manager**: category → group/facet → file list with preview.

We reproduce this information architecture with our own visual design and wording.

### 3.3 Our Clutter module: screen spec (INFERRED, original wording)

```
┌ Clutter ─────────────────────────────────────────────────────────────┐
│ [Landing]  Title · one-line promise · 3 benefit bullets              │
│            Location chip: [Home ▾]  (Home / Macintosh HD / External  │
│            volumes… / Choose Folder…)          [ Scan ]              │
├──────────────────────────────────────────────────────────────────────┤
│ [Scanning] orb animation · "Indexing ~/Pictures/2019…" (≤10 Hz)      │
│            running counters: files indexed · candidates · [Stop]     │
├──────────────────────────────────────────────────────────────────────┤
│ [Dashboard] "2 341 files worth a look (38.2 GB)"   [Review Everything]│
│   ┌Duplicates──────┐ ┌Similar photos──┐ ┌Big & forgotten─┐ ┌Downloads┐│
│   │ 412 copies     │ │ 61 sets        │ │ 23.4 GB        │ │ 6.1 GB  ││
│   │ 3.2 GB to free │ │ 1.1 GB         │ │ 188 files      │ │ 3 apps  ││
│   │ [Review]       │ │ [Review]       │ │ [Review]       │ │[Review] ││
│   └────────────────┘ └────────────────┘ └────────────────┘ └─────────┘│
├──────────────────────────────────────────────────────────────────────┤
│ [Manager] ◀Back  Clutter Manager        [Search]  Sort: Size ▾       │
│ ┌Categories┐┌Groups / facets───────┐┌Files / preview────────────────┐│
│ │Duplicates││All files     23.4 GB ││☐ ▣ name.mov  ~/Movies/…  4.1 GB││
│ │Similar   ││Selected       1.2 GB ││☐ ▣ …                           ││
│ │Big & old ││— By kind —           ││ (duplicates/similar: preview   ││
│ │Downloads ││Movies 12 GB …        ││  strip + big preview + meta)   ││
│ │          ││— By size — / By age —││                                ││
│ └──────────┘└──────────────────────┘└────────────────────────────────┘│
│  12 items selected · 4.7 GB     [Move to Trash ▾]                    │
└──────────────────────────────────────────────────────────────────────┘
```

- **Primary button with a split menu:**
  - **Move to Trash** (default);
  - **Move to Folder…**;
  - **Delete Immediately…**, which needs confirmation;
  - **Erase…**, which hands off to Eraser and needs confirmation.
- **Row hover affordances:** Quick Look (space bar too), Reveal in Finder. Both mirror CMM3 "magnifier" and "Quick Look" icons, VERIFIED-V topic-7.
- **Context menu:** Reveal in Finder · Quick Look · Copy Path · Open With… · **Ignore this file** · **Ignore this group** (CMM3-style group ignore, VERIFIED-V) · Explain (optional on-device LLM, like vendor Smart Insights; VERIFIED-K `01-overview.md`).
- **Badges:**
  - `in iCloud` / `cloud-only` (CMM3 had "This item is located in iCloud", VERIFIED-V);
  - `in Photos` (CMM3 "In Photos", VERIFIED-V);
  - `clone (no space gain)`, `hard link`, `open in <App>`, `recently used`, `protected`.
- **Rescan** discards results after a confirm. CMM3: "Starting a new scan will discard current scan results." VERIFIED-V. **Start Over** returns to the landing.
- **Completion:** "Moved 12 items to Trash (4.7 GB)", with **Undo** (restores from Trash using the recorded `resultingItemURL`). Also "Trash must be emptied to free space" when the Trash is on the same volume, and **Review remaining**.

### 3.4 Clutter selection policy (copy the vendor principle)

| Category | Default selection | Rationale / source |
|---|---|---|
| Large & Old | **None** | CMM3: nothing auto-selected; personal files need review. VERIFIED-V topic-7 + strings |
| Duplicates (in module) | **Smart selection**: all but the keeper in each *exact-content* group | VERIFIED-K duplicate-files KB ("Apply smart selection") |
| Duplicates (in Checkup) | Exact duplicates **in ~/Downloads only**, pre-selected | VERIFIED-K smart-care KB |
| Similar Images | **None**; button "Select all but best" | Gemini didn't auto-select similar (VERIFIED-R); irreversible aesthetic judgement (INFERRED) |
| Downloads | Only **incomplete / broken downloads** older than 24 h and not open | Safari rule "broken only" (VERIFIED-K); our age gate is INFERRED |

Hard invariants (INFERRED, enforced in the removal pipeline, §12.3):

- (a) never remove every member of a duplicate or similar group in one operation unless the user explicitly confirms "Remove all copies";
- (b) never touch protected roots (§12.4);
- (c) re-validate each item (inode, size, mtime) right before acting.

---

## 4. Large & Old Files

### 4.1 Vendor behaviour (verified)

**CMM3 Help, topic-7** (VERIFIED-V, https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-7.html):

- **Scan locations:** the Home folder, a default location, or any other place, including internal or external drives **and network folders**. Buttons: "Add Folder…", ✕ per location, "Clear List". The same labels appear in `LargeOldFilesStartScanView.strings`.
- **Review:** "Review Files". Hover a row for **Quick Look** (files stored in iCloud can't be previewed) or the **magnifier** to reveal in Finder. For iCloud Photos items the magnifier downloads the file and opens it in **Photos**.
- **Origin icons** mark files from iCloud Photos, local Photos libraries and local iTunes libraries. **The module scanned inside media libraries.**
- **"Sort by"** menu and a live search field.
- **Nothing is selected automatically.**
- Control-click → "Add to Ignore List". Action → "Rescan" (results not saved). "Start Over".
- **Removal pop-up:** Move to Folder · Move to Trash · Remove Immediately · Remove Securely (zero overwrite, slower).

**CMM3 shipped strings** (VERIFIED-V, `Base.lproj/Localizable.strings` and `en.lproj/LargeOldFilesScanResultsView.strings` in the same mirror):

- **Module description:** finds large files and folders "you did not open for months".
- **Group modes:** "Group by Kind", "Group by Size", "Group by Access Date".
- **Kind groups:** All Files, Archives, Documents, Folders, Movies, Music, Pictures, Other.
  - Note **Folders**: large *folders* were candidates too.
- **Access-date groups:** Today · Last Week · A Week Ago · A Month Ago · One Year Ago.
- **Access-date slider stops:** last week · more than a week ago · more than two weeks ago · more than a month ago · more than three months ago · more than half a year ago · more than a year ago · more than two years ago.
- **Size and time filters:** "any size", "any time", "Less than %@", "More than %@". Size placeholder width is "999 MB".
- **Columns / sort keys:** Name, Path, Selection, Size, Access Date, Kind, Group (Ascending / Descending). Menu items: "Sort by Size / Date / Access Date / Kind / Name".
- **Badges:** "This item is located in iCloud", "In Photos".
- **Photos handling:** `LAOF_PhotosAlbum_Name = "Large Media to Delete"`. Large Photos-library items selected for removal were collected into a **Photos album** for the user to delete in Photos, rather than deleted from the library package (INFERRED from the string's name and use).
  - (corrected/nuanced) The same Help topic-7 says that removing an iCloud Photos item "will be removed from both iCloud and local Photos library" (VERIFIED-V, re-read). So CMM3 *did* remove library items, at least in some macOS versions. A sibling string says only Photos can permanently delete items in the Gemini album on High Sierra (`DescriptionText_UnsupportedHighSierraGeminiDuplicates_ReasonText`, VERIFIED-V). INFERRED: direct removal worked on older Photos versions, and the album hand-off became the fallback once Photos stopped allowing it. For us: PhotoKit delete or the album hand-off only (§6.5), never file-level.
- **Cross-sell:** "Scan for Duplicates with Gemini".
- **Empty state:** "It's tidy here!" / "No large or old files found."
- **Notification:** "…has found %@ of large and old files for you to review."

**CleanMyMac 5.x:** sort by size / kind / date accessed. VERIFIED-K (`01-overview.md` §5.2). "Large Files" is reused for cloud storage in Cloud Cleanup. VERIFIED-V (DevMate 5.2.1).

**Gaps:** the default **size threshold** and **age threshold** in X and 5.x are not documented in anything reachable. See §15.

- Fact-check addition: the 5.x KB says Large & Old results can be grouped or sorted by kind, size or access date, offer Preview and Reveal, and leave large files **unselected** because they may hold useful data. VERIFIED-R (third-party summary of https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old at https://raw.githubusercontent.com/HuakunShen/space-lens/HEAD/apps/web/UX_RESEARCH.md).
- Replica-app consensus (not vendor): VaderCleaner's string reads "Scan your home folder for files larger than 50 MB or not accessed in the past six months". MacSai, DiskBuddy and ViniciusDeep/MacCleaner also use 50 MB. VERIFIED-R (GitHub code search). Our 100 MB / 1 year default is stricter on purpose (a shorter list). Offer a **50 MB / 6 months** preset as "More results".

### 4.2 Our algorithm (INFERRED, implementation-ready)

**Inputs.** The shared index (§12.1) for the chosen roots, filtered to regular files, plus *packages treated as files* (`.app` outside `/Applications`, `.dmg`, `.sparsebundle`, `.photoslibrary` as an info-only row, `.fcpbundle`, `.logicx`, `.utm`, `.pvm`), plus optionally large folders (CMM3 "Folders" kind).

**Candidate rule.** An item is a candidate if `allocatedSize ≥ largeThreshold` **or** (`allocatedSize ≥ oldMinSize` and `lastUsed < now − oldThreshold`).

| Setting | Default | Range | Why |
|---|---|---|---|
| `largeThreshold` | **100 MB** | 10 MB – 10 GB | Keeps the list short on a typical home folder. Sibling `01-overview.md` §10.1 suggested 50/100 MB. |
| `oldThreshold` | **1 year** | 1 month – 3 years | Matches the CMM3 slider stop "more than a year ago" |
| `oldMinSize` | **10 MB** | 1–100 MB | Avoids thousands of tiny old files |
| `includeFolders` | off | — | CMM3 had "Folders". Our Space Map covers folders better |

**`lastUsed` derivation (best signal first):**

1. `kMDItemLastUsedDate`. LaunchServices updates it when a file is opened by double-click or LS open. VERIFIED-APPLE (https://developer.apple.com/documentation/coreservices/kmditemlastuseddate). Files opened via an app's own Open panel *may* not update it (INFERRED from the doc's wording; verify on device).
   - Fact-check addition: the same date is stored on the file itself in the undocumented xattr **`com.apple.lastuseddate#PS`**, a 16-byte `timespec` (seconds, then nanoseconds). Reading it works where Spotlight is off or excluded (external volumes, `~/Library`). IINA and VLC write this xattr themselves when they play a file, which shows that opens outside LaunchServices don't update it automatically. VERIFIED-OSS (iina `PlayerCore.swift`, videolan/vlc `VLCPlayQueueController.m`, exiftool `MacOS.pm` "XAttrLastUsedDate"). Order: Spotlight value → xattr → fallback below.
2. `max(kMDItemDateAdded, contentModificationDate)`. `kMDItemDateAdded` exists since 10.7 (VERIFIED-APPLE). It is the date the file arrived in its folder.
3. `contentAccessDateKey` (atime) only as a tie-breaker. Apple says it is nil when the volume doesn't support access dates (VERIFIED-APPLE). It is unreliable because indexers and backups read files (INFERRED).

Batch the Spotlight lookups:

- `MDItemCreateWithURL` + `MDItemCopyAttributes` per candidate. There are only a few thousand candidates, so this is cheap.
- Or run one `NSMetadataQuery` with predicate `kMDItemFSSize >= %lld` scoped to the roots, merged with the walk.
- **Spotlight alone is not enough:** `~/Library`, hidden folders, excluded volumes and privacy-excluded folders aren't indexed (INFERRED). The walk is authoritative; Spotlight only enriches it.

**Kind classification** (UTType conformance, first match wins; INFERRED, a superset of CMM3's groups):

| Bucket | UTTypes / rules |
|---|---|
| Movies | `.movie`, `.video`, `.audiovisualContent` |
| Music & Audio | `.audio` |
| Pictures | `.image`, `.rawImage` |
| Archives | `.archive`, `.zip`, `.gzip`, `.bz2`, `public.tar-archive`, `org.7-zip.7-zip-archive`, `.xip` |
| Disk Images & Installers | `com.apple.disk-image*`, `.dmg`, `.iso`, `.pkg`/`.mpkg`, `.ipsw` |
| Virtual Machines | `.vmdk`, `.vdi`, `.qcow2`, `.hdd`, `.utm`, `.pvm`, `.vmwarevm` |
| Documents | `.pdf`, `.presentation`, `.spreadsheet`, `.text`, `.compositeContent`, iWork/Office |
| Apps | `.application` / `.applicationBundle` (outside `/Applications`) |
| Folders | directories (if enabled) |
| Other | everything else |

**Size buckets** (CMM3 used free-form "More than / Less than"; ours are fixed facets plus a slider): 100–500 MB · 500 MB–1 GB · 1–5 GB · 5–20 GB · > 20 GB. INFERRED.

**Age buckets** (paraphrasing the CMM3 structure): Used this week · This month · 1–6 months ago · 6–12 months ago · 1–2 years ago · Over 2 years ago · Never opened (no `kMDItemLastUsedDate` and added > 1 year ago). INFERRED.

**Default exclusions** (INFERRED; all user-overridable except the protected ones):

- **Protected, never shown:** `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/vm` (swap and sleep image), `/Library` root, app bundles inside `/Applications` (Applications module territory), `~/Library/Mobile Documents` (Cloud module), Photos and Music library *internals*, Time Machine backup volumes, our own app's data. Volume roots are shown as nodes only in Space Map.
- **Hidden by default:** `~/Library/**` (Cleanup module territory), dot-folders (`~/.git`, `~/.cache`…), `node_modules`, `.Trash`, and files modified within the last 24 h ("in use" risk).
- **Cloud dataless files** are listed with a `cloud-only` badge but **excluded from "space to free" totals**, because their allocated size is 0 (§10).

**Edge cases (INFERRED):**

| Case | Handling |
|---|---|
| File currently open (VM disk, mail DB, Xcode index) | Check `proc_listpidspath` / `lsof -F n -- <path>` (bounded). Show `open in <App>` and disable selection until the app quits |
| Hard link (`linkCount > 1`) | Show once; reclaimable = 0 unless all links are selected; badge `hard link` |
| APFS clone (`EF_MAY_SHARE_BLOCKS`) | reclaimable = `ATTR_CMNEXT_PRIVATESIZE`; badge `clone` (VERIFIED-APPLE semantics) |
| Sparse file (`EF_IS_SPARSE`; VM images, sparsebundles) | Rank by allocated size, not logical size |
| Compressed (`UF_COMPRESSED`, decmpfs) | Allocated ≪ logical. Show allocated, logical in a tooltip |
| Network volumes | Allowed (CMM3 supported network folders, VERIFIED-V). Throttle concurrency to 2 and skip Spotlight |
| External APFS/HFS/ExFAT | Allowed. ExFAT has no clones/xattrs. Trash is `/Volumes/X/.Trashes/<uid>` |
| Photos library assets | Info row "Photos library — 182 GB" → button **Open in Photos / Manage with PhotoKit** (§6.5) |

### 4.3 Swift sketch: enrichment and bucketing (INFERRED)

```swift
import Foundation
import UniformTypeIdentifiers
import CoreServices

struct LargeOldCandidate: Identifiable, Hashable {
    let id: FileKey          // (volumeUUID, inode) – see §12.1
    let url: URL
    let allocated: Int64     // ATTR_FILE_ALLOCSIZE
    let logical: Int64       // ATTR_FILE_TOTALSIZE
    let reclaimable: Int64   // ATTR_CMNEXT_PRIVATESIZE (falls back to allocated)
    let lastUsed: Date?      // kMDItemLastUsedDate
    let dateAdded: Date?     // kMDItemDateAdded
    let modified: Date
    let kind: KindBucket
    let flags: ItemFlags     // .cloudOnly, .hardLink, .clone, .open, .inPhotos …
}

func spotlightDates(for url: URL) -> (lastUsed: Date?, added: Date?) {
    guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return (nil, nil) }
    let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    let added    = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
    return (lastUsed, added)
}

func effectiveLastUse(_ c: LargeOldCandidate) -> Date {
    c.lastUsed ?? max(c.dateAdded ?? .distantPast, c.modified)
}

func kindBucket(for url: URL, isDirectory: Bool) -> KindBucket {
    let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    if isDirectory && !isPackage { return .folders }
    guard let t = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return .other }
    if t.conforms(to: .audiovisualContent) && !t.conforms(to: .audio) { return .movies }
    if t.conforms(to: .audio) { return .audio }
    if t.conforms(to: .image) { return .pictures }
    if t.conforms(to: .diskImage) || ["pkg","mpkg","ipsw","iso"].contains(url.pathExtension.lowercased()) { return .installers }
    if t.conforms(to: .archive) { return .archives }
    if ["vmdk","vdi","qcow2","hdd","utm","pvm","vmwarevm"].contains(url.pathExtension.lowercased()) { return .virtualMachines }
    if t.conforms(to: .application) || t.conforms(to: .applicationBundle) { return .apps }
    if t.conforms(to: .pdf) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet)
        || t.conforms(to: .text) || t.conforms(to: .compositeContent) { return .documents }
    return .other
}
```

---

## 5. Duplicates

### 5.1 Vendor behaviour (verified / relayed)

- **5.x.** Duplicates are found by **content comparison**, and the module offers **"Apply smart selection"**. The KB does not say which copy is kept.
  - VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files via `02-smart-care.md` §3.1).
  - Marketing says "Smart Selection" pre-picks the user-side copies and avoids system files. VERIFIED-K (cleanmymac.com blog via `01-overview.md`).
- **Smart Care** pre-selects duplicates in **~/Downloads only** and reports their count. VERIFIED-K.
- **Ignore List › My Clutter › Duplicates.** VERIFIED-K.
- **CMM3 era.** The `Localizable.strings` contains "Select Same Files" and "Get Rid of Duplicate Files" / "Delete duplicates with Gemini to free up even more space." This shows duplicates were delegated to Gemini. VERIFIED-V.
- **Gemini 2**, MacPaw's dedicated duplicate finder and the likely ancestor of the 5.x engine (INFERRED). Relayed from MacPaw's *Gemini 2 User Guide* (2021, `cdn3.macpaw.com/manuals/Gemin-2-User-Guide-29062021.pdf`, unreachable here) by a third-party research file (https://raw.githubusercontent.com/ayhid/twins/main/.planning/research/FEATURES.md). VERIFIED-R:
  - **Smart Selection keeper filters:** Automatically / Newest / Oldest / Any. The tool claims to learn from your manual choices.
  - **Always Select / Never Select** folders.
  - **Remove Last Instance:** a warning before removing the last copy, which can be overridden with one checkbox.
  - **Removal modes:** Trash, Move to folder, Remove permanently, optional replace-with-hardlink. Only permanent removal on volumes without a Trash.
  - **Duplicates Monitor:** watches cleaned folders and notifies with Review / Remove / Ignore.
  - **Completion screen:** "Review Trashed" / "Put All Back". Put Back "may not be available" for its removals.
  - **"Similar" is a separate mode that is never auto-selected.**
  - **Photos and iTunes libraries are special-cased.** Photos duplicates are routed into a **"Gemini Duplicates" album**.
  - Fact-check additions from the same relay (VERIFIED-R, re-read):
    - **Ignore List** covers files, folders *and extensions*;
    - the results summary chart is the entry screen, and Gemini caps how many results it shows ("shows only the largest");
    - **duplicate-folder detection** exists;
    - optional **remove empty folders after clean**;
    - a Finder **Services** item, "Scan for Duplicates with Gemini 2";
    - Put Back works only **within the current session**.
    - Our design keeps the useful parts (folder duplicates as optional, extension ignores, a Finder Service) and drops the result cap and the "learning" selection.
  - Corroboration from CMM3: the **Trash Bins "Gemini Duplicates"** category "contains duplicated images that you have earlier removed from a Photos library using Gemini" (VERIFIED-V topic-6), and its string says these can only be deleted from Photos (VERIFIED-V strings).

### 5.2 Open-source prior art (VERIFIED-OSS)

- **czkawka** (`instructions/Instruction_Core.md`, `czkawka_core/src/tools/duplicate/core.rs`):
  - **Modes:** Name, Size, Size+Name, Hash.
  - **Hash pipeline:**
    1. group by size, drop unique sizes;
    2. **prehash** of the **first and last 4 KB**, drop unique prehashes;
    3. full hash.
  - **Hash types:** Blake3 (recommended), XXH3 (fastest), CRC32.
  - Optional `filter_hard_links` within size groups.
  - Prehash and full-hash caches. The integration example caches only files ≥ 257,144 bytes.
  - Rayon jobs capped at 3 items each.
  - On Stop, it still saves already-computed hashes to the cache.
  - **Reference paths** are protected from selection.
  - **Select presets:** one oldest / newest / biggest / smallest; shortest / longest path; invert; "Select All from Folder (recursive)".
- **dupeGuru** (`help/en/scan.rst`, `results.rst`, `core/prioritize.py`):
  - **Contents scan:** size groups, then MD5 of the remaining files.
  - **Folders scan:** a folder matches if all its files match. Matching parents suppress their subfolders.
  - **Reference file:** a file in a reference folder always wins. Otherwise the largest file wins.
  - **"Make Selected into Reference"**; reference files can't be marked.
  - **Re-Prioritize criteria:** Kind; Folder; Filename (Ends with number / Doesn't end with number / Longest / Shortest / Longest Path / Shortest Path); Size (Highest / Lowest); Modification (Newest / Oldest). Criteria are applied in order as tie-breakers.
  - **Delta values view** (differences from the reference in orange).
  - **Actions:** Send to Trash · Move/Copy marked · Remove from results · Link deleted files (symlink/hardlink) · Directly delete.
- **fclones** (relayed, VERIFIED-R):
  - Before acting, re-checks size and mtime and skips the group if anything changed after the scan.
  - Links via a temp name then `rename`.
  - `--dry-run` prints the commands.
- **jdupes** `-B`: dedupe via `clonefile` on APFS (VERIFIED-R).

### 5.3 Our duplicate engine (INFERRED, implementation-ready)

```
roots ─► shared index (§12.1) ─► filter (regular files, size ≥ minSize, not excluded,
        not dataless, not inside packages) ─► Stage A: bucket by logical size
   ─► Stage B: collapse identity
        • same (dev, ino)  → hard links of one file: keep 1 representative, mark "hard link"
        • same CLONEID / fileContentIdentifier → APFS clones: group as "clones" (0 B gain)
   ─► Stage C: prehash  = H( size ‖ first 4 KiB ‖ last 4 KiB )   (files ≤ 8 KiB: whole file)
   ─► Stage D: full hash = H( whole data fork ), streamed in 1 MiB chunks, F_NOCACHE
   ─► Stage E (deletion time only): byte-for-byte compare against keeper (optional, default on
        for files < 64 MiB, sampled 16 × 64 KiB windows for larger files)
   ─► groups: [keeper] + [copies]  → smart selection
```

- **Hash choice.**
  - Use **SHA-256 via CryptoKit**. It is hardware-accelerated on Apple Silicon and needs no dependency. Collision risk is negligible.
  - Alternatives: XXH3-128 or BLAKE3 via a Swift package, if profiling shows hashing (not I/O) is the bottleneck.
  - Prehash can use the same function. INFERRED.
- **`minSize` defaults:**
  - **1 MB** in the full module (cuts thousands of tiny identical resources);
  - **1 byte** (all non-empty files) for the ~/Downloads Checkup routine.
  - Zero-byte files are always excluded, because all empty files are "identical". INFERRED.
- **Never read** `SF_DATALESS` files or files under cloud roots that are not materialized. Reading one blocks and downloads (VERIFIED-R, PortOS). Report them as "not compared (cloud-only)".
- **Packages are atomic.** Don't compare files inside `.app`, `.photoslibrary`, `.musiclibrary`, `.fcpbundle`, `.logicx`, `.xcodeproj` or `.git`. A *folder-duplicate* pass (below) can still flag two identical packages. INFERRED.
- **Folder duplicates (optional, dupeGuru-style).**
  - Compute a Merkle signature per directory: SHA-256 over the sorted `(relativePath, fileSize, fileHash)` children.
  - Equal signatures mean duplicate folders.
  - Suppress child matches when the parents match.
- **Concurrency.**
  - Bounded `TaskGroup` (4–8 concurrent file reads on internal SSD, 2 on external or network).
  - Hashing on a utility-QoS executor.
  - Cancellation is checked between chunks.
  - Stop keeps cached results (czkawka pattern).
- **Cache.**
  - SQLite table `hashes(volumeUUID, inode, size, mtime_ns, ctime_ns, prehash, fullhash)`.
  - Valid only if size, mtime and ctime all match.
  - Cache only files ≥ 256 KiB (czkawka uses about 257 KB).

**Smart selection (keep-one ranking).** Evaluate per group, highest score kept. Ties fall to the next rule.

| # | Rule | Detail |
|---|---|---|
| 1 | **Protected / reference location wins** | User "Always keep" folders (like Gemini "Never Select", dupeGuru reference dirs); Photos/Music library exports; anything under protected roots |
| 2 | **Preferred location score** | `~/Documents`, `~/Pictures`, `~/Music`, `~/Movies`, `~/Desktop`, project folders > external archive volumes > `~/Downloads`, `/tmp`, `~/Library/Caches`, mail-attachment folders, "Copy" or "Backup" named dirs. User "Always select from" folders score lowest |
| 3 | **Clean filename** | Penalise ` copy`, ` copy N`, ` (N)`, `-N`, `_N`, `Copy of `, `(conflicted copy)`, `.~`, and a trailing number when another member lacks it (dupeGuru "Doesn't end with number") |
| 4 | **Oldest creation date** | The original usually came first (Gemini "Oldest") |
| 5 | **Richer metadata** | Has Finder tags, comments or more xattrs |
| 6 | **Shortest path depth**, then lexicographic order | Deterministic tie-break |

**Never auto-select:**

- a group where *all* members are in the same folder with identical dates (ambiguous);
- clones or hard links (no space gain);
- items open in apps;
- anything in iCloud or File Provider roots in the Checkup.

**Deletion-time safety** (fclones-style, INFERRED; VERIFIED-R pattern):

- Re-stat every member: inode, size, mtime.
- Abort that group if the keeper vanished or changed.
- Optionally byte-compare.
- Refuse if the operation would leave zero copies.
- Move to Trash and record the undo entry.

**Advanced actions (off by default, behind "Advanced"):**

- **Replace copies with APFS clones** ("keep all paths, free the space"): `clonefile(keeper, tmp)` → `rename(tmp, copy)` after verifying the content. Same volume only. Preserve the copy's xattrs and ownership. This saves space without deleting anything, like jdupes `-B`.
- **Replace with hard links** is not recommended for user documents: editing one silently edits all of them (INFERRED).

### 5.4 UI specifics (INFERRED)

- **Group list rows:** thumbnail (QuickLookThumbnailing `QLThumbnailGenerator`), keeper name, `×N copies`, "N MB to free" (sum of `reclaimable` of the non-keepers).
- **Detail pane:** members listed with location chips and Finder-style path breadcrumbs, **keeper crown** (radio button "Keep this"), per-copy checkbox, and delta columns (dupeGuru-style) for size, dates and path.
- **"Select" menu:** Smart (default) · All but newest · All but oldest · All in folder… · None.
- **Footer:** "Removes N copies · keeps one of each".
- **Checkup ~/Downloads tile:** "N duplicate downloads · X MB".

---

## 6. Similar Images

### 6.1 Vendor behaviour (verified / relayed)

- **5.0.0** added Similar Images to My Clutter, with its own Ignore List section. VERIFIED-K (`01-overview.md` §6; cleanmymac-safety KB).
- **Replica UI (VERIFIED-R):**
  - groups with a representative thumbnail;
  - a preview strip with the **kept original flagged**;
  - a big preview;
  - a "Select:" menu;
  - headline tiles about nearly identical images.
- **Gemini 2 relay (VERIFIED-R):** "Similar" is a separate mode, not auto-selected. Photos library duplicates go to a "Gemini Duplicates" album.
- **Algorithm not documented** by MacPaw in reachable sources (GAP).

### 6.2 Open-source prior art (VERIFIED-OSS)

- **czkawka similar images.**
  - **Pipeline:**
    1. collect by extension;
    2. load hashes from the cache;
    3. resize to the hash size with the chosen filter and compute a perceptual hash;
    4. insert into a **BK-tree**;
    5. group pairs with Hamming distance ≤ `max_difference`.
  - **Hash sizes:** 8 / 16 / 32 / 64.
  - **Algorithms:** Gradient (CLI default), Mean (Krokiet default), Blockhash, VertGradient, DoubleGradient, Median.
  - **Filters:** Nearest (fast), Lanczos3 (best), Triangle, Gaussian, CatmullRom.
  - **Geometric invariance:** Off / MirrorFlip / MirrorFlipRotate90.
  - **Similarity presets** (`SIMILAR_VALUES[hashSize][level]`, levels Very High → Minimal), from `czkawka_core/src/tools/similar_images/mod.rs`:

    | Hash size | VeryHigh | High | Medium | Small | VerySmall | Minimal |
    |---|---|---|---|---|---|---|
    | 8 | 1 | 2 | 5 | 7 | 14 | 40 |
    | 16 | 2 | 5 | 15 | 30 | 40 | 40 |
    | 32 | 4 | 10 | 20 | 40 | 40 | 40 |
    | 64 | 6 | 20 | 40 | 40 | 40 | 40 |

  - The integration example uses hash size 16, max_difference 10.
- **dupeGuru picture "blocks" algorithm.**
  - Divide the image into a **15×15** grid of average colours (cached).
  - Sum the RGB differences per tile.
  - Match when the score ≤ `100 − threshold`.
  - Comparison is O(N²) and multi-core.
  - An alternative "EXIF Timestamp" mode matches `DateTimeOriginal` and is prone to false positives.
- **Apple Vision.**
  - `VNGenerateImageFeaturePrintRequest` (macOS 10.15+) produces `VNFeaturePrintObservation`s.
  - `computeDistance(_:to:)`: "Shorter distances indicate greater similarity."
  - `VNGenerateImageFeaturePrintRequestRevision2` is available from **macOS 14.0**. Revision 1 dates from macOS 10.15. VERIFIED-APPLE (developer.apple.com JSON docs, re-checked).
  - Fact-check addition: the Swift-native Vision API **`GenerateImageFeaturePrintRequest`** (struct, returns `FeaturePrintObservation`) is available from **macOS 15.0**. VERIFIED-APPLE (https://developer.apple.com/documentation/vision/generateimagefeatureprintrequest). Our macOS 14 floor means the `VN…` class API must stay the baseline, with the new API optional on 15+.
  - Revision 2 yields a normalized 768-element vector; revision 1 yields 2048. Prints from different revisions are not comparable. VERIFIED-R (https://github.com/omnifroodle/fieldproof docs/REFERENCE.md).
  - One open-source photo culler uses rev-2 distance starting points of **0.35 strict / 0.55 standard / 0.80 loose** on 300-px thumbnails. VERIFIED-R (https://github.com/hsuBnOediH/photo-filter `SimilarityEngine.swift`).

### 6.3 Our pipeline (INFERRED)

1. **Candidates.**
   - UTType conforms to `.image` (JPEG, HEIC/HEIF, PNG, TIFF, WebP, RAW). GIF only if not animated.
   - Exclude images < 200 px on the short side or < 50 KB (icons, UI assets).
   - Exclude package internals, `~/Library`, dataless cloud files and screenshots of *different* windows (handled naturally by distance).
2. **Decode cheaply.**
   - `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 256`, `kCGImageSourceCreateThumbnailWithTransform = true` (respect EXIF orientation), `kCGImageSourceCreateThumbnailFromImageIfAbsent = true` (use the embedded JPEG/HEIC thumbnail when present).
   - This avoids full HEIC/RAW decodes.
3. **Tier-1 fingerprint.** 64-bit **dHash**: 9×8 grayscale gradient. Optionally also a 64-bit pHash (32×32 DCT → top-left 8×8 vs median) for robustness. Store in the cache keyed like §5.3.
4. **Candidate pairs.**
   - BK-tree or 4-way multi-index hashing (split 64 bits into 4×16-bit tables). By pigeonhole, any pair with distance ≤ 3 shares at least one 16-bit block exactly.
   - (corrected) For the radius below (10), exact-block lookup is **not enough**. With m = 4 blocks, distance ≤ r guarantees some block is within ⌊r/4⌋ = 2. So probe each table with every key within Hamming distance 2 (1 + 16 + 120 = 137 probes per table), then verify the full distance. Or use a BK-tree. INFERRED (standard multi-index-hashing bound).
   - Hamming radius **≤ 10** (on 64-bit dHash). (corrected) This is *looser* than the earlier note said. czkawka's 8×8 (64-bit) presets are VeryHigh 1 · High 2 · Medium 5 · Small 7 · VerySmall 14 · Minimal 40 (VERIFIED-OSS, `SIMILAR_VALUES`, re-checked), so 10 sits between "Small" and "Very Small". That is acceptable only because Tier 1 is a recall-oriented pre-filter and Tier 2 (Vision) decides. If Tier 2 is disabled, default to ≤ 5 (czkawka "Medium").
5. **Tier-2 verification.**
   - For each candidate pair, compute (and cache) the Vision rev-2 feature print on a 300–512-px thumbnail.
   - Accept if distance ≤ **0.45** (default "Standard"). User slider: Strict 0.30 · Standard 0.45 · Loose 0.65.
   - Calibrate on device against a labelled set before shipping **(verify on device)**.
6. **Clustering.**
   - Union-find over accepted pairs with a **complete-linkage guard**: when merging clusters, require the new member's distance to the cluster medoid ≤ threshold × 1.2. This prevents chaining A~B~C~…~Z.
   - Optional **burst boost**: if EXIF `DateTimeOriginal` is within 3 s and the camera model matches, accept up to 1.3 × threshold.
7. **Best-shot ranking** (the keeper gets a crown, not deletion):
   - Score = w1·log(pixelCount) + w2·sharpness (variance of the Laplacian on the 512-px thumbnail via vImage/Core Image) + w3·face capture quality (`VNDetectFaceCaptureQualityRequest`, if faces exist) + w4·(has edits / is newest) + w5·file format (prefer RAW/HEIC original over a re-encoded JPEG).
   - Tie: largest file.
8. **Pairs to treat as one asset:**
   - **Live Photos** (`IMG_1234.HEIC` + `IMG_1234.MOV`, same content identifier in metadata);
   - **RAW+JPEG** pairs with the same basename;
   - edited plus original exports from Photos (`(Edited)` suffix).
   - Never split them silently. Show them as a single tile with both files.

### 6.4 Swift sketch (INFERRED)

```swift
import ImageIO
import CoreGraphics
import Vision

func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceShouldCacheImmediately: false
    ]
    return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
}

/// 64-bit difference hash (9×8 grayscale, compare horizontal neighbours).
/// (corrected) The earlier sketch passed `&px` straight to `CGContext(data:)`. Swift's
/// inout-to-pointer conversion is valid only for the duration of that init call, so the later
/// `draw` wrote through a dangling pointer. Keep context creation AND drawing inside
/// `withUnsafeMutableBytes` (or pass `data: nil` and read `ctx.data`).
func dHash(_ image: CGImage) -> UInt64? {
    let w = 9, h = 8
    var px = [UInt8](repeating: 0, count: w * h)
    let ok: Bool = px.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard ok else { return nil }
    var hash: UInt64 = 0
    for y in 0..<h { for x in 0..<(w - 1) {
        hash <<= 1
        if px[y * w + x] < px[y * w + x + 1] { hash |= 1 }
    } }
    return hash
}

@inline(__always) func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

func featurePrint(_ image: CGImage) throws -> VNFeaturePrintObservation? {
    let req = VNGenerateImageFeaturePrintRequest()
    req.revision = VNGenerateImageFeaturePrintRequestRevision2   // macOS 14+
    req.imageCropAndScaleOption = .scaleFill
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
    return req.results?.first
}

func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
    var d: Float = 0
    do { try a.computeDistance(&d, to: b) } catch { return nil }   // throws across revisions
    return d
}
```

### 6.5 Photos library handling (INFERRED unless marked)

- **Never** read or modify files inside `*.photoslibrary` directly for deletion. The library database owns them. Sibling `03-cleanup.md` §5.22 marks `originals/`, `database/` and iCloud local copies as **never (FS)**.
- **Opt-in "Scan Photos library"** uses **PhotoKit**:
  - `PHPhotoLibrary.requestAuthorization(for: .readWrite)`, with `NSPhotoLibraryUsageDescription` in Info.plist.
  - Fetch `PHAsset`s of type image. Request 256-px thumbnails via `PHCachingImageManager` with `isNetworkAccessAllowed = false`, so iCloud-optimized assets aren't downloaded. Missing thumbnails are skipped.
  - Hash as above. Group.
  - Delete with `PHAssetChangeRequest.deleteAssets(_:)` inside `PHPhotoLibrary.shared().performChanges`. Apple: "Call this method within a photo library change block to delete assets." VERIFIED-APPLE.
  - Expected platform behaviour: macOS shows a system confirmation and the assets go to **Recently Deleted** for about 30 days **(verify on device)**.
  - Fact-check addition: Apple's `performChanges(_:completionHandler:)` page says that for each call "iOS shows an alert asking the user for permission to edit the contents of the photo library", and advises combining changes into one change block. VERIFIED-APPLE (https://developer.apple.com/documentation/photos/phphotolibrary/performchanges(_:completionhandler:)). The note names iOS only, so the macOS prompt is still **(verify on device)**. Either way, put **all** selected deletions in **one** `performChanges` block so the user sees one prompt, not one per group. `deleteAssets(_:)` itself is macOS 10.15+ (VERIFIED-APPLE).
- **Fallback that mirrors the vendor.** Create an album "To Review — Similar" (our wording) and add the selected assets with `PHAssetCollectionChangeRequest`. The user then deletes from Photos.
  - CMM3 did this for Large & Old ("Large Media to Delete" album). VERIFIED-V strings.
  - Gemini did this for duplicates ("Gemini Duplicates" album). VERIFIED-V/R.
- **Recommend Photos' own built-in Duplicates album** (Photos › Utilities › Duplicates with Merge, macOS 13+), and show a deep-link button. INFERRED (platform knowledge; verify the menu path on macOS 26).

---

## 7. Downloads

### 7.1 Vendor behaviour

- **5.x My Clutter › Downloads:** old **DMGs, archives, documents**. VERIFIED-K (`01-overview.md` §5.2). My Tools has a "Downloads" tool. VERIFIED-K. A replica's tool description calls these "one-time use files" (VERIFIED-R).
- **X System Junk "Downloads" smart-selection rules:** Safari, only **broken** downloads; Slack, broken **or ≥ 1 month old**. VERIFIED-K (https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk).
- **Smart Care** pre-selects duplicate downloads. VERIFIED-K.
- **Replica evidence (VERIFIED-R).** VaderCleaner groups Downloads **by source app**. It reads the `com.apple.quarantine` xattr (`;`-separated; field index 2 = downloading agent) and titles the card with the dominant source by bytes, e.g. "Google Chrome Downloads". (corrected path) The file is `VaderCleanerCore/Sources/VaderCleanerCore/DownloadsScanner.swift`, plus `DownloadSourceResolver.swift`, which maps the agent string to an installed app (bundle ID, name or executable) for the icon.
- **Quarantine field layout (VERIFIED-OSS).** exiftool decodes `com.apple.quarantine` as "Flags=0082 set at 2020:11:12 12:27:26 by Safari", i.e. `flags;hex-unix-time;agent;UUID`. That confirms field 2 = agent and field 1 = download time (exiftool test output `t/MacOS_2.out`, mirrored at https://github.com/whmou/insta360-auto-converter).
- **Second download-time source (VERIFIED-OSS, same exiftool sample).** The xattr `com.apple.metadata:kMDItemDownloadedDate` holds the download date. Prefer it over `kMDItemDateAdded` for "downloaded N days ago", because `DateAdded` resets when a file is moved into Downloads from elsewhere.
- **X history (VERIFIED-V DevMate X 4.4.6 page):** "Downloads cleanup feature within System Junk" arrived in **4.4.3**, and "Chrome Downloads cleanup within System Junk" in **4.4.6**.

### 7.2 Our Downloads review (INFERRED)

- **Roots:** `~/Downloads` (TCC "Downloads folder" consent if FDA isn't granted), plus optional additional download folders (Telegram/WhatsApp/Discord media folders, browser-specific dirs).
- **Facets:**
  - **By kind:** Installers (`.dmg .pkg .mpkg .iso .xip`), Archives, Incomplete (`.download` bundles from Safari, `.crdownload`, `.part`, `.partial`, `.opdownload`, `.tmp` siblings), Documents, Images, Video, Audio, Other.
  - **By source:**
    - App: from the `com.apple.quarantine` agent name (e.g. "Safari", "Google Chrome", "Telegram"; AirDrop arrivals show "sharingd").
    - Site: from `kMDItemWhereFroms` (the URL list in the `com.apple.metadata:kMDItemWhereFroms` binary-plist xattr). Show the registrable domain.
  - **By age:** (corrected order) from `kMDItemDownloadedDate` (xattr `com.apple.metadata:kMDItemDownloadedDate`), else the quarantine timestamp, else `kMDItemDateAdded` (when it landed in Downloads). Same buckets as §4.2.
  - **Opened?** "Never opened" if there is no `kMDItemLastUsedDate`.
- **Hints:**
  - "**Installer already used**": the DMG/PKG name matches an installed app in `/Applications` (normalise names: strip versions and arch suffixes) and the app's install date is later than the download date.
  - "**Archive already extracted**": a sibling folder with the archive's basename exists and was created after the archive.
  - Both shown as chips, never auto-selected.
- **Default selection:**
  - Incomplete downloads with mtime > 24 h, not open, and whose owning browser isn't actively downloading them (Safari `.download` bundles contain an `Info.plist`; check mtime).
  - Everything else unselected.
  - The Checkup pre-selects exact duplicates in Downloads (vendor parity).
- **Action:** Move to Trash (default). "Move to Folder…" for an archive drive.

---

## 8. Space Lens → our "Space Map"

### 8.1 Vendor behaviour (verified)

- **History:** introduced in CleanMyMac X and left beta in **4.4.0** (VERIFIED-K, https://macpaw.com/news/cleanmymac-x-update-4.4.0). Absent from 5.0. **Returned in 5.1.0** (MacPaw date 2025-06-12; the App Store lists it under 5.1.1 on 2025-07-04). VERIFIED-K/V.
- **Visual form (5.1+).** DevMate 5.1.0 notes, VERIFIED-V (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html):
  - "Welcome back, Space Lens!";
  - a reimagined storage visualisation that "creates a map of your storage, displaying folders as bubbles arranged from largest to smallest";
  - you can zoom in to find what takes the most space and remove it.
- **Flow:**
  - It is a sidebar item. Pick a volume or folder → **Scan** → bubble map → zoom in → select & remove. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/space-lens via `01-overview.md`).
  - Plus plan only. VERIFIED-K (feature-plans KB).
  - Also used inside Cloud Cleanup to map cloud storage. VERIFIED-V (DevMate 5.2.1: "use familiar tools like Space Lens and Large Files to scan and remove unnecessary files").
- **CleanMyMac X visual form.** Our sibling report describes it as a "sunburst-ish bubble map" (`01-overview.md` §7). From product memory it was a **bubble (circle) chart beside a left-hand list**.
  - (upgraded from INFERRED) A third-party summary of the **X** Space Lens KB (https://macpaw.com/support/cleanmymac-x/knowledgebase/space-lens) describes it as "a size-based bubble map with a complete file list". Hovering in the map highlights the list row, and the summary also lists drill-down, Quick Look / Reveal, checkboxes and a **Review Selected** step before removal. VERIFIED-R (https://raw.githubusercontent.com/HuakunShen/space-lens/HEAD/apps/web/UX_RESEARCH.md; also https://raw.githubusercontent.com/kali-physi-hacker/veyra/HEAD/docs/product-research.md for the 5.x `space-lens-results` KB: coordinated map/list, size ordering, breadcrumbs, separate selection review). Whether X used *pure* circle packing or a hybrid is still not documented.
  - **X release notes (VERIFIED-V, DevMate):**
    - 4.3.0: Space Lens debuts as **Beta** ("instantly identify the largest space wasters").
    - 4.4.0: out of beta ("Visualize your disk space in a matter of seconds … Interacting with the storage map").
    - 4.4.1: "Better sidebar scan results indication for Space Lens".
    - 4.4.3: fixed a "Crash on **Purgeable Space popover** click within Space Lens", so X **did show purgeable space** in Space Lens.
    - 4.4.4: fixed "Space Lens scan results might have included the size of **mounted Volumes**", so it is meant to stop at mount points.
    - 4.4.6: "Quick Look preview by double click".
    - 4.5.2: fixed a crash when navigating.
    - 4.6.9: "Displaying the correct **Users folder size**" (consistent with a firmlink double-count class of bug).
    - 4.15.4 (2024-06-19): "Space Lens now automatically **ignores cloud-stored files**. They don't use your local disk space anyway", so sizes reflect **local on-disk usage**, not logical cloud size.
  - **We are confident neither version used a treemap.** DaisyDisk (sunburst rings) and GrandPerspective (treemap) are the other common forms (§8.6).
- **Replica evidence (VERIFIED-R).** MacOptimizer `SpaceLensView.swift` reproduces the X/5.x layout:
  - **landing:** title + one-line description + disk-selector card (volumes, Home, "Select Folder…") + floating **Scan**;
  - **scanning:** planet animation, "Building your storage map…", current path, **Stop** with a progress ring and running total;
  - **results:** 300-pt **left list** (back/forward chevrons, breadcrumb, rows with a selection circle, icon, name, item count, size, drill chevron) + **circular bubble canvas** on the right + **Start Over** + bottom **Remove** orb showing the selected size + confirmation overlay;
  - standard home folders (Library, Downloads, Movies, Pictures, Documents, Applications, Desktop, Music, Public) can't be selected for removal.
  - **Do not reuse that wording.**
- **MacPaw CLI `analyze`**, the vendor's terminal analogue (VERIFIED-V, https://github.com/MacPaw/cleanmymac-cli + wiki):
  - interactive explorer starting at home or a given path;
  - header "X GB of Y GB free";
  - rows: checkbox, name, size, % of total, usage bar, `→` to drill in;
  - sorted by size; small items roll up into **"Other (N items)"**;
  - keys: ↑↓←→, ⌫ delete, Space toggle, A select all, **O reveal in Finder**, Esc back, Q quit;
  - browsing is read-only; removal needs explicit selection and confirmation.

### 8.2 Our Space Map UI (INFERRED)

```
┌ Space Map ───────────────────────────────────────────────────────────────┐
│ ◀ ▶  Macintosh HD › Users › me › Movies          312 GB used · 182 GB free│
│ ┌ List (≈320 pt) ───────────┐ ┌ Bubble canvas ─────────────────────────┐ │
│ │ ☐ ▣ Final Cut   128 GB 41%›│ │              ( Final Cut )             │ │
│ │ ☐ ▣ Footage      64 GB 20%›│ │     ( Footage )        ( Exports )     │ │
│ │ ☐ ▣ Exports      22 GB  7%›│ │  (VM)  (Other 1 204 items)   (Music)   │ │
│ │ ☐ 🔒 Library (no access)   │ │                                        │ │
│ │ … Other (1 204 items) 9 GB │ │  hover: name · size · items · modified │ │
│ └───────────────────────────┘ └────────────────────────────────────────┘ │
│  [Rescan] [View: Bubbles ▾ | Tiles | Rings]      3 selected · 14.2 GB [Move to Trash]│
└──────────────────────────────────────────────────────────────────────────┘
```

- **Interaction:**
  - Click a folder bubble (or the row chevron) to **zoom in**. The animated transition respects Reduce Motion (the vendor honoured Reduce Motion from 5.0.7, VERIFIED-K).
  - Click a file to toggle selection. Breadcrumb and back/forward to zoom out.
  - Keyboard: arrows, Return (enter), ⌫ (select for removal), Space (Quick Look), ⌘R (reveal) — similar to the CLI's key map.
- **Top-N + Other:** show the top **24** children as bubbles (clones use 14–24); the remainder becomes one non-drillable "Other (N items)" bubble. CLI parity: "Other (N items)".
- **Labels:** draw name and size only when radius > ~28 pt. Font scales with radius and is capped. Tooltip always.
- **Colours** (original palette, not MacPaw's): folders in one hue ramp by size rank, files neutral, packages a second hue. Inaccessible (TCC-denied) nodes get a warning hue and a lock glyph. Pseudo-nodes are hatched.
- **Pseudo-nodes at volume root** (§8.4): "macOS (sealed system)", "Other volumes (VM / Preboot / Recovery)", "Purgeable (managed by macOS)", "Local snapshots", "Not accessible / unscanned".
- **Deletion:**
  - "Move to Trash" for selected nodes after a confirm sheet listing paths and sizes.
  - Protected nodes have no checkbox: volume roots, `/System`, `/Library`, `/Applications` (the folder itself), home itself, the standard home folders themselves, `~/Library`, cloud roots (use Cloud Storage).
  - Precedent: OpenDisk and SquirrelDisk protect system folders, home and whole drives. VERIFIED-OSS.

### 8.3 Layout algorithm: circle packing (INFERRED, with OSS precedent)

- **Radius from size:** `r_i = sqrt(size_i / π) · k`, so **area ∝ size**. Sort children **descending** to get "largest to smallest" (vendor wording).
- **Packing:** d3-hierarchy's **front-chain** sibling packing (VERIFIED-OSS, `d3-hierarchy/src/pack/siblings.js`):
  1. place circles 1–3 mutually tangent;
  2. keep a circular doubly linked "front chain";
  3. place each new circle tangent to the current pair (a, b);
  4. search the chain for intersections, moving the pair on a hit;
  5. otherwise insert it;
  6. choose the next pair by the minimum distance of the radius-weighted midpoint to the origin, which keeps growth compact around the centre;
  7. finally compute the enclosing circle (Welzl-style `packEnclose`) and centre it.
  - It is about O(n²) worst case, which is trivial for n ≤ 25. Use a seeded LCG for determinism.
- **Fit:** scale so the enclosing circle fits `min(width, height) − padding`. Animate between levels by interpolating each child's frame from its parent bubble's frame.
- **Cache:** memoize the layout per (node ID, sizes hash, canvas size). Selection changes don't re-layout. The MClean clone does exactly this (VERIFIED-R).
- **Alternate views (optional):**
  - **Tiles:** squarified treemap. d3 `squarify` uses the golden ratio φ as the target aspect and greedily grows a row while the worst aspect ratio doesn't worsen. VERIFIED-OSS `src/treemap/squarify.js`.
  - **Rings:** sunburst / partition, like DaisyDisk and SquirrelDisk.

### 8.4 Scanning engine and size semantics (INFERRED, with verified building blocks)

**Enumeration.**

- Use `getattrlistbulk(2)` per directory FD, which returns many entries' attributes per syscall. `ATTR_CMN_NAME` and `ATTR_CMN_RETURNED_ATTRS` are mandatory, and per-entry `ATTR_CMN_ERROR` follows `RETURNED_ATTRS`. VERIFIED-APPLE (xnu `bsd/man/man2/getattrlistbulk.2`).
- **Attributes to request:**
  - common: `NAME, DEVID, OBJTYPE, FLAGS, FILEID, MODTIME, ACCTIME, ADDEDTIME`;
  - file: `LINKCOUNT, TOTALSIZE, ALLOCSIZE`;
  - extended (in `forkattr` with the extended-common option): `ATTR_CMNEXT_PRIVATESIZE`, `ATTR_CMNEXT_EXT_FLAGS`, `ATTR_CMNEXT_CLONEID`.
  - The forkattr carriage of CMNEXT is VERIFIED-APPLE (xnu `attr.h` comment). (corrected: confirmed) The option is `FSOPT_ATTR_CMN_EXTENDED = 0x00000020` in xnu `bsd/sys/attr.h`, and `getattrlistbulk(2)` accepts it ("forkattrs are reinterpreted as a set of extended common attributes"). VERIFIED-APPLE.
  - Also request `ATTR_DIR_MOUNTSTATUS` (dirattr 0x4), `ATTR_DIR_LINKCOUNT` (0x1) and optionally `ATTR_DIR_ALLOCSIZE` (0x8, the directory's own physical size). VERIFIED-APPLE (`attr.h`, `getattrlist.2`).
  - More `ATTR_CMNEXT_EXT_FLAGS` bits worth using (VERIFIED-APPLE, `getattrlist.2`):
    - `EF_SHARES_ALL_BLOCKS`: a full clone (implies `EF_MAY_SHARE_BLOCKS`), i.e. 0 B reclaimable;
    - `EF_IS_PURGEABLE`: an item the file system may delete when asked to free space. Show it as purgeable, never as clutter;
    - `EF_IS_SYNC_ROOT`: a directory that is a sync root. A cheap way to recognise File Provider and iCloud roots;
    - `EF_NO_XATTRS`: skip `listxattr`.
  - **Always check the returned-attrs bitmap before reading each field.** File attributes aren't present for directories.
- **Concurrency:** ~**8** directory readers for a full internal-SSD scan. OpenDisk reports that APFS locks directory reads, so more threads slow things down, and that it does a 1 TB cold scan in 17 s vs DaisyDisk 37 s (its own benchmark). VERIFIED-OSS (https://github.com/137137137/OpenDisk). Use 2–4 on external or network volumes.
- **Fallback:** `FileManager.enumerator(at:includingPropertiesForKeys:options:)`, without `.skipsPackageDescendants` (Space Map needs package contents; Clutter rolls packages up itself), prefetching `.totalFileAllocatedSizeKey` ("total allocated size … includes the size of any file metadata", VERIFIED-APPLE), `.fileSizeKey`, `.linkCountKey`, `.fileResourceIdentifierKey`, `.mayShareFileContentKey`, `.isSymbolicLinkKey`. Slower, but simpler for v1.

**Boundaries.**

- ~~A directory whose `st_dev` differs from its parent's is a **mount point**.~~ (corrected) With `getattrlistbulk`, a mount-point directory reports the attributes of the *underlying* file system, so its `ATTR_CMN_DEVID` equals the parent's and a device-ID comparison misses it. Detect mount points with `ATTR_DIR_MOUNTSTATUS & DIR_MNTSTATUS_MNTPOINT` (0x1). Emit a stub and don't descend (like `du -x`). VERIFIED-APPLE (xnu `getattrlistbulk.2`: "the attributes for the mount point will be those from the (underlying) file system"). The `st_dev` comparison is still valid when the walker `lstat`s a path *after* opening it (FTS-style), so keep it as a second check.
- (new) **Automount triggers:** never descend into a directory with `DIR_MNTSTATUS_TRIGGER` (0x2). Entering it can fire an automount (autofs / network home), which hangs the scan. VERIFIED-APPLE (`attr.h`); behaviour INFERRED.
- (new) **Firmlinks are flagged in-band:** `SF_FIRMLINK` (0x00800000) appears in `ATTR_CMN_FLAGS`, and bulk attributes are "those from the firmlink, not the firmlink's target". VERIFIED-APPLE (`getattrlistbulk.2`, `stat.h`).
- **Exception:** the firmlinks listed in `/usr/share/firmlinks` are the sanctioned crossing that merges the system and data views. Their `/System/Volumes/Data` twins are then stopped by the boundary rule, so nothing is walked twice. If the file is unreadable, refuse all crossings. VERIFIED-OSS (Ferail `disk_usage_scanner.rs`). With volume groups, `ATTR_CMN_DEVID` may return one *logical* value for both System and Data, unless `FSOPT_RETURN_REALDEV` is passed. VERIFIED-APPLE (`getattrlist.2`). Use the `SF_FIRMLINK` flag and the firmlinks list, not device IDs, to decide.
- OpenDisk also stops at mount points and snapshots. VERIFIED-OSS.
- **Recommended roots:**
  - "Macintosh HD" → walk `/` with the firmlink rule.
  - "Data only" → walk `/System/Volumes/Data`.
  - Any folder → walk from it.
- **Symlinks:** never follow; count as 0-byte leaves. VERIFIED-OSS (Ferail).
- **Hard links:** count `(dev, ino)` once when `linkCount > 1`. Otherwise `cp -al` backups and Homebrew Cellars over-report. VERIFIED-OSS (Ferail; dust "does not count hard links multiple times").
  - Apple's own `du` does the same and also counts **directory hard links once** ("typically Time Machine backups", i.e. HFS+ backup disks). VERIFIED-APPLE (file_cmds `du/du.1`; `-A` shows apparent size instead of disk usage). So apply the `(dev, ino)` set to directories with `ATTR_DIR_LINKCOUNT > 1` too, and treat Time Machine HFS+ volumes as info-only nodes.
- **Cloud folders:** (new) Listing a *dataless directory* triggers materialization of its listing. Apple's TN3150 trace shows `getattrlistbulk` → `apfs_materialize_dataless_file_ext`. With the materialization iopolicy off (§17.2), such reads fail with `EDEADLK` instead. Show the folder as "cloud folder — not listed locally" and size it from the provider's local view only. VERIFIED-APPLE (TN3150).

**Sizes.**

| Quantity | Source | Shown as |
|---|---|---|
| **Allocated** ("on disk") | `ATTR_FILE_ALLOCSIZE` (physical bytes of all forks, VERIFIED-APPLE) or `totalFileAllocatedSizeKey` | **default bubble size** |
| Logical | `ATTR_FILE_TOTALSIZE` (logical bytes of all forks, VERIFIED-APPLE) | tooltip, toggle |
| **Reclaimable** | `ATTR_CMNEXT_PRIVATESIZE`: bytes "not trapped inside a clone or snapshot … freed immediately if the file were deleted" (VERIFIED-APPLE `getattrlist.2`) | "frees ≈ X" in the confirm sheet |
| Clone status | `EF_MAY_SHARE_BLOCKS` in `ATTR_CMNEXT_EXT_FLAGS`; `ATTR_CMNEXT_CLONEID` (pure clones share it); `ATTR_CMNEXT_CLONE_REFCNT`; Foundation `mayShareFileContentKey` / `fileContentIdentifierKey` ("APFS allows only cloned files and their originals to have the same identifier", macOS 11+) — all VERIFIED-APPLE | badge |
| Sparse | `EF_IS_SPARSE` (VERIFIED-APPLE) | badge |
| Cloud placeholder | `st_flags & SF_DATALESS` (0x40000000, "file is dataless object", VERIFIED-APPLE xnu `stat.h`); alt. `size > 0 && blocks == 0` scoped to cloud roots (VERIFIED-R PortOS) | excluded from local totals, shown hatched with its logical size |

**Volume-level accounting** (for the root pseudo-nodes):

- **Free:** `volumeAvailableCapacity`.
- **Important-usage free:** `volumeAvailableCapacityForImportantUsage`.
- **Purgeable ≈ important − free** (VERIFIED-OSS diskhound formula; sibling `05-performance.md` §4.2 uses the same).
- `volumeAvailableCapacityForOpportunisticUsage` is "available capacity … for storing nonessential resources". Apple flags these capacity APIs as **required-reason APIs** that must be declared in `PrivacyInfo.xcprivacy`. VERIFIED-APPLE. This matters only for App Store distribution, but add the manifest anyway.
- **Per-APFS-volume "in use"** (System, Data, Preboot, VM, Recovery) from `diskutil apfs list -plist` → `CapacityInUse`. All volumes in a container share one free pool. VERIFIED-OSS (diskhound).
- **Snapshots:** list via `diskutil apfs listSnapshots -plist` / `tmutil listlocalsnapshots /`. macOS does **not** expose how much each snapshot holds. VERIFIED-OSS (diskhound comment). Show the count and explain that they are part of purgeable/"System Data".
- **"System Data / not accessible"** = Data-volume in-use − scanned allocated sum − purgeable estimate (clamped ≥ 0). Label it honestly: "Space used by macOS, snapshots and folders we can't read". Explain that granting Full Disk Access shrinks it.

**Speed and memory.**

- Stream partial results: the UI updates every 250 ms (Ferail throttles progress to ~250 ms, VERIFIED-OSS).
- **Incremental rescans:**
  - persist the tree plus the last FSEvents event ID;
  - on the next open, replay `FSEventStreamCreate(… sinceWhen: lastID …)` and rescan only the changed directories;
  - OpenDisk reports rescans 20–28× faster (VERIFIED-OSS);
  - fall back to a full scan if `kFSEventStreamEventFlagMustScanSubDirs` or history wrap.
- **Compact node store:** struct-of-arrays (parent `UInt32`, first child `UInt32`, next sibling `UInt32`, allocated `UInt64`, logical `UInt64`, flags `UInt16`, name offset `UInt32` into a byte arena). About 40 B per node plus the name, so 3 M nodes ≈ 250 MB worst case.
- **Summarize directories** with > 10 k tiny files into one aggregate child ("1 234 small files"), as Radix does (VERIFIED-OSS https://github.com/colinvkim/Radix).
- **Cancel:** checked between directory batches. Cancelled scans are marked partial and never cached as complete (Ferail, Mole — VERIFIED-OSS).

**Permissions.**

- Without FDA, TCC-protected folders (`~/Library/Mail`, `~/Library/Messages`, Safari, other apps' containers, and possibly Desktop, Documents and Downloads prompts) return `EACCES`/`EPERM`.
- Show them as locked bubbles, count them in the "not accessible" pseudo-node, and offer a banner deep-link to System Settings › Privacy & Security › Full Disk Access.
- OpenDisk and Radix both detect skipped folders and walk the user through enabling FDA. VERIFIED-OSS.

### 8.5 Swift sketch of the bulk directory reader (INFERRED; verify field offsets against the SDK)

```swift
import Darwin

struct RawEntry { var name: String; var type: fsobj_type_t; var dev: dev_t; var flags: UInt32
                  var fileID: UInt64; var linkCount: UInt32; var logical: off_t; var allocated: off_t }

/// Reads one directory with getattrlistbulk. Attributes come back in bit order within each group,
/// preceded by the entry length and attribute_set_t (RETURNED_ATTRS). Always test `returned` bits.
@inline(__always) func g<T: BinaryInteger>(_ v: T) -> attrgroup_t { attrgroup_t(truncatingIfNeeded: v) }

func readDirectory(fd: Int32, into body: (RawEntry) -> Void) throws {
    var req = attrlist()
    req.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    // RETURNED_ATTRS is 0x80000000; the Swift import type of these macros varies, hence g(_:).
    // Production code should also request ATTR_CMN_ERROR (returned right after RETURNED_ATTRS)
    // and ATTR_CMNEXT_* via req.forkattr with the extended-common option.
    req.commonattr  = g(ATTR_CMN_RETURNED_ATTRS) | g(ATTR_CMN_NAME) | g(ATTR_CMN_DEVID) |
                      g(ATTR_CMN_OBJTYPE) | g(ATTR_CMN_FLAGS) | g(ATTR_CMN_FILEID)
    req.fileattr    = g(ATTR_FILE_LINKCOUNT) | g(ATTR_FILE_TOTALSIZE) | g(ATTR_FILE_ALLOCSIZE)
    let cap = 256 * 1024
    let buf = UnsafeMutableRawPointer.allocate(byteCount: cap, alignment: 8)
    defer { buf.deallocate() }
    while true {
        let n = getattrlistbulk(fd, &req, buf, cap, 0)
        if n < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if n == 0 { return }
        var entry = buf
        for _ in 0..<n {
            let len = Int(entry.load(as: UInt32.self))
            var p = entry + MemoryLayout<UInt32>.size
            let returned = p.load(as: attribute_set_t.self); p += MemoryLayout<attribute_set_t>.size
            // ATTR_CMN_NAME → attrreference_t relative to its own address
            let nameRef = p.load(as: attrreference_t.self)
            let name = String(cString: (p + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
            p += MemoryLayout<attrreference_t>.size
            let dev   = p.load(as: dev_t.self);          p += MemoryLayout<dev_t>.size
            let type  = p.load(as: fsobj_type_t.self);   p += MemoryLayout<fsobj_type_t>.size
            let flags = p.load(as: UInt32.self);         p += MemoryLayout<UInt32>.size
            let fid   = p.loadUnaligned(as: UInt64.self); p += MemoryLayout<UInt64>.size
            var e = RawEntry(name: name, type: type, dev: dev, flags: flags, fileID: fid,
                             linkCount: 1, logical: 0, allocated: 0)
            if returned.fileattr & g(ATTR_FILE_LINKCOUNT) != 0 {
                e.linkCount = p.load(as: UInt32.self); p += MemoryLayout<UInt32>.size }
            if returned.fileattr & g(ATTR_FILE_TOTALSIZE) != 0 {
                e.logical = p.loadUnaligned(as: off_t.self); p += MemoryLayout<off_t>.size }
            if returned.fileattr & g(ATTR_FILE_ALLOCSIZE) != 0 {
                e.allocated = p.loadUnaligned(as: off_t.self); p += MemoryLayout<off_t>.size }
            body(e)
            entry += len
        }
    }
}
// Then: dataless = (flags & UInt32(SF_DATALESS)) != 0; hard link = linkCount > 1 → dedupe (dev, fileID);
// (corrected) mount point: request req.dirattr = ATTR_DIR_MOUNTSTATUS (comes after the common attrs, before
// fileattr) and test DIR_MNTSTATUS_MNTPOINT; do NOT rely on dev != parentDev, because bulk results for a
// mount point carry the covered directory's devid. firmlink = (flags & UInt32(SF_FIRMLINK)) != 0 →
// cross only if listed in /usr/share/firmlinks. Skip DIR_MNTSTATUS_TRIGGER directories.
// Attribute order in each record: RETURNED_ATTRS, [ERROR], common (bit order), dir, file, then forkattr/CMNEXT.
```

### 8.6 Comparable visualisers (for design reference only)

| Tool | Form | Notable behaviour | Source |
|---|---|---|---|
| CleanMyMac 5.1+ Space Lens | **Bubbles**, largest → smallest, zoom | sidebar item; select & remove; reused for cloud | VERIFIED-V/K |
| MacPaw CLI `analyze` | List with % bars, "Other (N items)" | read-only browse; O = reveal | VERIFIED-V |
| DaisyDisk | Sunburst rings | (site unreachable; well-known) | INFERRED |
| GrandPerspective | **Treemap** (area ∝ size; colour by name, extension, type, folder, level, size, dates) | hard-link aware (Time Machine); filters; save/reload scans; refresh | VERIFIED-OSS https://grandperspectiv.sourceforge.net/ |
| SquirrelDisk v2 | **Sunburst** default, treemap option | click to zoom, centre to go back; collector → Trash / permanent / copy-out; optional 3-pass overwrite; protects system, home, whole drives | VERIFIED-OSS https://github.com/adileo/squirreldisk |
| dust | Terminal tree with bars | disk usage by default, `-s` apparent size; hard links counted once; `-T` threads | VERIFIED-OSS https://github.com/bootandy/dust |
| OpenDisk | Sunburst | `getattrlistbulk`, ~8 readers, stops at mounts and snapshots, FSEvents replay, shows purgeable | VERIFIED-OSS |
| Radix | Sunburst + treemap | APFS-clone aware; summarizes tiny-file dirs; FDA guidance | VERIFIED-OSS |

---

## 9. Shredder → our "Eraser"

### 9.1 Vendor behaviour (verified)

- **CMM3 Help topic-92** (VERIFIED-V, …/English.lproj/topic-92.html):
  - add items with **Select Files** → Open, or **drag and drop**; **Add Files** for more;
  - checkbox per item, **Deselect All**, Sort by, search;
  - **Shred** erases "in an ordinary way" (default, "Remove immediately");
  - **Remove Securely** from the pop-up next to Shred rewrites data with zeros and is slower;
  - secure removal still worked even though El Capitan dropped Secure Empty Trash;
  - Shredder **completes removal even when Finder reports errors for items used by current processes**.
- **CMM3 strings** (VERIFIED-V):
  - internal scanner name `EraserGroupScanner`; description: erase files or folders quickly "without leaving a trace";
  - benefits: securely erases sensitive data, and "Gets around various Finder errors" / removes "items locked by running processes";
  - completion: "%@ shredded." + "Add or simply drag and drop more files for shredding.";
  - list strings: "Zero KB", "Remove from List", "Sort by Name ▾" (Name/Type/Size);
  - related alerts: "Item was not removed, because you didn't quit the related process.", "Dependent applications should be quit to perform the requested operation:".
- **X:**
  - in the "Files" section (VERIFIED-K `01-overview.md` §7);
  - the **Safety Database makes it refuse critical folders** (VERIFIED-K https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database);
  - **not in the App Store edition** (VERIFIED-K missing-features KB);
  - described by reviewers as also fixing "can't delete" files (VERIFIED-K `01-overview.md` §7).
- **5.0:** removed (VERIFIED-K). Trash Bins in CMM3 also offered "Remove Securely" (zero overwrite) next to **Empty** (VERIFIED-V topic-6).

### 9.2 Platform reality on Apple Silicon / APFS

- **Apple has abandoned overwrite-based deletion.**
  - The current `rm(1)` says `-P` "has no effect" and is kept only for 4.4BSD-Lite2 compatibility. VERIFIED-APPLE (https://raw.githubusercontent.com/apple-oss-distributions/file_cmds/main/rm/rm.1).
  - Secure Empty Trash disappeared in OS X 10.11. VERIFIED-V (CMM3 Help notes it).
- **Why overwriting is unreliable here** (INFERRED, platform and storage knowledge):
  1. SSD controllers remap writes (wear levelling, over-provisioning), so an "overwrite" lands on new NAND pages while old pages linger until garbage-collected.
  2. APFS is copy-on-write for metadata and keeps old blocks referenced by **snapshots** (Time Machine local snapshots, OS-update snapshots). `ATTR_CMNEXT_PRIVATESIZE` explicitly excludes bytes "trapped inside a clone or snapshot" (VERIFIED-APPLE), so overwriting a cloned or snapshotted file can't touch those blocks.
  3. Copies exist elsewhere: iCloud/File Provider servers, Time Machine backups, Spotlight/QuickLook thumbnail caches, app autosave versions (`/.DocumentRevisions-V100`).
  4. The internal SSD on Apple Silicon is always hardware-encrypted, and FileVault adds the user-password binding. Deleted data without keys is unreadable, so **FileVault-on + normal delete** is the meaningful guarantee. Verify against Apple Platform Security guide wording before stating it in UI copy.
- **Overwriting cloud items is dangerous.**
  - Writing to a dataless file first **downloads** it (`O_TRUNC` and append writes materialize, ~0.7–0.9 s per 5 MB). VERIFIED-R (PortOS measured on macOS 26).
  - Overwriting a synced file would **upload zeros** to the cloud and every device (INFERRED).
  - The Eraser must refuse cloud-rooted files, or only delete them.

### 9.3 Our Eraser spec (INFERRED)

- **Entry points:**
  - the Tools hub;
  - drag files onto the Eraser drop zone or the Dock icon;
  - Finder Services / Share extension ("Erase with <App>");
  - context menu in Clutter and Space Map.
- **List:** name, kind, size, reason chips. Remove-from-list, sort, search.
- **Modes:**
  1. **Delete (force)**, the default. It is permanent (no Trash) and handles the "can't delete" cases:
     - **Locked:** clear `UF_IMMUTABLE` (`uchg`) with `chflags`/`lchflags` after confirmation. `SF_IMMUTABLE` or SIP (`com.apple.rootless` xattr, `SF_RESTRICTED`) is **refused**.
     - **In use:** find holders via `proc_listpidspath`/`lsof` and offer "Quit <App> and retry". Never kill system processes. This mirrors the CMM3 "quit the related process" alerts, VERIFIED-V.
     - **Permission denied / root-owned** inside the user's home or `/Applications`/`/Library` third-party items: route to the **privileged helper**, which accepts only (path, expected inode) pairs, re-validates with `O_NOFOLLOW` and `realpath`, checks the allow-list (§12.4), deletes with `removefile(3)` (`REMOVEFILE_RECURSIVE`), and never follows symlinks. This is the lesson of the Talos 2018 CleanMyMac X helper CVEs (VERIFIED-K/OSS).
     - **Busy volume / external:** ok. **Network shares:** delete directly (no Trash).
  2. **Overwrite, then delete (best effort)**, with a caveat panel.
     - **Allowed only if** the item is a regular file on a local volume; `EF_MAY_SHARE_BLOCKS` is clear (not a clone); there are no local snapshots on that volume (`tmutil listlocalsnapshots` empty), or the user acknowledges they will retain old data; it is not under a cloud root and not dataless; and the link count is 1.
     - **Procedure:**
       1. `open(O_WRONLY|O_NOFOLLOW)`;
       2. `fcntl(F_NOCACHE, 1)`;
       3. write 1 pass of random bytes (`SecRandomCopyBytes` / ChaCha stream) in 1 MiB chunks to the full logical length;
       4. `fcntl(F_FULLFSYNC)`;
       5. `ftruncate(0)`;
       6. rename to a random name in the same directory;
       7. `unlink`.
     - **One pass** (no DoD 3-pass theatre). SquirrelDisk offers 3-pass DoD 5220.22-M (VERIFIED-OSS), but more passes add no assurance on flash (INFERRED).
     - **Directories:** recurse with the same per-file checks. Skip and report non-regular files.
     - **UI copy:** "On SSDs and APFS, overwriting cannot guarantee that old data is unrecoverable. FileVault is the reliable protection. This option is best effort."
- **Refuse list:**
  - volume roots, `/`, `/System`, `/usr`, `/bin`, `/sbin`, `/Library` (root), `/Applications` (root), `~` (home itself), `~/Library` (root), `/private/var/db`, the running app's bundle;
  - anything with `SF_RESTRICTED` or `com.apple.rootless`;
  - mount points;
  - Photos and Music library packages ("use Photos").
  - CMM X refused critical folders too (VERIFIED-K).
- **Confirmation:** a sheet with the count, total and mode. Typed confirmation ("ERASE") when more than 1,000 items or more than 10 GB are selected, or when the mode is overwrite.
- **Completion:** "%@ erased". A failures list with reasons. **No undo.** The activity log records the paths, hashed if the user enables "private log".
- **Not offered:** "erase free space". On APFS/SSD it is not meaningful and not supported by Apple tooling (INFERRED). Point to "Erase Mac" / FileVault in System Settings for disposal.

---

## 10. Cloud Cleanup → our "Cloud Storage"

### 10.1 Vendor behaviour (verified)

- **5.2.1 (2025-07-29)**, DevMate notes, VERIFIED-V:
  - connect **iCloud Drive, Google Drive, OneDrive**;
  - delete files that exist **only in the cloud** from inside the app;
  - remove files synced to the Mac **from both Mac and cloud in one action**;
  - **unsync** = remove from the Mac but keep in the cloud;
  - **Space Lens and Large Files** scan cloud storage.
- (corrected: resolved) **5.3.0 (2025-12-17):** **Dropbox** support + improved **OneDrive** integration. The direct-channel notes say: "introduce Dropbox and OneDrive integration … connect your Dropbox account to CleanMyMac", and OneDrive integration was "improved". The DevMate appcast lists 5.3.0 as build `50300.0.2512161141`, pubDate 2025-12-17 10:31 UTC. 5.3.1 (2026-01-28) is fixes only. The App Store's attribution to 5.3.1 is App Store lag. VERIFIED-V (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html; …/updates.xml).
- **Accounts and scope.**
  - Accounts are connected per provider, Google via browser OAuth. Views are a Space Lens map plus a Large Files list per account.
  - **Google Drive only sees files from Google's official desktop client.**
  - Plus plan only.
  - VERIFIED-K (https://macpaw.com/how-to/icloud-drive-taking-up-space, https://www.iphoneincanada.ca/2025/07/29/cleanmymac-now-helps-you-clean-up-your-cloud-storage-too/, https://chrischinchilla.com/blog/2026/cleaning-cloud-storage-with-cleanmymac/ via `01-overview.md` §5.2).
  - INFERRED reading: the vendor combines OAuth APIs (to see and delete cloud-only content and account quotas) with the local sync folders (to unsync). The exact split is not documented (GAP).
  - Fact-check refinement (INFERRED-strong): the help-center summary words the Google requirement as "Google Drive needs Google's desktop client" (`13-helpcenter.md` §5, from https://macpaw.com/how-to/icloud-drive-taking-up-space). That points to a **local-first** design. All four providers expose their *whole* namespace locally through File Provider or CloudDocs: in "stream" / online-only / Optimize-Storage mode, cloud-only files exist as **dataless placeholders** with a real logical size. A local walker therefore sees "cloud-only" files without any API. `unlink` deletes them in the cloud too, and eviction "unsyncs". This also explains iCloud "connect" without a public iCloud Drive API. "Only sees files from the official desktop client" then means: only what Drive for desktop mounts under `~/Library/CloudStorage/GoogleDrive-*` (My Drive and the Shared drives the client shows). It excludes items outside the mount, such as Google Photos, Gmail and "Computers" backups. OAuth, where used, most likely serves account identity and quota display. See §17.4.
- **Not part of Smart Care.** VERIFIED-K (`02-smart-care.md` §2). "Cloud Cleanup improvements" are listed as upcoming on What's New. VERIFIED-K.

### 10.2 Where the data lives on macOS 14–26 (INFERRED unless marked)

| Provider | Local root (current clients) | Mechanism |
|---|---|---|
| iCloud Drive | `~/Library/Mobile Documents/com~apple~CloudDocs` (+ per-app containers `~/Library/Mobile Documents/<team>~<bundle>`; Desktop & Documents when "Desktop & Documents Folders" sync is on) | CloudDocs (bird). Evicted files are APFS **dataless** in place. Across 223 containers / 373 evicted files on macOS 26 **zero** legacy `.name.icloud` stubs were found (VERIFIED-R PortOS) |
| Google Drive for desktop | `~/Library/CloudStorage/GoogleDrive-<account>/My Drive` (+ Shared drives) | File Provider. Content cache `~/Library/Application Support/Google/DriveFS/<id>/content_cache` (VERIFIED-OSS via `03-cleanup.md`, mac-cleanup-py) |
| OneDrive | `~/Library/CloudStorage/OneDrive-Personal` / `OneDrive-<Org>` | File Provider (Files On-Demand) |
| Dropbox | `~/Library/CloudStorage/Dropbox` (legacy `~/Dropbox` on old installs) | File Provider (online-only files are dataless) |
| Box, pCloud, etc. | `~/Library/CloudStorage/<Provider>-…` | File Provider |

Discover roots by enumerating `~/Library/CloudStorage` plus the iCloud path. Show friendly names from the folder prefix. Resolve symlinks: `~/Desktop` and `~/Documents` can live inside iCloud Drive (VERIFIED-R PortOS: resolve with `realpath`).

### 10.3 Item state detection

- **Foundation resource keys:**
  - `ubiquitousItemDownloadingStatusKey` → `.current` (local copy exists and is up to date), `.downloaded` (local copy exists but is stale), `.notDownloaded` ("has not been downloaded yet"). VERIFIED-APPLE.
  - Also `isUbiquitousItemKey`, `ubiquitousItemIsUploadedKey`, `ubiquitousItemIsUploadingKey`, `ubiquitousItemHasUnresolvedConflictsKey`, `ubiquitousItemIsDownloadingKey`. INFERRED from the SDK; verify that they populate for File Provider items on device.
- **Kernel flag:** `st_flags & SF_DATALESS` (0x40000000). VERIFIED-APPLE (xnu `stat.h`). `stat -f "%Sf"` shows `compressed,dataless` for evicted files. VERIFIED-R (PortOS).
- **Heuristic:** `size > 0 && blocks == 0`, **scoped to cloud roots**, because sparse or compressed files also show 0 blocks. VERIFIED-R (PortOS).
- **Syscall safety table** (macOS 26, APFS; VERIFIED-R https://raw.githubusercontent.com/atomantic/PortOS/main/server/lib/icloudFile.js):

| Syscall | Materializes (downloads)? |
|---|---|
| `stat`, `open` (read/append/rw without I/O), `rename`, `unlink` | **No** (unlink measured at about 0.1 ms) |
| `read`, `write` after `O_TRUNC`, append `write`, `link`, `clonefile` | **Yes** (~0.7–0.9 s per 5 MB; a read can block uncancellably) |

  Fact-check addition (VERIFIED-APPLE, TN3150 "Getting ready for dataless files", https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files):
  - Apple's canonical dataless test is exactly `stat`/`getattrlist` + `st_flags & SF_DATALESS`.
  - **But** `stat` and `getattrlist` "trigger the materialization of any intermediate folders in the file's path, if they themselves are dataless". Directory enumeration (`contentsOfDirectory` → `getattrlistbulk`) and even `fileExists(atPath:)` can materialize.
  - Opt-out primitive: `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD or IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)`. Accessing a dataless file then fails with **`EDEADLK`** instead of downloading. Restore the previous policy afterwards.
  - Symptoms of not handling it: hangs, `ETIMEDOUT`, watchdog kills.
  - This upgrades our "never read dataless files" rule from VERIFIED-R (PortOS) to VERIFIED-APPLE, and gives a *mechanical* guarantee instead of a convention.

  Our rules:
  - **Set the materialization-off iopolicy on every scanner, hasher and thumbnail thread** (scope thread, restored on exit), and treat `EDEADLK` as "cloud-only, skipped". Only the explicit "Download" action runs with materialization on.
  - Never `read`, hash, thumbnail or Quick Look a dataless file unless the user asks.
  - Deleting a dataless file is safe and fast.
  - Directory listing of a *dataless directory* asks the provider to enumerate it: "The next time the system accesses the directory, it requests a list of the contents" (VERIFIED-APPLE, `NSFileProviderManager.evictItem` discussion). Expect network latency, and show per-folder progress.

### 10.4 Actions and implementation ladder

| Our action (vendor analogue) | Implementation | Notes |
|---|---|---|
| **Remove local copy** ("Unsync") | 1) `FileManager.default.evictUbiquitousItem(at:)`. Apple: removes only the local version; don't wrap it in a coordinated write. VERIFIED-APPLE. 2) If that throws (PortOS saw `NSCocoaErrorDomain 512` from an unentitled process — VERIFIED-R), and the path is in iCloud Drive: run `/usr/bin/brctl evict <path>` **as the logged-in user** (it refuses as root; it isn't listed in `brctl --help` but works on macOS 26 — VERIFIED-R). 3) For File Provider roots: try (1). If unsupported, show a guided fallback that reveals in Finder and tells the user to choose the provider's "Remove Download" / "Free up space" / "Make online-only". (corrected) **`fileproviderctl evict` / `materialize` were removed in macOS 14.4** and are absent on 15 and 26 (VERIFIED-R: Apple Developer Forums thread 748036, "All these commands which is available in 13.6 have been removed with 14.4"; PortOS on macOS 26; FB13580772 reportedly closed "won't fix", second-hand). Older notes that show it working predate 14.4. Do not ship it. `NSFileProviderManager.evictItem` is for the provider's own app or extension only (VERIFIED-APPLE: "communicate with the file provider from either your app or your File Provider extension"). | Pre-check: uploaded, no unresolved conflicts, not open. Directory eviction is recursive, and fails on unsynced edits ("unsyncedEdits"), user-pinned items ("nonEvictable"), open FDs (EBUSY) or too many hard links (EMLINK) (VERIFIED-APPLE evictItem error list). Afterwards re-stat and confirm `SF_DATALESS` |
| **Delete everywhere** ("remove from Mac and cloud") | `FileManager.trashItem` (or `removeItem`) on the local path inside the sync root. The provider propagates the deletion. `unlink` doesn't download dataless content (VERIFIED-R) | Warn: removes it from all devices. Most providers keep a server-side trash/recycle bin for a while (INFERRED; varies by provider). Apple: deleting from iCloud via FileManager is permanent ("gone forever") (VERIFIED-APPLE evictUbiquitousItem discussion), so prefer `trashItem` to keep a local Trash copy where the provider allows |
| **Delete cloud-only item** | Same as above: the dataless entry is visible locally and unlinking it deletes it remotely | No download needed |
| **Download / keep offline** | `FileManager.startDownloadingUbiquitousItem(at:)` (VERIFIED-APPLE: named as the re-download path) / `brctl download <path>`. Exit 0 means "accepted/queued", so re-screen (VERIFIED-R) | Cap concurrent downloads (PortOS caps at 4) |
| **Space Map / Large files per provider** | Walk the provider root. For dataless files use `st_size` (logical size is reported, VERIFIED-R) as the "cloud size" and allocated size as the "local size". Two rings or colours: local vs cloud-only | Exclude provider caches from "local" totals, and show them separately as "Provider cache (review)" (`03-cleanup.md`) |
| **(Optional) Remote API mode** | Google Drive API `files.list` (size, md5Checksum, quotaBytesUsed); Microsoft Graph driveItem + `/delta`; Dropbox `files/list_folder` + `content_hash` | OAuth app registration needed. Enables cloud-side duplicate detection via provider hashes. **Out of scope for v1** (INFERRED). iCloud Drive has no public listing API, so it stays local only (INFERRED) |

**Safety rules (INFERRED):**

- (1) Never evict items with pending uploads or conflicts.
- (2) Never evict or delete inside app-private iCloud containers (other than CloudDocs) without an explicit per-container confirmation. Those can be app databases.
- (3) Treat packages (`.pages`, `.key`, `.numbers`, `.photoslibrary`, `.fcpbundle`) atomically.
- (4) Respect user-pinned / "keep downloaded" items. Detect via the nonEvictable error, or skip if the provider marks them (verify on device).
- (5) Never overwrite cloud files (§9.2).
- (6) Show the account free quota only when an API is connected; local mode shows local usage only.

### 10.5 Swift sketch: eviction with fallback (INFERRED)

```swift
import Foundation

enum EvictError: Error { case notCloud, notUploaded, conflicts, failed(String) }

func isDataless(_ url: URL) -> Bool {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return false }
    return (st.st_flags & UInt32(SF_DATALESS)) != 0          // 0x40000000, xnu bsd/sys/stat.h
}

func removeLocalCopy(_ url: URL, isICloudDrive: Bool) async throws {
    let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemIsUploadedKey,
                                     .ubiquitousItemHasUnresolvedConflictsKey]
    let v = try url.resourceValues(forKeys: keys)
    if v.ubiquitousItemHasUnresolvedConflicts == true { throw EvictError.conflicts }
    if v.isUbiquitousItem == true, v.ubiquitousItemIsUploaded == false { throw EvictError.notUploaded }
    do {
        try FileManager.default.evictUbiquitousItem(at: url)    // do NOT wrap in NSFileCoordinator write
    } catch where isICloudDrive {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/brctl")
        p.arguments = ["evict", url.path]                         // must run as the user, not root
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw EvictError.failed("brctl exit \(p.terminationStatus)") }
    }
    // Verify: may complete asynchronously → poll briefly.
    for _ in 0..<20 where !isDataless(url) { try await Task.sleep(for: .milliseconds(250)) }
    if !isDataless(url) { throw EvictError.failed("still materialized") }
}
```

---

## 11. Photo Junk (legacy) and Photos-related clutter

- **CMM3 categories** (VERIFIED-V topic-3 + strings):
  - **RAW Originals** (replace RAW with its JPEG; not selected by default; ignorable via "Ignore RAW photos");
  - **Faces Cache** (smart-selected);
  - **Photos Cache** (smart-selected; "Various cache files generated by Photos");
  - **iCloud Local Copies** ("Local copies of your iCloud photos"; restoring needs internet);
  - iPhoto-era originals of red-eye-fixed or rotated photos;
  - "\"%@\" Photo Cache" for **iOS photo sync caches**.
  - **Change Library**; "Reveal in Photos"; Quick Look shows RAW/JPEG side by side; zoom slider.
  - Trash Bins had **Photos Trash** (Recently Deleted) and "Gemini Duplicates". On High Sierra+ those had to be emptied **via Photos** ("Make sure you empty it via Photos to actually save space").
- **X:** a Cleanup module, not in the App Store edition. **5.x:** dropped (VERIFIED-K).
- **Our stance** (aligned with `03-cleanup.md` §5.22, rows F2/F3):
  - **Review-only, off by default:** cache trees inside the library package (`resources/caches/*`, `private/com.apple.photoanalysisd/caches/*`) and only when Photos is quit. Daemons may still hold them.
  - **Never:** originals, `database/`, iCloud local copies.
  - Instead deep-link to Photos › Settings › iCloud › **Optimize Mac Storage**, and show the library size in Space Map as an info node.
  - Photos "Recently Deleted" can't be emptied safely from the file system: show its size if detectable and deep-link (`03-cleanup.md` row in §5.23).
  - Similar/duplicate photos inside the library → PhotoKit flow (§6.5).

---

## 12. Shared architecture for these modules (INFERRED)

### 12.1 One index, many consumers

```
VolumeScanner (actor)  ── getattrlistbulk workers (≈8) ──►  NodeStore (struct-of-arrays, per root)
      │  FSEvents replay for incremental rescans                │
      ├──► SpaceMapModel (tree, top-N + Other, pseudo-nodes)    │
      ├──► LargeOldFinder (filter + Spotlight enrichment)        │
      ├──► DownloadsReviewer (quarantine / WhereFroms / ages)    │
      ├──► DuplicateFinder (size buckets → prehash → hash)  ◄──  HashCache (SQLite)
      └──► SimilarImageFinder (thumb → dHash → Vision verify) ◄─ PerceptualCache (SQLite)
```

- **FileKey** = `(volumeUUID, inode)`. Get the volume UUID from `URLResourceKey.volumeUUIDStringKey` once per device ID. It survives renames, and caches stay valid across moves.
- **Scan sessions** are cancellable `Task`s. Progress goes through an `AsyncStream` throttled to 4 Hz. All heavy work runs at `.utility` QoS. Hashing/IO uses `FileHandle` with `F_NOCACHE` so the user's page cache isn't evicted.
- **Persistence:**
  - `~/Library/Application Support/<App>/index/<volumeUUID>.bin` for the tree;
  - `hashes.sqlite` and `phash.sqlite` for fingerprints (WAL mode; vacuum monthly).
  - All of it is excluded from our own scans.

### 12.2 Data model sketch

```swift
struct FileKey: Hashable, Codable { let volume: UUID; let inode: UInt64 }

struct ItemFlags: OptionSet, Codable {
    let rawValue: UInt32
    static let directory  = ItemFlags(rawValue: 1 << 0)
    static let package    = ItemFlags(rawValue: 1 << 1)
    static let symlink    = ItemFlags(rawValue: 1 << 2)
    static let hardLink   = ItemFlags(rawValue: 1 << 3)
    static let clone      = ItemFlags(rawValue: 1 << 4)   // EF_MAY_SHARE_BLOCKS
    static let sparse     = ItemFlags(rawValue: 1 << 5)   // EF_IS_SPARSE
    static let dataless   = ItemFlags(rawValue: 1 << 6)   // SF_DATALESS
    static let cloudRoot  = ItemFlags(rawValue: 1 << 7)
    static let noAccess   = ItemFlags(rawValue: 1 << 8)
    static let protected_ = ItemFlags(rawValue: 1 << 9)
    static let mountPoint = ItemFlags(rawValue: 1 << 10)
    static let locked     = ItemFlags(rawValue: 1 << 11)  // UF_IMMUTABLE
}

enum RemovalMode { case trash, moveTo(URL), deleteNow, erase(overwrite: Bool), evictLocal, photosAlbum }

struct RemovalPlan {
    var items: [PlannedItem]          // url + FileKey + expected size/mtime + group id
    var mode: RemovalMode
    var groupsMustKeepOne: [UUID: Set<FileKey>]   // duplicate/similar invariants
}
```

### 12.3 Removal pipeline (all modules)

1. **Preflight** for each item:
   - re-`lstat`: inode, size and mtime must match the scan, else skip as "changed since scan";
   - protected-root check (§12.4);
   - ignore-list check;
   - open-file check;
   - group invariant (at least one survivor);
   - cloud rules (§10.4);
   - for `.trash` on a volume without a Trash (network, some external) → ask to delete permanently (Gemini did the same, VERIFIED-R).
2. **Execute:**
   - `FileManager.trashItem(at:resultingItemURL:)` → record `(original path, trashed URL)` for **Undo**. Finder's own "Put Back" may not work for app-trashed items; Gemini warned similarly (VERIFIED-R). That is why we keep our own log.
   - Root-owned items → helper (Eraser only).
   - Photos → PhotoKit / album.
3. **Measure:** compare `volumeAvailableCapacityForImportantUsage` before and after. Explain any gap (Trash not emptied, snapshots, clones). `03-cleanup.md` §4.7 uses the same approach.
4. **Log** to Activity (bytes, counts, module) for the dashboard (`01-overview.md` §11).

### 12.4 Protected roots (never selectable in Clutter, Space Map or Eraser)

`/`, `/System`, `/usr` (except `/usr/local` contents), `/bin`, `/sbin`, `/private/var/db`, `/private/var/vm`, `/Library` (root), `/Applications` (root), `/Users` (root), `~` (home root), `~/Library` (root), the standard home folders *themselves* (Desktop, Documents, Downloads, Movies, Music, Pictures, Public), volume roots and mount points, `*.photoslibrary` and `*.musiclibrary` packages (info rows only), `~/Library/Mobile Documents` and `~/Library/CloudStorage` (handled by Cloud Storage), and our own app bundle and data. Everything carrying `SF_RESTRICTED` or `com.apple.rootless` is also protected. Sibling `01-overview.md` §12 has the same list.

### 12.5 Permissions matrix

| Capability | Needed for | How to request / detect |
|---|---|---|
| Full Disk Access | Whole-disk Space Map, Large & Old across `~/Library`, Mail/Messages folders, other apps' containers | Probe-read a TCC canary (e.g. `~/Library/Safari/Bookmarks.plist`). Deep-link `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` |
| Files & Folders (Desktop / Documents / Downloads / removable / network) | Running without FDA | System prompts on first access. Handle denial gracefully |
| (new) File Provider data ("files managed by <provider>") | Walking `~/Library/CloudStorage/*` and iCloud Drive | TCC service `kTCCServiceFileProviderDomain` exists (VERIFIED-OSS: darling TCC headers; jamf aftermath maps it to "icloudDriveAccess"). Field reports say macOS prompts before an app first reads another provider's files, and a denial shows up as `EPERM`, which a naive walker reads as an empty folder (VERIFIED-R, broots144/gdrive-organizer notes). Treat `EPERM` under cloud roots as "not authorised", never as "empty". Whether FDA suppresses this prompt: **verify on device** |
| Photos (read/write) | Opt-in library scan, deletion, album creation | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` + `NSPhotoLibraryUsageDescription` |
| Admin helper (SMAppService daemon) | Eraser force-delete of root-owned items only | Install on first need; task-specific XPC API (`01-overview.md` §8, §12) |
| None (network) | Default build makes no network calls | Optional provider OAuth later |
| Privacy manifest | `volumeAvailableCapacity*` and file-timestamp APIs are required-reason APIs | `PrivacyInfo.xcprivacy` (VERIFIED-APPLE for the capacity keys) |

### 12.6 Settings (Clutter / Space Map / Cloud / Eraser)

- **Clutter:**
  - Large threshold (100 MB);
  - Old threshold (1 year);
  - Old minimum size (10 MB);
  - Include folders (off);
  - Duplicate minimum size (1 MB);
  - Include hidden files (off);
  - Exclusions (paths, globs, extensions; CMM3 had "File extensions to ignore:", VERIFIED-V);
  - "Always keep from" / "Always select from" folders;
  - Similarity (Strict / Standard / Loose);
  - Scan Photos library (off);
  - Treat RAW+JPEG and Live Photos as pairs (on).
- **Space Map:**
  - Size basis (On disk / Logical);
  - Show hidden files;
  - Bubbles shown per level (24);
  - View style (Bubbles / Tiles / Rings);
  - Remember scans and rescan incrementally (on);
  - Volumes to include (external, network).
- **Cloud Storage:**
  - Providers detected (toggle each);
  - Never evict files modified in the last N days (7);
  - Confirm before delete-everywhere (always).
- **Eraser:**
  - Default mode (Delete);
  - Allow overwrite mode (off);
  - Typed-confirmation threshold.

---

## 13. Naming and branding (INFERRED)

- **Don't use:** "My Clutter", "Space Lens", "Cloud Cleanup", "Smart Care", "Gemini", "Shredder" (as a product module name), "Large & Old Files" (as an exact title), MacPaw's bubble colour palette, planet/orb illustrations, sounds, or marketing lines.
- **Also don't reuse** replica strings such as "Building your storage map…" or "files to sort through". Write our own.
- **Suggested names:** **Clutter** (or "Declutter"); facets **Duplicates**, **Look-alikes** (similar photos), **Big & Forgotten** (large/old), **Downloads**; **Space Map**; **Cloud Storage**; **Eraser**. `01-overview.md` §13 already proposed "Space Map" and "Cloud Storage".

---

## 14. Verification checklist on the Mac mini (before shipping)

1. **Space Map scan:**
   - full `/` scan time and peak RAM with and without FDA;
   - compare the totals to `du -skx` per volume and to System Settings › Storage;
   - confirm firmlinked `/Users` is counted once.
2. **Clones:**
   - `cp -c big.mov clone.mov`;
   - confirm `EF_MAY_SHARE_BLOCKS` is set, `ATTR_CMNEXT_CLONEID` is equal and `PRIVATESIZE ≈ 0`;
   - confirm the duplicate finder groups them as "clone (no gain)".
3. **Hard links:** `ln a b` → counted once; duplicate finder shows "hard link".
4. **iCloud:**
   - evict via Finder "Remove Download" and confirm `SF_DATALESS`;
   - test `evictUbiquitousItem` from our signed (non-iCloud-entitled) app;
   - test `brctl evict` as the user;
   - confirm `unlink` of a dataless file doesn't download.
5. **File Provider (Google Drive / OneDrive / Dropbox):**
   - do the resource keys populate?
   - does `evictUbiquitousItem` work?
   - ~~does `fileproviderctl` have an `evict` verb on macOS 26?~~ (corrected) Resolved: removed since macOS 14.4 (§10.4). Instead, check the `kTCCServiceFileProviderDomain` prompt with and without FDA, and whether `EF_IS_SYNC_ROOT` is set on each `~/Library/CloudStorage/*` root;
   - with the materialization-off iopolicy set, confirm that walking a stream-mode Google Drive root returns `EDEADLK` (not a download) for dataless folders.
6. **Spotlight:** does `kMDItemLastUsedDate` update when opening via the app's Open panel vs double-click? Behaviour on external volumes with Spotlight disabled.
7. **Vision rev-2:** calibrate thresholds on 200 labelled pairs (bursts, crops, edits, screenshots).
8. **PhotoKit `deleteAssets`:** confirmation UI and Recently Deleted behaviour on macOS 26. Album creation path.
9. **Eraser:**
   - locked-file (`chflags uchg`) flow;
   - in-use file flow (open in Preview);
   - SIP path refusal;
   - the helper rejects symlink swaps (TOCTOU test).
10. **Trash:** external ExFAT volume Trash path; network share without Trash → permanent-delete prompt.

---

## 15. Gaps / open questions

Status after the fact-check pass (2026-10-12) is in brackets.

1. **Thresholds.** The vendor's exact default size and age thresholds for Large & Old Files in X and 5.x. Only CMM3 slider and bucket labels were found. [**Still open.** Replica consensus is 50 MB / 6 months (VERIFIED-R, §4.1), but that is not vendor evidence.]
2. **Duplicates.** The vendor's duplicate hash/algorithm, minimum file size, and which copy "Apply smart selection" keeps (`02-smart-care.md` gap #5 also). The Gemini 2 rules are only relayed. [**Still open.** No new vendor evidence was reachable.]
3. **Similar Images.** The algorithm, sensitivity setting (if any), and whether 5.x scans the Photos library via PhotoKit or only file-system images. [**Still open.** One replica (VaderCleaner `SimilarImageScanner.swift`) uses Vision feature prints and keeps the largest file, but that is not vendor evidence.]
4. **Downloads.** The exact 5.x facets (by source app? by kind?) and default selection. Replica evidence suggests source-app grouping. [**Partly.** The replica card is titled by dominant source, e.g. "Google Chrome Downloads" (VERIFIED-R). X added System Junk "Downloads" in 4.4.3 and Chrome downloads in 4.4.6 (VERIFIED-V).]
5. **Space Lens:**
   - whether X used pure circle packing or a hybrid; [open; "size-based bubble map" is VERIFIED-R]
   - whether it shows purgeable/"System Data" pseudo-nodes; [**partly resolved:** X had a "Purgeable Space popover" (4.4.3 notes, VERIFIED-V). No evidence for a "System Data" node.]
   - scan-speed claims; [vendor marketing only: "Visualize your disk space in a matter of seconds" (4.4.0 notes, VERIFIED-V). No figures.]
   - what size basis it uses (logical vs allocated). [**partly resolved:** since 4.15.4 it "ignores cloud-stored files" because they don't use local disk space (VERIFIED-V), so it measures local on-disk usage. Clone and hard-link handling are undocumented.]
6. **Cloud Cleanup:**
   - how iCloud "connect" works without a public iCloud Drive API (probably local only); [INFERRED-strong: local CloudDocs tree with dataless placeholders, §10.1 / §17.4]
   - what "Google Drive only sees files from Google's official desktop client" means technically; [INFERRED-strong: only what the Drive for desktop File Provider mount exposes, §10.1]
   - whether "unsync" uses `brctl`/FileManager or provider APIs; [open. `fileproviderctl evict` is ruled out since macOS 14.4; candidates are `evictUbiquitousItem`, private CloudDocs/FileProvider SPI, or the provider's own API]
   - ~~the Dropbox version (5.3.0 vs 5.3.1)~~ [**resolved (corrected): 5.3.0, 2025-12-17**, VERIFIED-V DevMate notes and appcast]
7. **Shredder in X.** Exact refusal list and whether overwrite was single-pass zeros (CMM3 says zeros) in X as well.
8. **Primary sources not reachable this session:**
   - MacPaw KB articles `space-lens`, `duplicate-files`, `free-up-more-space`, `cloud-cleanup` (if it exists);
   - the Gemini 2 manual PDF;
   - Behance/Dribbble design case studies (MacPaw UX awards: https://macpaw.com/news/cleanmymac-received-ux-design-awards).
   - Re-fetch these when web access is available.

---

## 16. Sources

**MacPaw primary (read this session)**

- CleanMyMac 3 Help book (MacPaw-authored), mirror at https://github.com/auspham/mac-essential :
  - topic-7 Large & Old Files — https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-7.html
  - topic-92 Shredder — …/English.lproj/topic-92.html
  - topic-3 Photo Junk — …/English.lproj/topic-3.html
  - topic-6 Trash Bins — …/English.lproj/topic-6.html
  - index — …/English.lproj/index.html
- CleanMyMac 3 shipped strings (same mirror, `CleanMyMac 3.app/Contents/Resources/`):
  - `Base.lproj/Localizable.strings`
  - `en.lproj/LargeOldFilesScanResultsView.strings`
  - `en.lproj/LargeOldFilesStartScanView.strings`
  - `en.lproj/EraserScanResultsView.strings`
  - `en.lproj/CMIgnoreListPreferencesViewController.strings`
  - `en.lproj/CMGeneralPreferencesViewController.strings`
- CleanMyMac 5 DevMate release notes (5.1.0 Space Lens; 5.2.1 Cloud Cleanup) — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html
- CleanMyMac X DevMate notes (no hits for these features in the 4.11–4.12 range) — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- (fact-check pass) More DevMate notes read:
  - CMM5 5.3.1 page, covering 5.0.x–5.3.1 incl. Dropbox in 5.3.0 — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
  - CMM5 appcast with build numbers and pubDates (ends at 5.3.1; the current feed moved to `updates.cleanmymac.com` per the Homebrew cask livecheck) — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml
  - X 4.3.1 page (4.2.0 Large & Old external drives, 4.3.0 Space Lens Beta) — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.3.1/releasenotes.html
  - X 4.4.6 page (4.4.0 out of beta, 4.4.3 Purgeable popover and Downloads cleanup, 4.4.4 mounted volumes, 4.4.6 Quick Look, Chrome downloads) — …/com.macpaw.CleanMyMac4/4.4.6/releasenotes.html
  - X 4.5.2 page — …/com.macpaw.CleanMyMac4/4.5.2/releasenotes.html
  - X 4.6.9 page (4.6.3 Move to Folder, 4.6.7 Shredder symlinks, 4.6.9 Users folder size) — …/com.macpaw.CleanMyMac4/4.6.9/releasenotes.html
  - X 4.15.8 page (4.15.4 cloud files ignored) — …/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html
  - X appcast — …/com.macpaw.CleanMyMac4/updates.xml
- Homebrew cask `cleanmymac` (5.7.1, build `50701.0.2609301754`, feed `updates.cleanmymac.com`) — https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb
- MacPaw CleanMyMac CLI:
  - https://github.com/MacPaw/cleanmymac-cli
  - wiki pages Commands, FAQ, "Analyze Disk Usage on macOS from Terminal"

**MacPaw KB / press (verified by sibling tracks; see `01-overview.md`, `02-smart-care.md`, `03-cleanup.md`)**

- https://macpaw.com/support/cleanmymac/knowledgebase/smart-care
- https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files
- https://macpaw.com/support/cleanmymac/knowledgebase/space-lens
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety
- https://macpaw.com/support/cleanmymac/knowledgebase/missing-features
- https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans
- https://macpaw.com/support/cleanmymac/knowledgebase/free-up-more-space
- https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk
- https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database
- https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features
- https://macpaw.com/news/cleanmymac-x-update-4.4.0
- https://macpaw.com/news/my-tools-cleanmymac
- https://macpaw.com/cleanmymac/whats-new
- https://macpaw.com/how-to/icloud-drive-taking-up-space
- https://macpaw.com/how-to/delete-junk-files-on-mac
- https://cleanmymac.com/blog/duplicate-file-finder-mac
- https://www.iphoneincanada.ca/2025/07/29/cleanmymac-now-helps-you-clean-up-your-cloud-storage-too/
- https://chrischinchilla.com/blog/2026/cleaning-cloud-storage-with-cleanmymac/
- https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716
- GitHub advisory list (read this session) — https://github.com/advisories?query=cleanmymac (CVE-2018-4032…4037, CVE-2019-5011)

**Apple (read this session)**

- `FileManager.evictUbiquitousItem(at:)` — https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:)
- `URLResourceKey.ubiquitousItemDownloadingStatusKey` / `URLUbiquitousItemDownloadingStatus` — https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus
- `NSFileProviderManager.evictItem(identifier:completionHandler:)` — https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager/evictitem(identifier:completionhandler:)
- `NSFileProviderItemCapabilities.allowsEvicting`
- `URLResourceKey.fileContentIdentifierKey`, `.mayShareFileContentKey`, `.totalFileAllocatedSizeKey`, `.contentAccessDateKey`, `.volumeAvailableCapacityForOpportunisticUsageKey`
- `kMDItemLastUsedDate`, `kMDItemDateAdded` — https://developer.apple.com/documentation/coreservices/kmditemlastuseddate
- Vision `VNGenerateImageFeaturePrintRequest`, `VNGenerateImageFeaturePrintRequestRevision2`, `VNFeaturePrintObservation.computeDistance(_:to:)`
- Photos `PHAssetChangeRequest.deleteAssets(_:)` — https://developer.apple.com/documentation/photos/phassetchangerequest/deleteassets(_:)
- xnu sources:
  - `bsd/man/man2/getattrlistbulk.2`
  - `bsd/man/man2/getattrlist.2` (ATTR_CMNEXT_PRIVATESIZE, CLONEID, EXT_FLAGS, CLONE_REFCNT, ALLOCSIZE, TOTALSIZE)
  - `bsd/sys/attr.h`
  - `bsd/sys/stat.h` (SF_DATALESS)
  - repo: https://github.com/apple-oss-distributions/xnu
- file_cmds `rm/rm.1` (`-P` has no effect) — https://raw.githubusercontent.com/apple-oss-distributions/file_cmds/main/rm/rm.1
- (fact-check pass) Further Apple sources:
  - file_cmds `du/du.1` (hard links and directory hard links counted once; `-A` apparent size) — https://raw.githubusercontent.com/apple-oss-distributions/file_cmds/main/du/du.1
  - TN3150 "Getting ready for dataless files" — https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files
  - `PHPhotoLibrary.performChanges(_:completionHandler:)` — https://developer.apple.com/documentation/photos/phphotolibrary/performchanges(_:completionhandler:)
  - `PHAssetChangeRequest` — https://developer.apple.com/documentation/photos/phassetchangerequest
  - `NSFileProviderManager` — https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager
  - `GenerateImageFeaturePrintRequest` (macOS 15) — https://developer.apple.com/documentation/vision/generateimagefeatureprintrequest
  - `URLUbiquitousItemDownloadingStatus.current/.downloaded/.notDownloaded` — https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus
  - Apple Developer Forums thread 748036 (fileproviderctl verbs removed in 14.4; user posts, not Apple staff) — https://developer.apple.com/forums/thread/748036
  - xnu `bsd/sys/attr.h` (`FSOPT_ATTR_CMN_EXTENDED`, `ATTR_DIR_MOUNTSTATUS`, `DIR_MNTSTATUS_*`, `EF_*`), `bsd/sys/stat.h` (`SF_FIRMLINK`, `SF_DATALESS`), `bsd/man/man2/getattrlistbulk.2` (mount-point and firmlink semantics)

**Open source and secondary (read this session)**

- czkawka:
  - https://github.com/qarmin/czkawka
  - `instructions/Instruction.md`, `instructions/Instruction_Core.md`
  - `czkawka_core/src/tools/similar_images/mod.rs`, `czkawka_core/src/tools/duplicate/core.rs`
- dupeGuru:
  - https://github.com/arsenetar/dupeguru
  - `help/en/scan.rst`, `help/en/results.rst`, `help/en/reprioritize.rst`, `core/prioritize.py`
- d3-hierarchy: `src/pack/siblings.js`, `src/treemap/squarify.js` — https://github.com/d3/d3-hierarchy
- GrandPerspective — https://grandperspectiv.sourceforge.net/
- SquirrelDisk — https://github.com/adileo/squirreldisk
- dust — https://github.com/bootandy/dust
- OpenDisk — https://github.com/137137137/OpenDisk
- Radix — https://github.com/colinvkim/Radix
- Ferail `crates/ferail-fs-native/src/disk_usage_scanner.rs` — https://github.com/jonx/Ferail
- diskhound `src/shared/macStorageAccounting.ts` — https://github.com/tzarebczan/diskhound
- PortOS iCloud dataless research `server/lib/icloudFile.js` and `.changelog/v2.41.0.md` — https://github.com/atomantic/PortOS
- Mole (`mo analyze`) — https://github.com/tw93/Mole
- Gemini 2 / fclones / jdupes relay — https://github.com/ayhid/twins/blob/main/.planning/research/FEATURES.md
- Replica apps (secondary evidence of vendor UI; wording not to be reused):
  - VaderCleaner — https://github.com/jayvicsanantonio/VaderCleaner (`MyClutterDashboardView.swift`, `MyClutterManagerView.swift`, `MyClutterSelectionSeed.swift`, (corrected path) `VaderCleanerCore/Sources/VaderCleanerCore/DownloadsScanner.swift` + `DownloadSourceResolver.swift`, `SimilarImageScanner.swift`, `en.lproj/Localizable.strings`)
  - PristineCleaner — https://github.com/RabinApps/PristineCleaner (`assets/translations/en.i18n.json`)
  - MacOptimizer — https://github.com/ddlmanus/MacOptimizer (`AppUninstaller/SpaceLensView.swift`)
  - MClean — https://github.com/maclifevn/MClean (`MClean/Views/SpaceLens/BubbleMapView.swift`)
- Vision rev-2 notes:
  - https://github.com/omnifroodle/fieldproof (`docs/REFERENCE.md`)
  - https://github.com/hsuBnOediH/photo-filter (`Sources/PhotoFilter/SimilarityEngine.swift`)
- `brctl` / `fileproviderctl` usage corpus (GitHub code search):
  - https://github.com/AlphaGit/tech-garden
  - https://github.com/wyattowalsh/agents
  - https://github.com/charlie0129/dotfiles
- (fact-check pass) More secondary sources:
  - broots144/gdrive-organizer `docs/macos-fileprovider-notes.md` (fileproviderctl removal, TN3150 iopolicy, Drive shortcuts, `.gdoc` pointers, File Provider TCC prompt) — https://github.com/broots144/gdrive-organizer
  - HuakunShen/space-lens `apps/web/UX_RESEARCH.md` (summaries of the X Space Lens and 5.x Large & Old KB articles) — https://github.com/HuakunShen/space-lens
  - kali-physi-hacker/veyra `docs/product-research.md` (summary of the 5.x Space Lens results KB) — https://github.com/kali-physi-hacker/veyra
  - `com.apple.lastuseddate#PS` usage: iina `iina/PlayerCore.swift` (https://github.com/iina/iina), VLC `modules/gui/macosx/playqueue/VLCPlayQueueController.m` (https://github.com/videolan/vlc), exiftool `lib/Image/ExifTool/MacOS.pm` (https://github.com/exiftool/exiftool)
  - `kTCCServiceFileProviderDomain`: darling `src/private-frameworks/TCC/include/TCC/TCC.h` (https://github.com/darlinghq/darling); jamf aftermath `analysis/DatabaseParser.swift` (https://github.com/jamf/aftermath)
  - Replica thresholds: iliyami/MacSai, mich312/DiskBuddy, ViniciusDeep/MacCleaner (GitHub code search "Large & Old Files" "50 MB")

---

## 17. Fact-check additions: items the original report missed

These additions come from the adversarial fact-check pass on 2026-10-12. Labels follow §0. Section numbers point to the in-place edits made elsewhere.

### 17.1 Space Lens / Space Map details

- **Vendor timeline (VERIFIED-V, DevMate X notes):** Beta in 4.3.0 → GA in 4.4.0 → Purgeable Space popover (crash fix in 4.4.3) → mounted-volume exclusion fix (4.4.4) → Quick Look on double-click (4.4.6) → Users-folder size fix (4.6.9) → cloud-stored files ignored (4.15.4, 2024-06-19) → absent in 5.0 → "reimagined" bubble map in 5.1.0 (2025-06-12) → reused for cloud drives in 5.2.1. Details and URLs in §8.1.
- **Design implications (INFERRED, from the timeline):**
  1. Show **purgeable space** as its own node or popover at the volume root. The vendor did from 4.4.x.
  2. Stop at mount points, and treat firmlinked `/Users` as one tree. The vendor shipped fixes for both bug classes.
  3. Size bubbles by **local on-disk usage** and leave cloud-only (dataless) items out of local totals. The vendor did from 4.15.4.
  4. Keep a separate **Review Selected** step between selecting in the map and removing (VERIFIED-R, X and 5.x KB summaries).
  5. Double-click = Quick Look.
- **Visual form:**
  - X: "size-based bubble map" + full list, hover-linked (VERIFIED-R).
  - 5.1+: "folders as bubbles arranged from largest to smallest" (VERIFIED-V).
  - Neither is a treemap or a sunburst. Our circle-packing choice (§8.3) stands. Offer treemap/sunburst only as optional views.
- **Clone over-count in totals (INFERRED, from VERIFIED-APPLE semantics).** `ATTR_FILE_ALLOCSIZE` counts each clone's blocks in full, so the per-folder sum over-reports when APFS clones exist. Either:
  - (a) label folder totals as "on disk (clones counted per file)" and show "unique ≈ Σ PRIVATESIZE" in the inspector; or
  - (b) dedupe by `ATTR_CMNEXT_CLONEID` for files with `EF_SHARES_ALL_BLOCKS` (full clones share one clone-id), counting one copy per clone-id per scan. Partial clones (`EF_MAY_SHARE_BLOCKS` without `SHARES_ALL`) can't be deduped exactly. Report them as "may share data".
- **Fast directory sizing hint (INFERRED).** xnu mentions APFS "extended directory statistics, for fast directory sizing" under `VOL_CAP_FMT_CLONE_MAPPING`, plus `ATTR_CMNEXT_RECURSIVE_GENCOUNT` for maintain-dir-stats directories (VERIFIED-APPLE, `attr.h` / `getattrlist.2`). No public API to *enable* dir-stats was found. Use the gencount, where non-zero, only as a cheap "unchanged since last scan" check for incremental rescans.
- **"System Data".** No vendor evidence that Space Lens shows a "System Data" node. Our pseudo-node design (§8.4) is original and honest: it is labelled as an estimate and shrinks with FDA.
- **Scan speed.** Vendor claim is marketing only: "Visualize your disk space in a matter of seconds" (4.4.0, VERIFIED-V). Budget for ours: a warm full scan of a 1 TB internal SSD in under 30 s with FDA. OpenDisk reports 17 s cold (VERIFIED-OSS, its own benchmark). **(verify on device)**

### 17.2 Dataless-file safety as a mechanism, not a convention (VERIFIED-APPLE: TN3150, xnu `resource.h`)

- Constants (xnu `bsd/sys/resource.h`):
  - `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES = 3`; `IOPOL_MATERIALIZE_DATALESS_FILES_OFF = 1` (`_DEFAULT = 0`, `_ON = 2`);
  - `IOPOL_SCOPE_PROCESS = 0`, `IOPOL_SCOPE_THREAD = 1`;
  - also `IOPOL_TYPE_VFS_ATIME_UPDATES = 2` with `IOPOL_ATIME_UPDATES_OFF = 1`.
- **Use the atime policy too.** Hashing every candidate otherwise rewrites `atime` on volumes that track it, which destroys the weak "last accessed" signal (§4.2) for every file we compared. INFERRED (the effect follows from the constant's name; verify that APFS honours it).
- **Swift concurrency caveat (INFERRED).** A thread-scoped policy does not follow a Swift `Task` across suspension points, because tasks hop threads. Run hashing, thumbnailing and bulk enumeration on a **dedicated `Thread` / serial `DispatchQueue` with no `await` inside the protected region**. Better still, run the scanner in a separate XPC service and use `IOPOL_SCOPE_PROCESS` once at launch.

```swift
import Darwin

/// Runs `body` on the current thread with cloud downloads and atime updates disabled.
/// Accessing a dataless file inside `body` fails with EDEADLK instead of downloading it (TN3150).
func withoutMaterialization<T>(_ body: () throws -> T) rethrows -> T {
    let mType = IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, aType = IOPOL_TYPE_VFS_ATIME_UPDATES
    let prevM = getiopolicy_np(mType, IOPOL_SCOPE_THREAD)
    let prevA = getiopolicy_np(aType, IOPOL_SCOPE_THREAD)
    _ = setiopolicy_np(mType, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    _ = setiopolicy_np(aType, IOPOL_SCOPE_THREAD, IOPOL_ATIME_UPDATES_OFF)
    defer {
        if prevM >= 0 { _ = setiopolicy_np(mType, IOPOL_SCOPE_THREAD, prevM) }
        if prevA >= 0 { _ = setiopolicy_np(aType, IOPOL_SCOPE_THREAD, prevA) }
    }
    return try body()   // treat errno == EDEADLK as "cloud-only, skipped"
}
```

### 17.3 Large & Old Files and Downloads signals

- **`com.apple.lastuseddate#PS`** is the on-file copy of "last opened" (§4.2). It is readable without Spotlight. Some apps write it themselves (IINA, VLC). VERIFIED-OSS.
- **`com.apple.metadata:kMDItemDownloadedDate`** and the quarantine timestamp give the download time (§7.1/7.2). VERIFIED-OSS (exiftool).
- **`kMDItemDateAdded`** resets on move (INFERRED from its meaning, "date added to folder"). Don't use it alone for "how long has this download sat here".
- **Replica default thresholds:** 50 MB / 6 months (VERIFIED-R). Vendor defaults remain unknown (§15).
- **Vendor X history:** external-drive support for Large & Old in 4.2.0; "Move to Folder" in 4.6.3 (VERIFIED-V). Our "Move to Folder…" action (§3.3) matches.

### 17.4 Cloud Cleanup mechanics (best current model)

- **Local-first model (INFERRED-strong, §10.1).**
  - iCloud Drive (`~/Library/Mobile Documents`), Google Drive for desktop, OneDrive and Dropbox (`~/Library/CloudStorage/*`) all expose the full cloud namespace locally.
  - Cloud-only items are **dataless** entries with a real logical size (`st_size`) and zero allocated blocks.
  - So a local walker can list "cloud-only files", size them for a cloud Space Map, and delete them: `unlink` doesn't download, and the provider propagates the delete.
  - That covers three of the four vendor actions ("delete cloud files directly", "remove synced files from Mac and cloud", Space Lens/Large Files for the cloud) with no provider API.
  - The fourth, "unsync", is eviction: `evictUbiquitousItem`, `brctl evict` for iCloud, or Finder's "Remove Download".
- **Google Drive specifics** (VERIFIED-R via broots144 notes, citing Google support pages):
  - Drive **shortcuts** appear as aliases/symlinks, with targets under a hidden `shortcut-targets-by-id` folder. Exclude that folder from totals, or files are counted twice.
  - Google Docs/Sheets/Slides are small `.gdoc`/`.gsheet`/`.gslides` pointer files. Never treat them as "tiny documents to clean", and never copy them.
  - Duplicate names in one Drive folder show up locally with a " (1)" suffix. Don't let the duplicate finder's "clean filename" rule (§5.3) treat these as copies without a content match.
  - Drive for desktop has a **Lost & Found** for failed syncs.
- **TCC:** reading another provider's files can trigger the `kTCCServiceFileProviderDomain` prompt. Denial shows up as `EPERM` (§12.5). **(verify on device)**
- **Eviction tooling on macOS 14.4+:** `fileproviderctl evict` is gone. `brctl evict` works for iCloud as the user (VERIFIED-R). `chflags dataless` silently does nothing (VERIFIED-R, PortOS).

### 17.5 Photos

- CMM3 removed iCloud Photos items "from both iCloud and local Photos library" per its Help, as well as using a "Large Media to Delete" album (§4.1, corrected nuance). We still never touch library files directly. Use PhotoKit delete in **one** change block, or the album hand-off (§6.5).

---

## Verification notes

**Method and access in this pass.**

- WebSearch was unavailable: the shared per-turn budget was exhausted ("limit: 200 WebSearch calls per turn"), so **0 searches ran**.
- WebFetch and curl could not reach macpaw.com, cleanmymac.com, updates.cleanmymac.com, apps.apple.com, setapp.com, Macworld, TidBITS, support.apple.com, web.archive.org, Reddit, 9to5Mac, MacRumors, Talos, Objective-See or DaisyDisk (DNS failure or proxy 403).
- Reachable and used:
  - MacPaw's DevMate S3 bucket: CMM5 and CMM X release notes and appcasts, about 14 pages;
  - developer.apple.com: documentation JSON for about 25 symbols, TN3150 and forum thread 748036;
  - apple-oss-distributions: xnu `attr.h`, `stat.h`, `resource.h`, `fcntl.h`, `getattrlist.2`, `getattrlistbulk.2`; file_cmds `rm.1`, `du.1`;
  - raw.githubusercontent.com: CMM3 Help and strings mirror, czkawka, PortOS, MacPaw CLI README, the twins/Gemini relay, the Homebrew cask, third-party KB summaries;
  - GitHub code search: 7 queries.

**Claims checked (≈ 28) and outcome.**

| # | Claim | Result |
|---|---|---|
| 1 | Space Lens returned in 5.1.0, "folders as bubbles arranged from largest to smallest" | **Confirmed** (VERIFIED-V; appcast pubDate 2025-06-12) |
| 2 | Cloud Cleanup in 5.2.1: iCloud Drive / Google Drive / OneDrive; delete cloud-only / remove Mac+cloud / unsync; Space Lens + Large Files for cloud | **Confirmed** (VERIFIED-V). Date nuance: DevMate pubDate 2025-07-28 15:59 UTC vs. the 07-29 announcement |
| 3 | Dropbox in 5.3.0 vs 5.3.1 | **Resolved → 5.3.0 (2025-12-17)**, corrected in §2 and §10.1 |
| 4 | Space Lens "introduced in X; left beta in 4.4.0" | **Confirmed and made precise:** Beta in 4.3.0, GA in 4.4.0 (corrected in §2) |
| 5 | X Space Lens visual form ("bubble chart", INFERRED-strong) | **Upgraded to VERIFIED-R** ("size-based bubble map" in the X KB summary). Pure circle packing still unverified |
| 6 | Space Lens purgeable / size basis unknown | **Partly resolved:** Purgeable popover (4.4.3); cloud files ignored, local usage only (4.15.4) |
| 7 | `fileproviderctl evict` "conflicting; verify on device" | **Corrected:** removed in macOS 14.4 (§1, §10.4, §14) |
| 8 | Mount points detected by `st_dev` change during the `getattrlistbulk` walk | **Corrected:** bulk returns the underlying directory's attributes, so use `ATTR_DIR_MOUNTSTATUS`; added `SF_FIRMLINK`, `DIR_MNTSTATUS_TRIGGER` and the volume-group devid caveat (§1, §8.4, §8.5) |
| 9 | `FSOPT_ATTR_CMN_EXTENDED` "should be confirmed" | **Confirmed** (0x20; accepted by `getattrlistbulk`) |
| 10 | `ATTR_CMNEXT_PRIVATESIZE` / `CLONEID` / `EXT_FLAGS` / `CLONE_REFCNT` semantics; `SF_DATALESS` = 0x40000000 | **Confirmed**; added `EF_SHARES_ALL_BLOCKS`, `EF_IS_PURGEABLE`, `EF_IS_SYNC_ROOT`, `EF_NO_XATTRS` |
| 11 | Hamming ≤ 10 on a 64-bit dHash ≈ czkawka "High/Medium" | **Corrected:** between "Small" (7) and "Very Small" (14); MIH probing radius fixed (§6.3) |
| 12 | dHash Swift sketch | **Corrected:** dangling-pointer bug in `CGContext(data: &px …)` (§6.4) |
| 13 | czkawka prehash = first + last 4 KB; `SIMILAR_VALUES` table; 257,144-byte cache minimum | **Confirmed** (VERIFIED-OSS). Note: 257,144 is czkawka's *prehash* cache minimum |
| 14 | `kMDItemLastUsedDate` updated by LaunchServices on double-click / LS open; `kMDItemDateAdded` since 10.7 | **Confirmed**; added the `com.apple.lastuseddate#PS` xattr |
| 15 | `VNGenerateImageFeaturePrintRequestRevision2` from macOS 14.0 | **Confirmed**; added the Swift `GenerateImageFeaturePrintRequest` (macOS 15) |
| 16 | `deleteAssets(_:)` must be called in a change block; system confirmation on macOS | API **confirmed**. Apple's alert note names **iOS** only, so macOS stays *verify on device*; advice: one change block |
| 17 | `evictUbiquitousItem` semantics (no coordinated write; local copy only; FileManager delete is permanent) | **Confirmed** |
| 18 | `URLUbiquitousItemDownloadingStatus` `.current` / `.downloaded` / `.notDownloaded` meanings | **Confirmed** |
| 19 | `NSFileProviderManager.evictItem` error list | **Confirmed**; added that the manager is for the provider's own app/extension only |
| 20 | "Never read dataless files" (VERIFIED-R) | **Upgraded to VERIFIED-APPLE** (TN3150) and turned into a mechanism (iopolicy, §17.2) |
| 21 | `fileContentIdentifierKey` clone semantics, macOS 11+; `totalFileAllocatedSizeKey` includes metadata; `contentAccessDateKey` nil if unsupported; capacity keys are required-reason APIs | **Confirmed** |
| 22 | `rm -P` has no effect; Secure Empty Trash gone in 10.11 | **Confirmed** (file_cmds `rm.1`; CMM3 topic-7 text) |
| 23 | Hard links counted once | **Confirmed**, and extended to directory hard links (Apple `du.1`) |
| 24 | CMM3 Large & Old strings (groups, slider stops, "Large Media to Delete", no smart-selection) | **Confirmed**; added the nuance that CMM3 Help says iCloud Photos items were removed from iCloud and the local library (§4.1) |
| 25 | Gemini 2 relay (keeper filters, Always/Never Select, Remove Last Instance, album, monitor) | **Confirmed present in the relay** (still VERIFIED-R; the PDF itself is unreachable); added Gemini extras (§5.1) |
| 26 | MacPaw CLI `analyze` (header "X GB of Y GB free", "Other (N items)", O = Reveal, read-only browse) | **Confirmed** (README) |
| 27 | VaderCleaner Downloads by source app | **Confirmed**; file path corrected |
| 28 | Current version 5.7.1 (table header) | **Consistent:** the Homebrew cask is 5.7.1 / `50701.0.2609301754`. The DevMate appcast stops at 5.3.1 because the feed moved to `updates.cleanmymac.com` |

**Downgrades.** None of the existing VERIFIED tags were found false. The VERIFIED-K items (macpaw.com KB via siblings) could not be re-fetched, so they keep their K label, which already means "not re-fetched here". No claim needed downgrading to INFERRED. Claims that remain INFERRED stay so marked (e.g. the Photos › Utilities › Duplicates path, FDA versus the File Provider TCC prompt, the Vision thresholds).

**Still uncertain / open after this pass.**

1. Vendor defaults for Large & Old size and age thresholds (X, 5.x).
2. The 5.x duplicate algorithm, its minimum size, and which copy "Apply smart selection" keeps.
3. The 5.x Similar Images algorithm and sensitivity, and whether it uses PhotoKit.
4. The exact 5.x Downloads facets and default selection.
5. Whether X/5.x Space Lens used pure circle packing; its clone and hard-link accounting; any "System Data" node.
6. The mechanism behind 5.x "unsync" (public `evictUbiquitousItem`, private SPI, or provider APIs) and what OAuth is used for.
7. On-device checks:
   - `evictUbiquitousItem` on File Provider roots from an unentitled app;
   - the `brctl evict` behaviour on macOS 26;
   - the PhotoKit delete prompt on macOS;
   - `IOPOL_ATIME_UPDATES_OFF` on APFS;
   - the File Provider TCC prompt with and without FDA;
   - Vision rev-2 threshold calibration.
8. The Gemini 2 manual PDF, the MacPaw KB pages, and the Behance/Dribbble case studies remain unreachable from this environment. Re-fetch them when web access returns.
