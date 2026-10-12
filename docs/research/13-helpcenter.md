# 13 — MacPaw Help Center Deep Crawl: per-article implementation facts

> **Track:** a systematic digest of MacPaw's CleanMyMac help material: the online knowledge base for the 2024+ "CleanMyMac" (5.x), the CleanMyMac X knowledge base, the Business and legacy KBs, MacPaw "how-to" articles, the **in-app Help Book** MacPaw shipped inside CleanMyMac 3, the CleanMyMac **CLI wiki** (MacPaw's newest first-party docs), and the package metadata that documents the uninstall footprint.
> **Goal:** give the build team one place that answers "what does the vendor's help say this feature does, and what exact behaviour/label/path/permission follows from that", one section per article.
> **Target:** our own original app (not named CleanMyMac) for an Apple-Silicon Mac mini on macOS 14 Sonoma, 15 Sequoia, 26 Tahoe (and 27 where relevant).
> **Date of research:** 2026-10-12.

---

## 0. Method, access limits, labels

### 0.1 What happened during this crawl (read this first)

- **`macpaw.com` was not reachable from this session.** WebFetch failed with a DNS error (`getaddrinfo ENOTFOUND macpaw.com`), and `curl` through the agent proxy got `CONNECT tunnel failed, response 403` (organisation egress policy). Per the proxy rules this block was reported, not routed around. Archive and reader services were not used to get past it.
- **The shared WebSearch budget for the workflow was already used up** when this track started ("limit: 200 WebSearch calls per turn, shared by every agent"). This track could not run a single new search.
- So a live crawl of `macpaw.com/support/...` was impossible. To still produce a per-article digest I combined four kinds of evidence. Every bullet says which kind it is:
  1. **MacPaw-authored help material I fetched and read myself** from GitHub:
     - the complete **CleanMyMac 3 in-app Help Book**: all 16 articles, from a public mirror of the app bundle;
     - the CMM3 **Preferences, Alerts and Localizable `.strings`** files from the same bundle;
     - MacPaw's own **`MacPaw/cleanmymac-cli` README and wiki**, which is MacPaw's current help centre for the CLI;
     - MacPaw's **Sparkle appcast** for 5.x on the DevMate S3 bucket.
  2. **Package metadata I fetched myself**, which documents the install and uninstall footprint: the Homebrew casks `cleanmymac` (5.7.1), `cleanmymac-zh` (X Chinese 4.15.14) and `cleanmymac-cli`, a community `cleanmymac-x` (4.15.8) cask, and Fleet's maintained uninstall script.
  3. **Online KB articles that sibling research tracks were able to read** before the block and budget ran out. They read them through search-engine extraction of those exact URLs (method described in `01-overview.md` §0). I consolidated every such article and fact from reports 01–12 and re-organised them per article. I could **not** re-fetch them.
  4. A few **third-party observations** of the same KB pages or of real installs (GitHub-hosted notes, dotfiles, blog posts).
- **Fact-check pass (same date).** A second agent re-checked the most implementation-critical claims and corrected them in place; corrected items are marked **(corrected)**. It hit the same blocks: `macpaw.com`, `updates.cleanmymac.com` and `updates.devmate.com` refused, WebSearch budget used up. It could reach `raw.githubusercontent.com`, GitHub code search, Apple's documentation JSON (`developer.apple.com/tutorials/data/...`) and the DevMate S3 appcasts. What it checked, corrected and could not settle is in the final section, "Verification notes".

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED-D** | I fetched and read the cited source directly in this session (URL given). |
| **VERIFIED-KB** | A fact from the cited **MacPaw help-centre URL**, verified by a sibling track (report number given). I did not re-fetch it, because macpaw.com was blocked. |
| **VERIFIED-3P** | A third party's description or observation (URL given). It is secondary, so weigh it accordingly. |
| **INFERRED** | Our reasoning, or a recommendation for our implementation. |

**Paraphrase policy:** vendor help text is paraphrased. Only short UI labels and setting names are quoted, because the implementation needs them exact. None of this wording should be copied into our UI (see §12).

---

## 1. Executive summary: the 20 help-centre facts that most constrain our build

1. **Every module follows the same help-documented loop:** Scan → summary with pre-selected recommendations → **Review** → **Run/Clean/Remove**, plus a **Start Over** to rescan. This is documented for Smart Care, every CMM3 module, and the CLI's "Scan → Review → Confirm".
   - VERIFIED-KB (smart-care, via 02).
   - VERIFIED-D (CMM3 Help topics 1–9; CLI README).
2. **Smart Care scope is deliberately narrow.** It covers junk, mail attachments and trash; a **Quick** malware scan; maintenance scripts plus Flush DNS; app updates excluding system apps and macOS; and duplicates in **~/Downloads only**. Everything is selected by default. Excluded modules show as dimmed tiles. VERIFIED-KB (smart-care, via 02).
3. **Safety contract (every generation):** a built-in **Safety Database** keeps vital items from being selected by default. User files are never removed unless the user picks them.
   - VERIFIED-D (CMM3 topics 1, 2).
   - VERIFIED-KB (cleanmymac-safety, safety-database, via 01/02).
4. **Large & Old Files, Uninstaller and Extensions never pre-select anything.** Trash Bins and Mail Attachments pre-select everything that is recoverable. VERIFIED-D (CMM3 topics 4, 6, 7, 8, 91).
5. **Documented smart-selection rules:**
   - Document Versions: never the earliest or the latest; only versions made less than 4 h apart, keeping the latest in each range.
   - iOS backups: never the latest.
   - Mail attachments: only unmodified ones (marked "changed by user" otherwise).
   - Photo Junk: only Photos Cache and Faces Cache.
   - Xcode: never Module Cache or Archives automatically.
   - Leftovers: never pre-selected.
   - VERIFIED-D (CMM3 topics 2, 3, 4, 5); VERIFIED-KB (X system-junk, DE mail-attachments, via 02).
6. **5.x System Junk exceptions:** Spotify and Gradle caches are not auto-selected (cache holds real data). VERIFIED-KB (5.x system-junk excerpt, via 03); VERIFIED-KB (X safety-database: Spotify offline music, via 02).
7. **Ignore List** = items never shown in results. Adding works via a Control-click on any result, then **Add to Ignore List**.
   - 5.x categories: Cleanup (System Junk, Mail Attachments), Protection (Malware Removal), Applications (Uninstaller, Updater), My Clutter (Duplicates, Similar Images, Downloads).
   - System apps are pre-ignored.
   - CMM3 adds: "All changes take effect after a new scan", "Reset Selected Ignore List", "Reset All Ignore Lists", a conflict check against the Safety Database, and a warning when an ignored item is selected for removal.
   - VERIFIED-KB (cleanmymac-safety, via 01/02); VERIFIED-D (CMM3 strings).
8. **Full Disk Access (FDA) is why scans are complete.**
   - Without it the app can't scan all junk or malware locations, can't malware-scan email attachments, and the Health monitor lacks disk data.
   - The KB tells users to **run a scan first** so the app's components register in the FDA list, then toggle them on.
   - The Assistant offers an **Allow Access** shortcut.
   - VERIFIED-KB (full-disk-access 5.x and X; protection-scan-options; via 01/02).
9. **Five background pieces**, each with its own help article:
   - **Menu** (background item);
   - **Health Monitor** (background item; drives alerts, the real-time malware monitor and background scans);
   - **Agent** (privileged helper tool, not a background item; installed lazily on the first root task after an admin password prompt; idle unless needed);
   - **Updater** (self-update);
   - **(corrected)** an Endpoint-Security system extension for Moonlock (`com.macpaw.moonlock.engine`) is **not** a confirmed 5.x component. The Homebrew cask and Fleet's script (re-fetched) list no system extension. One process capture shows it running beside CMM5. A later full capture of a CMM5 Mac shows no such extension. It may belong to MacPaw's standalone Moonlock app. INFERRED / unresolved (see §9.1, 04 §1.6, 10 §2.1).
   - VERIFIED-KB (background-items, cleanmymac-processes, cleanmymac-agent, cleanmymac-helper-tool, via 01/10); VERIFIED-D (casks, for Menu, Health Monitor, Agent and Updater only).
10. **If "Allow in the Background" is off**, the Menu won't open and the Settings toggle does nothing. VERIFIED-KB (allow-background-items, via 01/08).
11. **Complete-uninstall footprint (5.x).** All paths VERIFIED-D (cask; Fleet script; both re-fetched in the fact-check); full list in §9.
    - App: `CleanMyMac_5.app` on disk. Finder shows "CleanMyMac". The Homebrew cask installs it under the target name `CleanMyMac.app` and says why: the Finder name and the shell name differ.
    - Launchd labels `com.macpaw.CleanMyMac5.{HealthMonitor,Menu}`, login item "CleanMyMac 5 Menu".
    - Helper: `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` + `/Library/LaunchDaemons/…Agent.plist`.
    - Updater LaunchAgent: `~/Library/LaunchAgents/…Updater.plist`.
    - Support data: `/Users/Shared/CleanMyMac_5`, plus 9 per-user paths.
12. **Mac App Store edition = sandbox minus root.**
    - Cleanup: no System Caches/Logs, Language Files, Universal Binaries, Broken Login Items, Deleted Users or iOS backups.
    - Protection: no real-time monitor.
    - Login/launch items: review only.
    - Applications: App Store app binaries can't be deleted (reset only); no Leftovers; no App Store or macOS updates.
    - Menu: no disk health or temperature.
    - VERIFIED-KB (missing-features, disk-no-health-and-temperature, via 01).
13. **System requirements (5.x):**
    - macOS **11 Big Sur → 27**; Catalina and older unsupported.
    - ~320 MB of disk; display ≥1280×800 (the download page says 1200×800).
    - Smart Insights needs Apple Silicon + macOS 26 + Apple Intelligence.
    - The appcast's `minimumSystemVersion` is `11.0` on all 23 builds (5.0.0 → 5.3.1).
    - (added) The final CleanMyMac X build in its own appcast is **4.15.14** (2025-12-02), `minimumSystemVersion` 10.13.
    - VERIFIED-KB (operating-systems, via 01); VERIFIED-D (both appcasts, re-fetched).
14. **Maintenance tasks come with "when to run" guidance.** Run Maintenance Scripts is safe daily. Each other task is tied to symptoms:
    - Repair Permissions → access problems;
    - Speed Up Mail → slow search;
    - Rebuild Launch Services → wrong "Open With";
    - Reindex Spotlight → missing results, high load;
    - Flush DNS → sites not resolving.
    - The help says it isn't necessary to run them all at once. VERIFIED-D (CMM3 topic 9).
15. **Malware:** Moonlock engine; Quick, Balanced and Deep modes; extra locations (DMG, archives, mail attachments with FDA, USB, iCloud); found threats auto-selected; a Deep scan recommended monthly; the database updated every 7–10 days.
    - The real-time monitor reacts to new installs and only notifies.
    - Some removals need a **restart**.
    - VERIFIED-KB (malware-removal, protection-scan-options, how-often-run-cleanup-scans, protection-monitoring, PUA, via 01/02/04); VERIFIED-D (CMM3 alert string).
16. **Privacy cleanup** needs the browser quit first ("Quit %@ to Estimate"). It deletes history lists, not the downloaded files. Removing saved passwords or cookies means re-entering logins. CMM3 offered a "Time range to clean". VERIFIED-KB (privacy, via 01/02); VERIFIED-D (CMM3 topic 90 + strings).
17. **The Menu's notification settings** (CMM3, the most detailed help available):
    - "Warn when free space is less than" and "Notify when Trash size exceeds" (500 MB → 100 GB, or Don't Warn / Don't Notify);
    - "Offer to correctly uninstall applications" (Trash watcher);
    - "Notify about hung applications";
    - "Reset All Warnings".
    - 5.x Settings › Menu: Enable Menu and Recommendations (weekly cleanup reminders). VERIFIED-D (CMM3 strings + topic 94); VERIFIED-KB (cleanmymac-menu-on-off, …-recommendations, via 01).
18. **Updater (apps).**
    - Sources: App Store, Sparkle, Custom (vendor updaters like Chrome and Zoom), macOS.
    - The App Store edition lacks App Store and macOS updates.
    - Smart Care counts updates excluding system apps and macOS.
    - Ignore List › Applications › Updater exists.
    - The self-updater wakes every 6 h; the 5.x appcast ships Sparkle **deltas**.
    - VERIFIED-KB (updater, smart-care, cleanmymac-processes, via 02/06); VERIFIED-D (appcast).
19. **Space Lens** is a sidebar item: pick a volume or folder → Scan → bubble map (largest → smallest) → zoom → select → **Review Selected** → remove. The map and list are linked. Plus plan only. VERIFIED-KB (space-lens, via 01/07); VERIFIED-3P (X space-lens and space-lens-results summaries).
20. **The CLI help** (MacPaw, 2026) states the modern rule set outright:
    - nothing is removed until confirmed;
    - protected system locations are excluded;
    - project artifacts older than **7 days** are pre-selected, newer ones shown unchecked;
    - the ignore list applies to clean, purge and analyze;
    - `--force` skips confirmation;
    - analytics can be disabled; no files are uploaded.
    - VERIFIED-D (CLI wiki).

---

## 2. Help-centre structure (index pages)

