# 20-gap-06 — CleanMyMac 5.x Settings window (⌘,), preference keys and alert defaults

**Gap-fill assignment.** Rebuild the CleanMyMac 5.x Settings window as of 5.6–5.7.1. That means the tab list and order, every control with its default, and the preference keys the 5.x processes read. It also covers the Notifications and alert thresholds, the analytics opt-out, the Full Disk Access (FDA) and helper status, and any CleanMyMac Business / Jamf configuration-profile keys.

**Closes or narrows:** 01 §14 gap 3 · 02 §15 gap 9 · 08 §12 gap 2 · 09 §7 gap 7. It also settles the tab-list disagreement between 01 §10 and 04 §5 / 13 §3.28.

**Target build:** our own original app (no MacPaw names, art or copy) for an Apple-silicon Mac mini on macOS 14+, with extras on 15 and 26. Our naming follows 01 §13 and 04 §14: **Checkup** (= Smart Care), **Shield** (= Protection), **Monitor** (= the Menu), **Clutter**, **Ignored Items**.

Date of research: 2026-10-12. Latest vendor build: **5.7.1, `50701.0.2609301754`**. VERIFIED from the Homebrew cask (fetched): https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/c/cleanmymac.rb.

---

## 0. Method, source access and evidence labels

### 0.1 What was reachable this pass

