# 20 — Gap-fill 02: CleanMyMac 5.x Cleanup, Protection and Performance, screen by screen

> **Assignment:** close the open 5.x layout, label, default-selection and exception-list gaps in 03 §12 (gaps 1, 4, 5), 04 §15 (gaps 2, 6) and 05 §12 (gaps 1, 4, 6). For each of the three modules, document the landing, scanning, results tiles and review/detail screens.
> **Target of our build:** *Spruce* (see `docs/ARCHITECTURE.md`), an original app for an Apple-Silicon Mac mini on macOS 14 Sonoma, 15 Sequoia and 26 Tahoe.
> **Product being studied:** MacPaw CleanMyMac 5.x. The current release is **5.7.1**, build `50701.0.2609301754` (per the Homebrew cask cited in 04). The last build on the legacy DevMate appcast is **5.3.1** (Jan 2026).
> **Date:** 2026-10-12.

---

## 0. Method, access limits, evidence labels

### 0.1 What could and could not be reached (read first)

- **No primary 5.x page could be read in this session.**
  - `macpaw.com`, `cleanmymac.com`, `apps.apple.com`, `setapp.com`, the review sites and YouTube all failed DNS resolution in WebFetch. With curl they returned `000` through the agent proxy.
  - `dl.devmate.com`, which hosts the 5.x app archives, returned **403 from the egress policy**. Per the proxy rules this was reported, not routed around.
  - No archive or reader services were used.
