# 04 — Protection: Malware Removal, Real-Time Monitoring, Privacy and App Permissions

> **Track:** Protection. This covers MacPaw's malware engine (Moonlock), real-time and background monitoring, the Privacy cleaner and App Permissions. It also gives a design for an original, open implementation.
> **Target:** our own app (not called CleanMyMac) for an Apple Silicon Mac mini on macOS 14 Sonoma, 15 Sequoia, 26 Tahoe and, where noted, macOS 27 ("Golden Gate", released Sept 2026). (corrected/clarified) The name "Golden Gate" = macOS 27 is VERIFIED (fetched) in Homebrew's version table (`golden_gate: "27"`, https://raw.githubusercontent.com/Homebrew/brew/main/Library/Homebrew/macos_version.rb). The September 2026 release date comes from 01-overview and was not re-checked here.
> **Date:** 2026-10-12. **Current product version:** CleanMyMac **5.7.1**, build `50701.0.2609301754` (built 2026-09-30). VERIFIED (fetched): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb

## 0. How to read this report (method, labels, limits)

- **VERIFIED** means the claim is backed by the URL cited inline. Two kinds of verification are used:
  - *"(search excerpt)"*: the agent proxy blocks direct fetches of macpaw.com, moonlock.com, Apple Support, Macworld, eclecticlight.co and most news sites from this sandbox. The text was therefore read from web-search excerpts of those pages.
  - *"(fetched)"*: the source itself was retrieved and read. This applies to github.com, raw.githubusercontent.com and developer.apple.com.
- **VERIFIED-OSS** (added in the fact-check pass) means the fact was read in shipping open-source code or a public repo on GitHub (fetched). It shows how macOS behaves, not how MacPaw implements anything.
- **REPLICA (weak)** (added) means the labels come from a third-party "CleanMyMac reconstruction" on GitHub (`ddlmanus/MacOptimizer`), whose author evidently transcribed the real UI. Treat these as plausible on-screen strings, not as confirmed MacPaw copy.
- **INFERRED** means our reasoning, platform knowledge or recommendation for our build. Treat it as a design decision to validate on a real Mac, not as a fact about MacPaw's product.
- The web-search budget ran out partway through. Some 5.x details could not be confirmed and are listed under §15 Gaps, notably exact on-screen strings and per-release Protection changes in 5.1–5.7.
- (added) **Fact-check pass limits.** The adversarial fact-check had **zero web-search budget**: the shared per-turn limit was already used up. WebFetch could not resolve macpaw.com, moonlock.com, setapp.com, apps.apple.com or macworld.com. It therefore relied on:
  - GitHub (code search and raw files), including the Homebrew cask, Objective-See, Tencent Lemon, SigmaHQ, CVEProject and macOS SDK headers;
  - developer.apple.com documentation JSON;
  - MacPaw's DevMate release-notes bucket on S3, where one cumulative file (5.0.0–5.2.5) was readable.
- Everything is paraphrased. No MacPaw copy, illustrations or names are to be reused (see §14 for our own naming).
- Related team reports: `01-overview.md` (IA, editions, settings) and `02-smart-care.md` (one-click scan). Where this report relies on facts they verified, it says so. (added) `10-internals.md` (process architecture), `11-oss-api.md` (KnockKnock and Lemon taxonomy) and `13-helpcenter.md` (KB digest and CMM3 strings) are also used.

---

## 1. TL;DR: the facts that matter for implementation

1. **Protection is one sidebar module in CleanMyMac 5.x with three sub-areas.** They are **Malware Removal** (threats), **Privacy** (browser and system traces) and **App Permissions** (TCC grants). In CleanMyMac X, "Malware Removal" and "Privacy" were separate sidebar items under a "Protection" heading. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal, https://macpaw.com/support/cleanmymac-x/knowledgebase/malware-removal and https://macpaw.com/support/cleanmymac/knowledgebase/app-permissions (search excerpts). The team's 01-overview.md lists the same structure. (added) REPLICA (weak): an X-era Privacy reconstruction puts "Application Permissions" *inside* the X Privacy list, next to Recent Items, Chrome, Safari, Firefox, Wi-Fi Networks and Chat Data. So X also had a permissions view, just not as a separate area. Source: https://raw.githubusercontent.com/ddlmanus/MacOptimizer/HEAD/AppUninstaller/PrivacyReplicaView.swift (fetched).
2. **The engine is MacPaw's in-house Moonlock Engine.** The name dates from CleanMyMac X 4.14 (July 2023). It powers three things: on-demand **malware removal**, the **real-time malware monitor** and **background scanning**. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/moonlock-engine (search excerpt). (added) Independent corroboration: a MacPaw-sponsored newsletter slot dated 19 July 2023 introduced the new Moonlock Engine for CleanMyMac's Malware Removal. It claimed **2× faster** scans and **new coverage of external drives, mail attachments and browser extensions**. VERIFIED (fetched, archived newsletter): https://raw.githubusercontent.com/GaloisField2718/tldr_news/HEAD/TLDR/article_19-07-2023.md
3. **Three scan depths: Quick, Balanced, Deep.** There are also opt-in "extra locations": disk images (DMG), email attachments (needs Full Disk Access) and archives. Per 01-overview, USB drives and iCloud files are also options. MacPaw recommends a **Deep scan at least monthly**, even with monitoring on. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/malware-removal and https://macpaw.com/support/cleanmymac-business/knowledgebase/malware-scan (search excerpts).
   - (corrected) The claim that older X builds called the thorough mode **"Maximize suspicion"** is now **INFERRED (unconfirmed)**. Only the original researcher saw it, in a search excerpt. 13-helpcenter repeats it from this report, so it is not independent. No other source could be found.
   - (added) REPLICA (weak): the 5.x settings rows read "Scan DMG disk images", "Scan email attachments", "Scan archives" and "Scan USB drives". The iCloud option is worded as an **exclusion**: "Exclude downloaded iCloud files". Each mode shows three descriptor rows, **Speed / Depth / Purpose**; for Deep they read Slowest / Thorough / "inspect the entire system…". Source: https://raw.githubusercontent.com/ddlmanus/MacOptimizer/HEAD/AppUninstaller/MalwareRemovalReplicaView.swift (fetched).
4. **Results UX.** Threats are **all pre-selected**. You choose **Remove** to delete without review or **Review** to inspect first. Smart Care runs a **Quick** scan and auto-selects threats (VERIFIED in 02-smart-care.md).
5. **Real-time monitoring is notify-only and triggered by installs.** The Malware Monitor "subscribes to macOS notifications about new program installations". It checks newly added or modified items and posts a system notification when it finds malware or a PUA. The **Health Monitor** background agent drives it, so it works even when the main app is closed. Separately, a **periodic background scan** sweeps the whole system. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/potentially-unwanted-applications, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes and https://macpaw.com/support/cleanmymac/knowledgebase/protection-monitoring (search excerpts).
6. **(corrected) Whether CleanMyMac 5 uses an Endpoint Security (ES) system extension is unresolved. The evidence conflicts.**
   - **What the Homebrew cask actually says** (VERIFIED, fetched): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb
     - The `uninstall` stanza boots out the `com.macpaw.CleanMyMac5.HealthMonitor` and `.Menu` launchd labels and quits the app and both helpers.
     - It also removes the login item "CleanMyMac 5 Menu" and deletes `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`.
     - The Agent's **LaunchDaemon plist** and the **`Updater` LaunchAgent plist** appear **only in `zap`**, not in `uninstall`. The earlier text put all four in the uninstall stanza.
     - The cask has no system-extension entry. A cask may simply omit one, so this is not proof that none exists.
   - **Evidence for a sysext:** a third-party process capture shows the following running **as root** (79% CPU) on a Mac where `/Applications/CleanMyMac_5.app` was also running: `/Library/SystemExtensions/591E23C7-…/com.macpaw.moonlock.engine.systemextension/Contents/MacOS/com.macpaw.moonlock.engine`. VERIFIED-OSS (fetched): https://github.com/TaliskerMan/Monitro/blob/HEAD/backend/out.txt. 10-internals and 13-helpcenter cite this capture to say CMM5 ships the sysext.
   - **Evidence against:** a full 853-process capture dated 2026-09-20 shows CleanMyMac 5's Menu, HealthMonitor and FinderSync extension running, plus root daemons such as `endpointsecurityd` and two third-party privileged helpers. It shows **no Moonlock system extension**. VERIFIED-OSS (fetched): https://raw.githubusercontent.com/OpenAgentsInc/openagents/main/docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-after.txt
   - **INFERRED resolution:** the `com.macpaw.moonlock.engine` sysext most likely belongs to MacPaw's **standalone Moonlock app**, or CMM5 installs it only in some configurations. Our build must not assume ES either way (see §8). Monitoring in CMM5 is at least partly user-space, through the Health Monitor, which fits "notifies you" rather than "blocks".
