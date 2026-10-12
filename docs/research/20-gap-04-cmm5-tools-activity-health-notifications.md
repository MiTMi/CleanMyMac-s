# 20-gap-04: CleanMyMac 5 features added after launch (5.2.6 → 5.7.1)

**Scope.** My Tools (5.5.0), My Activity (5.4.0), Mac Health / Assistant (as of 5.7), Notification Center (5.6.0), Smart Insights (5.2.6+) and Screen Cleaning Mode.
**Written:** 2026-10-12. **Fills:** 01-overview §5.2 and §14 gaps 4 and 7; 08-menu-app §12 gap 8; 09-design §4.4 ("Poor/Unknown" vs the KB bands); 13-helpcenter §3.2–3.3.
**Target build:** our original app (no MacPaw names, art or copy) for an Apple-silicon Mac mini on macOS 14+, with extras on 15 and 26. Our names follow 01 §13 and 09 Part B: **Toolbox** (= My Tools), **Activity** (= My Activity), **Advisor / Health** (= Assistant / Mac Health), **Notifications** (bell), **Explain** (= Smart Insights), **Screen Cleaning**.

---

## 0. Method, access limits and evidence labels

### 0.1 What this pass could reach

This table bounds every conclusion in the file.

| Attempt (this pass) | Result |
|---|---|
| `WebSearch` | **Refused.** The session-wide budget of 200 searches was already used up when this task began. No web search ran. I did not work around this through search engines, readers or archives. |
| `WebFetch` on `macpaw.com/news/my-tools-cleanmymac`, `www.macpaw.com/support/cleanmymac/knowledgebase/my-tools`, `apps.apple.com/us/app/cleanmymac/id1339170533`, `cleanmymac.com/blog/cleanmymac-vs-cleanmymac-x` | **DNS failure** (`getaddrinfo ENOTFOUND`) for every host. |
| `curl` to `updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml` (the appcast for 5.4+ named in the Homebrew cask) | **Blocked by the egress proxy** (`CONNECT tunnel failed, response 403`). |
| `curl` to DevMate S3 (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/…`) | **Reachable.** The appcast was re-fetched: it ends at **5.3.1** (`50301.0.2601271414`, 28 Jan 2026). The cumulative 5.3.1 release notes were re-fetched and read. Per-build notes for 5.5.4 (`50504.0.2605130801`), 5.6.0 (`50600.0.2608201300`) and 5.7.1 (`50701.0.2609301754`) return **403 AccessDenied**, under both bundle-ID spellings. |
| GitHub (MCP code search plus `raw.githubusercontent.com`) | **Reachable.** About 30 code searches and about 35 raw fetches were made. |

**What this means.** As in earlier passes, **no researcher has read MacPaw's 5.4–5.7 news posts, KB pages or App Store notes directly**. The vendor facts below come from earlier passes, which got them from search-engine extraction. Each carries its vendor URL and the report section that recorded it. This pass adds:
- (a) a **directly re-read** 5.2.6 release note;
- (b) a design article by a MacPaw author;
- (c) a third-party teardown of the shipped 5.5.4 bundle, and a clone health model that claims to mirror the vendor;
- (d) open-source prior art for screen-cleaning locks;
- (e) a full **reconstruction and build spec** for each screen, marked INFERRED.

§10 is a 20-minute on-device kit that closes the remaining gaps with the vendor's 7-day trial.

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED [vendor-direct]** | MacPaw text read **in this pass** from a MacPaw-controlled host (DevMate S3). |
| **VERIFIED [vendor-via-NN §x]** | MacPaw text (news, KB, What's New, App Store) recorded by an earlier pass in report NN, section x. The vendor URL is given. It was not re-read here. |
| **VERIFIED [3P-bundle]** | A third party inspected the **shipped** app bundle and published what they found. |
| **VERIFIED [3P-article]** | A published article (here, by a MacPaw design author) mirrored on GitHub. |
| **VERIFIED [3P-oss]** | Behaviour of open-source code or docs that we read. Used for *how to build*, never for *what the vendor did*. |
| **INFERRED [clone-obs]** | A third-party clone whose code says it mirrors CleanMyMac. Moderate weight. |
| **INFERRED** | Our reasoning or recommendation. |
| **GAP** | Unknown. A way to close it is given in §10. |

---

## 1. Executive summary

| # | Question | What is known (best label) | What is still unknown | What we build (INFERRED) |
|---|---|---|---|---|
| 1 | **My Tools** (5.5.0) | A hub with a **search bar**, a **Favourites** section (star any tool) and an **Other Tools** section. It can also be opened **from the Menu**. Eight tools are named as examples: Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions, Email Cleanup. The 5.0 launch already promised "**25+ tools**". The sidebar label may be just **"Tools"**. [vendor-via-01 §5.2/§6; gap-01 §4.1] | The full list, icons, default favourites, search rules, and any grouping inside Other Tools. | **Toolbox** with 27 tools in 7 groups, Favourites on top, live search over names and keywords, and four default favourites (§3). |
| 2 | **My Activity** (5.4.0) | A dashboard with **local space cleaned**, **cloud space freed**, **malware scans and threats found**, **items scanned**, a **time saved** estimate, **month-over-month changes**, and the **Health Score with recommendations**. [vendor-via-01 §5.2] MacPaw's design lead says the UI deliberately "shows progress" (space cleared, threats removed, time saved) and designs the moment of completion. [3P-article] | Card order, charts, time ranges beyond monthly, and the time-saved formula. | **Activity**: a month selector, six metric cards with month-over-month chips, a 12-month bar chart, a Health card, and a transparent time-saved model (§4). |
| 3 | **Mac Health / Assistant** | KB bands are **Excellent · Good · Fair · Requires Attention · Critical**. Inputs are disk space, threats, battery health, system load, other hardware metrics, FDA granted and recent scan. The **Allow Access** card exists for FDA. [vendor-via-01 §11] The 5.5.4 bundle ships six gauge images: `HealthStatusExcellent / Good / Fair / Poor / Critical / Unknown`. [3P-bundle] In 5.0 the Assistant was a row at the bottom-left of the sidebar. [vendor-via-08 §8.2] | Placement in 5.7, numeric cutoffs, and the full card catalogue. | "Poor" is most likely the internal name of the **Requires Attention** image, and "Unknown" the **not-yet-rated** state (§5.2). We use a worst-factor band, a "Not rated yet" state, and a recommendation card per failing factor (§5). |
| 4 | **Notification Center** (5.6.0) | A **bell icon** opens an in-app list of **product news, offers and messages** that are kept for later. [vendor-via-01 §5.2] | Bell position, badge style, row layout, and read/dismiss actions. | A bell at the top-right of the title strip, an unread dot, a 360 pt popover grouped by Today/Earlier, mark-read and dismiss, and **no offers** (§6). |
| 5 | **Smart Insights** (5.2.6) | Release notes: powered by **Apple Intelligence**, it explains **system files**: what they are, why they matter and whether you need them. [vendor-direct] A button sits next to unfamiliar items in **Cleanup, Protection, Performance and Applications**. It runs **on-device**. It needs **Apple silicon + macOS 26 + Apple Intelligence on**. In the Uninstaller the icon is beside **app names**. [vendor-via-01 §5.2, 13 §3.4] | Exact button glyph and row position, panel layout, and behaviour when the model is unavailable. | A `sparkles` **Explain** button on hover, a 340 pt popover with three answers and a verdict chip, hidden or disabled according to `SystemLanguageModel.Availability`, with a curated offline library as fallback (§7). |
| 6 | **Screen Cleaning Mode** | **Unconfirmed.** The only source is one App Store snapshot that attributes it to two different versions (5.4.0 and 5.7.1). [vendor-via-01 §5.2, downgraded to INFERRED there] The 5.5.4 bundle has a squeegee **`WiperFrame_1…6`** sprite, but its use is unknown. [3P-bundle] | Whether it exists, where it launches, how it locks input, and how to exit. | We ship it anyway as a Toolbox tool and a Monitor action. It uses a full-screen overlay on every display, an active `CGEventTap` (Accessibility), a frozen cursor, **hold Esc for 3 s** to exit, and a 5-minute safety timeout (§8). |

---

## 2. Evidence ledger (new or re-checked in this pass)

| # | Source | Label | What it contributes | URL |
|---|---|---|---|---|
| E1 | DevMate cumulative release notes for CleanMyMac 5.3.1, re-fetched today | VERIFIED [vendor-direct] | The 5.2.6 entry introduces Smart Insights: "powered by Apple Intelligence", it gives info about **system files**, telling you "what these items are, why they matter, and whether you need them". 5.2.7–5.2.10 are fixes only. 5.3.0 adds Dropbox. No Assistant, Tools or Activity entries through 5.3.1. | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html |
| E2 | DevMate appcast, re-fetched today | VERIFIED [vendor-direct] | 46 items, the last being **5.3.1**. Builds after Jan 2026 moved to a new feed (`updates.cleanmymac.com`, per the Homebrew cask), which is unreachable from here. This is why no researcher has the 5.4–5.7 notes. | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml ; cask: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb |
| E3 | Kyrylo Levashov (MacPaw), "Rethinking The Experience Of System Tools", Smashing Magazine, 2026-05-05 (GitHub mirror) | VERIFIED [3P-article] | MacPaw's stated design principles are: translate system jargon into human language; show process and progress; **design the moment of completion**. The new CleanMyMac uses colour, depth, motion and 3D to move the focus from diagnosing problems to **showing progress: space cleared, threats removed, time saved**, and it ends on a picture of a machine that already works better. This is the rationale behind My Activity's metric set. The article cites the peak-end rule. | https://raw.githubusercontent.com/uto-usui/magazine/HEAD/articles/2026-05-07/rethinking-the-experience-of-system-tools.md (original: https://smashingmagazine.com/2026/05/rethinking-experience-system-tools/) |
| E4 | VaderCleaner teardown of **CleanMyMac 5.5.4 (MAS, build 50504.0.2605130801)** | VERIFIED [3P-bundle] | About 128 frameworks, each with its own `Assets.car`. `AssistantUI.framework` holds the six `HealthStatus*` images (Excellent, Good, Fair, Poor, Critical, Unknown), described as dial/gauge states. `TipsServiceUI.framework` holds one Rive animation (`main.riv`) for a **tips surface**. The root catalog has `WiperFrame_1…6` (a squeegee wipe sprite), `Snowflakes1…3` and `EmitterMask`. `SharedResources` has a "health-monitor" asset. Category icons use a domain-shaped silhouette and a two-stop gradient. | https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md |
| E5 | VaderCleaner `MacHealthStatus.swift` and `HealthMonitorViewModel.swift` | INFERRED [clone-obs] | A five-tier verdict ordered Critical < Requires Attention < Fair < Good < Excellent. The code says it "mirrors CleanMyMac": the Mac is **Excellent until a concrete problem is detected**, and the verdict is the **worst tier any factor produces** (no compounding). It has a "critical battery health" factor, caps the verdict at **Good until the first scan**, shows a neutral "Measuring…" state before data exists, and maps ring fill to the band. Each band has a one-line summary that reads like KB copy, so we do not reuse it. | https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleanerCore/Sources/VaderCleanerCore/MacHealthStatus.swift ; …/HealthMonitorViewModel.swift |
| E6 | gaowujian/obsidian-vault "cleanmymac-feature-summary" (2026-06-05), an LLM-style digest citing the My Tools KB | INFERRED (weak) | My Tools "shows all tools, supports search, favourites, **grouping by module**, one entry point". The candidate tool list in it is the author's own. | https://raw.githubusercontent.com/gaowujian/obsidian-vault/HEAD/2026-06-05/cleanmymac-feature-summary.md |
| E7 | A process listing captured 2026-09-20 on a Mac running CleanMyMac 5 | VERIFIED [3P-observed] | Resident processes: `CleanMyMac_5_FinderSyncExtension`, `com.macpaw.CleanMyMac5.Menu` and `com.macpaw.CleanMyMac5.HealthMonitor`. The Health Monitor is the always-on source for health data. | https://raw.githubusercontent.com/OpenAgentsInc/openagents/HEAD/docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-after.txt |
| E8 | Screen-cleaning prior art: fvumbaca/screen-cleaner spec, fexxdev/Wipe, pavinthan/mac-bar `CleaningModeManager`, ScreenCleanModeWiki, a One Switch Raycast script | VERIFIED [3P-oss] | The working patterns: a session `CGEventTap` that swallows key, mouse and scroll events; one black borderless window per `NSScreen`; a hidden cursor; a display-sleep assertion; a hold-to-exit gesture or a chord; a safety timeout. **Accessibility permission** is required to lock the keyboard. | https://raw.githubusercontent.com/fvumbaca/screen-cleaner/HEAD/docs/screen-cleaner-spec.md ; https://raw.githubusercontent.com/fexxdev/Wipe/HEAD/README.md ; https://raw.githubusercontent.com/pavinthan/mac-bar/HEAD/MacBar/Features/CleaningMode/CleaningModeManager.swift ; https://raw.githubusercontent.com/mdrrrrrr/ScreenCleanModeWiki/HEAD/README.md ; https://raw.githubusercontent.com/monsterhxw/dotfiles/HEAD/raycast/shell/one-switch-screen-cleaning-mode.sh |
| E9 | MuhibNayem/clarity-macos production matrix | VERIFIED [3P-oss] (design idea only) | Their "evidence-backed My Activity" keeps **measured available-space increases** separate from **recoverable Trash bytes**. This honesty rule is worth copying (§4.4). | https://raw.githubusercontent.com/MuhibNayem/clarity-macos/HEAD/Documentation/production-requirement-matrix.md |

**Rejected or empty this pass:** GitHub searches for "Screen Cleaning" with CleanMyMac, "time saved" with CleanMyMac, "25+ tools", "Notification Center" + bell, the news-post slugs (`my-tools-cleanmymac`, `my-activity-cleanmymac`, `introducing-smart-insights`), and Chinese and Japanese feature names all returned **no** CleanMyMac-specific hits. The kafkaGen/dora-ai dataset covers only CleanMyMac X. MYLEKHATECH/Ccmacui is an invented design guide (rejected in gap-01).

---

## 3. My Tools (5.5.0): our **Toolbox**

### 3.1 Vendor facts

| Fact | Label / source |
|---|---|
| Shipped in **5.5.0** (2026-04-02) as a "hub" of tools with **favourites, search, quick switching**. | VERIFIED [vendor-via-01 §6] https://macpaw.com/news/my-tools-cleanmymac |
| Layout: a **search bar**, **Favourites** (the user stars any tool) and **Other Tools**. | VERIFIED [vendor-via-01 §5.2, 13 §3.2] https://macpaw.com/support/cleanmymac/knowledgebase/my-tools |
| Can also be opened **from the Menu** (the menu-bar app). | VERIFIED [vendor-via-08 §1, §4.12] https://macpaw.com/news/my-tools-cleanmymac |
| Named example tools: **Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions, Email Cleanup**. | VERIFIED [vendor-via-01 §5.2] (news + https://cleanmymac.com/blog/cleanmymac-vs-cleanmymac-x) |
| Email Cleanup (5.7.0) lives under Tools. A how-to says "go to **Tools** in the sidebar". | VERIFIED [vendor-via-01 §1, gap-01 §4.1] https://macpaw.com/how-to/organize-email-inbox |
| The 5.0 launch already advertised "six modules, assistant, **25+ tools**". | VERIFIED [vendor-via-01 §2/§6] https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/ ; https://macpaw.com/news/introducing-new-cleanmymac |
| No **Extensions** tool among the examples; Shredder was removed in 5.0. | VERIFIED [vendor-via-06, 01 §5.2] (absence among examples is not proof) |
| Grouping "by module" | INFERRED (weak, E6) |

### 3.2 How "25+" was probably counted (INFERRED)

At 5.0 the modules had these sub-features:
- Cleanup: 3 (System Junk, Mail Attachments, Trash Bins);
- Protection: 3 (Malware Removal, Privacy, App Permissions);
- Performance: 3 (Maintenance, Login Items, Background Items);
- Applications: 4 (Uninstaller, Updater, Leftovers, Installation Files);
- My Clutter: 4 (Large & Old Files, Duplicates, Similar Images, Downloads).

That is **17**. Add the **7** maintenance tasks of 5.0 (Free Up RAM, Flush DNS Cache, Reindex Spotlight, Run Maintenance Scripts, Repair Disk Permissions, Speed Up Mail, Thin Time Machine Snapshots) and the total is **24 to 25**, which matches "25+". Space Lens (5.1), Cloud Cleanup (5.2.1), Purgeable Space (5.0.5) and Email Cleanup (5.7) raise it to about 29 by 5.7.1. The vendor examples include **Login Items**, a sub-feature of Performance, so the hub works at **sub-feature granularity**. It is not just a list of modules. (All sub-feature names: VERIFIED [vendor-via-01 §5.2]. The arithmetic and the conclusion: INFERRED.)

### 3.3 The catalogue: vendor features → our Toolbox

Column notes:
- **"In vendor hub?"**: **V** = named in vendor My Tools text; **F** = the feature exists in 5.x (VERIFIED), so its presence in the hub is INFERRED; **X** = our own extra.
- **Vendor icon facts** are VERIFIED [3P-bundle] for the module **category** icons (E4). That the hub reuses them is INFERRED.
- **Our icon** uses SF Symbols from 09 §B.10.1, in our lens style. We never use vendor art.
- **Descriptions** are our own wording.

| # | Our tool (group) | Vendor feature | In vendor hub? | Vendor icon facts (do not copy) | Our icon (SF Symbol, hierarchical, module tint) | Our short description (≤ 60 chars) | Opens (our route) |
|---|---|---|---|---|---|---|---|
| **Cleanup** | | | | | | | |
| 1 | System Junk | System Junk | F | Green **circle**, gradient #5CD746→#155B29, frosted bin with "×" | `bubbles.and.sparkles` | Caches, logs and leftovers macOS can rebuild | `cleanup/systemJunk` (scan → review) |
| 2 | Mail Attachments | Mail Attachments | F | (mail icons exist in `JunkCleanupModule`; shape unknown) | `paperclip` | Local copies of attachments you can re-download | `cleanup/mailAttachments` |
| 3 | Trash Bins | Trash Bins | F | Green circle, open tub | `trash` | Empty every Trash: startup, external drives, Mail | `cleanup/trash` |
| **Protection** | | | | | | | |
| 4 | Malware Scan | Malware Removal | F | Pink "no-malwares" shield art | `exclamationmark.shield` | Find and remove adware, spyware and other threats | `protection/malware` |
| 5 | Privacy | Privacy | F | Pink **octagon**, #FD66ED→#B31C6E, shield with check | `hand.raised` | Clear browser history, cookies and recent items | `protection/privacy` |
| 6 | App Permissions | Application Permissions | **V** | (Protection icon set) | `lock.shield` | See which apps can use camera, mic, files | `protection/permissions` |
| **Performance** | | | | | | | |
| 7 | Maintenance | Maintenance Tasks | F | Orange **banner badge**, #FCA106→#D34A25, wrench + screwdriver | `wrench.adjustable` | Run macOS upkeep tasks in one go | `performance/maintenance` |
| 8 | Login Items | Login Items | **V** | (Performance set) | `power` | Choose which apps open when you log in | `performance/loginItems` |
| 9 | Background Items | Background Items (launch agents) | F | (Performance set) | `gearshape.arrow.triangle.2.circlepath` | Agents and daemons running behind the scenes | `performance/backgroundItems` |
| 10 | Free Up Memory | Free Up RAM (task + Menu action) | F | — | `memorychip` | Release inactive memory (runs `purge`) | runs task inline with a progress toast; detail at `performance/maintenance#ram` |
| 11 | Purgeable Space | Free Up Purgeable Space (5.0.5) | F | — | `internaldrive` | Reclaim space macOS holds for caches | runs inline; detail at `performance/maintenance#purgeable` |
| 12 | Flush DNS Cache | Flush DNS Cache | F | — | `network` | Fix stale name lookups after network changes | runs inline (helper) |
| 13 | Rebuild Spotlight Index | Reindex Spotlight | F | — | `magnifyingglass` | Fix missing or wrong search results | runs inline (helper, confirmation) |
| 14 | Time Machine Snapshots | Thin Time Machine Snapshots | F | — | `clock.badge.checkmark` | Remove local snapshots to free space | `performance/maintenance#snapshots` |
| **Applications** | | | | | | | |
| 15 | Uninstaller | Uninstaller | **V** | Blue **hexagon**, #47B6F9→#055EC4, broom-X + circular × badge | `trash.square` | Remove apps with all their support files | `applications/uninstaller` |
| 16 | App Updates | Updater ("App Updater") | **V** | (Applications set) | `arrow.down.circle` | Update apps from one list | `applications/updater` |
| 17 | Leftovers | Leftovers | F | (Applications set) | `shippingbox` | Files left behind by apps you already deleted | `applications/leftovers` |
| 18 | Installers | Installation Files | F | (Applications set) | `archivebox` | Old .dmg and .pkg installers you no longer need | `applications/installers` |
| 19 | Extensions | — (X only; dropped in 5.x) | X | — | `puzzlepiece.extension` | Safari, Quick Look and other plug-ins | `applications/extensions` (06 §decision) |
| **Clutter** | | | | | | | |
| 20 | Large & Old Files | Large & Old Files | F | — | `doc.richtext` | Big or forgotten files, sorted by size and age | `clutter/largeOld` |
| 21 | Duplicates | Duplicate Finder | **V** | — | `doc.on.doc` | Identical copies, with smart keep-one selection | `clutter/duplicates` |
| 22 | Similar Photos | Similar Images | F | — | `photo.on.rectangle` | Near-identical shots and bursts | `clutter/similar` |
| 23 | Downloads | Downloads | **V** | — | `arrow.down.to.line` | Old installers, archives and documents in Downloads | `clutter/downloads` |
| **Storage & Cloud** | | | | | | | |
| 24 | Space Map | Space Lens | **V** | (treemap/bubble states only) | `circle.hexagongrid.fill` | See what takes space, folder by folder | `spaceMap` |
| 25 | Cloud Storage | Cloud Cleanup (iCloud, Google Drive, OneDrive, Dropbox) | F | — | `icloud` | Tidy cloud drives and local synced copies | `cloud` |
| 26 | Email Cleanup | Email Cleanup (Gmail, 5.7.0) | **V** | — | `envelope.badge` | Unsubscribe and archive bulk mail (Gmail) | `tools/email` |
| **Utilities** | | | | | | | |
| 27 | Screen Cleaning | Screen Cleaning Mode (unconfirmed) | X / F? | `WiperFrame_1…6` sprite exists | `sparkles.tv` (fallback `display`) | Lock keyboard and mouse while you wipe the screen | starts the overlay (§8) |

**Not tools (INFERRED):** Checkup (Smart Care), Activity, Health/Advisor, Settings, the Monitor itself. Vendor parity needs only rows 1–18 and 20–26 (25 tools). Rows 19 and 27 are our extras, or parity if Screen Cleaning turns out to exist.

**Mac-mini notes (INFERRED):**
- Hide "Speed Up Mail" (an obsolete Mail reindex) and "Repair Disk Permissions" (no effect under SIP) from the default catalogue. Keep them as advanced tasks inside Maintenance only. See 05 for the safety rationale.
- "Run Maintenance Scripts" appears only when `/usr/sbin/periodic` exists (it is gone on macOS 26 per Mole; 01 §5.2).

### 3.4 Sections and grouping

- **Vendor:** two sections, **Favourites** and **Other Tools**. VERIFIED [vendor-via-01]. Whether Other Tools is grouped by module is INFERRED (E6, weak).
- **Ours:**
  - **Favourites** first. An editable grid of up to 8 tiles, reorderable by drag.
  - Then **All Tools**, grouped under small caps headers: CLEANUP, PROTECTION, PERFORMANCE, APPLICATIONS, CLUTTER, STORAGE & CLOUD, UTILITIES. Groups are collapsible, and their state persists.
  - A favourited tool also stays in its group, with a filled star. Duplicates are fine, and the user learns where each tool lives.
  - The term **"Favourites"** is generic; use the user's locale spelling ("Favorites" in en-US). INFERRED.

### 3.5 Default favourites

- **Vendor:** not published. GAP. The first four example tools in MacPaw's own text are Uninstaller, Duplicate Finder, Space Lens and Login Items. They are probably the showcase set (INFERRED).
- **Ours:** **Uninstaller, Space Map, Duplicates, Login Items**. These are the four tools a Mac-mini owner opens most often without a full Checkup (INFERRED). Store them as an ordered array. Seed it only on first launch. Never re-add a default the user removed.

### 3.6 Search behaviour

- **Vendor:** a search bar exists. VERIFIED. Its rules are GAP.
- **Ours (INFERRED):**
  - **Focus:** ⌘F, or just start typing while the Toolbox has focus (type-to-search). Esc clears and leaves the field.
  - **Matching:** case- and diacritic-insensitive, using `localizedStandardContains` plus token **prefix** matching on name, group and a keyword list. Examples: Uninstaller → "remove app, delete app, leftovers"; Space Map → "disk usage, storage, treemap"; Free Up Memory → "ram, purge"; Screen Cleaning → "wipe, lock keyboard".
  - **Ranking:** exact name match > name prefix > keyword > description. Favourites win ties.
  - **Results:** the sections collapse into one flat "Results" grid, with matched substrings highlighted in `accentText`. Return opens the first result; arrow keys move between tiles.
  - **No results:** "No tool called '<query>'" plus a link "Search files with Space Map…", which opens Space Map with the query as a name filter.
  - **Speed:** search is local and synchronous; 27 items need no debounce.

### 3.7 How the Menu opens the hub

- **Vendor:** the Menu can open My Tools. VERIFIED [vendor-via-08 §4.12]. The control and transport are GAP. INFERRED: a grid or "Tools" button in the Menu footer that launches or brings forward the main app on the Tools route. The 5.x Menu and main app are separate processes (E7), so it uses a URL or IPC hand-off.
- **Ours:**
  - **Footer row.** The Monitor popover footer holds our **favourites** (first 4, icon-only, with tooltips) and a **"Toolbox"** button (`square.grid.2x2`).
  - **Transport.** Clicking calls `NSWorkspace.shared.open(URL(string: "ourapp://toolbox")!)`, or `ourapp://tool/<id>` for a favourite. The main app handles it in `.onOpenURL` and selects the route. If the main app is not running, Launch Services starts it (declare the `ourapp` scheme in `CFBundleURLTypes`).
  - **Instant tools.** Free Up Memory, Flush DNS and Screen Cleaning run straight from the Monitor through the helper or agent, without opening the main window.
  - **Shared state.** Favourites live in App Group defaults (`group.<team>.ourapp`, key `toolbox.favorites`), so the popover and the app stay in sync. Observe them with KVO on `UserDefaults(suiteName:)`, or listen for a Darwin notification `ourapp.toolbox.changed` posted on every write.

### 3.8 Blueprint (ours)

```
‹ Back?                         Toolbox                                         🔔
 ╭──────────────────────────────────────────────────────────────────────────────╮
 │ 🔍  Search tools                                                     ⌘F     │
 ╰──────────────────────────────────────────────────────────────────────────────╯
 FAVOURITES                                                         Edit · Reset
 ╭─────────────╮ ╭─────────────╮ ╭─────────────╮ ╭─────────────╮
 │ ◉lens   ★   │ │ ◉lens   ★   │ │ ◉lens   ★   │ │ ◉lens   ★   │   tile 168×120, radius 18
 │ Uninstaller │ │ Space Map   │ │ Duplicates  │ │ Login Items │   title 15 semibold
 │ Remove apps…│ │ See what…   │ │ Identical…  │ │ Choose…     │   2-line caption, ink.secondary
 ╰─────────────╯ ╰─────────────╯ ╰─────────────╯ ╰─────────────╯
 ALL TOOLS
 CLEANUP ▾     [System Junk] [Mail Attachments] [Trash Bins]
 PROTECTION ▾  [Malware Scan] [Privacy] [App Permissions ★]
 PERFORMANCE ▾ [Maintenance] [Login Items ★] [Background Items] [Free Up Memory ⚡] …
 …
 UTILITIES ▾   [Screen Cleaning ⚡]
```

- **Tile anatomy:**
  - our 44 pt lens icon in the tool's module tint (09 §B.10.2, reduced to 4 layers);
  - a star toggle at the top-right, visible on hover/focus or when starred, with `accessibilityLabel` "Add to Favourites" / "Remove from Favourites";
  - ⚡ marks tools that run immediately rather than opening a screen;
  - a status chip when a prerequisite is missing: "Needs Full Disk Access", "Needs helper", "Sign in", "macOS 26+", "Needs Accessibility".
- **Context menu:** Open · Add to/Remove from Favourites · Show in Sidebar Module · Copy Link (`ourapp://tool/<id>`).
- **Opening a tool** pushes the module's screen with a "‹ Toolbox" back button in the title strip, so you return to the hub. The sidebar selection does **not** jump to the module, to keep the "hub" mental model. INFERRED; the vendor's "quick switching" wording suggests fast hops between tools.

### 3.9 Data model (ours)

```swift
enum ToolID: String, CaseIterable, Codable, Sendable {
    case systemJunk, mailAttachments, trashBins, malware, privacy, permissions,
         maintenance, loginItems, backgroundItems, freeMemory, purgeable, flushDNS,
         spotlight, tmSnapshots, uninstaller, updater, leftovers, installers, extensions,
         largeOld, duplicates, similarPhotos, downloads, spaceMap, cloud, email, screenCleaning
}

enum ToolGroup: String, CaseIterable { case cleanup, protection, performance, applications, clutter, storage, utilities }

enum ToolAction { case open(Route), runInline(TaskKind), start(ModeKind) }

enum Requirement { case fullDiskAccess, helper, accessibility, macOS(Int), account(Provider) }

struct ToolDescriptor: Identifiable, Hashable {
    let id: ToolID
    let group: ToolGroup
    let title: LocalizedStringResource
    let caption: LocalizedStringResource
    let symbol: String
    let keywords: [String]              // search synonyms, localized
    let action: ToolAction
    let requirements: Set<Requirement>
}

@Observable final class FavoritesStore {
    private let defaults = UserDefaults(suiteName: "group.<team>.ourapp")!
    private let key = "toolbox.favorites"
    static let seed: [ToolID] = [.uninstaller, .spaceMap, .duplicates, .loginItems]
    var ids: [ToolID] {
        get { (defaults.stringArray(forKey: key) ?? []).compactMap(ToolID.init) }
        set { defaults.set(newValue.map(\.rawValue), forKey: key)
              CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                  CFNotificationName("ourapp.toolbox.changed" as CFString), nil, nil, true) }
    }
    func seedIfNeeded() { if defaults.object(forKey: key) == nil { ids = Self.seed } }
}
```

**Edge cases (INFERRED):**
- A tool whose requirement is missing still opens. Its screen shows the requirement banner with a "Grant…" button (09 §B.8 "limited" state). Never hide tools for lack of permission, or users won't find them.
- **Email Cleanup and Cloud Storage** show "Sign in" until an account is connected. Tokens live in the Keychain only.
- **Screen Cleaning** without Accessibility opens a one-screen explainer with "Open Accessibility Settings" (§8.3).
- Unknown IDs in stored favourites (after a downgrade) are skipped silently.

---

## 4. My Activity (5.4.0): our **Activity**

### 4.1 Vendor facts

| Fact | Label / source |
|---|---|
| Shipped in **5.4.0** (2026-02-26 direct / 03-03 App Store). | VERIFIED [vendor-via-01 §6] |
| Dashboard metrics: **local space cleaned**, **cloud space freed**, **malware scans** and **threats found**, **items scanned**, **time saved** (an estimate), and **month-over-month changes**. | VERIFIED [vendor-via-01 §5.2] https://macpaw.com/news/my-activity-cleanmymac |
| It also shows the **Health Score** and **recommendations**. | VERIFIED [vendor-via-01 §5.2, 08 §8.2] https://macpaw.com/support/cleanmymac/knowledgebase/mac-health |
| Precursor: X 4.10.0 (Dec 2021) gave the Assistant "timely Recommendations and **extended statistics** of your experience" with the app. | VERIFIED [vendor-direct, cached X DevMate notes; also 08 §8.1] https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html |
| Design intent: show **progress** (space cleared, threats removed, time saved) and design a clear **ending**, using the peak-end rule. | VERIFIED [3P-article] E3 |
| A **published formula for "time saved"** | **None found.** GAP. Neither the Smashing article nor the earlier vendor extracts give one. |
| Time ranges, chart types, card order | GAP |

### 4.2 Metric catalogue (vendor set + our definitions)

| Card | Vendor? | Our definition (INFERRED) | Event source | Display | Month-over-month rule |
|---|---|---|---|---|---|
| **Space cleaned** (hero) | V | Sum of `totalFileAllocatedSize` of items **our app removed** from their original location: moved to Trash and later emptied, or deleted directly. Items still sitting in the Trash count separately as "in Trash, not yet freed". | `clean` events from every module | "48.2 GB" (`ByteCountFormatter`, `.file`) plus a sub-line "Measured free-space gain: 45.9 GB" | Δ% vs previous month; "New" if the previous month was 0 |
| **Cloud space freed** | V | Bytes **deleted from the cloud** by Cloud Storage. Unsync (local-only) does not count; it goes into Space cleaned instead. | `cloudDelete` | "3.1 GB" | same |
| **Malware scans** | V | Number of completed malware scans: manual, Checkup, and scheduled/background if we add them. | `malwareScan` | "14 scans" | absolute Δ ("+3") |
| **Threats** | V ("threats found") | Found this month · removed this month · currently unresolved (red if > 0). | `threatFound`, `threatRemoved` | "2 found · 2 removed" | absolute Δ |
| **Items scanned** | V | Files and objects examined across all scans: files enumerated, apps inspected, launch items checked. | every `scan` event carries `itemsExamined` | "1.2 M items" (compact notation) | Δ% |
| **Time saved** | V (estimate) | Our transparent model (§4.4). | derived | "≈ 2 h 40 min" plus an ⓘ "How we estimate" popover | Δ% |
| Health | V | The current band plus the top 3 recommendations (§5). | live from the Health engine | gauge + cards | trend arrow vs 30 days ago (best band in each window) |
| Tasks run | ours | Maintenance tasks completed. | `taskRun` | "9 tasks" | absolute Δ |
| Apps updated / removed | ours | Counts from Updater and Uninstaller. | `appUpdated`, `appRemoved` | "6 updated · 2 removed" | absolute Δ |

**Honesty rules (INFERRED, after E9):**
- Never add Trash-moved bytes to "cleaned" until they leave the Trash.
- Show the measured free-space gain from `volumeAvailableCapacityForImportantUsageKey` sampled before and after next to the sum of item sizes. The two differ because of APFS clones, snapshots and purgeable space.
- Never count Unsync or Purgeable as "deleted data". Label them separately.

### 4.3 Time ranges and charts

- **Vendor:** "month-over-month changes" implies a **calendar month** as the base period. VERIFIED wording; the period itself is INFERRED.
- **Ours:**
  - **Header:** a month stepper (‹ October 2026 ›) plus a segmented "Month | All time" control. "All time" hides the delta chips.
  - **Chart:** a Swift Charts `BarMark` of Space cleaned per month for the last 12 months, with the current month highlighted in `accent`. A tap or hover shows a tooltip; clicking selects that month. A secondary overlay toggle shows a `LineMark` for "Items scanned" on a normalised axis, off by default.
  - **Streak line (optional):** "You've run a Checkup 4 weeks in a row." It uses the peak-end idea from E3 without nagging. INFERRED.
  - **History list (bottom):** reverse-chronological sessions (Checkup, Cleanup, Uninstall…) with date, bytes and a "View log" link to the per-run log (05/03 logs).

### 4.4 "Time saved": our model (vendor formula unpublished)

Time saved = Σ over actions in the period of (count × manual-effort seconds), capped at 3 h per day so a big cleanup can't claim a week.

| Action | Manual-effort constant (s) | Rationale (INFERRED) |
|---|---|---|
| Checkup completed | 600 | Equivalent of checking junk, Trash, updates and malware by hand |
| Junk category cleaned | 45 per category + 1 per 200 items | Finding and deleting a cache folder |
| Trash emptied (per volume) | 15 | |
| Malware scan | 300 | Running a separate scanner |
| Threat removed | 600 | Manual removal of an agent and its persistence |
| Maintenance task | 120 | Looking up and running the command |
| App uninstalled (with leftovers) | 180 | Hunting `~/Library` for leftovers |
| App updated | 60 | Opening the app and checking for updates |
| Duplicate group resolved | 20 | |
| Browser privacy cleaned (per browser) | 45 | |
| Login/background item disabled | 60 | |
| Cloud file deleted | 5 per item (cap 600 per session) | |
| Email sender unsubscribed / bulk-archived | 20 per sender | |

- **UI copy:** "Estimated" appears beside the value. The ⓘ popover lists the constants actually applied this month (for example "3 apps uninstalled × 3 min"), so the number is auditable.
- **Settings › Privacy & Activity › "Show time-saved estimate"** (default on). INFERRED.

### 4.5 Storage

- **Event log (INFERRED; 01 §11, 13 §5.7 "local removal log").** Append-only SQLite (or JSON Lines) at `~/Library/Group Containers/group.<team>.ourapp/Activity/activity.sqlite`, in the App Group so the Monitor agent and helper results can be recorded (10 §App Group).

  ```swift
  struct ActivityEvent: Codable, Sendable {
      let id: UUID; let date: Date
      let kind: Kind            // scan, clean, cloudDelete, malwareScan, threatFound, threatRemoved,
                                // taskRun, appUpdated, appRemoved, dupResolved, privacyCleaned, emailAction
      let module: String        // "cleanup", "protection", …
      let bytes: Int64?         // allocated bytes affected
      let measuredBytes: Int64? // free-space delta if measured
      let items: Int?           // items examined or affected
      let runID: UUID?          // links to the per-run log with paths
  }
  ```

- **Paths are not stored in the activity table.** Only `runID` links to the detailed run log, which has its own retention (90 days by default).
- **Monthly aggregates** are cached in `activity_month(yyyymm, kind, sumBytes, sumItems, count)` for instant rendering.
- **Retention:** events are kept for 24 months; aggregates forever. "Reset Activity…" sits in Settings with a confirmation. Export is available as CSV or JSON.
- **No telemetry.** Activity never leaves the Mac (13 §5.7 and 10 §9: "we ship no telemetry").

### 4.6 Blueprint (ours)

```
                                 Activity                                        🔔
  ‹ October 2026 ›     [ Month | All time ]
 ╭────────────────────────────── hero ───────────────────────────────╮ ╭─ HEALTH ─────────╮
 │  48.2 GB cleaned this month        ▲ 18 % vs September             │ │  ◔ Good          │
 │  Measured free-space gain 45.9 GB · 1.4 GB still in Trash          │ │  3 suggestions   │
 │  ▁▂▃▅▂▆▃▄▅▇▆█   (12-month bars, current highlighted)               │ │  • Allow FD Acc… │
 ╰────────────────────────────────────────────────────────────────────╯ │  • Trash 7.4 GB  │
 ╭ Cloud freed ─╮ ╭ Malware scans ─╮ ╭ Threats ───────╮ ╭ Items scanned ╮ │  • 3 app updates │
 │ 3.1 GB  ▲2 % │ │ 14   +3        │ │ 2 found · 2 ✓  │ │ 1.2 M  ▼4 %   │ │  (Open Health)   │
 ╰──────────────╯ ╰────────────────╯ ╰────────────────╯ ╰───────────────╯ ╰──────────────────╯
 ╭ Time saved (estimated) ⓘ ─╮ ╭ Tasks run ─╮ ╭ Apps ───────────────╮
 │ ≈ 2 h 40 min   ▲ 25 %     │ │ 9   +2     │ │ 6 updated · 2 gone  │
 ╰───────────────────────────╯ ╰────────────╯ ╰─────────────────────╯
 HISTORY
 Oct 11  Checkup · 6.2 GB · 0 threats · 3 tasks                       View log
 Oct 08  Uninstaller · Xcode-beta · 18.4 GB                           View log
```

- **Empty state** (no events yet): our Activity lens plus "Your progress will appear here after your first Checkup", with a **Run Checkup** button.
- **First month:** show values without delta chips, with the caption "Comparisons start next month".
- **Accessibility:** each card is one VoiceOver element, for example "Space cleaned, 48.2 gigabytes, up 18 percent from September". The chart supplies an `AXChartDescriptor`.

---

## 5. Mac Health / Assistant (state of 5.7): our **Advisor**

### 5.1 Where it lives

| Version | Placement | Label |
|---|---|---|
| X 4.10–4.15 | An **Assistant** pill in the **upper-right corner** of the window that expands to a full view; recommendations mirrored in the Menu. | VERIFIED [vendor-direct X notes; X screenshots via gap-01 E10] |
| 5.0 (2024) | An **Assistant** row at the **bottom-left of the sidebar**. | VERIFIED [vendor-via-08 §8.2, citing MacStories / 9to5Mac / MacObserver] |
| 5.4+ | The **Health Score + recommendations** also appear inside **My Activity**. | VERIFIED [vendor-via-01 §5.2] |
| 5.0–5.7 | The **Menu** has a **Health** monitor tile. | VERIFIED [vendor-via-01 §5.2] (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu) |
| 5.5.4 bundle | `AssistantUI.framework` still ships with gauge images. | VERIFIED [3P-bundle] E4 |
| 5.7.x | Whether the bottom-of-sidebar Assistant row survived next to My Activity | **GAP** (§10 step 4) |

**Our placement (INFERRED; matches 09 §B.8.1):**
- a **Health pill** in the rail footer (status dot + band word), which opens a **Health** sheet or page;
- the same gauge and cards as the right column of **Activity**;
- a compact ring in the **Monitor** popover header.

All three surfaces read one `HealthEngine` snapshot, so they can never disagree. (VaderCleaner states the same rule, E5.)

### 5.2 Gauge states: reconciling "Poor / Unknown" with the KB bands

| Ordinal | KB label (user-facing) | 5.5.4 asset name | Reconciliation | Our label | Our colour token | Ring fill | Our one-line copy (original) |
|---|---|---|---|---|---|---|---|
| 1 | Excellent | `HealthStatusExcellent` | 1:1 | Excellent | `status.success` | 100 % | "Everything checks out." |
| 2 | Good | `HealthStatusGood` | 1:1 | Good | `status.success` @ 70 % mixed with `status.info` | 80 % | "In good shape. A few small wins available." |
| 3 | Fair | `HealthStatusFair` | 1:1 | Fair | `status.warning` @ 70 % | 58 % | "Worth a look soon." |
| 4 | **Requires Attention** | **`HealthStatusPoor`** | **INFERRED:** the asset is named by severity ("Poor"); the copy uses the softer KB wording. The ordering and count (5 graded states) match exactly. | Needs Attention | `status.warning` | 38 % | "Some issues are affecting your Mac." |
| 5 | Critical | `HealthStatusCritical` | 1:1 | Critical | `status.danger` | 18 % (a sliver, never empty) | "Act now: see the first card." |
| — | (none in KB) | **`HealthStatusUnknown`** | **INFERRED:** a **not-rated** state. It applies before the first scan or first Health Monitor sample, or while the monitor is not running. This fits the KB inputs "FDA granted" and "recent scan" (no basis for a score yet) and the clone's "Measuring…" state (E5). | Not rated yet | `ink.tertiary` | dashed track only | "Run a Checkup to rate your Mac." |

**Copy rule:** our band names must be ours. "Requires Attention" is a generic phrase, but we use **"Needs Attention"** to keep our voice (12 §naming). INFERRED.

### 5.3 Inputs, thresholds and what reviewers saw

- **Vendor inputs.** VERIFIED [vendor-via-01 §11, 02 §5]:
  - free disk space;
  - **threats** (malware);
  - **battery health** (the clone says "critical battery health");
  - **system load** (CPU/RAM);
  - other hardware/system metrics, including **disk health**;
  - whether **Full Disk Access** is granted;
  - whether a **recent scan** exists.
- **Thresholds:** **unpublished.** GAP (01 §14 gap 7 stays open).
- **Reviewer impression:** the score mostly tracks scan recency. VERIFIED [vendor-via-02 §5] (softwarehow review).
- **Aggregation:** the clone says CleanMyMac uses the **worst factor**, with no compounding, and that transient CPU/RAM spikes should not drag the verdict. INFERRED [clone-obs] E5.

### 5.4 Recommendation cards

- **Vendor, VERIFIED:**
  - the **"Allow Access"** card for FDA [vendor-via-01 §9.1, https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access];
  - **maintenance reminders** [vendor-via-01 §5.2];
  - in X, **yellow buttons** marked the most relevant tasks, and the Assistant could be silenced [vendor-via-02 §6];
  - 5.x defaults keys `ShowAssistantRecommendations` and `SmartCareReminderEnabled` exist (Setapp edition dotfiles) [3P, via gap-01 E9: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh];
  - 5.x Settings › Menu › Recommendations covers feature suggestions and weekly cleanup reminders [vendor-via-08 §4.12].
- **Card anatomy (ours, INFERRED):** status-tinted icon · title (≤ 48 chars) · one-line reason with the measured number · **one primary action button** · overflow (⋯) with "Snooze 7 days", "Don't suggest again", "Why am I seeing this?". The action runs in place when possible (Empty Trash, Free Up Memory), otherwise it deep-links (`ourapp://…`).

| Card ID | Factor → band contribution | Title (ours) | One-click action | Snooze default |
|---|---|---|---|---|
| `threat.active` | unresolved threat → **Critical** | "1 threat needs removal" | **Remove** (opens Malware results preselected) | not snoozable |
| `disk.smart` | SMART/NVMe failing → **Critical** | "Your startup disk reports a problem" | **Back Up Now** (opens Time Machine settings) + "Learn more" | 1 d |
| `disk.free` | free space band (table below) | "Only 9 GB free on Macintosh HD" | **Free Up Space** (Cleanup scan) | 1 d |
| `fda.missing` | FDA off → caps at **Fair** | "Allow Full Disk Access for complete scans" | **Allow Access** (opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`) | 3 d |
| `scan.stale` | no Checkup ≥ 14 d → caps at Good; ≥ 30 d → caps at Fair | "It's been 3 weeks since your last Checkup" | **Run Checkup** | 7 d |
| `protection.db` | signature DB older than 14 d → Fair | "Protection data is out of date" | **Update** | 1 d |
| `protection.off` | real-time monitor off → Fair | "Real-time protection is off" | **Turn On** | 7 d |
| `memory.pressure` | sustained critical pressure ≥ 10 min in the last hour → Fair | "Memory has been under pressure" | **See Top Apps** (Monitor › Memory) | 1 d |
| `cpu.runaway` | one process > 90 % CPU for 15 min → Good | "'<app>' has used a lot of CPU" | **Show in Activity Monitor** / **Quit** | 1 d |
| `battery.service` | condition Service/Replace → Needs Attention (laptops only; **N/A on Mac mini**) | "Battery needs service" | **Battery Settings** | 30 d |
| `helper.approval` | helper not approved → caps at Good | "Allow the helper to run maintenance" | **Open Login Items** | 3 d |
| `trash.big`, `updates.n`, `apps.unused`, `downloads.old`, `backup.none` | informational, no band change | (see 08 §8.4.1) | (see 08 §8.4.1) | (08) |

### 5.5 Our scoring algorithm (INFERRED)

We combine the vendor's input list, the clone's worst-factor rule and 01 §11's deduction idea.

1. **Not rated yet** until (a) the first Checkup has completed **and** (b) the Monitor has produced one full sample. Show the dashed ring.
2. Compute a **tier per factor** using the table below. **Band = the worst tier.** This is transparent: the first card always explains the band.
3. Apply **caps** (FDA missing → max Fair; no Checkup for 14 days → max Good, 30 days → max Fair; helper not approved → max Good). Caps only ever lower the band.
4. **Hysteresis:** a band improves only after the triggering factor has been clear for 2 samples (≥ 2 min). It worsens immediately for Critical and after 2 samples otherwise. This stops flicker.
5. A numeric score (0–100) exists only to draw the ring inside a band: band floor + a small offset for non-blocking issues. Never show the number as text. The vendor shows bands, not numbers (VERIFIED wording).

| Factor | Excellent | Good | Fair | Needs Attention | Critical | API |
|---|---|---|---|---|---|---|
| Free space on startup volume (`volumeAvailableCapacityForImportantUsage` ÷ total) | ≥ 20 % and ≥ 40 GB | ≥ 15 % or ≥ 30 GB | ≥ 10 % or ≥ 20 GB | ≥ 5 % or ≥ 10 GB | < 5 % and < 10 GB | `URLResourceValues` (VERIFIED API, 03) |
| Threats | none | — | DB stale / monitor off | — | any unresolved | our engine (04) |
| Disk health | verified | — | — | wear ≥ 90 % (if readable) | SMART failing | IOKit (08 §disk) |
| Memory pressure (sustained) | normal | warn ≥ 10 min/h | critical ≥ 10 min/h | critical ≥ 30 min/h | — | `kern.memorystatus_vm_pressure_level` (08 §5.1) |
| CPU (sustained single process) | — | > 90 % for 15 min | > 90 % for 60 min | — | — | `proc_pid_rusage` (08) |
| Battery (if present) | normal | — | max capacity < 80 % | service recommended | — | IOKit `AppleSmartBattery` (08) |

On a Mac mini the battery row is skipped. Absent factors never count against the band (the clone says the same, E5).

### 5.6 Settings (ours)

- **Show suggestions** (in app, in Monitor), mirroring `ShowAssistantRecommendations`.
- **Checkup reminders** (Off / 3 days / Weekly / 2 weeks / Monthly; default Weekly), mirroring `SmartCareReminderEnabled` (02 §6).
- **Reset dismissed suggestions.**

---

## 6. Notification Center (5.6.0): our **Notifications**

### 6.1 Vendor facts

| Fact | Label |
|---|---|
| Shipped in **5.6.0** (Homebrew 2026-08-21; build `50600.0.2608201300`). | VERIFIED [vendor-via-01 §6] |
| A **bell icon** opens an in-app **Notification Center** holding **product news, offers and messages**, kept so you can read them later. | VERIFIED [vendor-via-01 §5.2] https://macpaw.com/cleanmymac/whats-new |
| The 5.5.4 bundle has a `TipsServiceUI` framework with a Rive animation for a **tips** surface (before 5.6). | VERIFIED [3P-bundle] E4. That tips feed into the Notification Center is INFERRED. |
| Bell position, badge behaviour, message list layout, read/dismiss actions | **GAP**. gap-01 §3.2 places the bell at the top-right of the title strip (INFERRED). |

### 6.2 Our spec (INFERRED)

- **Placement.** The trailing edge of the title strip, right of any search field (09 §B.8.1). The bell is a 28 pt circular button; on macOS 26 it is a Liquid Glass button.
- **Badge.**
  - `bell` when everything is read; `bell.badge` (red dot, `status.danger`) when ≥ 1 unread item has priority ≥ normal.
  - **No numeric count**, to keep it calm. Low-priority tips never light the dot.
  - The dot clears when the popover opens: items are marked "seen", not "read".
- **Popover.** 360 × up to 520 pt, `surface.raised`.
  - **Header:** "Notifications" · `Mark All as Read` · overflow (⋯: Clear All, Notification Settings…).
  - **List:** sectioned **Today / This Week / Earlier**.
  - **Row:** 28 pt type icon in a tinted circle · title (13 semibold, **bold + accent dot** if unread) · body (2 lines, 12 regular, `ink.secondary`) · relative time (11, `ink.tertiary`) · optional **action button** (capsule, e.g. "Open", "Run Checkup", "See What's New").
  - **Interactions:** hover shows a ✕ (dismiss) at the trailing edge. Clicking the row performs its action and marks it read. Context menu: Mark as Read/Unread · Dismiss · Turn Off "<type>".
- **Empty state:** a `bell.slash` glyph and "You're all caught up."
- **Keyboard:** ⌘⇧N toggles the popover; ↑/↓ select; Return activates; ⌫ dismisses.

| Type | Examples (ours) | Priority | Default on | Also posts a macOS notification? |
|---|---|---|---|---|
| `whatsNew` | "Version 1.4: Toolbox search, faster Space Map" (local, bundled release notes) | normal | yes | no |
| `reminder` | "Time for your weekly Checkup" | normal | yes | yes (with a Scan Now action, 02 §6) |
| `alert` | "Startup disk almost full (9 GB)", "Threat removed: <name>" | high | yes | yes |
| `result` | "Background cleanup finished: 2.3 GB" / "3 app updates installed" | normal | yes | optional |
| `tip` | "Did you know? Star tools to pin them to Favourites." | low | yes (max 1 per week) | no |
| `offers` | — | — | **never** (personal build; 01 §4) | — |

**Retention and persistence.**
- Items are kept 60 days; dismissed items are deleted; at most 200.
- Stored in `~/Library/Group Containers/group.<team>.ourapp/Notifications/inbox.json` (atomic writes with `NSFileCoordinator`), so the Monitor agent and the app share one inbox.
- System notifications posted through `UNUserNotificationCenter` are **mirrored** into the inbox with the same ID, so users can find an alert they swiped away. INFERRED; this matches the vendor's "kept for later" idea.
- **Settings › Notifications:** a per-type toggle, the macOS-notification toggle per type, and "Show tips".

```swift
struct InboxItem: Codable, Identifiable, Sendable {
    enum Kind: String, Codable { case whatsNew, reminder, alert, result, tip }
    let id: String; let kind: Kind; let date: Date
    let title: String; let body: String
    let actionTitle: String?; let actionURL: URL?   // ourapp:// deep link
    var seen: Bool; var read: Bool
    let priority: Int                                // 0 low, 1 normal, 2 high
}
```

---

## 7. Smart Insights (5.2.6+): our **Explain**

### 7.1 Vendor facts

| Fact | Label |
|---|---|
| 5.2.6 (direct 2025-10-17; App Store lists it under 5.2.7): "Smart Insights" is **powered by Apple Intelligence**. It gives information about **system files**: what the items are, why they matter, whether you need them. | **VERIFIED [vendor-direct]** E1 |
| A button appears next to **unfamiliar items** in **Cleanup, Protection, Performance and Applications**. | VERIFIED [vendor-via-01 §5.2] https://macpaw.com/news/introducing-smart-insights |
| It runs **on-device** with Apple's Foundation Model. | VERIFIED [vendor-via-01 §5.2, 13 §10] |
| Requirements: **Apple silicon + macOS 26 Tahoe + Apple Intelligence enabled**. | VERIFIED [vendor-via-01 §3.1] (news + https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller) |
| In the Uninstaller, a Smart Insights **icon appears beside app names** on macOS 26 with Apple Intelligence. | VERIFIED [vendor-via-13 §3.4] |
| It is the only AI feature in the app; no chat. (MacPaw's agent product is Eney, which is separate.) | VERIFIED [vendor-via-08 §8.3] |
| Button glyph, row position, panel layout, behaviour when unavailable | **GAP** |

### 7.2 Where the button sits (per module)

| Module | Vendor (label) | Our placement (INFERRED) |
|---|---|---|
| **Cleanup** | "next to unfamiliar items" (VERIFIED, module level) | In the review list (two-pane manager, 09 §B.8.7): a `sparkles` button at the **trailing edge of the row**, left of the size column. It appears on hover/selection, and is **always visible on rows we flag "unfamiliar"**: items not in our curated path library (§7.5), e.g. unknown `~/Library/Caches/<bundle-id>` or `~/Library/Application Support/<vendor>` folders. Also in the detail pane header of a selected item. |
| **Protection** | VERIFIED (module level) | On each **detected threat or PUA row** ("What is this?") and on **App Permissions** entries ("Why does this app have camera access?"). Never on the "Remove" decision itself (§7.6). |
| **Performance** | VERIFIED (module level) | On **Login Items** and **Background Items** rows: the classic "what is `com.foo.helper.plist`?" question. Facts passed: label, program path, signer team, parent app, whether `SMAppService`-managed. |
| **Applications** | VERIFIED: an icon **beside app names** in the Uninstaller | Beside the app name in the Uninstaller list (a small `sparkles` glyph after the name, as the vendor does), and on **Leftovers** and **Installers** rows. |
| My Clutter, Space Lens | not listed by the vendor | Ours: optional on Space Map hover cards for **system-owned** folders only (never on user documents). |

### 7.3 The explanation panel (ours, INFERRED; the vendor layout is GAP)

The vendor's three questions (VERIFIED E1) become the panel's three fields.

```
╭──────────────────────────────── 340 pt popover, arrow to the button ─╮
│ [app/file icon]  com.example.UpdaterAgent.plist                       │
│                  ~/Library/LaunchAgents · 2 KB · signed: Example Inc. │
│ ───────────────────────────────────────────────────────────────────── │
│ WHAT IT IS                                                            │
│ A background helper that checks for updates to Example App.           │
│ WHY IT'S HERE                                                         │
│ Example App installed it so updates arrive without opening the app.   │
│ DO YOU NEED IT?                    [ Safe to remove ]  ← verdict chip │
│ Only if you still use Example App and want automatic updates.         │
│ ───────────────────────────────────────────────────────────────────── │
│ ✦ Generated on this Mac by Apple Intelligence. May be inaccurate.     │
│ [Copy]  [Reveal in Finder]                      [Regenerate]          │
╰───────────────────────────────────────────────────────────────────────╯
```

- **Verdict chip:**
  - `Safe to remove` (`status.success`);
  - `Use caution` (`status.warning`);
  - `Keep` (`status.info`).
  - The verdict is **advice only**. Selection and deletion are decided by our deterministic safety tiers (03 §safety; 08 §8.4.2 guardrails).
- **States:**
  - **loading:** a shimmer on the three fields and "Thinking on device…", cancellable;
  - **result**;
  - **refused/guardrail:** "Apple Intelligence couldn't explain this item.";
  - **error:** "Something went wrong. Try again.";
  - **from library:** the same layout with the footnote "From the built-in library" when the curated library answered without AI.
- **Caching:** answers are cached per (normalised path pattern, bundle ID, OS major version) for 30 days in the App Group cache. "Regenerate" bypasses the cache.
- **Grounding facts** passed to the model: path, kind, size, dates, owning bundle ID (via `NSMetadataItem` or `LSCopyApplicationURLsForBundleIdentifier`), code-signing team (`SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation`), and whether the owner app is installed. Keep the prompt under ~1,000 tokens; the window is 4096 tokens per session (VERIFIED, TN3193 via 08 §8.4.2).

### 7.4 When Apple Intelligence is unavailable

- **Vendor:** the feature is documented as requiring Apple silicon, macOS 26 and Apple Intelligence (VERIFIED). The KB says the icon "appears" on such Macs, which suggests it is **hidden elsewhere** (INFERRED). No published fallback (GAP).
- **Ours, keyed on `SystemLanguageModel.default.availability`** (the cases are VERIFIED in 08 §8.4.2):

| Condition | Button | Extra UI |
|---|---|---|
| macOS < 26 (`#unavailable(macOS 26)`) | Hidden for AI; the **library** answer (§7.5) still shows as an `info.circle` button on known items | none |
| `.unavailable(.deviceNotEligible)` | same as above | none |
| `.unavailable(.appleIntelligenceNotEnabled)` | library-only `info.circle`; the `sparkles` button is hidden | One dismissible tip in Notifications and a row in Settings › Explain: "Turn on Apple Intelligence in System Settings to explain unfamiliar items." with **Open Settings** (deep link to the Apple Intelligence & Siri pane; resolve the pane ID at runtime and fall back to opening System Settings) |
| `.unavailable(.modelNotReady)` | `sparkles` shown **disabled**, tooltip "Apple Intelligence is still getting ready" | Re-check availability on `NSApplication.didBecomeActiveNotification` |
| `.available` | `sparkles` enabled | — |
| Unsupported language (`supportsLocale` false) | treat as not enabled; library only | Settings row explains it |

**Mac mini:** every Apple-silicon Mac mini (M1 or later) meets the hardware requirement. On macOS 26 with Apple Intelligence on, the feature is available. INFERRED from Apple's published eligibility, which is not re-checked here.

### 7.5 The curated library (our offline fallback; INFERRED)

A bundled JSON of about 300 known path patterns and bundle IDs. Each entry has `whatItIs`, `why`, `need`, a `verdict` and a source note. Examples: `~/Library/Caches/com.apple.Safari`, `~/Library/Developer/Xcode/DerivedData`, `com.google.keystone.agent`, `com.microsoft.update.agent`, `/Library/Application Support/Adobe/OOBE`.
- It is answered first, with no model call, on every macOS version.
- AI is used only for misses. This also defines "unfamiliar" (not in the library), which is what decides whether the button is always shown (§7.2).

### 7.6 Code sketch

```swift
import FoundationModels                 // macOS 26+

@available(macOS 26, *)
@Generable struct Insight {
    @Guide(description: "One or two sentences: what this item is and which app or macOS component owns it")
    var whatItIs: String
    @Guide(description: "Why it exists on this Mac")
    var whyHere: String
    @Guide(description: "Whether the user needs it, in one sentence, never advising deletion of personal documents")
    var needIt: String
    @Guide(description: "Exactly one of: safe, caution, keep")
    var verdict: String
}

@available(macOS 26, *)
actor Explainer {
    func explain(_ facts: ItemFacts) async throws -> Insight {
        let session = LanguageModelSession {
            "You explain macOS files, apps and background items to non-experts in plain language."
            "Use only the facts provided. If unsure, say so and choose caution."
        }
        return try await session.respond(to: facts.promptText, generating: Insight.self).content
    }
}
```

The API shape is VERIFIED in 08 §8.4.2. The prompt wording is ours.

---

## 8. Screen Cleaning Mode: our **Screen Cleaning**

### 8.1 Does it exist in 5.7.x?

| Evidence | Reading | Label |
|---|---|---|
| A Mac App Store "Added" note listing "Screen Cleaning Mode", attributed to **5.7.1** in one snapshot and **5.4.0** in another. A MacPaw page had listed it as "coming". | One self-contradicting source | VERIFIED-conflicting → **INFERRED** (01 §5.2) |
| DevMate notes (to 5.3.1) and the Homebrew history | No mention. The DevMate feed ends before 5.4, so the absence proves nothing. | VERIFIED absence (E1, E2) |
| 5.5.4 bundle: `WiperFrame_1…6` (squeegee wipe sprite) next to `Snowflakes1…3` and `EmitterMask` in the root catalog. The app icon itself is a display with a squeegee. | The sprite could be a Screen Cleaning animation, a completion flourish or a seasonal effect. The teardown author guessed "used during cleaning". | VERIFIED [3P-bundle] asset; its use is INFERRED |
| Launch point, locking method, exit gesture | — | **GAP** |

**Conclusion:** status **unconfirmed**. If it exists, the most plausible entry points are a **My Tools tile** and the **Menu**, both "quick tool" surfaces (INFERRED). On macOS, locking keyboard and trackpad from a non-kernel app needs an **active Quartz event tap**, which requires the **Accessibility** permission (VERIFIED [3P-oss] E8). The vendor's App Store build is sandboxed, which makes this harder. Expect the feature, if present, to be **keyboard and trackpad blocking plus a dark overlay**, with an on-screen exit instruction. INFERRED.

### 8.2 Our implementation spec (INFERRED, built from E8 patterns)

**Entry points.**
- **Toolbox › Utilities › Screen Cleaning**.
- **Monitor popover** › ⋯ › "Clean Screen".
- Main menu: **Tools › Start Screen Cleaning** (⌃⌥⌘L).
- A URL route `ourapp://screen-cleaning`.

**Pre-flight.**
1. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])`. If false, show a sheet: "To lock the keyboard and mouse, allow [App] in Privacy & Security › Accessibility." with **Open Settings** (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) and **Cancel**. **Never** start a partial lock without the tap.
2. Show a 3-second countdown card: "Locking keyboard and mouse in 3… Hold Esc for 3 seconds to exit." This lets the user lift their hands.

**Session (all screens).**
- **Overlay windows.** One borderless `NSWindow` per `NSScreen`.
  - `level = .screenSaver`, or `CGShieldingWindowLevel()` to also cover the menu bar and Dock;
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`;
  - opaque black;
  - centre text at 40 % white: "Screen Cleaning" / "Hold Esc for 3 seconds to exit" / an elapsed timer;
  - the instructions fade to 15 % after 5 s (idea from E8, Wipe).