- **WebSearch was unavailable.** The shared per-turn budget ("200 WebSearch calls per turn, shared by every agent") was already used up before this track started, so not one search ran. This report therefore falls short of the "15+ searches / 10+ fetches" target. A follow-up turn with a fresh budget, or a check on the Mac mini (§7), is needed to finish closing the gaps.
- **What was reachable, and what it added:**
  1. **MacPaw DevMate release notes on S3** (fetched). The cumulative 5.0.0 → 5.3.1 notes are new to the team. They add the 5.2.6–5.3.1 entries.
  2. **Real vendor screenshots** of a late CleanMyMac **X** build, from the public dataset `kafkaGen/dora-ai`. Report 05 had used only routes 1, 7 and 8. **I fetched and read routes 2 (System Junk), 3 (Mail Attachments), 4 (Trash Bins), 5 (Malware Removal) and 6 (Privacy, including X's App Permissions view)** for the first time. These are the newest real vendor UI pixels the team has. They are X, not 5.x, but X 4.15 is the direct ancestor, and several 5.x KB facts match them.
  3. **A third-party 5.x clone, `jayvicsanantonio/VaderCleaner`.** Its author inspected an installed **CleanMyMac 5.5.4 (build 50504.0.2605130801), Mac App Store edition** (documented in the repo's `docs/cleanmymac-3d-assets.md`). Its code comments say many screens "mirror the reference". **This is the only 5.x-specific screen-structure evidence found.**
     - **Caveat:** at least one of its strings equals X-era copy word for word (the Privacy tagline, see §4.6). Its *copy* is therefore unreliable. Its *layout claims* ("mirrors the reference …") are the useful part.
     - The reference was the **App Store edition**, which lacks several features (§1.3). That matters for Protection.
  4. The sibling reports 01–13 (their 5.x KB facts came from search-engine excerpts read before the budget ran out).

### 0.2 Labels used on every claim

| Label | Meaning |
|---|---|
| **VERIFIED-KB** | A MacPaw help-centre fact read by a sibling track (via search excerpt). The original URL is cited. Not re-fetchable here. |
| **VERIFIED-DM** | Read directly in MacPaw's DevMate release notes or appcast on S3 (URL in §9). |
| **VERIFIED-SCR-X** | Read directly by me off a **real CleanMyMac X screenshot** (dora-ai `datasets/routes/<r>/<s>/image.png`). X build, no version stamp. INFERRED to be 4.15.x: the Claude desktop app is visible, and Moonlock branding plus "Free Up Purgeable Space" are present. |
| **REPLICA-5** | VaderCleaner code or comments built against CMM **5.5.4 (MAS)**. Plausible 5.x structure; copy may be X-derived. Weak to moderate. |
| **REPLICA-X** | `ddlmanus/MacOptimizer` "…ReplicaView" files, which call themselves reconstructions of CleanMyMac **X**. Weak. |
| **VERIFIED-3P** | A third-party bundle teardown or observation (URL given). |
| **INFERRED** | Our reasoning, or a recommendation for Spruce. Everything not tagged is INFERRED. |

**Copy policy:** short UI labels are quoted only so the team can recognise the screens. **Spruce must not reuse any of this wording, art or iconography.** Our own labels are given in §6.

---

## 1. Answer sheet (one line per assignment question)

Confidence: **H** = vendor-verified; **M** = verified for X plus 5.x KB consistent, or REPLICA-5 consistent with the KB; **L** = inference only.

### 1.1 Cleanup

| # | Question | Best answer | Conf. | Evidence |
|---|---|---|---|---|
| C1 | Current System Junk group list | 12 groups: User Cache Files, System Cache Files, User Log Files, System Log Files, Language Files, Universal Binaries, Xcode Junk, Document Versions, iOS Device Backups, Broken Preferences, Broken Login Items, Deleted Users. | M (list); **L (order)** | VERIFIED-KB missing-features via 01/03 |
| C2 | On-screen group order | **Not documented.** The review list is most likely sorted by size by default, with Name as the alternative sort. The summary's "Including …" line names the largest group (X showed "User Cache Files"). | L | VERIFIED-SCR-X 2/2; REPLICA-5 manager sorts Size/Name, pre-sorted by size |
| C3 | Unused Disk Images / Old Updates / Downloads in 5.x | **Not System Junk groups in 5.x.** Installers moved to Applications › Installation files; downloads (old DMGs, archives) moved to My Clutter › Downloads; Old Updates was dropped or folded into caches. | M | VERIFIED-KB (01 module map); absent from the 12-group list |
| C4 | Dev junk / AI-tool junk in the 5.x desktop app | **Not as separate desktop groups** as far as any source shows (Xcode Junk only). They exist in MacPaw's **CLI** (`clean dev`, `clean ai`; AI Junk unchecked by default). No release note through 5.3.1 mentions them, and 01's 5.4–5.7 What's-New table does not either. | M (CLI); L (desktop absence) | VERIFIED-DM; CLI README via 03 |
| C5 | Full "not auto-selected" exception list in the 5.x KB | **Only Spotify and Gradle are known.** The full current list is **still unread.** Other documented never-auto rules from X/CMM3/CLI are consolidated in §3.6. | H (two items); gap (rest) | VERIFIED-KB system-junk excerpt via 03/13 |
| C6 | How Mail Attachments is presented | A sibling section of System Junk and Trash Bins inside the Cleanup results and review (left pane). Only recoverable, unmodified attachments are pre-selected; edited ones are labelled "changed by user". In X, when nothing was smart-selected, the result screen showed **only "Review Details"** with no Clean button. | M | VERIFIED-KB; REPLICA-5; VERIFIED-SCR-X 3/2 |
| C7 | How Trash Bins is presented | Third section of Cleanup. Categories: Mail, Photos, Gemini Duplicates, Startup drive (incl. items removed from iCloud), one row per External drive. X named the startup row by volume ("Trash on Macintosh HD"). | H (categories); M (row naming) | VERIFIED-KB trash-bins via 02/03; VERIFIED-SCR-X 4/2 |
| C8 | Which trash bins are pre-checked | **All of them**: startup, external drives, Mail and Photos. X showed "smart-selected" equal to "found in total". Whether 5.x **Smart Care** pre-checks external-drive trash is still unconfirmed. | H (module); L (Smart Care) | VERIFIED-KB ("all items auto-selected"); CMM3 Help topic-6; VERIFIED-SCR-X 4/2 |

### 1.2 Protection

| # | Question | Best answer | Conf. | Evidence |
|---|---|---|---|---|
| P1 | One scan with three tiles, or three sub-screens? | **One Protection scan** feeding a results dashboard of tiles: a live malware tile first, then privacy tiles (one per browser with data, plus Recent Items), plus App Permissions "recommended to review" tiles. Review happens in one shared manager, with the sub-areas as left-pane sections. X, by contrast, had separate sidebar modules. | M | VERIFIED-KB (three sub-areas; App Permissions tiles); REPLICA-5 (dashboard grid; manager left nav) |
| P2 | Where the scan-mode picker sits | **Settings › Protection** (Quick / Balanced / Deep plus extra locations). The landing shows the current mode with a **Configure…** shortcut, and the results repeat "Scan mode: <mode>". | H (settings); M (landing shortcut, verified on X) | VERIFIED-KB protection-scan-options; VERIFIED-SCR-X 5/1, 5/3 |
| P3 | Privacy browsers and categories in 5.x | Per browser (Safari, Chrome, Firefox named; other Chromium browsers INFERRED): Browsing History, Cookies, Downloads History, Autofill, Search Queries, Tabs From Last Session. System: Recent Items (apps, documents, servers) and Wi-Fi Networks. | H (categories) | VERIFIED-KB privacy via 01/13 |
| P4 | Wi-Fi networks present? | **Yes** in the direct edition (the App Store edition restricts it). X showed "Wi-Fi Networks" with an ⓘ in place of a checkbox. | H/M | VERIFIED-KB missing-features; VERIFIED-SCR-X 6/3 |
| P5 | Chats present? | **Unconfirmed for 5.x.** X 4.15's Privacy landing still advertised chat cleanup, but no chat row appeared on that Mac. The 5.x KB category list omits chats. | L | VERIFIED-SCR-X 6/1, 6/3 |
| P6 | Saved passwords present? | **Not in the 5.x KB list.** REPLICA-5 shows "Saved Passwords" and "Autofill Values" as **informational rows (ⓘ, no checkbox)**. CMM3 offered them as deletable. | L/M | REPLICA-5; CMM3 via 04 |
| P7 | App Permissions tiles and grouping | Tiles for recommended reviews (5.x). In the review list, grouped **by permission type** with an alternative grouping (X: "Group by Permission Type ▾"), "Sort by Name ▾", one expandable row per type with an item count. | M | VERIFIED-KB app-permissions; VERIFIED-SCR-X 6/3 |
| P8 | App Permissions actions | X offered checkbox selection plus a **Remove** (= revoke) button on this list, so a programmatic revoke existed. INFERRED mechanism: `tccutil reset <Service> <bundle-id>`. Granting must go through System Settings. App Store edition: management restricted. 5.x action wording unknown. | M (X) / L (5.x) | VERIFIED-SCR-X 6/3; VERIFIED-KB missing-features |

### 1.3 Performance

| # | Question | Best answer | Conf. | Evidence |
|---|---|---|---|---|
| F1 | The "weekly maintenance" card | The landing/dashboard shows a recommended weekly maintenance set with **Review** and **Run Tasks**, plus **View All Tasks**. REPLICA-5 shows the dashboard as: tagline, a "View All Tasks" button, then summary cards (maintenance tasks recommended, login items, background items), each with Review. | H (card + buttons); M (layout) | VERIFIED-KB maintenance-tasks via 02/13; REPLICA-5 |
| F2 | View All Tasks list per OS | Full catalogue: Free Up RAM, Free Up Purgeable Space (5.0.5+), Flush DNS Cache, Reindex Spotlight, Run Maintenance Scripts (**macOS ≤ 13 only** per the KB), Repair Disk Permissions, Speed Up Mail, Thin Time Machine Snapshots. **On 14, 15 and 26: the seven without Run Maintenance Scripts.** | M | VERIFIED-KB; VERIFIED-SCR-X (a late X build listed exactly 7 tasks without scripts); `periodic` absent on 15+ (05) |
| F3 | Is Run Maintenance Scripts shown on 14? | **Per the KB, no** ("≤13"), even though `/usr/sbin/periodic` still exists on 14. | M | VERIFIED-KB via 01; man pages via 05 |
| F4 | Structure of a task's detail text | X: title, then a 2–3 sentence explanation, then a "Usage recommendations:" bulleted list, then "Last run date: …". 5.x REPLICA: an info (ⓘ) per row. | M (X) | VERIFIED-SCR-X 8/1 via 05; REPLICA-5 |
| F5 | Login Items / Background Items lists | Two separate lists. Disable/Enable is reversible; **Remove** is permanent and confirmed. X rows: checkbox, icon, name, status dot + "Enabled", sorted by name, search in the toolbar. REPLICA-5 adds a "Select:" bulk menu, an "N Items Selected" footer, a destructive **Remove** with confirmation, and a note that "N more items are managed by macOS" and can only be changed in System Settings. | H (semantics); M (layout) | VERIFIED-KB optimization; VERIFIED-SCR-X 7/2 via 05; REPLICA-5 |
| F6 | Other apps' SMAppService items on 13+ | **Still unverified.** Best reading: 5.x cannot toggle them (private BTM entitlement). They are omitted, or shown with a pointer to System Settings, and only plist-backed agents and daemons get Disable/Remove. | L/M | 05 §6.4 [ENT-BTM]; REPLICA-5 note |
| F7 | Quit-apps dialog | Title "Some applications should be quit.", one line of explanation, a per-app row with a **Quit** button, footer **Ignore** (left) and **Quit All** (right, default). Raised mid-run (the run button already shows **Stop**). | H (X) | VERIFIED-SCR-X 2/3, 8/2 |

**App Store edition caveats** (VERIFIED-KB missing-features via 01/13). They matter because REPLICA-5 was built against the App Store build:
- no maintenance tasks;
- login items and launch agents are review-only, and launch agents can only be uninstalled;
- no real-time monitor;
- Safari privacy items, Wi-Fi cleanup and App Permissions management are restricted;
- no Broken Login Items, Deleted Users, or Photos/Gemini trash.

---

## 2. The common 5.x module skeleton (applies to all three modules)

Every 5.x module follows the same five-state shell. The parts that are VERIFIED are marked.

1. **Landing (intro).**
   - Module art, title, a one-sentence promise, and three feature rows (icon + label). These rows are informational, not buttons.
   - A big round **Scan** button at bottom centre.
   - Pattern VERIFIED-SCR-X (5/1, 6/1). 5.x keeps the floating round action button; its glassy "ubiquitous button" shader ships as `CMM5UbiquitousButton…bundle/default.metallib` (VERIFIED-3P teardown, VaderCleaner `docs/cleanmymac-3d-assets.md`).
   - REPLICA-5 feature rows:
     - Cleanup: System Junk · Mail Attachments · Trash Bins.
     - Protection: Malware Removal · Privacy · Application Permissions.
     - Performance: Login Items · Launch Agents · Free Up RAM · Maintenance Scripts.
2. **Scanning.**
   - The art animates, the current location or file is shown, and the round button becomes **Stop**. VERIFIED-SCR-X 5/2; REPLICA-5.
   - Sections that finish early fill in while slower ones keep running. In Protection, privacy tiles appear while the malware tile still shows "Looking for threats…" (REPLICA-5).
3. **Results dashboard (5.x novelty: "tiles UI").**
   - A **Start Over** bar at top left.
   - A headline total.
   - A grid of cards (one tall lead card on the left, smaller cards on the right). Each card has a metric-led title, a one-line description, art and **Review** / primary-action buttons.
   - VERIFIED-KB that 5.0 introduced a "tiles UI" (01 What's New); grid geometry REPLICA-5.
   - X instead used a single "Scan completed" summary with "<size> Smart-selected", an "Including …" list, **Review Details** and "<size> found in total" (VERIFIED-SCR-X 2/2, 4/2).
4. **Manager (review), three panes.**
   - **Header:** **Back**, centred title ("Cleanup Manager", "Protection Manager", "Performance Manager"), a **Search** field and **Sort by:** (Size / Name; Name / Count for privacy).
   - **Left pane:** sections (sub-areas).
   - **Middle pane:** groups with tri-state checkbox, icon, size or count.
   - **Right pane:** a heading and one-line description for the focused group, a **Select:** menu (Select All / Deselect All; the trigger reads All / Some / None), then item rows (checkbox, Finder icon, name, size; disclosure for children).
   - **Footer:** "N Items Selected" and the destructive primary button.
   - REPLICA-5 throughout. X's equivalent was a two-pane list with "Sort by Name ▾" in each column, search in the toolbar, and the round action button (VERIFIED-SCR-X 6/3).
5. **Run → completion.**
   - Per-group progress, then a completion card with the amount freed.
   - X: **Share Results**, a cross-sell card, **View Log** (with a warning glyph when something failed) and **Start Over** (VERIFIED-SCR-X 4/3, 8/4).
   - 5.x ships `MoonlockCleanupCompletePromo…` art, so a Moonlock cross-sell can appear on Cleanup completion (VERIFIED-3P asset names).

**Context menu on any result row** (VERIFIED-KB cleanmymac-safety): **Add to Ignore List**. Ignore-list scopes in 5.x: Cleanup (System Junk, Mail Attachments), Protection (Malware Removal), Applications (Uninstaller, Updater), My Clutter (Duplicates, Similar Images, Downloads). **Trash Bins and Privacy have no ignore scope.**

---

## 3. Cleanup (5.x), screen by screen

### 3.1 Landing
- **Title:** Cleanup. Feature rows: System Junk / Mail Attachments / Trash Bins (REPLICA-5; the KB confirms these are the module's three parts).
- **Promise line** (paraphrase): clean the system for performance and reclaim free space. The X System Junk intro said the same; REPLICA-5 reuses it.
- **Button:** Scan.
- **X benefit rows** (VERIFIED-SCR-X 2/1, paraphrased via the dataset description): optimize the system by removing temp files; resolve errors by removing broken items.
- **5.x Settings › Scanning ("Customize Smart Care")** has a per-category tree in which only System Junk exposes per-category checkboxes (REPLICA-5 `SettingsScanningTab.swift` comment). This matches the CMM3 rule (03 §3): deselecting a sub-category excludes it from both the module scan and Smart Care.

### 3.2 Scanning
- Animated art; the current path is shown; **Stop**.
- **Full Disk Access gate.** Without FDA the scan is incomplete. The FDA banner/Assistant offers **Allow Access** (VERIFIED-KB full-disk-access).

### 3.3 Results dashboard
- **Headline** (REPLICA-5 pattern): "There are <size> of junk files on your Mac." Then **Review All Junk**.
- **Cards** (REPLICA-5 geometry; titles in the form "<size> of <Group> Found"):
  - **System Junk** is the tall lead card on the left. Description (paraphrase): unneeded files generated by the system and apps. Buttons: **Review** and **Clean**.
  - **Trash Bins** is the wide card on the right. Description (paraphrase): stop wasting space, empty the trash bins for good. Buttons: **Review** and **Clean**.
  - **Mail Attachments.** REPLICA-5 folds it into System Junk's card. The vendor's Cleanup Manager has it as a separate left-pane section (REPLICA-5 `CleanupManagerModel.swift`: "System Junk is the umbrella…, while Mail Attachments and Trash Bins stand alone").
  - **INFERRED for 5.x:** three cards (System Junk, Mail Attachments, Trash Bins), with Mail Attachments showing **Review** only when nothing in it is smart-selected. X did exactly this (VERIFIED-SCR-X 3/2: "Your Mail looks clean. However, we've found a few items you might want to review and clean." → **Review Details**, "<size> found in total", no Clean button).
- **Metrics:** each card shows its found size. The vendor separates **found** from **smart-selected**: X showed 3.46 GB found vs 1.91 GB smart-selected for System Junk, so about 45% of the found junk was **not** pre-selected (VERIFIED-SCR-X 2/2). Spruce must show both numbers.
- **Default checks:** System Junk follows the Safety DB (§3.6). Mail Attachments: recoverable and unmodified only. Trash Bins: everything (§3.8).
- **Smart Insights** (5.2.6+, Apple Intelligence on Apple Silicon + macOS 26) adds an on-device "what is this / do I need it" explainer to system items (VERIFIED-DM 5.2.6 notes).

### 3.4 Cleanup Manager (review)
- **Left pane:** System Junk · Mail Attachments · Trash Bins (REPLICA-5).
- **Middle pane:** the groups of the focused section, with tri-state checkbox, group art and size. The default order is **size, descending** (REPLICA-5: items "pre-sorted by size (descending)"; **Sort by:** Size | Name).
- **Right pane:**
  - a one-line description of the group (REPLICA-5 System Junk paraphrase: redundant files that clog storage);
  - the **Select:** menu;
  - item rows (Finder icon, name, size, disclosure for folders with child rows one level deep).
- **Per-row actions:**
  - hover magnifier → Reveal in Finder; Quick Look (CMM3 VERIFIED; X/5 INFERRED);
  - context menu → **Add to Ignore List** (VERIFIED-KB);
  - Smart Insights explainer on supported Macs (VERIFIED-DM).
- **Search:** filters item names across the focused section (REPLICA-5). CMM3 had ✕ to clear (VERIFIED, 03 §3).
- **Footer:** "N items selected · <size>" and the **Clean** button. Trash uses the same button in 5.x per REPLICA-5; **X used "Empty"** for Trash Bins (VERIFIED-SCR-X 4/2).

### 3.5 System Junk group list and order (5.x)
- **List:** the 12 groups in C1 (VERIFIED-KB). **Order:** unknown, see C2. For reference, X's on-screen order (REPLICA-X) was: Unused Disk Images, User Cache Files, Downloads, Universal Binaries, System Cache Files, User Log Files, System Log Files, Deleted Users, iOS Device Backups, Old Updates, Broken Login Items, Broken Preferences, Xcode Junk, Document Versions, Language Files.
- **App Store edition:** no System Caches/Logs, Language Files, Universal Binaries, Broken Login Items, Deleted Users or iOS backups (VERIFIED-KB missing-features via 13 §1).
- **Removed vs X:** Unused Disk Images, Downloads, Old Updates (C3). **Not added:** Dev Tools and AI Junk (C4; CLI only).
- **Release-note check (VERIFIED-DM, 5.0.0 → 5.3.1):** no Cleanup-category change is announced. The entries are:
  - 5.0.5 Free Up Purgeable Space (Performance);
  - 5.0.7 VoiceOver and Reduce Motion;
  - 5.1.0 Space Lens returns;
  - 5.2.1 Cloud Cleanup (iCloud Drive, Google Drive, OneDrive);
  - 5.2.6 Smart Insights;
  - 5.3.0 Dropbox and improved OneDrive;
  - 5.3.1 and the other point releases: fixes only.

  For 5.4–5.7.1, see 01's What's New table: My Activity, background Applications scan, Notification Center, Email Cleanup; no new junk groups.

### 3.6 Not-auto-selected exceptions: what is known and what Spruce ships

**5.x KB (VERIFIED-KB, system-junk excerpt via 03/13):** "all types" are auto-selected except listed exceptions, and the two named are **Spotify** and **Gradle** caches. **The rest of the 5.x list is still unread (gap).**

**Other vendor-documented never-auto rules** (still the vendor's rules unless 5.x changed them):

| Rule | Generation / source | Status |
|---|---|---|
| Spotify cache (offline music lives there) | 5.x KB; X safety-database KB | VERIFIED-KB |
| Gradle caches | 5.x KB | VERIFIED-KB |
| Document Versions: never the earliest or latest; only versions < 4 h apart, keeping the newest in each run | X KB, CMM3 Help | VERIFIED-KB / VERIFIED (CMM3) |
| iOS Device Backups: latest never auto | X KB, CMM3 Help | VERIFIED |
| Xcode: Module Cache and Archives never auto | CMM3 Help | VERIFIED (CMM3) |
| Leftovers never pre-selected (now in Applications) | CMM3 Help; 5.x moved | VERIFIED (CMM3) |
| Downloads (X): Safari only broken downloads; Slack broken plus ≥ 1 month | X KB | VERIFIED-KB (X) |
| Mail attachments: user-edited ("changed by user") never auto | X KB (DE) | VERIFIED-KB |
| AI-tool junk unchecked by default | CLI README mock-up | VERIFIED (CLI) |
| Project artifacts < 7 days unchecked ("recent") | CLI wiki (`purge`) | VERIFIED (CLI) |
| Large & Old Files never pre-selected | CMM3/KB | VERIFIED |
| Partial pre-selection in practice: 1.91 of 3.46 GB | X screenshot | VERIFIED-SCR-X 2/2 |

**Spruce Safety DB v1 exception list** (INFERRED; merges the above with 03 §7, add-only):
- Spotify `PersistentCache/Storage` (never), `Caches/com.spotify.client/Data` (unchecked);
- Gradle `~/.gradle/caches` (never auto);
- Maven `~/.m2`, pnpm store, Docker raw disk (review only);
- Xcode Archives, ModuleCache, newest DeviceSupport per platform (review);
- iOS backups (all unchecked; newest flagged);
- Document Versions (4-hour rule);
- Mail attachments of POP and "On My Mac" accounts plus edited ones;
- AI model stores and chat histories (never), AI caches (unchecked);
- JetBrains current-version caches (never);
- app caches for apps that are running (skip with reason "in use").

**Verify on device (§7)** before calling this "parity".

### 3.7 Mail Attachments presentation
- 5.x: a section of Cleanup, reviewed in the Cleanup Manager (REPLICA-5, KB).
- X: its own sidebar module (VERIFIED-SCR-X 3/1–3/2).
- **Groupings** carried over from CMM3: by Mail account, by Last view date, by File kind (VERIFIED, 03 §5.23). INFERRED for 5.x: grouped by account in the middle pane, with the file list on the right.
- **Defaults:** recoverable copies only. Edited files are labelled **changed by user** and left unchecked (VERIFIED-KB).
- **Zero-smart-selection state:** **Review** only, no primary action (VERIFIED-SCR-X 3/2). Spruce copies this behaviour generically: never show a big Clean button that would act on nothing.

### 3.8 Trash Bins presentation and pre-checks
- **Rows** (5.x KB): Mail · Photos · Gemini Duplicates · Startup drive (incl. items removed from iCloud) · External drives (one row per drive). X labelled the startup row "Trash on <volume name>" (VERIFIED-SCR-X 4/2: "Trash on Macintosh HD").
- **Pre-checks:** **all rows, including external drives, Mail and Photos** (VERIFIED-KB; CMM3 topic-6; X "Smart-selected" = total).
- **Primary button:** X used **Empty**; REPLICA-5 uses Clean. INFERRED for 5.x: Clean on the Cleanup dashboard, since all three sections share one action.
- **Spruce decision** (unchanged from 02/03, restated):
  - Dedicated Trash view: pre-check the startup trash and writable external volumes (our uid only).
  - Mail trash and Photos "Recently Deleted": listed, **unchecked**, acted on through Mail/Photos-sanctioned routes or a deep link, never by raw file deletion.
  - One-click Checkup: external-volume trash unchecked (it may be a backup disk).
  - **This is a deliberate safety deviation from the vendor's "everything pre-checked".**

### 3.9 Quit-apps interruption during Clean (VERIFIED-SCR-X 2/3)
- Shown **after** Clean is pressed (the round button already reads **Stop**). It lists the running apps whose caches are selected (seen: Code, Claude, Safari).
- Layout: title "Some applications should be quit." + one explanatory line; rows of app icon, name and **Quit**; footer **Ignore** (left), **Quit All** (right, default).
- **Ignore** = clean what is possible and skip those apps' items (INFERRED).

### 3.10 Completion
- Freed amount, the remaining free space on the startup disk, **Start Over**, **View Log**, and a cross-sell card (VERIFIED-SCR-X 4/3). 5.x adds a Moonlock promo asset (VERIFIED-3P).

---

## 4. Protection (5.x), screen by screen

### 4.1 One scan or three sub-screens? (gap 04-2, part)
- **VERIFIED-KB:** Protection = Malware Removal + Privacy + App Permissions (three sub-areas), and App Permissions shows recommended reviews **as tiles**.
- **REPLICA-5:** a single Scan produces one dashboard:
  - the **live malware tile** is the tall lead card ("Looking for threats…", biohazard art, current file, **Stop**);
  - the right column holds **privacy tiles**, one per browser with data ("<Browser> Browsing Data Found") plus "Recent Items Found", each with **Review** / **Remove**;
  - a header button **Manage Privacy Items** opens the Protection Manager.

  The manager's left pane lists **Malware Removal** and **Privacy** only. That is consistent with the App Store reference, which restricts App Permissions management.
- **Conclusion (M):** in the direct-download 5.x, one Protection scan → one tile dashboard (malware + privacy + app-permission tiles) → a shared three-pane manager with **Malware Removal / Privacy / App Permissions** in the left pane.
- **X differed:** Malware Removal and Privacy were separate sidebar modules, and App Permissions lived inside Privacy as a row (VERIFIED-SCR-X 6/3).

### 4.2 Landing and the scan-mode picker
- **X 4.15 landing** (VERIFIED-SCR-X 5/1):
  - title "Malware Removal by moonlock";
  - one-line promise (in-depth checkup for vulnerabilities);
  - **"Last scan: today"**;
  - rows: Removes malicious files · Protects your Mac · **"<Mode> ⓘ"** (e.g. "Deep Scan") with a line about tailoring the engine;
  - a **Configure…** button and the round **Scan** button.
- **5.x:** the picker itself is in **Settings › Protection** (Quick / Balanced / Deep; extra locations DMG, email attachments with FDA, archives, USB, iCloud) (VERIFIED-KB protection-scan-options). The REPLICA-X/5.x settings rows are listed in 04 §5.
- **INFERRED for 5.x:** the Protection landing keeps the "Scan mode: <mode> · Configure…" shortcut (REPLICA-X shows it too) and adds feature rows for Privacy and App Permissions (REPLICA-5).
- **Spruce:** an inline segmented control (Quick / Standard / Deep) on our landing, mirrored in Settings. One place to change it, two places to see it.

### 4.3 Scanning
- The malware tile shows a live counter or current file and **Stop** (VERIFIED-SCR-X 5/2; REPLICA-5).
- **Privacy estimation needs browsers quit.** The vendor shows the quit dialog of §3.9 with the browser rows (VERIFIED-SCR-X 6/2), and CMM3 offered a per-browser "Quit %@ to Estimate" (VERIFIED, 04 §11).

### 4.4 Results: the malware tile states
- **Clean** (VERIFIED-SCR-X 5/3, "Scan completed!"), three check rows:
  - "<N> items scanned" + "Scan mode: Deep Scan ⓘ";
  - "<duration>" + "Great Result!";
  - "Protected" + "No threats found".

  Then a reassurance sentence and a "Powered by Moonlock" card with **Learn More About Moonlock ↗**. Observed: **90,781 items in 52 s in Deep mode**, a useful performance baseline.
- **Threats found:** all threats pre-selected; **Remove** (no review) or **Review** (VERIFIED-KB).
  - Each row carries a **malware-family glyph**. 5.5.4 ships glyphs for adware, backdoor, botnet, dropper, exploit, installer, keylogger, miner, pua, ransomware, riskware, rootkit, spyware, stealer, trojan, virus, worm and other (VERIFIED-3P, asset names in `SharedResources.framework`).
  - Some removals ask for a **restart** (VERIFIED, CMM3 strings via 13).
- **Removing → done → partial failure:** unremoved items stay listed for retry (REPLICA-X/5).
- **Basic plan / unlicensed:** threats are found but not removed (VERIFIED-KB via 01).

### 4.5 Protection Manager (review)
- **Header:** Back · "Protection Manager" · Search · **Sort by:** Name | Count (REPLICA-5).
- **Left pane:** Malware Removal · Privacy · (App Permissions in the direct edition; INFERRED).
- **Malware Removal → right pane:** "Detected Threats", rows with checkbox, family glyph, name, path, and Reveal. Empty state: "No Threats Found" (REPLICA-5).
- **Privacy → middle pane:** one row per browser (icon, item count) plus Recent Items and Wi-Fi Networks.
- **Privacy → right pane:** that source's categories. Cookies and Downloads History expand to **per-site child rows** (REPLICA-5).
- **Footer:** "N Privacy Items Selected" / "N Threats Selected" and **Remove**. Confirmation title "Remove selected items?" (REPLICA-5; wording unverified).
- **X layout of the same data** (VERIFIED-SCR-X 6/3):
  - **middle column:** Application Permissions (52 items) · Recent Items Lists (22 items) · Safari (4 827 items) · Wi-Fi Networks (32 items, with an **ⓘ instead of a checkbox**, i.e. not selectable on that Mac), plus "Sort by Name ▾";
  - **right column:** the focused source's title and description, then category rows;
  - **bottom:** a round **Remove** button.

### 4.6 Privacy: per-browser list and categories (gap 04-6)
- **Categories (VERIFIED-KB 5.x):** Browsing History · Cookies · Downloads History · Autofill · Search Queries · Tabs From Last Session, per browser. System: **Recent Items** (servers, apps, documents) and **Wi-Fi Networks** (direct edition).
- **Browsers:** Safari, Chrome and Firefox are named in the KB. INFERRED: other Chromium-family browsers (Edge, Brave, Opera, Vivaldi, Arc) are detected, as 04 §11 recommends for Spruce.
- **REPLICA-5 per-category behaviour.** The reference was the **App Store** build, so the Safari and Wi-Fi restrictions apply.
  - **Removable** (checkbox): Cookies, Downloads History, Cached Files, Tabs From Last Session.
  - **Informational** (ⓘ popover, no checkbox): Autofill Values, Browsing History, Saved Passwords, Search Queries.
  - INFERRED: in the direct edition, Browsing History, Autofill and Search Queries are removable (the KB lists them as cleanable). **Saved Passwords, if shown at all, is informational only.**
- **Chats:** not in the 5.x KB list. X 4.15's Privacy landing still advertised "Sweeps up your chat data" (Skype and other messengers; VERIFIED-SCR-X 6/1), but the X results on that Mac had no chat row (6/3). **Treat as absent in 5.x** (L). Spruce does not offer chat deletion (04 §11.2).
- **Wi-Fi Networks:** present (direct edition). X marked the row ⓘ/non-selectable on a modern macOS. INFERRED cause: removal needs admin rights, and SSID names now need Location permission on macOS 14+. Spruce: list (CoreWLAN with Location, or the `networksetup` list), never preselect, never the current network, removal via helper (04 §11.2).
- **Copy contamination note.** REPLICA-5's Privacy pane description is identical to X's Privacy landing tagline (VERIFIED-SCR-X 6/1). So either 5.x reused X copy, or the replica author copied X. Do not treat REPLICA-5 strings as 5.x proof.

### 4.7 App Permissions: tiles, grouping, actions (gap 04-2, part)
- **5.x (VERIFIED-KB):** recommended reviews appear as tiles on the Protection dashboard. Below them sits a list grouped by permission type (camera, microphone, files and folders, FDA, others). Management is restricted in the App Store edition.
- **X list** (VERIFIED-SCR-X 6/3):
  - heading "Application Permissions" + a one-sentence description;
  - controls **"Group by Permission Type ▾"** (implies a "group by application" alternative) and **"Sort by Name ▾"**;
  - rows: checkbox, permission icon, permission name, chevron (drill into apps), count.
  - Seen: Accessibility 5 · Automation 1 · Camera 7 · Desktop Folder 4 · Documents Folder 9 · Downloads Folder 11 · Full Disk Access 1 · Input Monitoring 1 · Microphone 8 · … (the list continues below the fold).
  - A round **Remove** button: selecting a type or app and removing = revoking the grant.
- **Action mechanism (INFERRED):** `tccutil reset <Service> <bundle-id>` per selected app/service. That works for user-domain services, and for system-domain ones via a root helper. A revoke cannot grant, so "allow" goes through the System Settings deep link (04 §12 anchors).
- **5.x wording of the action:** unknown (gap). Candidates are Remove or Revoke. Spruce uses its own: **Reset Access** (per row) and **Open in System Settings**.
- **Recommended-review tile logic** in 5.x is undocumented. The Spruce heuristics are in 04 §12 (powerful permissions, stale bundles, long-unused camera/mic holders, unsigned clients).

### 4.8 Quit-browser dialog
- The same dialog as §3.9, listing the browsers (VERIFIED-SCR-X 6/2).
- **Ignore** = skip that browser's items. For Safari, Spruce re-estimates after the quit.

---

## 5. Performance (5.x), screen by screen

### 5.1 Landing / dashboard and the "weekly maintenance" card (gap 05-1)
- **VERIFIED-KB (maintenance-tasks, via 02/13):** the Performance landing offers a recommended **weekly maintenance** bundle with **Review** and **Run Tasks**, and **View All Tasks** opens the full task list.
- **REPLICA-5 dashboard:**
  - hero art and tagline (paraphrase: apply curated recommendations or run tasks manually);
  - a **View All Tasks** button;
  - a row of summary cards, each with **Review**:
    - "<N> Maintenance Tasks Recommended" (paraphrase: run the due tasks to keep the Mac in shape);
    - "You Have <N> Login Items" (app-icon cluster; paraphrase: apps that open at startup, consider disabling some);
    - "<N> Background Items Found" (paraphrase: background processes you may not need).
- **Which tasks the weekly card bundles:** undocumented.
  - INFERRED: tasks not run in the last 7 days, from a "routine" subset (Free Up RAM, Flush DNS Cache, Free Up Purgeable Space and, on ≤ 13, Run Maintenance Scripts).
  - **Not** Reindex Spotlight, Speed Up Mail or Repair Disk Permissions, which are symptom-driven per the CMM3 guidance.
  - Smart Care's Performance tile suggests "maintenance scripts and Flush DNS" (VERIFIED-KB smart-care). On 14+, where scripts are hidden, that leaves Flush DNS (+ RAM) (INFERRED).
- **App Store edition:** no maintenance tasks (VERIFIED-KB). So REPLICA-5's maintenance card is the author's own invention, while the Login/Background cards plausibly mirror the reference.

### 5.2 View All Tasks → Performance Manager
- **Left pane** (REPLICA-5): **Maintenance Tasks** · **Login Items** · **Background Items**. Header: Back · "Performance Manager" · Search · Sort by.
- **Maintenance Tasks pane:**
  - rows: checkbox, colourful task icon, task name, an **ⓘ info** button, and after a run the latest result line;
  - footer: "<N> Tasks Selected" and **Run** (REPLICA-5).
- **X equivalent** (VERIFIED-SCR-X 8/1 via 05 §3.1):
  - left list of tasks with round checkboxes, all checked by default;
  - right detail pane: **title**, a 2–3 sentence explanation, **"Usage recommendations:"** bullets, **"Last run date: Today at 12:58"**;
  - round **Run** button with "<N> tasks".
- **Running:** per-row state (queued `•••` → "Running…" spinner → "Done ✓"); the round button becomes **Stop** with a progress ring.
- **Completion:** "<N> tasks completed", "Share Results", **View Log** (warning glyph if any task failed).

### 5.3 Task list by macOS version (gap 05-6)

| Task | macOS 14 Sonoma | macOS 15 Sequoia | macOS 26 Tahoe | Evidence / notes |
|---|---|---|---|---|
| Free Up RAM | ✔ | ✔ | ✔ | VERIFIED-KB; X screenshot |
| Free Up Purgeable Space | ✔ (5.0.5+) | ✔ | ✔ | VERIFIED-DM 5.0.5; KB |
| Flush DNS Cache | ✔ | ✔ | ✔ | VERIFIED-KB |
| Reindex Spotlight | ✔ | ✔ | ✔ | VERIFIED-KB |
| Repair Disk Permissions | ✔ | ✔ | ✔ | VERIFIED-KB (still listed); 05 says it runs `diskutil resetUserPermissions` (CMM3) |
| Speed Up Mail | ✔ | ✔ | ✔ | VERIFIED-KB; the quit-Mail dialog appears if Mail is running (VERIFIED-SCR-X 8/2) |
| Thin Time Machine Snapshots | ✔ | ✔ | ✔ | VERIFIED-KB. INFERRED: shown even with no snapshots (X listed it on a Mac whose TM state is unknown) |
| Run Maintenance Scripts | **✘ (KB: ≤ 13 only)** | ✘ (`periodic` removed) | ✘ | VERIFIED-KB via 01; a late X build listed 7 tasks without it (VERIFIED-SCR-X 8/1) |
| Verify Startup Disk / Rebuild Launch Services | ✘ | ✘ | ✘ | Absent from the X build and the 5.x KB list (05) |

**Spruce rule** (supersedes 05 gap 6). Show **Run Maintenance Scripts** only when `/usr/sbin/periodic` is executable **and** the OS is ≤ 14.x. On 14 it is offered as an *advanced* routine with a note ("macOS normally runs these itself"). This is a deliberate superset of the vendor, which hides it on 14; it is harmless, because `periodic` exists there. On 15+ the task is hidden entirely.

### 5.4 Task detail text structure (for our own copy)
Vendor pattern (X; CMM3 Help topic 9): **What it does** (2–3 sentences) → **When to run it** (bullets of symptoms) → **Last run**.

Spruce adds two rows: **Needs** (admin / quits Mail / Full Disk Access) and **Side effects** (e.g. Spotlight search is slow while it rebuilds). Copy is written fresh, using 05 §4 for facts.

### 5.5 Login Items and Background Items lists (gap 05-1 and 05-4)
- **Semantics (VERIFIED-KB optimization):** separate lists. **Disable/Enable** is reversible; **Remove** is permanent. App Store edition: review only, and launch agents can only be uninstalled.
- **X rows** (VERIFIED-SCR-X 7/2 via 05):
  - checkbox, app icon, "<App>.app Login Item", status dot + **Enabled**;
  - "Sort by Name ▾" in each column, search in the toolbar;
  - the round **Perform** button is disabled until something is checked;
  - no visible per-row action picker.
- **5.x (REPLICA-5):**
  - **Select:** bulk menu; rows: checkbox, real Finder icon, name, a one-line detail (Enabled / Disabled / "Pending — approve in System Settings");
  - footer "<N> Items Selected" and a destructive **Remove**;
  - confirmation "Remove the selected items?", with body variants: login items stop opening at login; background items are permanently removed from disk;
  - a note line: "<N> more items are managed by macOS and can be changed only in System Settings."
  - INFERRED for the direct edition: Enable/Disable also appear (KB semantics), probably as a per-row toggle or an action menu next to Remove.
- **Columns:** neither generation shows true table columns. Each row is icon + name + status subtitle (+ size or count in some lists). The Spruce table (05 §3.4) adds Kind, Developer and Status columns. That is an improvement, not parity.
- **Other apps' SMAppService items, 13+ (gap 05-4):** still not observed in a 5.x screenshot.
  - Platform facts (05 §6.2): BTM per-item writes need the private `com.apple.private.backgroundtaskmanagement.manage` entitlement, and Apple gives it to its own tools only.
  - So 5.x most likely lists SMAppService main-app and login-item helper records as **read-only**, or summarises them in the "managed by macOS / change in System Settings" line (REPLICA-5). It acts only on plist-backed agents and daemons, using `launchctl` disable/bootout and plist removal through its root Agent.
  - **Spruce:** the same split, with an **Open Login Items Settings** button (`SMAppService.openSystemSettingsLoginItems()`) on such rows.
- **Asset hint.** 5.5.4's `PerformanceModule.framework` ships "login-items" and "launch-agents" icon sets (VERIFIED-3P). The internal name is still "launch agents", while the KB says "Background Items".

### 5.6 Quit-apps dialog in Performance
The same component as §3.9. Speed Up Mail lists Mail with **Quit**, and the footer has **Ignore** and **Quit All** (VERIFIED-SCR-X 8/2). INFERRED: **Ignore** = that task is skipped. In the same X run, the completion screen read "6 tasks completed" out of 7 (VERIFIED-SCR-X 8/4 via 05); 05 infers the missing one was skipped or failed, but the causal link to Ignore is not proven.

---

## 6. Spruce screen spec delta (our own words; replaces nothing, adds precision)

| Screen | Spruce label set (original) | Defaults and rules |
|---|---|---|
| Cleanup landing | Title "Cleanup"; rows "System leftovers · Mail downloads · Trash"; button **Scan** | FDA banner if missing |
| Cleanup results | Headline "<size> can be cleared"; cards **System leftovers** (lead), **Mail downloads**, **Trash**; each shows *found* and *selected*; buttons **Inspect** / **Clear** | Card with 0 selected → **Inspect** only |
| Cleanup review | Panes Sections · Groups · Items; header Back · Search · Sort (Size / Name / Date); footer "N selected · <size>" + **Clear** | Reason badges on unchecked rows (03 §3); context menu Reveal / Quick Look / Copy Path / **Never show again** / Explain |
| Quit sheet | "Close these apps to finish?"; per-app **Close**; **Skip these** / **Close all** | Skipped apps' items are reported as "in use" |
| Protection landing | "Protection"; rows "Threat scan · Browser traces · App access"; inline mode control Quick / Standard / Deep | Last-scan line |
| Protection results | Lead tile "Threats"; tiles per browser "<Browser> traces", "Recent lists", "App access to review" | Threats pre-selected; privacy categories selected per 04 §11.1 (cookies unchecked) |
| Protection review | Sections Threats · Browser traces · App access; Sort Name / Count | Passwords never offered; Wi-Fi never preselected; App access actions **Reset Access** / **Open in System Settings** |
| Performance dashboard | "Performance"; cards "Routines due (N)", "Open at login (N)", "Background (N)"; button **All routines** | "Routines due" = routine subset not run in ≥ 7 days |
| Performance review | Sections Routines · Open at login · Background; routine detail What / When / Needs / Side effects / Last run; **Run N** | Scripts routine only when `periodic` exists and OS ≤ 14 |
| Startup lists | Rows icon · name · developer · status (Allowed / Off / Not allowed in Settings / Managed / Broken); actions **Turn Off**, **Turn On**, **Remove…** | SMAppService records of other apps are read-only, with **Open Login Items Settings**; Remove confirms and keeps an undo copy (05 §6.4) |

---

## 7. On-device verification protocol (closes the remaining gaps on the Mac mini)

These checks need a real 5.x install. Use the free trial from MacPaw's site, or `brew install --cask cleanmymac`. Record findings as notes only, **never copy vendor text or art into Spruce**, and uninstall afterwards (cask `zap` paths are in 13 §9).

1. **Version.** `defaults read /Applications/CleanMyMac.app/Contents/Info.plist CFBundleShortVersionString`. The cask installs it as `CleanMyMac.app`; the Finder name is "CleanMyMac".
2. **Label capture without screenshots.** Use Accessibility Inspector (Xcode › Open Developer Tool) on each screen. Alternatively, run `osascript -e 'tell application "System Events" to tell process "CleanMyMac" to get entire contents of window 1'` once Automation and Accessibility are granted. Capture the landing, results, manager, footers and dialogs for all three modules.
3. **System Junk order and exceptions.** Seed fixtures:
   - `mkdir -p ~/Library/Caches/com.spotify.client/Data ~/.gradle/caches/test` with dummy 50 MB files;
   - an old DMG in `~/Downloads`;
   - a fake Sparkle `PersistentDownloads` item.

   Run Cleanup, then record the group order (default sort), the unchecked groups and items and their tooltips, and where the DMG surfaces (My Clutter vs Applications).
4. **Exception list text.** Open the in-app Help or KB link for System Junk in a normal browser on the Mac and note every named exception. That closes C5.
5. **Trash pre-checks.** Put a file in the startup trash and a USB stick's trash, and delete a Photos item and a Mail message. Record which rows appear and which are checked, in the module **and** in Smart Care.
6. **Protection flow.** Is there one Scan for all three sub-areas? Record the tile set; whether App Permissions tiles exist; the left-pane sections; the App Permissions action name and whether it calls `tccutil`. Watch `log stream --predicate 'process == "tccd"'` during a revoke.
7. **Privacy categories.** With Safari, Chrome and Firefox installed, record each browser's category rows and whether **Saved Passwords**, **Chats**/Messages and **Wi-Fi Networks** appear, and which are checkable.
8. **Performance on three OSes.** Run 5.x in macOS 14, 15 and 26 VMs (UTM / Virtualization.framework) and record the View All Tasks list and the weekly card contents on each. That confirms F2/F3.
9. **SMAppService handling.** Install an app that registers an `SMAppService.agent` (Spruce's own helper works) and one that uses `SMAppService.mainApp`. Check whether 5.x lists them, under which list, which actions are enabled, and what the confirmation says. Compare `sfltool dumpbtm` before and after. That closes F6.
10. **Optional: localization tables (research only).** `find /Applications/CleanMyMac.app -name '*.strings' -o -name '*.stringsdict' -o -name '*.xcstrings' -o -name '*.loctable' | head -50`, then `plutil -p <file> | grep -i -E 'spotify|gradle|not selected|managed by macOS'`. Check MacPaw's EULA first. Use the results only to *confirm behaviour*; do not reuse the text.

---

## 8. Remaining gaps after this pass

1. **The full 5.x System Junk exception list** (beyond Spotify and Gradle). *Open*; needs the KB page or §7.3–7.4.
2. **5.x on-screen group order** and exact card set on the Cleanup dashboard. *Open* (REPLICA-5 only).
3. **Smart Care's treatment of external-drive trash in 5.x.** *Open.*
4. **Direct-edition Protection manager:** App Permissions placement and action wording. *Open* (best reading: left-pane section; revoke via `tccutil`).
5. **Saved Passwords / Chats in 5.x Privacy.** *Open* (best reading: passwords informational at most; chats absent).
6. **Performance weekly-card composition** and other apps' SMAppService handling. *Open*; §7.8–7.9.
7. **Exact 5.x copy for every label.** Intentionally not pursued beyond recognition-level labels; Spruce writes its own.

---

## 9. Sources

**Fetched in this session**
- MacPaw DevMate cumulative release notes 5.0.0 → 5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html (VERIFIED-DM)
- MacPaw DevMate 5.x appcast (builds 50003 → 50301; archives hosted on `dl.devmate.com`, which is blocked here): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml (VERIFIED-DM)
- Real CleanMyMac X screenshots plus descriptions (dora-ai dataset), routes read for this report:
  - https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/2/2/image.png (System Junk result)
  - …/routes/2/3/image.png (quit-apps dialog)
  - …/routes/3/2/image.png (Mail Attachments result)
  - …/routes/4/2/image.png (Trash Bins result)
  - …/routes/5/1/image.png (Malware landing with mode + Configure…)
  - …/routes/5/3/image.png (Malware clean result)
  - …/routes/6/1/image.png (Privacy landing)
  - …/routes/6/3/image.png (Privacy list incl. Application Permissions)
  - descriptions: https://github.com/kafkaGen/dora-ai/blob/main/help/neo4j/import/graph_export.json
  - Routes 1, 7 and 8 were read by 05; I re-used its findings.
- VaderCleaner (third-party clone built against CMM 5.5.4 MAS), REPLICA-5:
  - https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/HEAD/docs/cleanmymac-3d-assets.md (bundle teardown: frameworks, asset names, malware-family glyphs, Moonlock promo art)
  - …/VaderCleaner/ProtectionDashboardView.swift, …/VaderCleaner/ProtectionDashboardSubviews.swift, …/VaderCleaner/ProtectionManagerView.swift
  - …/VaderCleanerCore/Sources/VaderCleanerCore/ProtectionPrivacyCategory.swift
  - …/VaderCleaner/PerformanceDashboardSubviews.swift
  - …/VaderCleanerCore/Sources/VaderCleanerCore/CleanupGroup.swift, …/CleanupManagerModel.swift, …/ManagerModel.swift, …/SectionPresentation.swift
  - …/VaderCleaner/SystemJunkDashboardSubviews.swift, …/VaderCleaner/SettingsScanningTab.swift, …/docs/Optimization.md
- REPLICA-X: https://github.com/ddlmanus/MacOptimizer (SystemJunkReplicaView.swift, PrivacyReplicaView.swift, MalwareRemovalReplicaView.swift), as cited by 03/04.

**Cited via sibling reports (VERIFIED-KB; not re-fetchable here)**
- https://macpaw.com/support/cleanmymac/knowledgebase/system-junk · …/trash-bins · …/malware-removal · …/protection-scan-options · …/privacy · …/app-permissions · …/maintenance-tasks · …/optimization · …/missing-features · …/smart-care · …/cleanmymac-safety · …/full-disk-access
- https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk · …/mail-attachments (DE) · …/safety-database
- MacPaw CLI: https://github.com/MacPaw/cleanmymac-cli (README, wiki), via 03/13.

**Checked and rejected as evidence**
- `gaowujian/obsidian-vault` (an AI-written summary, as 08 also concluded).
- `alex-foster-personal/cleanmymacfree` (an AI design-tool wireframe, not derived from the product).
- `Flopsi69/crs` (X-era homepage copy only).