7. **Quarantine and Trusted Items are documented for Moonlock**, and removals are logged in a **Detection History**. Moonlock moves a detection into Quarantine. You then delete it permanently or add it to **Trusted Items**. One MacPaw comparison table marks quarantine as Moonlock-only and not part of CleanMyMac. Separately, CleanMyMac's **Ignore List** has a "Protection › Malware Removal" scope. VERIFIED (search excerpts, original researcher; moonlock.com could not be re-checked in the fact-check pass). The Ignore List scope is independently VERIFIED in 01-overview and 13-helpcenter (cleanmymac-safety KB). (added) **Best reading:** CleanMyMac's Malware Removal **removes (deletes)** selected threats; quarantine is a Moonlock-app feature. CMM3-era strings tell the user to **restart** after removing malware (VERIFIED via 13-helpcenter §4.x, CMM3 strings). **Our build quarantines first** (§9). That is our design choice, not a copy of either product.
8. **(added) Privacy cleans per-browser traces plus system lists.**
   - Browser traces: history, cookies, downloads list, autofill, search queries and last-session tabs.
   - System lists: **Recent Items** (apps, documents, servers) and **Wi-Fi networks**.
   - The browser must be **quit** first.
   - The Mac App Store edition restricts **Safari items, Wi-Fi network cleanup and App Permissions management**.
   - VERIFIED via 01-overview and 13-helpcenter (privacy and missing-features KB).
   - CMM3 also offered Saved Passwords, HTML5 Local Storage, messenger histories and a **time-range filter** (VERIFIED, fetched CMM3 resources; see §11).
9. **(added) App Permissions is a TCC *review* surface.** It groups apps by permission (camera, microphone, files and folders, Full Disk Access and others) and shows recommended reviews as tiles (VERIFIED via 01 and 13). On modern macOS the only supported writes are `tccutil reset <Service> [bundle-id]` or sending the user to System Settings. INFERRED for our build: read-only listing, per-app reset and deep links (§12).
10. **(added) This is not a replacement for XProtect.** Apple's XProtect, XProtect Remediator and Gatekeeper keep running regardless. Our app should show their status (`xprotect version` on macOS 15+) and never interfere with them (§10).

---

## 2. Version history of the protection features (added)

| Version / date | Protection-relevant change | Status |
|---|---|---|
| CleanMyMac 3 (2015–2018) | **No malware module.** A **Privacy** module covered Safari, Chrome, Opera and Firefox (Autofill Values, Browsing History, Cookies, Downloads History, HTML5 Local Storage, Saved Passwords, Tabs from Last Session), messengers (Skype, Messages, AOL IM, Jabber, Yahoo, iMessage) and Recent Items. It had a time-range filter. | VERIFIED via 13-helpcenter §4.10 (CMM3 Help topic-90, fetched from `auspham/mac-essential`) |
| X 4.0 (Sept 2018) | **Malware Removal** introduced. | VERIFIED via 01-overview |
| X 4.14 (July 2023) | Security component renamed to **Moonlock Engine**: about 2× faster, adds external drives, mail attachments and browser extensions. | VERIFIED (01; TLDR sponsor slot, fetched) |
| X 4.15.0 (2024) | Configurable protection scan settings; Moonlock Engine 1.2.0. 4.15.4 (2024-06-20): Moonlock 1.3.0. | VERIFIED via 01-overview |
| 5.0.0 (2024-10-16) | New app. **Protection** module = Malware Removal + Privacy + **App Permissions** (grouped). | VERIFIED via 01-overview |
| 5.0.1 → 5.2.5 (Oct 2024 – Sept 2025) | **No Protection-specific changes** in the cumulative release notes. Entries are "minor issues and known crashes", Free Up Purgeable Space (5.0.5), VoiceOver and Reduce Motion (5.0.7), Space Lens (5.1.0) and Cloud Cleanup (5.2.1). | VERIFIED (fetched): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html |
| July 2025 | **Basic vs Plus** plans. Protection (malware and privacy) is in **Plus**. | VERIFIED via 01-overview |
| 5.4.0 (Feb–Mar 2026) | **My Activity** dashboard counts malware scans, threats found and items scanned. | VERIFIED via 01-overview |
| 5.2.6–5.7.1 (Oct 2025 – Oct 2026) | No Protection-specific change appears in 01-overview's What's New table: Smart Insights, Dropbox, My Tools, background Applications scan, Notification Center, Email Cleanup. DevMate notes after 5.2.5 return 403. | INFERRED (absence of evidence) |
| Standalone **Moonlock** app (separate MacPaw product) | Its own app (DMG at `dl.devmate.com/com.macpaw.moonlock/Moonlock.dmg`) with Quarantine, Trusted Items and Detection History. | DMG URL VERIFIED-OSS: https://github.com/opengood-ai/env-setup/blob/HEAD/packages/moonlock.sh ; features per §1.7 |

---

## 3. The Moonlock engine: what is public and what is not (added)

**Public (VERIFIED):**
- Built by MacPaw's cybersecurity division ("Moonlock"). It powers on-demand scans, the real-time monitor and background scans (§1.2).
- The malware database updates about **every 7–10 days**, per X KB how-often-run-cleanup-scans (VERIFIED via 02-smart-care and 13-helpcenter).
- It uses its own API/CDN host, `cdn-public-apis.moonlock.com`, separate from MacPaw analytics (VERIFIED via 10-internals, host-block rulesets).
- On 5.x the Moonlock component holds a `kTCCServiceBluetoothAlways` grant (VERIFIED via 10-internals; purpose unknown).
- **Moonlock Lab** publishes threat research on macOS infostealers and backdoors. Post slugs include `amos-backdoor-persistent-access`, `atomic-macos-stealer`, `macc-stealer-macsync-backdoor`, `new-mac-stealer-notnullosx`, `xcsset-malware-mac-app-development` and `realtek-macos-malware`. VERIFIED (URL list, fetched): https://raw.githubusercontent.com/stuartjash/macos-malware-kb/HEAD/data/sources-seen.txt. A SigmaHQ rule built from the AMOS-backdoor post is quoted in §6.

**Not public:**
- Whether detection uses YARA, hashes, machine learning or behaviour. INFERRED: almost certainly a hybrid, with hash and signature matching for known samples, rule or heuristic matching for families and PUAs, and code-signing and notarization checks. The "Quick/Balanced/Deep" split reads as *how much of the file system* is walked and *how aggressive* heuristics are, not as different engines.
- Where the database lives on disk. INFERRED candidates: `~/Library/Application Support/CleanMyMac_5/…` or the app group `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/` (both appear in the cask `zap`). The file format is unknown.
- How the "Speed/Depth/Purpose" levels map to concrete paths. Our mapping is in §6.

---

## 4. Threat taxonomy: what to detect (added)

MacPaw's documented classes are viruses, adware, spyware, keyloggers, worms, Trojans, ransomware and **potentially unwanted applications (PUAs)** (VERIFIED via 01 and 13). For our signatures and heuristics we organise detections by **family behaviour**. The family list below comes from a public macOS malware index. It is VERIFIED (fetched) as a secondary source: https://raw.githubusercontent.com/stuartjash/macos-malware-kb/HEAD/SKILL.md. "XProtect coverage" follows that index.

