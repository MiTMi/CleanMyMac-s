# 20-gap-07: CleanMyMac 5.x menu-bar app ("The Menu") tiles and Health Monitor alerts (state as of Oct 2026)

**Scope.** Two parts. Part A is the 5.x menu-bar companion: the status-bar icon, panel size and layout, the tiles and their order, what each tile shows and does, the detail views, network fields, Connected Devices and external drives, how the panel adapts to a Mac mini with no battery, header and footer controls, and recommendation and reminder cards. Part B is the 5.x Health Monitor alert catalogue: trigger and default threshold per alert, macOS notification or custom panel, action buttons, and snooze options.
**Fills:** 08-menu-app §12 gaps 1, 2, 3, 4, 5 and 7, and it refines 08 §4 (popover) and §6 (alerts). It also touches 01-overview §5.2 (The Menu row) and 13-helpcenter §3.30–3.34.
**Written:** 2026-10-12.
**Target:** our own app (not called CleanMyMac) for an Apple-silicon **Mac mini** on macOS 14, 15 and 26. Our names follow 01 §13 and 09 Part B: **Monitor** (= The Menu), **Advisor / Health** (= Assistant / Mac Health), **Checkup** (= Smart Care), **Toolbox** (= My Tools).

---

## 0. Method, access limits and evidence labels

### 0.1 What this pass could reach (it bounds every conclusion below)