- **Event tap.** `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback:…)`.
  - The mask covers keyDown, keyUp, flagsChanged, all mouse down/up/dragged/moved, scrollWheel, otherMouse, tabletPointer and tabletProximity, **systemDefined (14)** for media/brightness keys, and gesture types (29–32) where delivered.
  - The callback returns `nil` (swallows) for every event, after first feeding key events to the exit detector.
- **Cursor.** `CGAssociateMouseAndMouseCursorPosition(0)` freezes the pointer, so there are no hot corners and no accidental Dock reveal; `NSCursor.hide()`. Restore both on exit.
- **Display sleep.** `IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, …)`; release on every exit path.
- **"Reveal smudges" (optional).** A click is swallowed, so cycle background colours with a **double-tap of Space** (black → white → mid-grey). This is detected in the tap callback like the exit key.
  - Skip the "max brightness" idea from Wipe. A Mac mini drives **external** displays, whose brightness is not settable through public API.

**Exit (always at least two ways).**
1. **Hold Esc for 3 seconds.** Track the `keyDown` timestamp for keycode 53 and ignore auto-repeat (`kCGKeyboardEventAutorepeat`). A `keyUp` before 3 s resets. While holding, show a progress ring on every screen.
2. **Safety timeout:** 5 minutes by default (Settings: 1–15). At T−30 s show "Exiting in 30 s. Press Space to keep cleaning." Space resets the timer (pattern from E8, screen-cleaner).
3. **Process death unlocks.** The tap belongs to our process, so a crash or `kill` frees input. Run the session in the **main app**, never the privileged helper. Also install `SIGTERM`/`SIGINT` handlers that tear down cleanly.
4. **Tap watchdog.** If the callback receives `.tapDisabledByTimeout` or `.tapDisabledByUserInput`, re-enable with `CGEvent.tapEnable(tap:enable:true)`. After 3 failures within 10 s, **exit the mode** and show "Screen Cleaning stopped: input lock was interrupted." Fail open, never locked.