| Source | Result |
|---|---|
| `macpaw.com` (KB, product pages), `cleanmymac.com`, `setapp.com`, `apps.apple.com`, `tidbits.com`, `marketplace.jamf.com`, `updates.devmate.com` | **Not reachable.** DNS failure in WebFetch; the egress proxy refused the CONNECT for macpaw.com. No archive mirrors were used. |
| WebSearch | **Unavailable.** The per-turn search budget, shared by all agents in this run, was already used up when this agent started. No search-engine excerpts were gathered this pass. |
| GitHub code search (all public repos) + `raw.githubusercontent.com` | **Reachable.** This was the main new source: dotfiles, exported plists, uninstall scripts, clones, and the CleanMyMac 3 bundle mirror. |
| DevMate S3 (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/...`) | **Reachable.** Read this pass: the 5.x appcast, the cumulative 5.0–5.3.1 release notes, and the cumulative CleanMyMac X 4.x release notes. |

All KB statements below were verified by earlier teammates (01, 02, 04, 08, 13) from macpaw.com, mostly via search excerpts. They could not be re-fetched this pass and are labelled as such.

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED-KB (via NN)** | MacPaw help-centre statement, verified by teammate report NN; not re-fetchable this pass. |
| **VERIFIED-OSS** | Read this pass in a public GitHub file that records the **shipped** app's behaviour or data (a dotfile writing real keys, an exported plist, an uninstall script, a cask). The URL is given. |
| **VERIFIED-D** | Read this pass in MacPaw's own DevMate release notes or appcast, or in the CleanMyMac 3 bundle's own strings. |
| **REPLICA** | A third-party clone's UI code. Weak evidence: it may copy CleanMyMac X rather than 5.x, or invent things. |
| **INFERRED** | Our reasoning or our recommendation for our implementation. |

---

## 1. Answers in brief

1. **Tab list (settled as far as public evidence allows).**
   - The KB-verified 5.x tabs are **General, Scanning, Ignore List, Protection, Menu** (VERIFIED-KB via 01 §10).
   - The nine-tab strip **General · Scan · Notifications · Menu · [slot 5] · Protection · Disk Access · Analytics · Ignore List** comes from a replica of **CleanMyMac X 4.14/4.15**, not 5.x (§2.2).
   - The most probable 5.x set, in X's relative order, is **General · Scanning · Notifications · Menu · Protection · Ignore List**.
     - Five of these are KB-verified.
     - **Notifications** is INFERRED-strong. It rests on the alert-toggle keys found in 5.x prefs (§4) and on the KB saying Settings › Menu holds only two controls.
     - Disk Access, Analytics and Assistant tabs are **unverified for 5.x and probably absent.**
2. **Real 5.x preference keys found (VERIFIED-OSS).** These were read from a Setapp 5.x install:
   - in the **main domain** `com.macpaw.CleanMyMac-setapp`: `MenuAppEnabled` and `ShowAssistantRecommendations`;
   - in the **App Group plist** `S8EX82NJP6.com.macpaw.CleanMyMac-setapp`: `SoundsEnabled`, `CustomThemes`, `SmartCareReminderEnabled`, `TrashSizeAlertsEnabled` and `MalwareScanMode` (`"protected"` | `"manual"`).
   - A real exported 5.6.0 (Setapp) main-domain plist adds `CMIsUserEligibleForAppsStatistics`, `FRServiceLastKnownBootDate`, `FRServiceLastKnownVersion` (`50600.0.2608201305`), `KeychainAccessibilityMigration` and the Setapp `STP_*` keys. Another user's ignore list adds `DbHash`, `DbSize`, `LaunchCount`, `TotalCleansCount`, `CMAUIdentifier` and `LastActiveBundle`. Details in §4.
3. **`MalwareScanMode` is the real-time monitor switch, not the Quick/Balanced/Deep depth.** It is `protected` (continuous) vs `manual`, so it maps to **Enable Malware Monitor**. The depth key was not found (§3.5, §4).
4. **No threshold keys were found** (free space, Trash size, memory, hung apps) for 5.x. Only the `TrashSizeAlertsEnabled` on/off is known. The CleanMyMac 3 threshold menus are recovered exactly, including their likely split (§3.3).
5. **X stored the Smart Scan composition as a dictionary of *disabled* task IDs**: `SmartScanModuleDisabledTasks = { CMMalwaresModuleScanIdentifierDetection = true }` (VERIFIED-OSS). We copy the *idea* (store exclusions, not inclusions) (§3.2).
6. **CleanMyMac Business / Jamf configuration-profile keys:** not published anywhere reachable. There is no ProfileManifests entry, no public `.mobileconfig`, and no GitHub hit. **GAP.** Business was sunset on 2026-07-14 (VERIFIED via 01), so this gap will probably never close. §5 gives our own managed-preferences schema.

---

## 2. The tab list: evidence, conflict and verdict

### 2.1 Evidence table

| # | Source | Tabs (order as given) | Era it describes | Strength |
|---|---|---|---|---|
| A | MacPaw KB articles `general`, `smart-care`, `cleanmymac-safety`, `protection-scan-options`, `real-time-monitoring-on-off`, `background-scanning-on-off`, `cleanmymac-menu-on-off`, `cleanmymac-menu-recommendations` | **General** (Updates) · **Scanning** (Smart Care tree) · **Ignore List** · **Protection** · **Menu**. No order is given. | 5.x | VERIFIED-KB (via 01 §10, 02 §1.6, 04 §1, 13 §3.16–3.30) |
| B | ddlmanus/MacOptimizer `MalwareRemovalReplicaView.swift` (preferences replica) | General · Scan · Notifications · Menu · *[slot 5: the clone's own "Mac Optimization Agent"]* · Protection · Disk Access · Analytics · Ignore List | **X 4.14/4.15** (see 2.2) | REPLICA. https://raw.githubusercontent.com/ddlmanus/MacOptimizer/5fdfcc04cf6ad09752174a64dff3fc960bc66445/AppUninstaller/MalwareRemovalReplicaView.swift (re-read this pass) |
| C | jayvicsanantonio/VaderCleaner `PreferencesView.swift` (a 5.x-styled clone) | General · Scanning · Notifications · Menu Bar · Protection · Ignore List | 5.x-inspired. The file names no vendor reference. | REPLICA (weak). https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/07a21ea959e9575e25bab02600c7cb4b47446022/VaderCleaner/PreferencesView.swift |
| D | X KB pages: Notifications tab for reminders and alerts; Preferences › Assistant; Preferences › Scanning | X had **Notifications**, **Assistant** and **Scanning** | X | VERIFIED-KB (via 02 §6, 08 §7.1, 13 §3.36, §3.42) |
| E | X release notes (DevMate, read this pass) | 4.10.0: Assistant recommendations in the Menu "(manage in Preferences)". 4.10.4: Ukrainian theme can be switched off "in the Preferences". 4.14.0: scan speed and intensity configurable "within CleanMyMac's Protection Settings". 4.15.0: "configurable protection scan settings". | X | VERIFIED-D. https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41514.0.2512021236/releasenotes.html |
| F | 5.x prefs keys (Setapp) | Alert toggles `SmartCareReminderEnabled` and `TrashSizeAlertsEnabled`; `SoundsEnabled`; `CustomThemes`; `MalwareScanMode`; `MenuAppEnabled`; `ShowAssistantRecommendations` | 5.x | VERIFIED-OSS (§4) |
| G | CleanMyMac 3 `Preferences.strings` | General · Smart Cleanup · Scheduler · CleanMyMac 3 Menu · Updates · Ignore List · Privacy | CMM3 | VERIFIED-D (via 13 §5) |

### 2.2 Why source B is CleanMyMac X, not 5.x (INFERRED, strong)

- B's Protection pane has a "Powered by: Moonlock Engine" badge, a **Scan Mode** picker (Quick/Balanced/Deep) with **Speed / Depth / Purpose** rows, and the description "Adjust Moonlock Engine scanning performance and features to your preference". That is exactly the X feature set from 4.14.0 ("configure the speed and intensity of your malware scans within CleanMyMac's Protection Settings") and 4.15.0 ("configurable protection scan settings") (VERIFIED-D, source E). Moonlock was named in X 4.14, July 2023 (VERIFIED-KB via 13 §3.15).
- 09 classifies the ddlmanus code as a "pixel-led" replica of **CleanMyMac X** (09 §0 evidence labels).
- Slot 5 sits between Menu and Protection. In X, the Assistant was "managed in Preferences" from 4.10.0 (source E) and could be silenced in "Preferences › Assistant" (source D). So slot 5 was X's **Assistant** tab, which the clone replaced with its own AI-agent tab.
- **Disk Access** and **Analytics** fit X's era:
  - FDA became a macOS requirement in Mojave (2018).
  - CMM3 already had a **Privacy** tab with "Share anonymous usage data" (VERIFIED-D via 13 §5.7), which X plausibly renamed **Analytics**.
  - These two tabs therefore describe X. Nothing places them in 5.x.

### 2.3 Verdict for 5.x (5.6–5.7.1)

| Position (INFERRED order) | Tab | Status in 5.x | Confidence |
|---|---|---|---|
| 1 | **General** | VERIFIED-KB (Updates section) | High |
| 2 | **Scanning** | VERIFIED-KB: the KB names the "Scanning" tab. B's "Scan" is the X label, or the clone's abbreviation. | High for existence. Medium for the exact label ("Scanning" per KB). |
| 3 | **Notifications** | INFERRED-strong. See below. | Medium |
| 4 | **Menu** | VERIFIED-KB | High |
| 5 | **Protection** | VERIFIED-KB | High |
| 6 | **Ignore List** | VERIFIED-KB | High |
| — | Assistant | Probably **absent**. In 5.x the Assistant is a main-window surface (01 §5.1), and recommendations are toggled by `ShowAssistantRecommendations` (§4), probably exposed under Menu › Recommendations or General. | Medium |
| — | Disk Access | Probably **absent**. 5.x surfaces FDA through an Assistant / Mac Health recommendation with an **Allow Access** button, and through the Health score (VERIFIED-KB via 01 §9.1, 08 §8.2). | Low–medium |
| — | Analytics | **Unknown**. A `CMIsUserEligibleForAppsStatistics` eligibility flag exists (§4), but no 5.x opt-out UI is documented. It may sit at the bottom of General. | Low |

**Why Notifications probably still exists in 5.x:**
- The 5.x Setapp App Group plist stores user-togglable alert switches: `SmartCareReminderEnabled` and `TrashSizeAlertsEnabled`. The dotfile author treats them as settings ("Disable Smart Care reminder nags", "Disable trash-size alerts").
- The KB says Settings › Menu holds only **Enable Menu** and **Recommendations**, and TidBITS called Menu settings "very limited" (via 01). So the alert switches need another home.
- X had a Notifications tab (source D), and both clones (B, C) keep one.
- The fallback, if a device check shows otherwise, is a Notifications section inside General. Either way our app ships a Notifications tab.

**Order rationale (INFERRED).** Keep X's relative order (B): General → Scan(ning) → Notifications → Menu → Protection → Ignore List. Drop the three X-only tabs. Clone C independently arrived at the same order.

**Disagreements with existing reports.**
- 01 §10 is right about the five verified tabs. Its "Notifications (X-era; likely still present)" row stands as INFERRED-strong.
- 04 §5 and 13 §3.28 are right to call the nine-tab list weak. This report pins it to X 4.14/4.15.
- 13 §11.3 lists a superset for **our** app. That is a design proposal, not vendor fact. §6 supersedes it.

---

## 3. Every control, tab by tab (vendor), with defaults

Defaults are marked VERIFIED only where a source states them. Otherwise:
- **"default-on (INFERRED-dotfile)"** means a dotfile author wrote `false` to disable the setting. Writing `false` only matters if the default is `true`.
- **"default unknown"** means no basis either way.

### 3.1 General

| Control | Vendor label (short) | Type | Default | Key (domain) | Evidence |
|---|---|---|---|---|---|
| Automatic updates | "Automatically keep CleanMyMac up to date" (Updates section) | checkbox | INFERRED on | INFERRED Sparkle keys `SUAutomaticallyUpdate` / `SUEnableAutomaticChecks` in the main domain | Label: VERIFIED-KB (via 01 §10, 13 §3.28). X's main domain held `SUAutomaticallyUpdate = true` and `SUEnableAutomaticChecks = true` (VERIFIED-OSS, X plist: https://raw.githubusercontent.com/aboqasem/dotfiles/main/synced/defaults/com.macpaw.CleanMyMac4.plist). The 5.x cask livechecks a **Sparkle** feed on `updates.cleanmymac.com` (VERIFIED-OSS, cask), and 5.x runs a `com.macpaw.CleanMyMac5.Updater` LaunchAgent (VERIFIED-OSS, uninstall scripts). |
| (App Store edition) | Updates handled by the App Store | — | — | — | VERIFIED-KB (via 01) |
| (Setapp edition) | Updates handled by Setapp | — | — | Setapp framework keys `STP_*` | INFERRED. `STP_is_first_launch` and `STP_last_used_version` are present (VERIFIED-OSS, §4). |
| Sound effects | label unknown | checkbox | default-on (INFERRED-dotfile) | `SoundsEnabled` (bool, App Group plist) | VERIFIED-OSS (hollow dotfiles, "Silence sound effects"). The UI placement in General is INFERRED; CMM3 kept Sounds in General (VERIFIED-D via 13 §5.1). |
| Custom / seasonal themes | label unknown | checkbox | default-on (INFERRED-dotfile) | `CustomThemes` (bool, App Group plist) | VERIFIED-OSS (hollow: "Disable custom themes (use system appearance)"). The 5.5.4 bundle ships `Snowflakes1…3` + `EmitterMask` (VERIFIED-OSS via 09 §4.5). X 4.10.4: "Updated the Ukrainian theme and added an ability to switch it off in the Preferences" (VERIFIED-D). INFERRED: `CustomThemes` gates seasonal and national overlays, not a light/dark switch. |
| Reduce motion | none | — | follows macOS | — | 5.0.7: the app now adapts to the Mac's **accessibility preferences** to simplify visual effects (VERIFIED-D, 5.0–5.3.1 cumulative notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html). INFERRED: there is no in-app animation toggle. CMM3 had one: "Disable for better performance" (via 13 §5.1). |
| Language | none | — | follows macOS | — | VERIFIED-KB (via 13 §3.29) |
| Appearance (light/dark) | none found | — | — | — | GAP. INFERRED that the canvas is always dark (09 §3.10). |
| Assistant recommendations | label unknown; may be under Menu (3.4) | checkbox | default unknown (INFERRED on) | `ShowAssistantRecommendations` (bool, **main domain**) | VERIFIED-OSS. hollow sets `true` ("Show assistant recommendations in the UI"); hosmelq sets `false`. https://raw.githubusercontent.com/hosmelq/.config/bf50517e14c3195df3f9bf86e31c55c417474319/dotfiles/macos/app-settings.json |
| Usage data / analytics | unknown | unknown | unknown | `CMIsUserEligibleForAppsStatistics` (bool, main domain) is an **eligibility** flag, not necessarily the user's choice | VERIFIED-OSS (§4). The UI is a GAP. |

### 3.2 Scanning ("Customize Smart Care")

**Layout (VERIFIED-KB via 02 §1.6).**
- The left pane lists **Smart Care**. REPLICA C adds the individual modules below it ("Smart Care / its Modules").
- The right pane is a tree of modules → categories → groups with checkboxes.
- Deselecting a parent deselects its children.
- Excluded modules still appear in Smart Care results as **dimmed** tiles.
- In X, deselecting System Junk or iTunes Junk *sub-modules* also affected their standalone module scans (VERIFIED-KB via 02 §2.2). CMM3's footer says the same in reverse: deselecting a whole module removes it from Smart Cleanup but keeps it available for its own scan (VERIFIED-D via 13 §5.3).

**Tree contents.**

| Module node (Smart Care run) | Children | Default | Evidence |
|---|---|---|---|
| **Cleanup** | System Junk (groups) · Mail Attachments · Trash Bins | checked | Module scope: VERIFIED-KB (Smart Care KB, via 02 §3.1). "Only System Junk exposes per-category checkboxes" is REPLICA C. |
| ↳ System Junk groups (the Smart Care subset) | REPLICA C's list, "matching the reference screenshot's set and order": System Caches · User Log Files · System Log Files · Document Versions · User Cache Files · Language Files · Xcode Junk | checked | REPLICA (weak). The full 5.x System Junk list (01 §5) also has Universal Binaries, iOS Device Backups, Broken Preferences, Broken Login Items and Deleted Users. |
| **Protection** | Malware Removal: always **Quick** in Smart Care, plus the DMG option from Settings › Protection | checked | VERIFIED-KB (via 02 §3.1) |
| **Performance** | maintenance tasks: periodic maintenance scripts, Flush DNS Cache | checked | VERIFIED-KB (via 02 §3.1) |
| **Applications** | app updates, excluding system apps and macOS updates | checked | VERIFIED-KB (via 02 §3.1) |
| **My Clutter** | duplicate files in ~/Downloads only | checked | VERIFIED-KB (via 02 §3.1) |

- **Default composition:** "all Smart Care tasks are selected by default" (VERIFIED-KB via 02 §1.5).
- One hands-on 5.x note saw only Cleanup and My Clutter ticked on the results screen (https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md). INFERRED: that is result-tile pre-selection (licence or permission dependent), not the Settings composition.

**Storage.**
- **X:** `SmartScanModuleDisabledTasks` (dict, main domain `com.macpaw.CleanMyMac4`), mapping a task identifier to `true` for each *excluded* task. The observed entry was `CMMalwaresModuleScanIdentifierDetection = true`, meaning the user had excluded the malware scan. VERIFIED-OSS (aboqasem X plist, URL in 3.1).
- **5.x:** key not found. INFERRED: an equivalent "disabled tasks" set in the App Group plist, so HealthMonitor and Menu can tell when Smart Care is due.

### 3.3 Notifications (INFERRED tab; controls from 5.x keys + X KB + CMM3 strings)

| Alert / reminder | 5.x key (if known) | Vendor default | Threshold control (vendor) | Evidence |
|---|---|---|---|---|
| **Smart Care reminders** | `SmartCareReminderEnabled` (bool, App Group) | default-on (INFERRED-dotfile: "Disable Smart Care reminder nags") | **Frequency:** X let you adjust it on the Notifications tab; weekly or bi-weekly recommended. 5.x Menu › Recommendations includes **weekly** cleanup reminders. A 5.x frequency picker is a **GAP**. | Key: VERIFIED-OSS. X frequency: VERIFIED-KB (via 02 §6). 5.x weekly via Menu: VERIFIED-KB (via 01 §10). CMM3 options: Never · Weekly · Once in two weeks · Monthly · Once in three months · Once in six months · Annually; plus "Simply launch" vs "Launch and start full scan" (VERIFIED-D via 13 §5.5). Business: forced runs every 7/14/30 days with 0–2 reminders (VERIFIED-KB via 13 §3.45). |
| **Trash size** | `TrashSizeAlertsEnabled` (bool, App Group) | default-on (INFERRED-dotfile) | threshold key **not found** (GAP) | Key: VERIFIED-OSS. X "overfilled Trash" alerts: VERIFIED-KB (via 08 §2). CMM3 popup: "Notify when Trash size exceeds:" (VERIFIED-D, see the CMM3 menus below). |
| **Low free space / cluttered drives (incl. external)** | not found | unknown | not found | X: VERIFIED-KB (via 08 §2). CMM3: "Warn when free space is less than:", with the default computed per root volume (`defaultThresholdForRootDiskVolume`) and a "close to threshold" de-bounce (VERIFIED-D via 08 §3.1.1). |
| **Heavy memory use** | not found | unknown | none known | X 4.14.2: alert "when your Mac's memory is overloaded" (VERIFIED-D). X 4.6.2: free up RAM from the notification (via 02 §6). CMM3 "RAM + Swap almost full" (via 08). |
| **Unresponsive apps** | not found | unknown | none known | CMM3 checkbox "Notify about hung applications" (App monitor) (VERIFIED-D). 5.x HealthMonitor offers it (VERIFIED-K via 08 §6.2). |
| **App moved to Trash → full uninstall offer** | not found | unknown (CMM3: likely on) | — | CMM3 checkbox "Offer to correctly uninstall applications" (VERIFIED-D). X "full-uninstall prompt" (VERIFIED-KB via 13 §3.42). |
| **App updates available** | not found | unknown | — | X 4.11.4 / 4.14.0: more informative update notifications listing top outdated apps (VERIFIED-D) |
| **Malware found (real-time / background)** | governed by `MalwareScanMode` (§3.5) | on when the monitor is on | — | VERIFIED-KB (via 13 §3.17). Not in the App Store edition. |
| **Tips about unused features** | probably `ShowAssistantRecommendations` (or Menu › Recommendations) | — | — | X KB lists tips (VERIFIED-KB via 13 §3.42). 5.x Menu › Recommendations covers "feature suggestions" (VERIFIED-KB). |
| **Battery drain / Bluetooth device low battery** (laptops; BT devices on a mini) | not found | — | 5.x Menu shows devices **under 20 %** in red | X 4.12.4 / 4.13.6 / 4.14.0 (VERIFIED-D). 20 %: VERIFIED-KB (via 08 §2). |
| **Notification Center (5.6.0)** | — | — | — | In-app bell inbox for "product news, offers and messages" (VERIFIED-KB via 01 §5.2). **Not** an alert setting. Whether a "show offers" opt-out exists is a GAP. |

**CleanMyMac 3 threshold menus, recovered exactly** (VERIFIED-D, `CMMenuPreferencesViewController.strings`: https://raw.githubusercontent.com/auspham/mac-essential/7004fca7c50fc36d4b9ab42bc799fa3b1c84d416/CleanMyMac%203.app/Contents/Resources/en.lproj/CMMenuPreferencesViewController.strings)
- The file holds 17 size items.
- **2, 5, 10, 20, 50 and 100 GB occur twice**, so they belong to both popups.
- **500 MB, 1, 3, 15 and 30 GB occur once.**
- The two sentinels are "Don't Warn" (free-space label "Warn when…") and "Don't Notify" (Trash label "Notify when…").
- Likely split (INFERRED):
  - **Free space:** Don't Warn · 2 · 5 · 10 · 15 · 20 · 30 · 50 · 100 GB.
  - **Trash:** Don't Notify · 500 MB · 1 · 2 · 3 · 5 · 10 · 20 · 50 · 100 GB.
- Other strings in the same file: "Reset Health and Monitoring:" with "Reset All Warnings", and "Features are disabled because CleanMyMac is running from a disk image."

### 3.4 Menu

| Control | Label | Default | Key | Evidence |
|---|---|---|---|---|
| Menu on/off | **Enable Menu** | default-on (INFERRED-dotfile: both dotfile users turn it **off**) | `MenuAppEnabled` (bool, **main domain**, e.g. `com.macpaw.CleanMyMac-setapp`) | Label: VERIFIED-KB (via 01 §10). Key and domain: VERIFIED-OSS. jasonfungsing's exported 5.6.0 Setapp plist holds `MenuAppEnabled = false`: https://raw.githubusercontent.com/jasonfungsing/dotfiles/47ba7516495662b5d621815634edf546fa2e0f8c/app/setapp/prefs/com.macpaw.CleanMyMac-setapp.plist |
| Recommendations | **Recommendations** (feature suggestions + weekly cleanup reminders) | INFERRED on | INFERRED `ShowAssistantRecommendations` (main domain). Lineage: X 4.10.0 showed Assistant recommendations in the Menu "(manage in Preferences)". | Label: VERIFIED-KB (via 01 §10). Key mapping: INFERRED, medium. |
| Background-items dependency | If "Allow in the Background" is off in System Settings › General › Login Items & Extensions, the Menu won't open and the toggle does nothing | — | — | VERIFIED-KB (via 08 §1.7) |

Domains:
- `com.macpaw.CleanMyMac5.Menu` exists (VERIFIED-OSS, a `defaults domains` export: https://github.com/tracycsmith/refineo-laptop-config/blob/9dc3b79b9f32dc3fdb81d5e55d5cdee4674c7fdd/exports/macos-settings/defaults-domains.txt).
- The Setapp `.Menu` domain held only `STP_is_first_launch` and `STP_last_used_version` (VERIFIED-OSS, jasonfungsing `com.macpaw.CleanMyMac-setapp.Menu.plist`).
- So the Menu helper keeps **no user settings in its own domain**. It reads them from the App Group plist and the main domain (INFERRED).

### 3.5 Protection

| Control | Label (KB / REPLICA B) | Default | Key | Evidence |
|---|---|---|---|---|
| Real-time monitor | **Enable Malware Monitor** (KB: "recommended on") | INFERRED **on** for licensed direct/Setapp builds; not present in the App Store build | `MalwareScanMode` = `"protected"` (monitor on) / `"manual"` (off) — string, App Group plist | Label: VERIFIED-KB (via 13 §3.17). Key and values: VERIFIED-OSS (hollow: `Malware scan mode: "protected" (continuous) vs "manual"`). The mapping is INFERRED, high. |
| Background scanning | KB: background scanning on/off. B: "Monitor threat activity in the background". | INFERRED on (B: true) | not found | VERIFIED-KB (via 13 §3.17). Wording: REPLICA. |
| Scan mode | **Quick / Balanced / Deep**. B shows Speed / Depth / Purpose rows (Deep = Slowest / Thorough). | unknown. B shows Deep selected (weak; may be the clone's own state). Smart Care always runs Quick. | not found | VERIFIED-KB (via 13 §3.16; 02 §3.1). X origin: 4.14.0 (VERIFIED-D). |
| Extra locations | **disk images (DMG)** (also applies to Smart Care) · **email attachments** (needs FDA) · **archives** · **USB drives** · **iCloud files** | B: all checked (weak) | not found | VERIFIED-KB (via 13 §3.16). B words the iCloud option **"Exclude downloaded iCloud files"**: an *exclusion* in X. The 5.x polarity is a GAP. |
| Engine badge | "Powered by: Moonlock Engine" | — | — | REPLICA B. The engine itself: VERIFIED-KB. |

The Health Monitor runs the monitor, so it keeps working with the main app closed (VERIFIED-KB via 13 §3.17). `com.macpaw.CleanMyMac5.HealthMonitor` is a real defaults domain (VERIFIED-OSS, same `defaults domains` export). Its keys are unknown.

### 3.6 Ignore List

| Element | Vendor | Evidence |
|---|---|---|
| Sections | **Cleanup** (System Junk, Mail Attachments) · **Protection** (Malware Removal) · **Applications** (Uninstaller, Updater) · **My Clutter** (Duplicates, Similar Images, Downloads). Trash Bins and Privacy have **no** scope. | VERIFIED-KB (via 01 §10, 20-gap-02 §3) |
| Default entries | System apps pre-added under Uninstaller (they can be reset, not removed). X 4.12.4 added "Mac wallpaper settings cache" to the default ignored items. | VERIFIED-KB (via 13 §3.5); VERIFIED-D (X notes) |
| Adding | Control-click a result → **Add to Ignore List**. A one-time explainer ("won't be shown in scan results; manage in Preferences") has a "Do not show this message again" box. | VERIFIED-KB (X) and VERIFIED-D (CMM3) (via 13 §4.15) |
| Settings UI (CMM3, the only exact source) | Header "View and manage items that were earlier excluded from scan results". Footer "All changes take effect after a new scan." Controls: +, −, Reveal in Finder, Quick Look, Remove from List, and a reset menu with "Reset Selected Ignore List" and "Reset All Ignore Lists" (with a warning). Extra rule kinds: RAW-photo toggle, file extensions (Large & Old), volumes (Trashes), "Ignore system applications". | VERIFIED-D (via 13 §5.4) |
| 5.x add/remove UI | **GAP**. INFERRED to keep CMM3's +/− list per section. | — |
| Storage | **GAP**. INFERRED to be the App Group container or Application Support, not the defaults plist (none of the observed plists holds list data). | — |

### 3.7 FDA, helper and analytics status (no tab verified in 5.x)

- **FDA:**
  - 5.x asks the user to run a Smart Care scan first, so its components register with macOS; then grant access in System Settings › Privacy & Security › Full Disk Access. The Assistant shows **Allow Access**. The Health score counts "FDA granted". VERIFIED-KB (via 01 §9.1, 08 §8.2).
  - X's dedicated **Disk Access** tab (B) is not evidenced for 5.x.
- **Helper (Agent):**
  - The root helper is `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` with `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` (VERIFIED-OSS, IntuneBrew uninstall script: https://raw.githubusercontent.com/ugurkocde/IntuneBrew/HEAD/Uninstall%20Scripts/uninstall_cleanmymac.sh).
  - No Settings control for its status is documented (GAP).
- **Analytics:**
  - Observed flags: `CMIsUserEligibleForAppsStatistics` (bool) and `CMAUIdentifier` (VERIFIED-OSS, §4). The CLI has an analytics toggle in `cleanmymac config` (VERIFIED-D via 13 §6.3). CMM3 had "Share anonymous usage data" (VERIFIED-D via 13 §5.7).
  - A 5.x in-app opt-out is a GAP.

---

## 4. Preference domains and keys the 5.x processes read

### 4.1 Domain and file map

| Edition / process | Domain or file | Evidence |
|---|---|---|
| Direct main app | `com.macpaw.CleanMyMac5` → `~/Library/Preferences/com.macpaw.CleanMyMac5.plist` (≈4 KB on a fresh install) | VERIFIED-OSS: `defaults domains` export (tracycsmith); size seen in an uninstaller listing (https://github.com/earthinversion/Mac-apps-self-manage/blob/7b6087f0f82fc11aa1a04c42d9225d1300c77119/README.md); zap lists. |
| Direct Menu helper | `com.macpaw.CleanMyMac5.Menu` | VERIFIED-OSS (tracycsmith) |
| Direct Health Monitor | `com.macpaw.CleanMyMac5.HealthMonitor` | VERIFIED-OSS (tracycsmith) |
| Direct shared (App Group) | `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Preferences/S8EX82NJP6.com.macpaw.CleanMyMac5.plist` | The container is VERIFIED-OSS (cask zap, uninstall scripts). The plist file name is INFERRED by analogy with Setapp (next row). |
| Setapp main app | `com.macpaw.CleanMyMac-setapp` | VERIFIED-OSS (jasonfungsing export; hollow; hosmelq) |
| Setapp Menu helper | `com.macpaw.CleanMyMac-setapp.Menu` | VERIFIED-OSS (jasonfungsing export) |
| Setapp Health Monitor | `com.macpaw.CleanMyMac-setapp.HealthMonitor` (launchd label; the domain is INFERRED) | VERIFIED-OSS label (https://github.com/vscarpenter/MacHeadroom/blob/58a8e4c69fd169d5f209752a05276a7dac79bc5b/Evidence/phase-zero-unsandboxed-report.json) |
| Setapp shared (App Group) | `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac-setapp/Library/Preferences/S8EX82NJP6.com.macpaw.CleanMyMac-setapp.plist` | VERIFIED-OSS (hollow `defaults.sh`: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh) |
| App Store edition | `CleanMyMac_5_MAS.app`, sandboxed. Domain and container paths not observed (GAP). | VERIFIED-OSS that it is sandboxed (taylorarndt) |
| CLI (separate product) | Group container `S8EX82NJP6.com.macpaw.CleanMyMac5.CLI` | VERIFIED (cask, via 01) |
| Logs (not prefs) | `…/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Logs/CleanMyMac_5` (also `_Menu`, `_HealthMonitor`). Log tokens seen: `SpaceLensScanTask`, `CleaningCore:FileRemover`, `RemovalTask`, `trackCleanComplete`. | VERIFIED-OSS (https://github.com/nathanvale/dotfiles-private/blob/f6f5a666f57c4467a63d8cedc4be7df30bf87486/docs/agents/mac-storage.md; 10 §2) |

### 4.2 Key catalogue (5.x)

| Key | Type | Observed value(s) | Domain | Meaning | Who reads it (INFERRED) | Evidence |
|---|---|---|---|---|---|---|
| `MenuAppEnabled` | bool | `false` (users who disabled it) | main | Settings › Menu › Enable Menu | main app (registers/unregisters the Menu login item); Menu | VERIFIED-OSS (3 sources) |
| `ShowAssistantRecommendations` | bool | `true` / `false` | main | Recommendation cards (Assistant and/or Menu) | main app, Menu | VERIFIED-OSS (2 sources) |
| `SoundsEnabled` | bool | `false` | App Group | UI sound effects | main app (and Menu, if it plays sounds) | VERIFIED-OSS (hollow) |
| `CustomThemes` | bool | `false` | App Group | seasonal / national theme overlays | main app | VERIFIED-OSS (hollow) |
| `SmartCareReminderEnabled` | bool | `false` | App Group | Smart Care reminder notifications | HealthMonitor / Menu | VERIFIED-OSS (hollow) |
| `TrashSizeAlertsEnabled` | bool | `false` | App Group | Trash-size alerts | HealthMonitor / Menu | VERIFIED-OSS (hollow) |
| `MalwareScanMode` | string | `"protected"`, `"manual"` | App Group | real-time monitor on / off | HealthMonitor | VERIFIED-OSS (hollow) |
| `CMIsUserEligibleForAppsStatistics` | bool | `true` | main | analytics eligibility | main app | VERIFIED-OSS (jasonfungsing export; hollow ignore list) |
| `CMAUIdentifier` | unknown (probably string) | — | main | analytics / user identifier (INFERRED) | main app | VERIFIED-OSS name only (hollow ignore list: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/reconcile.sh) |
| `FRServiceLastKnownBootDate` | real (Unix seconds) | `1789941025.956` (= 2026-09-20 21:50 UTC) | main | last boot seen by a service named "FR…" (meaning unknown) | main app | VERIFIED-OSS (export) |
| `FRServiceLastKnownVersion` | string | `50600.0.2608201305` (Setapp 5.6.0 build) | main | last app build seen by the same service | main app | VERIFIED-OSS (export) |
| `KeychainAccessibilityMigration` | **string** | `"true"` | main | one-time keychain migration flag | main app | VERIFIED-OSS (export; hollow calls it a migration flag) |
| `DbHash`, `DbSize` | unknown | — | main | hash and size of a local database (INFERRED: rules/safety DB) | main app | VERIFIED-OSS names (hollow ignore list) |
| `LaunchCount`, `TotalCleansCount` | unknown (int) | — | main | usage counters (rating prompts, My Activity) | main app | VERIFIED-OSS names |
| `LastActiveBundle` | unknown | — | main | last frontmost bundle / instance state | main app | VERIFIED-OSS name |
| `STP_is_first_launch`, `STP_last_used_version` | bool, string | `false`, `"4.2.1"` | main and `.Menu` (Setapp only) | Setapp framework state (`4.2.1` is the framework version, not the app's) | Setapp framework | VERIFIED-OSS (export) |
| `SS_*` | — | — | Setapp-distributed apps | Setapp framework | — | VERIFIED-OSS (hollow ignore pattern) |
| `SUAutomaticallyUpdate`, `SUEnableAutomaticChecks` | bool | X: `true`, `true` | main (X) | Sparkle auto-update | main app / Updater | VERIFIED-OSS for **X**; INFERRED for 5.x direct |
| `SmartScanModuleDisabledTasks` | dict<string,bool> | X: `{CMMalwaresModuleScanIdentifierDetection: true}` | main (X) | excluded Smart Scan tasks | X main app | VERIFIED-OSS for **X** |
| `SeenIntroVideo`, `ShowReleaseNotes`, `SUHasLaunchedBefore` | bool | X: `true`, `false`, `true` | main (X) | onboarding / what's-new state | X main app | VERIFIED-OSS for **X** |

**Threshold keys (low free space, Trash size, memory, hung apps):** none found in any public source. **GAP.** Also not found: the scan-depth key, background-scan key, extra-location keys, reminder-frequency key and ignore-list storage. The fastest way to close these is the toggle-diff in §7.

**CleanMyMac Business / Jamf profile keys:** none published or found. Searches covered GitHub (ProfileManifests `pfm_domain com.macpaw` has only The Unarchiver), public `.mobileconfig` files and "CleanMyMac Business" code mentions. Jamf Marketplace and the Business KB were unreachable. **GAP.** Business sunset 2026-07-14 (via 01).

---

## 5. Implementation notes for our Settings (INFERRED)

### 5.1 Process model and storage

- **Single source of truth.** Use one `SettingsSchema` Swift file listing every key, type, default, minimum OS and owner process. Every process calls `UserDefaults(suiteName:)!.register(defaults:)` from it at launch.
- **Shared suite without App Group entitlements.** Our app is non-sandboxed (FDA, helper), so a plain suite domain such as `com.<us>.<app>.shared` (→ `~/Library/Preferences/com.<us>.<app>.shared.plist`) is readable by the main app, the Monitor agent and the CLI.
  - That avoids App Group entitlements, which an ad-hoc personal build cannot sign properly. It also avoids macOS 15's group-container access prompts for mismatched signing (INFERRED; verify on the mini).
  - If we later sign with a Team ID, switch to `<TEAMID>.<bundle>.shared` in `~/Library/Group Containers/` (MacPaw's pattern, §4.1). Migrate keys once, guarded by `settings.schemaVersion`.
- **Split like the vendor.**
  - UI-only preferences (window state, last tab) go in `UserDefaults.standard`.
  - Anything the agent needs goes in the shared suite: alert toggles and thresholds, reminder schedule, monitor mode, sounds (the agent plays alert sounds), ignore rules version.
- **Change propagation.** cfprefsd keeps reads coherent across processes. To react quickly, post a Darwin notification (`notify_post("com.<us>.<app>.settings-changed")`) after each write, and have the agent re-read on receipt. Do not rely on `UserDefaults.didChangeNotification`, which only covers the current process.
- **Lists live outside defaults.** Ignore rules, trusted items and the reminder log go in a small SQLite or JSON file under `~/Library/Application Support/<App>/`. That matches the vendor, which keeps no list data in plists.
- **Managed preferences (optional).** Honour `/Library/Managed Preferences/<bundle id>.plist` with `UserDefaults.standard.objectIsForced(forKey:)` and show "Managed by a profile" under any locked control. Ship a JSON schema (for Jamf "Application & Custom Settings") with the same key names as §5.3. The vendor published none, so ours is original.

### 5.2 SwiftUI shell

- Use a `Settings { SettingsRoot() }` scene. Inside it, a `TabView(selection:)` with `.tabItem { Label(…, systemImage:) }` gives the standard macOS toolbar-tab Settings window, with a per-tab height animation. Use a fixed width of ~620 pt and `Form { … }.formStyle(.grouped)`.
- **Deep links to a tab.** Persist `settings.selectedTab`, set it, then call `@Environment(\.openSettings)` (macOS 14+) or use `SettingsLink`. URL form: `ourapp://settings/<tab>`.
- The window follows the system appearance (09 §B). On macOS 26 it gets Liquid Glass toolbar chrome automatically with the 26 SDK.

### 5.3 Our tabs, controls and defaults

Tabs: **General · Checkup · Notifications · Monitor · Shield · Ignored Items · Permissions**. That is six tabs mirroring the probable 5.x set, plus Permissions, which replaces X's Disk Access tab and the helper status. Keys use our own names.

**General**

| Control | Default | Key (ours) |
|---|---|---|
| Play sounds | on | `ui.sounds` (shared suite: alert sounds too) |
| Seasonal effects | **off** (09 §4.8) | `ui.seasonal` |
| Removal method: Move to Trash / Delete immediately | Move to Trash | `cleanup.removalMethod` |
| Confirm before removing | on | `cleanup.confirm` |
| Show icon in Dock | on (app); the Monitor is separate | `ui.dockIcon` |
| Updates: check automatically | on if we ship Sparkle, else hidden | `SUEnableAutomaticChecks` (Sparkle's own key) |
| Usage data | **none collected**. Show a static line, no toggle. | — |
| Reset all warnings (re-enable every "don't show again") | button | clears `warnings.suppressed.*` |
| Reset all settings… | button with confirmation | removes the suite and re-registers defaults |

**Checkup** (the "Customize Smart Care" equivalent)
- Tri-state tree: Cleanup (System Junk groups · Mail Attachments · Trash Bins) · Shield (Threat Scan, always Fast) · Performance (maintenance tasks) · Applications (updates) · Clutter (Downloads duplicates).
- Store **excluded node IDs**: `checkup.excluded = [String]` (shared suite).
- Defaults: everything included **except** System Junk › Language Files (code-signature risk, 01 §12) and iOS Device Backups (not unattended-safe, 13 §3.45).
- Footer: "Excluded areas still appear in Checkup, dimmed. You can still scan them from their own screen."

**Notifications** (keys `alerts.<id>.enabled` and `alerts.<id>.threshold`, matching 08 §7.2; triggers and throttles follow 08 §6.2)

| Row | Default | Threshold options (popup) |
|---|---|---|
| Checkup reminder | on, **Weekly** | Off · Every 3 days · Weekly · Every 2 weeks · Monthly (02 §6.2). Plus "When I click the reminder: Just open / Open and start Checkup". |
| Low free space (startup disk) | on, **Automatic** = min(50 GB, max(10 GB, 5 %)) (08 §14.3) | Automatic · 5 · 10 · 15 · 20 · 30 · 50 · 100 GB · Don't warn (the CMM3 set, §3.3) |
| Trash is large | on, **5 GB** | Don't notify · 500 MB · 1 · 2 · 3 · 5 · 10 · 20 · 50 · 100 GB |
| Heavy memory use | on | — (rule in 08 §6.2) |
| App not responding | on | — (≥ 5 s) |
| App moved to Trash → offer to remove leftovers | on | — |
| App updates available | on (daily check) | — |
| Threat found | on (cannot be turned off while Guard is on; explain why) | — |
| Bluetooth device battery low | on | 10 · 15 · **20** · 30 % |
| External drive connected with junk | off | — |
| Tips about features | off | — |
| Allow notification sounds | follows `ui.sounds` | — |
| Notification permission status + "Open Notification Settings" | — | — |
| Reset ignored alerts | button | — |

**Monitor** (the Menu equivalent)
- Enable Monitor: on. Key `monitor.enabled`. Toggling it calls `SMAppService.agent(plistName:)`.register/unregister. Show the status: Enabled / Needs approval → "Open Login Items" via `SMAppService.openSystemSettingsLoginItems()`.
- Show recommendations in Monitor: on. Key `monitor.recommendations`.
- Menu-bar label, card order and units: per 08 §7.2.

**Shield** (Protection)
- Real-time Guard: on. Key `shield.mode = "guard" | "manual"`, mirroring the vendor's string-enum design (§4.2).
- Background scan: on, weekly. Keys `shield.background.enabled`, `shield.background.interval`.
- Scan mode Fast / Standard / Thorough: **Standard**. Key `shield.depth`. Each mode shows Speed / Depth / Purpose rows (04 §14).
- Extra locations (04 §14):
  - disk images: on (also used by Checkup);
  - archives: on;
  - mail attachments: on, disabled with a note when FDA is missing;
  - external drives: on;
  - include downloaded iCloud files: **off**. Positive wording, the opposite of X's "Exclude…" phrasing (§3.5).
- Rules version and last update, with "Check now". Quarantine retention 30 days.

**Ignored Items**
- Sidebar sections: Cleanup (System Junk, Mail Attachments) · Shield (Threats) · Applications (Uninstaller, Updater) · Clutter (Duplicates, Similar Photos, Downloads). The same scopes as the vendor (§3.6).
- Controls: +, −, Reveal in Finder, Quick Look, Remove, and a reset menu (Reset this list / Reset all lists, both with confirmation). Also "Hide system apps in Uninstaller", default on.
- Rule kinds: path prefix, exact file, bundle ID, extension, volume UUID.
- Footer: "Changes apply to the next scan."

**Permissions**
- **Full Disk Access:** status from the four-file probe (10 / 01 §9.1), re-checked on `didBecomeActive`. "Open Privacy Settings" deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
- **Helper:** `SMAppService.daemon(plistName:).status`, one of `.enabled` / `.requiresApproval` / `.notRegistered` / `.notFound`. Show the version and offer Install, Reinstall and Remove.
- **Monitor agent:** status as above.
- **Notifications:** `UNUserNotificationCenter.notificationSettings()`.
- **Accessibility:** only if Screen Cleaning is built (20-gap-04 §8).

---

## 6. Behaviour notes worth copying (INFERRED from vendor evidence)

1. **Alert toggles live with the agent, not the UI.** MacPaw put alert and monitor switches in the App Group plist, where HealthMonitor and Menu can read them, and kept window and launch counters in the main domain (§4.2). We follow the same split (§5.1).
2. **Monitor mode is an enum, not a bool** (`protected` / `manual`). That leaves room for a third mode later, such as "notify only" vs "auto-quarantine", without a migration.
3. **Store exclusions, not inclusions.** X's `SmartScanModuleDisabledTasks` keeps working when a release adds a new task: the task is included by default.
4. **Disabling the Menu disables its alerts.** CMM3 warned that turning the Menu off loses most notifications, while Scheduler reminders still fire (VERIFIED-D via 08 §2). Ours: alerts belong to the Monitor agent. When the user turns off "Enable Monitor", show a note: "Alerts and reminders also stop." Offer "Keep alerts, hide menu-bar icon" as a separate choice; it is cheap to support.
5. **Reset All Warnings** has existed since CMM3 (VERIFIED-D). Keep it, under our wording "Reset ignored alerts" or "Reset warnings".

---

## 7. How to close the remaining gaps on a real Mac (toggle-diff procedure)

Run this on a Mac with the CleanMyMac 5.7.1 trial. Read-only except for toggling Settings in the vendor UI.

```sh
APP_DOM=com.macpaw.CleanMyMac5
GRP="$HOME/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Preferences"
snap() {  # $1 = label; writes one XML plist per domain into ~/cmm-diff/<label>/
  out=~/cmm-diff/"$1"; mkdir -p "$out"
  for d in $APP_DOM $APP_DOM.Menu $APP_DOM.HealthMonitor; do
    defaults export "$d" "$out/$d.plist" 2>/dev/null && plutil -convert xml1 "$out/$d.plist"
  done
  for f in "$GRP"/*.plist; do cp "$f" "$out/group-$(basename "$f")"; plutil -convert xml1 "$out/group-$(basename "$f")"; done
}
snap 00-baseline
# Toggle ONE control in Settings, wait 2 s, then:
snap 01-after-trash-alert
diff -ru ~/cmm-diff/00-baseline ~/cmm-diff/01-after-trash-alert
```

- Repeat for each control: every Notifications row and threshold popup, each Protection extra-location box, the scan mode, background scanning, and a Scanning tree node.
- To catch writes to non-plist stores (ignore list), run `sudo fs_usage -w -f filesys | grep -i macpaw` while adding an ignore entry.
- Screenshot every tab, in both light and dark system appearance, at 5.7.1. Record the window title, tab order and size.
- Capture the full label text of each control as a short-label inventory (do not reuse it verbatim in our UI).
- For each GAP, record the result in this file's §8 and update 01 §10.

---

## 8. Remaining gaps

| # | Gap | Status |
|---|---|---|
| 1 | 5.x tab list verified by screenshot (Notifications present? exact order?) | INFERRED-strong. §7 closes it. |
| 2 | Full 5.x General contents (labels for sounds and themes; analytics; anything else) | Keys known (§4). Labels: GAP. |
| 3 | Notifications thresholds and their keys, reminder frequency options | Only `TrashSizeAlertsEnabled` and `SmartCareReminderEnabled` are known. Thresholds: GAP. |
| 4 | Scan-depth, background-scan and extra-location keys and defaults | GAP (the monitor key is known) |
| 5 | Polarity of the iCloud option in 5.x ("Exclude…" vs "Scan…") | GAP |
| 6 | Ignore List add/remove UI in 5.x, and its storage | GAP (CMM3 UI known) |
| 7 | Whether 5.x has any Disk Access / Analytics / helper-status UI in Settings | GAP (probably not) |
| 8 | Meaning of `FRService*` and `CMAUIdentifier` | GAP |
| 9 | Direct-edition App Group plist file name (by analogy only) | INFERRED |
| 10 | CleanMyMac Business / Jamf configuration-profile keys | GAP. Not published; product sunset. |
| 11 | Whether the 5.6.0 Notification Center has an "offers" opt-out | GAP |

---

## 9. Sources (read this pass unless marked "via NN")

**GitHub (VERIFIED-OSS):**
- hollow/dotfiles `macos/defaults.sh`: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh
- hollow/dotfiles `macos/reconcile.sh` (CleanMyMac noise keys): https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/reconcile.sh
- jasonfungsing/dotfiles exported Setapp 5.6.0 plists:
  - https://raw.githubusercontent.com/jasonfungsing/dotfiles/47ba7516495662b5d621815634edf546fa2e0f8c/app/setapp/prefs/com.macpaw.CleanMyMac-setapp.plist
  - https://raw.githubusercontent.com/jasonfungsing/dotfiles/47ba7516495662b5d621815634edf546fa2e0f8c/app/setapp/prefs/com.macpaw.CleanMyMac-setapp.Menu.plist
  - export script: https://raw.githubusercontent.com/jasonfungsing/dotfiles/47ba7516495662b5d621815634edf546fa2e0f8c/app/setapp/export-prefs.sh
- hosmelq/.config `app-settings.json`: https://raw.githubusercontent.com/hosmelq/.config/bf50517e14c3195df3f9bf86e31c55c417474319/dotfiles/macos/app-settings.json
- aboqasem/dotfiles, X plist: https://raw.githubusercontent.com/aboqasem/dotfiles/main/synced/defaults/com.macpaw.CleanMyMac4.plist
- tracycsmith `defaults-domains.txt`: https://github.com/tracycsmith/refineo-laptop-config/blob/9dc3b79b9f32dc3fdb81d5e55d5cdee4674c7fdd/exports/macos-settings/defaults-domains.txt
- Homebrew cask `cleanmymac` (5.7.1): https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/c/cleanmymac.rb
- IntuneBrew uninstall script: https://raw.githubusercontent.com/ugurkocde/IntuneBrew/HEAD/Uninstall%20Scripts/uninstall_cleanmymac.sh
- earthinversion uninstaller listing: https://github.com/earthinversion/Mac-apps-self-manage/blob/7b6087f0f82fc11aa1a04c42d9225d1300c77119/README.md
- nathanvale log-path note: https://github.com/nathanvale/dotfiles-private/blob/f6f5a666f57c4467a63d8cedc4be7df30bf87486/docs/agents/mac-storage.md
- taylorarndt hands-on skill: https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md
- MacHeadroom process report (Setapp HealthMonitor label): https://github.com/vscarpenter/MacHeadroom/blob/58a8e4c69fd169d5f209752a05276a7dac79bc5b/Evidence/phase-zero-unsandboxed-report.json

**MacPaw first-party (VERIFIED-D):**
- 5.x appcast (ends at 5.3.1): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml
- 5.0–5.3.1 cumulative notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
- X cumulative notes (to 4.15.14): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41514.0.2512021236/releasenotes.html
- CMM3 `CMMenuPreferencesViewController.strings` (bundle mirror): https://raw.githubusercontent.com/auspham/mac-essential/7004fca7c50fc36d4b9ab42bc799fa3b1c84d416/CleanMyMac%203.app/Contents/Resources/en.lproj/CMMenuPreferencesViewController.strings

**Replicas (weak):**
- ddlmanus/MacOptimizer: https://raw.githubusercontent.com/ddlmanus/MacOptimizer/5fdfcc04cf6ad09752174a64dff3fc960bc66445/AppUninstaller/MalwareRemovalReplicaView.swift
- VaderCleaner:
  - https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/07a21ea959e9575e25bab02600c7cb4b47446022/VaderCleaner/PreferencesView.swift
  - …/SettingsScanningTab.swift
  - …/SettingsNotificationsTab.swift

**MacPaw KB (VERIFIED-KB via 01/02/04/08/13; not re-fetchable this pass):** `general`, `smart-care`, `cleanmymac-safety`, `protection-scan-options`, `real-time-monitoring-on-off`, `background-scanning-on-off`, `protection-monitoring`, `cleanmymac-menu-on-off`, `cleanmymac-menu-recommendations`, `full-disk-access`, `allow-background-items`, `languages`, `devices-monitoring`. X: `how-often-run-cleanup-scans`, `cleanmymac-x-menu`, `cleanmymac-assistant`, `system-junk`. CMM3: `notifications`. Business: `smart-scan-automation`.