| Our category | Representative families (2016–2026) | Typical artifacts our scanner should look for | XProtect coverage (per index) |
|---|---|---|---|
| **Adware / browser hijackers** | Adload, Pirrit, Bundlore, Genieo, MaxOfferDeal, SurfBuyer, Trovi, ChromeLoader, OSX.Shlayer/ZShlayer (droppers) | LaunchAgents with random reverse-DNS labels; Safari or Chrome extensions; **configuration profiles** forcing homepage, search engine or extension; Chrome policies; `/Users/Shared/` and `~/Library/Application Support/<random>` | Adload, Pirrit, Shlayer: YARA. Bundlore, Genieo: XPR. ChromeLoader: none |
| **PUAs / scareware "cleaners"** | Advanced Mac Cleaner, MacMechanic, SearchProtect, SafeFinder (MacPaw has how-to pages on several) | App bundles by known team IDs; login items; fake alerts | Mostly none, so this is our value-add |
| **Infostealers** | **Atomic/AMOS** (and the SHAMOS variant), Poseidon, Banshee, Cuckoo, MacSync (Mac.c), Odyssey, NotNullOSX | Ad-hoc-signed or unsigned Mach-O from a DMG; `osascript` password-phishing dialogs; staging ZIPs in `/tmp`; **AMOS backdoor:** hidden `~/.helper` (fetched by `curl`), `~/.agent` and LaunchDaemon `/Library/LaunchDaemons/com.finder.helper.plist` | AMOS, Banshee, Poseidon: YARA (XPScripts.yr for osascript variants). Cuckoo: none |
| **Backdoors / RATs** | XCSSET (infects Xcode projects), AMOS backdoor, DPRK implants | Persistence plists pointing to hidden home dot-files; modified Xcode project build phases; injected `DYLD_INSERT_LIBRARIES` | XCSSET: XPR (DubRobber) |
| **Cryptominers** | OSAMiner, LoudMiner, CoinMiner, CpuMeaner, PPMiner | Bundled XMRig-like binaries; LaunchAgents with high-CPU helpers; cracked-app bundles | Mostly none |
| **Ransomware** | KeRanger, EvilQuest, LockBit (macOS), Turtle, NotLockBit | Unsigned binaries in user space; mass-rename behaviour (real-time only) | Partial |