| Attempt (this pass) | Result |
|---|---|
| `WebSearch` | **Refused.** The session-wide budget of 200 searches was already spent when this task started, so no web search ran. I did not try to get around this through search engines, readers or archives. |
| `WebFetch` on `macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu`, `tidbits.com/…`, `9to5mac.com/…` | **DNS failure** (`getaddrinfo ENOTFOUND`) on every host. |
| `curl` to macpaw.com, cleanmymac.com, updates.cleanmymac.com, apps.apple.com, setapp.com, youtube.com, reddit.com, macstories.net, macworld.com, tidbits.com, 9to5mac.com, appleinsider.com, theverge.com, web.archive.org, behance.net, dribbble.com, medium.com | **Blocked by the egress proxy** (HTTP 000 / `CONNECT tunnel failed, response 403`). |
| DevMate S3 (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/…`) | **Reachable.** I re-fetched the CleanMyMac X 4.15.8 and 4.15.14 cumulative release notes and the X appcast. Feeds for `com.macpaw.CleanMyMac-setapp`, `com.macpaw.CleanMyMac4.Menu` and `com.macpaw.CleanMyMac4.HealthMonitor` exist but are **empty** (no items). Feeds for `com.macpaw.CleanMyMac5.Menu` and `.HealthMonitor` return 403. |
| GitHub (MCP code search plus `raw.githubusercontent.com`) | **Reachable.** About 30 code searches and about 25 raw fetches: provisioning profiles, dotfiles, logs, mirrored articles, the CleanMyMac 3 Menu bundle, open-source clones. |
| `developer.apple.com` (documentation JSON and HIG JSON) | **Reachable.** 7 pages fetched. |

**What this means.** No researcher in this project has yet read the 5.x Menu KB pages, the 5.x Menu bundle strings, a 5.x review or a YouTube clip of the 5.x Menu *directly*. The 5.x KB facts below were captured by earlier passes (01, 02, 13), which got them from search-engine extraction. Each one names that report and the vendor URL. This pass adds:
- (a) new third-party evidence on the 5.x Menu window and its content;
- (b) the decoded 5.x Menu and Health Monitor provisioning profiles;
- (c) a 5.x Health Monitor log excerpt;
- (d) a mirrored review describing the X Connected Devices monitor;
- (e) re-verified CleanMyMac 3 alert anatomy and X release-note dates;
- (f) Apple HIG and API facts that decide our design;
- (g) a **complete build spec** for every tile, detail view and alert, marked INFERRED;
- (h) a step-by-step on-device kit (§9) that closes the remaining gaps with the vendor's 7-day trial on the Mac mini.

**Sibling written in parallel.** `20-gap-06-cmm5-settings-prefkeys-alerts.md` covers the Settings window, the 5.x preference keys and our Notifications tab in depth. This file defers to it for the tab list, key names and Settings rows, and uses the same alert defaults.

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED** | Read in this pass from a primary source: a MacPaw-hosted release note or appcast, a MacPaw-shipped file (strings, provisioning profile), or Apple documentation. |
| **VERIFIED-K** | A MacPaw KB or review fact recorded by an earlier pass. The sibling report and the vendor URL are named. It was not re-read here. |
| **VERIFIED-M** | A third-party **mirror** (on GitHub) of a published review, read in this pass. |
| **VERIFIED-X** | A third-party file read in this pass that shows vendor **behaviour** or **footprint**: a log, a dotfile, a proxy rule list, a window-manager rule, a process list. |
| **VERIFIED-3P** | A third party's **description** of the vendor UI (for example, of a screenshot). Weak. |
| **INFERRED** | Our reasoning or design decision. It should be validated on a real Mac (§9). |
| **GAP** | Unknown. §9 gives a way to close it. |

**Paraphrase policy.** Only short UI labels are quoted. Nothing here should be copied into our UI. §10 lists the names to avoid.

---

## 1. Executive summary: answers to 08 §12 gaps 1–5 and 7

| 08 gap | Question | Best answer now | Confidence | What we build (INFERRED) |
|---|---|---|---|---|
| **1** | 5.x tile list, order and detail views | The KB lists the monitors in this order: **Health, Protection, Storage, Memory, Battery, CPU, Network, Connected Devices** (VERIFIED-K, 01 §5.2, 13 §3.30). A third party describing a 5.x screenshot saw a **dark gradient hero card reading "Mac Health: Good", glass tiles for Storage / Memory / Battery / CPU, and a recommendation card** (VERIFIED-3P). The tiles form a **grid** (VERIFIED-K, 02 §2 citing MacStories / 9to5Mac). There is **no evidence** of a separate External Drives, My Tools or Smart Care *tile* in 5.x. My Tools can be **opened from the Menu** (VERIFIED-K, 20-gap-04 §3.7). | Medium for the list. Low for exact on-screen order and detail-view contents. | A hero Health header, then a 2-column grid in the KB order with the Battery slot dropped on a Mac mini, then one recommendation card and a footer (§3, §4). |
| **2** | Is there a Notifications settings tab, and what are the 5.x thresholds? | 5.x preference keys **`TrashSizeAlertsEnabled`** and **`SmartCareReminderEnabled`** exist in the group-container plist (VERIFIED-X, user dotfiles). So at least the Trash-size alert and the Checkup reminder have their own on/off switches. The nine-tab replica strip that includes **Notifications** is a CleanMyMac **X** replica. 20-gap-06 §2 rates a 5.x Notifications tab as INFERRED-strong because these alert keys exist and Settings › Menu holds only two controls. **No 5.x threshold value has been published anywhere we can reach.** CMM3 computed the low-disk threshold per volume and offered a Don't Warn / 500 MB … 100 GB list (VERIFIED, 08 §3.1.1). | Medium (toggles exist). Thresholds stay a GAP. | Per-alert toggle plus threshold popup in Settings › Notifications, with defaults in §6.2. |
| **3** | 5.x Network tile fields | **Unverified for 5.x.** X 4.11.2 (9 Aug 2022) added a Network Monitor with **Speed Test** and connection details. 4.11.3 (6 Sep 2022) added **traffic amounts**, and the speed units were later adjusted (VERIFIED). MacPaw runs its own speed-test host, **`speedtest.macpaw.com`** (VERIFIED-X; proxy rule lists file it under "MacPaw" speed tests, and 10-internals §1 ties it to the Menu). | Low for 5.x fields; high that a speed test existed in X. | ↓/↑ throughput, interface and link, Wi-Fi name (with Location consent), IPs, router, DNS, session traffic, top apps, and a speed test through Apple's `networkQuality` rather than a third-party server (§4.7). |
| **4** | Menu-bar text next to the icon | **No evidence in any generation.** CMM3 shipped a template icon and a pressed variant only (VERIFIED, 08 §4.1). 5.x Settings › Menu has only **Enable Menu** and **Recommendations** (VERIFIED-K, 01 §10), and TidBITS called the Menu settings very limited (VERIFIED-K, 01 §10). With no setting to choose a metric, a text readout is very unlikely. | Medium–high: **icon only**. | Icon only by default. Optional readout (free disk / memory pressure / CPU % / network) as a Settings choice (§3.1). |
| **5** | Connected Devices connect/disconnect; external drives eject and clean | **X (4.13.0, 28 Mar 2023):** connect or disconnect peripherals, see battery or storage, and an External Drives section that cleans junk on the spot; not in the App Store edition (VERIFIED). A mirrored ZDNet piece on X adds: iPhone/iPad battery and storage with space tips, Bluetooth battery with low-power alerts, external-drive storage with freeing space, and **eject all devices with one click** (VERIFIED-M). **5.x KB:** cable, Bluetooth or Wi-Fi devices; up to **3** shown; a device **under 20 %** turns **red** and moves to the **top** (VERIFIED-K, 01 §5.2, 13 §3.31). The 5.x app holds a **Bluetooth Always** TCC grant (VERIFIED-K, 10 §4). Whether 5.x kept connect/disconnect, eject and clean is **not documented**. | High for X. Low for 5.x actions. | Devices tile with Bluetooth connect/disconnect, external drives with Eject, Eject All and "Clean junk on this drive" (§4.8, §4.9). |
| **7** | Mac Health thresholds and battery band semantics | **Unpublished.** The KB bands are Excellent / Good / Fair / Requires Attention / Critical (VERIFIED-K). The 5.5.4 bundle ships gauge images named Excellent / Good / Fair / **Poor** / Critical / **Unknown** (VERIFIED-K, 20-gap-04 §5.2). Battery: "≥ 80 % Normal, ≤ 79 % Warning" reads as **health**, and "≤ 10 % Critical" almost certainly as **charge** (INFERRED, 08 §4.9). | Low (numbers). | Keep 20-gap-04 §5.5's worst-factor bands. On a Mac mini the battery factor is skipped. |

**Two corrections to sibling reports found in this pass:**
1. The X 4.10.0 release note **does** say that Assistant recommendations shown in the Menu are managed in Preferences. The fetched DevMate text reads "(manage in Preferences)" (VERIFIED). 01-overview §2 had "corrected" this away. See the addendum appended to 01.
2. X 4.15.14 (Dec 2025) added macOS Tahoe support and says **Tahoe is the last macOS that CleanMyMac X supports** (VERIFIED, DevMate 41514 notes). This does not affect the Menu. It is recorded for 01's timeline.

---

## 2. Evidence ledger (new in this pass)

| # | Evidence | What it shows | Label | Source |
|---|---|---|---|---|
| E1 | Decoded 5.x provisioning profiles for `com.macpaw.CleanMyMac5.Menu` and `.HealthMonitor` (created 2025-02-11, "match Direct … macos") | The only entitlements are application-identifier, keychain group `S8EX82NJP6.*` and team ID. There is **no** time-sensitive-notification, critical-alert, Bluetooth or location entitlement in either profile. | VERIFIED | https://raw.githubusercontent.com/eliekh05/provision-files/HEAD/profiles/CleanMyMac_5_Menu.provisionprofile , …/CleanMyMac_5_HealthMonitor.provisionprofile |
| E2 | A unified-log excerpt (macOS 26.6.2) showing `CleanMyMac_5_HealthMonitor` acting as a `com.apple.cache_delete` client | The Health Monitor queries **CacheDelete**, the purgeable-space service. So its free-space number very likely counts purgeable space as available, like the CMM3 tooltip did. | VERIFIED-X | https://raw.githubusercontent.com/pabloguia/XCodeVault/15bd48e15b8f0894ede4e153f864a7122c88b326/docs/research/evidence/e18-simctl-log-erase-macos26.6.2-25G83-xcode26.5-x86_64-superseded-20260915T202842.txt (lines 116–121) |
| E3 | An AeroSpace tiling-WM rule that floats windows whose app-id is `com.macpaw.CleanMyMac5.Menu` | The 5.x Menu panel is a **real window** (`NSWindow`/`NSPanel`) that window managers see. It is not an `NSMenu`. | VERIFIED-X | https://github.com/JetNoLi/dotfiles/blob/HEAD/aerospace/.config/aerospace/aerospace.toml |
| E4 | `~/Library/HTTPStorages/com.macpaw.CleanMyMac5.Menu.binarycookies` listed by a cleaner rule set | The Menu process does its **own HTTP**: speed test, recommendations or promos. | VERIFIED-X | https://github.com/themoretheless/ppduster/blob/HEAD/rules/apps-personal.yaml |
| E5 | Setapp-edition 5.x defaults written by users: `MenuAppEnabled`, `ShowAssistantRecommendations` (app domain); `SmartCareReminderEnabled`, `TrashSizeAlertsEnabled`, `SoundsEnabled`, `CustomThemes`, `MalwareScanMode` (group-container plist) | There are per-alert booleans and a reminder switch. The Menu has a master switch, and recommendations are switchable. | VERIFIED-X | https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh |
| E6 | A developer's note describing a CleanMyMac screenshot: "dark gradient hero card, 'Mac Health: Good', glass tiles for Storage/Memory/Battery/CPU, a recommendation card" | The 5.x Menu (called a "widget" in the note) has a hero, glass tiles and a recommendation card. | VERIFIED-3P (weak) | https://raw.githubusercontent.com/ProFiveCK/my-Kikau/ef7bbea8fca20e34a088a7266fe9762e35de93a4/docs/IMPLEMENTATION_PLAN.md (line 111) |
| E7 | ZDNet's CleanMyMac X piece, mirrored on GitHub (post dated 2024-11-04) | The X Menu App gave a bird's-eye view of CPU, RAM, storage, battery, network and the real-time malware monitor. The **Connected Devices** monitor had an **"extended" window** covering iPhone/iPad battery and storage with space tips, Bluetooth battery with low-power alerts, external drives with storage and freeing space, and **eject all devices with one click**. | VERIFIED-M | https://raw.githubusercontent.com/techidaily/site-tech-renaissance/8dd4bc00b87802dfea500833bf1920cc7f12e054/source/_posts/top-1-essential-app-you-need-on-your-fresh-macos-grab-the-discounted-offer-now-tips.md |
| E8 | X release notes with dates from the X appcast | 4.10.0 (21 Dec 2021): Assistant recommendations in the Menu, managed in Preferences. 4.11.0 (29 Jun 2022): Menu rebuilt with CPU, Memory, Storage, Battery and Protection. 4.11.2 (9 Aug 2022): Network Monitor with Speed Test. 4.11.3 (6 Sep 2022): traffic amounts. 4.12.4 (8 Feb 2023): battery-drain alert. 4.13.0 (28 Mar 2023): Connected Devices and External Drives. 4.13.6 (12 Jun 2023): drain alerts show time to empty and can enable Display Dimming and Low Power Mode (macOS 12+). 4.14.0 (18 Jul 2023): Bluetooth low-battery alerts and richer update notifications. 4.14.2 (11 Aug 2023): heavy-memory alert with quick release. | VERIFIED | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html ; appcast https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml |
| E9 | CMM3 Menu alert nibs (strings), re-fetched | Custom alert panels. Low-disk: title, message, **Launch CleanMyMac**, **Dismiss**. Trash: **Empty Trash**, **View in CleanMyMac**, plus Emptying/Done tabs. Trashed app: **Uninstall Completely**, **View in CleanMyMac**, plus Progress/Done tabs. Hung apps: **Quit**, **Force Quit All**. RAM: "RAM + Swap", "Almost full", **Learn More…**, **Ignore ▾** (Ignore For Now / Ignore Forever). SMART: Ignore ▾ (Ignore Forever / **Remind in a Week**), **Dismiss**, Learn More…. Battery: "Health: n%", capacity in mAh, Ignore ▾. The gear menu holds About, Preferences, Provide Feedback, **Reset All Warnings** and Quit. | VERIFIED | https://github.com/auspham/mac-essential/tree/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/Resources/en.lproj (`*Alert.strings`, `MainMenu.strings`) |
| E10 | CMM3 Help topic 94 | Most notifications came **through the Menu**. With the Menu off, only the Scheduler's cleanup reminder still appeared. Every notification could be ignored or postponed. | VERIFIED | https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html |
| E11 | Apple HIG, "The menu bar › Menu bar extras" | Use a **symbol** (template; the system recolours it). The bar is **24 pt** tall. **Prefer a menu over a popover** unless the feature is too complex for a menu. **Let people decide** whether the extra appears. **Don't rely on it being visible**, because the system hides extras when space runs out. | VERIFIED | https://developer.apple.com/design/human-interface-guidelines/the-menu-bar (JSON: `developer.apple.com/tutorials/data/design/human-interface-guidelines/the-menu-bar.json`) |
| E12 | Apple docs for `IOBluetoothDevice.openConnection()`, `closeConnection()` and `pairedDevices()` | Both calls are **synchronous** and return `IOReturn`. Since 10.7, `openConnection` reports "connection exists" as an error, so callers must handle that. `pairedDevices()` returns devices paired by **any** user. | VERIFIED | `developer.apple.com/documentation/iobluetooth/iobluetoothdevice/openconnection()` , `…/closeconnection()` , `…/paireddevices()` |
| E13 | `memory_pressure` source (system_cmds) | `memory_pressure -S -l warn` (or `-l critical`) **simulates** a system pressure level without allocating memory. Use it to test the heavy-memory alert. | VERIFIED | https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c (usage, lines 78–95) |
| E14 | Notification Center database location in forensic tools | `~/Library/Group Containers/group.com.apple.usernoted/db2/db` on recent macOS (Sequoia+ per mac_apt and HackTricks; Objective-See's code comment says macOS 26+). Older systems use `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`. It needs FDA. Lets us record the vendor's real notifications in §9. | VERIFIED-X | https://github.com/ydkhatri/mac_apt/blob/HEAD/plugins/notifications.py ; https://github.com/objective-see/AuRevoir/blob/HEAD/auRevoir/AuRevoir/Database.m |
| E15 | Process and executable names | Menu process `CleanMyMac_5_Menu`, Health Monitor `CleanMyMac_5_HealthMonitor`. Logs live in the group container `…/Library/Logs/CleanMyMac_5_Menu` and `…/CleanMyMac_5_HealthMonitor`. | VERIFIED-X | https://github.com/vzaliva/perf-glance/blob/HEAD/rules/builtin.d/11-apps-macos.toml ; https://github.com/andreychev/dotfiles/blob/HEAD/.config/mole/operations.log |
| E16 | Two independent third-party "CleanMyMac-style" monitors | Both use a **hero tile plus a grid of secondary tiles**. One shares the hero health verdict between the menu-bar panel and the main app. | INFERRED [clone-obs] | https://github.com/AThevon/TokenEater (`MonitoringView.swift` header comment); https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/MenuBarContent.swift |

**Not used as evidence:** an AI-written Chinese feature summary (`gaowujian/obsidian-vault`; generic and unsourced) and a "CleanMyMac Menu: Partial live stats" cell in a competitor table (`romatroskin/molebar`; no basis given).

---

# Part A — The Menu (5.x) and our **Monitor**

## 3. Status item, window and overall layout

### 3.1 Status-bar icon (08 gap 4)

**Vendor.**
- CMM3: a monochrome **template** image plus a pressed variant (`MenubarIconTemplate.tiff`). VERIFIED (08 §4.1, [CMM3-MENU]).
- X and 5.x: no source shows text, a number or colour next to the icon. 5.x Settings › Menu has only **Enable Menu** and **Recommendations**, with no choice of readout (VERIFIED-K, 01 §10, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-on-off and …/cleanmymac-menu-recommendations). TidBITS called these settings very limited (VERIFIED-K, https://tidbits.com/watchlist/cleanmymac-5-0/ via 01 §10).
- INFERRED: the 5.x status item is **icon only**, monochrome, with no colour states. Whether it adds a badge when an alert is pending is a GAP (§9 step 2).

**Ours (INFERRED, refines 08 §4.1).**
- `NSStatusItem` with `variableLength`. The image is our own SF-Symbol-style **template** glyph at 18 × 18 pt inside the 24 pt bar (E11).
- **States:**
  - normal: the plain template glyph;
  - **issue pending**: the same glyph with a small **cut-out dot** in its top-right corner, still a template image. It stays monochrome, as the HIG asks, and still inverts correctly when highlighted;
  - optional "Colour the alert dot" setting (off by default): a non-template image is drawn in `labelColor` with only the dot in `systemOrange` / `systemRed`;
  - **busy** (a Checkup or Free Up is running): the glyph's inner stroke animates in a slow 1.2 s loop, or a static "…" badge when Reduce Motion is on.
- **Optional readout** (Settings › Monitor › "Show in menu bar"): Icon only (default) · Free disk ("38 GB") · Memory pressure (dot plus "%") · CPU ("12%") · Network ("↓1.2 ↑0.1 MB/s", two-line 9 pt). Use `button.attributedTitle` with `monospacedDigitSystemFont(ofSize: 11)` so the width doesn't jitter. Update at most every 2 s while visible.
- Left click toggles the panel. Right click or ⌥-click opens an `NSMenu`: Open <App>, Settings…, Pause Alerts ▸ (1 Hour / Until Tomorrow / Until I Turn Them On), Quit Monitor.
- **Hidden item.** The HIG warns that the system hides extras when space runs out (E11), and macOS 26 can also hide third-party items. Detect `button.window?.occlusionState` or a zero-width frame. Offer a global hotkey (default ⌃⌥⌘M) and a "Show monitor icon" fix in the main app (08 §4.1).

### 3.2 Window type and size

**Vendor.**
- The 5.x Menu is a **window** that tiling WMs detect (E3), not an `NSMenu`.
- X opened detail content in an **"extended" side window** next to the main panel (E7, for Connected Devices).
- The size is not documented (GAP; §9 step 1 measures it with Accessibility Inspector).

**Ours (INFERRED; 08 §4.2 and 09 §B.9 agree).**
- A borderless `NSPanel` (`.nonactivatingPanel`, `.fullSizeContentView`, `level = .popUpMenu`, `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`) hosting SwiftUI. It is anchored under the status item, 8 pt below the bar, with its right edge aligned to the item but clamped into `screen.visibleFrame` with a 12 pt margin.
- The HIG prefers a menu (E11). Our content (gauges, lists, actions) is "too complex for a menu", which is the HIG's own exception, so a panel is justified. We still provide the right-click `NSMenu` for quick commands.
- **Width 360 pt.** **Height** fits the content, up to `min(640, visibleFrame.height − 40)`, then the grid scrolls and the header and footer stay pinned.
- Dismiss on outside click (global `NSEvent` monitor), Esc, or the status item again. **Detail views push in place** with a back chevron (⌘[ or Esc goes back). We do not open X-style side windows. Side windows collide with the screen edge for items near the left of a crowded bar, and a single surface is easier for VoiceOver.
- Material: `NSVisualEffectView(.popover)` on 14/15. On macOS 26, `glassEffect()` on cards, with Reduce Transparency fallbacks (09 §B.9).

### 3.3 Overall layout (08 gap 1, structure)

**Vendor (5.x).** Hero health header → grid of glass tiles → a recommendation card (E6, VERIFIED-3P). The tile set and its listed order come from the KB (VERIFIED-K). The footer is GAP.

**Ours (INFERRED).**

```
┌──────────────────────────── 360 pt ────────────────────────────┐
│ Header  [ring 44pt] Mac Health: Good        [⤢ Open] [⚙︎]        │  64 pt
│         "Mac mini · up 6 d 4 h"                                 │
├─────────────────────────────────────────────────────────────────┤
│ Alert strip (only when something is active; max 2 rows, "+N")   │  0–64 pt
├────────────── Grid: 2 columns, 8 pt gutter, 12 pt insets ───────┤
│ [ Protection ]        [ Storage ]                               │  each tile
│ [ Memory     ]        [ Power* ]   *Battery, UPS, or omitted    │  164 × 112 pt
│ [ CPU        ]        [ Network ]                               │
│ [ Connected Devices — full width when it is the odd tile out ]  │
├─────────────────────────────────────────────────────────────────┤
│ Recommendation card (one at a time; dismissible)                │  72 pt
├─────────────────────────────────────────────────────────────────┤
│ Footer  [Checkup] [Free Up RAM] [Empty Trash] [Toolbox ▸]  · 2h │  40 pt
└─────────────────────────────────────────────────────────────────┘
```

**Grid order rule.** Tiles follow the KB order (Protection, Storage, Memory, Battery, CPU, Network, Devices). Unavailable tiles are removed **before** layout. Tiles are paired left-to-right. If the count is odd, the **last** tile spans both columns.
- **Laptop (7 tiles):** Protection | Storage; Memory | Battery; CPU | Network; Devices (full width).
- **Mac mini without UPS (6 tiles):** Protection | Storage; Memory | CPU; Network | Devices. No empty cells, no "No battery" placeholder.
- **Mac mini with a UPS (7 tiles):** the Battery slot becomes **UPS**, and the layout is the same as a laptop.
- INFERRED basis: the vendor's listed order maps naturally onto a 2-column grid, and the 5.x KB shows the Battery monitor only where a battery exists (the KB defines it by design capacity in mAh). How the vendor's Mac mini layout looks is a GAP (§9 step 1).

Settings › Monitor › Tiles lets the user hide and reorder tiles (drag list). The default is the order above.

---

## 4. Tiles: content, primary action and detail view

**Tile anatomy (ours, INFERRED).**
- `overline` label (11 pt, semibold, secondary colour);
- one **big value** (22 pt, monospaced digits) with its unit;
- one **gauge**: a ring (storage, battery), a 60-sample sparkline (CPU, network) or a segmented bar (memory);
- a **status line** (11 pt);
- one **capsule action** at most.

The whole tile is a button that pushes its **detail view**. The capsule action does not navigate; it runs the action. Accessibility label: "<Title>, <value>, <status>". Accessibility action: the capsule's verb.

### 4.1 Health (header, not a tile)

| | |
|---|---|
| Vendor | The 5.x Menu shows **Health**, the same Mac Health status as the main app. Bands: Excellent / Good / Fair / Requires Attention / Critical. Inputs: free space, threats, battery health, system load, other hardware metrics, FDA granted, recent scan. VERIFIED-K (01 §5.2, §11; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu , …/mac-health). Hero card reading "Mac Health: Good" (E6). Asset names also include Poor and Unknown (20-gap-04 §5.2). |
| Shows (ours) | A 44 pt ring in the band colour, the band word ("Mac Health: Good" is the vendor's phrasing, so ours reads e.g. "Health · Good"), and a device line ("Mac mini · up 6 d 4 h"). It shows "Not rated yet" (dashed ring) before the first Checkup (20-gap-04 §5.2). |
| Action | Click: push the **Health detail**. |
| Detail | One row per failing factor (from the 20-gap-04 §5.5 table), each with its fix button: **Free Up Space**, **Remove**, **Allow Access**, **Run Checkup**, **Turn On**. Then "Last Checkup: 3 days ago" and an **Open Advisor** link (`ourapp://advisor`). |
| Data | `HealthEngine` snapshot shared through the App Group; the same object the main app reads, so the two can't disagree. |

### 4.2 Protection

| | |
|---|---|
| Vendor | 5.x: real-time and background scan status, plus database status. VERIFIED-K (01 §5.2, 13 §3.30). 01 records a MacPaw-named status term here ("Sonar"); don't reuse it. X 4.11: how protected the Mac is, which monitors are on, and when the malware database was last updated. VERIFIED (E8). |
| Big value (ours) | A shield state word: **Protected** / **Off** / **Needs Access** / **N threats**. |
| Status line | "Scanned 2 d ago · DB 12 Oct". |
| Gauge | Shield glyph tinted success / warning / danger. |
| Primary action | **Scan** (Quick scan) when protected. **Review** when threats exist (opens Protection results preselected). **Turn On** when real-time is off. **Allow Access** when FDA is missing. |
| Detail | Real-time monitor toggle (writes the setting through XPC to the agent). Background-scan schedule. Last quick scan and last full scan (date, items, result). Threat list (up to 5, then "Show all"). Signature DB version and date with **Update now**. FDA state. |
| Data | Protection engine state in the App Group (04-protection §8). |

### 4.3 Storage (startup volume only)

| | |
|---|---|
| Vendor | 5.x: free space, disk health and temperature, empty Trash; **startup volume only**. VERIFIED-K (01 §5.2; 13 §3.30). The App Store edition has no disk health or temperature. VERIFIED-K (13 §3.33, https://macpaw.com/support/cleanmymac/knowledgebase/disk-no-health-and-temperature). The Health Monitor queries **CacheDelete**, so "available" likely includes purgeable space (E2). In X, the storage **Free Up** started a Smart Scan at once. VERIFIED-K (13 §3.42). |
| Big value (ours) | Available on the startup volume, e.g. "142 GB". Uses `volumeAvailableCapacityForImportantUsage`, which counts purgeable space as available, matching the vendor's CacheDelete-backed figure. |
| Status line | "of 494 GB · Healthy · 38 °C". Temperature uses the locale's unit through `MeasurementFormatter` (13 §3.32). |
| Gauge | Ring of used / total. Amber below our warning threshold, red below critical (§6.2 `disk.low`). |
| Primary action | **Clean Up** opens the main window **and starts** a Checkup (`ourapp://checkup?autostart=1`). This copies X's behaviour as a function, not its label. |
| Detail | Name and format (APFS). Capacity, available and free (both shown; "free" uses `volumeAvailableCapacity`). Purgeable estimate (available minus free; labelled an estimate). **Trash**: size of `~/.Trash` plus per-volume `.Trashes/<uid>`, with **Empty Trash…** and a confirmation sheet. **Disk health** (internal NVMe via the SMART plug-in, 08 §5.4): condition, life left (100 − percentage used), temperature, power-on hours, data written, unsafe shutdowns, media errors. "Not available for this disk" when SMART can't be read. |

### 4.4 Memory

| | |
|---|---|
| Vendor | 5.x: Free Up, pressure, swap, top apps. VERIFIED-K (01 §5.2). X 4.11: available memory, which apps use it, how to free it quickly. VERIFIED (E8). CMM3: free and total, with a legend for Wired / Active / Inactive / Compressed, and "Freeing Up…" while running (08 §4.6). |
| Big value (ours) | Pressure word (**Normal** / **Elevated** / **Critical**), with "62 % used" small. |
| Status line | "Swap 1.2 GB · 16 GB RAM". |
| Gauge | Segmented bar: App, Wired, Compressed, Cached (free is the remaining track). |
| Primary action | **Free Up**. Show before → after "available" as a toast. Mechanism and caveats are in 05-performance §4.1. |
| Detail | Pressure sparkline for the last 10 min. Used / total split. Swap used, swap-ins and swap-outs per minute. **Top 5 apps** by footprint, grouped by responsible app, each with **Quit** (and **Force Quit** after a 3 s wait), and "Show in Activity Monitor". |

### 4.5 Battery / Power (laptops; UPS on a Mac mini; otherwise omitted)

| | |
|---|---|
| Vendor | 5.x: battery **health** = actual / design capacity (mAh), with bands. VERIFIED-K (01 §5.2); band semantics INFERRED (§1 gap 7). X 4.11: cycle count, health, time to full. VERIFIED (E8). X drain alerts with Display Dimming / Low Power Mode (E8). |
| Mac mini (ours) | **Omit the tile** unless `IOPSCopyPowerSourcesList` reports a source whose type is `kIOPSUPSType`. In that case the tile is titled **UPS** and shows level %, "On AC" / "On UPS", and time remaining if reported. Detail: UPS name, `pmset -g ups` halt thresholds (08 §5.6), and a link to Energy settings. |
| Laptop (ours, kept for completeness) | Big value: charge %. Status: "Charging · 1:12 to full" or "3:40 left". Ring of charge. Detail: health % (max / design), cycle count, condition, temperature, adapter watts, top 5 energy users, **Low Power Mode** toggle (helper). |

### 4.6 CPU

| | |
|---|---|
| Vendor | 5.x: load, temperature, top consumers. VERIFIED-K (01 §5.2). The temperature unit follows Language & Region. VERIFIED-K (13 §3.32, https://macpaw.com/support/cleanmymac/knowledgebase/cpu-temperature). X 4.11: top-consuming apps, system uptime, unusual activity spikes. VERIFIED (E8). |
| Big value (ours) | Total CPU % (user + system). |
| Status line | "52 °C · load 2.1". Always show the number, and add a plain word for it (Cool < 50 °C, Warm < 80 °C, Hot ≥ 80 °C or `thermalState ≥ .serious`) so a reading never looks alarming without context. The cut-offs are ours. |
| Gauge | 60-sample sparkline. A point turns red when > 80 % for ≥ 10 s ("spike"). |
| Primary action | None. Clicking opens the detail. |
| Detail | Per-core bars split into P and E clusters (`hw.nperflevels`). Load average 1/5/15. Uptime. Thermal state (`ProcessInfo.thermalState`). **Top 5 processes** by CPU, with **Quit** / **Force Quit**. "Recent spikes" (last 3, with process and time). |

### 4.7 Network (08 gap 3)

| | |
|---|---|
| Vendor | X 4.11.2: Network Monitor with **Speed Test** and connection info. 4.11.3: amount of traffic. Speed units later adjusted. VERIFIED (E8). Speed-test host `speedtest.macpaw.com` (VERIFIED-X; e.g. https://github.com/SukkaW/Surge/blob/HEAD/Source/domainset/speedtest.conf lists it under "MacPaw"). The 5.x fields are **GAP** (§9 step 1). |
| Big value (ours) | ↓ and ↑ live throughput (auto units; bytes or bits per Settings). |
| Status line | "Ethernet · 1 Gb/s" or "Wi-Fi · −52 dBm · 5 GHz". Show the network name only once Location is authorised (below). |
| Gauge | Dual sparkline (↓ filled, ↑ line). |
| Primary action | **Speed Test** (runs inside the detail view, which opens automatically). |
| Detail fields (ours) | **Connection:** active interface (service name and BSD name, e.g. "Ethernet (en0)"), link speed (Ethernet media subtype; Wi-Fi `transmitRate`), Wi-Fi network name, BSSID, RSSI, noise, channel and band (CoreWLAN; name and BSSID need Location consent, 08 §5.5). **Addresses:** local IPv4/IPv6, router, DNS servers, public IP (**off by default**; "Show public IP" contacts an endpoint the user chooses). **Traffic:** since boot (64-bit interface counters, 08 §5.5) and "since reset" with a Reset button. **Top 5 apps** by traffic (sampled only while this view is open). **Speed Test:** download, upload, responsiveness (RPM) and idle latency via `/usr/bin/networkQuality -c` (macOS 14 flags differ, 08 §5.5), with a progress ring, a Cancel button and a 30 s timeout; results kept for the last 5 runs. |
| Why not the vendor's approach | Their own speed server is a third-party dependency. Apple's tool needs no account or endpoint, works offline-safe, and is already on every macOS 12+ system. |

### 4.8 Connected Devices (08 gap 5)

| | |
|---|---|
| Vendor (5.x) | Cable, Bluetooth or Wi-Fi devices; **up to 3** shown; a device **below 20 %** turns **red** and moves to the **top**. VERIFIED-K (01 §5.2; 13 §3.31; https://macpaw.com/support/cleanmymac/knowledgebase/devices-monitoring). The app holds Bluetooth Always access (VERIFIED-K, 10 §4). Connect/disconnect is **not mentioned** in the 5.x KB summary (08 §12 gap 5). |
| Vendor (X) | Headphones, speakers, mice, keyboards, trackpads; battery or storage; **connect or disconnect**; not in the App Store edition (VERIFIED, E8). iPhone/iPad battery and storage with space tips, Bluetooth low-battery alerts, external drives with storage and freeing space, **eject all** in one click, in an extended window (VERIFIED-M, E7). |
| Big value (ours) | The most urgent device: e.g. "Magic Keyboard 18 %" in red, or "3 devices" when all are fine. |
| Rows on the tile | Full width: up to 3 rows (glyph · name · battery % · connection type). Half width (Mac mini layout): 2 rows, then "+N". AirPods show L / R / Case. |
| Sort | Battery < 20 % first (red), then connected Bluetooth by name, then wired, then drives. |
| Primary action | None on the tile. The **Eject All** capsule appears only when ≥ 1 ejectable volume is mounted. |
| Detail | Sections: **Bluetooth** (all paired devices: connected state, battery, and **Connect / Disconnect** buttons), **Wired** (USB/Thunderbolt peripherals from IOKit, name only), **Drives** (§4.9), and **iPhone / iPad** (name only, see the non-goal below). Footer: "Open Bluetooth Settings" (`x-apple.systempreferences:com.apple.BluetoothSettings`; INFERRED URL, check on 14, 15 and 26). |
| Connect / Disconnect (ours) | `IOBluetoothDevice.openConnection()` / `closeConnection()`. Both are synchronous (E12), so call them on a background queue with a spinner and a 10 s timeout. Treat "connection exists" on open as success. Re-read `isConnected()` afterwards. Requires `NSBluetoothAlwaysUsageDescription` in Info.plist, and the first use triggers the Bluetooth TCC prompt (INFERRED from the vendor's grant, 10 §4). |
| Non-goal | iPhone/iPad battery and storage need the private MobileDevice framework. We list the device only. |

### 4.9 External drives (inside Devices)

| | |
|---|---|
| Vendor | X 4.13.0: a separate **External Drives** Menu section that manages connected storage and cleans junk on the spot (VERIFIED, E8). 5.x: Storage is **startup volume only** (VERIFIED-K). No 5.x source names an External Drives tile. The X Connected Devices view already included drives (E7). INFERRED: 5.x shows drives as "cable" devices inside Connected Devices, if at all. GAP (§9 step 1). |
| Ours | Drives appear in the Devices tile and in the Devices detail's **Drives** section. One row per mounted external volume: name, format, free / total ring, **⏏ Eject**; overflow: **Clean junk on this drive…**, **Reveal in Finder**. **Eject All** sits on the section header. |
| Eject | `NSWorkspace.shared.unmountAndEjectDevice(at:)` off the main thread. On failure, show "In use by <app>" using the DiskArbitration dissenter (08 §5.4) and offer **Force Eject…** with a data-loss warning. |
| Clean junk on drive | Only these, each shown with its size before anything is removed: the volume's `.Trashes/<uid>` (FDA), `._*` AppleDouble files **only** on non-HFS/APFS volumes (FAT/exFAT), `.DS_Store` (off by default), and `.Spotlight-V100` / `.fseventsd` **never**. Reuses the 03-cleanup safety engine. |
| Optional alert | `drive.cluttered` (§6.2): the X Notifications tab covered cluttered drives, including external ones (VERIFIED-K, 13 §3.42). |

### 4.10 Mac mini adaptation summary (ours, INFERRED)

| Area | Behaviour |
|---|---|
| Battery tile | Omitted. It becomes **UPS** only when a UPS reports through IOPowerSources. |
| Health factors | The battery factor is skipped. An absent factor never lowers the band (20-gap-04 §5.5). |
| Network | Prefer the **primary service** (`SCDynamicStore` `State:/Network/Global/IPv4` → `PrimaryInterface`), usually Ethernet on a mini. Don't ask for Location unless the user opens Wi-Fi details while on Wi-Fi. |
| Devices | Most useful on a mini: Magic Keyboard, Trackpad and Mouse batteries and external drives. Tile placed in the grid's last cell (half width). |
| Temperatures | The internal SSD and CPU sensors are readable on Apple silicon (08 §5.8). Show the number with the Cool / Warm / Hot word from §4.6. A mini is usually "Cool" at idle. |
| Low Power Mode | Desktop Macs on macOS 14+ can use Low Power Mode, but there is no battery drain alert. Show the toggle in the UPS detail only. |

### 4.11 Header and footer controls

**Vendor.**
- CMM3 gear menu: About · Preferences · Provide Feedback · **Reset All Warnings** · Quit (VERIFIED, E9).
- 5.x: header and footer controls are GAP. The KB says the Menu is switched on and off in Settings › Menu (VERIFIED-K, 01 §10), and that My Tools can be opened from the Menu (VERIFIED-K).

**Ours (INFERRED).**
- **Header:** **Open** button (⤢, opens the main window on the last route), **⚙︎** menu: Settings…, Pause Alerts ▸, Reset Ignored Alerts, About, Quit Monitor. "Quit Monitor" explains in a one-time sheet that alerts stop until the next login or until <App> is opened.
- **Footer:** four quick actions, user-configurable (Settings › Monitor › Quick actions): **Checkup**, **Free Up RAM**, **Empty Trash** (shows the size, e.g. "Empty Trash · 7.4 GB"), **Toolbox ▸** (opens `ourapp://toolbox`). Right-aligned: "Checked 2 h ago".

### 4.12 Recommendation and reminder cards

**Vendor.**
- X 4.10.0: Assistant recommendations shown in the Menu, managed in Preferences (VERIFIED, E8).
- 5.x Settings › Menu › **Recommendations**: feature suggestions plus weekly cleanup reminders (VERIFIED-K, 01 §10, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-recommendations).
- A recommendation card in the 5.x panel (E6).
- Keys `ShowAssistantRecommendations` and `SmartCareReminderEnabled` (E5).

**Ours (INFERRED).**
- One card at a time, under the grid. It is chosen by priority from the 20-gap-04 §5.4 card catalogue: threats > disk > FDA > stale Checkup > memory > updates > tips.
- **Anatomy:** tinted icon · title (≤ 48 characters) · reason with the measured number · one action · ✕. The ✕ menu offers "Snooze 7 days" and "Don't suggest this again".
- **Weekly reminder card:** appears when the last Checkup is ≥ 7 days old (the vendor's "weekly"), with **Run Checkup**. It shares its schedule with the `reminder.cleanup` notification (§6.2) so the user isn't told twice: the card shows only if the notification was dismissed or not delivered.
- Settings › Monitor › **Show suggestions** (on) and **Checkup reminders** (Weekly).

### 4.13 Empty, loading and error states

- **Vendor:** a KB article is titled "Troubleshoot the CleanMyMac Menu not loading correctly" (VERIFIED-3P, 13 §3.34). If background items are disallowed, the Menu won't open (VERIFIED-K, 01 §8).
- **Ours (INFERRED):**
  - On open, render the **last snapshot** from the App Group immediately (no blank tiles), then refresh. Each tile shows a 1-line skeleton only if no snapshot exists.
  - If the agent is not running: a banner "Monitor is paused" with **Start**.
  - If the login item needs approval (`SMAppService.Status.requiresApproval`): "Allow in Login Items" → `SMAppService.openSystemSettingsLoginItems()`.
  - If FDA is missing: Protection and Trash values show "Needs access" instead of a number.

---

# Part B — Health Monitor alerts (5.x) and our **alert engine**

## 5. How the vendor presents alerts

| Generation | Presentation | Evidence |
|---|---|---|
| CMM3 | **Custom alert panels** owned by the Menu app, one nib per alert type. Each has a title, message, primary button, "View in CleanMyMac", Dismiss, Learn More…, an **Ignore ▾** split button and in-panel Progress/Done/Failed tabs. With the Menu turned off, only the Scheduler reminder still appeared. | VERIFIED (E9, E10) |
| X | X 4.6.2 could free RAM **right from the notification**. So X alerts carried actions (02 §6, citing the DevMate 4.6.9 notes, VERIFIED-K). X had a **Notifications** preferences tab: weekly cleanup reminders, tips about unused features, the full-uninstall prompt, overfilled Trash and cluttered drives (including external), low-RAM warnings (VERIFIED-K, 13 §3.42, https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu). | VERIFIED-K |
| 5.x | The **Health Monitor** background item raises alerts even when the main app is closed: low disk space, high memory use, unresponsive apps, and "uninstall completely?" when an app goes to the Trash. It also powers real-time malware monitoring. | VERIFIED-K (01 §8, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes) |
| 5.x, form | **GAP: macOS notification or custom panel.** INFERRED **macOS notifications** (`UNUserNotificationCenter`) for most alerts. The Health Monitor is a separate, windowless login item, while custom panels lived in the Menu process in CMM3. The 5.x profiles carry no time-sensitive entitlement (E1), so alerts are probably delivered at the normal ("active") level. §9 step 4 settles it by reading the Notification Center database. | INFERRED |

## 6. Alert catalogue

### 6.1 Reading the table

- **Vendor trigger / threshold:** what the vendor documents. "—" means not published.
- **Vendor UI:** buttons. CMM3 values are VERIFIED (E9). X and 5.x values are GAP unless stated.
- **Ours:** our default trigger (INFERRED), how we present it, the action buttons (`UNNotificationAction` titles, our own wording) and the snooze options. On macOS, a banner shows one action directly and the rest under an "Options" menu (INFERRED from current macOS behaviour; check on device).
- Every alert has its own toggle in Settings › Notifications. Thresholds sit next to the toggle. All alerts honour **Pause Alerts** and Focus.

### 6.2 The catalogue

| ID (ours) | Vendor evidence (generation) | Vendor trigger / default threshold | Vendor UI and snooze | **Ours: trigger and default** | **Ours: presentation** | **Ours: actions** | **Ours: snooze / re-arm** |
|---|---|---|---|---|---|---|---|
| `disk.low` | CMM3, X, 5.x (VERIFIED, VERIFIED-K) | CMM3: per-volume computed default (`defaultThresholdForRootDiskVolume`) with a "close to threshold" de-bounce (VERIFIED, 08 §3.1.1). Popup most likely Don't Warn · 2 · 5 · 10 · 15 · 20 · 30 · 50 · 100 GB (split INFERRED in 20-gap-06 §3.3). 5.x: no key or value found | CMM3 panel: **Launch CleanMyMac** · **Dismiss** (E9) | Warn when startup **available** < **min(50 GB, max(10 GB, 5 % of capacity))**; critical < **max(3 GB, 2 %)**. Sustained for 2 samples (≥ 2 min). (08 §6.2, §14.3) | Notification (critical: notification **and** the status-item dot plus alert strip) | **Clean Up…** (foreground; starts Checkup) · **Empty Trash (7.4 GB)** (only if Trash ≥ 1 GB; confirmation in the panel) | Snooze 1 day / 1 week. Re-arm when available rises 20 % above the threshold. At most once per 24 h per band. |
| `memory.heavy` | CMM3; X 4.6.2 (free from notification); X 4.14.2; 5.x (VERIFIED / VERIFIED-K) | CMM3: "RAM + Swap … Almost full" (both physical and virtual memory nearly exhausted). 5.x: "high memory usage", no number | CMM3: **Learn More…** · **Ignore ▾** (For Now / Forever) (E9) | Memory pressure **critical ≥ 60 s**, or warn ≥ 5 min **and** swap > 50 % of RAM | Notification | **Free Up** (runs in the agent; result in a follow-up banner) · **Show Top Apps** (opens Monitor › Memory) | Ignore 1 h / Today / Forever. Re-arm after 10 min at normal. At most once per 2 h. |
| `app.hung` | CMM3, 5.x (VERIFIED / VERIFIED-K) | CMM3 used WindowServer's unresponsive-app notification (08 §5.9). 5.x: "unresponsive apps". No delay published | CMM3: **Quit** · **Force Quit All** · Ignore ▾ (For Now / Forever); per-app and per-session ignore lists (08 §3.1.1) | A GUI app reported unresponsive for ≥ **5 s** (re-check after 2 s), not in the ignore list | Notification (one per incident; multiple apps grouped into one with a count) | **Force Quit** (destructive; names the app) · **Wait** | "Never for this app" (adds the bundle ID to the ignore list). Re-arms per process instance. |
| `trash.large` | CMM3, X (VERIFIED / VERIFIED-K); 5.x key `TrashSizeAlertsEnabled` (VERIFIED-X) | CMM3 "Notify when Trash size exceeds": most likely Don't Notify · 500 MB · 1 · 2 · 3 · 5 · 10 · 20 · 50 · 100 GB (split INFERRED in 20-gap-06 §3.3). 5.x: on/off key only | CMM3: **Empty Trash** · **View in CleanMyMac** · Dismiss; Emptying → Done tabs (E9) | Total Trash (user plus all mounted volumes) > **5 GB** (options Off / 1 / 2 / 5 / 10 / 20 GB) | Notification | **Empty Trash…** (opens a confirmation in the panel; never empties silently) · **Review** (opens Finder Trash) | Remind in a week. Re-arm only if size doubles or after 7 days. |
| `app.trashed` | CMM3, X, 5.x (VERIFIED / VERIFIED-K) | Immediate when an app lands in the Trash. CMM3 setting "Offer to correctly uninstall applications" (VERIFIED, 08 §7.1) | CMM3: **Uninstall Completely** · **View in CleanMyMac** · Dismiss; Progress / Done / Failure tabs ("Uninstallation Failed") (E9) | A `.app` bundle appears in `~/.Trash` (FSEvents on the Trash; needs FDA). Skip Apple apps and apps we can't identify | Notification | **Remove Leftovers…** (opens the Uninstaller leftovers review for that bundle ID; nothing is deleted from the banner) | "Don't ask for this app". Once per bundle ID. |
| `threat.found` | X, 5.x (VERIFIED-K, 04 §1) | Real-time monitor finds malware or a PUA in a new or changed item (04 §1) | — | Our engine flags an item (04 §8) | Notification, plus the Protection tile turns red and the Health band goes Critical | **Review** (foreground; results preselected) · **Remove…** (asks in the app) | Not snoozable while unresolved. Re-alerts only for new items. |
| `updates.available` | X 4.11.4 and 4.14.0 (VERIFIED) | X: informative notification listing the **top outdated apps** (VERIFIED, E8) | — | Daily background check finds ≥ 1 update not ignored | Notification (body names up to 3 apps, then "+N") | **Review Updates** (opens Updater) | "Later" = tomorrow. At most once per day. Silent if nothing new since the last alert. |
| `bt.lowBattery` | X 4.14.0 (VERIFIED); 5.x red under 20 % (VERIFIED-K) | X: low-battery alert for Bluetooth devices (not in the App Store edition). 5.x visual threshold **< 20 %** | — | A connected device ≤ **20 %** (options 10 / 15 / 20 / 30 %) | Notification (one per device) | **OK** · **Open Bluetooth Settings** | Once per device per discharge. Re-arm above 50 % or after reconnecting at > 20 %. |
| `battery.low` (Mac laptop) | Not a vendor alert (macOS already warns) | — | — | Off by default; never on a Mac mini | — | — | — |
| `battery.drain` (laptop) | X 4.12.4 / 4.13.6 (VERIFIED) | Sudden burst of consumption. 4.13.6 shows time until empty and offers Display Dimming and Low Power Mode (macOS 12+) | — | Discharge power > 2 × the 30-min median for 3 min | Notification | **Show Energy Users** · **Low Power Mode** | Once per discharge session. **N/A on a Mac mini.** |
| `ups.onBattery` / `ups.low` (mini) | Not a vendor alert | — | — | UPS switches to battery; level ≤ halt level + 10 % (08 §14.2) | Notification, `.timeSensitive` if the entitlement is present (08 §6.3 reserves that level for this, `threat.found` and critical `disk.low`) | **Show Status** | Each transition. |
| `battery.failing` (laptop) | CMM3 (VERIFIED) | CMM3 battery alert shows "Health: n%" and capacity in mAh (E9) | CMM3: Learn More… · Ignore ▾ | Condition "Check Battery" / "Permanent Battery Failure", or health < 80 % | Notification | **Learn More** (in-app page) | Remind in a week / Ignore forever. |
| `disk.smart` / `disk.life` / `disk.hot` | CMM3 (VERIFIED) | CMM3: critical SMART, low SSD life, high disk temperature (08 §6.2) | CMM3: Learn More… · Ignore ▾ (Forever / **Remind in a Week**) · Dismiss (E9) | NVMe critical warning ≠ 0 or rising media errors; life left ≤ 10 %; SSD > 70 °C for 5 min | Notification | **Back Up Now** (opens Time Machine settings) · **Learn More** | Remind in a week (hardware conditions change slowly). |
| `reminder.cleanup` | X, 5.x (VERIFIED-K); 5.x key `SmartCareReminderEnabled` (VERIFIED-X) | Weekly cleanup reminders (01 §10; 02 §6) | — | No Checkup for **7 days** (Off / 3 days / Weekly / 2 weeks / Monthly), at 10:00 local time (`UNCalendarNotificationTrigger`) | Notification and the Monitor reminder card (§4.12) | **Run Checkup** (foreground, autostart) · **Tomorrow** | "Turn off reminders". Rescheduled after every Checkup. |
| `tip.feature` | X tips, 5.x Recommendations (VERIFIED-K) | Feature suggestions | — | At most one per week, only from local rules (e.g. "Trash on external drive 3 GB"). No marketing | **Monitor card only**, never a notification | (card action) | Snooze 7 days / Don't suggest again. |
| `drive.cluttered` (optional) | X Notifications tab (VERIFIED-K) | Cluttered drives, including external | — | An external volume mounts with ≥ 1 GB of its own Trash or junk | Notification (off by default) | **Clean Drive…** · **Eject** | Once per volume UUID per 7 days. |
| `notifications.denied`, `monitor.paused`, `helper.outdated` | — | — | — | Self-health problems (08 §14.2) | **Panel banner and main-app banner**, never a notification | (fix button) | — |

### 6.3 Snooze model (ours, INFERRED, maps the CMM3 model)

| Vendor (CMM3, VERIFIED) | Ours | Storage (App Group defaults, key `alerts.ignore`) |
|---|---|---|
| Ignore For Now | "Not now": suppress until the condition clears and re-arms | `.untilRecovered` |
| (session list) | Clear at agent launch | `.thisSession` |
| Remind in a Week | "Remind me in a week" (hardware and Trash) | `.until(Date)` |
| Ignore Forever | "Turn off this alert" (flips the Settings toggle; visible and reversible) | `alerts.<id>.enabled = false` |
| per-app ignore (`permanentlyIgnoredApps`) | "Never for this app / device / volume" | `.forSubject(Set<String>)` |
| Reset All Warnings | Settings › Notifications › **Reset ignored alerts** | clears all of the above |

**Global pause.** Pause Alerts 1 h / Until tomorrow 08:00 / Until turned back on (`alerts.pausedUntil`). Focus is honoured automatically by the system.

### 6.4 Settings › Notifications (ours) vs the vendor

| Vendor fact | Ours |
|---|---|
| 5.x: `TrashSizeAlertsEnabled`, `SmartCareReminderEnabled`, `ShowAssistantRecommendations`, `MenuAppEnabled` (E5) | One toggle per alert ID, plus "Show suggestions" and "Show Monitor in menu bar" |
| CMM3: free-space and Trash threshold popups, "Offer to correctly uninstall applications", "App monitor: notify about hung applications", "Reset All Warnings" (08 §7.1) | Threshold popups for `disk.low`, `trash.large`, `bt.lowBattery`, `memory.heavy` (Sensitive / Normal / Only critical); per-subject ignore lists with **Manage…**; Reset ignored alerts |
| 5.x Notifications tab: INFERRED-strong (20-gap-06 §2.3); the nine-tab replica is X (20-gap-06 §2.2) | Settings tab **Notifications**, next to **Monitor**. Rows and defaults as in 20-gap-06 §5.3, which match §6.2 here |

Keys (extends 08 §7.2): `alerts.<id>.enabled`, `alerts.<id>.threshold`, `alerts.ignore`, `alerts.pausedUntil`, `monitor.tiles` (ordered array), `monitor.statusReadout`, `monitor.alertDotColor`, `monitor.quickActions`, `reminder.interval`, `reminder.hour`, `privacy.publicIP`, `privacy.wifiDetails`.

---

## 7. Implementation sketch (Swift, INFERRED)

### 7.1 Tile availability and grid

```swift
import IOKit.ps

enum MonitorTile: String, CaseIterable, Codable, Sendable {
    case protection, storage, memory, power, cpu, network, devices   // KB order; power = battery or UPS
}

struct PowerCaps: Sendable { var internalBattery = false; var ups = false }

func powerCaps() -> PowerCaps {
    var caps = PowerCaps()
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return caps }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
              let type = d[kIOPSTypeKey] as? String else { continue }
        if type == kIOPSInternalBatteryType { caps.internalBattery = true }
        if type == kIOPSUPSType { caps.ups = true }
    }
    return caps
}

/// User order (Settings) minus hidden and unavailable tiles; pairs of two; an odd last tile spans both columns.
func gridRows(order: [MonitorTile], hidden: Set<MonitorTile>, caps: PowerCaps) -> [[MonitorTile]] {
    let tiles = order.filter { !hidden.contains($0) && ($0 != .power || caps.internalBattery || caps.ups) }
    return stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
}
```

Re-run `powerCaps()` on `IOPSNotificationCreateRunLoopSource` callbacks so a UPS plugged in later adds the tile without a relaunch.

### 7.2 Bluetooth connect / disconnect (off the main thread)

```swift
import IOBluetooth

func setConnected(_ device: IOBluetoothDevice, _ connect: Bool) async -> Bool {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let rc = connect ? device.openConnection() : device.closeConnection()   // synchronous (E12)
            // openConnection reports an already-open link as an error since 10.7, so re-read the state.
            cont.resume(returning: rc == kIOReturnSuccess || device.isConnected() == connect)
        }
    }
}
```

### 7.3 Eject all external volumes

```swift
func ejectAllExternal() async -> [(URL, Error)] {
    let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey]
    let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    var failures: [(URL, Error)] = []
    for url in vols {
        let v = try? url.resourceValues(forKeys: Set(keys))
        guard v?.volumeIsInternal == false, (v?.volumeIsEjectable == true || v?.volumeIsRemovable == true) else { continue }
        do { try await Task.detached { try NSWorkspace.shared.unmountAndEjectDevice(at: url) }.value }
        catch { failures.append((url, error)) }   // show "In use by …" via the DiskArbitration dissenter (08 §5.4)
    }
    return failures
}
```

### 7.4 Alert record and de-duplication

```swift
struct AlertState: Codable, Sendable {
    var id: String                 // "disk.low", "app.hung", …
    var subject: String?           // bundle ID, device address, volume UUID
    var band: Int                  // 1 warn, 2 critical
    var firstSeen: Date
    var lastPosted: Date?
    var consecutiveSamples: Int    // fire only at >= 2 (08 §6.3, stats pattern)
}
// Request identifier "alert.<id>.<subject ?? "-">": a re-post replaces the old banner,
// and recovery calls removeDeliveredNotifications(withIdentifiers:).
```

Mirror every posted alert into the panel's alert strip and the in-app Notifications inbox (20-gap-04 §6.2), so a swiped-away banner is still findable.

---

## 8. Changes to 08-menu-app (what this file revises)

| 08 section | Change |
|---|---|
| §4.1 status item | Keep icon only by default. Use a **monochrome cut-out dot** for pending issues instead of tinting the glyph. Colour is opt-in. |
| §4.2 layout | Replace the hand-placed grid with the **KB-order grid rule** (§3.3). Battery → "Power" slot (battery, UPS or omitted). External drives move **into Devices**. Detail views push in place. |
| §4.3–4.11 | Use the per-tile tables in §4 (big value, status, gauge, single action, detail fields). |
| §4.8 network | Speed test via `networkQuality`. Public IP off by default. Wi-Fi name only with Location consent. |
| §4.10–4.11 | Connect/disconnect and eject specified with API caveats (§7.2, §7.3). iPhone/iPad stats are a non-goal. |
| §4.12 | One card at a time, de-duplicated against the reminder notification. |
| §6.2 | Use the merged catalogue in §6.2 (adds vendor buttons, `tip.feature` as card-only, and Mac-mini applicability). |
| §6.3 ignore store | Matches §6.3 here; "Turn off this alert" flips the visible Settings toggle instead of a hidden "forever" flag. |

---

## 9. On-device verification kit (vendor 7-day trial on the Mac mini; record structure and numbers only, never copy strings or art)

Run on a test user account. Delete fill files and uninstall the trial afterwards.

1. **Menu layout and size.** Open the Menu. In **Accessibility Inspector**, select the panel window and note its frame (width × height), the order of `AXGroup`/`AXButton` tiles, each tile's title role, and what is clickable. Then:
   ```bash
   osascript -e 'tell application "System Events" to tell process "CleanMyMac_5_Menu" to get {name, size} of every UI element of window 1'
   ```
   Screenshot every detail view, including Network. Note whether a Battery tile appears on the mini, and whether drives appear under Connected Devices or elsewhere. Closes gaps 1, 3, 5.
2. **Status item.** Trigger an alert (step 5) and see whether the icon changes (badge, colour, text). Check Settings › Menu for any readout option. Closes gap 4.
3. **Defaults and thresholds.**
   ```bash
   defaults read com.macpaw.CleanMyMac5.Menu
   defaults read com.macpaw.CleanMyMac5.HealthMonitor
   plutil -p ~/Library/Group\ Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Preferences/*.plist | grep -iE 'alert|threshold|remind|notif|trash|disk|memory|battery|device'
   ```
   Record key names and default values only. 20-gap-06 §3.4 found that the Setapp `.Menu` domain holds only Setapp framework keys, so expect the alert keys in the App Group plist; its §7 gives a toggle-diff procedure for finding each key. Closes gap 2.
4. **Notification form and buttons.** After each alert fires, read the newest records (needs FDA for Terminal):
   ```bash
   DB=~/Library/Group\ Containers/group.com.apple.usernoted/db2/db
   [ -f "$DB" ] || DB="$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db"
   sqlite3 "$DB" "select a.identifier, datetime(r.delivered_date+978307200,'unixepoch') from record r join app a using(app_id) where a.identifier like 'com.macpaw%' order by r.delivered_date desc limit 10;"
   ```
   If rows appear for `com.macpaw.CleanMyMac5.HealthMonitor` (or `.Menu`), the alerts are macOS notifications. Decode `data` with `plutil -p` to see the category and the number of actions (structure only). If no rows appear while an alert is on screen, it is a custom panel: note its window owner in Accessibility Inspector.
5. **Trigger each alert and time it.**
   - Low disk: `dd if=/dev/zero of=~/fill.bin bs=1m count=<N>` until available drops under candidate thresholds (e.g. 20 GB, 10 GB, 5 GB). Note when the alert fires, then `rm ~/fill.bin`.
   - Heavy memory: `sudo memory_pressure -S -l critical` (simulated, E13), then `-l warn`.
   - Unresponsive app: open TextEdit, `kill -STOP <pid>`, click its window, time the alert, then `kill -CONT <pid>`.
   - Trash size: copy a 6 GB file to the Trash; repeat at 2 GB.
   - App to Trash: drag a small disposable app to the Trash.
   - Bluetooth low battery: note the % at which a Magic accessory turns red and the % at which an alert appears (it happens over days; log it).
   - Updates: install an older version of a free app.
   - Weekly reminder: read the reminder-date key from step 3. Don't change the system clock.
   Closes gaps 2 and 7 (alert part).
6. **Health Monitor behaviour.**
   ```bash
   log stream --info --predicate 'process == "CleanMyMac_5_HealthMonitor" OR process == "CleanMyMac_5_Menu"'
   ```
   Watch subsystems during step 5 (CacheDelete, IOKit, WindowServer notifications). Also check `top -l 2 -stats pid,command,cpu,mem | grep -i cleanmymac` with the panel closed and open, to set our resource budget against theirs.
7. **Network endpoints.** During a Menu speed test, run `sudo lsof -i -n -P | grep -i cleanmymac` (or use LuLu) to confirm `speedtest.macpaw.com` and any other hosts.

Append the results here as "§9 results".

---

## 10. Naming and originality (INFERRED)

- Do not use: "CleanMyMac", "The Menu" or "CleanMyMac Menu" as a product name, "Mac Health" as a branded heading, "Smart Care", "My Tools", "Moonlock", "Sonar", "Assistant" (as branding), or the vendor's glyphs, gradients and hero art.
- Our labels: **Monitor**, **Health**, **Checkup**, **Toolbox**, **Clean Up**, **Free Up RAM**, **Remove Leftovers…**, **Not now**, **Remind me in a week**, **Turn off this alert**, **Reset ignored alerts**.
- Generic verbs (Empty Trash, Force Quit, Eject, Connect, Disconnect, Speed Test) are platform vocabulary and fine to use.

---

## 11. Remaining gaps after this pass

| # | Gap | Status | Closes with |
|---|---|---|---|
| 1 | Exact 5.x on-screen tile order, panel size and detail-view contents | KB list VERIFIED-K; screenshot description VERIFIED-3P; layout INFERRED | §9 step 1 |
| 2 | 5.x Network fields and whether the speed test survived | Open | §9 steps 1 and 7 |
| 3 | Menu-bar icon states or text | INFERRED icon only | §9 step 2 |
| 4 | 5.x Connected Devices actions (connect/disconnect, eject, clean junk) and where drives appear | Open for 5.x; VERIFIED for X | §9 step 1 |
| 5 | 5.x alert thresholds | Open; our defaults set | §9 steps 3 and 5 |
| 6 | Notification vs custom panel; button titles; snooze options in 5.x | INFERRED notification | §9 step 4 |
| 7 | Mac Health numeric cut-offs | Unpublished; ours in 20-gap-04 §5.5 | not observable without code; keep ours |
| 8 | 5.4–5.7 release notes (Menu changes since 5.3.1) | Unreachable (appcast host blocked) | a session with App Store or `updates.cleanmymac.com` access |

---

## 12. Sources

**MacPaw-hosted or MacPaw-shipped (fetched this pass)**
- CleanMyMac X release notes 4.10–4.15.8: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html
- CleanMyMac X release notes to 4.15.14: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41514.0.2512021236/releasenotes.html
- CleanMyMac X appcast (dates): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml
- Empty feeds: …/com.macpaw.CleanMyMac-setapp/updates.xml , …/com.macpaw.CleanMyMac4.Menu/updates.xml , …/com.macpaw.CleanMyMac4.HealthMonitor/updates.xml (same host)
- CleanMyMac 5 Menu and Health Monitor provisioning profiles: https://raw.githubusercontent.com/eliekh05/provision-files/HEAD/profiles/CleanMyMac_5_Menu.provisionprofile , https://raw.githubusercontent.com/eliekh05/provision-files/HEAD/profiles/CleanMyMac_5_HealthMonitor.provisionprofile
- CleanMyMac 3 Menu alert strings and gear menu: https://github.com/auspham/mac-essential/tree/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/Resources/en.lproj (`LowDiskSpaceAlert`, `TrashSizeAlert`, `TrashedAppAlert`, `HungAppsAlert`, `RAMUsageAlert`, `SMARTAlert`, `BatteryHealthAlert`, `MainMenu` `.strings`)
- CleanMyMac 3 Help topic 94: https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html

**MacPaw KB facts recorded by earlier passes (VERIFIED-K; not re-read)**
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu , …/cleanmymac-menu-on-off , …/cleanmymac-menu-recommendations , …/devices-monitoring , …/cpu-temperature , …/disk-no-health-and-temperature , …/menu-no-elements , …/cleanmymac-processes , …/allow-background-items , …/mac-health (via 01-overview §5.2, §8, §10, §11; 13-helpcenter §3.30–3.34)
- https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu (via 13-helpcenter §3.42; 02-smart-care §6)
- TidBITS 5.0 watchlist: https://tidbits.com/watchlist/cleanmymac-5-0/ (via 01-overview §10)
- MacStories / 9to5Mac on the 5.x tile grid (via 02-smart-care §2)

**Third-party evidence (fetched this pass)**
- Health Monitor CacheDelete log: https://raw.githubusercontent.com/pabloguia/XCodeVault/15bd48e15b8f0894ede4e153f864a7122c88b326/docs/research/evidence/e18-simctl-log-erase-macos26.6.2-25G83-xcode26.5-x86_64-superseded-20260915T202842.txt
- Menu as a window (AeroSpace rule): https://github.com/JetNoLi/dotfiles/blob/HEAD/aerospace/.config/aerospace/aerospace.toml
- Menu HTTP cookies path: https://github.com/themoretheless/ppduster/blob/HEAD/rules/apps-personal.yaml
- 5.x preference keys: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh
- Screenshot description (hero, tiles, recommendation card): https://raw.githubusercontent.com/ProFiveCK/my-Kikau/ef7bbea8fca20e34a088a7266fe9762e35de93a4/docs/IMPLEMENTATION_PLAN.md
- ZDNet on the X Menu and Connected Devices (mirror): https://raw.githubusercontent.com/techidaily/site-tech-renaissance/8dd4bc00b87802dfea500833bf1920cc7f12e054/source/_posts/top-1-essential-app-you-need-on-your-fresh-macos-grab-the-discounted-offer-now-tips.md
- Speed-test host: https://github.com/SukkaW/Surge/blob/HEAD/Source/domainset/speedtest.conf ; https://github.com/HotKids/Rules/blob/HEAD/Surge/RULE-SET/Speedtest.list
- Process names and log folders: https://github.com/vzaliva/perf-glance/blob/HEAD/rules/builtin.d/11-apps-macos.toml ; https://github.com/burakoskay/Milo/blob/HEAD/App/Milo/Runtime/ProcessData.swift ; https://github.com/andreychev/dotfiles/blob/HEAD/.config/mole/operations.log
- Notification Center DB path: https://github.com/ydkhatri/mac_apt/blob/HEAD/plugins/notifications.py ; https://github.com/objective-see/AuRevoir/blob/HEAD/auRevoir/AuRevoir/Database.m ; https://github.com/HackTricks-wiki/hacktricks (macos-sensitive-locations.md)
- Clone observations (weak): https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/MenuBarContent.swift ; https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md ; https://github.com/AThevon/TokenEater (`TokenEaterApp/Windows/Monitoring/MonitoringView.swift`)

**Apple (fetched this pass)**
- HIG, The menu bar: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
- `IOBluetoothDevice` `openConnection()`, `closeConnection()`, `pairedDevices()`: https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice
- `CWInterface.ssid()`: https://developer.apple.com/documentation/corewlan/cwinterface/ssid()
- `NSStatusItem.button`: https://developer.apple.com/documentation/appkit/nsstatusitem/button
- `memory_pressure`: https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c

**Sibling reports relied on:** 01-overview (§2, §5.2, §8, §10, §11), 02-smart-care (§2, §6), 04-protection (§1, §8), 05-performance (§4.1, §7), 06-applications (§3.10), 08-menu-app (§3–§7, §12, §14), 09-design (§B.9), 10-internals (§1, §2, §4), 13-helpcenter (§3.28, §3.30–3.34, §3.42, §4.14), 20-gap-04 (§3.7, §5, §6), 20-gap-06 (§2, §3.3, §3.4, §5.3, §7).