**What cannot be blocked (tell the user in the explainer):**
- the **power button**;
- **Touch ID** on a Magic Keyboard, which can still lock the Mac or sleep it;
- the **Caps Lock** LED may still toggle (hardware-level; test);
- the Secure Input login window;
- **Siri** if invoked by voice.

Multi-finger trackpad gestures (Mission Control, App Exposé) are recognised by the system. Whether a session tap on gesture events fully suppresses them must be tested on a Magic Trackpad. If not, the frozen cursor and full-screen overlay at least keep content hidden. INFERRED; test item in §10.

**Mac-mini specifics:** the keyboard and pointer are Bluetooth or USB peripherals. A simple alternative many users prefer is "turn off the display". Offer a secondary button in the explainer: "Just turn off displays" (`pmset displaysleepnow`, which needs no privileges).

```swift
@MainActor final class ScreenCleaningSession {
    private var tap: CFMachPort?; private var source: CFRunLoopSource?
    private var windows: [NSWindow] = []; private var assertion: IOPMAssertionID = 0
    private var escDownAt: CFAbsoluteTime?; private let holdToExit: CFTimeInterval = 3

    func start() throws {
        guard AXIsProcessTrusted() else { throw CleaningError.needsAccessibility }
        windows = NSScreen.screens.map(Self.makeOverlay(for:))
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        var mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        mask |= (1 << 14)                                   // NX_SYSDEFINED: media & brightness keys
        let me = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: mask, callback: { _, type, event, ctx in
            let s = Unmanaged<ScreenCleaningSession>.fromOpaque(ctx!).takeUnretainedValue()
            return s.handle(type, event)                      // returns nil to swallow
        }, userInfo: me)
        guard let tap else { teardown(); throw CleaningError.tapFailed }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CGAssociateMouseAndMouseCursorPosition(0); NSCursor.hide()
        IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "Screen Cleaning" as CFString, &assertion)
    }
    nonisolated private func handle(_ type: CGEventType, _ e: CGEvent) -> Unmanaged<CGEvent>? {
        // re-enable on .tapDisabledByTimeout; track Esc (keycode 53) down/up, ignoring autorepeat;
        // dispatch to main to update the hold ring; call teardown() when held ≥ 3 s. Swallow all.
        return nil
    }
    func teardown() { /* disable tap, remove source, CGAssociateMouseAndMouseCursorPosition(1),
                         NSCursor.unhide(), IOPMAssertionRelease, close windows */ }
}
```