- VERIFIED (fetched) for AMOS persistence. A Sigma rule (Gen Digital, 2025-11-22, citing Moonlock's AMOS-backdoor post) flags two things: `curl` writing a file ending in `.helper` under `/Users/`, and creation of `/Library/LaunchDaemons/com.finder.helper.plist`. Source: https://raw.githubusercontent.com/SigmaHQ/sigma/master/rules-emerging-threats/2025/Malware/Atomic-MacOS-Stealer/file_event_macos_malware_amos_persistence.yml
- VERIFIED (fetched): the AMOS family entry lists Keychain, browser-credential and wallet theft, a spoofed AppleScript password dialog and ZIP exfiltration. A 2026 ClickFix build persisted as `/Library/LaunchDaemons/com.xdivcmp.plist`. Source: https://raw.githubusercontent.com/stuartjash/macos-malware-kb/HEAD/families/infostealer/atomic-stealer.md
- INFERRED: specific labels like `com.finder.helper` rotate quickly. Our heuristics must be **behavioural**: for example, a launchd plist whose `ProgramArguments` runs `/bin/bash` or `osascript` on a hidden file in `$HOME`, or a plist with `RunAtLoad` + `KeepAlive` pointing to an unsigned binary. Names are a weak signal.

---

## 5. Malware Removal UX in CleanMyMac 5.x (added)

**Flow (VERIFIED parts: Scan, pre-selection, Remove/Review, Settings toggles; see §1):**
1. **Intro screen.** Module title, short benefit bullets, a "powered by" engine badge, last-scan time and current **scan mode** (for example "Scan mode: Deep Scan" with a **Configure…** link to settings). The big round button reads **Scan**. REPLICA (weak) for the badge, last-scan line and "Configure…".
2. **Scanning.** Live counter of items scanned and a **Stop** button. REPLICA (weak).
3. **Result: clean.** A positive "protected" state. REPLICA (weak).
4. **Result: threats.** A list of detected malware, **all pre-selected** (VERIFIED). **Remove** acts at once; **Review** opens details (VERIFIED). Rows offer "reveal in Finder" (REPLICA, weak) and add-to-Ignore-List (VERIFIED scope "Protection › Malware Removal").
5. **Removing**, then a **done** state. Partial failure leaves unremoved items in the list for retry (REPLICA, weak). A **restart** may be recommended (CMM3 strings, VERIFIED via 13).
6. **Unlicensed / Basic plan:** malware is *found* but not *removed* (VERIFIED via 01).

**Settings › Protection** (VERIFIED: toggle names "Enable Malware Monitor", background scanning, scan modes, extra locations; KB via 01/13). REPLICA (weak) wording, quoted as short labels only:
- Section "Malware Monitor Settings":
  - toggle **Enable Malware Monitor**;
  - toggle "Monitor threat activity in the background" (= background scanning).
- "Scan Options": Scan DMG disk images · Scan email attachments · Scan archives · Scan USB drives · Exclude downloaded iCloud files.
- "Scan Mode": Quick Scan · Balanced Scan · Deep Scan. Each shows **Speed / Depth / Purpose** rows.
- REPLICA (weak) Settings tab list: General · Scan · Notifications · Menu · (Agent) · Protection · Disk Access · Analytics · Ignore List. 01-overview has the KB-verified tab set; use that as primary.

**The Menu** has a Protection monitor showing real-time and background status and database status (VERIFIED via 01-overview).

**Smart Care** runs a **Quick** malware scan with threats auto-selected (VERIFIED via 02).

**App Store edition:** no real-time monitor and no malware alerts (VERIFIED via 01).

---

## 6. Scan depths and scan locations (added)

### 6.1 Depth mapping (INFERRED; MacPaw does not publish paths)

| Mode | Purpose | What we walk | Heuristic level | Expected time on a Mac mini |
|---|---|---|---|---|
| **Quick** (used by Smart Scan) | Persistence-first triage | All **persistence points** (§6.2 A), running processes' executables, `/Applications` + `~/Applications` top-level bundles (signature check only), browser extensions, configuration profiles | Known-bad hashes and rules plus strong heuristics only | < 1 min |
| **Balanced** (our default) | Everyday | Quick + `~/Library/Application Support/*`, `~/Library/Containers` top level, `/Library/Application Support/*`, `/Users/Shared`, `/tmp`, `/private/var/tmp`, `~/Downloads`, `~/Desktop`, hidden dot-entries directly under `$HOME`; Mach-O, scripts and installers only | + medium heuristics | 2–5 min |
| **Deep** (monthly) | Everything | Whole user-accessible file system on the boot volume (skipping `/System`, the sealed system volume and iCloud placeholders); every Mach-O, script, `.app`, `.pkg`, `.dmg` (if enabled) and archive (if enabled); all user home folders when run with the helper | + weak heuristics, shown as "suspicious" and unselected | 15–60 min |

Opt-in **extra locations**: DMG images, mounted read-only via `hdiutil attach -nobrowse -readonly -noverify` and then scanned; archives (zip, xar/pkg, tar), listed and scanned in memory with size and depth limits; **Mail attachments**, which need FDA, under `~/Library/Mail/V*/…/Attachments` and the Mail container; **external/USB volumes** under `/Volumes/*`, skipping Time Machine; iCloud Drive (`~/Library/Mobile Documents`), **downloaded files only**, never forcing materialisation of dataless files.

### 6.2 Location catalogue for our scanner

A. **Persistence points.** The taxonomy is VERIFIED-OSS from Objective-See KnockKnock's plugins (GPL-3, so we study the paths but do not copy code). Fetched: https://raw.githubusercontent.com/objective-see/KnockKnock/master/Plugins/ (LaunchItems.m, Cronjobs.m, PeriodicScripts.m, ShellConfigs.m, EventRules.m, AuthorizationPlugins.m, LogInOutHooks.m, StartupScripts.m, DirectoryServicesPlugins.m, DylibInserts.m, Extensions.m). See also 11-oss-api §3.7.

| Point | Paths / command | Root needed? |
|---|---|---|
| Launch agents and daemons | `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons` (skip `/System/Library/Launch*`, which is Apple's and sealed) | Read: no; remove system items: yes |
| Loaded jobs | `launchctl print gui/$(id -u)` (user domain); `launchctl print system` | INFERRED: system detail may need root |
| Background Task Management (macOS 13+) | `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`; dump with `sfltool dumpbtm` | **Yes**: `sfltool dumpbtm` prompts for admin when run as a user (VERIFIED via 01 fact-check of Mole) |
| Legacy login items | `~/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm`; old `~/Library/Preferences/com.apple.loginitems.plist` | No (FDA may be needed) |
| Cron | `crontab -l` (current user); `/usr/lib/cron/tabs/*` (all users) | Tabs dir: yes |
| Periodic | `/etc/periodic/{daily,weekly,monthly}`, `/etc/defaults/periodic.conf`, `/etc/periodic.conf(.local)` | No. Absent on macOS 26+ (VERIFIED via 01) |
| Shell startup files | `/etc/{zshenv,zprofile,zshrc,zlogin,zlogout,profile,bashrc}`; user `~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, `~/.profile` | No |
| emond | `/etc/emond.d/emond.plist`, `/etc/emond.d/rules/` | No. INFERRED: legacy, may be absent on current macOS |
| Login/logout hooks | `com.apple.loginwindow` plist `LoginHook`/`LogoutHook` in `/Library/Preferences` and `~/Library/Preferences` | No |
| rc / launchd.conf | `/etc/rc.common`, `/etc/rc.cleanup`, `/etc/launchd.conf` (legacy) | No |
| Authorization plugins | `/Library/Security/SecurityAgentPlugins/` | No |
| DirectoryServices plugins | `/Library/DirectoryServices/PlugIns` | No |
| `DYLD_INSERT_LIBRARIES` | `EnvironmentVariables` in launchd plists and `LSEnvironment` in app `Info.plist` (incl. `__XPC_DYLD_INSERT_LIBRARIES`) | No |
| System extensions / kexts | `systemextensionsctl list`; `/Library/SystemExtensions/`; `/Library/Extensions/*.kext` | List: no |
| App extensions | `pluginkit -mAvvv` (Safari web extensions: `-p com.apple.Safari.web-extension`) | No |
| **Browser extensions** | `~/Library/Safari/Extensions/` (legacy); Chrome/Chromium `~/Library/Application Support/<Vendor>/<Profile>/Extensions/` plus `Preferences`/`Secure Preferences`; Firefox `~/Library/Application Support/Firefox/Profiles/*/extensions(.json)` (VERIFIED-OSS, 11-oss-api §3.7) | No (Safari container needs FDA) |
| **Configuration profiles** | `profiles list` / `sudo profiles show -type configuration`; managed prefs under `/Library/Managed Preferences/` (e.g. Chrome policies forcing an extension). INFERRED: commands are standard, verify output format on 14/15/26 | Full listing: yes |
| Quarantine evidence | `xattr -p com.apple.quarantine <file>`; `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` (SQLite, `LSQuarantineEvent`) (VERIFIED via 11-oss-api) | No |

B. **Payload locations** (INFERRED, from the families in §4): `~/Library/Application Support/<random or lookalike>`, `/Library/Application Support/<…>`, `/Users/Shared/`, `/tmp`, `/private/var/tmp`, `/private/var/folders/*/T/` (current user only), hidden files directly in `$HOME` (`.helper`, `.agent`, `.<random>`), `~/Downloads`, `~/Desktop`, `/Applications`, `~/Applications`, Xcode projects (XCSSET), and `~/Library/Containers/com.apple.Safari/…` (needs FDA).

C. **Never scan or write** (INFERRED, consistent with the team-wide blocklist in 02/03): `/System`, the sealed system volume, `/usr` (except `/usr/local`), `~/Library/Keychains`, `/Library/Keychains`, `~/Library/Mobile Documents` (except downloaded files, read-only), Photos libraries, Mail stores (read-only, for attachments only), TCC databases (read-only), Time Machine volumes.

---

## 7. Detection engine design for our build (added; INFERRED unless marked)

**Layered verdicts, cheapest first:**
1. **Allow-list.** Apple-signed platform binaries; Developer-ID apps that pass `SecStaticCodeCheckValidity` with a notarization requirement and a valid stapled ticket; user-trusted items. Notarized code skips heuristic layers 4–5 but **not** hash and rule layers. Notarized malware has existed.
2. **Hash deny-list.** SHA-256 of whole files (Mach-O slices hashed both whole and per slice), scripts and installer payloads. Look up in a local SQLite table.
3. **Rule matching with YARA.** Embed **libyara** or **YARA-X**. Both are BSD-3-style licensed (VERIFIED, fetched LICENSE files: https://raw.githubusercontent.com/VirusTotal/yara/master/COPYING, https://raw.githubusercontent.com/VirusTotal/yara-x/main/LICENSE), so we can link them into a closed or personal app. We ship **our own** rules.
   - Optional: also evaluate Apple's on-disk XProtect rules, **read-only at runtime**, from `/private/var/protected/xprotect/XProtect.bundle/Contents/Resources/XProtect.yara` and `XPScripts.yr` (macOS 15+), or the legacy `/Library/Apple/System/Library/CoreServices/XProtect.bundle`. Reading needs FDA. Paths VERIFIED (fetched): https://raw.githubusercontent.com/stuartjash/macos-malware-kb/HEAD/SKILL.md. Never redistribute Apple's rules.
4. **Code-signing heuristics.**
   - Read the code: `SecStaticCodeCreateWithPath` → `SecCodeCopySigningInformation` (team ID, flags, entitlements) → `SecStaticCodeCheckValidity`.
   - Gatekeeper assessment: `spctl --assess -vv --type exec` (or `SecAssessment*`).
   - Signals: unsigned or ad-hoc-signed code in persistence points; signature invalid after modification; team ID on our PUA list; revoked Developer ID (assessment fails with "CSSMERR_TP_CERT_REVOKED").
5. **Behavioural and static heuristics**, each scored. Examples:
   - a launchd plist executing a shell or `osascript` on a hidden `$HOME` file;
   - `RunAtLoad` + `KeepAlive` + an unsigned target;
   - the program path is in `/tmp` or `/Users/Shared`;
   - the label imitates Apple (`com.apple.*` outside `/System`);
   - a script containing `display dialog … hidden answer` together with `security`/`dscl` and `curl`;
   - the quarantine xattr was stripped from an app downloaded within the last N days;
   - a Chrome extension force-installed by policy;
   - a configuration profile that sets proxy or DNS or forces an extension.
   - **Score ≥ high → "Malware" (pre-selected); medium → "Potentially unwanted" (pre-selected); low → "Suspicious" (not selected, Deep only).**
6. **Rule database.** A versioned SQLite file (hashes, PUA team and bundle IDs, YARA source, heuristic weights) plus a detached **Ed25519** signature checked before load (same pattern as 10-internals §12). It sits in our app group container. The update check runs at most daily and is user-toggleable. Never execute anything from it.

**Performance on Apple Silicon:** read files with `F_NOCACHE`; skip files over a size cap (e.g. 200 MB unless DMG or archive is enabled); use a `TaskGroup` sized to performance cores; keep a **result cache** keyed by (inode, size, mtime, rules-version) so rescans are incremental; `QOS_CLASS_UTILITY` for background scans and `.userInitiated` for manual ones.

---

## 8. Real-time monitoring and background scanning (added)

**MacPaw behaviour (VERIFIED, §1.5):**
- The monitor reacts to new program installations and new or modified items, and notifies only.
- It is hosted by the Health Monitor background agent, so it runs with the app closed.
- Background scanning is a separate periodic sweep with its own toggle.
- A Deep scan is still recommended monthly.
- The App Store edition has neither feature.

**Endpoint Security facts (VERIFIED, fetched SDK header):** https://raw.githubusercontent.com/alexey-lysiuk/macos-sdk/main/MacOSX26.5.sdk/usr/include/EndpointSecurity/ESTypes.h (event pages also on developer.apple.com, fetched JSON). Relevant notify events and their first macOS version:

| Event | Since |
|---|---|
| `ES_EVENT_TYPE_NOTIFY_XP_MALWARE_DETECTED` / `_REMEDIATED` | macOS 13.0 |
| `ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_ADD` / `_REMOVE` | macOS 13.0 |
| `ES_EVENT_TYPE_NOTIFY_PROFILE_ADD` / `_REMOVE` | macOS 14.0 |
| `ES_EVENT_TYPE_NOTIFY_GATEKEEPER_USER_OVERRIDE` | macOS 15.0 |
| `ES_EVENT_TYPE_NOTIFY_TCC_MODIFY` | macOS 15.4 |

An ES client needs the restricted `com.apple.developer.endpoint-security.client` entitlement, which Apple grants per developer. So a **personal, ad-hoc-signed build cannot use ES** (INFERRED, consistent with 10-internals §13).

**Our user-space monitor (INFERRED design):**
- **Host:** our background agent (the equivalent of Health Monitor), registered with `SMAppService.agent(plistName:)`. It runs in the user session.
- **FSEvents** stream (`FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`, latency about 2 s) on: `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Applications`, `~/Applications`, `~/Downloads`, `/Users/Shared`, `$HOME` (non-recursive filter for new dot-files), `~/Library/Application Support` (depth 1), `/Library/Application Support` (depth 1), browser extension folders, `/Library/Managed Preferences`.
- **New apps:** also `NSWorkspace.didLaunchApplicationNotification`, which scans the bundle on first launch, and an `NSMetadataQuery` for `kMDItemContentType == "com.apple.application-bundle"` added since the last check.
- **New volumes:** `NSWorkspace.didMountNotification`. Scan USB volumes if the option is enabled.
- **Persistence diff:** every 15 minutes, and on each FSEvent in launchd folders, re-enumerate persistence points (§6.2 A) and diff against the last snapshot. With the helper installed, also diff `sfltool dumpbtm` output hourly.
- **XProtect events without ES:** poll the unified log every 30 minutes. Use `log show --last 35m --style ndjson --predicate 'subsystem == "com.apple.XProtectFramework.PluginAPI" && category == "XPEvent.structured"'` (macOS 13–15). On **macOS 26** that structured stream reportedly vanished; XProtect then logs plain "system scan" messages under `com.apple.XProtectFramework` / category `Runner`. Match both. Reading the log needs an admin user. VERIFIED-OSS (third-party observation): https://raw.githubusercontent.com/NativeMojo/mojo-pulse/HEAD/Sources/MojoPulse/SecurityCollector.swift ; predicate also used by Jamf's aftermath (https://github.com/jamf/aftermath/blob/main/unifiedlogs/UnifiedLogModule.swift).
- **Notification:** `UNUserNotificationCenter` with a category offering **Review** (opens the app at the item) and **Remove** (asks for confirmation in the app; never removes silently from the notification).
- **Background scan schedule:** `NSBackgroundActivityScheduler` (interval 24 h or 7 d, `qualityOfService = .utility`, `tolerance` 1 h) inside the agent. It runs **Quick** by default, plus a monthly reminder for Deep. Skip when on battery; not relevant on a Mac mini, but keep the check.
- **Self-throttle:** coalesce events for 5 s; hash-cache unchanged files; cap concurrent scans to 1 in the background.

---

## 9. Removal, quarantine, trusted items, ignore list and history (added)

**MacPaw:** CleanMyMac removes; the Moonlock app quarantines and has Trusted Items and Detection History; CleanMyMac has an Ignore List with a Malware Removal scope (§1.7).

**Our design (INFERRED):**
1. **Quarantine first, delete later.**
   - Move the item to `~/Library/Application Support/<OurApp>/Quarantine/<UUID>/payload`. System-domain items go to `/Library/Application Support/<OurApp>/Quarantine/` via the helper.
   - Write `meta.json` next to it: original path, owner, mode, SHA-256, detection name, rules version and timestamp.
   - Strip execute bits (`chmod a-x`) and set a `com.apple.quarantine` xattr.
   - Auto-purge after 30 days (a setting). **Restore** puts the file back with its original mode and owner.
2. **Persistence removal order:**
   1. `launchctl bootout gui/$(id -u) <plist>`, or `launchctl bootout system <plist>` via the helper;
   2. terminate processes whose executable path matches (`proc_pidpath` + `kill`);
   3. quarantine the binary;
   4. quarantine the plist;
   5. re-enumerate to confirm.
   - For others' login items use `SMAppService` only for our own items. Third-party items: AppleScript `tell application "System Events" to delete login item "<name>"` (needs the Automation permission), or deep-link to Login Items: `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` (VERIFIED, fetched: https://raw.githubusercontent.com/bvanpeski/SystemPreferences/HEAD/macos_preferencepanes-Ventura.md).
   - **Never** run `sfltool resetbtm` automatically. It resets everyone's background-item approvals.
3. **Browser extensions:** require the browser to be quit.
   - Chromium: remove the extension folder *and* its entry in `Preferences`. `Secure Preferences` is HMAC-protected, so prefer opening `chrome://extensions` if editing fails.
   - Policy-forced extensions: remove the profile or managed preference first, or they come back.
   - Safari web extensions live inside a host app, so remove or quarantine the host app.
4. **Configuration profiles:** `sudo profiles remove -identifier <id>` via the helper (INFERRED; verify on 14/15/26; MDM-installed profiles cannot be removed this way), or deep-link to `x-apple.systempreferences:com.apple.Profiles-Settings.extension` (VERIFIED, same source).
5. **Trusted Items** (per-file hash + path) and **Ignore List** (path or folder patterns) share one store with the rest of the app's ignore list. Scope tag: "Protection › Malware".
6. **Detection History:** a local SQLite log (detected / quarantined / restored / deleted / ignored), shown in Settings and feeding our "Activity" dashboard. No telemetry.
7. **After removal:** recommend a restart when a process was killed or a daemon booted out (CMM3 precedent, VERIFIED via 13).

---

## 10. Relationship to Apple XProtect and Gatekeeper (added)

- **Apple components** (paths VERIFIED, fetched: https://raw.githubusercontent.com/stuartjash/macos-malware-kb/HEAD/SKILL.md):
  - XProtect signature bundle: legacy `/Library/Apple/System/Library/CoreServices/XProtect.bundle`; the live copy on macOS 15+ is `/private/var/protected/xprotect/XProtect.bundle`.
  - **XProtect Remediator**: `/Library/Apple/System/Library/CoreServices/XProtect.app`, with scanner plugins per family (Adload, Bundlore, Pirrit, DubRobber = XCSSET, and others).
- **CLI on macOS 15+:** `/usr/bin/xprotect version` (installed version and date), `xprotect check` (update available?) and `sudo xprotect update`. VERIFIED-OSS (fetched): https://github.com/and992/Jamf-EA/blob/HEAD/xprotect%20version%2015%2B.sh , https://github.com/wazuh/wazuh/blob/HEAD/ruleset/sca/darwin/25/cis_apple_macOS_26.x.yml . Older macOS: read `CFBundleShortVersionString` from the bundle's `Info.plist` (INFERRED).
- **Positioning (INFERRED):** Moonlock, and our engine, are *complementary*. XProtect blocks known malware at launch and Remediator cleans some families periodically. Neither covers PUAs, browser hijacks via profiles or many fresh stealers well (see the coverage column in §4). Our app should:
  - show an **"Apple protection" status card**: XProtect version and age, Gatekeeper `spctl --status`, SIP `csrutil status`, FileVault `fdesetup status`, firewall `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`;
  - surface recent XProtect detections from the log (§8);
  - **never** disable, modify or "optimise" any Apple security component.

---

## 11. Privacy module: every category (added)

General behaviour (VERIFIED via 01 and 13):
- Results are grouped **per browser**, then per category, plus system sections.
- The browser must be **quit** before estimation and cleaning. CMM3 used "Quit %@ to Estimate" (VERIFIED, fetched CMM3 strings: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/en.lproj/PrivacyScanResults.strings). REPLICA (weak): the X-era dialog offers "Quit All" or "Ignore".
- Privacy is **not part of Smart Care**. Deleting history *lists* never deletes the downloaded files themselves.
- After clearing cookies or passwords, logins must be re-entered.
- CMM3's **"Time range to clean"** options were: Last hour · Last two hours · Last 24 hours · Last week · Last month · Everything (VERIFIED, same strings file).

### 11.1 Category table

Paths are VERIFIED-OSS from Tencent Lemon's privacy cleaner (GPL-3; study only). Fetched: `…/LemonPrivacyClean/Classes/Manager/{Safari,Chrome,Firefox,BaseBrowser}PrivacyDataManager.m` at https://github.com/Tencent/lemon-cleaner/tree/master/localPod/LemonPrivacyClean/LemonPrivacyClean/Classes/Manager. Its category enum is: Cookie, Browser History, Download History, Session, Local Storage, Saved Password and Autofill (`Model/PrivacyData.h`).

| Category | MacPaw status | Safari | Chrome / Chromium (`~/Library/Application Support/Google/Chrome/<Profile>/`) | Firefox (`~/Library/Application Support/Firefox/Profiles/<p>/`) | Our default |
|---|---|---|---|---|---|
| **Browsing history** | CMM3 ✔, 5.x ✔ | `~/Library/Safari/History.db` (`history_items`, `history_visits`) | `History` (`urls`, `visits`) | `places.sqlite` (`moz_places`, `moz_historyvisits`) | Selected |
| **Downloads history** (list only) | CMM3 ✔, 5.x ✔ | `~/Library/Safari/Downloads.plist` (`DownloadHistory` array) | `History` → `downloads` table | `places.sqlite` → `moz_annos` (download annotations) | Selected |
| **Cookies** | CMM3 ✔, 5.x ✔ | `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies` (modern); legacy `~/Library/Cookies/Cookies.binarycookies` (VERIFIED-OSS, MacOptimizer scanner) | `Cookies`, and on recent versions `Network/Cookies` (VERIFIED-OSS: many tools read `Default/Network/Cookies`) | `cookies.sqlite` (`moz_cookies`) | **Not** selected (logs the user out) |
| **Autofill / form values** | CMM3 ✔, 5.x ✔ | `~/Library/Safari/Form Values` | `Web Data` (autofill tables). INFERRED: Lemon reads logins and history; the autofill table name is not verified | `formhistory.sqlite` (`moz_formhistory`) | Not selected |
| **Search queries** | 5.x ✔ (KB) | INFERRED: recent searches in Safari prefs | INFERRED: `History` → `keyword_search_terms` | INFERRED: `formhistory.sqlite` field `searchbar-history` | Selected |
| **Last-session / recently closed tabs** | CMM3 ✔, 5.x ✔ | `~/Library/Safari/LastSession.plist`, `RecentlyClosedTabs.plist`. Lemon hides Safari sessions on 10.14+ because the file can't be deleted, so expect SIP/container quirks | `Current Session`, `Last Session`, `Session Storage`, `Sessions/` | `sessionstore.jsonlz4`, `sessionstore-backups/` | Not selected |
| **HTML5 Local Storage / IndexedDB** | CMM3 ✔; 5.x unconfirmed | `~/Library/Safari/LocalStorage`, `~/Library/Safari/Databases` (legacy); modern WebKit data in the Safari container (INFERRED) | `Local Storage/`, `IndexedDB/`, `Service Worker/` | `storage/default/`, `webappsstore.sqlite` | Not selected |
| **Saved passwords** | CMM3 ✔ (re-enter logins except Keychain ones); X/5 unconfirmed | Keychain (do not touch) | `Login Data` (`logins` table) | `logins.json` + `key4.db` | **Never offered** in our build |
| **Top sites / favicons** | Not documented | `TopSites.plist`, `Favicon Cache/`, `Touch Icons Cache/` (VERIFIED-OSS paths) | `Top Sites`, `Favicons` | `favicons.sqlite` | Optional, unselected |
| **Browser cache** | Belongs to **Cleanup › System Junk**, not Privacy | `~/Library/Caches/com.apple.Safari` | `~/Library/Caches/Google/Chrome/<Profile>/Cache` | `~/Library/Caches/Firefox/Profiles/<p>/cache2` | n/a (Cleanup track) |

Other browsers (INFERRED, same Chromium layout under other vendor folders):
- Edge: `Microsoft Edge`, plus Beta, Dev and Canary.
- Brave: `BraveSoftware/Brave-Browser`.
- Opera: `com.operasoftware.Opera`.
- Vivaldi: `Vivaldi`.
- Arc: `Arc/User Data`.

Discover profiles from each vendor's `Local State` → `profile.info_cache`. Lemon supports Safari, Chrome, Firefox, QQ Browser, Opera, Chromium and four Edge channels (VERIFIED-OSS enum).

### 11.2 System sections

| Section | What it is | Paths / commands | Notes |
|---|---|---|---|
| **Recent Items** (apps, documents, servers) | 5.x ✔ (KB) | `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.{RecentApplications,RecentDocuments,RecentServers,RecentHosts}.sfl3`; per-app `…/com.apple.LSSharedFileList.ApplicationRecentDocuments/<bundle-id>.sfl3`; legacy `~/Library/Preferences/com.apple.recentitems.plist`; `~/Library/Recent Servers/` | VERIFIED-OSS: file names (https://github.com/force4u/AppleScript, https://github.com/Gary-Ash/Scripts) and the `.sfl2` → `.sfl3` → `.sfl4` evolution with macOS versions (https://raw.githubusercontent.com/spatel-DFIR/Everything-DFIR/HEAD/macOS/11%20-%20Artifacts/Recent%20Items%20and%20SharedFileList.md). INFERRED: after editing, `killall sharedfilelistd` so the daemon doesn't rewrite the old contents (third-party code does this). Never touch `FavoriteItems`/`FavoriteVolumes`, which are the Finder sidebar |
| **Wi-Fi networks** | 5.x ✔ (KB; restricted in the App Store edition) | List: `networksetup -listpreferredwirelessnetworks <dev>`; remove: `networksetup -removepreferredwirelessnetwork <dev> "<SSID>"` (admin); store: `/Library/Preferences/com.apple.wifi.known-networks.plist` (Big Sur+); legacy `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist` | VERIFIED-OSS (fetched snippets): https://github.com/dhruv-anand-aintech/wifi-priority-tui , https://github.com/yrbane/macosx-scripts. **Mac mini edge case (INFERRED):** `en0` is Ethernet; Wi-Fi is usually `en1`. Resolve with `networksetup -listallhardwareports`. Never preselect the **currently connected** network. Known networks sync via iCloud Keychain and may reappear. SSID names via CoreWLAN need Location permission on recent macOS. **Never delete the whole plist** (a third-party clone does; that is an anti-pattern) |
| **Chats / Messages** | CMM3 ✔ (Skype, Messages, iMessage…); X-era REPLICA shows "Chat Data"; **5.x unconfirmed** | `~/Library/Messages/chat.db`, `~/Library/Messages/Attachments/` (FDA) | INFERRED: **do not offer** chat-history deletion. Editing `chat.db` while Messages in iCloud is on risks sync corruption, and attachments are user data. At most offer `~/Library/Messages/Caches/Previews/*` (handled by Cleanup in 03) |
| **Download log** (quarantine events) | Not documented for MacPaw (Lemon has "Download Logs") | `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "DELETE FROM LSQuarantineEvent; VACUUM;"` | VERIFIED via 11-oss-api. Optional, unselected. It does **not** remove `com.apple.quarantine` xattrs, and must not |
| **Developer / shell traces** | Not MacPaw (REPLICA's own "Development Traces") | `~/.zsh_history`, `~/.bash_history`, `~/.zsh_sessions/`, `~/.python_history`, `~/.node_repl_history`, `~/.lesshst` | INFERRED optional extra, unselected; warn that shell history is useful |

### 11.3 Implementation rules (INFERRED)

- **Quit handling:** detect running browsers via `NSRunningApplication.runningApplications(withBundleIdentifier:)`. Offer per-browser **Quit** (`terminate()`, then wait up to 10 s, then offer Force Quit), **Skip** or **Cancel**. Re-estimate automatically after quit.
- **Reading locked SQLite:** copy the DB plus `-wal`/`-shm` to a temp folder, open read-only and count rows for the estimate (Lemon copies DBs before reading; VERIFIED-OSS, `BaseBrowserPrivacyDataManager.m`). **Writing** happens only on the live DB with the browser quit, in one transaction, followed by `VACUUM`.
- **Granularity:** per-site rows for history and cookies (group by host), like Lemon's per-URL and per-host SQL. Apply the time-range filter on visit timestamps: Safari uses seconds since 2001, Chrome microseconds since 1601 and Firefox microseconds since 1970 (INFERRED; verify).
- **Safari needs Full Disk Access** (`~/Library/Safari` is TCC-protected; MacPaw's PermissionsKit probes `~/Library/Safari/Bookmarks.plist`, VERIFIED via 10). For cookies of our *own* WebKit store only, `WKWebsiteDataStore` is irrelevant; Safari's store must be edited on disk with Safari quit.
- **Safari profiles (Safari 17+)** keep separate history and website data per profile. INFERRED: locate under the Safari container `…/Safari/Profiles/<UUID>/` and verify on device.
- Anything that cannot be deleted (SIP/container) is reported as "skipped", never an error loop.

---

## 12. App Permissions (TCC) (added)

**MacPaw (VERIFIED via 01/13):** a review screen grouped by permission type (camera, microphone, files and folders, Full Disk Access, and others), with recommended reviews as tiles. Management is restricted in the App Store edition. REPLICA (weak): rows can be sorted by name or "Permission Type"; changes route to System Settings.

**Data sources:**
- **User TCC DB:** `~/Library/Application Support/com.apple.TCC/TCC.db`. **System TCC DB:** `/Library/Application Support/com.apple.TCC/TCC.db`. Both need FDA to read, and the system one also needs root.
- Query: `SELECT service, client, client_type, auth_value, auth_reason, last_modified, policy_id, indirect_object_identifier, indirect_object_identifier_type FROM access;`. VERIFIED-OSS (fetched, Fleet's osquery table): https://github.com/fleetdm/fleet/blob/HEAD/orbit/pkg/table/tcc_access/tcc_access.go
- INFERRED (common knowledge, verify): `auth_value` 0 = denied, 2 = allowed, 3 = limited; `client_type` 0 = bundle ID, 1 = path. System-wide services (Accessibility, Screen Recording, Input Monitoring, Full Disk Access, PostEvent) live in the **system** DB; per-user services (Camera, Microphone, Contacts, Calendars, Photos, …) live in the **user** DB. Partially VERIFIED-OSS: a provisioning script seeds Accessibility, ScreenCapture and PostEvent in the system DB (https://github.com/trycua/cua/blob/HEAD/libs/images/macos/files/seed-tcc.sh).
- **Screen Recording on macOS 15+** also keeps per-app approval dates in `~/Library/Group Containers/group.com.apple.replayd/ScreenCaptureApprovals.plist` (VERIFIED-OSS: https://github.com/electron/electron/blob/HEAD/script/actions/screencapture-nag-remover.sh , https://github.com/actions/runner-images/blob/HEAD/images/macos/scripts/build/configure-tccdb-macos.sh).
- **Location Services** are not in TCC.db. INFERRED: `/var/db/locationd/clients.plist` (root); show read-only, or skip.

**Service → label → deep link.** Service keys are VERIFIED-OSS (https://github.com/todddube/reviewAppPerms/blob/HEAD/ReviewAppPermsSwift/Sources/ReviewAppPerms/Models/ServiceDefinitions.swift). Anchors are VERIFIED (fetched: https://raw.githubusercontent.com/bvanpeski/SystemPreferences/HEAD/macos_preferencepanes-Ventura.md). Base URL: `x-apple.systempreferences:com.apple.preference.security?<anchor>`.

| TCC service | Settings label | Anchor |
|---|---|---|
| `kTCCServiceCamera` | Camera | `Privacy_Camera` |
| `kTCCServiceMicrophone` | Microphone | `Privacy_Microphone` |
| `kTCCServiceScreenCapture` | Screen & System Audio Recording | `Privacy_ScreenCapture` |
| `kTCCServiceAccessibility` | Accessibility | `Privacy_Accessibility` |
| `kTCCServiceListenEvent` | Input Monitoring | `Privacy_ListenEvent` |
| `kTCCServiceSystemPolicyAllFiles` | Full Disk Access | `Privacy_AllFiles` |
| `kTCCServiceSystemPolicy{Desktop,Documents,Downloads}Folder`, `…NetworkVolumes`, `…RemovableVolumes` | Files & Folders | `Privacy_FilesAndFolders` |
| `kTCCServiceAppleEvents` | Automation | `Privacy_Automation` |
| `kTCCServiceSystemPolicyAppBundles` (INFERRED key) | App Management | `Privacy_AppBundles` |
| `kTCCServiceDeveloperTool` | Developer Tools | `Privacy_DevTools` |
| `kTCCServiceAddressBook` | Contacts | `Privacy_Contacts` |
| `kTCCServiceCalendar` / `kTCCServiceReminders` | Calendars / Reminders | `Privacy_Calendars` / `Privacy_Reminders` |
| `kTCCServicePhotos` | Photos | `Privacy_Photos` |
| `kTCCServiceBluetoothAlways` | Bluetooth | `Privacy_Bluetooth` |
| `kTCCServiceSpeechRecognition` | Speech Recognition | `Privacy_SpeechRecognition` |
| `kTCCServiceMediaLibrary` | Media & Apple Music | `Privacy_Media` |
| (locationd) | Location Services | `Privacy_LocationServices` |

**Actions (INFERRED):**
- **Revoke:** `tccutil reset <ServiceName> <bundle-id>`, run as the user for user-DB services and via the helper for system-DB services. It resets *that app's* grant to "not determined", so the app re-prompts next time.
  - Correction to a common belief seen in a third-party clone: `tccutil reset` only resets *all* apps when no bundle ID is given. Always pass one, and never call the bare form.
  - The service names for `tccutil` drop the `kTCCService` prefix (`Camera`, `Microphone`, `ScreenCapture`, `SystemPolicyAllFiles`, …) (VERIFIED-OSS, same reviewAppPerms file).
- **Grant:** impossible programmatically. Deep-link to the anchor.
- **Never write TCC.db.** It is SIP-protected, and editing it is how malware bypasses TCC.
- **"Recommended to review" tiles:** apps holding Screen Recording, Accessibility, Input Monitoring or Full Disk Access; apps whose bundle no longer exists (stale grants: offer reset); apps not launched in more than 90 days that still hold Camera or Microphone; unsigned or ad-hoc clients.

---

## 13. Permissions, platform constraints and security lessons (added)

**What our Protection features need (INFERRED):**

| Need | Why | How |
|---|---|---|
| **Full Disk Access** | Safari data, Mail attachments, TCC.db, other apps' containers, XProtect bundle, BTM | PermissionsKit-style probe and deep link to `Privacy_AllFiles` (10-internals) |
| **Admin / privileged helper** | System LaunchDaemons, `/Library/*` quarantine, `sfltool dumpbtm`, `profiles`, system TCC resets, Wi-Fi removal, other users' homes | `SMAppService.daemon` helper with intent verbs (10-internals §12) |
| **Background item approval** | Monitor agent and scheduler | `SMAppService.agent`; handle `.requiresApproval` with a link to Login Items |
| **Notifications** | Monitor alerts | `UNUserNotificationCenter.requestAuthorization` |
| **Automation (System Events)** | Removing third-party legacy login items | Prompted on first use |
| **Location** (optional) | Showing Wi-Fi SSID names via CoreWLAN | Ask only when the user opens the Wi-Fi section |
| **Endpoint Security** | Not available to a personal ad-hoc build | User-space monitor instead (§8) |

**Security lessons from CleanMyMac's own CVEs** (VERIFIED, fetched CVE records from https://github.com/CVEProject/cvelistV5):
- CVE-2018-4032 through CVE-2018-4037 and CVE-2018-4041/-4042: CleanMyMac X 4.04's **privileged helper** accepted unvalidated input and let local users modify the file system as root.
- **CVE-2019-5011** (X 4.20): the update left the old vulnerable helper in place.

Implications for our Protection module, which runs the most privileged operations:
- per-connection code-signing checks on the helper XPC;
- intent verbs with IDs only, so the helper re-derives and re-validates paths;
- replace the helper on every update;
- resolve symlinks and re-check the blocklist at delete time;
- quarantine rather than unlink.

(Matches 10-internals §12.)

---

## 14. Our naming and information architecture (added; INFERRED)

- Do **not** use "Moonlock", "CleanMyMac", "Smart Care" or MacPaw's illustrations or copy (01-overview §13).
- **Module name:** "Shield" (sidebar). Sub-areas: **Threat Scan** (malware), **Traces** (privacy) and **Access Review** (app permissions). Plus a **Guard** status card for the real-time monitor and an **Apple Protection** card (XProtect, Gatekeeper, SIP, FileVault, firewall).
- **Engine name:** our own, e.g. "Sentinel rules" (versioned "rules database"). Show the rules version and date in Settings.
- **Scan modes:** "Fast / Standard / Thorough", each with our own Speed/Depth/Purpose blurb.
- **Settings › Shield:**
  - Real-time Guard (on);
  - Background scan (daily/weekly);
  - Scan mode;
  - Extra locations: disk images, archives, mail attachments, external drives, downloaded iCloud files;
  - Quarantine retention (30 days);
  - Rules updates (on, daily check);
  - Trusted items;
  - Detection history.
- **Traces sections:** one card per installed browser plus Recent Items, Wi-Fi Networks, Download Log and (optional) Shell History. Time-range picker; defaults per §11.1.

---

## 15. Gaps (updated in the fact-check pass)

1. **Unfinished-report gap: resolved in this revision.** Sections 2–14 were written by the fact-checker from GitHub-reachable sources and sibling reports. A follow-up researcher with web access should re-verify the MacPaw-side claims marked "search excerpt" or REPLICA against live macpaw.com pages.
2. **Exact 5.x on-screen labels:** still unconfirmed from MacPaw. The best available evidence is the third-party REPLICA strings in §1.3 and §5 (weak).
3. **Per-release Protection changes:** 5.0.1–5.2.5 VERIFIED as none (DevMate notes). For 5.2.6–5.7.1 there is only absence of evidence; DevMate returns 403 and macpaw.com/whats-new was unreachable.
4. **Moonlock internals** (YARA, hash, ML or behaviour; database location and format): still not public. Our design does not depend on it (§7).
5. **Quarantine vs delete:** best reading is that CleanMyMac deletes and Moonlock quarantines (§1.7). The comparison table itself could not be re-read.
6. **Messages/chats in 5.x Privacy:** unconfirmed. CMM3 had it (VERIFIED); X-era REPLICA shows "Chat Data"; no 5.x evidence. Our build deliberately excludes chat-history deletion (§11.2).
7. **Macworld 5.0.4 malware-test verdict:** still unreadable (macworld.com blocked; no mirror on GitHub).
8. **(new)** Whether CleanMyMac 5 installs the `com.macpaw.moonlock.engine` ES system extension: conflicting evidence (§1.6).
9. **(new)** Exact `auth_value`/`client_type` meanings and Safari 17+ profile paths should be confirmed on a Mac running 14, 15 and 26.
10. **(new)** Configuration-profile listing and removal commands (`profiles list/show/remove`) should be verified on 14, 15 and 26, where Apple has been restricting the `profiles` CLI.

---

## Verification notes

**Method.**
- This fact-check ran with **no web-search budget**. The shared per-turn limit was already exhausted, so not a single WebSearch call could run. WebFetch failed DNS for macpaw.com, moonlock.com, setapp.com, apps.apple.com and macworld.com.
- `curl` through the proxy reached only GitHub, raw.githubusercontent.com, developer.apple.com and one S3 bucket.
- Claims were therefore tested against GitHub code search, raw files (Homebrew cask, SDK headers, CVE records, OSS tools), Apple documentation JSON and MacPaw's DevMate S3 notes. No archive or reader services were used.

**Claims checked (about 17) and outcome:**

| # | Claim | Result |
|---|---|---|
| 1 | Current version and build (5.7.1, `50701.0.2609301754`) | Confirmed (cask, fetched) |
| 2 | macOS 27 = "Golden Gate" | Confirmed (Homebrew `macos_version.rb`) |
| 3 | Homebrew cask's uninstall stanza lists HealthMonitor, Menu, Agent and its LaunchDaemon, and Updater | **Corrected.** LaunchDaemon plist and Updater LaunchAgent are `zap`-only |
| 4 | "No ES system extension visible in CleanMyMac 5" | **Corrected and downgraded to INFERRED.** Monitro shows a Moonlock sysext running beside CMM5; OpenAgents shows none on another CMM5 Mac. Conflicts with 10-internals and 13-helpcenter, which state it as fact |
| 5 | Moonlock Engine introduced July 2023 | Corroborated (TLDR sponsor slot, 19 July 2023, fetched). Also confirms new coverage of external drives, mail attachments and browser extensions |
| 6 | Scan modes Quick/Balanced/Deep and extra-location toggles | Not refuted. REPLICA strings agree, but suggest the iCloud option is an *exclusion* |
| 7 | "Maximize suspicion" X-era mode name | **Downgraded to INFERRED.** Single unverifiable source; no corroboration found |
| 8 | Protection changes in 5.1–5.7 | 5.0.1–5.2.5: none (DevMate, fetched). Later versions: unknown |
| 9 | ES event names and availability | Confirmed with exact first versions from the macOS 26.5 SDK `ESTypes.h`. GATEKEEPER_USER_OVERRIDE is 15.0 and TCC_MODIFY is 15.4, not 13 |
| 10 | XProtect paths and the `xprotect` CLI (15+) | Confirmed (OSS scripts, malware KB) |
| 11 | XProtect Remediator log predicate | Confirmed (Jamf aftermath, Velociraptor). New finding: reportedly gone on macOS 26 |
| 12 | Recent Items `.sfl3` file names | Confirmed (OSS) |
| 13 | Wi-Fi known-networks plist and `networksetup` commands | Confirmed (OSS). Mac mini `en1` caveat added (INFERRED) |
| 14 | TCC.db schema and paths | Confirmed (Fleet). Screen-recording approvals plist on 15+ confirmed |
| 15 | System Settings privacy anchors, Profiles and Login Items deep links | Confirmed (fetched reference) |
| 16 | CleanMyMac CVEs (2018-4032…4042, 2019-5011) | Confirmed (CVEProject records) |
| 17 | YARA and YARA-X licences | Confirmed BSD-3-style (fetched LICENSE files) |

**Gaps addressed:** the unfinished report (§§2–14 written); Moonlock internals (documented as not public, with an alternative design); quarantine vs delete (best reading stated); Messages under Privacy (evidence summarised, exclusion recommended); per-release changes (partially, through 5.2.5).

**Still uncertain:** MacPaw's exact 5.x strings; Moonlock's detection internals and database location; whether CMM5 ships the ES sysext; 5.2.6+ Protection changes; the Macworld 5.0.4 verdict; several macOS behaviours marked INFERRED, which need on-device verification on 14, 15 and 26 (profiles CLI, Safari profile paths, TCC value meanings, Location-gated SSIDs).

**Cross-team note:** 10-internals (§1, §2.1 table) and 13-helpcenter (§1 item 9, §9.1) state the Moonlock sysext as a verified CleanMyMac 5 component. Per finding 4, that should be softened to "observed on one CMM5 machine; may belong to the standalone Moonlock app". This fact-checker edited only this file.

---

## Addendum (gap-fill)

See `20-gap-02-cmm5-cleanup-protection-performance-screens.md` (2026-10-12) §4 for the 5.x Protection flow. It covers:
- one scan feeding a tile dashboard (malware tile plus privacy and app-permission tiles), reviewed in a shared three-pane manager;
- the scan-mode picker in Settings › Protection, with a "Scan mode · Configure…" shortcut on the landing (verified on real X screenshots);
- the per-browser Privacy categories, where Wi-Fi is present, chats are probably absent and saved passwords are at most informational;
- the App Permissions grouping and the Remove (revoke) action, as seen in X's Privacy › Application Permissions screenshot.

This partly answers §15 gaps 2 and 6. Exact 5.x strings remain unverified.

## Addendum (gap-fill)

See `20-gap-06-cmm5-settings-prefkeys-alerts.md` §2.2 and §3.5 (2026-10-12).
- The nine-tab "REPLICA" Settings strip in §5 is CleanMyMac **X 4.14/4.15** (Moonlock badge plus Speed/Depth/Purpose scan modes, from 4.14.0 and 4.15.0 release notes).
- 5.x stores **Enable Malware Monitor** as `MalwareScanMode` = `"protected"` | `"manual"` (string, App Group plist; VERIFIED-OSS).
- The scan-depth, background-scan and extra-location keys are still unknown.
