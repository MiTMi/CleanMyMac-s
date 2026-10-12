# 20 — Gap-fill 03: CleanMyMac 5.x Applications, My Clutter, Space Lens and Cloud Cleanup as shipped

> **Assignment:** close 06 §10 gaps 1, 3, 4, 6 and 7 and 07 §15 gaps 2, 3, 5 and 6. In particular: the 5.x Applications window, what the Updater's **Update** button really does (this decides what Checkup "Run" does to apps), the Clutter keep rules, and the Cloud Cleanup account model. Also settle the 06 ↔ 13 contradiction on whether our updater replaces app bundles.
> **Target of our build:** *Spruce* (see `docs/ARCHITECTURE.md`). Modules `Applications`, `Clutter`, `SpaceMap`, `CloudStorage`. Apple-silicon Mac mini, macOS 14 / 15 / 26.
> **Product studied:** MacPaw CleanMyMac 5.x (current 5.7.1, build `50701.0.2609301754`), with CleanMyMac X 4.x as the direct ancestor.
> **Date:** 2026-10-12.

---

## 0. Method, access limits, evidence labels

### 0.1 Reachability (read first)

- **WebSearch returned nothing.** The shared per-turn budget ("200 WebSearch calls per turn, shared by every agent") was already spent, so the one search I attempted was refused. As instructed, I did not work around this.
- **Blocked or unresolvable hosts** (DNS failure in WebFetch, or `403 CONNECT` from the egress proxy; none were routed around):
  - `macpaw.com`, `cleanmymac.com`, `apps.apple.com`, `setapp.com`;
  - `www.youtube.com`, `www.prnewswire.com`;
  - `chrischinchilla.com`, `www.iphoneincanada.ca`;
  - `updates.cleanmymac.com` (the current 5.x appcast host), `dl.devmate.com`;
  - `ph-files.imgix.net` (Product Hunt screenshots).
- **What was reachable:** GitHub code search (MCP tool), `raw.githubusercontent.com`, and MacPaw's DevMate release-note pages on S3.
- **What I did instead of web searches:** about 30 targeted GitHub code searches and about 60 file or page fetches. Six sources are **new to the team**:
  1. **Chris Chinchilla's 2026 Cloud Cleanup review.** The blog is built from a public GitHub repo, so I read the Markdown source of the post itself.
  2. **MacSparky's Cloud Cleanup post**, captured in a public RSS archive (`rlridenour/elfeed-db`). It paraphrases MacPaw's own announcement.
  3. **The Product Hunt launch text for "Cloud Cleanup in CleanMyMac"** (2025-08-04), via two daily-digest repos.
  4. **Real CleanMyMac X screenshots not used before:**
     - a 2020 review with the Uninstaller, the Updater mid-run and Space Lens;
     - routes 9 (Uninstaller), 10 (Updater), 12 (Space Lens, five screens) and 13 (Large & Old) of the `kafkaGen/dora-ai` dataset, a late 4.15.x build. Earlier reports used only routes 1–8.
  5. **DevMate release notes for X 4.0.0–4.6.10** (S3). These carry the Updater/Uninstaller/Space Lens history lines that the 4.10+ notes used in 06 lack.
  6. **VaderCleaner's Applications, Space Lens and My Clutter code**, plus its inventory of the CleanMyMac **5.5.4** bundle's `SpaceLensUI.framework` assets. Gap-02 used only its Cleanup, Protection and Performance code.

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED-DM** | Read directly in MacPaw's DevMate release notes on S3 (URL in §8). |
| **VERIFIED-SCR-X** | Read directly by me off a **real CleanMyMac X screenshot**. **[IJ20]** = the 2020 review (X 4.x on Catalina); **[DORA]** = a late 4.15.x build (Moonlock era, Claude app installed). |
| **VERIFIED-3P** | A third party's hands-on observation or bundle inspection, with URL. |
| **VERIFIED-KB** | A MacPaw help-centre or how-to fact read by a sibling track (01/06/07/13), via search excerpt. URL given; not re-fetchable here. |
| **VERIFIED-OSS** | Read in open-source code or docs (Latest, mas). |
| **REPLICA-5** | VaderCleaner code or comments that say they "mirror the reference". The reference is CleanMyMac **5.5.4 (MAS edition)** (`docs/cleanmymac-3d-assets.md`). Layout claims are moderate evidence; copy may be paraphrased. |
| **INFERRED** | Our reasoning or a recommendation for Spruce. |

**Copy policy.** Vendor labels are quoted only so the team can recognise screens. Spruce must not reuse them, nor MacPaw art, the circular frame design, or the pink selection glow. Our own wording is in §6.

---

## 1. Answer sheet

Confidence: **H** = vendor-verified for 5.x · **M** = verified for X and consistent with 5.x evidence (KB or REPLICA-5) · **L** = inference.

### 1.1 Applications

| # | Question | Best answer | Conf. |
|---|---|---|---|
| A1 | Result tiles after a scan | Header: installed-app count, plus **Manage My Applications**. Then 2–4 tiles: **Unused Applications** (count, with total size in the subline); **Updates** (count; primary button **Update**); **App Leftovers** (size; **Review** and a direct **Remove**); **Installation Files** (size; **Review**). The lead tile is a tall card on the left; the others stack on the right. | M |
| A2 | Manage My Applications layout | A three-pane manager. Left nav: **Uninstaller · Updater · Leftovers** (Installation files is a section inside Leftovers in the replica). Middle: facet column. Right: item list with a drill-in detail. Header: Back · title · Search · "Sort by:" (Name / Last Opened / Size). Footer: "N … Selected · size" plus a context action (**Uninstall** / **Update** / **Remove**). | M (structure), L (nav order) |
| A3 | 5.x Uninstaller groups | Top block: **All Applications · Unused · Suspicious · Selected**. **Stores**: App Store · (Steam, when Steam games exist) · Other. **Vendors**: one row per vendor, then Other. *Leftovers* has left this column and became its own nav item. X's **32-Bit** row is gone. There is no evidence of a separate iPhone/iPad group. | M |
| A4 | Current meaning of Suspicious | The only definition published is X 4.10.4's: apps "associated with or owned by Russian or Belarusian developers". The 5.x KB still lists the group but gives no new definition. | M (X), L (5.x) |
| A5 | Per-app detail pane | Clicking the chevron drills into that app's resource list. X shows the **Dock icon** and **Login Items** as resource rows. Reset vs Uninstall uses the CMM3 "Smart Selector" logic; its 5.x placement is unverified. A **Smart Insights** icon sits beside app names on Tahoe with Apple Intelligence. | L–M |
| A6 | Leftovers / Installation files default | The Leftovers tile has a one-click **Remove**, so leftovers are treated as pre-approved. Installation files get **Review** only, so nothing is pre-selected. | L–M |
| A7 | Updater groups | **App Store Updates · Sparkle Updates · Custom Updates · macOS Updates**. The App Store edition has neither App Store nor macOS groups. | H |
| A8 | What **Update** does | **Sparkle and Custom: downloaded and installed in-app**, as a progress queue. **App Store:** installed in-app in X (2020 screenshot); 5.x behaviour unverified. **macOS:** notify only (hand-off to Software Update). See §2.8. | M / L / M |
| A9 | Paid or major upgrades; running apps | No vendor text on either. The only related vendor rule is the X 4.13.6 note: no updates the installed macOS can't run. | gap |
| A10 | 5.5.5 background scan | The Applications scan runs in the background; you can act on apps, leftovers and installers before it ends. | H |

### 1.2 My Clutter