**Tests:**
- unit-test a pure `CleaningStateMachine` (active → warning → exited; Esc-hold progress; Space resets) with an injected clock (E8 pattern);
- manually test on the Mac mini: Magic Keyboard, Magic Trackpad and mouse; media keys; Mission Control gesture; two displays; tap-timeout recovery (simulate a long main-thread block); `kill -9` unlock.

---

## 9. Cross-cutting: routes, IA and global chrome (ours)

| Surface | Kind | Route / URL | Notes |
|---|---|---|---|
| Toolbox | sidebar row (TOOLS group) | `ourapp://toolbox`, `ourapp://tool/<ToolID>` | The 09 §B.8.2 rail already has Toolbox and Activity under TOOLS |
| Activity | sidebar row (TOOLS group) | `ourapp://activity?month=2026-10` | |
| Health / Advisor | rail-footer pill → sheet; card in Activity; ring in Monitor | `ourapp://health` | one `HealthEngine` snapshot, published over App Group + Darwin notification `ourapp.health.changed` |
| Notifications | title-strip bell → popover | `ourapp://notifications` | inbox shared with the Monitor agent |
| Explain | per-row button in the four modules | (inline) | macOS 26+ AI; library everywhere |
| Screen Cleaning | Toolbox tile, Monitor action, menu command | `ourapp://screen-cleaning` | main-app process only |