### 2.1 `macpaw.com/support/cleanmymac/knowledgebase` (5.x)
- **Concepts and usage**: VERIFIED-KB (https://macpaw.com/support/cleanmymac/knowledgebase/concepts-and-usage, via 01 §5.1). Groups:
  - Basics: Smart Care, My Tools, Mac health, uninstalling.
  - Protection: malware removal, privacy, app permissions, potentially unwanted applications, scan depth.
  - Performance.
  - Applications.
  - Clutter.
  - Space Lens.
  - Cloud Cleanup.
  - Email cleanup.
  - The Menu: performance, battery, storage, network, connected devices.
- **Article slugs known to exist.** Collected from sibling reports and third-party citations, under `https://macpaw.com/support/cleanmymac/knowledgebase/<slug>`:
  - **Basics:** `smart-care`, `my-tools`, `mac-health`, `uninstaller`, `cleanmymac-safety`, `free-up-more-space`, `duplicate-files`, `large-and-old`, `trash-bins`, `system-junk`, `space-lens`, `space-lens-results`.
  - **Protection:** `malware-removal`, `moonlock-engine`, `protection-scan-options`, `real-time-monitoring-on-off`, `background-scanning-on-off`, `protection-monitoring`, `privacy`, `app-permissions`.
  - **Performance:** `optimization`, `maintenance-tasks`.
  - **Menu:** `cleanmymac-menu`, `cleanmymac-menu-on-off`, `cleanmymac-menu-recommendations`, `menu-no-elements`, `devices-monitoring`, `cpu-temperature`, `disk-no-health-and-temperature`, `the-menu`.
  - **Setup, permissions, components:** `full-disk-access`, `background-items`, `allow-background-items`, `cleanmymac-processes`, `cleanmymac-agent`, `cleanmymac-helper-tool`, `general`, `languages`, **`support-tool-safety`** (added in the fact-check; title cited as "Support Tool safety". A third-party summary says MacPaw documents its support/diagnostics tool as signed and notarized. VERIFIED-3P: https://raw.githubusercontent.com/777genius/clean_disk/HEAD/docs/technical/real-product-feature-adoption-playbook.md).
  - **Purchase / editions:** `missing-features`, `feature-plans`, `editions`, `purchase-options`, `installation-activation`, `upgrade`, `operating-systems`, `cleanmymac-x-release-notes`.

### 2.2 `macpaw.com/support/cleanmymac-x/knowledgebase` (X, 4.x)
Known slugs:
- `system-junk`, `safety-database`, `cleanmymac-safety`, `start-smart-scan`, `how-often-run-cleanup-scans`, `full-disk-access`, `missing-features`, `updater`, `uninstaller`, `extensions`;
- `maintenance`, `optimization`, `cleanmymac-processes`, `cleanmymac-x-menu`, `ram-monitoring`, `cleanmymac-assistant`, `malware-removal`, `potentially-unwanted-applications`;
- `trial`, `operating-systems`, `space-lens`, `large-and-old`, `shredder`;
- German-language: `de/.../mail-attachments`.

### 2.3 Other MacPaw help trees
- `cleanmymac-business/knowledgebase`: index, `smart-scan`, `smart-scan-automation`, `malware-scan`. The product was sunset 2026-07-14.
- `cleanmymac-3/knowledgebase/notifications`.
- `cleanmymac-classic/knowledgebase/cleanmymac-shareware-program`.
- `macpaw.com/how-to/...` articles: `is-cleanmymac-safe`, `stop-background-items-added-mac`, `icloud-drive-taking-up-space`, `organize-email-inbox`, `delete-junk-files-on-mac`, `full-disk-access`, `reindex-spotlight`.
- **Offline:** the CleanMyMac 3 in-app Help Book (§4), and the CLI wiki on GitHub (§6).

INFERRED for our app: ship an **in-app Help** with the same structure: one page per module plus Permissions, Background components, Ignore List, Uninstalling the app, and Troubleshooting. Each page should open from a "?" button in that module's header (the vendor links its help from each module). Bundle it as local HTML or Markdown so it works offline.

---

## 3. Per-article digest: online knowledge base (5.x and X)

> Format: **Title**, URL, then implementation facts. "INFERRED →" lines turn each article into a requirement for our build.

### 3.1 Smart Care
URL: https://macpaw.com/support/cleanmymac/knowledgebase/smart-care. VERIFIED-KB via 01/02/06/07.
- It is the landing screen. It runs five routines "one by one": Cleanup, Protection, Performance, Applications, My Clutter. It combines the modules but does not replace them.
- **What each routine covers:**
  - Cleanup: system junk (logs, caches, broken login items, other), mail attachments and Trash bins, auto-selected.
  - Protection: a **Quick** malware scan; threats auto-selected.
  - Performance: suggests periodic maintenance scripts plus **Flush DNS Cache**.
  - Applications: app updates, excluding system apps and macOS updates.
  - My Clutter: duplicate files in **Downloads only**.
- **Steps:** Smart Care → **Scan** → review tiles → **Run**. **Start Over** (top-left) rescans after a confirmation.
- **Tiles show:** safely removable size; number of threats; number of maintenance tasks; available updates; number of duplicates. Each tile has a **Review** button.
- All tasks are selected by default. Clear a tile's checkmark to skip it for this run.
- **Persistent exclusion:** Settings → **Scanning** → Smart Care (left pane), then deselect a module, category or group. A parent deselects its children. Excluded modules stay visible as dimmed tiles.
- The scan "may take a while" on older or heavily used Macs.
- It never deletes user files or app data unless the user chooses to.
- INFERRED → our "Checkup" screen:
  - five tiles with tri-state selection;
  - a persistent composition tree in Settings › Scanning;
  - dimmed excluded tiles;
  - a rescan confirmation;
  - only low-risk categories.

### 3.2 My Tools
URL: https://macpaw.com/support/cleanmymac/knowledgebase/my-tools. VERIFIED-3P (cited by GitHub notes); content VERIFIED-KB via the 5.5.0 news (01).
- Hub with a search bar, **Favourites** (star any tool) and **Other Tools**. It can also be opened from the Menu.
- Example tools: Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions, Email Cleanup.
- INFERRED → a "Toolbox" with starring persisted in the shared app-group defaults.

### 3.3 Mac Health (Assistant)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/mac-health. VERIFIED-KB via 01/02/08.
- Five bands: **Excellent · Good · Fair · Requires Attention · Critical**.
- Inputs: free disk space, threats, battery health, system load, other hardware metrics, whether FDA is granted, whether a scan ran recently.
- Recommendations include **Allow Access** for FDA, plus maintenance reminders.
- Numeric cutoffs are unpublished (GAP).
- INFERRED → our scoring rubric is in `01-overview.md` §11. Every deduction must map to a one-click fix card.

### 3.4 Uninstaller (and "Uninstalling" basics)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller. VERIFIED-KB via 01/06.
- The Applications module has four parts: **Uninstaller**, **Updater**, **Leftovers** (service files of apps removed by hand) and **Installation files**.
- Flow: scan → tiles → **Manage My Applications**.
- **Groups:** All Applications; **Unused** (not opened in **6 months**); **Suspicious**; and others.
- It removes components located **outside /Applications**.
- System apps are on the Ignore List by default. They can be reset, not removed.
- The App Store edition can't delete App Store app binaries (reset only).
- A Smart Insights icon appears beside apps on macOS 26 with Apple Intelligence.
- Since 5.5.5 the scan runs in the background, so you can act before it finishes (What's New, via 01).
- INFERRED → we need:
  - an "Unused" group based on `kMDItemLastUsedDate` older than 180 days. Apple documents that LaunchServices updates this attribute whenever a file is opened by double-click or through LaunchServices, so apps started any other way (CLI, helpers) can look "unused" (VERIFIED-APPLE, `coreservices/kmditemlastuseddate` doc JSON);
  - Reset (remove everything except the bundle) next to Uninstall;
  - system apps hidden behind an "Ignore system apps" toggle that defaults on.

### 3.5 Safety and reliability (Ignore List)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety. VERIFIED-KB via 01/02/07; VERIFIED-3P (third-party summaries).
- By default only automatically generated system and app data is offered for removal. Personal files are removed only on explicit user choice.
- (added) **Permanent removal vs Trash.** A third-party summary of the KB says MacPaw documents cases where items are **deleted permanently rather than moved to the Trash**, and that features differ by store (VERIFIED-3P: https://raw.githubusercontent.com/mxcl/pkg.so/HEAD/agents/cleanmymac.yml). This is consistent with the CLI's "`--force` … removes detected items immediately" (VERIFIED-D, §6.3) and with CMM3's Large & Old "Remove Immediately" action (§4.7). INFERRED → our UI must say before every cleanup whether items go to the Trash or are deleted, per category (see 03 §delete modes).
- Driven by a safety database plus the **Ignore List**.
- **Ignore List tab categories:** Cleanup (System Junk, Mail Attachments) · Protection (Malware Removal) · Applications (Uninstaller, Updater) · My Clutter (Duplicates, Similar Images, Downloads).
- Ignored items are never shown in results. Add them through the context menu in results; manage them in Settings › Ignore List.
- X-era scope: System Junk, Photo Junk, Mail Attachments, iTunes Junk, Malware Removal, Updater, Large & Old Files, Uninstaller (X cleanmymac-safety KB, via 01).
- INFERRED → ignore rules of type {path prefix, exact file, bundle ID, file extension, result group, volume}, stored per category. A context-menu "Ignore" action is available in every list. See §4.15 for the CMM3 behaviours we should copy.

### 3.6 System Junk (5.x)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/system-junk. VERIFIED-KB (search excerpt, via 03/12).
- "All types" are auto-selected except listed exceptions; **Spotify** and **Gradle** caches are named as user-cache exceptions.
- **Broken login items** are not available in the App Store edition.
- **Groups** (5.x module table, via 01 and missing-features): User Cache Files, System Cache Files, User Log Files, System Log Files, Language Files, Universal Binaries, Xcode Junk, Document Versions, iOS Device Backups, Broken Preferences, Broken Login Items, Deleted Users.
- INFERRED → an exceptions list in our signed rules file (app-specific caches that hold real data), at minimum:
  - **Spotify (corrected).** Downloaded offline music lives by default in `~/Library/Application Support/Spotify/PersistentCache/Storage`. `~/Library/Caches/com.spotify.client/Data` is the streaming cache. Never auto-select the first. Treat the second as an unselected "app cache with user value" row. VERIFIED-3P: https://github.com/JonnyBurger/make-space/blob/HEAD/docs/spotify-cache.md, and the separate cache vs offline-storage constants in https://github.com/jithin-sabu/purge-app/blob/HEAD/purge/Services/DeletionSafetyPolicy.swift (found by GitHub code search).
  - Gradle (`~/.gradle/caches`).
  - Re-verify on device.

### 3.7 Trash Bins
URL: https://macpaw.com/support/cleanmymac/knowledgebase/trash-bins. VERIFIED-KB via 02/03.
- Categories: Mail, Photos, Gemini Duplicates, Startup drive (including items removed from iCloud), External drives (one trash per drive).
- All items are auto-selected.
- INFERRED → we enumerate:
  - `~/.Trash`;
  - `/Volumes/*/.Trashes/<uid>`;
  - the Mail "Deleted Messages" mailboxes (FDA);
  - Photos "Recently Deleted" (report only; deletion via Photos).
  - The Mail and Photos trash should **not** be emptied by direct file deletion.

### 3.8 Duplicates
URL: https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files. VERIFIED-KB via 02/07.
- My Clutter › Duplicates compares by **content**. **Apply smart selection** keeps one copy per group.
- Smart Care only looks in ~/Downloads.
- Which copy is kept is not documented for CleanMyMac (GAP, still open after the fact-check).
- (added) **Closest vendor evidence: MacPaw's own duplicate finder, Gemini 2.** CleanMyMac's Trash Bins already list a "Gemini Duplicates" category. VERIFIED-3P, from a summary of the Gemini 2 user guide PDF (https://raw.githubusercontent.com/ayhid/twins/70a63e785573c0768769850603e5e1faed3a4b3f/.planning/research/FEATURES.md):
  - auto-select filters "Automatically / Newest / Oldest / Any";
  - a "Never Select" list of protected folders;
  - a context action "Select All Copies Within folder";
  - removing the last copy in a group needs an explicit "Remove Last Instance" step with a warning;
  - similar (non-identical) items are never auto-selected;
  - Photos and iTunes libraries are special-cased, with Photos duplicates routed through a "Gemini Duplicates" album;
  - "Automatically" is marketed as learning from the user's choices, which makes it opaque.
  - INFERRED: CleanMyMac's "Apply smart selection" probably reuses Gemini's "Automatically" logic, but that is unconfirmed.
- INFERRED → use a deterministic keep rule with a visible reason per group. Default: keep the copy outside `~/Downloads` and `~/Desktop`, then the oldest by creation date, then the shortest path. Add a "Never select in…" folder list. Make "remove every copy" impossible. Never auto-select inside Photos or Music libraries.

### 3.9 Free up more space
URL: https://macpaw.com/support/cleanmymac/knowledgebase/free-up-more-space. VERIFIED-KB via 01/07.
- My Clutter: choose a location (home, a disk, an external drive) → scan → **Review All Files**. Categories: Large & Old Files, Duplicates, Similar Images, Downloads (old DMGs, archives, documents).
- Smart selection avoids system files.

### 3.10 Large & Old files
URL: https://macpaw.com/support/cleanmymac/knowledgebase/large-and-old (X: …/cleanmymac-x/knowledgebase/large-and-old). VERIFIED-3P (https://raw.githubusercontent.com/HuakunShen/space-lens/HEAD/apps/web/UX_RESEARCH.md); VERIFIED-KB (sort options, via 01).
- Group or sort by **kind, size, or access date**. Preview and Reveal are available.
- Large files are **left unselected**, because they may hold useful data.
- Consistent with CMM3 topic 7 (§4.7).

### 3.11 Space Lens and Space Lens results
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/space-lens and https://macpaw.com/support/cleanmymac/knowledgebase/space-lens-results (X: …/cleanmymac-x/knowledgebase/space-lens). VERIFIED-KB via 01/07; VERIFIED-3P (HuakunShen/space-lens UX_RESEARCH.md; kali-physi-hacker/veyra `docs/product-research.md`).
- A sidebar item: pick a volume or folder → **Scan** → bubble map, with bubbles ordered from largest to smallest.
- Click a bubble to zoom in. Select items and remove them.
- **Results page** (3P summary): the map and a complete list are coordinated. Hovering in the map highlights the list row. Also: breadcrumbs, size ordering, Quick Look and Reveal, checkboxes, and a separate **Review Selected** step before removal.
- Absent in 5.0, back in 5.1.0. Plus plan only.
- Cloud Cleanup reuses Space Lens for cloud drives.
- INFERRED → "Space Map" with a linked treemap/bubble view and list, breadcrumb navigation, a selection tray, and a Review sheet before Trash.

### 3.12 Optimization (Login Items / Background Items)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/optimization. VERIFIED-KB via 01/06.
- Performance includes **Login Items** and **Background Items**.
- **Disable** is reversible; **Remove** is permanent.
- The App Store edition can only review login items and launch agents, and only uninstall launch agents (not disable them).
- INFERRED → use `SMAppService.statusForLegacyPlist(at:)` for state. For disable, prefer `launchctl bootout` plus a disabled override over deleting the plist; deletion is "Remove". See 05-performance.

### 3.13 Maintenance tasks
URL: https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks. VERIFIED-KB via 01/02/05.
- The Performance module has a "weekly maintenance" bundle with **Review** and **Run Tasks**. **View All Tasks** opens the full list.
- **Tasks:**
  - Free Up RAM;
  - Free Up Purgeable Space (5.0.5+);
  - Flush DNS Cache;
  - Reindex Spotlight;
  - Run Maintenance Scripts (macOS ≤13);
  - Repair Disk Permissions;
  - Speed Up Mail;
  - Thin Time Machine Snapshots.
- Not in the App Store edition.
- Per-task "when to run" guidance: §4.9 (CMM3 Help).
- X-era KB (https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance): rows showed the **last-run date** (VERIFIED-KB via 02).

### 3.14 Malware Removal
URL: https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal (X: …/cleanmymac-x/knowledgebase/malware-removal). VERIFIED-KB via 01/02/04.
- Protection has three sub-areas: **Malware Removal**, **Privacy**, **App Permissions**. In X, Malware Removal and Privacy were separate sidebar items.
- **Threat classes:** viruses, adware, spyware, keyloggers, worms, Trojans, ransomware, potentially unwanted applications.
- **Scan modes:** Quick, Balanced, Deep. **(corrected)** The claim that older X builds called the thorough mode "Maximize suspicion" is downgraded to **INFERRED (unconfirmed)**. It traces back to one search excerpt seen by the 04 researcher, and 04's own fact-check could not confirm it. This report repeated it, so it is not an independent source.
- (added) REPLICA, weak: a third-party pixel replica of the Protection settings shows the option rows "Scan DMG disk images", "Scan email attachments", "Scan archives" and "Scan USB drives". It words the iCloud option as an exclusion, "Exclude downloaded iCloud files". Each mode shows Speed, Depth and Purpose descriptors; Deep reads "Slowest" and "Thorough". Source: https://raw.githubusercontent.com/ddlmanus/MacOptimizer/5fdfcc04cf6ad09752174a64dff3fc960bc66445/AppUninstaller/MalwareRemovalReplicaView.swift (fetched). Write our own labels.
- All found threats are auto-selected. **Remove** works without review; **Review** shows details first.
- MacPaw recommends a **Deep scan monthly** even with monitoring on (X KB).

### 3.15 Moonlock Engine
URL: https://macpaw.com/support/cleanmymac/knowledgebase/moonlock-engine. VERIFIED-KB via 01/04.
- MacPaw's in-house engine, named in X 4.14 (July 2023). It powers on-demand removal, the real-time monitor and background scanning.
- INFERRED → we name our own engine. Signature and heuristics design lives in 04-protection.

### 3.16 Protection scan options
URL: https://macpaw.com/support/cleanmymac/knowledgebase/protection-scan-options. VERIFIED-KB via 01/02.
- **Settings › Protection:** scan mode Quick / Balanced / Deep.
- Extra locations: **disk images (DMG)** (this one also applies to Smart Care), **email attachments** (needs FDA), **archives**, **USB drives**, **iCloud files**.

### 3.17 Real-time monitoring on/off; Background scanning on/off; Protection monitoring
URLs:
- https://macpaw.com/support/cleanmymac/knowledgebase/real-time-monitoring-on-off
- https://macpaw.com/support/cleanmymac/knowledgebase/background-scanning-on-off
- https://macpaw.com/support/cleanmymac/knowledgebase/protection-monitoring

VERIFIED-KB via 01/04.
- **Enable Malware Monitor** (recommended on) subscribes to macOS notifications about new program installations. It checks new or modified items and posts a notification on malware or a PUA. It is notify-only and runs from the Health Monitor, so it works while the app is closed.
- **Background scanning** is a separate periodic whole-system sweep, with its own toggle.
- The App Store edition has no real-time monitor or alerts.
- INFERRED → our monitor:
  - FSEvents on `/Applications`, `~/Applications`, `~/Library/LaunchAgents`, `/Library/Launch*`, plus BTM change notifications;
  - notification with **Review** and **Remove** actions;
  - no Endpoint Security, because a personal ad-hoc build can't get the entitlement (see 10 §13).

### 3.18 Potentially unwanted applications
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/potentially-unwanted-applications. VERIFIED-KB via 04.
- PUAs are a detection class reported by the monitor and by scans, with the same notification path as malware.

### 3.19 Privacy
URL: https://macpaw.com/support/cleanmymac/knowledgebase/privacy. VERIFIED-KB via 01/02.
- **Grouped per browser** (Safari, Chrome, Firefox): browsing history, cookies, downloads history, autofill, search queries, last-session tabs.
- **Recent Items:** recently accessed servers, launched apps, opened documents.
- The browser must be **quit** first.
- Not part of Smart Care.
- The App Store edition restricts Safari items and Wi-Fi network cleanup (missing-features).
- CMM3 detail is in §4.10.

### 3.20 App Permissions
URL: https://macpaw.com/support/cleanmymac/knowledgebase/app-permissions. VERIFIED-KB via 01/04.
- Review which apps hold camera, microphone, files/folders, FDA and other TCC grants. Recommended reviews appear as tiles.
- Permission management is restricted in the App Store edition.
- INFERRED → we read TCC state (user `TCC.db` with FDA; read-only). Changes deep-link to the right System Settings pane, e.g. `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`, because modifying TCC.db is unsupported and SIP-blocked.

### 3.21 Full Disk Access permission
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access and https://macpaw.com/support/cleanmymac-x/knowledgebase/full-disk-access. VERIFIED-KB via 01/02/10; VERIFIED-3P (third-party summary: "without it they cannot scan all junk or malware locations").
- **Why it's needed:** without FDA the app can't scan all areas (junk and malware), email-attachment malware scanning is unavailable, and the Health monitor lacks disk data.
- **Steps (macOS 13+):** run a Smart Care scan first, so the app registers its components and they appear in the list. Then System Settings › Privacy & Security › **Full Disk Access** › toggle the app on › Touch ID or password.
- **Steps (Mojave–Monterey):** Security & Privacy › Privacy › Full Disk Access, unlock, add components.
- **Shortcut:** the Assistant's FDA recommendation offers **Allow Access**.
- MacPaw open-sourced its detector as `PermissionsKit`: probe-open TCC-protected files, then deep-link to `Privacy_AllFiles` (VERIFIED, via 10). **Re-verified in the fact-check (VERIFIED-D):**
  - The README lists the probe files: `~/Library/Safari/Bookmarks.plist`, `~/Library/Safari/CloudTabs.db`, `/Library/Application Support/com.apple.TCC/TCC.db` and `/Library/Preferences/com.apple.TimeMachine.plist`. It warns there is **no callback** when FDA is granted, so apps must poll or re-check on app activation. https://raw.githubusercontent.com/MacPaw/PermissionsKit/master/README.md
  - `MPFullDiskAccessAuthorizer.m` opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` (GitHub code search, repo MacPaw/PermissionsKit).
- INFERRED → onboarding step plus a persistent banner. Before deep-linking, attempt a protected read so the app appears in the list. Poll to auto-detect the grant.

### 3.22 Background items / Allow background items
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/background-items and https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items. VERIFIED-KB via 01/02/08; how-to https://macpaw.com/how-to/stop-background-items-added-mac (VERIFIED-KB via 01).
- macOS shows **"Background Items Added"** after install.
- **Menu** and **Health Monitor** must be allowed under System Settings › General › **Login Items & Extensions** › **Allow in the Background**.
  - **(corrected: the pane name depends on the macOS version)** It is "Login Items & Extensions" on macOS 15 and later, and plain "**Login Items**" on macOS 14 Sonoma, with the same "Allow in the Background" list in both. VERIFIED-3P: https://github.com/DonMikone/CloudWire/blob/HEAD/scripts/release-notes.md.tmpl (found by GitHub code search).
  - Our onboarding text must name the right pane for the running OS.
- If they are disallowed, the Menu won't open and the in-app toggle does nothing.
- INFERRED → read `SMAppService.status`. On `.requiresApproval` or not-allowed, show "Background monitor is blocked" with a button calling `SMAppService.openSystemSettingsLoginItems()`.
  - **API check (VERIFIED-APPLE, fact-check):**
    - `SMAppService` and `openSystemSettingsLoginItems()` are macOS 13.0+.
    - `SMAppService.Status` has the cases `.notRegistered`, `.enabled`, `.requiresApproval` and `.notFound`.
    - `statusForLegacyPlist(at:)` is macOS 13.0+.
    - Sources: https://developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice.json and `…/smappservice/status-swift.enum.json`, `…/statusforlegacyplist(at:).json`, `…/opensystemsettingsloginitems().json`.

### 3.23 Background processes (cleanmymac-processes, 5.x and X)
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes and https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes. VERIFIED-KB via 01/02/04/06/08.
- The **Health Monitor** collects memory, disk space, battery, CPU, network, unresponsive apps and Trash level.
- It feeds Menu indicators and alerts:
  - low disk space;
  - high memory;
  - unresponsive apps;
  - "uninstall completely?" when an app is dragged to the Trash.
- It also powers real-time malware monitoring and background scans.
- X-era: the self-**Updater** woke every **6 h**.

### 3.24 CleanMyMac Agent / Helper tool
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent and https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-helper-tool. VERIFIED-KB via 01/06/10.
- The Agent is a **privileged helper tool**; macOS does not list it as a background item.
- It is installed the first time an operation needs root (admin password prompt).
- **It is used to:** delete system files, uninstall some apps, remove launch agents, flush DNS, clear system caches.
- It is inactive unless needed and exits when the app quits. Privilege-separated design.
- **On disk** (VERIFIED-D, cask): `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` and `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist`. The plist has only a `MachServices` key, so launchd starts it on demand (VERIFIED, via 10).
- The exact troubleshooting wording for "helper tool not installed" was not retrieved (GAP, still open after the fact-check: macOS-only KB, no third-party copy found by GitHub code search). CMM3's equivalent prompt is in §4.16.
- (added) **What the install mechanism implies for troubleshooting.** VERIFIED via 10 §1: three signals say 5.x installs the Agent with `SMJobBless`:
  - the helper ships in the bundle at `Contents/Library/LaunchServices/com.macpaw.CleanMyMac5.Agent`;
  - its on-disk launchd plist has exactly the shape `SMJobBless` writes;
  - tooling rewrites the app's `SMPrivilegedExecutables` key.
  - INFERRED: so the usual repair is the one used for any blessed helper:
    1. quit the app;
    2. remove `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` and `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` with `sudo launchctl bootout system/com.macpaw.CleanMyMac5.Agent` first;
    3. relaunch, and run a root task so the app re-blesses the helper after an admin prompt.
  - INFERRED: it also explains a "not installed" state after a manual "Allow in the Background" toggle-off. On macOS 13+ blessed daemons appear in Background Items too, under the vendor's name.
- INFERRED → **Settings › Advanced › Helper** shows: status (Not installed / Requires approval / Enabled / Version mismatch) with **Install**, **Reinstall** and **Remove** buttons. Every root-requiring task explains why before prompting. Our own helper uses `SMAppService.daemon(plistName:)` (macOS 13+, VERIFIED-APPLE), not the deprecated `SMJobBless`. It pins the client with `NSXPCConnection.setCodeSigningRequirement(_:)` / `NSXPCListener.setConnectionCodeSigningRequirement(_:)` (both macOS 13.0+, VERIFIED-APPLE: https://developer.apple.com/tutorials/data/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:).json).

### 3.25 Missing features (Mac App Store edition)
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/missing-features and https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features. VERIFIED-KB via 01/02/03/06.
- **5.x feature table order:** Smart Care · Cleanup · Protection · Performance · Applications · My Clutter · Space Lens · Cloud Cleanup · My Tools · My Activity · The Menu.
- **Missing or restricted in the App Store edition:**

| Area | App Store edition limitation |
|---|---|
| System Junk | No System Cache Files, System Log Files, Language Files, Universal Binaries, Broken Login Items, Deleted Users, or iOS Device Backups. User Cache, User Logs, Xcode Junk, Document Versions and Broken Preferences are kept. |
| Trash Bins, Mail Attachments | Available. |
| Smart Care | No Broken Login Items or Deleted Users; no Photos/Gemini trash categories. |
| Protection | No real-time monitor or alerts; Safari privacy, Wi-Fi network cleanup and permission management restricted. |
| Performance | Some maintenance tasks missing; login items and launch agents review-only. |
| Applications | No deletion of App Store app binaries (reset only); no Leftovers; no App Store or macOS updates. |
| Menu | No Disk Health and Temperature. |
| X App Store edition | No Photo Junk, Maintenance, Updater or Shredder. Its Smart Scan used Large & Old Files instead of Speed. |

- INFERRED → this table is our "needs FDA, root or no sandbox" checklist. Our direct build implements all of it.

### 3.26 Feature plans / Editions / Purchase options / Installation & activation / Upgrade
URLs: …/feature-plans, …/editions, …/purchase-options, …/installation-activation, …/upgrade (5.x). Also https://macpaw.com/support/cleanmymac-x/knowledgebase/trial. VERIFIED-KB via 01.
- **Plans:** Basic and Plus since July 2025. Plus adds Protection, Space Lens and Cloud Cleanup.
- **Channels:** MacPaw Store, Mac App Store and Setapp.
- **Trial:** 7 days, full functionality. Unlicensed: everything scans, but cleanup is locked and malware is found but not removed.
- **Activation:** "Unlock Full Version" (top-right) or menu **CleanMyMac › Activate**, then trial / buy / "I already have a license", then MacPaw Account sign-in.
- **Install:** DMG → drag to Applications → launch.
- INFERRED → none of the licensing applies to our personal build. Keep only "install by drag" and the "Move to Applications?" check (§4.16).

### 3.27 Supported operating systems (system requirements)
URLs: https://macpaw.com/support/cleanmymac/knowledgebase/operating-systems and https://macpaw.com/support/cleanmymac-x/knowledgebase/operating-systems. VERIFIED-KB via 01.
- **5.x:** macOS 27, 26, 15, 14, 13, 12, 11. Catalina and earlier are not supported.
- **X:** development ended; Tahoe 26 is the last supported macOS.
  - (added) The X appcast (`https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml`, fetched) has 43 items. The newest is 4.15.14, build `41514.0.2512021236`, published 2025-12-02, with `minimumSystemVersion` 10.13. Before that: 4.15.13 (2025-08-06) and 4.15.12 (2025-03-11). VERIFIED-D. This fits "development ended" after Tahoe support.
- **CMM3:** 10.9–10.14.
- Corroboration: the appcast `minimumSystemVersion` is `11.0` (VERIFIED-D, `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml`). The CLI requires macOS 11+ (VERIFIED-D, CLI wiki and cask `depends_on macos: :big_sur`).
- INFERRED → our deployment target is **macOS 14**, so we can rely on `SMAppService`, `NSXPCConnection.setCodeSigningRequirement`, SwiftUI `MenuBarExtra` and Observation.

### 3.28 General settings (updates)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/general. VERIFIED-KB via 01.
- The **Updates** section has "Automatically keep CleanMyMac up to date". In the App Store edition the App Store handles updates.
- Other 5.x General options were not documented (GAP). CMM3 General tab: §5.1.
- (added) **Settings window tabs, weak evidence.** The third-party replica's settings tab strip reads **General · Scan · Notifications · Menu · [one slot the replica filled with its own AI-agent tab] · Protection · Disk Access · Analytics · Ignore List**. REPLICA (weak): https://raw.githubusercontent.com/ddlmanus/MacOptimizer/5fdfcc04cf6ad09752174a64dff3fc960bc66445/AppUninstaller/MalwareRemovalReplicaView.swift.
  - With 01 §10, which verified General, Scanning, Ignore List, Protection and Menu for 5.x, this **suggests a Notifications tab still exists**. It also suggests a "Disk Access" (FDA status) tab and an "Analytics" (usage-data opt-out) tab.
  - The replica may copy the X Preferences window rather than 5.x, so treat the list as INFERRED.
  - The open slot was probably "Assistant" in X (X KB: the Assistant can be silenced in Preferences › Assistant, §3.42).

### 3.29 Languages
URL: https://macpaw.com/support/cleanmymac/knowledgebase/languages. VERIFIED-KB via 01.
- There is no in-app language picker; the app follows macOS. Per-app language is set in System Settings › General › Language & Region › Applications.
- 12 localisations: zh-Hans, nl, fr, de, en, it, ja, ko, pl, pt-BR, es, uk.
- The 5.x appcast carries per-language release-notes links (VERIFIED-D, appcast). **(corrected)** It has **13** languages, not 12: the 12 above plus **`tr` (Turkish)**. Turkish release notes appear on every build from **5.2.3** (2025-08-13) onward and on no earlier build. VERIFIED-D (re-fetched; `xml:lang="tr"` on 10 of 23 items).
  - INFERRED: the KB's 12-language list predates a Turkish localisation added around 5.2.3.
  - INFERRED → our app follows the system language (no in-app picker), the same as the vendor.

### 3.30 The Menu (cleanmymac-menu, -on-off, -recommendations, the-menu)
URLs:
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-on-off
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-recommendations

VERIFIED-KB via 01/08.
- **Monitors:**
  - Health.
  - Protection: real-time and background scan status, database status.
  - Storage: free space, disk health and temperature, Empty Trash; **startup volume only**.
  - Memory: Free Up, pressure, swap, top apps.
  - Battery: health = actual/design capacity in mAh; **≥80% Normal, ≤79% Warning, ≤10% Critical**.
  - CPU: load, temperature, top consumers.
  - Network.
  - Connected Devices.
- **Settings › Menu:** **Enable Menu**; **Recommendations** (feature suggestions plus weekly cleanup reminders).
- TidBITS noted the Menu settings are very limited (via 01).
- INFERRED → we offer more: per-monitor visibility, a menu-bar label choice and alert thresholds (CMM3-style, §5.2).

### 3.31 Devices monitoring
URL: https://macpaw.com/support/cleanmymac/knowledgebase/devices-monitoring. VERIFIED-KB via 01/08.
- Shows connected devices over cable, Bluetooth or Wi-Fi, **up to 3**. A device with battery **below 20%** turns red and moves to the top.

### 3.32 CPU temperature
URL: https://macpaw.com/support/cleanmymac/knowledgebase/cpu-temperature. VERIFIED-KB via 01/08.
- The unit follows System Settings › Language & Region › Temperature.
- INFERRED → use `MeasurementFormatter` with `.temperatureWithoutUnit` off and the locale's unit preference.

### 3.33 Disk has no health and temperature
URL: https://macpaw.com/support/cleanmymac/knowledgebase/disk-no-health-and-temperature. VERIFIED-KB via 01.
- Disk health and temperature monitors are unavailable in the App Store edition (sandbox).
- INFERRED → also expect them to be unavailable for external, USB or NVMe enclosures that don't pass SMART. Show "Not available for this disk" rather than a blank.

### 3.34 Menu shows no elements (troubleshooting)
URL: https://macpaw.com/support/cleanmymac/knowledgebase/menu-no-elements. VERIFIED-3P (described by a GitHub note as "menu 'no elements' until loaded/opened": https://raw.githubusercontent.com/venomousmoog/lintel/HEAD/docs/research/2026-07-06-feasibility-findings.md).
- Exact steps not retrieved (GAP). The related, verified cause is background items being disallowed (§3.22).
- (added) The same third-party note gives the article's title as "Troubleshoot the CleanMyMac Menu not loading correctly", which means it is about the Menu failing to load, not about empty monitors. VERIFIED-3P (same URL, line 193).
- INFERRED → our menu-bar extra shows a placeholder state ("Starting monitor…") and a "Fix" link if the agent isn't running.

### 3.35 Release notes
URL: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-x-release-notes (used as the changelog link by IntuneBrew; VERIFIED-3P https://raw.githubusercontent.com/ugurkocde/IntuneBrew/HEAD/Apps/cleanmymac.json).
- The appcast links per-build release notes at `https://updates.devmate.com/releasenotes/<build>/com.macpaw.CleanMyMac5.html` (VERIFIED-D, appcast).

### 3.36 X: System Junk (smart-selection rules)
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk. VERIFIED-KB via 02/03/07.
- Document Versions: the 4-hour rule; never the earliest or latest.
- iOS backups: the most recent is never auto-selected.
- **Downloads:** Safari, only **broken** downloads; Slack, broken downloads **or files ≥ 1 month old**.
- Mail attachments: only local copies are removed.
- Per-module subcategory toggles exist in Preferences › Scanning.

### 3.37 X: Mail attachments (German KB)
URL: https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments. VERIFIED-KB via 02/03.
- Smart selection only flags attachments you can get back by reopening the mail (Mail, Spark) or by Outlook's "Repair Folders".
- Edited attachments are labelled **"changed by user"** and not selected.

### 3.38 X: Safety Database
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database. VERIFIED-KB via 02/07.
- A database of items, rules and exceptions consulted on every scan.
- It protects locations: no wholesale `/Library` or `/System/Library`; the Shredder refuses critical folders.
- It holds app-specific exceptions where "cache" is real data (Spotify offline music).
- CMM3 Preferences › Updates had "Enable background updates of … Safety Database". The help called keeping it current vital (VERIFIED-D, §5.6).

### 3.39 X: Start Smart Scan
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/start-smart-scan. VERIFIED-KB via 02.
- **Three scanners:**
  - Cleanup: System Junk, Photo Junk, Mail Attachments, iTunes Junk, Trash Bins.
  - Protection: Malware Removal.
  - Speed: Free Up RAM, Run Maintenance Scripts, Flush DNS Cache, Hung Applications.
- The result shows removable size, threats and tasks. **Review Details** sits under each scanner; deselections apply to this run only. **Run** executes.
- Persistent exclusion is in Preferences › Scanning. Excluding a System Junk or iTunes Junk sub-module also affects the standalone module.

### 3.40 X: How often to run cleanup scans
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/how-often-run-cleanup-scans. VERIFIED-KB via 02.
- Smart Scan **weekly** for heavy use, about **every 2 weeks** for light use.
- **Deep malware scan monthly**. The malware database updates every **7–10 days**.
- Reminders come from the Menu and the Notifications tab; there is no forced auto-run.

### 3.41 X: Updater
URL: https://macpaw.com/support/cleanmymac-x/knowledgebase/updater. VERIFIED-KB via 02/06.
- **Sources:** App Store, Sparkle, Custom, macOS. 5.x groups: "App Store Updates", "Sparkle Updates", "Custom Updates", "macOS Updates".
- The App Store edition lists neither App Store nor macOS updates.
- "Custom" covers vendor updaters; X 4.11.2 added Zoom and 4.11.3 added Chrome (DevMate notes, via 06/08).
- INFERRED → for Sparkle apps, read `SUFeedURL` from the target app's Info.plist and fetch the appcast. Updates open the app's own updater or the App Store page; we never replace bundles ourselves.
- (added, gap 5) **What else is known about the 5.x Updater** (VERIFIED via 06 §4.1, from DevMate X release notes):
  - since X 4.13.6 it hides updates the running macOS cannot run;
  - 4.13.6 also fixed scanning of Microsoft Outlook and **Microsoft AutoUpdate**, so MAU-managed Office apps are probably a "Custom" source (INFERRED);
  - since 4.14.0 the update notification lists the top outdated apps;
  - Smart Care's **Run** "updates the selected apps" (KB via 02).
- **Still unknown:** how "Custom Updates" are discovered (a vendor-side catalogue keyed by bundle ID is the likely design), and whether Sparkle and custom updates install silently or hand off to each vendor's updater. No primary text was reachable in the fact-check. INFERRED reading: "Run updates the selected apps" without opening anything suggests the vendor downloads and installs Sparkle and custom updates itself, while App Store items go through the App Store. Our build should still not do in-place replacement (see 06 §4.4).

### 3.42 X: CleanMyMac X Menu / RAM monitoring / Assistant
URLs:
- https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu
- https://macpaw.com/support/cleanmymac-x/knowledgebase/ram-monitoring
- https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-assistant

VERIFIED-KB via 02/08.
- **Notifications preferences:** weekly cleanup reminders; tips about unused features; a full-uninstall prompt; overfilled Trash and cluttered drives (including external); low-RAM warnings. Configurable from the Menu or Preferences › Notifications.
- The Menu's disk **Free Up** button starts Smart Scan instantly.
- **Assistant:** personalised suggestions and "scheduled maintenance" reminders. Yellow buttons mark the most relevant tasks. It can be silenced in Preferences › Assistant.

### 3.43 X: Optimization / Maintenance
URLs: https://macpaw.com/support/cleanmymac-x/knowledgebase/optimization and …/maintenance. VERIFIED-KB via 01/02/05.
- **Optimization:** Login Items, Launch Agents, Hung Applications, Heavy Consumers.
- **Maintenance:** maintenance scripts, DNS, Spotlight, RAM, permissions, Mail, Time Machine snapshots; last-run dates shown. Verify Startup Disk is unavailable on APFS.

### 3.44 X: Extensions / Uninstaller / Shredder (partially retrieved)
URLs: …/cleanmymac-x/knowledgebase/extensions, …/uninstaller, …/shredder.
- **Not retrieved** (GAP), per 06 §12.
- The CMM3 Help covers the same modules in full (§4.8, §4.11, §4.12), and the X behaviour is believed to be equivalent (INFERRED).

### 3.45 Business: Smart Scan automation / Malware scan
URLs: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation, …/smart-scan, …/malware-scan. VERIFIED-KB via 02/03/04.
- Scheduled forced runs every **7/14/30 days**, with **0–2 reminders** before the forced run.
- **Unattended-safe junk types:** System log files, Broken login items, User cache files, Language files, Broken preferences, Xcode junk, Mail attachments, Trash bins. iOS backups and Document Versions are absent.
- Malware scan depths are the same as consumer.
- INFERRED → if we add a scheduler, restrict unattended runs to this list, minus Language files (code-signature risk on Apple Silicon, per 01 §12).

### 3.46 CleanMyMac 3 KB: Notifications
URL: https://macpaw.com/support/cleanmymac-3/knowledgebase/notifications. VERIFIED-KB via 02.
- Reminder frequency is adjustable on the Notifications tab (older versions: a "Scheduler" tab, weekly → annually). Reminders can be turned off.
- See §5.5 for the exact CMM3 Scheduler values.

### 3.47 Classic: Shareware program
URL: https://macpaw.com/support/cleanmymac-classic/knowledgebase/cleanmymac-shareware-program. VERIFIED-KB via 01.
- The 2008 shareware did a full scan and cleaned up to 500 MB free. CMM3's demo similarly showed "%@ left to clean" (VERIFIED-D, CMM3 Alerts).

### 3.48 How-to articles (macpaw.com/how-to)
VERIFIED-KB via 01/02/07.
- **is-cleanmymac-safe:** only automatically generated system and app data is offered by default.
- **stop-background-items-added-mac:** explains the macOS 13+ "Background Items Added" notice.
- **icloud-drive-taking-up-space:** Cloud Cleanup is chosen from the sidebar. Actions: **Remove** (from the cloud), remove from Mac and cloud, **Unsync** (free the local copy). Google Drive needs Google's desktop client.
- **organize-email-inbox:** Tools in the sidebar → **Email Cleanup** (Gmail OAuth). Finds newsletters, promotions, spam, old drafts and large attachments. Actions: Unsubscribe, Archive, Move to Trash, each confirmed.
- **delete-junk-files-on-mac**, **full-disk-access**, **reindex-spotlight:** generic how-tos (titles cited by 3P research notes).

---

## 4. Per-article digest: CleanMyMac 3 in-app Help Book (fetched in full)

Source: MacPaw's own Help Book, shipped inside `CleanMyMac 3.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/`. Mirror base URL (all VERIFIED-D): `https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/`, files `index.html`, `topic-1..9.html`, `topic-90..94.html` (16 pages; other topic numbers return 404).

It is old (2015–2018), but it is the **only complete MacPaw help centre we could read end-to-end**. Its rules mostly carry through X and 5.x, as the online KB facts in §3 show.

### 4.0 Index
- Table of contents: Welcome · Smart Cleanup · System Junk · Photo Junk · Mail Attachments · iTunes Junk · Trash Bins · Large & Old Files · Uninstaller · Maintenance · Privacy · Extensions · Shredder · Dashboard · CleanMyMac 3 Menu.
- INFERRED → this is exactly our in-app help skeleton, renamed to our modules.

### 4.1 Smart Cleanup (topic-1)
- Runs all cleaning modules. A built-in **Safety Database** makes sure no vital items are selected by default.
- Click **Scan**. Smart Selection focuses on unneeded and outdated files:
  - System Junk: outdated caches, old logs, extra binaries, broken app data, unused localisations.
  - Photo Junk: only restorable caches are smart-selected.
  - Mail Attachments: local copies of opened attachments; the online mailbox is never touched.
  - iTunes Junk: iOS apps, old backups and updates, artwork cache, broken downloads.
  - Trash Bins: all trashes, including external drives, Photos and Mail.
  - Large & Old Files: **nothing selected by default**; the user must review.
- The result screen shows a total plus a per-module amount. Clicking a module icon opens its details. **Clean** removes. **Start Over** on the completion screen returns to Welcome.
- **Persistent exclusion:** Preferences › **Smart Cleanup** tab.
  - Deselecting a *sub-module* of System Junk or iTunes Junk also excludes it from that module's own scan.
  - Deselecting a whole module only removes it from Smart Cleanup; a separate module scan still covers everything.
- INFERRED → keep this **two-level exclusion semantics**: group-level exclusions are global, module-level exclusions are Checkup-only. The settings footer should say so (CMM3's footer said exactly this; §5.3).

### 4.2 System Junk (topic-2)
- **Group list with one-line rationale each.** INFERRED → write our own descriptions:
  - **Broken Login Items:** links left after an app was removed.
  - **Broken Preferences:** corrupted prefs that cause misbehaviour.
  - **Document Versions:** the 4-hour rule (§1 #5).
  - **Development Junk:** install/config leftovers.
  - **iOS Photo Cache:** post-sync photo cache.
  - **Language Files:** unused app localisations.
  - **Leftovers:** remains of uninstalled apps, **not offered by default; select manually**.
  - **macOS Localizations:** unused system languages.
  - **Old Updates:** old app update files; safe to remove.
  - **System Cache Files**, **System Log Files**, **User Cache Files**, **User Log Files**.
  - **Universal Binaries:** extra architectures.
  - **Xcode Junk:** intermediate build data and index. **Module Cache and Archives are never removed automatically.**
- **Results-list UX:**
  - a magnifier icon on hover reveals the item in Finder;
  - a "Sort by" menu;
  - **Deselect All** (top-left);
  - per-group and per-item checkboxes;
  - **Action › Rescan** (current selection discarded);
  - a live **search field** with a clear (x) button;
  - Control-click → **Add to Ignore List**;
  - **Clean**, then **Start Over**.
- INFERRED → every results list in our app gets: hover Reveal, Sort-by, Select/Deselect All, search, a context-menu Ignore, and Rescan with a "selection will be lost" confirmation.

### 4.3 Photo Junk (topic-3)
- **Groups:**
  - **RAW Originals:** replaces RAWs with Photos' JPEGs.
  - **Faces Cache.**
  - **Photos Cache:** regenerable.
  - **iCloud Local Copies:** viewed images; need internet to re-download.
- **Change Library** picks a non-default library.
- **Smart selection:** only Photos Cache and Faces Cache. RAWs are never default-selected. Ignore List › Photo Junk has an "Ignore RAW photos" option.
- RAW review: a zoom slider; **Reveal in Photos**; Quick Look side-by-side.
- iPhoto: hidden originals (rotated, cropped, enhanced, red-eye); only red-eye and rotated originals are smart-selected.
- INFERRED → **do not implement** Photos-library internals manipulation on modern macOS. Photos libraries are managed databases, and edits outside PhotoKit risk corruption. At most, report the size and suggest Photos' "Optimize Mac Storage".

### 4.4 Mail Attachments (topic-4)
- Mail keeps a local copy of every attachment you open until the email is deleted.
- Smart selection covers locally stored attachments and recoverable Mail downloads, and **skips modified ones**. Everything removed is recoverable by opening the email again.
- **Review Files:** Reveal; Quick Look; **group by Mail account / Last view date / File kind**; sort; search; Rescan; Ignore.
- INFERRED → scan `~/Library/Mail/V*/…/Attachments` (FDA) and `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`. Compare the modification date against the original (unmodified = safe). Group by account (parse the mailbox path) and by last-opened date (`kMDItemLastUsedDate`).

### 4.5 iTunes Junk (topic-5)
- **Groups:**
  - **iOS Applications:** old `.ipa` copies.
  - **iOS Device Backups:** the **latest is never auto-selected**.
  - **iOS Software Updates:** `.ipsw`.
  - **iTunes Broken Downloads.**
  - **iTunes Cache:** artwork, regenerable.
- Smart selection: only broken and iOS-related files. The same sub-module exclusion semantics as System Junk apply.
- INFERRED → modern equivalents:
  - `~/Library/Application Support/MobileSync/Backup/*`: keep the newest per device;
  - `~/Library/iTunes/iPhone Software Updates`, `~/Library/iTunes/iPad Software Updates`;
  - Music/TV app caches under `~/Library/Caches/com.apple.Music`.

### 4.6 Trash Bins (topic-6)
- **Folders:** Local Mail Trash, Aperture Trash, iPhoto Trash, Photos Trash, Gemini Duplicates, **Startup Drive Trash** (including items removed from iCloud), **External Drive Trash** (one per external drive).
- **Everything is auto-added** to the cleanup list.
- **Empty** = an ordinary removal (default). **Remove Securely** (a pop-up next to Empty, after Review Files) overwrites with zeroes; the help claims recovery becomes impossible.
- INFERRED → **do not offer "secure erase" on APFS/SSD.** Overwriting doesn't reach the old blocks because of copy-on-write, snapshots and TRIM, so the claim can't be honoured. Apple removed Secure Empty Trash in 10.11 for this reason. Offer FileVault guidance instead (see 07 §Shredder).

### 4.7 Large & Old Files (topic-7)
- **Locations:** Home by default, plus any folder, internal or external drive, or **network folder**. Buttons: **Add Folder**, (x) per location, **Clear List**.
- Results: Reveal, Quick Look, Sort by. Origin icons mark files that live in iCloud Photos, a local Photos library or an iTunes library.
  - Deleting an iCloud Photos item removes it from iCloud **and** the local library.
- **Nothing is smart-selected.**
- **Actions** (pop-up next to the button): **Move to Folder**, **Move to Trash**, **Remove Immediately**, **Remove Securely**.
- INFERRED → we offer Move to Trash (default), Move to Folder…, and Delete Immediately (with confirmation). Photos-library items are routed to Photos (a "Large Media to Delete" album; §4.16) rather than deleted directly.

### 4.8 Uninstaller (topic-8)
- Shows all custom apps, **including those outside /Applications**.
- System apps are hidden. Ignore List › Uninstaller › "Ignore system applications" reveals them; they can then be **reset** but not uninstalled.
- **Capabilities:** reset an app to its initial state; remove an app with all its files; view unsupported apps; reset system apps.
- **View All Applications**; Sort by (e.g. **Last Launch Date** to find rarely used apps); **Action › Refresh**; search.
- **Nothing is selected by default.** Per app, choose **Complete Uninstallation** or **Application Reset** in the "Smart Selector" block. Reset selects only the items needed to return the app to a clean state.
- **The main button relabels itself:** **Uninstall** (whole apps), **Reset** (smart-selected files), **Remove** (mixed or individual files). Afterwards, **View All Apps** returns to the list.
- INFERRED → replicate the two smart selectors and the adaptive button label. Default sort is by size, with an optional "Last opened".

### 4.9 Maintenance (topic-9): per-task explanations
The task list and MacPaw's usage guidance, paraphrased. INFERRED → this drives our task descriptions and "recommended when" badges:

| Task | What it does (vendor) | When to run (vendor) | Our implementation on macOS 14+ (INFERRED) |
|---|---|---|---|
| Run Maintenance Scripts | The daily, weekly and monthly routines: temp-file deletion, log rotation, database rebuilds | Fine to run every day (fast) | `periodic` is gone in 15 Sequoia (see 02 §1.14; re-confirmed in the fact-check: a 15.6.1 host had no `/usr/sbin/periodic`, no `/etc/periodic` and no `com.apple.periodic-*` jobs, VERIFIED-3P https://github.com/AppliedIR/sift-mcp/blob/HEAD/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml). On 14, `periodic daily weekly monthly` via the helper, gated on `isExecutableFile(atPath: "/usr/sbin/periodic")`. On 15+, hide the task or replace it with log/temp cleanup |
| Repair Disk Permissions | Verifies and restores permissions | Only on access problems (can't move/delete files, apps showing "?" icons) | Obsolete under SIP. Offer `diskutil resetUserPermissions / $(id -u)` as an advanced action only |
| Verify Startup Disk | File-system check; if repair is needed, points to Recovery | Periodically, or on slow I/O or corrupted files | `diskutil verifyVolume /` (read-only). Warn that the system may be unresponsive for minutes (the CMM3 alert says so). Off by default |
| Speed Up Mail | Reindexes Mail's envelope database | Slow or broken Mail search; can take hours on big mailboxes; empty Junk/Trash first | **(corrected)** Default: quit Mail, then run SQLite `VACUUM;` on `~/Library/Mail/V*/MailData/Envelope Index` (FDA). This is what the CMM3 binary does (VERIFIED via 05 §4.x, CMM3 binary strings `Envelope Index` + `VACUUM;`). Heavier fallback, with confirmation: move `Envelope Index*` aside so Mail rebuilds it on next launch (VERIFIED-OSS via 05). V10 = macOS 13+; glob `V*` |
| Rebuild Launch Services Database | Fixes wrong default apps, wrong icons, duplicate "Open With" entries | On those symptoms | **(corrected)** The classic `lsregister -kill -r -domain local -domain system -domain user` **fails on current macOS**: `lsregister` answers that "-kill option has been removed because it was dangerous and no longer useful" and exits non-zero. Measured on macOS 26 (VERIFIED-3P: https://github.com/MadMartian/Scribobulate/blob/HEAD/packaging/macos/uninstall.sh; https://github.com/1tuz/Lead-Aggregator/blob/HEAD/docs/audits/2026-10-04/macos.md). `-domain` is also gone, replaced by `-all <comma list>` (VERIFIED-3P: https://github.com/kdeldycke/dotfiles/blob/HEAD/macos-config.sh). Use, as the user (no root): `lsregister -gc -r -f -all local,system,user`. Then, per 05 §4.x, unregister stale paths from `lsregister -dump` with `lsregister -u <path>`. Detect `-kill` support from `lsregister -h` only if older systems matter. Path: `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister` |
| Reindex Spotlight | Full reindex; Spotlight unavailable and the system busy meanwhile | On missing results or slow search | **(corrected)** `mdutil -E /` alone can rebuild only the sealed system volume's store and leave the user-data store untouched, because user files live on the separate `/System/Volumes/Data` store (VERIFIED-3P, measured: https://github.com/hemp/baremetal/blob/HEAD/dot_local/bin/spotlight.sh; also https://github.com/unixorn/tumult.plugin.zsh/blob/HEAD/bin/spotlight-reindex). Use `mdutil -E /System/Volumes/Data` (or `mdutil -a -E` for all volumes) via the helper (root). Check state with `mdutil -s /System/Volumes/Data` |
| Flush DNS Cache | Resets the resolver cache | Sites not loading; network slowdowns | `dscacheutil -flushcache; killall -HUP mDNSResponder` (root). VERIFIED via 05 (Mole source; CMM3 Agent binary used the same pair) |

- The help explicitly says the tasks have different recommendations and **don't all need to run at once**. **Action › Refresh** reloads the list.

### 4.10 Privacy (topic-90)
- **Browsers:** Safari, Google Chrome, Opera, Mozilla Firefox.
- **Per-browser items:** Autofill Values · Browsing History · Cookies · **Downloads History** (the list only; the files are kept) · HTML5 Local Storage · Saved Passwords · Tabs from Last Session.
- **Messengers:** Skype, Messages, AOL IM, Jabber, Yahoo, iMessage (conversation, call and file-transfer history).
- **Recent Items:** app, document and server recents, system-wide. The files themselves are untouched.
- **Select Items** shows details. **All browsers must be quit.**
- A **"Time range to clean"** filter shows items from a period; changing it asks to quit the browser again.
- After cleaning, saved logins must be re-entered, except Keychain-stored passwords.
- INFERRED → a per-browser "Quit to scan" button (`NSRunningApplication.terminate()` after confirmation).
  - Safari data lives in `~/Library/Safari` and `~/Library/Containers/com.apple.Safari/…`, needs FDA, and the browser must be closed.
  - **(corrected)** `WKWebsiteDataStore` is **not** a way to clear Safari's data. It manages only the calling app's own WebKit store. Safari's items must be handled as files.
  - Concrete Safari paths, from BleachBit's maintained Safari cleaner (VERIFIED-OSS: https://raw.githubusercontent.com/bleachbit/bleachbit/master/cleaners/safari.xml):
    - **Cookies:** `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`.
    - **History:** `~/Library/Safari/History.db` (+ `-wal`, `-shm`, `-lock`), `RecentlyClosedTabs.plist`, `TopSites.plist`.
    - **Downloads list:** `~/Library/Safari/Downloads.plist`.
    - **Last-session tabs:** `~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db` and `CloudTabs.db`.
    - **Autofill:** `~/Library/Safari/Form Values`.
    - **Site data:** `~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData/{Default,LocalStorage,IndexedDB}/`.
    - **Cache:** `~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari/`.
    - **Per-site preferences:** `~/Library/Safari/PerSitePreferences.db`.
    - INFERRED: `CloudTabs.db` syncs through iCloud, so deleting it locally does not clear other devices. Say so in the UI.
  - **Never touch saved passwords** in our build (Keychain or browser password stores). The risk outweighs the benefit; leave that to browsers.

### 4.11 Extensions (topic-91)
- **Groups:** Plugins (per parent app), Widgets, Login Items, Preference Panes, Screen Savers, Dictionaries, **Launch Agents**, Services, Siri (disable only, since it's a system app).
- **View All Extensions**, Sort by, Refresh, search.
- **Disable is reversible; Remove cannot be undone.** Nothing is auto-selected.
- To disable, hover the "Enabled" status, which turns into a **Disable** button.
- INFERRED → an Extensions tool under Applications covering:
  - Safari Web Extensions (via `pluginkit -m -p com.apple.Safari.web-extension`; read-only);
  - QuickLook (`qlmanage -m`). **(corrected/added)** Legacy `.qlgenerator` plug-ins are no longer loaded on macOS 15 Sequoia and later; Quick Look now uses app extensions (VERIFIED-3P: https://github.com/haokaiyang/Mac-QuickLook/blob/HEAD/README.md, citing Eclectic Light 2024-10-31; https://github.com/rdmpage/gis-quicklook/blob/HEAD/README.md). On 15+, list `~/Library/QuickLook` and `/Library/QuickLook` items as "inactive (unsupported on this macOS)". Enumerate Quick Look preview and thumbnail extensions with `pluginkit -m -p com.apple.quicklook.preview` and `-p com.apple.quicklook.thumbnail` (INFERRED extension-point IDs; verify on device);
  - Spotlight importers;
  - `~/Library/PreferencePanes`;
  - `~/Library/Screen Savers`;
  - Services (`~/Library/Services`);
  - Internet Plug-Ins;
  - Login/Background items (§3.12).
  - Disable means moving the item into an app-managed "Disabled" folder so it can be restored.

### 4.12 Shredder (topic-92)
- Removes items in an ordinary or secure way, and works even when Finder errors because the item is in use.
- **Select Files** or drag-and-drop; **Add Files**; checkboxes; Sort by; search; **Shred** (ordinary by default) or **Remove Securely**.
- INFERRED → keep it as a "Force Delete" tool (quit the owning process, unlock `uchg`, then delete) with **no "secure" claim** on SSD. Refuse system and critical paths; CMM3 alert: "Removing these files or folders may damage your system", §4.16.

### 4.13 Dashboard (topic-93)
- Real-time infographics for internal drives, RAM, battery and CPU. It also shows the Mac model and the **total amount cleaned**.
- **Disk graph categories:** Audio, Movies, Photos, Apps, Backups, Other, Used (fallback).
  - Shows **free** space and explains it differs from "available", which includes purgeable space.
  - Clicking the disk icon opens it in Finder. Double-clicking a segment runs a Spotlight search for that category.
- **Memory:** **Free Up**; legend Wired / Active / Inactive / Compressed; the icon opens Activity Monitor.
- **Battery:** charge, health, cycle count; the icon opens Energy Saver.
- **CPU:** percentage load; the icon opens Activity Monitor.
- **Health issues:** the button title changes to "N issues". A yellow triangle explains each issue with recommendations, and stays until the issue is resolved.
- INFERRED → this is our Activity/Health screen. Show "N issues" in the sidebar health pill. Always distinguish free from available (`volumeAvailableCapacityForImportantUsageKey`, macOS 10.13+, which counts purgeable space as available; VERIFIED-APPLE https://developer.apple.com/tutorials/data/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey.json).

### 4.14 CleanMyMac 3 Menu (topic-94)
- The icon appears at first launch and stays when the main app quits. Turn it on or off in Preferences › Menu; quit it from the gear menu. Most notifications are delivered through the Menu.
- **Metrics:**
  - Startup disk: free space, health, a min-free threshold; click opens Finder.
  - RAM: unused and total; click opens Activity Monitor.
  - Battery: charge, health, capacity.
  - Trash: system and external trash sizes, a max threshold; click opens the Trash.
  - The Menu's junk figure can differ from Trash Bins, because the module also counts app trashes.
- **Actions:** hover Memory → **Free Up**; hover Trash → **Empty Trash**.
- **Notifications:**
  - low free space;
  - Trash over its threshold;
  - an offer to uninstall correctly when an app is moved to the Trash;
  - disk failure precautions (SMART);
  - possible disk overheating;
  - battery failure;
  - heavy memory usage;
  - non-responding apps.
  - Every notification can be ignored or postponed.
- The Scheduler's reminder still fires even when the Menu is off.
- Settings detail: §5.2.

### 4.15 Ignore List behaviours (topics 2–8, plus strings)
Consolidated from the help topics and shipped strings (VERIFIED-D):
- Control-click any result → **Add to Ignore List**. A confirmation explains that the item will no longer be shown in scan results and can be managed in Preferences. It has a "Do not show this message again" option.
- Selecting an ignore-listed item for removal triggers a warning that removing it may affect system or app functionality.
- Adding something already covered by the **Safety Database** fails with "already in CleanMyMac's Safety Database" (single, some, or all variants).
- "Reset Ignore List to default" asks for confirmation, warning that the app may then scan and remove items previously ignored.
- Ignoring the startup-drive Trash **disables the Trash Monitor** alert, with a confirmation; un-ignoring re-enables it.
- INFERRED → port all five behaviours. The Safety-Database-conflict check maps to "already protected by built-in rules".

### 4.16 Alerts, confirmations and edge cases (shipped `Alerts.strings` and `Localizable.strings`)
Paraphrased catalogue (VERIFIED-D, `.../Resources/Base.lproj/Alerts.strings` and `Localizable.strings`). INFERRED → our confirmation and edge-case spec.
- **Destructive confirmations:**
  - permanently remove "X"? / all selected items? ("You can't undo this action");
  - permanently uninstall "X" and all related items?;
  - reset "X" by removing related items?;
  - permanently erase (Shredder)?
- **Module-specific warnings:**
  - Large & Old: a warning when several personal files are selected (the module doesn't suggest safe items; use it as a reference).
  - Uninstaller: a warning when several apps are selected (they will be gone completely).
- **Interruptions:**
  - stop scan? (results incomplete); stop cleanup? (some junk remains);
  - quit during scan or cleanup? (scan results lost / cleanup incomplete);
  - starting a new scan discards current results;
  - refresh discards the selection.
- **Running apps:**
  - "Quit %@ to Estimate" (privacy needs the browser closed);
  - "Some applications should be quit or N of junk will remain";
  - "Dependent applications should be quit…";
  - "Item was not removed because you didn't quit the related process".
- **Crash recovery:** a "could not quit normally last time" alert; cleanup processes may still be running and interrupting them risks data loss; offers **Complete All and Quit** or **Force Quit**.
- **Install location:**
  - "not running from the recommended Applications folder" → offers to install (copy) into /Applications, with an overwrite prompt;
  - "Features are disabled because CleanMyMac is running from a disk image" (Menu and Scheduler preferences).
- **Privileges:** "needs your permission to make changes required by its functionality" / "authorize … to enable/disable this extension and perform other operations which require Administrative rights".
- **Malware:** after uninstalling malware, a restart is required; some apps may misbehave until then. Offers **Restart**.
- **Self-uninstall:** selecting CleanMyMac itself in its Uninstaller warns that it will close and be removed completely. There was an optional uninstall survey.
- **Setapp:** selecting Setapp for uninstall warns that its apps will be selected too.
- **macOS compatibility:** "This copy does not support macOS %@" → upgrade prompt.
- **Extended logging:** a toggle to keep a detailed log of located/removed items for support. Securely erased files are not logged (Privacy prefs).
- **Photos:** Large & Old items in Photos are gathered into a "Large Media to Delete" album, to be deleted inside Photos; an unsupported-library message.
- **Shredder refusal:** "Some of the items you selected cannot be added to Shredder. Removing these files or folders may damage your system."

---

## 5. CleanMyMac 3 Preferences, tab by tab (shipped strings, fetched)

Source: `https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/en.lproj/<File>.strings` (VERIFIED-D). Toolbar tabs (from `Preferences.strings`): **General · Smart Cleanup · Scheduler · CleanMyMac 3 Menu · Updates · Ignore List · Privacy**.

### 5.1 General (`CMGeneralPreferencesViewController.strings`)
- **Warning Dialogs:** "Reset All Warnings" re-enables every "don't show again" dialog.
- **Sounds:** "Play sounds for main CleanMyMac 3 actions".
- **Animations:** "Disable for better performance".
- **Languages to keep:** "Don't remove the following languages from your system or applications:", an editable list with add and remove buttons. Tooltips call it the "Exclude List".
- **External Drives:** a pointer to a separate free utility for automatic external-drive cleanup.
- **Getting Started:** a help button.
- INFERRED → our General tab: Reset warnings; Sounds; Reduce animations (also honour the system Reduce Motion); a protected-languages list, if we ever offer language-file removal.

### 5.2 CleanMyMac 3 Menu (`CMMenuPreferencesViewController.strings`)
- Master ON/OFF switch. Description: quick look at key system readings plus easy access to Free Up RAM.
- **"Warn when free space is less than:"** a pop-up with a "Don't Warn" option and sizes (the two pop-ups together list 500 MB, 1, 2, 3, 5, 10, 15, 20, 30, 50, 100 GB).
- **"Notify when Trash size exceeds:"** a pop-up with "Don't Notify" plus sizes.
- **Uninstaller:** "Offer to correctly uninstall applications" (an app moved to the Trash triggers the offer).
- **App monitor:** "Notify about hung applications" (offers Force Quit).
- **Reset Health and Monitoring:** "Reset All Warnings".
- These options are disabled when running from a disk image.
- INFERRED → defaults for us:
  - free-space warning at **10 GB** or 10%, whichever is larger;
  - Trash warning at **5 GB**;
  - the uninstall offer and the hung-app monitor on by default;
  - every notification gets "Ignore for now" and "Ignore forever" (the CMM3 Menu had "Ignore For Now" / "Ignore Forever", per 08).

### 5.3 Smart Cleanup (`CMSmartCleanupPreferencesViewController.strings`)
- "Specify the items you would like to include to Smart Cleanup and module scans:" (a checkbox tree).
- Footer: deselecting an entire module removes it from Smart Cleanup but keeps it available for its own scan.
- INFERRED → our Settings › Scanning uses the same footer semantics (§4.1).

### 5.4 Ignore List (`CMIgnoreListPreferencesViewController.strings`)
- Header: "View and manage items that were earlier excluded from scan results". Footer: "All changes take effect after a new scan."
- **Sub-tabs and their lists:**
  - **System Cleanup:** "Files and applications to ignore".
  - **Photo/iPhoto:** "Photo cache groups to ignore", "Ignore RAW photos", "Add Photo Library".
  - **Mail:** "Attachments and downloads to ignore".
  - **iTunes.**
  - **Trashes:** "Select volumes to add their Trash folders to Ignore List"; "Add Volume"; "All mounted volumes are already in your Ignore List".
  - **Large & Old Files:** "Files, folders, and file groups to ignore", plus "File extensions to ignore".
  - **Uninstaller:** "Applications that are hidden from the Uninstaller list" plus "Ignore system applications".
  - Also: "Volumes, photo libraries and Mail accounts to ignore".
- **Actions:** Add items (+), Remove items (−), "Reveal in Finder", "Quick Look", "Remove from List", and a reset menu with "Reset Selected Ignore List" and "Reset All Ignore Lists".
- INFERRED → our Ignore List supports these rule kinds:
  - path or file;
  - group (e.g. "Kind: Movies" in Large & Old);
  - file extension;
  - volume (for trashes);
  - mail account;
  - app bundle ID;
  - system-apps toggle.
- Each category gets reset-selected and reset-all.

### 5.5 Scheduler (`CMSchedulerPreferencesViewController.strings`)
- **"Remind me about regular cleanup:"** Never · Weekly · Once in two weeks · Monthly · Once in three months · Once in six months · Annually.
- **"When launching from the Scheduler notification:"** "Simply launch CleanMyMac 3" or "Launch and start full scan".
- Disabled when running from a disk image.
- INFERRED → our reminder: the same frequency set plus a "start Checkup on open" option. Implement with `UNCalendarNotificationTrigger` or a LaunchAgent `StartCalendarInterval`. **No unattended cleaning by default** (the consumer KB documents reminders only).

### 5.6 Updates (`CMUpdatesPreferencesViewController.strings`)
- "Check for updates automatically"; "Download updates in the background"; "Check For Updates" button; "Last check:" (Never).
- "Offer to update to Beta versions when available", with a data-loss caution.
- **"Enable background updates of … Safety Database"**, described as vital for cleanup efficiency and compatibility with other software.
- INFERRED → keep "rules database updates" separate from app updates in our UI, even if a personal build ships rules inside the bundle.

### 5.7 Privacy (`CMPrivacyPreferencesViewController.strings`)
- "Share anonymous usage data" checkbox (vendor asks users to keep it on; no personal info is shared).
- **Extended Logging:** "Gather detailed logs of all cleaned items". Securely erased files are not logged.
- INFERRED → we ship **no telemetry** (see 10 §9). We do keep a **local removal log**, on by default, with paths and sizes, viewable and exportable. This is our "My Activity" source of truth and a recovery aid.

---

## 6. Per-page digest: CleanMyMac CLI wiki (MacPaw, fetched)

Source: `https://raw.githubusercontent.com/wiki/MacPaw/cleanmymac-cli/<Page>.md` and `https://raw.githubusercontent.com/MacPaw/cleanmymac-cli/HEAD/README.md` (VERIFIED-D). MacPaw states the CLI's detection logic is **shared with the desktop app**, so this is the best first-party view of current rules.

### 6.1 Home
- Install: `brew install --cask cleanmymac-cli` (the tap is `macpaw/taps`). Run `cleanmymac` (interactive) or `cleanmymac --help`.
- (added) The tap cask is version **1.0.0**, downloaded from `https://cli.cleanmymac.com/1.0.0/CleanMyMac-CLI-1.0.0.zip`, `depends_on macos: :big_sur`. Both `cleanmymac` and `cmm` link to `CleanMyMac_5_CLI.app/Contents/MacOS/CleanMyMac_5_CLI`. VERIFIED-D (re-fetched).
- Public beta; docs evolve.

### 6.2 Getting Started
- **Requirements:** macOS 11+, Homebrew, Terminal.
- The alias `cmm` equals `cleanmymac`.
- First steps: `cleanmymac analyze`, then `cleanmymac clean`. Items are shown before removal.

### 6.3 Commands

| Command | Behaviour |
|---|---|
| `clean` | All categories |
| `clean junk` | User logs, Xcode DerivedData, Device Support, Module Cache, Documentation Cache, other Xcode junk |
| `clean dev` | Caches from Homebrew, npm, Yarn, pnpm, pip, Poetry, uv, Cargo, Go, CocoaPods, Docker, VS Code, JetBrains, Maven, Gradle, Bun, Deno, mise |
| `clean ai` | AI-tool artifacts (e.g. a "Claude" entry appears in the README sample) |
| `clean trash` | System Trash and mounted-volume trash |
| `purge [path]` | Defaults: `~/Projects ~/Code ~/dev ~/GitHub ~/Workspace`. Detects `node_modules .next .turbo target .build .venv venv __pycache__ Pods DerivedData vendor cmake-build-*`. Grouped by project; **>7 days pre-selected**, newer unchecked; source code never targeted |
| `analyze [path]` | Read-only interactive explorer; arrows to navigate; `O` reveals in Finder; deletion needs explicit selection plus confirmation |
| `optimize` / `optimize ram` / `optimize purgeable` | Releases inactive memory ("no sudo required"); asks macOS to release purgeable space |
| `config` | Preferences, including an analytics toggle; persists |
| `ignore add/list/remove <path>` | Excluded from `clean`, `purge` and `analyze` until removed |
| `--force` | Skips confirmation (warned) |

- **README sample result screen** (VERIFIED-D): "N GB of items found"; category rows with ■/□ selection and sizes (System Junk, Dev Tools, **AI Junk shown unselected** in the sample); "N items selected (size)"; keys ↑↓←→ / Enter / Space (toggle) / A (select all) / Esc / Q.
- **Completion screen:** "Cleanup complete!", per-category ✓ lines with sizes, a total "cleaned", "N items removed".

### 6.4 Safety and Privacy
- Scan and review first. Nothing is deleted until confirmed.
- Protected system locations are excluded. Rules are shared with the desktop app.
- Purge protection: the 7-day rule; results grouped by project.
- Analyze is read-only.
- The ignore list protects paths.
- `--force` warning.
- **Privacy:** processing is local; no source or personal files are uploaded; analytics can be disabled (`cleanmymac config`); the privacy policy is at `https://macpaw.com/legal/cleanmymac-privacy-policy`.
- **Security reports:** `security@macpaw.com`, private disclosure.

### 6.5 FAQ
- The CLI is not the desktop app; it is terminal-first and developer-focused.
- **Proprietary**, owned by MacPaw Way Ltd. The GitHub repo is for docs, releases and issues only.

### 6.6 Guides
- **Clean Xcode cache:** `clean junk` covers DerivedData, Device Support, Module Cache, Documentation Cache. `purge` covers in-project build artifacts. The guide says not to start with `--force`.
- **Clean developer caches:** the tool list above.
- **Old node_modules:** the purge list above.
- **Analyze disk usage:** "Analyze first, clean second."
- **AI-tool artifacts:** `clean ai`; users can request support for more tools.
- INFERRED → we copy the **philosophy** (age-gated pre-selection, analyze-first, an ignore list that applies everywhere), not the wording or names. A "Developer" category in our Cleanup (dev caches) plus a "Projects" purge tool fits the Mac mini use case.

---

## 7. Updater FAQ (app self-update), consolidated

- **5.x direct edition:** Sparkle appcast at `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml` (cask livecheck, VERIFIED-D); zips at `…/releases/CleanMyMac5_<build>.zip`. The cask marks `auto_updates true`.
- The older DevMate-hosted appcast copy (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml`) lists 23 builds from 5.0.0 (2024-10-15) to 5.3.1 (2026-01-28). VERIFIED-D. It shows:
  - `sparkle:minimumSystemVersion` 11.0;
  - `sparkle:deltas` (delta updates);
  - per-language `releaseNotesLink`s;
  - full zips of roughly 185–197 MB.
  - (added in the fact-check, VERIFIED-D):
    - delta enclosures carry `sparkle:deltaFrom` and point to `dl.devmate.com/com.macpaw.CleanMyMac5/<build>/<timestamp>/<fromBuild>.delta`; full zips are at `…/CleanMyMac5-<build>.zip`;
    - **no item carries `sparkle:edSignature` or `sparkle:dsaSignature`**. INFERRED: the DevMate-era updater relied on Apple code-signature checks of the downloaded bundle, not Sparkle's EdDSA. **Our build must not copy that.** Any appcast we ever publish is EdDSA-signed;
    - release cadence is 23 builds in about 15 months (2024-10-15 → 2026-01-28). The Homebrew cask is already at **5.7.1**, build `50701.0.2609301754` (build stamp 2026-09-30), served from `updates.cleanmymac.com`, so the DevMate copy is a stale mirror.
- **Settings toggle:** "Automatically keep CleanMyMac up to date" (5.x General, VERIFIED-KB). CMM3 had: automatic check, background download, beta channel, Safety Database background updates (§5.6).
- **Self-updater process:** a user LaunchAgent `com.macpaw.CleanMyMac5.Updater` waking every 6 h (VERIFIED-D path from cask; interval VERIFIED-KB X processes and VERIFIED via 10).
- **App Store and Setapp editions** update through their stores.
- INFERRED → a personal build needs no updater. If one is added later, use Sparkle 2 inside the app with an EdDSA-signed appcast; no separate LaunchAgent.

---

## 8. Troubleshooting digest (what the help covers, plus our design)

| Symptom | What MacPaw's help says | Status | Our implementation (INFERRED) |
|---|---|---|---|
| App doesn't appear in the Full Disk Access list | Run a scan first so components register, then toggle in Privacy & Security › FDA | VERIFIED-KB (full-disk-access) | Trigger a protected read before deep-linking. Show our icon in a draggable helper panel. Poll for the grant |
| Scans incomplete, or mail attachments not scanned for malware | Grant FDA | VERIFIED-KB | Health "Requires Attention" plus a banner in affected modules |
| Menu won't open, or the toggle does nothing | Allow background items in Login Items & Extensions | VERIFIED-KB (allow-background-items) | `SMAppService.status` check; "Open Login Items" button |
| Menu shows no elements | Dedicated KB article exists (steps not retrieved) | VERIFIED-3P / GAP | Placeholder state; restart-agent action |
| Disk health or temperature missing | App Store edition sandbox; not available | VERIFIED-KB | Explain "not available for this disk"; don't show 0 °C |
| Admin password prompt / helper | The Agent installs lazily on the first root task; idle otherwise | VERIFIED-KB (cleanmymac-agent, helper-tool) | Explainer sheet before the prompt. Advanced › Helper status, Reinstall, Remove. Version-pin the helper (10 §11.3) |
| Helper "not installed" or failing | Article exists; wording not retrieved | GAP (still open) | If the XPC connection fails: re-`register()`; if `.requiresApproval`, deep-link; offer "Run without helper" (skip root tasks). The vendor's blessed-helper repair path is described (INFERRED) in §3.24 |
| Item not removed | Related process wasn't quit | VERIFIED-D (CMM3 strings) | Pre-flight: list running owners (`NSRunningApplication`, plus `lsof` for files) and offer Quit / Skip |
| Privacy shows nothing | Browsers must be quit ("Quit X to Estimate") | VERIFIED-D / VERIFIED-KB | Per-browser Quit button; re-scan automatically after it quits |
| Scan feels stuck or slow | "May take a while on older or heavily used Macs"; Stop asks for confirmation (results incomplete) | VERIFIED-KB (smart-care) / VERIFIED-D. No dedicated "scan stuck" KB article was found in the fact-check either (GitHub-wide search of third-party KB citations turned up none) | Per-scanner progress, a 30 s watchdog per scanner, Skip this category, and partial results kept. INFERRED common causes to test for: FDA missing (TCC prompts or denials stall enumeration), network or cloud volumes (`URLResourceKey.volumeIsLocalKey` = false), dataless iCloud or File Provider files (never read their contents; skip `isUbiquitousItem` downloads), huge Mail stores, and Photos/Music library packages (treat as opaque) |
| App closed mid-cleanup last time | "Could not quit normally" alert; Complete All and Quit / Force Quit | VERIFIED-D | Journal of planned deletions. On next launch, report what was and wasn't done |
| Running from DMG / not in /Applications | Background features disabled; offer to copy into /Applications | VERIFIED-D | "Move to Applications" on first launch (required for SMAppService stability) |
| Malware removed but system misbehaves | Restart required | VERIFIED-D | Offer Restart after confirmation. (corrected/added) Scripting "System Events" to restart sends an Apple Event, which needs the **Automation** TCC grant (`NSAppleEventsUsageDescription` plus a one-time prompt) (INFERRED). Fall back to "Restart from the Apple menu" text if the user declines |
| Unsupported macOS | "This copy does not support macOS X" upgrade prompt | VERIFIED-D | Gate unsupported features by `ProcessInfo.operatingSystemVersion` (e.g. periodic scripts ≤13) |
| Too many reminders | Turn off Recommendations (Settings › Menu) or set the reminder frequency | VERIFIED-KB / VERIFIED-D | Same toggles, plus "Ignore forever" per alert |

---

## 9. "How to uninstall CleanMyMac completely": component list and paths

The 5.x KB lists "uninstalling" under Basics (VERIFIED-KB, concepts-and-usage), but the article body wasn't retrieved (GAP). CMM3 could uninstall **itself** from its own Uninstaller, after a warning that it would close and be removed (VERIFIED-D, Alerts.strings). The footprint below comes from package metadata and real-install observations.

### 9.1 CleanMyMac 5.x (direct edition)
VERIFIED-D: Homebrew cask `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb` (5.7.1, `50701.0.2609301754`) and Fleet's script `https://raw.githubusercontent.com/fleetdm/fleet/HEAD/ee/maintained-apps/inputs/homebrew/scripts/cleanmymac-uninstall.sh`.

| Component | Path / identifier | Removal step |
|---|---|---|
| App | `/Applications/CleanMyMac_5.app` (Finder shows "CleanMyMac") | Quit `com.macpaw.CleanMyMac5`, then delete |
| Menu agent | launchd label `com.macpaw.CleanMyMac5.Menu`; login item "CleanMyMac 5 Menu" | `launchctl remove`; delete the login item |
| Health Monitor | launchd label `com.macpaw.CleanMyMac5.HealthMonitor` | `launchctl remove`; quit |
| Privileged helper | `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` | `sudo rm` |
| Helper daemon plist | `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` | Delete (cask: zap only). The `sudo launchctl bootout system/com.macpaw.CleanMyMac5.Agent` before it is our INFERRED addition; neither package script boots the daemon out |
| Self-updater | `~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist` | Unload, then delete |
| Shared data | `/Users/Shared/CleanMyMac_5` | Delete |
| App Support | `~/Library/Application Support/CleanMyMac_5` | Delete |
| Caches | `~/Library/Caches/com.macpaw.CleanMyMac5` | Delete |
| Group container | `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5` | Delete |
| App Scripts | `~/Library/Application Scripts/S8EX82NJP6.com.macpaw.CleanMyMac5` | Delete |
| HTTP storage | `~/Library/HTTPStorages/com.macpaw.CleanMyMac5` and `….binarycookies` | Delete |
| Logs | `~/Library/Logs/com.macpaw.CleanMyMac5` | Delete |
| Preferences | `~/Library/Preferences/com.macpaw.CleanMyMac5.plist` | Delete (`defaults delete` first, so `cfprefsd` doesn't rewrite it) |
| Saved state | `~/Library/Saved Application State/com.macpaw.CleanMyMac5.savedState` | Delete |

- **How the two package scripts split the work (re-fetched, VERIFIED-D):**
  - The cask's `uninstall` stanza does four things:
    - removes the launchd labels `…HealthMonitor` and `…Menu` (`launchctl`);
    - quits the app, the HealthMonitor and the Menu;
    - removes the "CleanMyMac 5 Menu" login item;
    - deletes `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`.
  - The Agent's LaunchDaemon plist and the Updater LaunchAgent plist appear **only in `zap`**. Homebrew trashes them only on `--zap`.
  - The cask declares `depends_on :macos` with no minimum, and `auto_updates true`.
  - Fleet's script:
    - runs `launchctl remove` for the HealthMonitor and Menu labels, first as the user, then with `sudo`;
    - deletes a matching `.plist` in `/Library` or `~/Library` LaunchAgents/LaunchDaemons only if one exists;
    - quits apps via `osascript … to quit`, with a 10 s timeout, skipped when no GUI user is logged in;
    - `sudo rm -rf` the helper and `/Applications/CleanMyMac_5.app`;
    - then moves the remaining items into the console user's `~/.Trash`.
- Other components known from sibling 10 (VERIFIED via 10):
  - a **Finder Sync extension** inside the bundle (`com.macpaw.CleanMyMac5.FinderSyncExtension`), which goes with the app. Being sandboxed, it leaves `~/Library/Containers/com.macpaw.CleanMyMac5.FinderSyncExtension` and `~/Library/Application Scripts/com.macpaw.CleanMyMac5.FinderSyncExtension` behind, and neither package script lists them (VERIFIED via 10);
  - **(corrected)** a **Moonlock Endpoint-Security system extension** (`/Library/SystemExtensions/<UUID>/com.macpaw.moonlock.engine.systemextension`). Whether CMM5 installs it is **unresolved**. One process capture shows it beside a running CMM5. A later full 853-process capture of a CMM5 Mac shows no such extension. It may belong to the standalone Moonlock app (see 04 §1.6, 10 §2.1). Neither package script mentions it.
- **(added, gap 7) How a system extension goes away, if one is present:**
  - **Apple:** "The system automatically uninstalls any system extensions when the user deletes the corresponding app". The host can also submit `OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier:queue:)` (macOS 10.15+). VERIFIED-APPLE: https://developer.apple.com/tutorials/data/documentation/systemextensions/installing-system-extensions-and-drivers.json and `…/ossystemextensionrequest/deactivationrequest(forextensionwithidentifier:queue:).json`.
  - **(corrected)** `systemextensionsctl uninstall <teamID> <bundleID>` is **refused whenever SIP is on**, so it is not a real uninstall route. VERIFIED-3P, measured on macOS 27 (2026-09-17): https://github.com/jo-duchan/tapflow/blob/HEAD/docs/operate/network-extension.md.
  - The same field tests found that deleting the host app alone left a (network) extension running. What worked: System Settings › General › Login Items & Extensions › (extension category) › ⋯ › **Delete Extension**, then a restart. Until then `systemextensionsctl list` shows `terminated waiting to uninstall on reboot`. VERIFIED-3P (same source; 06 §3.13 records this conflict with Apple's wording).
  - INFERRED: the vendor most likely deactivates through its own app (deactivation request) before self-uninstall. If the user drags the app to the Trash instead, macOS removes the extension at the next restart, or the user deletes it in System Settings.
  - INFERRED → our Uninstaller handles an app that owns a system extension like this: run `systemextensionsctl list` before and after; if the extension lingers, show "Finish in System Settings › Login Items & Extensions → Delete Extension, then restart".
- Fleet's script moves user-data items **to the Trash** with a timestamp **and random** suffix (`<name>_<YYYY-MM-DD-epoch>_<rand>`) rather than deleting them, a safety pattern worth copying (VERIFIED-D).

### 9.2 CleanMyMac X (4.x)
- Community cask `cleanmymac-x` 4.15.8. VERIFIED-D: `https://raw.githubusercontent.com/letuanhai/homebrew-tap/HEAD/Casks/cleanmymac-x.rb`.
  - App `CleanMyMac X.app`.
  - launchd labels `com.macpaw.CleanMyMac4.{Agent,HealthMonitor,Menu,Scheduler,Updater}`; login item "CleanMyMac 4 Menu".
  - Delete `/Library/LaunchDaemons/com.macpaw.CleanMyMac4.Agent.plist` and `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac4.Agent`.
  - **Zap list:**
    - `/Users/Shared/CleanMyMac X`, `/Users/Shared/CleanMyMac X Menu`;
    - `~/Library/Application Scripts/com.macpaw.CleanMyMac4.CleanMyMacWidget` (a **widget** extension existed);
    - `~/Library/Application Support/CleanMyMac X*`;
    - two `com.apple.sharedfilelist` recent-documents `.sfl*` entries (app and scheduler);
    - `~/Library/Caches/CleanMyMac 4`, `~/Library/Caches/com.macpaw.CleanMyMac4*`;
    - the Help-viewer index cache `~/Library/Caches/com.apple.helpd/SDMHelpData/Other/English/HelpSDMIndexFile/com.macpaw.CleanMyMac4.help*` (confirms X shipped an Apple Help Book);
    - `~/Library/Containers/com.macpaw.CleanMyMac4.CleanMyMacWidget`;
    - `~/Library/Group Containers/*.com.macpaw.CleanMyMac4*`;
    - `~/Library/HTTPStorages/com.macpaw.CleanMyMac4*`;
    - `~/Library/LaunchAgents/com.macpaw.CleanMyMac4*`;
    - `~/Library/Logs/CleanMyMac 4.log`, `~/Library/Logs/CleanMyMac X Menu`, `~/Library/Logs/com.macpaw.CleanMyMac4`;
    - `~/Library/Preferences/com.macpaw.CleanMyMac4*`;
    - `~/Library/WebKit/com.macpaw.CleanMyMac4`;
    - **`~/Pictures/Photos Library.photoslibrary/private/com.macpaw.CleanMyMac4`**, a folder the app wrote *inside the Photos library*.
- The X **Chinese edition** cask `cleanmymac-zh` 4.15.14 has the same shape under `com.macpaw.zh.CleanMyMac4.*`, app `CleanMyMac-X.app`, homepage mycleanmymac.com. VERIFIED-D: `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb`.
- **Observed on real installs** (VERIFIED-3P):
  - A 2018 listing shows `~/Library/LaunchAgents/com.macpaw.CleanMyMac4.HealthMonitor.plist` and `/Library/LaunchDaemons/com.macpaw.CleanMyMac4.Agent.plist` (https://raw.githubusercontent.com/FaiChou/blog/HEAD/content/blog/mac-startups/index.md).
  - A 2026 server-cleanup guide lists:
    - `~/Library/Application Support/CleanMyMac X`, `… X Menu`, `… X HealthMonitor`;
    - `~/Library/Preferences/com.macpaw.CleanMyMac4.plist`, `….Menu.plist`, `….HealthMonitor.plist`;
    - `~/Library/Group Containers/com.macpaw.CleanMyMac4`.
    - Source: https://raw.githubusercontent.com/minniexcode/hexo_ash/HEAD/source/_posts/other/mac-server-setup-and-cleanup-guide.md.
  - The `sfltool dumpbtm` view (Menu as an app login item; Health Monitor as a nested login item whose parent is the Menu) is in sibling 10 §2.2.
- **Setapp edition:** an Updater LaunchAgent `com.macpaw.CleanMyMac-setapp.Updater` with `StartInterval 21600`, pointing into `~/Library/Application Support/CleanMyMac Setapp/…` (VERIFIED via 10).
- **Mac App Store edition:** sandbox container `~/Library/Containers/com.macpaw.CleanMyMac-mas*` and `S8EX82NJP6.com.macpaw.CleanMyMac-mas` group/scripts. TCC lists `S8EX82NJP6/com.macpaw.CleanMyMac-mas` (VERIFIED via 10). The App Store edition has no Agent or Updater (VERIFIED-KB via 02).
- A third-party "uninstall any version" script also tries `/Library/LaunchAgents/com.macpaw.CleanMyMac4.Agent.plist`, a Scheduler **LaunchDaemon**, kexts and `/private/var/db/receipts/com.macpaw.*`. These guesses are not corroborated by the casks, so **don't rely on them** (VERIFIED-3P, https://raw.githubusercontent.com/Andrei-Barwood/kuwagga/HEAD/01%20-%202025/01%20-%20Junio%20-%202025/29%20de%20junio%20-%202025/01_uninstall_cleanmymac.zsh).

### 9.3 CleanMyMac CLI
- VERIFIED-D (`https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb`): `CleanMyMac_5_CLI.app`; binary symlinks `cleanmymac` and `cmm`; zap `~/Library/Application Scripts/S8EX82NJP6.com.macpaw.CleanMyMac5.CLI` and `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5.CLI`. Requires macOS 11 (Big Sur).

### 9.4 Lessons for our app's own uninstall (INFERRED)
1. Provide **App menu › Uninstall <App>…**. It should:
   - list every component it will remove;
   - `SMAppService.unregister()` the daemon, agent and login item;
   - remove the helper and its plist (through the helper's own "uninstall self" verb, then the daemon exits);
   - delete the app-group container, caches, logs, preferences (`defaults delete`), saved state and HTTP storages;
   - move the bundle to the Trash and quit.
2. **Never write inside other apps' data stores.** X wrote into the Photos library's `private/` folder; we should not.
3. Keep our footprint **small and discoverable**: one app-group container, one log folder, no `/Users/Shared` folder, no recent-documents `.sfl` entries. Use reverse-DNS names that match the bundle ID, so our own Leftovers engine finds everything.
4. Our Uninstaller must detect the vendor patterns above as test cases:
   - Team-ID-prefixed group containers;
   - `HTTPStorages/<id>.binarycookies`;
   - nested login items;
   - `PrivilegedHelperTools` + `LaunchDaemons` pairs;
   - system extensions;
   - widget `Containers`;
   - help-viewer caches under `com.apple.helpd`.

---

## 10. Privacy FAQ (data handling), consolidated

- **CMM3:**
  - an opt-out "Share anonymous usage data" checkbox;
  - extended logging is opt-in, for support;
  - securely erased files are never logged.
  - VERIFIED-D (§5.7).
- **CLI:** local processing; no source code or personal files uploaded; analytics toggle in `config`. VERIFIED-D (§6.4).
- **Privacy policy URL:** `https://macpaw.com/legal/cleanmymac-privacy-policy` (cited by the CLI wiki; not fetched). VERIFIED-D (link).
- **Analytics hosts** (`api-lytics.macpaw.com` and others) are in sibling 10 §9 (VERIFIED via 10).
- **Smart Insights** runs the Apple Foundation Model **on-device** (VERIFIED-KB, via 01).
- **Email Cleanup** uses Gmail OAuth, and every action is confirmed (VERIFIED-KB, via 01).
- INFERRED → our privacy statement in Help: no network calls except the optional rule-database update and explicitly user-initiated cloud/email features; no analytics; local logs only, deletable from Settings.

---

## 11. Build-ready requirements distilled from the help centre (INFERRED)

1. **Uniform module page:** header (title, one-line purpose, "?" help) → big **Scan** button → progress with per-category status → result summary (size and count, pre-selected per rules) → **Review** list (search, sort, group, Select/Deselect All, hover Reveal and Quick Look, context menu Ignore) → primary action button whose label reflects the selection (Clean / Remove / Uninstall / Reset / Run) → completion screen (freed space, items, **Start Over**).
2. **Pre-selection policy table** (source in brackets):
   - **Auto:** caches, logs (§4.2); trashes (§4.6); unmodified mail attachments (§4.4); broken downloads (§3.36); iOS backups except the newest (§4.5); document versions per the 4-h rule (§4.2); threats (§3.14).
   - **Never auto:** Large & Old (§4.7), Uninstaller (§4.8), Extensions (§4.11), Leftovers (§4.2), Xcode Module Cache and Archives (§4.2), RAW photos (§4.3), Spotify and Gradle caches (§3.6), project artifacts newer than 7 days (§6.3).
3. **Settings tabs:** General · Scanning · Ignore List · Protection · Menu · Notifications/Reminders · Updates/Rules · Privacy & Logs · Advanced (helper, FDA, reset).
4. **Every confirmation dialog in §4.16** gets an equivalent, with "Don't show again" plus a global "Reset All Warnings".
5. **Permissions centre** (Advanced): FDA, Background items, Helper, Notifications, Automation (if used). Each shows status plus a fix button.
6. **Offline Help** with pages mirroring §2.1's structure plus Troubleshooting (§8) and Uninstall (§9.4).

---

## 12. Naming, branding and copy guidance

- Do not reuse MacPaw names or labels as product names: "CleanMyMac", "Smart Care", "Smart Cleanup", "My Clutter", "Space Lens", "Moonlock", "The Menu", "Assistant" (as branding), "Safety Database" (as a proper noun).
- Use our own: e.g. Checkup, Clutter, Space Map, Rules Database, Monitor.
- Generic feature words like "System Junk", "Large & Old Files", "Trash Bins", "Ignore List", "Uninstaller", "Maintenance" are common industry terms. They are acceptable if we write our own descriptions. Prefer our own phrasing where it's easy: "Ignored Items", "Big & Stale Files".
- All help text in our app must be original. This report paraphrases MacPaw help for engineering purposes only.

---

## 13. Gaps (could not be retrieved this session)

Status after the fact-check pass is in brackets.

1. Full text of these 5.x KB articles: `cleanmymac-helper-tool` (exact troubleshooting steps), `menu-no-elements`, `general` (any options beyond Updates), `my-tools`, `space-lens-results`, `large-and-old`, and the "uninstalling CleanMyMac" article (exact component list as MacPaw states it). [**Still open.** macpaw.com is still blocked. GitHub code search found only titles: menu-no-elements is "Troubleshoot the CleanMyMac Menu not loading correctly". It also found one more slug, `support-tool-safety` (§2.1). The helper repair path is now described as INFERRED from the SMJobBless evidence (§3.24). The package-level component list was re-verified (§9.1).]
2. X KB `extensions`, `uninstaller`, `shredder`, `space-lens` (full text). [**Still open**; the CMM3 Help stand-ins remain the best source. The CMM3 Uninstaller and Maintenance topics were re-fetched and match §4.]
3. A **"scan stuck"** article: none was located in any source available to this track. [**Still none found.** Likely causes and our watchdog design were added to §8.]
4. Whether the 5.x Settings window still has a **Notifications** tab, and its exact options. [**Partly answered (weak).** A third-party replica's tab strip includes Notifications, Disk Access and Analytics (§3.28). Its options are still unknown; X's options are in §3.42.]
5. Updater-module FAQ for 5.x (how "Custom Updates" are discovered; whether updates install silently or open the vendor updater). [**Partly answered.** The macOS-compatibility filter, Microsoft AutoUpdate scanning and the top-outdated-apps notification are known (§3.41). The discovery mechanism and silent-vs-handoff are still unverified; our reading is INFERRED.]
6. Smart-selection rule for which duplicate copy is kept. [**Partly answered (indirect).** MacPaw's Gemini 2 rules (Automatically/Newest/Oldest/Any, Never Select, Remove Last Instance warning) are documented 3P. The CleanMyMac rule itself is unknown (§3.8).]
7. Exact Moonlock system-extension deactivation on uninstall. [**Reframed.** It is unresolved whether CMM5 installs the extension at all. The macOS mechanics are now verified: deleting the app should remove it per Apple; host deactivation request; `systemextensionsctl uninstall` refused with SIP on; System Settings "Delete Extension" plus restart (§9.1).]
8. (added) The **health-score numeric cutoffs** (Excellent → Critical). [**Still open**; no source found. Our rubric stays INFERRED (01 §11).]

**To close these gaps** in a follow-up run with network access, fetch in this order:
- `…/knowledgebase/cleanmymac-helper-tool`, `menu-no-elements`, `general`, `uninstaller`, `space-lens-results`, `large-and-old`;
- the KB search page for "uninstall";
- `…/cleanmymac-x/knowledgebase/extensions`.

---

## 14. Sources

**Fetched directly this session (VERIFIED-D):**
- CleanMyMac 3 Help Book (MacPaw-authored), 16 pages: `https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/{index,topic-1…topic-9,topic-90…topic-94}.html`
- CleanMyMac 3 shipped strings:
  - `…/CleanMyMac%203.app/Contents/Resources/en.lproj/{Preferences,CMGeneralPreferencesViewController,CMSmartCleanupPreferencesViewController,CMSchedulerPreferencesViewController,CMMenuPreferencesViewController,CMUpdatesPreferencesViewController,CMIgnoreListPreferencesViewController,CMPrivacyPreferencesViewController}.strings`
  - `…/Resources/Base.lproj/{Alerts,Localizable}.strings`
  - `…/Contents/_CodeSignature/CodeResources`
- MacPaw CLI: `https://raw.githubusercontent.com/MacPaw/cleanmymac-cli/HEAD/README.md`; wiki pages `https://raw.githubusercontent.com/wiki/MacPaw/cleanmymac-cli/{Home,Getting-Started,Commands,Safety-and-Privacy,FAQ,Clean-Xcode-Cache-and-DerivedData-from-Terminal,Clean-Developer-Caches-on-macOS,Find-and-Remove-Old-node_modules-on-Mac,Analyze-Disk-Usage-on-macOS-from-Terminal,Clean-AI-Tool-Artifacts-on-macOS}.md`
- Homebrew casks:
  - `https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb`
  - `…/Casks/c/cleanmymac-zh.rb`
  - `https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb`
  - `https://raw.githubusercontent.com/letuanhai/homebrew-tap/HEAD/Casks/cleanmymac-x.rb`
- Fleet uninstall script: `https://raw.githubusercontent.com/fleetdm/fleet/HEAD/ee/maintained-apps/inputs/homebrew/scripts/cleanmymac-uninstall.sh`
- CleanMyMac 5 Sparkle appcast (DevMate S3): `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml`
- CVE list search (GitHub code search over `CVEProject/cvelistV5` and `github/advisory-database`). It confirmed the CleanMyMac CVE set documented in 10 §3.3. The only other MacPaw CVEs are for Encrypto and XADMaster, not CleanMyMac.

**MacPaw help-centre URLs (VERIFIED-KB, via sibling reports 01–12):**
- 5.x: https://macpaw.com/support/cleanmymac/knowledgebase/ followed by: `smart-care`, `concepts-and-usage`, `missing-features`, `feature-plans`, `editions`, `purchase-options`, `installation-activation`, `upgrade`, `operating-systems`, `full-disk-access`, `background-items`, `allow-background-items`, `cleanmymac-processes`, `cleanmymac-agent`, `cleanmymac-helper-tool`, `cleanmymac-safety`, `system-junk`, `trash-bins`, `duplicate-files`, `free-up-more-space`, `space-lens`, `uninstaller`, `optimization`, `maintenance-tasks`, `malware-removal`, `moonlock-engine`, `protection-scan-options`, `real-time-monitoring-on-off`, `background-scanning-on-off`, `protection-monitoring`, `privacy`, `app-permissions`, `cleanmymac-menu`, `cleanmymac-menu-on-off`, `cleanmymac-menu-recommendations`, `devices-monitoring`, `cpu-temperature`, `disk-no-health-and-temperature`, `mac-health`, `general`, `languages`.
- X: https://macpaw.com/support/cleanmymac-x/knowledgebase/ followed by: `system-junk`, `safety-database`, `cleanmymac-safety`, `start-smart-scan`, `how-often-run-cleanup-scans`, `full-disk-access`, `missing-features`, `updater`, `maintenance`, `optimization`, `cleanmymac-processes`, `cleanmymac-x-menu`, `ram-monitoring`, `cleanmymac-assistant`, `malware-removal`, `potentially-unwanted-applications`, `trial`, `operating-systems`. German: https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments
- Business: https://macpaw.com/support/cleanmymac-business/knowledgebase (+ `smart-scan`, `smart-scan-automation`, `malware-scan`)
- CleanMyMac 3: https://macpaw.com/support/cleanmymac-3/knowledgebase/notifications
- Classic: https://macpaw.com/support/cleanmymac-classic/knowledgebase/cleanmymac-shareware-program
- How-to: https://macpaw.com/how-to/is-cleanmymac-safe ; …/stop-background-items-added-mac ; …/icloud-drive-taking-up-space ; …/organize-email-inbox ; …/delete-junk-files-on-mac

**Third-party (VERIFIED-3P):**
- https://raw.githubusercontent.com/HuakunShen/space-lens/HEAD/apps/web/UX_RESEARCH.md (Space Lens and Large & Old KB summaries)
- https://raw.githubusercontent.com/kali-physi-hacker/veyra/HEAD/docs/product-research.md (space-lens-results summary)
- https://raw.githubusercontent.com/venomousmoog/lintel/HEAD/docs/research/2026-07-06-feasibility-findings.md (menu-no-elements reference)
- https://raw.githubusercontent.com/777genius/clean_disk/HEAD/docs/technical/permission-ux-playbook.md (FDA / safety KB summaries)
- https://raw.githubusercontent.com/ugurkocde/IntuneBrew/HEAD/Apps/cleanmymac.json (release-notes KB link)
- https://raw.githubusercontent.com/FaiChou/blog/HEAD/content/blog/mac-startups/index.md (2018 X launchd footprint)
- https://raw.githubusercontent.com/minniexcode/hexo_ash/HEAD/source/_posts/other/mac-server-setup-and-cleanup-guide.md (X footprint)
- https://raw.githubusercontent.com/Andrei-Barwood/kuwagga/HEAD/… (uninstall script; uncorroborated)

**Added in the fact-check pass:**
- Re-fetched (VERIFIED-D): the Homebrew `cleanmymac.rb`, `cleanmymac-zh.rb` and `MacPaw/homebrew-taps` `cleanmymac-cli.rb` casks; the letuanhai `cleanmymac-x.rb` cask; Fleet's `cleanmymac-uninstall.sh`; the DevMate S3 appcast for `com.macpaw.CleanMyMac5`; the CMM3 Help topics 1–9 and 90–94; the CMM3 Menu, Scheduler and Updates `.strings`; the CleanMyMac CLI README and wiki pages.
- New, VERIFIED-D: the X appcast `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml`; https://raw.githubusercontent.com/MacPaw/PermissionsKit/master/README.md and `MPFullDiskAccessAuthorizer.m` (GitHub code search).
- Apple documentation (VERIFIED-APPLE, JSON endpoints under `https://developer.apple.com/tutorials/data/documentation/`):
  - `servicemanagement/smappservice`, `…/status-swift.enum`, `…/statusforlegacyplist(at:)`, `…/opensystemsettingsloginitems()`;
  - `systemextensions`, `systemextensions/installing-system-extensions-and-drivers`, `systemextensions/ossystemextensionrequest/deactivationrequest(forextensionwithidentifier:queue:)`;
  - `foundation/nsxpcconnection/setcodesigningrequirement(_:)`, `foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey`;
  - `coreservices/kmditemlastuseddate`.
- OSS / third-party (VERIFIED-OSS / VERIFIED-3P):
  - BleachBit Safari cleaner: https://raw.githubusercontent.com/bleachbit/bleachbit/master/cleaners/safari.xml
  - `lsregister -kill` removal: https://github.com/kdeldycke/dotfiles/blob/HEAD/macos-config.sh ; https://github.com/MadMartian/Scribobulate/blob/HEAD/packaging/macos/uninstall.sh ; https://github.com/1tuz/Lead-Aggregator/blob/HEAD/docs/audits/2026-10-04/macos.md
  - Spotlight Data-volume store: https://github.com/hemp/baremetal/blob/HEAD/dot_local/bin/spotlight.sh ; https://github.com/unixorn/tumult.plugin.zsh/blob/HEAD/bin/spotlight-reindex
  - `periodic` gone on 15.6.1: https://github.com/AppliedIR/sift-mcp/blob/HEAD/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml
  - `systemextensionsctl uninstall` refused with SIP on, and the "Delete Extension" route: https://github.com/jo-duchan/tapflow/blob/HEAD/docs/operate/network-extension.md
  - Login Items pane naming by macOS version: https://github.com/DonMikone/CloudWire/blob/HEAD/scripts/release-notes.md.tmpl
  - `.qlgenerator` unsupported on 15+: https://github.com/haokaiyang/Mac-QuickLook/blob/HEAD/README.md ; https://github.com/rdmpage/gis-quicklook/blob/HEAD/README.md
  - Spotify offline storage: https://github.com/JonnyBurger/make-space/blob/HEAD/docs/spotify-cache.md
  - Gemini 2 selection rules (summary of MacPaw's user guide): https://raw.githubusercontent.com/ayhid/twins/70a63e785573c0768769850603e5e1faed3a4b3f/.planning/research/FEATURES.md
  - Replica of the 5.x Settings and Protection screens (weak): https://raw.githubusercontent.com/ddlmanus/MacOptimizer/5fdfcc04cf6ad09752174a64dff3fc960bc66445/AppUninstaller/MalwareRemovalReplicaView.swift
  - KB slug and article-title citations: https://raw.githubusercontent.com/777genius/clean_disk/HEAD/docs/technical/real-product-feature-adoption-playbook.md (support-tool-safety); https://raw.githubusercontent.com/mxcl/pkg.so/HEAD/agents/cleanmymac.yml (permanent-deletion note, timeline)

---

## Verification notes

Fact-check pass, 2026-10-12, by an adversarial reviewer. **Access was the same as the original crawl:**
- refused: `macpaw.com`, `updates.cleanmymac.com`, `updates.devmate.com` (DevMate release notes), `support.apple.com`, `keith.github.io`, `ss64.com`;
- WebSearch: refused (shared budget used up);
- reachable: `raw.githubusercontent.com`, GitHub code search, Apple's documentation JSON and the DevMate S3 appcasts.

So nothing here re-reads macpaw.com. Every check went to package metadata, MacPaw's own GitHub material, Apple documentation or OSS and field reports. About 30 fetches and about 20 code searches.

### Claims re-checked and confirmed

| # | Claim | How checked | Result |
|---|---|---|---|
| 1 | 5.x uninstall footprint (app, launchd labels, login item, Agent pair, Updater LaunchAgent, 9 per-user paths, `/Users/Shared/CleanMyMac_5`) | Cask + Fleet script re-fetched | Confirmed. Added: Homebrew target name `CleanMyMac.app`; Agent plist and Updater plist are zap-only; Fleet's random suffix |
| 2 | Appcast: `minimumSystemVersion` 11.0, 23 builds, 5.0.0 (2024-10-15) → 5.3.1 (2026-01-28), deltas, ~185–197 MB zips | Appcast re-fetched | Confirmed. Added: no EdDSA/DSA signatures; stale mirror vs cask 5.7.1 |
| 3 | CLI rules: 7-day pre-selection, ignore list covers clean/purge/analyze, `--force`, default purge folders, `cmm` alias, macOS 11+ | README, wiki, tap cask re-fetched | Confirmed. Added CLI version 1.0.0 |
| 4 | CMM3 rules: Document Versions 4-h rule; Xcode Module Cache/Archives never auto; Leftovers manual; Uninstaller selects nothing, Smart Selector, Uninstall/Reset/Remove button; Maintenance "when to run" text | Help topics 2, 8, 9 re-fetched | Confirmed word-for-word in substance |
| 5 | CMM3 Menu thresholds (500 MB…100 GB, Don't Warn/Don't Notify) and Scheduler values (Never…Annually; two launch options) | `.strings` re-fetched | Confirmed |
| 6 | FDA deep link `Privacy_AllFiles` and PermissionsKit probe approach | PermissionsKit README + source | Confirmed; probe-file list and "no callback" caveat added |
| 7 | `SMAppService` status/approval APIs, `statusForLegacyPlist(at:)`, `openSystemSettingsLoginItems()`, `setCodeSigningRequirement` (macOS 13+) | Apple doc JSON | Confirmed |
| 8 | `periodic` removed in macOS 15 | Forensic field report (15.6.1) + 05/02 | Confirmed |
| 9 | DNS flush pair | 05 (Mole + CMM3 binary) | Confirmed (secondary) |
| 10 | X cask footprint (Agent, HealthMonitor, Menu, Scheduler, Updater labels; widget; Photos-library folder) | Cask re-fetched | Confirmed |
| 11 | `volumeAvailableCapacityForImportantUsageKey`, `kMDItemLastUsedDate` | Apple doc JSON | Confirmed; LaunchServices-only update caveat added |

### Corrected in place (marked "(corrected)")

1. **Moonlock ES system extension listed as a verified 5.x component** (§1 #9, §9.1). The casks list no sysext, and the process evidence conflicts. It is now INFERRED/unresolved.
2. **`lsregister -kill -r -domain …`** (§4.9). Removed on current macOS ("dangerous and no longer useful", non-zero exit). Replaced with `lsregister -gc -r -f -all local,system,user` plus `-u` for stale paths.
3. **`mdutil -E /`** (§4.9). It can miss the user-data store. Replaced with `mdutil -E /System/Volumes/Data` or `mdutil -a -E`.
4. **Speed Up Mail method** (§4.9). The vendor ran SQLite `VACUUM` on the Envelope Index; moving the index aside is now the fallback.
5. **Spotify exception path** (§3.6). Offline music is `~/Library/Application Support/Spotify/PersistentCache/Storage`, not `~/Library/Caches/com.spotify.client`.
6. **`systemextensionsctl uninstall`** (§9.1). Refused with SIP on; not an uninstall route.
7. **Login Items pane name** (§3.22). "Login Items" on macOS 14, "Login Items & Extensions" on 15+.
8. **Localisation count** (§3.29). The appcast shows 13 languages; Turkish was added from 5.2.3.
9. **`WKWebsiteDataStore` for Safari cookies** (§4.10). Wrong API; replaced with concrete Safari file paths.
10. **Quick Look generators** (§4.11). `.qlgenerator` is unsupported on 15+.
11. **Restart via System Events** (§8). Needs the Automation permission.
12. **Helper daemon `bootout` step** (§9.1). It was presented as part of the vendor footprint; it is our own addition.

### Downgraded VERIFIED → INFERRED
- "Maximize suspicion" as an old X scan-mode name (§3.14). One unconfirmed search excerpt.
- "Moonlock system extension" as a CMM5 component (see corrected item 1).

### Still uncertain
- Every VERIFIED-KB fact is still second-hand, via sibling reports' search-engine extraction. None could be re-read from macpaw.com. Treat exact KB wording, numbers (battery 80/79/10 %, devices "up to 3", "<20 %", "Unused = 6 months") and slugs as probable, not certain.
- The 5.x Settings tab list and Notifications options rest on one third-party replica (weak).
- How Custom Updates are discovered, and whether the Updater installs silently: unverified.
- CleanMyMac's duplicate keep-rule and the health-score cutoffs: unverified.
- Which macOS first removed `lsregister -kill`: observed on 26 only. Detect at runtime.
- Whether CMM5 ships the Moonlock ES extension: unresolved; check `systemextensionsctl list | grep -i macpaw` on a real install.
- 13 is the language count in the appcast's release-notes links. The app bundle's `.lproj` list was not inspected.