| # | Question | Best answer | Conf. |
|---|---|---|---|
| B1 | Location picker | Home folder · a disk · an external drive. The replica adds "Choose folder…". | H / M |
| B2 | Tiles and headline structure | Header: "You have **N** files to sort through." Subline: use quick recommendations or review by hand. Button: **Review All Files**. Tile headlines follow **`<count or size> <category> Found`**, plus one sub-line. The Downloads tile names the **dominant source app**. | M |
| B3 | Review All Files manager | Three panes: categories → facets/groups → files + preview. Large & Old facets: All Files · Selected · By Kind · By Size (X also had By Access Date). Duplicates and Similar: groups (thumbnail, original's name, size, copy count). Downloads: by source app. Preview pane: big preview, Modified / Created / Size / File type, and a "Select:" menu (All Copies / None). Footer: "N Items Selected" + **Remove**. | M |
| B4 | Duplicate keep rule; destination | Neither is documented for 5.x. Lineage is Gemini 2 (keeper modes "Automatically / Newest / Oldest / Any"; Trash with "Put All Back"). Late X Large & Old and Space Lens defaulted to **permanent** removal. | L |
| B5 | Similar Images default | Undocumented. Gemini never auto-selected "similar". One replica pre-selects them. | L |

### 1.3 Space Lens

| # | Question | Best answer | Conf. |
|---|---|---|---|
| C1 | Volume / folder picker | A card with the disk icon, "‹Volume›: ‹capacity›", a usage bar, "‹used› Used" and an up/down chooser (X). 5.x adds folders. | H (5.x has folders), M (look) |
| C2 | Bubbles: layout, colour, labels | Circle packing, largest to smallest. In X, inside one big circular frame. In 5.x the bubble fills are **tinted at runtime per node**, with states Default / Hover / Selected / Selected-Hover. Each bubble shows the item's icon. Name and size appear only on the large or focused bubble; a hover card gives the details. | H (bubbles), M (rest) |
| C3 | "Smaller items" / Other bubble | 5.x ships a dedicated **"Smaller Items"** bubble (with Focused and Hover states) and an **"Other items"** icon. | M |
| C4 | Navigation | **Start Over** (top-left), back/forward arrows, a breadcrumb ("Macintosh HD › Applications"). Click a bubble or a row chevron to zoom in. Double-click opens Quick Look (X 4.4.6). | M |
| C5 | Selection tray and Review | Bottom bar: volume gauge whose **trailing segment shows the selected size**, a selected-size readout, **Remove** and **Review Selected**. A confirmation sheet lists each item (checkbox, icon, name, path, size). In X it warned that files are **gone forever**. | M |
| C6 | Cloud-only files | X 4.15.4 ignores cloud-stored files. 5.x ships a **"Clouds"** bubble state, most likely one distinct bubble for cloud-only content. Cloud Cleanup reuses Space Lens for cloud drives. | M / L |

### 1.4 Cloud Cleanup

| # | Question | Best answer | Conf. |
|---|---|---|---|
| D1 | Connect flow | **iCloud Drive:** the Mac's own iCloud Drive, no sign-in. **Google Drive:** browser OAuth sign-in. It works **without** Drive for desktop, supports several accounts, and recognises local copies only from Google's official client. **Dropbox:** "connect your Dropbox account". **OneDrive:** account connect, improved in 5.3.0. | M (iCloud L–M) |
| D2 | Shown per account | A **tile dashboard of insights per account**. iCloud groups: "Locally synced files", "Large locally synced files", "Large cloud files". **Quota** ("used of total") for Google. Space Lens map and Large Files list. Per-item icons for local / cloud / both. Smart alerts for unused files and nearly-full storage. | M |
| D3 | Action names | **Remove**: delete from the cloud; for a synced file this removes it from the Mac and the cloud "in one go". **Unsync**: drop the local copy, keep the cloud copy. | M–H |

---

## 2. Applications (5.x)

### 2.1 Results tiles

- **Vendor flow.** Scan → tiles → **Manage My Applications**. The four categories are Uninstaller, Updater, Leftovers and Installation files. VERIFIED-KB (https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller, via 01/06/13).
- **Tile set and copy** (REPLICA-5, `VaderCleaner/ApplicationsDashboardSubviews.swift`, "matching the reference dashboard"):
  - header: a hero image, then "We've found %lld apps on your Mac.", a subline (use quick recommendations or manage them by hand), and the **Manage My Applications** glass button;
  - **Unused**: "%lld Unused Applications Found". The subline gives the total space they use. The tile shows a cluster of the first three app icons. Action: **Review**;
  - **Updates**: "%lld Updates Available". Action: **Update**, which opens the Updater pane;
  - **App Leftovers**: "%@ of App Leftovers Found" (a size). Two actions: **Review** (bordered) and **Remove** (prominent). The replica's Remove "selects every leftover group and moves it to the Trash";
  - **Installation Files**: "%@ of Installation Files Found". Subline: DMGs and installers you no longer need. Action: **Review**;
  - (replica-only) an "Unsupported Applications" tile. INFERRED: a VaderCleaner addition; no vendor source mentions it.
- **Layout.** The tiles are ranked "most actionable first", 2–4 of them. The lead tile is tall on the left; the rest sit in a right column in rows of up to two (REPLICA-5). Empty categories fall back to "No … Found" reassurance cards.
- **Metric rule** (INFERRED from the replica copy):
  - **counts** for discrete decisions (unused apps, updates);
  - **sizes** for disk reclaim (leftovers, installers).

### 2.2 The "Manage My Applications" window

REPLICA-5 (`ApplicationsManagerView.swift`: "three-pane CleanMyMac-style surface (left nav → middle facets → right item list + footer action)"; "The reference Manager uses a magenta accent on a white surface"):

```
┌ ‹ Back      Applications Manager             [Search]   Sort by: Name ▾ ┐
│ Uninstaller │ All Applications  36 │ ○ ▣ AppName.app         ›  1.2 GB │
│ Updater     │ Unused             4 │ ○ ▣ …                              │
│ Leftovers   │ Suspicious           │   (chevron › = drill into the     │
│             │ Selected             │    app's resource list)           │
│             │ STORES               │                                    │
│             │  App Store 3 · Steam 1 · Other 32                         │
│             │ VENDORS              │                                    │
│             │  Apple · Microsoft · MacPaw · … · Other                   │
├─────────────┴──────────────────────┴────────────────────────────────────┤
│  N Applications Selected · size                           [ Uninstall ] │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Deep links.** Every dashboard **Review** opens the manager on the pane and facet where its finding lives: Unused → Uninstaller › Unused; Leftovers → Leftovers › leftover files; Installation files → Leftovers › installers (REPLICA-5 `Destination` enum).
- **Sort options per pane** (REPLICA-5):
  - Uninstaller: Name, Last Opened, Size;
  - Leftovers: Name, Size;
  - Updater: Name only.
  - Consistent with X: "Sort by Name" was the default, and sorting by last-open date came in 4.15.4 (VERIFIED-SCR-X [DORA 9/1]; 06 [DM-X15]).
- **Footer labels** (REPLICA-5): "No Applications Selected" / "%lld Applications Selected"; "%lld Items Selected" for leftovers.
- **Nav order and an Extensions pane.** The replica's nav has Uninstaller, Updater, Extensions, Leftovers, Unsupported. **No 5.x vendor source mentions an Extensions or Unsupported pane**: 5.x My Tools lists no Extensions tool (01). INFERRED: the vendor nav is **Uninstaller · Updater · Leftovers**, with Installation files either a fourth item or a section inside Leftovers. Spruce keeps Extensions as an extra pane (06 §5).
- **Visual change from X.** X drew this inside the main window, with the module sidebar replaced by "‹ Intro" and a filter column (VERIFIED-SCR-X [IJ20], [DORA 9/1]). 5.x opens a raised white card over the module's coloured canvas (REPLICA-5).

### 2.3 Uninstaller groups: evolution and final list

| Build | Top block | Stores | Vendors | Evidence |
|---|---|---|---|---|
| X, 2020 | All Applications 76 · **Unused** 0 · **Leftovers** 16 · **32-Bit** 0 · Selected | App Store 20 · Other 56 | Apple 6 · Microsoft 7 · Adobe 13 · Google 2 · MacPaw 2 · Other 46 | VERIFIED-SCR-X [IJ20] |
| X 4.15.x (dora) | All Applications 36 · **Unused** 4 · Leftovers 21 · **Suspicious** (no count) · Selected | App Store 3 · **Steam 1** · Other 32 | Apple 1 · Microsoft 1 · MacPaw 4 · JetBrains 1 · Other 29 | VERIFIED-SCR-X [DORA 9/1] |
| X 4.15.x (06's reference image) | All Applications · Leftovers · Suspicious · Selected | App Store · Other | per vendor · Other | VERIFIED-PX (06) |
| 5.x KB | All Applications · Unused (6 months) · Suspicious · "…" | — | — | VERIFIED-KB |
| 5.5.4 replica | All · Unused · Suspicious · Selected | App Store · Other (+ Homebrew, a replica addition) | per vendor | REPLICA-5 (`ApplicationsManagerModel.swift`: "Mirrors the reference layout: the top group (All / Unused / Suspicious / Selected), then a store group, then a per-vendor group") |

**Corrections to 06**

- **"Unused" is not 5.x-only.** X had it in 2020 and in late 4.15 builds. 06's reference screenshot simply lacked the row. Possibly that build hides the row when the group is empty, or it is a different X build (INFERRED).
- **"Steam" is a Stores row** when Steam games are installed (VERIFIED-SCR-X [DORA]). X 4.1.0 added "Manage your Steam games easily with CleanMyMac's Uninstaller" (VERIFIED-DM 4.1.0).
- **"32-Bit" existed in 2020** and is gone in late X. INFERRED: removed because 32-bit apps can't run on macOS 10.15+ (and most were deleted).

**Spruce's final list (INFERRED)**

| Group | Rule |
|---|---|
| All Applications | every non-ignored app |
| Unused | `kMDItemLastUsedDate` older than 180 days (fallback: date added) |
| Suspicious | 06 §3.4 heuristics. Ours means *security-suspicious*; we do not copy the vendor's nationality list. |
| Selected | apps with a pending action |
| Stores | App Store (includes wrapped iPhone/iPad apps) · Steam (only if present) · Homebrew (only if present) · Other |
| Vendors | per vendor, then Other |
| (optional) Intel-only, Unsupported | 06 §3.4 |

Leftovers is **not** in this list. It lives in its own pane (§2.6).

### 2.4 Suspicious

- **The only definition published:** "A new category in the Uninstaller module — Suspicious — where CleanMyMac puts apps associated with or owned by Russian or Belarusian developers". VERIFIED-DM (X 4.10.4, in the DevMate notes cited by 06).
- **5.x:** the KB names the group, but no reachable text redefines it (gap). On screen it shows no count when empty (VERIFIED-SCR-X [DORA 9/1]).
- **Spruce:** keep the slot and fill it with signature and behaviour heuristics (06 §3.4). INFERRED.

### 2.5 Per-app detail pane

**Verified history (X)**

- The row chevron or ▸ opens the app's resource list (VERIFIED-SCR-X [IJ20] ▸, [DORA 9/1] ›).
- "Uninstaller did not show **Dock icons** among application resources" was fixed in 4.3.0. The Dock tile is therefore a listed resource (VERIFIED-DM 4.3.0).
- "Incorrect sizes of **Login Items** within Uninstaller" was fixed in 4.4.3. Login items are listed resources too (VERIFIED-DM 4.4.3).
- Separate leftover files can be added to the Ignore List (VERIFIED-DM 4.3.0).
- "Removal of **Group Containers** … when deleting the **last app using them**" arrived in 4.6.10. This is a shared-container ownership rule (VERIFIED-DM 4.6.10).
- "Uninstaller could detect the **running app** as leftovers" was fixed in 4.6.10. Running apps must be excluded from orphan detection (VERIFIED-DM 4.6.10).
- CMM3 "Smart Selector": **Complete Uninstallation** vs **Application Reset**, where Reset keeps the binary (06 §1 item 4, VERIFIED).

**5.x additions (VERIFIED-KB, via 01/06)**

- A **Smart Insights** icon beside app names (Apple silicon, macOS 26, Apple Intelligence on).
- The App Store edition can only **reset** App Store apps.
- System apps are on the ignore list by default and can be reset only.

**Spruce detail pane (INFERRED; layout is our own)**

1. **Header:** icon, name, version, vendor, signature badge, source badge (App Store / Steam / Homebrew / Setapp), last opened, total size, and an ⓘ "Explain" button (Foundation Models on macOS 26, 06 §6).
2. **Mode:** a segmented control **Uninstall / Reset**. Reset unticks the app bundle and anything inside it. Toggling an item by hand flips the mode to "Custom".
3. **Resource groups** (tri-state checkboxes, count, size): Application · Preferences · Application Support · Caches · Containers & Group Containers · Logs & Crash Reports · Saved State · Launch Agents/Daemons & Login Items · **Dock icon** · Other.
4. **Shared Group Containers:** pre-ticked only when no other installed app declares that `com.apple.security.application-groups` ID. Otherwise show it unticked with "Shared with ‹App›".
5. **Footer action** relabels to **Uninstall** / **Reset** / **Remove** (CMM3 rule).

### 2.6 Leftovers and Installation files

- **Vendor:**
  - Leftovers = service files of apps the user removed by hand (VERIFIED-KB);
  - leftover search arrived in X 4.1.0 ("Uninstaller shows app leftovers", VERIFIED-DM);
  - search speed improved about 2× in 4.5.1 and up to 5× in 4.5.2 (VERIFIED-DM).
- **Default selection.**
  - Leftovers tile: Review + **Remove** (REPLICA-5). A direct Remove on a tile means the group is pre-approved, so leftovers are **effectively selected by default** in 5.x (INFERRED, L–M).
  - Installation files tile: **Review** only, so nothing is pre-selected (INFERRED, L).
- **Spruce (INFERRED, adjusted to this evidence):**
  - Pre-select only leftovers with **strong ownership proof** (06 §3.5, score ≥ 70). Weaker matches are shown unticked under "Possibly related".
  - The tile's one-click Remove acts only on the pre-selected set and moves it to the Trash.
  - Installation files keep 06 §3.14's rules. They are pre-selected only when the matching app is installed and the file is more than 30 days old.

### 2.7 Updater groups

- **5.x groups:** **App Store Updates · Sparkle Updates · Custom Updates · macOS Updates**. VERIFIED-KB (uninstaller KB and X updater KB, via 01 §5.2 / 06 §4.1).
- **App Store edition:** has neither App Store nor macOS groups. VERIFIED-KB.
- **X list details:**
  - empty state: centred title and one line saying all your Mac's software is up to date, with a disabled round **Update** button. Header: "‹ Intro" and Search (VERIFIED-SCR-X [DORA 10/1]);
  - details pane: version → version, date, size, a screenshot carousel and release notes (06 §4.1, VERIFIED-PX);
  - release notes are displayed: 4.4.6 fixed a crash on "unexpected Release Notes format" (VERIFIED-DM).
- **Spruce:** keep the four vendor groups and add **Homebrew**, **Ignored/Skipped**, and a **Selected** facet (06 §4.7). INFERRED.

### 2.8 What "Update" actually does

**Evidence**

| # | Evidence | What it shows | Label |
|---|---|---|---|
| 1 | X 4.0.1 notes: the Updater "will check all of your installed software for available updates and **let you apply them**". | The updater applies updates; it does not just report them. | VERIFIED-DM |
| 2 | X 4.1.0: "the Updater lets you update **several apps or even all of them at once**". 4.1.2: "Added a **side progress indicator** for the Updater module". | A batch queue with progress, i.e. work done inside CleanMyMac. | VERIFIED-DM |
| 3 | **2020 screenshot:** "Updating 8 applications". Per-row status: the first row shows "Updating…" with a spinner; queued rows show "•••". A central round **Stop** button. The sidebar Updater row shows a progress dot. Rows: Spark, Messenger, Day One, SiriMote, Pixelmator Pro, VLC, BibDesk, TeX Live Utility. | In-app, **sequential** installation. The list mixes apps that were Mac App Store titles in 2020 (Day One, Pixelmator Pro, Messenger; channel identification INFERRED) with Sparkle apps (VLC, BibDesk, TeX Live Utility). | VERIFIED-SCR-X [IJ20] |
| 4 | X 4.2.0: "Apart from apps, Updater will **let you know** about macOS updates." | macOS updates are informational: a hand-off. | VERIFIED-DM |
| 5 | X 4.11.2 / 4.11.3: the Updater "is now **capable of updating** Zoom / Chrome". | Custom (non-Sparkle) updaters are driven by CleanMyMac itself. | VERIFIED-DM (via 06) |
| 6 | X 4.12.2: fixed "Updater used to offer some updates after they were already installed". | A post-install re-read is needed. | VERIFIED-DM (via 06) |
| 7 | 5.x Smart Care: the Applications tile counts app updates (excluding system apps and macOS), all selected by default, and **Run updates the selected apps**. | Unattended in-app updating in 5.x. | VERIFIED-KB (smart-care KB, via 02) |
| 8 | 5.5.7, on-device: Smart Care reported "1 important update". | Smart Care surfaces updates; 5.x may flag "important" ones. | VERIFIED-3P (StorageCleanerMac audit, 2026-08-25) |
| 9 | The App Store edition lacks the App Store and macOS groups. | Weak signal. If the direct edition only *opened* the App Store, a sandboxed build could do the same. So the direct edition probably uses a mechanism the sandbox forbids: private App Store frameworks or root. It could also simply be App Review policy. | VERIFIED-KB fact; reading INFERRED |
| 10 | The X helper protocol had root `moveItemAtPath`, `removeItemAtPath`, `moveToTrashItemAtPath`, `removePackageWithID`, `removeLaunchdAgentAtPath`, `enable/disableLaunchdAgentAtPath`, `removeKextAtPath` and others (2018). | A root file mover existed. Bundles owned by root or by another user could be swapped in place. | VERIFIED-3P (Cisco Talos TALOS-2018-0705…0719) |

**Conclusion**

- **Sparkle Updates:** CleanMyMac downloads and installs the update itself, as a queue with per-row progress and a Stop control. It does **not** open each app's own updater. Confidence **M**: verified for X, and consistent with 5.x Smart Care "Run".
- **Custom Updates** (Chrome, Zoom, Microsoft): CleanMyMac performs the update itself. It most likely uses the vendor's own installer or update agent, since Chrome is Keystone-managed and Office is MAU-managed. INFERRED. Confidence **M** that the update happens in-app; **L** on the mechanism.
- **App Store Updates:**
  - in-app on X in 2020 (screenshot);
  - on 5.x, unverified;
  - INFERRED: still attempted in-app, through private App Store frameworks.
  - Modern constraint: the open-source `mas update` needs **root privileges and a signed-in Apple Account** (VERIFIED-OSS, https://github.com/mas-cli/mas README "Root Privileges"). Confidence **L**.
- **macOS Updates:** shown for information; acting on one opens Software Update. Confidence **M**.

**Decision for Spruce: this resolves the 06 ↔ 13 contradiction (INFERRED)**

13 §3.41 said "we never replace bundles ourselves". 06 §4.2.4 specified an atomic swap. **Both are partly right.** The rule from here on:

1. **Sparkle apps: install in-app, through Sparkle itself, never with our own swap code.**
   - Embed Sparkle 2. For each selected app, create `SPUUpdater(hostBundle: targetApp, applicationBundle: targetApp, userDriver: autoDriver, delegate: self)`.
   - The driver replies `.install` to `showUpdateFound` and `showReady(toInstallAndRelaunch:)`, and maps the download and extraction callbacks to row progress. This is exactly what Latest's `SparkleUpdateOperation` does (VERIFIED-OSS, https://github.com/mangerlahn/Latest/blob/main/Latest/Model/Updater/SparkleUpdateOperation.swift).
   - Sparkle then does the EdDSA and code-signature validation, the extraction, and the atomic replace through its `Autoupdate` helper.
   - **Pre-flight:**
     - an App Management grant (06 §4.2.4; macOS 13+). Without it, offer **Open App** for that row;
     - no `sparkle:informationalUpdate`. If there is one, offer **Download page** instead;
     - installed version ≥ `sparkle:minimumAutoupdateVersion`. If not, it is a *major upgrade*, see §2.9.
2. **App Store apps: hand off.**
   - Open `macappstore://showUpdatesPage`, or the app's page from the iTunes lookup `trackViewUrl`.
   - Optional advanced setting: "Use `mas` if installed". It runs through `PrivilegedRunner` because `mas update` needs root (VERIFIED-OSS).
   - We do not ship private CommerceKit code.
3. **Custom:**
   - **Homebrew casks:** `brew upgrade --cask <token>`, run as the user.
   - **Microsoft (MAU):** `msupdate --install --apps <id>` when MAU is present.
   - **Google Keystone:** trigger the app's own agent, or fall back to **Open App**.
   - **Zoom / others:** **Open App** or **Download page**.
   - No hand-rolled bundle swap in v1. (06 §4.2.4's verified-swap design stays a documented v2 option.)
4. **macOS:** open System Settings › General › Software Update. Never install from inside Spruce.
5. **Checkup "Run" on apps:**
   - pre-selects and runs only updates that can complete **unattended**: Sparkle (with the App Management grant) and Homebrew;
   - App Store, Keystone and other hand-off rows appear **unselected**, with a note that they open the App Store or the app;
   - after every run, re-read `CFBundleShortVersionString`/`CFBundleVersion` **uncached** (the vendor bug class in row 6).
6. **ARCHITECTURE rule 4** ("Never modify app bundles") is untouched. Sparkle replaces a bundle with the vendor's own signed bundle; we never edit bundle contents.

### 2.9 Paid or major upgrades, running apps

- **Vendor:** no text on paid upgrades (gap remains). The one related rule is X 4.13.6: "won't suggest application updates that are not supported by your macOS version" (06 §4.1, VERIFIED-DM).
- **Running apps:**
  - X asks the user to quit apps before cleaning, with per-app and "quit all" options (dora route 1/4 "Application Quit Prompt", VERIFIED-3P description);
  - Sparkle itself terminates and relaunches the host app during install (`showInstallingUpdate(withApplicationTerminated:)`, VERIFIED-OSS Latest).
- **Spruce (INFERRED):**
  - **Major or paid** (major version bump, `minimumAutoupdateVersion` not met, or flagged in our knowledge base): listed in a separate "Major upgrades" section, **never pre-selected**, with a note that a new licence may be required. The action is **Download page** (Sparkle) or **Open App Store**.
  - **Running app** selected for update: one sheet listing all running apps, with "Quit & Update" (relaunch afterwards), "Skip these" and "Cancel". Never force-quit an app holding unsaved documents. Use `NSRunningApplication.terminate()`, then wait up to 10 s, then mark the row "Skipped (still open)".

### 2.10 Background scanning (5.5.5)

- **Vendor:** "Applications module scans in background", so you can act on apps, leftovers and installers before the scan ends. VERIFIED-KB (https://macpaw.com/cleanmymac/whats-new, via 01 §6).
- **Spruce (INFERRED):**
  - Run four independent scanners: catalogue, updates, orphans, installers.
  - Each publishes partial results. Tiles appear and grow as each finishes; a small spinner marks tiles still scanning.
  - **Manage My Applications** is enabled as soon as the catalogue finishes, typically in under 2 s.
  - Update checks keep streaming into the Updater pane. Selections survive incremental updates, keyed by bundle ID.
  - The scanners keep running when the user switches modules, and finish with a notification badge on the sidebar item.

---

## 3. My Clutter (5.x)

### 3.1 Location picker

- **Vendor:** choose a location (the home folder, a disk, an external drive), then scan, then **Review All Files**. VERIFIED-KB (https://macpaw.com/support/cleanmymac/knowledgebase/free-up-more-space, via 01/07/13).
- **Replica:** "Which folder the My Clutter scan walks (home subtrees by default)", plus a picked folder. REPLICA-5 (`VaderCleanerApp.swift`).
- **Spruce:** a chip menu with Home (default) · Macintosh HD · each external volume · Choose Folder…. Remember the last choice. INFERRED.

### 3.2 Dashboard tiles and headline structure

REPLICA-5 (`MyClutterDashboardView.swift`). The same keys appear independently in PristineCleaner's `en.i18n.json` (VERIFIED-R in 07 §3.2).

- **Header:**
  - "You have %lld files to sort through.";
  - a subline: use quick recommendations or review them by hand;
  - a **Review All Files** button;
  - a **Start Over** control at top-left.
- **Tiles** (2–4, largest reclaimable first, backfilled with reassurance cards):

| Tile | Headline pattern | Sub-line pattern | Thumbnail |
|---|---|---|---|
| Duplicates | "%lld Duplicates Found" | remove ‹size› of duplicate files | real file thumbnails |
| Similar Images | "%lld Similar Images Found" | ‹size› of nearly identical photos | photo thumbnails |
| Large & Old | "‹size› of Large and Old Files Found" | — | file icons |
| Downloads | "‹size› of ‹Source App› Downloads Found", else "‹size› of Downloads Found" | — | source-app icon |

- **Structure rule** (INFERRED): **headline = metric + category + "Found"**.
  - The metric is a **count** for decision-per-item categories (duplicates, similar images).
  - It is a **size** for bulk-reclaim categories (large & old, downloads).
  - The sub-line restates the other metric.
  - The same grammar appears in Applications (§2.1).
- **Empty states:** a reassurance card when a scan finds fewer than two categories (REPLICA-5).

### 3.3 The "Review All Files" manager

**REPLICA-5** (`MyClutterManagerView.swift`: header "My Clutter Manager", "The reference Manager uses a magenta accent on a white surface"):

```
┌ ‹ Back     My Clutter Manager                 [Search]   Sort by: ▾       ┐
│ Large & Old  │ All Files        │ ○ ▣ name.mkv   ~/Movies   33.5 GB      │
│ Duplicates   │ Selected         │ …                                        │
│ Similar Imgs │ BY KIND          │ (Duplicates/Similar: thumbnail strip     │
│ Downloads    │  Archives/Movies/Other │  with the kept original flagged,    │
│              │ BY SIZE          │  big preview, Modified / Created / Size /│
│              │  >5 GB · 1–5 GB · <1 GB │  File type, "Select: All Copies |  │
│              │ (groups / source apps   │  None")                           │
│              │  for the other categories)                                  │
├──────────────┴──────────────────┴──────────────────────────────────────────┤
│  N Items Selected · size                                       [ Remove ]  │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Verified X ancestor** (VERIFIED-SCR-X [DORA 13/2], Large & Old list):
- facets **All Files · Selected**;
- **By Kind**: Documents · Pictures · Movies · Other;
- **By Size**: Huge · Small;
- **By Access Date**: One Year Ago · One Month Ago · Last Week;
- title "All Files", "Sort by Size ▾", rows with a round checkbox, icon, name and size;
- nothing pre-selected;
- a removal-mode pop-up next to the round **Remove** button, showing "**Remove Immediately**" in that build.

**Facets per category (INFERRED synthesis for Spruce):**

| Category | Middle-pane facets | Right pane |
|---|---|---|
| Large & Old | All Files · Selected · By Kind (Documents, Pictures, Movies, Music, Archives, Other) · By Size (Huge ≥ 5 GB, Large 1–5 GB, Medium < 1 GB) · By Last Opened (Last week, Last month, 6+ months, 1+ year) | list, Quick Look on Space |
| Duplicates | one row per group: thumbnail, keeper's name, reclaimable size, copy-count badge | thumbnail strip with the **keeper flagged**, large preview, metadata, "Select: All Copies / None" |
| Similar Images | the same as Duplicates, with a "best shot" badge | the same as Duplicates |
| Downloads | by source app (icon + name), then by kind | list with source URL / app and download date |

### 3.4 Duplicates: keep rule and where removed files go

- **Vendor:**
  - comparison by content; **Apply smart selection** keeps one copy per group (VERIFIED-KB duplicate-files);
  - Smart Care looks only in `~/Downloads` (VERIFIED-KB);
  - which copy is kept is **still undocumented**;
  - Gemini 2, the ancestor: keeper modes Automatically / Newest / Oldest / Any; Trash by default with "Review Trashed / Put All Back" (VERIFIED-R relay, 07 §5.1).
- **Where removed files go:**
  - 5.x: undocumented;
  - MacPaw says some removals bypass the Trash (VERIFIED-3P summary of the KB, 13 §3.5);
  - late X's Space Lens confirmation said selected files "will be gone forever" (VERIFIED-SCR-X [DORA 12/4]);
  - X Large & Old showed "Remove Immediately" as the active mode ([DORA 13/2]).
  - INFERRED: 5.x My Clutter removal is **permanent by default for some categories**. We can't tell which. Confidence L.
- **Spruce (unchanged from 07 §1 item 7, INFERRED):**
  - the deterministic keep order:
    1. protected or "never select" folder;
    2. outside `~/Downloads` and `~/Desktop`;
    3. a clean filename (no " copy" or " (1)");
    4. the oldest creation date;
    5. the shortest path;
  - a visible reason per group;
  - **"never every copy"** is enforced twice;
  - **always Trash** with Undo; "Delete Immediately" is an explicit alternative mode.

### 3.5 Similar Images default

- **Vendor:** undocumented. Gemini never auto-selected "similar" (VERIFIED-R, 07 §6.1). The 5.5.4 replica pre-selects redundant near-duplicates (07 §3.2), but nothing ties that to the reference.
- **Spruce:** **nothing selected**. Offer a **Select all but best** button per group and globally (07 §3.4). INFERRED.

---

## 4. Space Lens (5.1+)

### 4.1 Picker and landing

- **X 4.15 landing** (VERIFIED-SCR-X [DORA 12/1]):
  - title and one-line description;
  - two benefit rows with icons ("Instant size overview", "Quick decision-making");
  - a **disk card**: disk icon, "Macintosh HD: 494,38 GB" (capacity), a yellow usage bar, "395,8 GB Used", and an up/down chooser;
  - a round **Scan** button.
- **5.x:**
  - pick a **volume or folder** (VERIFIED-KB space-lens);
  - the replica's capsule shows the selected volume's Finder icon, its name and a chevron;
  - the menu lists mounted local volumes (the boot volume always present), then "Choose folder…" (REPLICA-5 `SpaceLensVolumePicker.swift`).
- **Spruce:** the same information, in our own layout. INFERRED.

### 4.2 Scanning

- **X:** "Building your storage map…", the current path (truncated in the middle), and a round **Stop** button with a progress ring and the running total, e.g. "115,96 GB" (VERIFIED-SCR-X [IJ20]).
- **After the scan,** the sidebar item shows the scanned total, e.g. "Space Lens 370,95 GB" (VERIFIED-SCR-X [DORA 12/2]).

### 4.3 Results: bubbles, colouring, labels

**Verified X layout** (VERIFIED-SCR-X [IJ20], [DORA 12/2, 12/3])

- **Left list (about a third of the content width):**
  - **Start Over** at top-left;
  - ‹ › buttons and a breadcrumb (disk icon "Macintosh HD › Applications" folder icon);
  - **rows:** round checkbox · icon · name · subtitle · size · › for folders. The selected row is highlighted.
  - **Subtitles:**
    - a *built-in description for well-known system folders*, e.g. user account folders, the default Applications folder, shared system libraries, macOS configuration files, essential files that run your Mac;
    - "application" for apps;
    - "‹N› items" for other folders.
- **Right canvas:**
  - one large **circular frame**, packed with bubbles;
  - the **largest child sits big and central** and shows its icon, name and size, e.g. "League of Legends.app 32,27 GB";
  - other bubbles show only the item's icon, or are plain discs when tiny;
  - the selected item's bubble is tinted brighter.
- **Bottom:**
  - "Macintosh HD: 494,38 GB" with a yellow used-bar. A **light trailing segment marks the size of the current selection**;
  - a round **Remove** button, with the selected size beside it ("2,51 GB");
  - a **Review Selected** button.

**5.x-specific (VERIFIED-3P bundle inspection of CleanMyMac 5.5.4)**

- `SpaceLensUI.framework` ships these tile/bubble states: `Default`, `Default_Hover`, `Selected`, `Selected_Hover`, `Smaller Items`, `Smaller Items_Focused` (+ `_Hover`), `Clouds_Default` (+ `_Hover`), `Other-Items-Icon`, `chevron`, and `navigation-button-back|forward`.
- "The colourful tile fills are generated/tinted at runtime per node, so the catalog only ships the state overlays" (https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/HEAD/docs/cleanmymac-3d-assets.md). The inspector calls them "treemap tiles". The 5.1.0 notes say **bubbles** (VERIFIED-DM), and we go with the vendor's word.

**5.5.4 replica behaviour (REPLICA-5, `SpaceLensView.swift`, `SpaceLensBubbleView.swift`, `SpaceLensHoverCard.swift`, `SpaceLensListPanel.swift`)**

- A breadcrumb bar with back / forward / Start Over; the list on the left; packed bubbles on the right; a pinned bottom bar.
- **Hover card:** name, category ("System folder" / "Folder" / "File"), size, descendant count ("155 items"; large counts abbreviated "3M items"), "Modified: ‹date›", and a "Selected:" line when anything is selected. It is placed beside the bubble so it never covers the cursor.
- **On-bubble checkbox** appears on hover. A selected bubble keeps the removal accent (the replica notes "like the reference's pink glow").
- **Protected items** (system roots, the home folder, standard home folders) show an **"i" badge** instead of a checkbox, with a tooltip saying the item is essential or is your home folder.
- **Small bubbles show only the icon.** Name and size labels appear only above a minimum radius.

**Spruce (INFERRED; 07 §8.2–8.3 stands, with these refinements)**

1. **No outer circular frame.** Pack directly on the canvas, so we don't reproduce the vendor's signature look.
2. **Bubble colours** come from our own palette (07 §8.2). States: rest / hover / selected / selected-hover / focused.
3. **Labels:** name + size inside a bubble only when its radius is above 28 pt. Every bubble gets a hover card.
4. **Shipped descriptions for about 25 well-known system and home folders**, written by us and shown as list subtitles. Example: `/private` → "System temporary files and caches (managed by macOS)".
5. The bottom gauge shows **used**, plus a **selected** overlay segment.

### 4.4 "Smaller items" and "Other"

- **Evidence:**
  - the dedicated **"Smaller Items"** bubble has focused and hover states, and there is an **"Other items"** icon (VERIFIED-3P bundle);
  - in the replica, the long tail folds into one "Other items" row. It **expands in the list** instead of drilling in. The bubble is shown but not interactive (REPLICA-5 `SpaceLensChildren.swift`);
  - another replica labels the bubble "%d smaller items" and has a "Show smaller items" command (REPLICA, https://github.com/maclifevn/MClean `en.lproj/Localizable.strings`);
  - MacPaw's CLI rolls small items into "Other (N items)" (07 §8.1).
- **Spruce:**
  - show the top 24 children as bubbles;
  - the rest become one **"‹N› smaller items"** bubble, sized by the sum of their sizes;
  - clicking it **expands those items in the list** and focuses the bubble (focused state); it does not drill into the bubble;
  - nothing inside it can be selected from the map, only from the list.
  INFERRED.

### 4.5 Navigation

- Click a folder bubble or a row's › to zoom in. ‹ › step through history. The breadcrumb jumps to any ancestor. **Start Over** returns to the picker (VERIFIED-SCR-X).
- Double-click opens Quick Look (VERIFIED-DM 4.4.6). Hover links the map and the list (VERIFIED-3P X KB summary, 07 §8.1).
- **Spruce keys:** ←/→ for history, ↑ for parent, Return to zoom in, Space for Quick Look, ⌘R to reveal, ⌫ to toggle selection (07 §8.2). INFERRED.

### 4.6 Selection tray and the Review Selected flow

- **X:**
  1. **Select** in the list or map. The bottom bar updates the Remove size and the gauge segment.
  2. **Review Selected** (or Remove) opens a sheet:
     - title "You are about to remove your files!";
     - a warning that selected files will be **gone forever**, and advice to review them;
     - rows with checkbox, icon, name, **full path** and size;
     - **Cancel** / **Remove**.
  3. **Completion screen:**
     - "Cleanup complete" and "‹size› Cleaned";
     - "You now have ‹X› free on your startup disk", with a prompt to reclaim more by reviewing remaining items;
     - **Review Remaining Items**, **Share Results**, **View Log**.
  VERIFIED-SCR-X [DORA 12/3, 12/4, 12/5].
- **5.x replica:** a "Review files before removal" overlay with two columns. Hero art on the left. On the right, the top-level selected nodes, each with a checkbox, a **location breadcrumb** ("Macintosh HD › Users") and a size. Footer: "983K Items selected", abbreviated like the reference footer, and **Remove** (REPLICA-5 `SpaceLensReviewSheet.swift`).
- **Spruce (INFERRED):**
  - the same three steps;
  - but **Move to Trash** by default (ARCHITECTURE rule 2), with Undo on the completion screen;
  - "Delete Immediately" is a secondary, confirmed option.
  - Deselecting in the review sheet keeps the row visible so it can be re-checked (replica behaviour; good UX).

### 4.7 Cloud-only files in Space Lens

- **X 4.15.4:** Space Lens "automatically ignores cloud-stored files. They don't use your local disk space anyway". VERIFIED-DM (07 §8.1).
- **5.x:**
  - the **`Clouds_Default` / `Clouds_Default_Hover`** bubble state exists (VERIFIED-3P bundle);
  - INFERRED: 5.x draws cloud-only content as **one distinctly styled bubble per folder** instead of hiding it. The "Clouds" name points to a cloud-styled aggregate, not a per-file state;
  - Cloud Cleanup reuses Space Lens to map cloud drives (VERIFIED-DM 5.2.1).
- **Spruce (INFERRED):**
  - Local totals use allocated size and **exclude dataless items** (07 §17.2).
  - When a folder contains dataless items, add one hatched **"In the cloud only · ‹N› items · ‹logical size›"** pseudo-bubble. Its area is capped at 15 % of the canvas so it never dominates. It cannot be selected.
  - Its hover card links to **Cloud Storage** for removal.
  - Scanner threads run with materialization off (`IOPOL_MATERIALIZE_DATALESS_FILES_OFF`, 07 §17.2).

---

## 5. Cloud Cleanup (5.2.1+)

### 5.1 Timeline and verified wording

- **5.2.1 (2025-07-29)** (VERIFIED-DM https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html):
  - connect iCloud Drive, Google Drive and OneDrive;
  - "use familiar tools like Space Lens and Large Files";
  - clean "both cloud-only and locally synced files";
  - delete cloud files directly;
  - "Remove synced files from your Mac and the cloud in one go";
  - "Unsync files … remove them from your Mac while keeping them safe in the cloud".
- **MacPaw's announcement, as relayed by MacSparky (2025-07):**
  - **two cleanup methods: "Remove"** (deletes unneeded files from cloud accounts) **and "Unsync"** (removes local copies, keeps the cloud copies);
  - **a tile-based dashboard with key insights for each connected account**;
  - **smart alerts** when unused files are detected or storage limits are near;
  - works **entirely on-device**, without saving or accessing files in your cloud storage, "connecting through existing desktop apps";
  - Plus plan only, from 2025-07-29.
  - VERIFIED-3P (MacSparky post "MacPaw Adds Cloud Storage Cleanup to CleanMyMac", from https://raw.githubusercontent.com/rlridenour/elfeed-db/HEAD/data/94/947e8310b87e48ce78df40c5f42505c70ed78edf; it links https://macpaw.com/news/macpaw-introduces-cloud-cleanup).
- **Product Hunt launch, 2025-08-04** (an aggregator's Chinese rendering): scans your cloud storage for space hogs; delete them safely or unsync them; runs fully on device; supports iCloud, OneDrive and Google Drive accounts. VERIFIED-3P (https://raw.githubusercontent.com/ViggoZ/producthunt-daily-hot/HEAD/data/producthunt-daily-2025-08-05.md).
- **5.3.0 (2025-12-17):** "connect your Dropbox account to CleanMyMac", plus improved OneDrive integration (VERIFIED-DM).
- **"Cloud Cleanup improvements"** were still listed as coming next on What's New (VERIFIED-KB, 01 §6).

### 5.2 Connect flow per provider

**Hands-on evidence** (VERIFIED-3P, Chris Chinchilla, published 2026-01-24; the Markdown source of the post is at https://raw.githubusercontent.com/ChrisChinchilla/chrischinchilla.com/HEAD/src/content/posts/2026/cleaning-cloud-storage-with-cleanmymac.md):

- He tested **iCloud and two Google Drive accounts**, so a provider can have several accounts.
- He uses **Insync, not Google's desktop client**. CleanMyMac **did not recognise Insync's local files**; it "only sees what the official Google Drive app would sync".
- **Yet the Google Drive scan still worked:** "less than 3 GB used out of 16 GB total", listing audio files, Ableton projects, `.docx` and `.pdf` files.
- **Native Google Docs files did not appear.** He suspects an API limitation.
- Each service has to be checked separately: no cross-service view and no cross-service duplicates.
- At the time of writing he says Dropbox wasn't supported. INFERRED: he tested before 5.3.0 reached him; the App Store got 5.3.x in late January 2026 (01 §6).

**Reading (INFERRED, confidence M)**

A Google Drive scan with **no Drive for desktop installed**, showing **account quota** and **omitting native Docs**, is the signature of the **Google Drive REST API**:
- native Docs have the `application/vnd.google-apps.*` MIME type and **no `size`**, so a size-ranked list drops them;
- quota comes from `about.get` → `storageQuota`.

Together with the help-centre note that Google is connected through a **browser OAuth** sign-in (VERIFIED-KB, 01 §5.2), this settles Google Drive as **OAuth + API for cloud inventory, quota and remote deletion**, with **local state taken from Google's official client mount only**. "On-device" in the marketing means no MacPaw server sits in between, not that no network API is used.

**Per-provider model**

| Provider | Connect | Cloud inventory | "Local copy" detection | Evidence / confidence |
|---|---|---|---|---|
| **iCloud Drive** | None; the Mac's signed-in iCloud Drive | Local CloudDocs tree (`~/Library/Mobile Documents/com~apple~CloudDocs`); evicted files are **dataless** placeholders | `SF_DATALESS` / `ubiquitousItemDownloadingStatus` | No public iCloud Drive API exists; the result groups match a local walk. INFERRED, M |
| **Google Drive** | **Browser OAuth** (Google account), several accounts | Drive API `files.list` | Only Drive for desktop's `~/Library/CloudStorage/GoogleDrive-<acct>` | VERIFIED-KB + VERIFIED-3P; M |
| **OneDrive** | Account connect, "improved" in 5.3.0 | INFERRED: Microsoft Graph | `~/Library/CloudStorage/OneDrive-*` | L |
| **Dropbox** | "connect your Dropbox account" (VERIFIED-DM) | INFERRED: Dropbox API v2 | `~/Library/CloudStorage/Dropbox` | M (connect), L (API) |

**This revises 07 §10.1 / §17.4.** 07's "local-first" reading holds for **iCloud only**. For Google Drive, and probably OneDrive and Dropbox, the vendor uses **account APIs plus local sync folders**: a hybrid. MacSparky's "connecting through existing desktop apps" most likely refers to the local half used for **Unsync**.

### 5.3 What each account shows

- **Dashboard:** tiles of "key insights" per connected account (VERIFIED-3P MacSparky).
- **iCloud result groups,** with his sizes: **"Locally synced files"** (34.4 GB), **"Large locally synced files"** (13.2 GB), **"Large cloud files"** (4 GB). VERIFIED-3P (Chinchilla).
  - INFERRED meaning:
    - *Locally synced* = items with a local copy (Unsync candidates);
    - *Large locally synced* = the large-file subset of those;
    - *Large cloud files* = large items stored only in the cloud (Remove candidates).
- **Item icons** show whether an item is stored locally, in the cloud, or both. The author still found the local-versus-cloud distinction unclear while browsing (VERIFIED-3P).
- **"Essential" marking:** items inside synced system folders such as Documents were flagged "essential" (VERIFIED-3P). INFERRED: Desktop & Documents sync roots, and maybe app containers, are protected or warned about.
- **Not shown:** per-app iCloud data (e.g. WhatsApp backups, visible only in System Settings › iCloud). VERIFIED-3P.
- **Quota:** "used of total" for Google Drive (VERIFIED-3P); "storage limits are near" alerts (VERIFIED-3P MacSparky). For iCloud there is no public quota API, so whether CleanMyMac shows the iCloud quota is unknown (gap).
- **Tools:** Space Lens map and Large Files list per account (VERIFIED-DM).
- **A known flaw:** an Ableton project was mis-typed as an archive (VERIFIED-3P). Kind detection is extension/UTI based; get packages right (§5.5 rule 4).

### 5.4 Action names

| Vendor action | Effect | Evidence |
|---|---|---|
| **Remove** | Deletes the file from the cloud. For a locally synced file it removes the Mac copy too, "in one go". | VERIFIED-3P (MacSparky), VERIFIED-DM, VERIFIED-KB (how-to via 13 §5) |
| **Unsync** | Frees the local copy and keeps the cloud copy. | VERIFIED-3P, VERIFIED-DM, VERIFIED-KB |

INFERRED: there is no separate "Remove from Mac and cloud" button. It is **Remove** applied to a synced item. Unsync is only offered for items with a local copy.

### 5.5 Spruce Cloud Storage (INFERRED, implementation-ready)

**v1: local-first, no accounts**

- **Discovery:**
  - iCloud: `~/Library/Mobile Documents/com~apple~CloudDocs`;
  - File Provider roots: every child of `~/Library/CloudStorage`, named from the folder prefix (GoogleDrive-, OneDrive-, Dropbox, Box-…).
- **One card per root.** Each shows local bytes (allocated), cloud-only items (count and logical size), and the three groups:
  - **Downloaded to this Mac** (Unsync candidates);
  - **Large downloaded files** (≥ 100 MB, with a local copy);
  - **Large cloud-only files** (≥ 100 MB, dataless).
- **Actions:** **Remove local copy** (our name for Unsync) and **Delete from cloud** (our name for Remove; shows "also removes it from this Mac" when a local copy exists). The implementation ladder is in 07 §10.4:
  - eviction: `evictUbiquitousItem` → `brctl evict` (iCloud, as the user) → Finder hand-off;
  - delete: `trashItem` inside the sync root, which the provider propagates.
- **Space Map per root:** a two-tone bubble map. Local is solid; cloud-only is hatched and sized by logical size.
- **Safety:**
  1. Never act on items with pending uploads or conflicts.
  2. Warn on Desktop & Documents roots ("essential", vendor parity).
  3. Never touch app-private iCloud containers.
  4. Treat packages (`.logicx`, `.als` project folders, `.photoslibrary`, `.fcpbundle`) atomically and classify them by UTI, not by extension.
  5. Google shortcut targets (`shortcut-targets-by-id`) are excluded from totals (07 §17.4).

**v2 (optional): account APIs, matching the vendor's hybrid**

The goal: quota, cloud-only content that is not mirrored locally, and remote deletion without the desktop client.
- **OAuth:**
  - `ASWebAuthenticationSession` + PKCE, a public client (no secret), and a custom-scheme or loopback redirect;
  - refresh tokens stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`);
  - support **several accounts per provider** (vendor parity).
- **Google Drive:**
  - `GET drive/v3/about?fields=storageQuota,user` gives quota;
  - `files.list` with `q="trashed=false"` and `fields=files(id,name,mimeType,size,quotaBytesUsed,modifiedTime,viewedByMeTime,md5Checksum,parents)`;
  - skip `application/vnd.google-apps.*` from size lists, but count them in a "Google Docs/Sheets/Slides (no storage)" note;
  - remove with `files.update {trashed:true}`, which is recoverable. Never use `files.delete`.
  - Personal-use caveat (INFERRED from Google's OAuth policy as we understand it; verify): full-Drive scopes are "restricted". An unverified "Testing" project works for your own account, but its refresh tokens expire after about 7 days, so expect periodic re-sign-in.
- **OneDrive:**
  - Microsoft Graph `GET /me/drive` → `quota{total,used,remaining,deleted}`;
  - `GET /me/drive/root/delta` for the inventory;
  - `DELETE /me/drive/items/{id}` (goes to the OneDrive recycle bin);
  - scopes `Files.ReadWrite offline_access`.
- **Dropbox:**
  - `POST /2/users/get_space_usage`;
  - `files/list_folder` (recursive) + `continue`;
  - `files/delete_v2` (recoverable from Dropbox's deleted files);
  - scopes `files.metadata.read files.content.write account_info.read`.
- **iCloud:** no API; local only. Show "Manage storage in System Settings" instead of a quota.
- **Alerts:** notify when an API-connected account passes 90 % of quota (vendor's "storage limits near"). For local-only roots, notify on unused (`viewedByMeTime` or `kMDItemLastUsedDate` > 1 year) large downloaded files.

---

## 6. Spruce wording (our own; do not use the vendor's)

| Vendor label | Spruce label |
|---|---|
| Manage My Applications | **Open App Manager** |
| Unused Applications Found | **Apps you haven't opened in 6 months** |
| App Leftovers | **Files from removed apps** |
| Installation Files | **Old installers** |
| Sparkle / Custom / App Store / macOS Updates | **In-app updates · Vendor updaters · App Store · macOS** |
| Review All Files | **Browse Everything** |
| "You have N files to sort through." | "**N files might be worth a look**" |
| Smaller items | **"N small items"** |
| Review Selected | **Check Selection** |
| Start Over | **New Scan** |
| Remove / Unsync (cloud) | **Delete from Cloud** / **Remove Local Copy** |

---

## 7. What this changes in earlier reports, and what is still open

### 7.1 Changes

- **06 §1 item 2 / §3.4:**
  - *Unused* existed in X (2020 and late 4.15);
  - *Steam* is a **Stores** row when present;
  - *32-Bit* existed in 2020 and was later dropped;
  - in 5.x, *Leftovers* is its own pane, not a filter row.
- **06 §10 gap 1:** answered at **M** (§2.3).
- **06 §10 gap 3:** the paid-major question stays open. The install behaviour is answered in §2.8.
- **06 §10 gap 4:** answered at **L–M** (§2.6).
- **06 §10 gap 6:** default answered at **L** (§2.6); rules still open.
- **06 §10 gap 7:** partly answered (§2.5).
- **06 §4.2.4 ↔ 13 §3.41:** resolved by §2.8, "Decision for Spruce":
  - Sparkle updates through the embedded Sparkle `SPUUpdater`, the Latest pattern;
  - App Store and macOS are hand-offs;
  - no custom bundle swap in v1.
- **07 §15 gaps:**
  - gap 2 (keep rule): still undocumented. We now have evidence that late X removed files **permanently** in Space Lens and Large & Old;
  - gap 3 (Similar Images): still open; default stays "none";
  - gap 5: resolved for the 5.x **bubble states**, the **Smaller Items** aggregate, a **cloud bubble state**, and the **gauge selection segment**;
  - gap 6: substantially revised. The cloud model is **hybrid** (API for Google, likely OneDrive and Dropbox; local for iCloud). Result-group names and quota display are now verified (§5).
- **13 §3.41:** replace "we never replace bundles ourselves" with the §2.8 rule.

### 7.2 Still open (needs a primary source or a device check with a CleanMyMac 5 trial)

1. The exact 5.x Manage window nav order, and whether Installation files is its own nav item.
2. The 5.x per-app detail pane: category names and where Reset lives.
3. Whether 5.x updates App Store apps in-app or opens the App Store.
4. How paid or major upgrades are handled.
5. Whether 5.x Uninstaller, Leftovers and My Clutter removals go to the Trash.
6. The duplicate keeper rule.
7. The Similar Images default.
8. The iCloud quota display and the OneDrive/Dropbox connect mechanism (OAuth vs local).
9. What the 5.x "Clouds" bubble aggregates.

---

## 8. Sources

**MacPaw (primary)**

- DevMate 5.x cumulative notes (5.0.0–5.3.1): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
- DevMate X notes, `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/<version>/releasenotes.html`, for versions:
  - 4.0.1 (Updater "let you apply them");
  - 4.0.2 (Services menu for Updater and Uninstaller);
  - 4.1.0 (leftovers, Steam, batch update);
  - 4.1.2 (side progress indicator);
  - 4.2.0 (macOS updates "let you know");
  - 4.2.1 (> 200 App Store apps bug);
  - 4.3.0 (Space Lens beta; Dock icons as resources; ignore leftover files);
  - 4.4.0, 4.4.3 (Login Items sizes; Purgeable popover);
  - 4.4.6 (Quick Look on double-click; release-notes crash);
  - 4.5.1, 4.5.2 (Uninstaller speed; 32-bit Steam apps);
  - 4.6.10 (Group Containers of the last app; running app shown as leftovers; Users folder size; Move to Folder).
- Help-centre and how-to URLs (via sibling reports, unreachable here): `…/knowledgebase/uninstaller`, `…/smart-care`, `…/duplicate-files`, `…/free-up-more-space`, `…/space-lens`, `…/space-lens-results`, `…/large-and-old`; https://macpaw.com/how-to/icloud-drive-taking-up-space ; https://macpaw.com/cleanmymac/whats-new ; https://macpaw.com/news/macpaw-introduces-cloud-cleanup

**Real vendor screenshots**

- [IJ20] 2020 review: https://raw.githubusercontent.com/iJaack/Jaack/HEAD/_posts/2020-09-25-cleanmymac-x-en.md ; images in `…/assets/images/routines/apps/CleanMyMacX/`:
  - `cleanmymac-x_uninstaller.png`;
  - `cleanmymac-x_updater.png`;
  - `cleanmymac-x_space-lens-1.png`;
  - `cleanmymac-x_space-lens-2.png`.
- [DORA] `kafkaGen/dora-ai`: `https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/<r>/<s>/image.png`, routes:
  - 9/1, 9/2 (Uninstaller list, completion);
  - 10/1 (Updater empty state);
  - 12/1–12/5 (Space Lens landing, results ×2, confirmation, completion);
  - 13/2 (Large & Old list).
  - Screen descriptions: https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/help/neo4j/import/graph_export.json

**Third-party hands-on and announcements**

- Chris Chinchilla, "Cleaning Cloud Storage with CleanMyMac" (2026-01-24): https://chrischinchilla.com/blog/2026/cleaning-cloud-storage-with-cleanmymac/ (source read: https://raw.githubusercontent.com/ChrisChinchilla/chrischinchilla.com/HEAD/src/content/posts/2026/cleaning-cloud-storage-with-cleanmymac.md)
- MacSparky, "MacPaw Adds Cloud Storage Cleanup to CleanMyMac" (2025-07): read via https://raw.githubusercontent.com/rlridenour/elfeed-db/HEAD/data/94/947e8310b87e48ce78df40c5f42505c70ed78edf
- Product Hunt digests (2025-08-04 launch):
  - https://raw.githubusercontent.com/ViggoZ/producthunt-daily-hot/HEAD/data/producthunt-daily-2025-08-05.md
  - https://raw.githubusercontent.com/Navyum/daily/HEAD/docs/_posts/PH-daily-2025-08-04.md
- StorageCleanerMac on-device audit of CleanMyMac 5.5.7 (2026-08-25): https://raw.githubusercontent.com/yangyihang96/StorageCleanerMac-OpenSource/HEAD/docs/COMPETITIVE_AUDIT_1.9.12.md
- Cisco Talos CleanMyMac X helper advisories (2018): https://talosintelligence.com/vulnerability_reports/TALOS-2018-0705 … TALOS-2018-0719 (text from the team's scratch copy of the Talos disclosure)

**Replica and open source**

- VaderCleaner (reference: CleanMyMac 5.5.4 MAS), `https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/HEAD/` plus these paths:
  - `docs/cleanmymac-3d-assets.md`;
  - `VaderCleaner/ApplicationsDashboardSubviews.swift`, `ApplicationsManagerView.swift`, `ApplicationsUninstallerPane.swift`;
  - `VaderCleanerCore/Sources/VaderCleanerCore/ApplicationsManagerModel.swift`;
  - `VaderCleaner/MyClutterDashboardView.swift`, `MyClutterManagerView.swift`;
  - `VaderCleaner/SpaceLensView.swift`, `SpaceLensVolumePicker.swift`, `SpaceLensReviewSheet.swift`, `SpaceLensHoverCard.swift`, `SpaceLensBottomBar.swift`, `SpaceLensListPanel.swift`, `SpaceLensBubbleView.swift`;
  - `VaderCleanerCore/Sources/VaderCleanerCore/SpaceLensChildren.swift`, `SpaceLensProtection.swift`, `SpaceLensBubbleLayout.swift`, `CloudFileAvailability.swift`.
- MClean strings: https://raw.githubusercontent.com/maclifevn/MClean/HEAD/MClean/en.lproj/Localizable.strings
- Latest, `SparkleUpdateOperation.swift`: https://raw.githubusercontent.com/mangerlahn/Latest/HEAD/Latest/Model/Updater/SparkleUpdateOperation.swift
- mas README ("Root Privileges", account requirements): https://raw.githubusercontent.com/mas-cli/mas/HEAD/README.md