- **Accessibility:**
  - every star toggle, bell, gauge and Explain button has an explicit `accessibilityLabel`;
  - the gauge exposes its value as text ("Health: Good");
  - Reduce Motion replaces the ring sweep and the hold-ring animation with a numeric countdown ("Exiting in 2…").
- **Localisation:** keep keywords for Toolbox search per locale in the `.xcstrings` catalogue (a comment-separated list).
- **System Settings deep links** (`x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, `…?Privacy_Accessibility`) are widely used and INFERRED to still resolve on macOS 14–26. Verify them on the Mac mini, and fall back to opening System Settings at the Privacy & Security pane if the anchor is ignored.

---

## 10. Hands-on verification kit (vendor trial on the Mac mini; structure only, never copy strings or art)

**1. Version and frameworks.**

```bash
APP=/Applications/CleanMyMac.app   # Homebrew renames it from CleanMyMac_5.app
defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString
ls "$APP/Contents/Frameworks" | grep -iE 'tool|activity|notif|inbox|insight|assistant|health|tips|wipe|clean' 
```

It answers whether there are dedicated `MyTools*`, `Activity*`, `NotificationCenter*`, `SmartInsights*` or `ScreenCleaning*` frameworks.

**2. Tool catalogue.**

```bash
for f in "$APP"/Contents/Frameworks/*Tool*.framework; do
  find "$f" -name '*.strings' -o -name '*.xcstrings' -o -name '*.loctable' | head; done
plutil -p "<path>/Localizable.loctable" | grep -iE '"[a-z_.]*tool' | head -80     # keys only
```

Count the tool keys to confirm the 25+ list and grouping (§3.3).

**3. Health states.**

```bash
assetutil --info "$APP/Contents/Frameworks/AssistantUI.framework/Resources/Assets.car" | grep -i Name
```

Then look up the localisation key that pairs with "Poor". This confirms or refutes §5.2.

**4. Placement (5.7).** In Accessibility Inspector, list the sidebar `AXRow`s and check whether an Assistant row is still at the bottom. Check the bell's `AXButton` position in the title strip.

**5. Defaults.**

```bash
defaults read com.macpaw.CleanMyMac5 | grep -iE 'favou?rite|tool|activity|notif|insight|clean.*screen|assistant'
```

Also read the group container plist `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Preferences/*.plist`. This reveals the favourites key and the default favourites.

**6. Activity math.** Clean a known 1.00 GB folder, then note the change in My Activity's Space cleaned and Time saved. Repeat with an app uninstall. This fits the per-action constants.

**7. Smart Insights.** On macOS 26 with Apple Intelligence **off**, check whether the button is hidden or disabled. Turn it on and record where the button appears in each of the four modules.

**8. Screen Cleaning.** Search the frameworks with `strings -a "$APP/Contents/MacOS/CleanMyMac_5" | grep -i -E 'screen ?clean|wiper'`. If found, launch it and record the entry point, the exit gesture and whether Accessibility is requested (`tccutil`/System Settings).

Append the results to this file as "§10 results" (facts and structure only).

---

## 11. Remaining gaps after this pass

| # | Gap | Status | Closes with |
|---|---|---|---|
| 1 | Complete vendor My Tools list and its grouping inside Other Tools | Reconstructed (§3.3; 8 tools VERIFIED, about 20 INFERRED) | §10 steps 2, 5 |
| 2 | Default favourites | Unknown; ours chosen | §10 step 5 |
| 3 | My Activity card order, charts, ranges | Unknown beyond the metric list and month-over-month | §10 step 6 + screenshot |
| 4 | "Time saved" formula | **Unpublished**; ours specified (§4.4) | §10 step 6 (fit) |
| 5 | Health thresholds | **Unpublished**; ours specified (§5.5) | not observable without code; keep ours |
| 6 | "Poor"/"Unknown" vs KB bands | Reconciled (INFERRED, §5.2) | §10 step 3 |
| 7 | 5.7 Assistant placement | Open | §10 step 4 |
| 8 | Notification Center layout, badge, actions | Open (ours specified) | screenshot |
| 9 | Smart Insights glyph, position, unavailable behaviour | Open (ours specified) | §10 step 7 |
| 10 | Screen Cleaning Mode existence and behaviour | **Unconfirmed** | §10 step 8 |
| 11 | 5.4–5.7 release notes | Unreachable (new appcast host blocked; DevMate per-build 403) | a session with App Store or `updates.cleanmymac.com` access |

---

## 12. Sources

**Vendor (direct this pass)**
- DevMate appcast: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml
- DevMate cumulative notes 5.0.0–5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
- CleanMyMac X notes 4.10.0 (Assistant "extended statistics"; cached copy of): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html

**Vendor (via earlier reports; not re-read here)**
- My Tools news: https://macpaw.com/news/my-tools-cleanmymac (01 §5.2, 08 §4.12)
- My Tools KB: https://macpaw.com/support/cleanmymac/knowledgebase/my-tools (13 §3.2)
- My Activity news: https://macpaw.com/news/my-activity-cleanmymac (01 §5.2)
- Mac Health KB: https://macpaw.com/support/cleanmymac/knowledgebase/mac-health (01 §11, 02 §5, 13 §3.3)
- Full Disk Access KB: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access (01 §9)
- What's New (5.6.0 Notification Center, 5.7.0 Email Cleanup): https://macpaw.com/cleanmymac/whats-new (01 §6)
- Smart Insights news: https://macpaw.com/news/introducing-smart-insights (01 §5.2)
- Uninstaller KB (Smart Insights icon beside app names): https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller (13 §3.4)
- Email Cleanup how-to ("Tools in the sidebar"): https://macpaw.com/how-to/organize-email-inbox (01 §1)
- Menu KB: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu (01 §5.2)
- App Store listing / version history (Screen Cleaning Mode snapshot): https://apps.apple.com/us/app/cleanmymac/id1339170533?mt=12 (01 §5.2)
- Launch coverage ("25+ tools"): https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/ ; https://macpaw.com/news/introducing-new-cleanmymac (01 §2, §6)
- MacPaw comparison blog: https://cleanmymac.com/blog/cleanmymac-vs-cleanmymac-x (01 §5.2)

**Third party**
- Smashing Magazine (MacPaw author), via GitHub mirror: https://raw.githubusercontent.com/uto-usui/magazine/HEAD/articles/2026-05-07/rethinking-the-experience-of-system-tools.md
- CleanMyMac 5.5.4 bundle teardown: https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md
- VaderCleaner health model: https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleanerCore/Sources/VaderCleanerCore/MacHealthStatus.swift ; https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleanerCore/Sources/VaderCleanerCore/HealthMonitorViewModel.swift
- Feature digest (weak): https://raw.githubusercontent.com/gaowujian/obsidian-vault/HEAD/2026-06-05/cleanmymac-feature-summary.md
- Process listing (2026-09-20): https://raw.githubusercontent.com/OpenAgentsInc/openagents/HEAD/docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-after.txt
- Homebrew cask (5.7.1; new appcast host): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb
- Setapp-edition defaults keys: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh
- Activity honesty pattern: https://raw.githubusercontent.com/MuhibNayem/clarity-macos/HEAD/Documentation/production-requirement-matrix.md
- Screen-cleaning prior art: https://raw.githubusercontent.com/fvumbaca/screen-cleaner/HEAD/docs/screen-cleaner-spec.md ; https://raw.githubusercontent.com/fexxdev/Wipe/HEAD/README.md ; https://raw.githubusercontent.com/pavinthan/mac-bar/HEAD/MacBar/Features/CleaningMode/CleaningModeManager.swift ; https://raw.githubusercontent.com/mdrrrrrr/ScreenCleanModeWiki/HEAD/README.md ; https://raw.githubusercontent.com/monsterhxw/dotfiles/HEAD/raycast/shell/one-switch-screen-cleaning-mode.sh

**Sibling reports used:** 01 §§1–6, 9, 11, 13–14; 02 §§5–6; 03 (safety tiers); 05 (maintenance tasks); 06 (Extensions decision); 08 §§4.12, 5, 8; 09 §§4.4, B.3, B.8, B.10, B.16; 10 (App Group, Team ID); 12 (naming); 13 §§3.2–3.4; 20-gap-01 §§0, 2, 3.2, 4.1.

---

## Verification notes

- **Re-checked this pass:**
  - the DevMate appcast still ends at 5.3.1 (28 Jan 2026);
  - the 5.2.6 Smart Insights note was read directly;
  - the per-build notes for 5.5.4, 5.6.0 and 5.7.1 are not publicly readable (HTTP 403);
  - the 5.4+ appcast host and macpaw.com / apps.apple.com / cleanmymac.com are unreachable from this environment (proxy 403 / DNS);
  - the WebSearch budget was exhausted before this task started, so no searches ran. A follow-up session with search enabled should prioritise the three news posts and the my-tools and mac-health KB pages.
- **Downgrades kept:** Screen Cleaning Mode stays INFERRED/unconfirmed. Grouping by module in My Tools is INFERRED (weak digest only).
- **New VERIFIED items:**
  - the 5.2.6 wording (vendor-direct);
  - MacPaw's design rationale for progress metrics (3P-article);
  - the 5.5.4 `TipsServiceUI` tips surface and the `WiperFrame` sprite (3P-bundle);
  - 5.x resident processes in Sept 2026 (3P-observed).
- **Everything in §§3.3–3.9, 4.2–4.6, 5.2 (reconciliation), 5.4–5.6, 6.2, 7.2–7.6 and 8.2 is our design (INFERRED)**, written to be implementable without vendor assets or copy.
