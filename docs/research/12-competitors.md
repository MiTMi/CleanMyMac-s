# 12 — Competitors, Criticism, Apple Built-ins and Legal Guardrails

> **Track:** competitive landscape, criticism of CleanMyMac turned into design principles, what macOS already does, and legal guardrails for an original, functionally equivalent app.
> **Target:** our own app (not named CleanMyMac) for an Apple-silicon Mac mini running macOS 14 Sonoma or later (15 Sequoia, 26 Tahoe; macOS 27 noted where sources cover it).
> **Research date:** 2026-10-12. **Not legal advice.** Section 5 is an engineering checklist. If the app is ever distributed or sold, have a lawyer review it.

---

## 0. Method, labels, access caveats

**Labels used on every claim:**

| Label | Meaning |
|---|---|
| **VERIFIED** | Read this session from the cited URL. |
| **VERIFIED-SIB** | Verified by a sibling research track in this repo (`docs/research/0x-*.md`). Its source URL is repeated here. |
| **RECALLED** | Background knowledge (cut-off mid-2026) that could **not** be re-fetched this session. A URL to re-check is given where known. Treat it as probable, not proven. |
| **VERIFIED-2ND** | (fact-check) Read this session from a **secondary** open-source page on GitHub that quotes or mirrors the primary (e.g. another project's docs, a threat-intel KB, an Apple localization glossary, a privacy-policy corpus). Stronger than RECALLED, weaker than VERIFIED. |
| **INFERRED** | Our reasoning or recommendation for our implementation. |

**Fact-check markers:** "(corrected)" = the adversarial fact-check pass changed the claim; "(fact-check)" = added by that pass. See "Verification notes" at the end.

**Access caveats:**
- The shared web-search budget for this run was already used up when this track started, so **no general web searches were possible**.
- DNS resolution failed for almost every non-GitHub host: macpaw.com, cleanmymac.com, wikipedia.org, daisydiskapp.com, titanium-software.fr, freemacsoft.net, support.apple.com, apple.com, uspto.gov, nvd.nist.gov, cve.org, talosintelligence.com, objective-see.org, eclecticlight.co, 9to5mac.com and tidbits.com all failed.
- **Reachable sources:**
  - `github.com` and `raw.githubusercontent.com`: READMEs, issues, the GitHub Advisory Database, the official CVE JSON in `CVEProject/cvelistV5`, and Homebrew cask definitions.
  - `developer.apple.com`: App Review Guidelines and the HIG/doc JSON.
  - `s3-us-west-2.amazonaws.com`: MacPaw DevMate release notes.
- So competitor **feature** claims are mostly RECALLED. Competitor **versions, minimum macOS, installed helpers/daemons and telemetry-SDK traces** are VERIFIED from Homebrew casks, which list exactly what each app installs.
- (fact-check) The fact-check pass had the same limits: the WebSearch budget was exhausted and the same hosts failed DNS. It added evidence from GitHub-wide code search (official CVE JSON, threat-intel KBs, open-source projects quoting Apple/Google docs, Apple localization glossaries), `developer.apple.com` (API JSON, App Review Guidelines, archived technotes) and WebFetch of individual `github.com` pages.
- Quotes are short labels only. Everything else is paraphrased.

---

## 1. Executive summary

1. **CleanMyMac's real moat is breadth plus polish, not any single feature.** Competitors beat it on depth in each area:
   - DaisyDisk: disk visualisation.
   - OnyX: deep maintenance and hidden settings.
   - AppCleaner, Pearcleaner, Nektony: uninstall and leftovers.
   - iStat Menus and Stats: monitoring and sensors.
   - Mole and PureMac: developer junk, dry-run and logs.

   Features that are close to unique to CleanMyMac:
   - a malware engine with a real-time Endpoint-Security monitor;
   - **Cloud Cleanup**;
   - **Email Cleanup** (Gmail);
   - **App Permissions** review;
   - the one-click cross-module **checkup**;
   - **Smart Insights** explanations.

   (§2.3)
2. **Our clone should be the union plus the best-in-class depth of each competitor** (§2.4). Examples: DaisyDisk-grade map and "hidden/purgeable" accounting, Pearcleaner-style Trash watcher and undo history, Mole-style dry-run, op-log and developer purge, iStat-style sensors (read-only fans on Apple silicon), OnyX-style "Parameters" (hidden `defaults` toggles, reversible).
3. **Most recurring criticism of CleanMyMac is about honesty and safety, not missing features:**
   - cache cleaning sold as speed;
   - the RAM "purge" myth;
   - purgeable-space overpromising;
   - bundle thinning that breaks some apps (corrected): the breakage comes from apps' own integrity self-checks, updaters and stripped `arm64e` slices, **not** from the code signature. Apple's TN2206 says removing `.lproj` files or a whole architecture slice does not invalidate a signature (§4.2 C4);
   - scan-free / pay-to-fix upsell;
   - background agents and notifications;
   - telemetry;
   - a 2018–2019 run of **14 privilege-escalation/DoS CVEs** in its root helper.

   Each becomes a numbered design principle in §4.4 (P1–P22).
4. **Security history is concrete and VERIFIED.** CVE-2018-4032…4037 and 4041…4047 hit CleanMyMac X 4.04. CVE-2019-5011 hit 4.20, because an upgrade left the old vulnerable helper in place. No CleanMyMac 5 CVE appears in the CVE list as of today (§4.2 C9).
   - (fact-check) **The same bug class keeps hitting the whole category.** Each of these shipped a root XPC helper that untrusted local processes could drive:
     - Sensei ≤ 1.5.10: CVE-2024-7915, PID-based client check;
     - Pearcleaner 4.4.0–4.5.1: CVE-2025-54595, no client check plus a shell-exec method;
     - iStat Menus 7.10.4: CVE-2025-11921, command injection;
     - BuhoCleaner 1.15.2: CVE-2026-0924, PID-reuse TOCTOU.

     All VERIFIED from cvelistV5. Our helper design (P14) must treat this as the top risk.
5. **macOS already covers part of the job.** Storage settings (recommendations plus per-category review), automatic purgeable/cache management, XProtect/XProtect Remediator, Login Items & Extensions, Activity Monitor and Software Update all exist. Our app should **deep-link into these and explain them**, not duplicate them badly (§3).
6. **Mac mini specifics:** no battery (hide battery UI), always on AC (maintenance can run anytime), one fan (show RPM read-only; no fan control by default).
7. **Legal:** functionality, generic feature names and platform layout conventions are free to use. What we must not copy:
   - the names "CleanMyMac", "MacPaw", "Moonlock", plus distinctive feature names ("Smart Care", "Space Lens", "My Clutter", "Smart Insights", and **also "Smart Scan"**, CleanMyMac X's own module name);
   - the pink-iMac-plus-squeegee icon motif;
   - the illustrations, sounds and copy;
   - the exact per-module palette plus circular "action orb" combination (trade dress);
   - code or data obtained by reverse engineering, which MacPaw's EULA forbids.

   **The repo itself is named `CleanMyMac-s`. Rename it before making it public.** (§5)
8. **Licences of open-source peers matter if we borrow code** (§5.6):
   - free to borrow with attribution: Stats, PureMac, Purge, Headroom (MIT), MacSai (BSD-3), DiskWise (Apache-2.0), MacPaw's own PermissionsKit (MIT);
   - copyleft: Mole, Latest and KnockKnock are GPL-3.0;
   - Pearcleaner's Apache-2.0 + Commons Clause forbids monetisation.

---

## 2. Competitive landscape

### 2.1 Product snapshots

Each snapshot gives: maker/model; current version and minimum macOS from Homebrew (VERIFIED); components it installs (VERIFIED from the cask's `uninstall`/`zap` stanzas); core features (mostly RECALLED); and what we take from it (INFERRED).

#### CleanMyMac (MacPaw), our baseline
- **Version:** 5.7.1, build `50701.0.2609301754`. Bundle `CleanMyMac_5.app`, team ID `S8EX82NJP6`. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb).
- **Installed components** (VERIFIED, same cask):
  - launchd jobs `…HealthMonitor` and `…Menu`;
  - privileged helper `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` plus `/Library/LaunchDaemons/…Agent.plist`;
  - a user LaunchAgent `…Updater.plist`;
  - a login item "CleanMyMac 5 Menu";
  - `HTTPStorages` and a Group Container.
- The sibling internals track adds the Moonlock Endpoint-Security system extension and the analytics endpoint `api-lytics.macpaw.com`. VERIFIED-SIB (`10-internals.md` §1, §9).
- **Modules (5.x):**
  - Smart Care;
  - Cleanup;
  - Protection (Malware Removal, Privacy, App Permissions);
  - Performance (maintenance tasks, Login/Background Items);
  - Applications (Uninstaller, Updater, Leftovers, Installation files);
  - My Clutter (Duplicates, Similar Images, Downloads, Large & Old files);
  - Space Lens;
  - Cloud Cleanup;
  - Email Cleanup (2026);
  - the Menu;
  - My Tools / My Activity;
  - Notification Center (5.6.0).

  VERIFIED-SIB (`01-overview.md` §5–6, citing https://macpaw.com/cleanmymac/whats-new and the KB).
- **Model:** subscription or one-time purchase. Basic/Plus plans since July 2025. 7-day trial. Unlicensed copies can **scan but not clean**. VERIFIED-SIB (`01-overview.md` §4, https://macpaw.com/support/cleanmymac/knowledgebase/editions).
- **Companion CLI** (public beta 2026, proprietary). (corrected) `cleanmymac-cli` is the **repo and Homebrew cask** name. The commands are **`cleanmymac`** and the alias **`cmm`**. The cask (v1.0.0) installs `CleanMyMac_5_CLI.app` and links both binaries. It needs macOS 11+.
  - subcommands `clean junk|dev|ai|trash`, `purge`, `analyze`, `optimize ram|purgeable`, `ignore`, `config`;
  - analytics can be switched off in `config`. Neither the README nor the wiki states the default. "Can be disabled" suggests on by default (INFERRED).

  VERIFIED (https://github.com/MacPaw/cleanmymac-cli ; https://raw.githubusercontent.com/wiki/MacPaw/cleanmymac-cli/Safety-and-Privacy.md ; fact-check: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-cli.rb).
- (fact-check) **CleanMyMac 3 plugged into Apple's own Storage Management window.** It shipped `StorageManagement.appex` (display name "System Junk") on the `com.apple.storagemanagement` extension point. Apple's Mail, Photos and Messages use the same point. Apple publishes no documentation for it (developer.apple.com returns 404), so treat it as private. VERIFIED-2ND (Info.plist of a third-party copy of CMM3: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/PlugIns/StorageManagement.appex/Contents/Info.plist ; Mail/Photos/Messages plists found by GitHub code search). INFERRED: don't build on it; deep-link to Storage settings instead.

#### DaisyDisk (Software Ambience)
- **Version:** 4.34.2. Sparkle updates. **Installs an admin helper** `com.daisydiskapp.DaisyDiskAdminHelper` in `/Library/PrivilegedHelperTools`, used for whole-disk scans. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/d/daisydisk.rb).
- **Features** (RECALLED; https://daisydiskapp.com/):
  - interactive **sunburst** ring map;
  - hover/zoom navigation;
  - Quick Look preview;
  - a "Collector" staging area: drag items in, review, then delete in one go;
  - separate display of **hidden** (not scannable) and **purgeable** space;
  - scans of external and network volumes;
  - a one-time purchase with a sandboxed Mac App Store version.
- **Take:** best-in-class map interaction; the "Collector" basket as a two-step delete; honest "hidden/purgeable" accounting. INFERRED.

#### OnyX (Titanium Software, Joël Barrière)
- **Version and builds:** separate build per macOS. Big Sur 4.0.2 · Monterey 4.2.7 · Ventura 4.4.7 · Sonoma 4.6.2 · Sequoia 4.8.5 · Tahoe 5.0.5 · macOS 27 5.1.0. Free. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/o/onyx.rb).
- **Cask description:** "Verify system files structure, run miscellaneous maintenance and more". VERIFIED (same).
- **Features** (RECALLED; https://www.titanium-software.fr/en/onyx.html):
  - **Maintenance**: verify the startup volume; rebuild LaunchServices, Spotlight and Mail indexes; clean system, user and Internet caches, logs and font caches; periodic scripts on older macOS.
  - **Utilities**: man pages, launcher for hidden Apple apps, checksums.
  - **Files**: visibility, disk images.
  - **Parameters**: hidden Finder/Dock/Safari/screenshot/animation `defaults`.
  - **Info** and a **Log**.
  - Asks for the admin password.
- **Take:**
  - a per-OS capability gate (OnyX ships one build per OS; we use runtime checks);
  - a reversible "Parameters" panel;
  - a visible action log.

  INFERRED.

#### AppCleaner (FreeMacSoft)
- **Version:** 3.7. **Requires macOS 15 Sequoia.** Free. Ships a **SmartDelete** launchd job `net.freemacsoft.AppCleaner-SmartDelete`, which watches for apps moved to the Trash. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/a/appcleaner.rb).
- **Features** (RECALLED): drag an app onto the window to list its related files; protects running and default apps; lists widgets and plug-ins.
- **Take:** the minimal drag-and-drop uninstall flow; an opt-in Trash watcher. INFERRED.

#### Pearcleaner (alienator88), open source
- **Version:** 5.4.3. macOS 13+. Ships a `PearcleanerSentinel` launchd job and a CLI binary. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/p/pearcleaner.rb).
- **Features** (VERIFIED; https://github.com/alienator88/Pearcleaner):
  - App Uninstall; Orphaned File Search; Development Environment Manager; File Search;
  - Homebrew Manager; **App Lipo** (architecture stripping); PKG Manager; Plugin Manager; Services Manager; Apps Updater;
  - translation pruning; **Sentinel Monitor** (auto-clean when apps are trashed, about 2 MB RAM);
  - Finder extension; CLI and deep links; export of bundles and file lists; Steam games; include/exclude folders; adjustable search sensitivity.
- **Requirements:** Full Disk Access plus a Privileged Helper. macOS 13/14/15/26.
- **Licence:** Apache-2.0 **+ Commons Clause** (no monetisation).
- **Status: "On Hold"**: development, issue responses, PR reviews and releases are paused indefinitely. VERIFIED (same).
- (fact-check) **Security history:** CVE-2025-54595 (CVSS 7.3). In 4.4.0–4.5.1 the root `PearcleanerHelper` XPC service accepted **unauthenticated** connections from any local process and exposed a method that ran arbitrary shell commands. Fixed in 4.5.2. VERIFIED (https://github.com/CVEProject/cvelistV5/blob/main/cves/2025/54xxx/CVE-2025-54595.json ; GHSA-gr2j-65fh-8pvc).
- (fact-check) **Impersonation:** the README warns that only itsalin.com is legitimate and links a PSA that "pearcleaner.com" is a fake site pushing macOS malware. VERIFIED (Pearcleaner README).
- **Take:**
  - feature ideas: Homebrew/PKG managers, undo history, sensitivity levels;
  - **bug lessons**: Lipo breaks integrity-checked apps and strips `arm64e`; orphan search over-matches (§4.2 C4/C5).

  INFERRED.

#### Sensei (Cindori)
- **Version:** 2.1.3. **macOS 14+.**
- **Installed components:**
  - launchd jobs `SenseiMonitor` (+ agent) and `SenseiTool`;
  - privileged helper `/Library/PrivilegedHelperTools/org.cindori.SenseiTool`;
  - daemons `SenseiDaemon` and `SenseiHelper`.
- **Its zap list includes `~/Library/Caches/amplitude/org.cindori.Sensei` and `~/Library/Caches/SentryCrash/Sensei`**, which are traces of the Amplitude analytics and Sentry crash-reporting SDKs. (fact-check) It also lists `com.plausiblelabs.crashreporter.data/org.cindori.Sensei`, a PLCrashReporter trace, and a system-wide `/Library/LaunchAgents/org.cindori.SenseiMonitor.plist`.

  VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/s/sensei.rb).
- (fact-check) **Security history:** CVE-2024-7915 (CVSS 7.8), Sensei ≤ 1.5.10. The root helper `org.cindori.SenseiHelper` validated XPC clients by `NSXPCConnection.processIdentifier`. A PID-reuse attack could impersonate the app and call helper methods: arbitrary file delete/write, load/unload daemons, change permissions, load extensions. VERIFIED (https://github.com/CVEProject/cvelistV5/blob/main/cves/2024/7xxx/CVE-2024-7915.json).
- **Features** (RECALLED; https://cindori.com/sensei): dashboard and menu-bar monitor; CPU/GPU/thermals; cleaner; uninstaller; startup-item optimiser; **SSD health (SMART), benchmark, TRIM**; battery health; hardware info. Subscription.
- **Take:** hardware-health depth (SMART, benchmark). A reminder that "pro" utilities commonly embed analytics SDKs (§4.2 C8). INFERRED.

#### BuhoCleaner (Dr.Buho)
- **Not in Homebrew cask.** Only the sibling app BuhoLaunchpad is there. VERIFIED (GitHub code search of `Homebrew/homebrew-cask`: only `Casks/b/buholaunchpad.rb` matches "drbuho").
- Apple's `tccd` built-in annotation list names `S7F733N4B5/com.drbuho.BuhoCleaner` alongside CleanMyMac. VERIFIED-SIB (`10-internals.md` §4).
- **Features** (RECALLED; https://www.drbuho.com/buhocleaner): Flash/Quick Clean; system junk; app uninstaller with leftovers; large files; duplicates; disk-space analyser; startup items; a toolkit (free up RAM, flush DNS, reindex Spotlight, shredder); a menu-bar status monitor. Subscription or lifetime licence.
- (fact-check) **Security history:** CVE-2026-0924, "BuhoCleaner 1.15.2 - Local Privilege Escalation via PID reuse attack". An insecure XPC service let local unprivileged users reach root (CWE-367 TOCTOU, CVSS 4.0 7.3). Published 2026-02-02 by Fluid Attacks (advisory "solstafir"). VERIFIED (https://github.com/CVEProject/cvelistV5/blob/main/cves/2026/0xxx/CVE-2026-0924.json).
- (fact-check) **Other traces:** team ID `S7F733N4B5` (tccd list above). The sibling BuhoLaunchpad cask zaps `~/Library/Caches/SentryCrash/BuhoLaunchpadServer` and needs macOS 15. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/b/buholaunchpad.rb). INFERRED: Dr.Buho uses the Sentry SDK in at least one app, and probably in BuhoCleaner too.
- **Feature list still unverified.** drbuho.com and the App Store were unreachable, and GitHub has only third-party one-liners ("light cleaner, fast scan, Flash Clean"; e.g. https://github.com/JackyLee3362/cs-wiki/blob/main/docs/app/macos/compare-macos-disk-manage.md). VERIFIED-2ND for "Flash Clean" only.
- **Take:** a cheaper CleanMyMac-shaped suite that confirms the "expected" module set. INFERRED.

#### Nektony: MacCleaner Pro and App Cleaner & Uninstaller
- **MacCleaner Pro 4.0.4** installs as a **suite** folder ("MacCleaner 4 Pro"). VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/m/maccleaner-pro.rb).
- **App Cleaner & Uninstaller 10.0.1:** cask description "Uninstaller and cleaning assistant". A container ID `com.nektony.StartupDiskFull` hints at a low-disk helper. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/a/app-cleaner.rb).
- (fact-check) **Funter 7.1.2** (hidden-files tool, with a Finder Sync extension) has its own cask. Its zap list includes the shared group container `8DKG4XB37M.group.com.nektony.MacCleaner-PRO-SIII`, which reveals the team ID `8DKG4XB37M` and the suite's shared data store. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/f/funter.rb). No Nektony CVE in cvelistV5 (code search, 2026-10-12).
- **Features** (RECALLED; https://nektony.com/mac-cleaner-pro , https://nektony.com/mac-app-cleaner):
  - The suite bundles App Cleaner & Uninstaller, Disk Space Analyzer (sunburst), Duplicate File Finder, Memory Cleaner and Funter (hidden files).
  - The uninstaller has remaining-files (orphan) search, app reset, startup-program management, extension management (Safari, QuickLook, Spotlight, preference panes, Internet plug-ins) and a smart-delete Trash watcher.
- **Take:** the most complete **extensions** manager and **app reset** in the category. INFERRED.

#### CCleaner for Mac (Piriform, now Gen Digital)
- **Version:** 2.11.194. Installs via a **.pkg**.
- **Installed components:**
  - **nine launchd jobs**, including `com.piriform.ccleaner.engine.xpc`, `…services.submit`, `…services.xpc`, `…update` and `…uninstall`;
  - a privileged helper `/Library/PrivilegedHelperTools/com.piriform.ccleaner.CCleanerAgent`;
  - `/Users/Shared/CCleaner`.

  VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/ccleaner.rb).
- **Features** (RECALLED; https://www.ccleaner.com/ccleaner-mac): system junk plus browser cleaner; "Health Check" one-click; startup items; large files; duplicates; uninstaller. Freemium.
- **Reputation:**
  - The 2017 supply-chain compromise of CCleaner 5.33 for Windows was discovered by Cisco Talos.
  - Its then-owner Avast was hit by the Jumpshot browsing-data scandal (2020) and an FTC order (2024).

  RECALLED (re-check: https://blog.talosintelligence.com/ , https://www.ftc.gov/).
  - (fact-check) The compromise itself is now VERIFIED. CVE-2017-20201 (CVSS 9.3; assigned 2025 by VulnCheck) covers CCleaner 5.33.6162 and CCleaner Cloud 1.07.3191, which carried an embedded malicious loader. The CVE does not name Talos, so "discovered by Talos" stays RECALLED. https://github.com/CVEProject/cvelistV5/blob/main/cves/2017/20xxx/CVE-2017-20201.json
  - (fact-check) Windows CCleaner had two recent root-equivalent bugs, both lessons for any privileged cleaner or uninstaller:
    - CVE-2025-3025 (7.3): insecure file deletes in the cleaning feature gave SYSTEM.
    - CVE-2026-12410 (7.8): the Uninstaller **followed a symlink/junction** while deleting an app's data folder with elevated rights.

    VERIFIED (cvelistV5). No CCleaner-for-Mac CVE was found.
- **Take:**
  - The job named `services.submit` is very likely a reporting channel. INFERRED.
  - A cautionary tale: users judge cleaners by their **trustworthiness**, and a heavyweight install footprint erodes it.

#### iStat Menus (Bjango)
- **Version:** 7.50.1. **macOS 13+.**
- **Installed components:**
  - launchd `agent`, `daemon`, `installerhelper`, `status` and `notifications`;
  - **`/Library/LaunchDaemons/com.bjango.istatmenus.fans.plist`** for fan control;
  - a widget extension;
  - privileged installer helpers.

  VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/i/istat-menus.rb).
- **Features** (RECALLED; https://bjango.com/mac/istatmenus/): CPU/GPU; memory (including pressure); disks (usage and activity); network (per-interface, public IP, per-app); sensors (temperatures, fans, power); battery and Bluetooth-device batteries; time/world clocks and weather; rule-based notifications; combined or separate menu-bar items; history graphs. One-time purchase or Setapp.
- (fact-check) **Security history:** CVE-2025-11921 (CVSS 8.5). iStat Menus 7.10.4 had an insecure XPC service that let local unprivileged users reach root through command injection (CWE-77 and CWE-732). Published 2025-11-24 by Fluid Attacks (advisory "muse"). The reference points at the 7.10.6 build. VERIFIED (https://github.com/CVEProject/cvelistV5/blob/main/cves/2025/11xxx/CVE-2025-11921.json).
- **Take:** monitoring depth and **rule-based alerts**. Our Menu/Monitor should match this. INFERRED.

#### Stats (exelban), open source
- **Version:** 3.0.21. **macOS 12+.** MIT. Installs an SMC helper daemon `eu.exelban.Stats.SMC.Helper` for sensors and fans. VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/s/stats.rb ; https://github.com/exelban/stats).
- **Modules** (VERIFIED, README): CPU, GPU, memory, disk, network, battery, **fan control** (the README lists it as "Fan's control (not maintained)"), sensors (temperature/voltage/power), Bluetooth devices, multi-timezone clock; desktop widgets.
- **README caveats** (VERIFIED):
  - **Fan control is "legacy mode" and receives no updates or fixes.**
  - Apple-silicon sensors are thermal zones, not per-core readings, and their keys change with each chip.
  - Wi-Fi names need Location Services.
  - The app contacts the developer's server for updates and public-IP lookup.
  - Sensors and Bluetooth are the heaviest modules.
  - On macOS 26 the user must allow the menu-bar icon in System Settings › Menu Bar.
- **Users ask for memory *pressure* rather than "used" RAM** (VERIFIED: https://github.com/exelban/stats/issues/318 , https://github.com/exelban/stats/issues/3234 , https://github.com/exelban/stats/issues/3303).
- **Take:**
  - Reader code for CPU/RAM/battery is reusable under MIT (sibling `05-performance.md` already cites it).
  - Fan control on Apple silicon is a maintenance burden; ship **read-only RPM** first.

  INFERRED.

#### Apple's built-ins
See §3. Apple's Storage settings, XProtect, Login Items & Extensions, Activity Monitor and Software Update. RECALLED, with what we could verify noted.

#### Bonus: open-source and other peers worth knowing (all VERIFIED from their READMEs)

| Project | What it is | Notable for us |
|---|---|---|
| **Mole** (tw93), GPL-3.0, macOS 12+ | CLI: `clean`, `uninstall`, `optimize`, `analyze`, `status`, `purge`, `installer` | `--dry-run` everywhere; whitelists; **op-log** `~/Library/Logs/mole/operations.log` plus `mo history`; purge guards (7-day activity, git-tracked files); symlinks not followed; no sudo unless needed. Self-described as combining CleanMyMac, AppCleaner, DaisyDisk and iStat Menus workflows. https://github.com/tw93/Mole |
| **Mole security audit** | Hard rules learned in production | Protected prefixes `/ /System /bin /sbin /usr /etc /var /private /Library/Extensions`. Refuses caches whose owner is running: **deleting an open SQLite cache made a helper loop writing to unlinked files until the volume filled** (issue #1390). Dock repair removed after it **reset users' wallpaper** (#995, #1300). https://raw.githubusercontent.com/tw93/Mole/main/SECURITY_AUDIT.md |
| **PureMac**, MIT, macOS 13+ | SwiftUI cleaner plus uninstaller | **"No fake urgency"**, "no overpromising". Shows purgeable space but **won't list it as junk**. Comparison table marks CleanMyMac "No" on telemetry-free and "Partial" on Trash support for uninstall. https://github.com/momenbasel/PureMac |
| **Mac Sai**, BSD-3, macOS 14+ (1.8k★) | Open "alternative to CleanMyMac" with 17 modules | SafetyGuard path validation, TOCTOU re-resolve, chunked deletes, an XPC code-signing requirement, 862 tests, **"verify no telemetry yourself"** steps. https://github.com/iliyami/MacSai . (fact-check) Its one-click module is literally called **"Smart Scan"**, CleanMyMac X's module name, and it bills itself as "Every major CleanMyMac tool". That is exactly the naming we avoid (§5.1). VERIFIED (README) |
| **Purge**, MIT, macOS 13+ | Allowlist-only cache cleaner | Unknown paths are **not even shown**; Trash by default; safety page generated from code. https://github.com/jithin-sabu/purge-app |
| **Headroom**, MIT, macOS 14+ | Treemap analyser | Safety labels **Safe / Usually safe / Caution / Never**; staged duplicate hashing; Trash default. https://github.com/Ryware/Headroom |
| **DiskWise**, Apache-2.0 | Trash-only cleaner | Per-session **undo**; **coverage reporting** (what could not be measured); knowledge base explaining each cache. https://github.com/DreamOfXM/diskwise |
| **CleanUp**, MIT | "No snake oil" cleaner | Refuses "Free up RAM" buttons and speed claims for cache clearing. https://github.com/syahrul84/cleanUp |
| **Lighten** (preview, macOS 26+, MIT) | "Honest" cleaner | "At least" sizes when hidden; ownership by bundle ID/signature/receipt; journal plus Undo. https://github.com/tunatavsan/lighten |
| **Latest**, GPL-3.0 | App update checker (Mac App Store plus Sparkle) | Alternative to CleanMyMac's Updater. https://github.com/mangerlahn/Latest |
| **KnockKnock** (Objective-See), GPL-3.0 | Persistence enumerator ("AutoRuns for macOS") | Model for a launch-item audit. https://github.com/objective-see/KnockKnock |
| **GrandPerspective** 3.8.1 (macOS 14+), **OmniDiskSweeper** 1.16, **Disk Inventory X** 1.3 | Disk analysers | Disk Inventory X's cask is **disabled from 2026-09-01: "fails_gatekeeper_check"**, needs Rosetta. Abandoned Intel-only utilities stop working. VERIFIED (casks) |

### 2.2 Feature matrix

**Legend:** ● yes · ◐ partial/limited · — no · ? unknown. Column evidence:
- **V** = verified from README/cask/sibling track.
- **R** = mostly RECALLED (vendor site unreachable). Treat R columns as a starting hypothesis to re-check.

| Feature | CMM 5 (V-SIB) | DaisyDisk (R) | OnyX (R) | AppCleaner (R) | Pearcleaner (V) | Sensei (R) | BuhoCleaner (R) | Nektony suite (R) | CCleaner Mac (R) | iStat Menus (R) | Stats (V) | macOS built-in (R) | Mole CLI (V) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| One-click combined checkup | ● Smart Care | — | ◐ | — | — | ? | ● | ◐ | ● Health Check | — | — | ◐ Recommendations | ◐ |
| User caches/logs | ● | — | ● | — | — | ● | ● | ● | ● | — | — | — | ● |
| System (root) caches/logs | ● helper | — | ● admin | — | — | ? | ? | ? | ● helper (V) | — | — | — | ● sudo |
| Developer junk (Xcode, pkg managers) | ◐ (Xcode in app; dev in CLI) | — | — | — | ◐ Dev Env Mgr | — | ? | — | — | — | — | ◐ "Developer" category | ● |
| Project artifacts purge (`node_modules`…) | ◐ CLI only | — | — | — | — | — | — | — | — | — | — | — | ● |
| Language-file removal | ● | — | — | — | ● | — | ? | — | — | — | — | — | — |
| Universal-binary thinning | ● | — | — | — | ● Lipo | — | ? | — | — | — | — | — | — |
| Mail attachments | ● | — | ? | — | — | — | ? | ? | ? | — | — | ◐ Mail download setting | — |
| Trash bins (incl. external) | ● | ◐ | ● | — | — | ? | ● | ? | ● | — | — | ● auto-empty 30 days | ● |
| Browser privacy cleanup | ● | — | ◐ | — | — | — | ? | — | ● | — | — | ◐ per browser | — |
| Malware scan/removal | ● Moonlock | — | — | — | — | — | — | — | — | — | — | ● XProtect/Remediator | — |
| Real-time protection/persistence monitor | ● ES extension | — | — | — | — | — | — | — | — | — | — | ◐ BTM notifications | — |
| App permissions (TCC) review | ● | — | — | — | — | — | — | — | — | — | — | ● Privacy & Security | — |
| Uninstaller with leftovers | ● | — | — | ● | ● | ● | ● | ● | ● | — | — | ◐ Storage › Apps | ● |
| Orphans of already-deleted apps | ● Leftovers | — | — | — | ● | ? | ◐ | ● | ? | — | — | — | ● |
| Trash watcher → "remove leftovers?" | ● | — | — | ● SmartDelete (V) | ● Sentinel | — | ? | ● | — | — | — | — | — |
| App reset | ● | — | — | — | ? | — | ? | ● | — | — | — | — | — |
| Third-party app updater | ● | — | — | — | ● | — | — | — | ? | — | — | ◐ MAS/Apple only | — |
| Homebrew/PKG management | — | — | — | — | ● | — | — | — | — | — | — | — | ◐ |
| Login/background items | ● | — | ◐ | — | ◐ Services | ● | ● | ● | ● | — | — | ● Login Items & Extensions | ? |
| Extensions/plug-ins manager | ● | — | — | ◐ | ● | — | ? | ● | — | — | — | ● (macOS 15+) | — |
| Maintenance (DNS, Spotlight, LaunchServices…) | ● | — | ● | — | — | ? | ◐ | — | — | — | — | ◐ Disk Utility | ● optimize |
| "Free up RAM" | ● | — | ? | — | — | ? | ● | ● Memory Cleaner | ? | — | — | — (OS manages) | ◐ pressure-gated |
| Purgeable / TM local snapshots | ● | ◐ shows | ? | — | — | — | ? | — | — | — | — | ● automatic | ? |
| Disk map visualisation | ● Space Lens | ● sunburst | — | — | — | ? | ● | ● | — | — | — | — | ◐ TUI explorer |
| Large & old files | ● | ◐ | — | — | ◐ File Search | — | ● | ● | ● | — | — | ● Documents › Large Files | ● |
| Duplicates | ● | — | — | — | — | — | ● | ● | ● | — | — | — | — |
| Similar photos | ● | — | — | — | — | — | ? | ? | — | — | — | — | — |
| Cloud-drive cleanup | ● (iCloud/GDrive/OneDrive 5.2.1; Dropbox 5.3.0, corrected) | ? | — | — | — | — | — | — | — | — | — | ◐ Optimize Mac Storage | — |
| Email (Gmail) cleanup | ● (2026) | — | — | — | — | — | — | — | — | — | — | — | — |
| Shredder | — removed in 5.0; X had it (corrected) | — | — | — | — | — | ? | — | ? | — | — | — (removed 10.11) | — |
| Menu-bar CPU/RAM/disk/network | ● Menu | — | — | — | — | ● | ● | — | ? | ● | ● | ◐ Activity Monitor (not menu bar) | ● TUI `status` |
| Sensors/fans | ◐ | — | — | — | — | ● | ? | — | — | ● + fan control | ● (fan control legacy) | — | ◐ |
| Battery health | ● | — | — | — | — | ● | ? | — | — | ● | ◐ level | ● (n/a on Mac mini) | ● |
| Network speed test | ● | — | — | — | — | — | — | — | — | ? | — | — (`networkQuality` CLI, RECALLED) | — |
| SSD health/benchmark | ? | — | ◐ verify | — | — | ● | — | — | — | ◐ | — | ◐ First Aid | — |
| Hidden settings (`defaults`) | — | — | ● Parameters | — | — | — | — | — | — | — | — | — | — |
| Alerts/notification rules | ● | — | — | — | — | ? | ? | — | ? | ● rules | ◐ | ◐ low-disk | ◐ CPU alerts |
| CLI/automation | ◐ separate CLI | — | — | — | ● | — | — | — | — | — | — | ● (`tmutil`, `mdutil`…) | ● JSON |
| Undo/restore history | ◐ activity log | ◐ Collector | ◐ log | — | ● undo (V-SIB) | — | — | — | — | — | — | ● Trash "Put Back" | ◐ op-log |
| Dry-run/preview | ● review | ● | — | ● | ● | ? | ● | ● | ● | — | — | ● | ● |
| Telemetry | ⚠ analytics (V-SIB); CLI opt-out; 2020 X policy: diagnostics under "legitimate interest", in-app analytics under consent (fact-check, §4.2 C8) | ? | ? | ? | none claimed | ⚠ Amplitude + Sentry traces (V) | ? | ? | ⚠ `services.submit` job (V) | ? | update + public-IP calls (V) | opt-in Apple analytics | none stated |
| Price model | sub / one-time | one-time | free | free | free (no-monetise licence) | sub | sub / lifetime | sub | freemium | one-time | free (MIT) | free | free (GPL) |
| Min macOS (current) | 11+ (Big Sur–27; V-SIB, corrected) | ? | per-OS build (11–27) | **15** | 13 | **14** | ? | ? | ? | 13 | 12 | — | 12 |
| (fact-check) Root-helper CVEs on record (cvelistV5) | 14 (2018–19) | none found | not searched | none found | 1 (2025) | 1 (2024) | 1 (2026) | none found | 0 Mac; 4+ Windows | 1 (2025) | not searched | n/a | not searched |

### 2.3 What is (near-)unique to CleanMyMac in this set

Unique, or only partly matched elsewhere (INFERRED from §2.2):

1. **One integrated checkup** across junk, malware, maintenance and app updates. Competitors do one or two of these.
2. **A malware engine with a real-time monitor.** An Endpoint-Security system extension runs as root (VERIFIED-SIB `10-internals.md`). No other product here ships one. Apple's XProtect is the only built-in equivalent.
3. **Cloud Cleanup:** iCloud Drive, Google Drive, OneDrive and Dropbox. Delete, delete everywhere, or "unsync". (corrected) The 5.2.1 launch notes list only iCloud Drive, Google Drive and OneDrive; Dropbox arrived in 5.3.0 (2025-12-17, per `09-design.md` and `07-clutter.md`). VERIFIED (DevMate 5.2.1 notes, re-read by the fact-check: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html); VERIFIED-SIB for Dropbox.
4. **Email Cleanup (Gmail, 2026).** VERIFIED-SIB (`01-overview.md` §2).
5. **App Permissions:** reviewing TCC grants per app. VERIFIED-SIB.
6. **Smart Insights:** Apple-Intelligence explanations of items. VERIFIED-SIB.
7. **Similar Images plus Duplicates plus Downloads** in one "clutter" area. Gemini, also MacPaw, overlaps.
8. **The Menu:** monitoring plus a network speed test, connected devices and a protection status in one panel.
9. **An ignore list that spans modules**, and a **local activity history**.

**What competitors do better** (INFERRED):
- Map fidelity and speed: DaisyDisk.
- Deep maintenance and hidden settings: OnyX.
- Leftover sensitivity and extension management: Nektony, Pearcleaner.
- Sensor depth and alert rules: iStat Menus.
- Hardware health: Sensei.
- Dry-run, op-log and developer purge: Mole.
- Honesty in copy: PureMac, CleanUp, Lighten.
- Undo journals: DiskWise, Lighten, Pearcleaner.
- Zero telemetry with verification steps: Mac Sai.

### 2.4 Completeness checklist for our clone ("union, but safer")

**P0 = must-have for parity · P1 = "better than CleanMyMac" · P2 = nice-to-have.** All INFERRED.

| Pri | Item | Borrowed idea from |
|---|---|---|
| P0 | Checkup (one-click) limited to **Tier-1 safe** items; everything else goes to review | CMM Smart Care; Headroom "Safe" one-click |
| P0 | Cleanup: user/system caches and logs, Xcode/dev junk, Mail attachments (local copies), Trash bins, iOS backups (review), broken prefs/login items, document versions (review) | CMM; sibling `03-cleanup.md` |
| P0 | Uninstaller + leftovers + orphans + reset + Trash watcher (opt-in) | CMM, AppCleaner, Pearcleaner, Nektony |
| P0 | Updater (Mac App Store, Sparkle, Homebrew casks) | CMM, Latest, Pearcleaner |
| P0 | Login/background items + extensions manager | CMM, Nektony, macOS 15 settings |
| P0 | Maintenance tasks, filtered by OS capability | CMM, OnyX, Mole |
| P0 | Disk map + large/old files + duplicates + similar photos | CMM, DaisyDisk, Headroom |
| P0 | Malware scan (signature/heuristic lite + XProtect status) + persistence audit | CMM, KnockKnock |
| P0 | Privacy cleanup (browsers quit first) + TCC permissions review (read-only, plus deep links) | CMM, Mac Sai |
| P0 | Menu-bar monitor: CPU, **memory pressure**, disk, network, top processes | CMM Menu, Stats, iStat |
| P0 | (fact-check) Root helper that resists the category's recurring CVEs: audit-token code-signing requirement, no PID checks, no shell or arbitrary-path verbs, symlink-safe deletes (P14) | Lessons from CMM X, Sensei, Pearcleaner, iStat Menus, BuhoCleaner, CCleaner CVEs |
| P1 | (fact-check) XProtect / XProtect Remediator version readout, compared with the public SOFA feed | macadmins/sofa, jamf/aftermath (§3.5) |
| P1 | **Undo journal** + Trash-first + permanent delete only for regenerable data | DiskWise, Lighten, Pearcleaner |
| P1 | **Dry-run everywhere** + exportable **operations log** | Mole |
| P1 | **Safety labels with plain-language explanations** on every item (Safe / Usually safe / Review / Never) | Headroom, DiskWise, Purge |
| P1 | **Coverage reporting**: "measured X of Y GB; N folders not readable without Full Disk Access" | DiskWise, Lighten |
| P1 | "Hidden" and "purgeable" shown as their own map segments, never as junk | DaisyDisk, PureMac |
| P1 | Developer **project purge** (7-day rule, git-tracked guard) | Mole, MacPaw CLI |
| P1 | Homebrew and PKG-receipt management | Pearcleaner |
| P1 | Alert rules (low disk, sustained memory pressure, runaway process, thermal) | iStat Menus |
| P1 | Reversible "Parameters" (hidden `defaults`) with one-click revert | OnyX |
| P1 | Zero telemetry + a "verify it yourself" page | Mac Sai |
| P2 | SMART/NVMe health readout + simple read/write benchmark | Sensei |
| P2 | CLI with JSON output; Shortcuts/App Intents | Mole, Pearcleaner deep links |
| P2 | Cloud cleanup (iCloud eviction first; others via File Provider) and Gmail cleanup (own OAuth client) | CMM 5 |
| P2 | Read-only fan RPM and temperatures (no fan control by default) | Stats, iStat |
| P1 | (fact-check) **Duplicate and older copies of apps** (same bundle ID in two places, old versions) plus "Unsupported" (e.g. Intel-only on a Rosetta-less future) | Apple Storage › Applications groups (§3.1) |
| P1 | (fact-check) **iOS firmware/installers** (`.ipsw`) and device backups, as separate review groups | Apple Storage › iOS Files (§3.1) |
| P2 | (fact-check) **GarageBand/Logic sound library** removal, explaining that it can be reinstalled | Apple Storage › Music Creation (§3.1) |
| P2 | (fact-check) Show and toggle Finder's "Remove items from the Trash after 30 days" (`FXRemoveOldTrashItems`) instead of building our own auto-empty | Apple / macOS defaults (§3.1) |

---

## 3. What macOS already does (and how our app should relate to it)

### 3.1 System Settings › General › Storage (macOS 13+)

RECALLED unless marked. Re-check https://support.apple.com/en-us/102624 and on device.

**Layout:**
- A usage bar per volume, coloured by category.
- A **Recommendations** list. Each item has a short explanation and a button:
  - **Store in iCloud**: Desktop & Documents, Photos and Messages in iCloud; keep only recent files locally when space is needed.
  - **Optimize Storage** (corrected): auto-remove Apple TV movies and shows already watched, **and keep only recent Mail attachments** on the Mac when space is needed. Apple's string: "Save space by automatically removing Apple TV movies and TV shows that you've already watched and by keeping only recent email attachments on this Mac when storage space is needed." VERIFIED-2ND (Apple localization glossary for System Information.app, pre-Ventura: https://raw.githubusercontent.com/clindsay3/GlossaryLookup/HEAD/macOS/German/SystemInfoApp.lg). A Ventura+ summary citing Apple's help says the same (https://github.com/zaewc/Lumen/blob/main/docs/research/03-macos-platform.md).
  - **Empty Trash Automatically**: erase items that have been in the Trash for more than **30 days**. VERIFIED-2ND (same glossary, plus Apple's `StorageManagement.framework` glossary). (fact-check) Apple's confirmation text says the setting can be changed "later in Finder preferences". It is the Finder setting stored as `defaults read com.apple.finder FXRemoveOldTrashItems` (bool, default false). VERIFIED-2ND (https://github.com/yannbertrand/macos-defaults/blob/main/docs/finder/fxremoveoldtrashitems.md). Our app can read it and show its state.
  - Older releases also had **Reduce Clutter** ("Review Files"). VERIFIED-2ND (both strings appear in the pre-Ventura glossary). Whether it still exists on 13–26 is unverified.
- (fact-check) **Apple's own category plug-ins.** Apple's private `StorageManagement.framework` ships per-category extensions: `ApplicationsStorageExtension`, `CloudFilesStorageExtension`, `GarageBandStorageExtension` (shown as "Music Creation"), `OtherUsersStorageExtension`, `TrashStorageExtension` and `iOSFilesStorageExtension`. VERIFIED-2ND (https://raw.githubusercontent.com/clindsay3/GlossaryLookup/HEAD/macOS/German/StorageManagement.lg ; glossary version is pre-Ventura and its exact macOS version is unknown). Their strings show:
  - **Applications** groups: App Store, Older Versions, **Duplicates** (extra copies of an app), Unsupported, Other.
  - **iOS Files** groups: Device Backups, iOS Installers (firmware).
  - **Music Creation** removes the GarageBand/Logic/MainStage sound library ("can be removed and reinstalled later").
  - Delete there is **immediate**: "The item will be deleted immediately… You can't undo this action". This is a weakness our Trash-first design improves on (P6).
  - A built-in **low-disk alert**: "Your disk is almost full", with a "Manage…" button.
- A **category list** with sizes and an ⓘ button. Categories include: Applications, Books, Developer, Documents, iCloud Drive, iOS Files, Mail, Messages, Music, Music Creation, Photos, Podcasts, TV, Trash, macOS, System Data, Other Users.

**What the category sheets offer:**
- **Applications**: sort by size or last opened; Delete; "Unsupported" apps.
- **Documents**: tabs Large Files, Downloads, Unsupported Apps, Containers, File Browser; Delete.
- **Developer**: Xcode caches, build products, old simulators/device support.
- **iOS Files**: device backups and firmware.

- (fact-check) A Ventura+ summary that cites Apple's help lists the categories as Applications, Documents (sortable by Last Accessed and Size), iCloud Drive, iOS Files, TV/Music/Books/Podcasts, Mail, Messages, Music Creation, Photos, Trash and Developer. **Other Users & Shared, macOS and System Data are view-only.** VERIFIED-2ND (https://github.com/zaewc/Lumen/blob/main/docs/research/03-macos-platform.md, citing https://support.apple.com/guide/mac-help/change-storage-settings-mchl3d437fbc/mac).

**Deep link:** `x-apple.systempreferences:com.apple.settings.Storage`. (corrected: upgraded from RECALLED to VERIFIED-2ND) Shipping open-source Mac apps use this exact URL: Pearcleaner `MainWindow.swift`, root3nl SupportApp, Raycast extensions. It is also in the Ventura System Settings URL list (https://github.com/bvanpeski/SystemPreferences/blob/main/macos_preferencepanes-Ventura.md), which lists Login Items (`com.apple.LoginItems-Settings.extension`), Software Update (`com.apple.Software-Update-Settings.extension`) and Full Disk Access (`com.apple.preference.security?Privacy_AllFiles`) too. The same page notes that pane IDs can be discovered at runtime from `/System/Applications/System Settings.app/Contents/Resources/Sidebar.plist`. INFERRED: read that plist at launch to validate our deep links on each OS release, falling back to opening System Settings.

**Third-party integration:** apps can plug into Storage Management through a `com.apple.storagemanagement` extension point. VERIFIED-SIB (`06-applications.md`).

**Our stance** (INFERRED):
- Our Cleanup "Overview" mirrors Apple's categories so the numbers are recognisable.
- Each Apple recommendation becomes a **"Use macOS for this"** card with the deep link. We never re-implement "Store in iCloud" ourselves.
- Our "System Data" explainer breaks the opaque bucket into: snapshots, caches, VM/swap, logs, iOS backups, simulator runtimes, Apple Intelligence models (macOS 27).
- Purge's README notes that Apple Intelligence models on macOS 27 can be released through Apple's asset service and re-downloaded. VERIFIED (https://github.com/jithin-sabu/purge-app).

### 3.2 Purgeable space and caches are managed by the OS

- Apple's capacity API separates three numbers: the **available capacity for "important" usage**, the **"opportunistic"** capacity, and the raw available capacity. VERIFIED (https://developer.apple.com/tutorials/data/documentation/foundation/checking-volume-storage-capacity.json). (fact-check) The keys are `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` and `…ForOpportunisticUsageKey`, both macOS 10.13+. VERIFIED (Apple doc JSON).
- The gap between "important" and raw available is a practical estimate of purgeable space that macOS will reclaim on demand. INFERRED (sibling `02-smart-care.md` uses the same formula).
- macOS's cache-delete service frees purgeable data when space is needed. The private `CacheDeletePurgeSpaceWithInfo` interface is documented by open-source projects. VERIFIED-SIB (`05-performance.md` §4, citing pymobiledevice3 and Purge sources).
- **Our stance** (INFERRED):
  - Display purgeable space; never call it junk.
  - Offer only (a) thinning **local Time Machine snapshots** with `tmutil` and (b) an explicit "ask macOS to free purgeable space" action.
  - After the action, report the **measured** before/after delta, not an estimate.

### 3.3 Memory

- Apple's `purge(8)` man page:
  - it forces the **disk cache** to be flushed and emptied;
  - it is meant to approximate a cold-boot buffer cache **for performance analysis**;
  - it **does not affect anonymous memory** allocated through malloc/vm_allocate.

  VERIFIED (https://raw.githubusercontent.com/apple-oss-distributions/system_cmds/main/purge/purge.8).
- Activity Monitor's **Memory Pressure** graph is the right health signal. RECALLED. Stats users have repeatedly asked for pressure instead of "used" (VERIFIED, Stats issues above).
- **Our stance:** see principle P2 (§4.4).

### 3.4 Login items, background items, extensions

- macOS 13+ shows a **"Background Items Added"** notification when an app registers background items. VERIFIED-SIB (`01-overview.md`, https://macpaw.com/how-to/stop-background-items-added-mac).
- System Settings › General › **Login Items & Extensions** has "Open at Login" and "Allow in the Background", plus an Extensions section on macOS 15+. RECALLED.
- Deep link `x-apple.systempreferences:com.apple.LoginItems-Settings.extension`. VERIFIED-SIB (`05-performance.md`).
- `SMAppService` (macOS 13+) registers login items, agents and daemons. A status of `requiresApproval` means the user must approve in Login Items; `openSystemSettingsLoginItems()` opens the pane. (corrected: upgraded) The fact-check read the Apple doc JSON directly: `SMAppService.daemon(plistName:)` and `openSystemSettingsLoginItems()` are macOS 13.0+, and `requiresApproval` means "registered, but the user needs to take action". VERIFIED (https://developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice/opensystemsettingsloginitems().json and siblings).
- **Our stance:**
  - Show every background item with its signer and team ID, code-signature validity, and the launchd plist path.
  - Disable items in user space ourselves. For BTM-managed items, deep-link to Settings rather than fighting the system. Sibling `05-performance.md` §6 has the details.

  INFERRED.

### 3.5 Security built-ins

- XProtect (signature detection), **XProtect Remediator** (periodic scan-and-remove), Gatekeeper and notarization ship with macOS and update silently. RECALLED (Apple Platform Security guide, https://support.apple.com/guide/security/).
- (fact-check) **Where to read versions** (VERIFIED-2ND from admin and forensic tools):
  - XProtect Remediator: `defaults read /Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist CFBundleShortVersionString`. Sources: macadmins/sofa `tool-scripts/XProtectVersionCheck-swiftDialog.sh`; jamf/aftermath `SystemReconModule.swift` (which reads `…/XProtect.app/Contents/version.plist`); the ERNW macOS 26 hardening guide.
  - XProtect signatures: `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist`. On macOS 15+ the primary location is `/private/var/protected/xprotect/XProtect.bundle`, with rules in `Contents/Resources/XProtect.yara` and `XPScripts.yr`. Sources: LETHAL-FORENSICS/macos-collector; Neo23x0/macguard-audit `docs/PLANNING.md`.
  - `XProtect.bundle/Contents/Resources/XProtect.meta.plist` blocks plug-ins by bundle ID/team ID or minimum version (HackTricks Gatekeeper page).
  - The public **SOFA** feed (macadmins/sofa) publishes the latest XProtect versions, so "up to date?" can be checked without Apple's private APIs.
- (fact-check) **macOS Tahoe 26.4 added a Terminal paste warning** against "ClickFix" lures (paste-this-command attacks). It delays and warns before running pasted commands. The SHub "Reaper" build already bypasses it through `applescript://` and Script Editor. VERIFIED-2ND (BleepingComputer, Reddit and The Register summaries mirrored on GitHub, e.g. https://github.com/DevComputaria/RssFeddCollection ; https://github.com/stuartjash/macos-malware-kb/blob/HEAD/families/infostealer/shub-stealer.md).
- **Our stance:**
  - The Protection module shows **XProtect/XProtect Remediator version and last run** and Gatekeeper/SIP/FileVault/firewall status (PureMac does a read-only check of these: VERIFIED, PureMac README).
  - Our own scanner complements Apple's: it does not claim to replace it.

  INFERRED.

### 3.6 Other built-ins to deep-link rather than duplicate

All RECALLED:
- Disk Utility First Aid.
- Spotlight privacy and reindex.
- Software Update (`x-apple.systempreferences:com.apple.Software-Update-Settings.extension`, VERIFIED-SIB `06-applications.md`).
- App Store auto-updates.
- iCloud Drive "Optimize Mac Storage".
- Photos "Optimize Mac Storage".
- Mail "Download Attachments: Recent/None".
- Safari "Clear History…".
- `networkQuality` CLI (network test). (fact-check) Built in since macOS 12 Monterey; `networkQuality -v` prints capacity, responsiveness (RPM) and idle latency. VERIFIED-2ND (e.g. https://github.com/lqhuang/flight-rules/blob/main/macos.md).
- `tmutil`.
- Privacy & Security permission lists.
- (fact-check) Finder › Settings › Advanced › "Remove items from the Trash after 30 days" (`FXRemoveOldTrashItems`, see §3.1).

### 3.7 Mac mini specifics (INFERRED)

- **No internal battery.** Hide all battery panels when IOKit power-source enumeration reports no internal battery. Keep Bluetooth-peripheral batteries.
- **Always on AC.** Maintenance tasks and Spotlight rebuilds need no "plug in first" gating.
- **One fan.** Show RPM and temperatures read-only. Stats documents that Apple-silicon fan control is a legacy, unmaintained path (VERIFIED, Stats README). A fan-control feature would need an SMC-writing root helper, which is extra attack surface. Default: off, or not shipped.
- **Displays:** desktop-class window sizes. CleanMyMac 5 requires at least 1280×800 (VERIFIED-SIB `01-overview.md`).

### 3.8 CleanMyMac feature vs built-in equivalent vs our value-add

| CleanMyMac feature | Built-in equivalent | Our value-add (INFERRED) |
|---|---|---|
| Cleanup › Trash | Empty Trash Automatically (30 days) | Per-volume Trash sizes, external drives, "Put Back" preview |
| Cleanup › caches/logs | OS cache-delete under pressure | Explain each item; age and running-owner guards; measured savings |
| Large & Old files | Storage › Documents › Large Files | Treemap, age filters, duplicate awareness, Quick Look, staged basket |
| Uninstaller | Storage › Applications › Delete; Finder | Leftovers, receipts, launchd jobs, shared-container guard, undo |
| Login Items | Login Items & Extensions | Signer/team ID, plist path, broken-item detection, history |
| Malware Removal | XProtect + Remediator | Persistence audit, notarization/signature status, quarantine view |
| Free Up RAM | macOS memory manager | Pressure display, top consumers, polite Quit; no placebo purge |
| Purgeable space | OS-managed | Snapshot thinning with measured result; honest copy |
| Updater | Software Update / App Store | Sparkle and Homebrew apps, release notes, team-ID-pinned installs |
| Privacy | Per-browser "Clear History" | Cross-browser view, quit-first guard, Recent Items |
| App Permissions | Privacy & Security panes | One table of all TCC grants per app, plus deep links |
| (fact-check) Shredder (X only; removed in 5.0) | None (Secure Empty Trash removed in 10.11) | "Delete immediately" with honest SSD/FileVault copy |
| (fact-check) — | Storage › Applications "Duplicates / Older Versions" | Same, plus bundle-ID evidence and Trash-first removal |

---

## 4. Criticism of CleanMyMac, and the design principles it gives us

### 4.1 Context: the "cleaner" category's reputation

- RECALLED (re-check sources given):
  - Long-standing advice on Apple's community forums and in Mac-press columns warns against "cleaning" utilities in general (https://discussions.apple.com/).
  - MacKeeper's 2015 class-action settlement over alleged deceptive "scareware" scans and its 2015 data exposure shaped user suspicion of the category.
  - CleanMyMac is usually rated better than MacKeeper but inherits the scepticism.
- VERIFIED: a 2016 Monolingual issue records a user being told on Apple's forum that the cleaning tool might be causing system instability (https://github.com/IngmarStein/Monolingual/issues/83).

### 4.2 Criticism catalogue → evidence → principle

Each row gives the criticism, the evidence (with labels), and our rule. The rules are collected as P-numbers in §4.4.

**C1. "Cleaning caches is counterproductive or risky."**
- Evidence:
  - Caches are rebuilt, so the space returns and the next launches are slower. RECALLED (common expert view; e.g. https://eclecticlight.co/).
  - Caches are not always disposable:
    - **urlwatch** kept its state DB in `~/Library/Caches`. CleanMyMac's cleanup removes everything there unless excluded, so users lost tracked-site history; the workaround was adding an exclusion. VERIFIED (https://github.com/thp/urlwatch/issues/416).
    - **Poetry** stores virtualenvs under `~/Library/Caches/pypoetry/virtualenvs`. Users report CleanMyMac periodically wiping them; one broke a running webserver. VERIFIED (https://github.com/python-poetry/poetry/issues/3346).
    - MacPaw itself excludes **Spotify** (offline music lives in the cache) and **Gradle** caches from auto-selection. VERIFIED-SIB (`03-cleanup.md`, https://macpaw.com/support/cleanmymac/knowledgebase/system-junk).
    - **Deleting an open SQLite cache** sent an app's helper into a loop that filled the disk. VERIFIED (Mole audit, issue #1390).
    - A user reported Universal Clipboard breaking after cache cleaning, with Purge and earlier with CleanMyMac. **Unconfirmed**; the maintainer could not reproduce. VERIFIED (https://github.com/jithin-sabu/purge-app/issues/134).
    - (fact-check) **Homebrew, 2018:** CleanMyMac X's cache cleaning removed the whole `~/Library/Caches/Homebrew`, and `brew doctor`/`brew leaves` then failed with `dir_s_mkdir` errors until the folder was recreated. Homebrew fixed its side (PR #5104). VERIFIED (https://github.com/Homebrew/brew/issues/5083).
  - (fact-check) **Apple's contract cuts both ways.** Apple's File System Programming Guide says `Caches` "contains cached data that can be regenerated as needed. Apps should never rely on the existence of cache files", one subfolder per bundle ID. So deleting caches is *permitted*. The costs are rebuild time, re-downloads and apps that break the contract (Homebrew, Poetry, urlwatch, Spotify offline). VERIFIED (https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/MacOSXDirectories/MacOSXDirectories.html).
- Principles: **P1, P3, P5, P6, P15**.

**C2. "'Free Up RAM' is a myth."**
- Evidence:
  - `purge` only empties the disk buffer cache and does not touch anonymous memory. VERIFIED (purge.8).
  - Users want pressure, not "used" RAM. VERIFIED (Stats #318, #3234, #3303).
  - Mole runs `purge` only when memory pressure is already high. A contributor proposing an on-demand version admitted it may be "more reassurance than a real optimization". VERIFIED (https://github.com/tw93/Mole/issues/1309).
  - CleanUp refuses "Free up RAM" buttons, saying purging makes things slower. VERIFIED (https://github.com/syahrul84/cleanUp).
  - CleanMyMac ships "Free Up RAM", and its CLI `optimize ram` claims no sudo. VERIFIED (cleanmymac-cli README).
- Principle: **P2**.

**C3. "Purgeable space claims overpromise."**
- Evidence:
  - PureMac deliberately does not list purgeable space as junk. It says no third-party app can reliably free it and Finder's own figure is inaccurate. Its comparison marks CleanMyMac "No" on "Honest about purgeable space". VERIFIED (https://github.com/momenbasel/PureMac).
  - CleanMyMac added "Free Up Purgeable Space" in 5.0.5. VERIFIED (DevMate 5.x notes).
- Principle: **P4**.

**C4. "Removing language files / thinning universal binaries breaks signed apps."** (corrected: the mechanism)
- (fact-check) **The code signature is not what breaks.** Apple's TN2206 "macOS Code Signing In Depth" (last revised 2016-08-09) says removing files from `.lproj` directories inside `Contents/Resources` does **not** invalidate the signature, though adding or changing files does. Removing a whole architecture slice from a universal binary does **not** invalidate it either. VERIFIED (https://developer.apple.com/library/archive/technotes/tn2206/_index.html, section "Changes That Don't Invalidate a Code Signature").
- What does break, per the evidence below (INFERRED synthesis):
  - apps that verify their own bundle integrity (security tools, Office, some VPNs);
  - vendor updaters and delta patches that expect the original bundle;
  - removing a slice the app actually needs (`arm64e` for Xcode tools);
  - removing the only localization a component loads;
  - over-broad removal outside app bundles (Monolingual's system-wide "?" glyphs).
- Evidence:
  - Monolingual users: OneDrive broken; Office 365 refusing to run; Chrome showing the wrong language; "?" glyphs system-wide after over-removal. VERIFIED (https://github.com/IngmarStein/Monolingual/issues/124 , /194 , /309).
  - Pearcleaner Lipo:
    - breaks integrity-checked apps such as **Little Snitch and AdGuard** (#561);
    - strips **`arm64e`** from Xcode, breaking `xcrun` (#575);
    - "creates unusable apps", e.g. Edge (#564);
    - orphans/lipo "break apps" (#538);
    - translation removal crashed Downie (#355).

    VERIFIED (https://github.com/alienator88/Pearcleaner/issues/561 , /575 , /564 , /538 , /355).
  - CleanMyMac 3 **pre-selected** both groups. VERIFIED-SIB (`02-smart-care.md`, https://tidbits.com/2015/08/28/save-space-and-uninstall-apps-with-cleanmymac-3/).
  - ~~Sealed resources fail `codesign --verify`.~~ (corrected) Contradicted by TN2206 for *removal* of `.lproj` contents and of whole slices. It is true only if files are added or modified, or if a tool rewrites a Mach-O slice instead of dropping it. INFERRED-SIB (`03-cleanup.md` §5.6) is superseded here. Still run `codesign --verify --deep --strict` after any change as a guard, but don't present "breaks the signature" as the reason.
- Principle: **P7**.

**C5. "Leftover/orphan detection over-matches."**
- Evidence:
  - Pearcleaner #538: orphans removed vital parts of Autodesk, CrossOver and Adobe apps. VERIFIED.
  - Lighten requires bundle-ID, signature or receipt evidence: "a similar name is not proof". VERIFIED (https://github.com/tunatavsan/lighten).
- Principle: **P8**.

**C6. "Scan free, pay to clean" upsell and alarmist UX.**
- Evidence:
  - Unlicensed CleanMyMac scans every module but locks cleanup; malware is found but not removed; an "Unlock Full Version" button appears top-right. VERIFIED-SIB (`01-overview.md` §4, https://macpaw.com/support/cleanmymac/knowledgebase/editions , …/installation-activation).
  - 5.6.0 added a Notification Center that carries "product news, offers". VERIFIED-SIB (https://macpaw.com/cleanmymac/whats-new).
  - PureMac's promise: no dramatised "47 GB of junk detected!", no red alarm counters, no "your Mac is at risk". VERIFIED (PureMac README).
- Principles: **P9, P10**.

**C7. Background agents, nags and notifications.**
- Evidence:
  - CleanMyMac installs a HealthMonitor, Menu, root Agent and Updater LaunchAgent (VERIFIED, cask). The sibling track reports the Updater wakes every **6 h** (VERIFIED-SIB `10-internals.md` §1).
  - macOS shows "Background Items Added". VERIFIED-SIB.
  - The HIG says to let people, not the app, decide whether a menu bar extra appears, and not to rely on it as the only access point. VERIFIED (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/the-menu-bar.json).
  - App Review 4.5.4: no promotional push notifications without explicit opt-in. VERIFIED (https://developer.apple.com/app-store/review/guidelines/).
- Principles: **P11, P12**.

**C8. Telemetry and privacy.**
- Evidence:
  - CleanMyMac analytics go to `api-lytics.macpaw.com`. VERIFIED-SIB (`10-internals.md` §9).
  - The CLI's analytics can be disabled in `config`, but the wiki does not say what is collected or the default. VERIFIED (cleanmymac-cli wiki; re-read by the fact-check).
  - (fact-check) **What the CleanMyMac X privacy policy said (version "Updated Sep 04, 2020"; data controller MacPaw Inc.):**
    - Under **legitimate interest**, i.e. not opt-in: crash and diagnostic logs, including "cleanup logs: files path and size", plus device information. The device information covers OS, IP, CMM version, RAM/disk/GPU info, "files metadata", "applications preferences data", "installed applications", "network names and preferences" and uptime.
    - Under **consent**: in-app analytics events, and the list of installed apps (only for users who installed after 10 May 2019).
    - Users can object by emailing support@macpaw.com.

    VERIFIED-2ND (ToS;DR corpus mirror: https://github.com/sonu-gupta/tosdr-terms-of-service-corpus/blob/HEAD/corpus/text/MacPaw_Privacy%20Policy.txt). This is a 2020 snapshot for CleanMyMac X. The current CleanMyMac 5 policy (https://macpaw.com/legal/cleanmymac-privacy-policy) was not reachable, and neither was the GUI location of the analytics toggle. A weak replica in `04-protection.md` shows an "Analytics" Settings tab.
  - INFERRED: the gap between "diagnostics under legitimate interest" and "analytics under consent" is the core criticism. Our app collects neither (P13).
  - Open-source rivals list "No telemetry" as a headline feature, and Mac Sai and PureMac mark CleanMyMac as having telemetry. VERIFIED (READMEs).
  - Sensei bundles Amplitude/Sentry traces and CCleaner a `services.submit` job. VERIFIED (casks).
- Principle: **P13**.

**C9. Past security vulnerabilities in the privileged helper.**
- Evidence:
  - The **official CVE records** list 13 CVEs in CleanMyMac X **4.04**:
    - CVE-2018-4032, -4033, -4034, -4035, -4037, -4041, -4042, -4043, -4044, -4045, -4047: local user can "modify the file system as root";
    - CVE-2018-4036: modify running kernel extensions;
    - CVE-2018-4046: DoS, terminating the privileged helper.

    (corrected) Talos reports TALOS-2018-0705…0710 and 0715…0721; 0711–0713 are unrelated Atlantis Word Processor bugs. CWE-20 (Improper Input Validation). Scores differ by source:
    - The **CNA (Talos) score in the official CVE record is CVSS 3.0 7.1 High**: `AV:L/AC:L/PR:N/UI:N/S:C/C:N/I:H/A:N`. Talos scored even the DoS (4046) 7.1.
    - The **NVD-derived score mirrored in the GitHub advisories is 5.5 Moderate**: `AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:N`.

    VERIFIED (https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4032.json ; https://raw.githubusercontent.com/github/advisory-database/main/advisories/unreviewed/2022/05/GHSA-5jv4-7vh6-9xcq/GHSA-5jv4-7vh6-9xcq.json). Published 2019-01-10.
  - **CVE-2019-5011 (4.20):** the upgrade **failed to remove the old vulnerable helper** (CWE-459). VERIFIED (https://github.com/advisories/GHSA-8xx8-72q4-m3hg , TALOS-2019-0759).
  - Root cause: generic helper primitives (`moveItemAtPath`, `removeItemAtPath`, `truncateFileAtPath`, `removeLaunchdAgentAtPath`…) with **no caller validation**. Patched 2018-12-27. VERIFIED-SIB (`02-smart-care.md` §9, `01-overview.md`).
  - **No CleanMyMac 5 CVEs** appear in cvelistV5 as of 2026-10-12 (code search for "CleanMyMac" / "Clean My Mac" returns only these 14). VERIFIED. (fact-check) Re-run on 2026-10-12: "CleanMyMac" gives 7 hits and "Clean My Mac" 14, all the same 2018/2019 set. A search for "MacPaw" finds only other products: The Unarchiver < 4.3.6 (CVE-2023-46270) and the XADMaster library (CVE-2024-22405), both **missing quarantine attributes on extracted files**, which lets them slip past Gatekeeper; and Encrypto for Windows (CVE-2021-47863). INFERRED lesson: if our app ever extracts archives or downloads updates, it must propagate `com.apple.quarantine`.
  - Peer risk: Pearcleaner's helper runs arbitrary `/bin/bash -c` as root, gated only by a code-signing check. VERIFIED-SIB (`06-applications.md`). (fact-check) Before 4.5.2 it had **no** check at all (CVE-2025-54595, see §2.1).
  - (fact-check) **Category-wide pattern** (VERIFIED, cvelistV5):

    | Product | CVE | Root cause |
    |---|---|---|
    | CleanMyMac X 4.04 / 4.20 | 2018-4032…4047, 2019-5011 | Generic file primitives with no input validation; stale helper left after upgrade |
    | Sensei ≤ 1.5.10 | 2024-7915 | Client check by `processIdentifier` → PID reuse |
    | Pearcleaner 4.4.0–4.5.1 | 2025-54595 | No client check; shell-exec method |
    | iStat Menus 7.10.4 | 2025-11921 | Command injection; bad permissions (CWE-77/732) |
    | BuhoCleaner 1.15.2 | 2026-0924 | PID-reuse TOCTOU (CWE-367) |
    | CCleaner (Windows) | 2025-3025, 2026-12410 | Privileged deletes that follow links |

    Each one is a rule in P14.
- Principle: **P14**.

**C10. "Shredder / secure erase is false comfort on SSDs."**
- Evidence:
  - Apple removed Finder's Secure Empty Trash in OS X 10.11 because it improperly deleted files, readable on flash media (CVE-2015-5901). VERIFIED (https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2015/5xxx/CVE-2015-5901.json).
  - ~~CleanMyMac still offers a Shredder.~~ (corrected) CleanMyMac X had a Shredder. It was **removed in CleanMyMac 5.0**, and the X Mac App Store edition never had one. VERIFIED-SIB (`01-overview.md` §5.2, citing https://thesweetbits.com/?p=8100 and Macworld; `03-cleanup.md`; `07-clutter.md`). So this criticism applies to X and to rivals, not to the current product. Our "Delete immediately" tool (P16) goes beyond CleanMyMac 5 while keeping honest SSD copy.
  - (fact-check) Overwriting tools also leak metadata. CCleaner (Windows) 3.26–5.02 wrote the filenames to disk while wiping (CVE-2015-3999). VERIFIED (cvelistV5).
- Principle: **P16**.

**C11. Obsolete or placebo maintenance.**
- Evidence:
  - "Repair Disk Permissions" survives in CleanMyMac's list. Only the undocumented `diskutil resetUserPermissions` remains on modern macOS. Mac Sai removed its version after failures. VERIFIED-SIB (`05-performance.md` §4.6).
  - Mole removed its Dock repair after it reset wallpapers. VERIFIED (Mole audit).
  - CleanMyMac itself filters tasks by OS: an X build listed only 7. VERIFIED-SIB.
- Principle: **P17**.

**C12. Protection overreach and politicised flags.**
- Evidence:
  - CleanMyMac X 4.10.4 added an Uninstaller group **"Suspicious"** for apps associated with or owned by Russian or Belarusian developers. 4.10.3 stopped sales in RU/BY. A Ukrainian theme was added, with an off-switch in Preferences. VERIFIED (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html).
  - This is a values choice by a Kyiv-founded company. For a neutral utility, flags must be **evidence-based** (signature, notarization, behaviour, known-bad hash), not developer nationality. INFERRED.
- Principle: **P18**.

**C13. App Store edition limits.**
- Evidence:
  - The sandboxed edition lacks System cache/log files, Language Files, Universal Binaries, Broken Login Items, Deleted Users and iOS backups.
  - It has no real-time protection, restricted Safari/Wi-Fi/permissions items, no App Store or macOS updates in Updater, and no Leftovers.
  - It **cannot delete App Store app binaries** (reset only).

  VERIFIED-SIB (`01-overview.md` §4.3, `06-applications.md`, https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features).
- App Review 2.4.5 bans root escalation, auto-launch without consent and non-MAS update mechanisms for MAS apps. VERIFIED (App Review Guidelines).
- Principle: **P19**.

**C14. Impersonation and fake downloads.**
- Evidence:
  - Pearcleaner warns that only its official site is legitimate and other download sites may be scams. VERIFIED (Pearcleaner README).
  - ~~Fake CleanMyMac sites… 2024–2025 with AMOS/"SHAMOS" lures~~ (corrected). The re-sourced record:
    - **Cthulhu Stealer** (first seen late 2023; analysed by Cado Security; AMOS-like, written in Go, sold as malware-as-a-service at $500/month). It was distributed as an **unsigned DMG impersonating CleanMyMac** (also GTA IV and Adobe GenP), used `osascript` to phish the login and MetaMask passwords, and staged loot in `/Users/Shared/NW`. XProtect coverage: none listed. VERIFIED-2ND (https://github.com/stuartjash/macos-malware-kb/blob/HEAD/families/infostealer/cthulhu-stealer.md).
    - **SHub Stealer** (Malwarebytes, published 2026-03-06). The fake site `cleanmymacos[.]org` told visitors to paste a base64 "install" command into Terminal (ClickFix). It skipped Russian-keyboard (CIS) machines; stole Keychain, browser, Telegram and wallet data; backdoored desktop wallets; and persisted as `~/Library/LaunchAgents/com.google.keystone.agent.plist` → `~/Library/Application Support/Google/GoogleUpdate.app`, beaconing about every 60 s. XProtect now detects it (`XProtect_MACOS_OSASCRIPT_TABUPA` in `XPScripts.yr`). The May 2026 "Reaper" build moved to WeChat/Miro lures and `applescript://` to bypass the macOS 26.4 Terminal warning. VERIFIED-2ND (https://github.com/stuartjash/macos-malware-kb/blob/HEAD/families/infostealer/shub-stealer.md ; https://github.com/bobby-tablez/TTP-Threat-Feeds/blob/HEAD/results/2026/03/20260308-231836-malwarebytes-shub-stealer.yml ; primary: https://www.malwarebytes.com/blog/threat-intel/2026/03/fake-cleanmymac-site-installs-shub-stealer-and-backdoors-crypto-wallets, not reachable).
    - **SHAMOS** (CrowdStrike, Aug 2025; an AMOS variant run by COOKIE SPIDER) used **fake macOS help/troubleshooting pages** and spoofed GitHub repos (e.g. iTerm2), not CleanMyMac lures, as far as the KB records. VERIFIED-2ND (https://github.com/stuartjash/macos-malware-kb/blob/HEAD/families/infostealer/shamos.md).
  - INFERRED: impersonation of *popular cleaner brands* is an active malware vector (CleanMyMac, Pearcleaner). Our app must never ask users to paste Terminal commands, and must have one canonical download location and a signed update feed.
- Principle: **P20**.

**C15. "One big button" over-automation.**
- Evidence:
  - Lighten's README criticises cleaners that "promise gigabytes of 'junk'" behind a single button. VERIFIED (Lighten README).
  - CleanMyMac 5 auto-selects "all types" except listed exceptions. VERIFIED-SIB (`03-cleanup.md`).
- Principles: **P1, P5**.

**C16. Permanent deletion without undo.**
- Evidence:
  - PureMac rates CleanMyMac "Partial" on Trash support for app uninstalls. VERIFIED (PureMac README).
  - DiskWise, Lighten and Pearcleaner provide undo journals. VERIFIED (READMEs; Pearcleaner via `06-applications.md`).
- Principle: **P6**.

**C17. Inflated or ambiguous sizes.**
- Evidence:
  - Lighten reports "at least" when hidden.
  - DiskWise reports coverage.
  - Headroom shows allocated vs logical size.

  VERIFIED (READMEs).
- APFS clones and hard links can double-count. INFERRED-SIB (`03-cleanup.md`).
- Principle: **P21**.

**C18. Unverifiable performance claims.**
- Evidence:
  - App Review 2.3.1: no promoting services the app doesn't actually offer.
  - 1.1.6: no "false information and features".
  - 2.3: metadata must reflect the core experience.

  VERIFIED (App Review Guidelines).
- Principle: **P10**.

**C19. Scheduled unattended cleaning.**
- Evidence:
  - PureMac admits its scheduled auto-clean can permanently delete unattended. VERIFIED (PureMac README).
  - CleanMyMac's consumer app documents reminders, not auto-runs. VERIFIED-SIB (`02-smart-care.md` §6).
- Principle: **P22**.

**C20. (fact-check) "Notarized by Apple" sold as a trust badge.**
- Evidence:
  - A MacPaw display ad reads "Make sure you can trust your Mac. Notarized by Apple. Get CleanMyMac X". VERIFIED-2ND (an ad-creative dataset on GitHub: https://github.com/deanandreakis/model/blob/main/ads_creative_text_sample.csv).
  - Notarization is an automated malware scan plus a ticket. It is not an Apple review or endorsement of what the app does: the cleaners in C9 were all notarized while shipping root-exploitable helpers. INFERRED (Apple's notarization docs were not re-fetched).
- Rule (INFERRED, folds into P10): never imply Apple endorsement. If we mention notarization, say what it is ("scanned by Apple for known malware").

### 4.3 What critics say CleanMyMac does well, so we keep it

INFERRED, from the verified facts above:
- **A safety database with app-specific exceptions** (Spotify, Gradle) and system apps hidden from the Uninstaller by default.
- **Review before clean**; the CLI requires confirmation, and `--force` is explicit.
- An **ignore list everywhere**.
- **Quit-the-browser-first** for privacy cleaning.
- Polished, accessible UI: VoiceOver and Reduce Motion since 5.0.7 (VERIFIED, DevMate 5.x notes).
- **Notarized** Developer-ID builds. PureMac's and Mac Sai's comparisons both mark CleanMyMac "notarized: Yes" (VERIFIED, READMEs).

### 4.4 Design principles for our safer clone (P1–P22)

Each principle comes with a testable acceptance rule. All INFERRED, derived from §4.2.

1. **P1 · Tiered selection.**
   - Every item has a tier: **Safe** (auto-selectable), **Usually safe**, **Review** (never pre-selected), **Never** (not shown or locked).
   - The one-click checkup acts on Safe only.
   - *Test:* a checkup run on a fixture home never removes a Review or Never item.
2. **P2 · No placebo RAM button.**
   - Show memory pressure (green/yellow/red), swap and compressed memory, plus top consumers with a polite Quit.
   - "Flush file cache (`purge`)" exists only under Advanced. It is enabled only at sustained warn/critical pressure, and its copy says it empties the disk cache, not app memory.
   - *Test:* the UI never displays "RAM freed: X GB" as a benefit.
3. **P3 · Space, not speed.**
   - All cache copy says "reclaim disk space; apps will rebuild these".
   - No "speeds up your Mac" claims anywhere.
4. **P4 · Purgeable honesty.**
   - Purgeable space is a separate segment.
   - Actions are limited to snapshot thinning and an explicit "ask macOS to release" step.
   - Report only the **measured** delta.
5. **P5 · Exceptions DB + running-owner guard.**
   - Signed, versioned rules ship with app-specific exceptions: Spotify `PersistentCache`, Gradle `modules-2`, Poetry `virtualenvs`, urlwatch, JetBrains, Playwright browsers, `ms-playwright`, and more.
   - Skip any cache whose owning bundle is running, or whose liveness can't be determined.
   - Probe SQLite `-wal`/`-shm` families with `lsof` before removal (Mole's tri-state rule).
   - Minimum age (e.g. 24 h, per category).
6. **P6 · Trash-first + undo journal.**
   - User-visible items, app bundles, leftovers and duplicates go to Trash (`FileManager.trashItem(at:resultingItemURL:)`, macOS 10.8+, VERIFIED Apple doc JSON; keep the returned URL for Undo) in a timestamped folder, with an undo history.
   - Permanent unlink only for regenerable caches/logs/temp, after confirmation.
   - Every action is appended to a local op-log.
7. **P7 · Bundle modification is opt-in, seal-aware and reversible.**
   - Language Files and Universal Binaries are **unchecked by default** and **hidden behind Advanced**.
   - Skip these apps:
     - Apple-signed apps;
     - Mac App Store apps;
     - ~~apps with sealed resources~~ (corrected: per TN2206, removing `.lproj` files or whole slices does not break the seal, so "sealed" is not a skip reason on its own);
     - apps on a deny-list of integrity-checking tools (Little Snitch, AdGuard, security/VPN/EDR clients, Xcode, Office, Adobe, Autodesk);
     - apps that update themselves with delta patches (Sparkle deltas, Microsoft AutoUpdate). INFERRED: thinning can make the next update fail;
     - running apps.
   - **Never drop `arm64e`.** Keep all ARM64-family slices.
   - Only **remove** files or whole slices; never rewrite or add files inside a bundle (that *does* break the signature, per TN2206).
   - Work on a staged copy, run `codesign --verify --deep --strict` as a guard, swap atomically, and keep a backup until the next launch succeeds.
   - Requires the App Management permission (macOS 13+).
8. **P8 · Evidence-based leftovers.**
   - Default-select a leftover only with hard evidence: exact bundle ID, team ID in a container name, a package receipt, or a launchd plist `Program` path into the bundle.
   - Name-similarity matches stay unchecked, labelled "possible match".
   - A shared-container guard ("Shared with <App>") applies.
9. **P9 · No paywall, no "unlock", no offers channel.**
   - A personal build has no licensing code at all.
   - No in-app inbox for promotions.
10. **P10 · Neutral language and numbers.**
    - No red alarm counters, countdowns or "your Mac is at risk".
    - Severity colours are reserved for real conditions: disk below 10 %, critical memory pressure, a confirmed malware hash.
    - Numbers are labelled "estimated" until measured.
11. **P11 · Zero background presence by default.**
    - Nothing runs in the background after quit unless the user enables the Monitor, the Trash watcher or scheduled reminders.
    - Each component is listed in Settings with a toggle and its macOS Login-Items status.
    - Self-uninstall unregisters every `SMAppService` and removes the helper **before** trashing the app.
12. **P12 · Notifications are opt-in, per type, actionable and never promotional.**
    - Types: low disk, sustained pressure, runaway process, threat found, app trashed → offer leftovers, app updates.
    - Each type has a threshold and an off switch.
13. **P13 · Zero telemetry, verifiable.**
    - The only network calls: an optional update check, the user-triggered updater feeds, optional user-initiated cloud or Gmail APIs, and an optional speed test.
    - Ship a "Network & Privacy" page listing every endpoint, plus `lsof`/`nettop` verification steps (as Mac Sai does).
14. **P14 · Hardened privileged helper.**
    - Intent-level XPC API only. Examples: `flushDNS()`, `thinSnapshots(bytes:)`, `removeSystemCaches(ruleIDs:)`, `removeLaunchDaemon(label:)`. Never `remove(path:)` or `runShell`.
    - The listener enforces a **code-signing requirement** on the client: `NSXPCListener.setConnectionCodeSigningRequirement(_:)`, macOS 13.0+ (corrected: upgraded from RECALLED to VERIFIED, https://developer.apple.com/tutorials/data/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:).json). There is also a per-connection `NSXPCConnection.setCodeSigningRequirement(_:)`, macOS 13.0+ (VERIFIED, Apple doc JSON). Pin the requirement to our team ID and bundle ID.
    - (fact-check) **Never authorise by PID.** Never use `processIdentifier` and then `SecCodeCopyGuestWithAttributes(pid)` or a path lookup. That exact pattern was CVE-2024-7915 (Sensei) and CVE-2026-0924 (BuhoCleaner). If a manual check is unavoidable, use the connection's **audit token**.
    - (fact-check) **No unauthenticated listener, ever.** No method that takes a command string or argv (CVE-2025-54595 Pearcleaner; CVE-2025-11921 iStat Menus). Helper files and sockets get root-only permissions (CWE-732 in iStat Menus).
    - The helper re-derives and re-validates every path (`realpath`, no symlink following, allow-listed roots, deny-list of protected prefixes). (fact-check) Open with `O_NOFOLLOW` / `openat`-relative walks, so a link swapped in mid-operation can't redirect a root delete. Windows CCleaner's CVE-2026-12410 was exactly this bug, in its uninstaller.
    - Version handshake; **on upgrade, unregister and remove any older helper binary** (the CVE-2019-5011 lesson).
    - Rate limiting and a full audit log.
    - Registered with `SMAppService.daemon`.
15. **P15 · Respect app data locations.**
    - Never wipe whole `~/Library/Caches`. Remove per-bundle subfolders only, matched by rules.
    - Never touch `~/Library/Application Support`, Group Containers, keychains, Mail/Messages/Photos libraries, iCloud Drive or SSH keys in cleanup flows (Lighten's protected list).
16. **P16 · Honest "Delete immediately".**
    - The Shredder becomes **Delete immediately (skip Trash)**. Its copy explains that on SSD/APFS, overwriting cannot guarantee unrecoverability, and recommends FileVault.
    - No multi-pass "military-grade" modes.
17. **P17 · Capability-filtered maintenance.**
    - Show a task only if the OS supports it and it has a measurable effect.
    - Each task explains what it runs: the exact command, whether it needs root, and how long it takes.
    - No "Repair Disk Permissions". Instead, "Check home-folder permissions" runs only when a real ownership problem is detected (sibling `05-performance.md`).
18. **P18 · Evidence-based threat flags.**
    - A flag must cite one or more of: a known-bad hash or signature rule, revoked or invalid code signature, unsigned/un-notarized plus persistence, or suspicious launchd configuration.
    - Never flag by developer nationality or company.
    - Show the evidence in the item's detail view.
19. **P19 · Direct distribution, graceful degradation.**
    - Build as a non-sandboxed Developer-ID or ad-hoc personal app.
    - Each feature declares what it needs: Full Disk Access, App Management, admin/helper, Automation.
    - Without a permission, the feature shows "partially available" with a fix-it deep link rather than failing silently.
20. **P20 · Distinct identity, trusted updates.**
    - Our own name, icon and look (§5).
    - Signed and notarized when distributed.
    - Sparkle EdDSA-verified updates.
    - Never instruct users to paste Terminal commands from a website. (fact-check) Fake-CleanMyMac malware (SHub, 2026) relied on exactly that (§4.2 C14).
    - Updater installs only when the **team ID matches** the installed app.
21. **P21 · Accurate sizes.**
    - Use allocated size (`totalFileAllocatedSize`; the key is `URLResourceKey.totalFileAllocatedSizeKey`, macOS 10.7+, VERIFIED Apple doc JSON); de-duplicate hard links and clones.
    - Say "at least" when coverage is partial, and show a coverage meter.
22. **P22 · Scheduling = reminders + Safe tier only.**
    - Scheduled runs may only clean Safe items, above a size threshold, never while the user is active.
    - Each run writes to the op-log and posts a summary.
    - Anything else is a reminder only.

---

## 5. Legal guardrails for a functional clone

> **Not legal advice.** Engineering checklist only. Doctrine notes are RECALLED and simplified. A personal build that is never distributed carries far less risk, but **this repo lives on GitHub**, so plan as if the code might become public.

### 5.1 Trademarks (names, logos, slogans)

**What is protected** (RECALLED; check USPTO TESS https://tmsearch.uspto.gov/ and EUIPO eSearch https://euipo.europa.eu/eSearch/ before choosing a name):
- MacPaw's product and brand marks: **CleanMyMac**, **CleanMyMac X**, **MacPaw**, **Moonlock**, likely **Setapp** and **Gemini** (the duplicate finder).
- Distinctive feature names should be treated as brand-like even if unregistered: **Smart Care**, **Space Lens**, **My Clutter**, **Smart Insights**, **Health Monitor**, and also **Smart Scan**, CleanMyMac X's checkup name.
- The EULA asserts copyright and trademark protection over the software. VERIFIED (https://github.com/MacPaw/cleanmymac-cli, LICENSE file).
- (fact-check) Registration status is still **unverified**: USPTO, EUIPO and macpaw.com were unreachable, and GitHub code search found no registration numbers for "Smart Care", "Space Lens", "My Clutter" or "Moonlock". MacPaw's site footer (2020 snapshot) links a dedicated **"Trademarks"** page, so MacPaw actively asserts marks. VERIFIED-2ND (ToS;DR corpus copy of the MacPaw privacy page, navigation section). Treat every MacPaw feature name as claimed.

**Rules:**
- Don't use any of these marks in our app name, bundle ID, icon, window titles, sounds, domain or repo name.
- Don't use a confusingly similar coinage ("CleanMyMini", "MyMacClean", "CleanMac…", "MacCleanse").
- The test is likelihood of confusion: similar sound/look/meaning plus related goods (RECALLED). Utility software is the same class of goods, so similarity alone is risky.

**Generic feature labels are fine.** Examples: System Junk, Caches, Logs, Trash, Uninstaller, Updater, Leftovers, Large & Old Files, Duplicates, Privacy, Malware Removal, Login Items, Maintenance, Menu-bar monitor. These describe functions (INFERRED). For a distinct voice we may still pick our own wording, e.g. "Checkup", "Space Map", "Clutter", "Toolbox" (sibling `01-overview.md` §13).

**Correction to a sibling suggestion:** `01-overview.md` §13 maps Smart Care → "Smart Scan". That name was CleanMyMac X's own module (VERIFIED-SIB `02-smart-care.md` title and §1 item 10: "Smart Scan (CleanMyMac X, 2018–2024)"). **Use "Checkup" instead.** INFERRED.

**Nominative or comparative use is OK in docs**, e.g. "an independent alternative to CleanMyMac", "imports nothing from CleanMyMac":
- Use only as much of the mark as needed (word only, no logo).
- Add a non-affiliation disclaimer: "CleanMyMac is a trademark of MacPaw Way Ltd. This project is not affiliated with or endorsed by MacPaw."
- RECALLED (US nominative fair use; EU "referential use" under the Trade Mark Directive).

**Apple marks** (RECALLED; re-check https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html):
- Don't put "Mac", "macOS", "Apple" or an Apple logo in the **product name** or icon.
- Descriptive compatibility phrases such as "for macOS" or "for Mac" in body text are acceptable.
- App Review 4.1(c): "You cannot use another developer's icon, brand, or product name in your app's icon or name, without approval". VERIFIED (App Review Guidelines).

**Repo hygiene (action item):**
- The repository is named **`CleanMyMac-s`** (`mitmi/cleanmymac-s`) and the README title is "CleanMyMac-s" (VERIFIED, local `README.md`).
- **Rename the repo and README to the new app name before any public release.** Keep "CleanMyMac" only in a research or disclaimer context.
- Use our own reverse-DNS **bundle IDs**, never `com.macpaw.*`. Never reuse MacPaw's team ID, URL schemes, Mach-service names or launchd labels (e.g. `com.macpaw.CleanMyMac5.Agent`).

**Name selection checklist** (INFERRED):
1. Coined or arbitrary word, not descriptive of "clean + Mac".
2. No conflict in USPTO/EUIPO classes 9 and 42.
3. No identical Mac App Store or Setapp app name.
4. Domain and GitHub org available.
5. Not similar to a competitor: DaisyDisk, OnyX, Pearcleaner, Sensei, Buho, Mole, Stats, iStat.

Sibling candidates ("Kempt", "Spruce", "Tidewater", "Mintleaf", "Brisk Care") **still need this clearance**. So does the design track's codename "Prism" (`09-design.md` §6). "Prism" is a very common software name, so as a product name it carries high conflict risk.

### 5.2 Copyright (code, art, icons, sounds, text, data)

**Code.**
- Write all code ourselves, or reuse permissively licensed OSS with notices (§5.6).
- **Do not decompile, disassemble or extract CleanMyMac binaries or resources.** MacPaw's EULA forbids copying, modifying, creating derivative works or **reverse engineering** without consent. VERIFIED (cleanmymac-cli LICENSE; the desktop app's EULA is RECALLED to be similar).
  - (fact-check) The CLI EULA's other terms:
    - the licensor is **MacPaw Way Ltd.** (registration no. 428214, Limassol, Cyprus);
    - Cyprus law and courts govern, unless the user's local law requires otherwise;
    - liability is capped at **US$50**;
    - there is a class-action waiver;
    - it states that rights under the CleanMyMac (desktop) agreement do not carry over to the CLI, and vice versa.

    VERIFIED (https://raw.githubusercontent.com/MacPaw/cleanmymac-cli/HEAD/LICENSE). The 2020 CleanMyMac X privacy policy instead named **MacPaw Inc.** as data controller (VERIFIED-2ND, §4.2 C8). The legal entity has changed over time.
- Interoperability exceptions (EU Software Directive art. 6, US §1201(f)) are narrow and do not cover building a competing product from extracted expression. RECALLED.
- **Clean-room note:** sibling tracks cite "VERIFIED-BIN"/"VERIFIED-OSS" observations made from MacPaw bundles found in third-party GitHub repos: `strings` on a CleanMyMac 3 bundle, an `assetutil` teardown of a 5.5.4 MAS bundle (`10-internals.md` §0, `09-design.md` §0).
  - Treat these strictly as **behavioural background**.
  - Do **not** import any extracted asset, string table, knowledge-base row, rule file, palette value list or class/protocol name into our code.
  - Implement from public platform documentation and our own observations.
  - INFERRED.

**Illustrations, icons, 3D hero renders, animations.** These are protected artistic works. Don't trace, recolour or "re-render" them, including:
- the module hero objects;
- the **pink iMac-with-squeegee** app-icon motif (VERIFIED-SIB `09-design.md`);
- the circular gradient category badges.

Commission or create original art. INFERRED.

**Apple's own restrictions also apply:**
- The HIG prohibits SF Symbols, or confusingly similar images, in **app icons, logos or any trademarked use**. VERIFIED (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sf-symbols.json).
- **Don't replicate Apple hardware** in icons. Apple products "are copyrighted and can't be reproduced in your app icons". VERIFIED (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/app-icons.json).
- So a stylised Mac/iMac icon is out on two counts. Pick a non-computer motif. INFERRED.
- SF Symbols **inside** the UI (sidebar, buttons) are fine. Apple-product symbols can be displayed but not customised. VERIFIED (same HIG page).

**Sounds.** CleanMyMac's "atmospheric sounds" and its success/failure sounds are protected recordings (VERIFIED-SIB `09-design.md`). Use system sounds (`NSSound`) or original or licensed audio.

**UI text, help articles and marketing copy.**
- Short words and phrases and functional labels are generally **not** copyrightable. RECALLED (US Copyright Office, Circular 33; 37 CFR 202.1(a)).
- Descriptions, tooltips, onboarding text, KB articles and taglines **are**. Write all explanatory copy from scratch. Do not paraphrase their paragraphs line by line.
- The research reports quote only short labels for this reason.

**Data compilations.** Don't copy:
- MacPaw's cleanup **Safety Database** or rules;
- Moonlock signatures;
- uninstaller leftover patterns;
- Updater feed lists.

Build ours from:
- Homebrew cask `zap` stanzas (BSD-2-Clause, attribution; VERIFIED-SIB `06-applications.md`);
- vendor documentation;
- our own observation.

The EU also has a **sui generis database right** (RECALLED).

**Screenshots of CleanMyMac** in our repo docs: avoid committing them. Link to MacPaw's pages instead. INFERRED.

### 5.3 Trade dress / look-and-feel

**What could be claimed** (RECALLED doctrine; US Lanham Act §43(a); EU/UK passing off and unfair competition, e.g. German UWG §4 no. 3 against misleading imitation):
- The **overall combination** of distinctive non-functional visual elements, if it has acquired distinctiveness. *Wal-Mart v. Samara* (2000) requires secondary meaning for product design.
- Functional features are excluded (*TrafFix*, 2001).

**CleanMyMac's distinctive combination** (VERIFIED-SIB `09-design.md`):
- a full-bleed **per-module gradient** sinking into deep indigo, with exact hex values per module;
- one glossy **pre-rendered 3D hero object** per module;
- a persistent **circular action orb** ("Ubiquitous Button") in the same place in every module, changing label and palette (Scan → Stop → Clean);
- pink/violet brand colours;
- circular gradient category badges;
- atmospheric sounds;
- the pink-iMac-plus-squeegee icon.

**Rule** (INFERRED): don't reproduce **more than one or two** of these traits, and none exactly. Concretely:
- Our own palette family. Avoid pink→violet→indigo per-module gradients. Use system materials and Liquid Glass on macOS 26 with a single accent, or a distinctly different hue system.
- A primary action with a different shape or placement: e.g. a toolbar prominent button or bottom action bar instead of a centred circular orb. If circular, use a different size, ring treatment and motion.
- A different illustration medium: e.g. live SwiftUI vector compositions, SF Symbols hierarchy art, or flat line illustration instead of glossy 3D renders.
- Different motion and sound design, and our own app icon motif.

**Free to replicate** (functional or platform conventions):
- **Sidebar + detail split view.** Apple's HIG prescribes sidebars for navigating top-level areas: at most two levels, grouped, SF Symbols in the accent colour. VERIFIED (https://developer.apple.com/tutorials/data/design/human-interface-guidelines/sidebars.json).
- **Grouped module list** (cleanup / protection / performance / apps / files).
- **Scan → review list with checkboxes → confirm** flow.
- Size totals, progress indicators, treemap or sunburst visualisations (long-standing prior art: treemaps since the early 1990s, sunbursts since around 2000; RECALLED).
- A **menu bar extra** with stats. The HIG covers it, including "let people decide" whether it shows. VERIFIED (menu-bar HIG).
- **Settings tabs, an ignore list, onboarding permission screens** (FDA deep link).

**Case-law intuition** (RECALLED, US; jurisdiction-dependent):
- *Lotus v. Borland* (1st Cir. 1995): a menu command hierarchy is an uncopyrightable "method of operation".
- *Apple v. Microsoft* (9th Cir. 1994): GUI ideas and functional elements are unprotected; protection is "thin".
- *Oracle v. Google* (2021): reimplementing an API's functionality was fair use.
- EU: *SAS Institute v. WPL* (CJEU C-406/10, 2012): functionality, programming languages and data formats are not protected by copyright. *BSA v. Ministry of Culture* (C-393/09, 2010): a GUI can be protected as a work if it is the author's own intellectual creation, and elements dictated by function are not.

Net: **copy the function, not the expression.**

### 5.4 Patents and designs

- No MacPaw patents were found this session (search was unavailable). That is a GAP. (fact-check) Still a gap: Google Patents, USPTO and EUIPO were unreachable, and GitHub code search has no patent references.
- Core techniques (directory walking, hashing duplicates, treemaps, launchd management, Sparkle-style updating) have abundant prior art. INFERRED.
- **GUI/icon design registrations** exist in the US (design patents) and EU (registered Community designs). Original art and layout differentiation (§5.3) mitigates this. RECALLED / INFERRED.

### 5.5 Platform rules if ever distributed

App Review Guidelines (VERIFIED, https://developer.apple.com/app-store/review/guidelines/):
- **4.1** Copycats: don't copy a popular app or "make some minor changes to another app's name or UI and pass it off as your own"; no impersonation.
- **5.2.1**: no third-party trademarks or copyrighted works without permission; no "copycat" metadata.
- **5.2.5**: don't look confusingly similar to Apple products or interfaces (e.g. Finder).
- **2.3.7**: no trademarked terms or popular app names in metadata.
- **2.4.5**: MAS apps must be sandboxed; no root escalation; no auto-launch without consent; updates only via the MAS.
- **4.5.4**: no marketing pushes without opt-in.
- **3.1.2**: subscription transparency.

Our direct-distribution build is not bound by MAS rules, but 4.1 and 5.2 mirror the legal risks above.

**Notarization:** when distributing, sign with Developer ID, use the hardened runtime and notarize. Ad-hoc signing is fine for a personal Mac mini build; Gatekeeper will need a one-time override. VERIFIED-SIB (`10-internals.md` §11).

### 5.6 Open-source licences of peers: what we may reuse

| Project | Licence | Reuse guidance (INFERRED) |
|---|---|---|
| Stats (readers for CPU/RAM/battery/sensors) | MIT (VERIFIED) | OK with copyright and licence notice |
| PureMac | MIT (VERIFIED) | OK with notice |
| Purge | MIT (VERIFIED) | OK with notice |
| Headroom | MIT (VERIFIED) | OK with notice |
| CleanUp | MIT (VERIFIED) | OK with notice |
| Mac Sai | BSD-3-Clause (VERIFIED) | OK with notice; **no use of the "Mac Sai" name for endorsement** |
| DiskWise | Apache-2.0 (VERIFIED) | OK with notice and NOTICE file; patent grant |
| MacPaw **PermissionsKit** (FDA detection) | MIT, © 2018 MacPaw Way Ltd. (VERIFIED: https://github.com/MacPaw/PermissionsKit) | OK with notice. Keeping MacPaw's copyright line in our licence file is compliance, not branding |
| Homebrew cask definitions (zap paths) | BSD-2-Clause (VERIFIED-SIB) | Data reuse OK with attribution |
| Mole | GPL-3.0 (VERIFIED) | Copying code makes our app GPL-3.0. Fine for personal use or a GPL release; **study ideas, don't paste code** if we may ever close-source |
| Latest, KnockKnock | GPL-3.0 (VERIFIED) | Same as Mole |
| Pearcleaner | Apache-2.0 + **Commons Clause** (VERIFIED) | Not OSI-open. Code can't be used in anything sold. Treat as reference only |
| Apple OSS (`purge.c`, etc.) | APSL / various | Reference only; call system binaries rather than vendoring |
| MacPaw `cleanmymac-cli` | **Proprietary** EULA (VERIFIED) | Docs are a functional reference only; no code or data reuse |

### 5.7 Third-party data and APIs in "cloud" and "email" features

RECALLED; re-check Google's policies:
- **Gmail cleanup** needs Google OAuth with Gmail scopes. These are **restricted scopes**: public apps need verification and a security assessment.
- For a personal build, create your own Google Cloud OAuth client in **Testing** mode with yourself as a test user. Refresh tokens for testing-mode apps expire after about 7 days, so the UI must handle re-auth. (fact-check) Upgraded to VERIFIED-2ND. Several projects quote Google's OAuth 2.0 doc (https://developers.google.com/identity/protocols/oauth2#expiration): an app with an **External** user type and publishing status **"Testing"** gets refresh tokens that expire in 7 days (e.g. https://github.com/iXanadu/pigeon-mcp/blob/main/docs/google-oauth-setup.md ; https://github.com/formbricks/formbricks/blob/main/docs/self-hosting/configuration/integrations/google-sheets.mdx). The "restricted scope" status of Gmail scopes is still RECALLED.
- Store tokens in the Keychain.
- **Cloud drives:**
  - Prefer system APIs: iCloud eviction via `FileManager.evictUbiquitousItem(at:)` (macOS 10.7+, "Removes the local copy of the specified item that's stored in iCloud", VERIFIED Apple doc JSON); File Provider for third-party drives.
  - Never scrape vendor apps' private databases.
  - INFERRED.
- **Malware signatures:**
  - Don't reuse Moonlock data.
  - Options: ClamAV signatures (GPL; check the database licence), YARA rules with compatible licences, our own hashes, and **reading** Apple's on-disk XProtect rules locally for status display. Don't redistribute them.
  - RECALLED / INFERRED.

### 5.8 Do / Don't summary

| Do | Don't |
|---|---|
| Re-implement every *function* (scan, review, clean, uninstall, update, monitor) | Use "CleanMyMac", "MacPaw", "Moonlock", "Smart Care", "Smart Scan", "Space Lens", "My Clutter", "Smart Insights" anywhere user-facing |
| Use generic labels (System Junk, Uninstaller, Updater, Large & Old Files) or our own coinages | Use a "Mac" or "Clean+Mac" style product name, or any Apple mark or logo in the name or icon |
| Follow HIG conventions (sidebar, toolbar, menu bar extra, SF Symbols in UI) | Put SF Symbols or Mac hardware in the app icon |
| Commission or create original icon, illustrations, sounds and copy | Trace, recolour or re-render MacPaw art; reuse their sounds; paraphrase their help articles |
| Pick our own palette and primary-action design | Clone the per-module pink→indigo gradients plus a centred circular orb plus glossy 3D heroes |
| Build rule data from cask `zap`, docs and observation | Import MacPaw rule DBs, signature data, string tables or assets (EULA forbids reverse engineering) |
| Reuse MIT/BSD/Apache OSS with notices | Paste GPL code unless we accept GPL; reuse Pearcleaner code in anything monetised |
| Add a non-affiliation disclaimer when comparing | Imply endorsement or a "successor to CleanMyMac" positioning |
| Rename this repo before going public | Ship bundle IDs, launchd labels or Mach-service names that echo `com.macpaw.*` |

---

## 6. Recommendations for product positioning (INFERRED)

1. **Positioning:** "the transparent Mac maintenance app". Everything CleanMyMac does, plus undo, dry-run, safety labels, coverage reporting and zero telemetry. No paywall, no fear copy.
2. **Rename or reshape these vendor features:**
   - Free Up RAM → **Memory** (pressure dashboard, optional cache flush).
   - Free Up Purgeable Space → **Snapshots & purgeable** (measured).
   - Shredder (X only; removed in 5.0, corrected) → **Delete immediately**.
   - Repair Disk Permissions → **Check home-folder permissions** (conditional).
   - Smart Care → **Checkup** (Safe tier only).
   - Space Lens → **Space Map** (sunburst or treemap with a "hidden" and "purgeable" ring).
3. **Add beyond CleanMyMac:**
   - Homebrew/PKG manager;
   - developer project purge;
   - OnyX-style reversible Parameters;
   - iStat-style alert rules;
   - SMART health;
   - a CLI with JSON;
   - op-log export;
   - "verify no telemetry" page;
   - a Storage-settings bridge ("Use macOS for this");
   - XProtect status.
4. **Defaults for a Mac mini:**
   - Monitor off until enabled;
   - no battery UI;
   - fan RPM read-only;
   - maintenance runs anytime (on AC).

---

## 7. Gaps / open questions

1. **Competitor feature lists** for DaisyDisk, OnyX, AppCleaner, Sensei, BuhoCleaner, Nektony, CCleaner and iStat Menus are mostly **RECALLED**: their sites were unreachable and there were no search results. Re-verify the "R" columns of §2.2 when web access returns. (fact-check: **partly filled**) Vendor sites were still unreachable and web search was exhausted. Added: cask-verified install footprints (re-fetched; all versions match), CVE histories for Sensei, Pearcleaner, iStat Menus, BuhoCleaner and CCleaner, a new matrix row, and Nektony/Dr.Buho team IDs. The feature cells themselves remain R.
2. **Apple Storage settings labels** on macOS 26 and 27, the exact deep link and category list, and whether "Reduce Clutter" returned: verify on device. (fact-check: **partly filled**)
   - The deep link is now VERIFIED-2ND.
   - Recommendation wording, Applications/iOS-Files sub-groups and the 30-day Trash setting come from Apple glossaries (pre-Ventura, VERIFIED-2ND).
   - The Ventura+ category list and view-only categories come from a secondary summary.
   - The macOS 26/27 labels are still unverified.
3. **Trademark registrations** for "Smart Care", "Space Lens", "My Clutter" and "Moonlock": not checked (USPTO/EUIPO unreachable). (fact-check) Still unverified. MacPaw maintains a "Trademarks" page (§5.1).
4. **CleanMyMac 5 desktop EULA and Privacy Policy** text (what analytics collects, defaults, opt-out location in the GUI): not fetched (macpaw.com unreachable). The CLI wiki does not specify the default. (fact-check: **partly filled**) CLI EULA terms (§5.2) and the 2020 CleanMyMac X privacy policy (§4.2 C8) were added. The CleanMyMac 5 desktop texts are still missing.
5. ~~**Fake-CleanMyMac malware campaigns** (2024–2025): details RECALLED, sources not re-fetched.~~ (fact-check: **resolved**) Cthulhu Stealer (fake CleanMyMac DMG, 2023–24) and SHub Stealer (fake `cleanmymacos[.]org`, March 2026). SHAMOS did not use CleanMyMac lures. See §4.2 C14. Primary Malwarebytes and Cado pages were still unreachable.
6. **MacPaw patents or design registrations:** unknown (still unreachable).
7. Whether CleanMyMac 5's Language Files / Universal Binaries steps skip sealed or MAS apps: undocumented (also open in `03-cleanup.md`). (fact-check) Per TN2206, "sealed" alone is not a breakage reason (§4.2 C4).
8. Notarization history: **no evidence** found of any notarization revocation or XProtect flagging of CleanMyMac. Absence is not proof. (fact-check) A GitHub-wide code search for team ID `S8EX82NJP6` finds only casks, admin and uninstall scripts, MacPaw's own repos and Apple `tccd` allow-list diffs (macOS 27 betas), with no XProtect or Gatekeeper rule. Mole even treats CleanMyMac X helper IDs as known stubs. Re-check on device: `XProtect.meta.plist` and `XPScripts.yr` (§3.5).
9. (fact-check) The current **CleanMyMac 5 privacy policy** and the GUI location of its analytics toggle: still not fetched. Only the 2020 X policy is mirrored (§4.2 C8).
10. (fact-check) **BuhoCleaner feature list:** still RECALLED. Only the CVE, team ID and "Flash Clean" are verified.

---

## 8. Sources

**Fetched this session (VERIFIED):**
- Homebrew casks: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb · …/c/cleanmymac-zh.rb · …/d/daisydisk.rb · …/o/onyx.rb · …/a/appcleaner.rb · …/p/pearcleaner.rb · …/s/sensei.rb · …/c/ccleaner.rb · …/i/istat-menus.rb · …/s/stats.rb · …/m/maccleaner-pro.rb · …/a/app-cleaner.rb · …/o/omnidisksweeper.rb · …/g/grandperspective.rb · …/d/disk-inventory-x.rb
- Pearcleaner README and issues: https://github.com/alienator88/Pearcleaner ; issues #561, #575, #564, #538, #355, #236
- Stats README and issues: https://github.com/exelban/stats ; issues #318, #3234, #3303, #3661
- Mole README, audit and issue: https://github.com/tw93/Mole ; https://raw.githubusercontent.com/tw93/Mole/main/SECURITY_AUDIT.md ; https://github.com/tw93/Mole/issues/1309
- Monolingual issues: https://github.com/IngmarStein/Monolingual/issues/83 , /124 , /194 , /309
- urlwatch: https://github.com/thp/urlwatch/issues/416
- Poetry: https://github.com/python-poetry/poetry/issues/3346
- Purge: https://github.com/jithin-sabu/purge-app ; https://github.com/jithin-sabu/purge-app/issues/134
- clean-mac-ai (unsourced Spotify claim, not relied on): https://github.com/devius/clean-mac-ai/issues/2
- PureMac: https://github.com/momenbasel/PureMac ; Mac Sai: https://github.com/iliyami/MacSai ; CleanUp: https://github.com/syahrul84/cleanUp ; Lighten: https://github.com/tunatavsan/lighten ; Headroom: https://github.com/Ryware/Headroom ; DiskWise: https://github.com/DreamOfXM/diskwise ; Latest: https://github.com/mangerlahn/Latest ; KnockKnock: https://github.com/objective-see/KnockKnock
- awesome-mac cleanup/system sections: https://raw.githubusercontent.com/jaywcjlove/awesome-mac/master/README.md
- MacPaw org and repos: https://github.com/MacPaw ; https://github.com/MacPaw/cleanmymac-cli (README and LICENSE/EULA) ; https://raw.githubusercontent.com/wiki/MacPaw/cleanmymac-cli/Safety-and-Privacy.md ; https://github.com/MacPaw/PermissionsKit
- CVE records: https://github.com/CVEProject/cvelistV5 (`cves/2018/4xxx/CVE-2018-40{32..37,41..47}.json`, `cves/2019/5xxx/CVE-2019-5011.json`, `cves/2015/5xxx/CVE-2015-5901.json`, `cves/2024/22xxx/CVE-2024-22405.json`)
- GitHub Advisory Database: https://github.com/advisories?query=CleanMyMac ; https://github.com/advisories?query=MacPaw ; GHSA-5jv4-7vh6-9xcq, GHSA-hv87-vwg4-xqmg, GHSA-cqmj-qx32-vqv9, GHSA-pjc7-272c-jc94, GHSA-gpjj-mwc7-6rjh, GHSA-35v8-f3m3-88h6, GHSA-8xx8-72q4-m3hg
- MacPaw DevMate release notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html ; https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html
- Apple: https://developer.apple.com/app-store/review/guidelines/ ; HIG JSON: …/design/human-interface-guidelines/sidebars.json , …/the-menu-bar.json , …/sf-symbols.json , …/app-icons.json ; https://developer.apple.com/tutorials/data/documentation/foundation/checking-volume-storage-capacity.json ; `purge(8)`: https://raw.githubusercontent.com/apple-oss-distributions/system_cmds/main/purge/purge.8
- GitHub issue search (CleanMyMac-related reports): https://github.com/search?q=%22CleanMyMac%22+deleted&type=issues ; https://github.com/search?q=%22CleanMyMac%22+cache+removed&type=issues

**Fetched by the fact-check pass (VERIFIED / VERIFIED-2ND):**
- Homebrew casks (re-fetched 2026-10-12): all of the above, plus …/c/cleanmymac-cli.rb · …/f/funter.rb · …/b/buholaunchpad.rb (`buhocleaner.rb` returns 404).
- CVE records (cvelistV5 raw JSON):
  - CVE-2018-4032…4048 (incl. the non-MacPaw 4038–4040 and 4048, to bound the Talos range) and CVE-2019-5011;
  - CVE-2024-7915 (Sensei), CVE-2025-54595 (Pearcleaner), CVE-2025-11921 (iStat Menus), CVE-2026-0924 (BuhoCleaner);
  - CVE-2017-20201, CVE-2025-3025, CVE-2026-12410 and CVE-2015-3999 (CCleaner);
  - CVE-2023-46270, CVE-2024-22405 and CVE-2021-47863 (other MacPaw products).
- GitHub advisory JSON: https://raw.githubusercontent.com/github/advisory-database/main/advisories/unreviewed/2022/05/GHSA-5jv4-7vh6-9xcq/GHSA-5jv4-7vh6-9xcq.json
- READMEs, raw: Pearcleaner, Stats, Mole (+ SECURITY_AUDIT.md, `lib/clean/apps.sh`), PureMac, Mac Sai, Purge, Lighten, CleanUp, Headroom, DiskWise, MacPaw/cleanmymac-cli (+ LICENSE EULA, wiki Safety-and-Privacy), awesome-mac.
- Apple:
  - App Review Guidelines (sections 1.1.6, 2.3.1(a), 2.3.7, 2.4.5, 3.1.2, 4.1(a)/(c), 4.5.4, 5.2.1, 5.2.5 re-read);
  - TN2206: https://developer.apple.com/library/archive/technotes/tn2206/_index.html
  - File System Programming Guide (Library directories);
  - doc JSON for `NSXPCListener.setConnectionCodeSigningRequirement(_:)`, `NSXPCConnection.setCodeSigningRequirement(_:)`, `FileManager.evictUbiquitousItem(at:)`, `FileManager.trashItem(at:resultingItemURL:)`, `URLResourceKey.totalFileAllocatedSizeKey`, `volumeAvailableCapacityFor{Important,Opportunistic}UsageKey`, `SMAppService.daemon(plistName:)`, `openSystemSettingsLoginItems()`, `SMAppService.Status.requiresApproval`;
  - `purge(8)` re-read.
- MacPaw DevMate notes, re-read: CMM4 41202 (4.10.3/4.10.4) and CMM5 50205 (5.0.5, 5.0.7, 5.2.1).
- Apple localization glossaries (VERIFIED-2ND): https://raw.githubusercontent.com/clindsay3/GlossaryLookup/HEAD/macOS/German/SystemInfoApp.lg ; …/StorageManagement.lg
- Threat intel (VERIFIED-2ND): https://github.com/stuartjash/macos-malware-kb (families/infostealer/shub-stealer.md, cthulhu-stealer.md, shamos.md) ; https://github.com/bobby-tablez/TTP-Threat-Feeds (Malwarebytes SHub record)
- Privacy policy (VERIFIED-2ND): https://github.com/sonu-gupta/tosdr-terms-of-service-corpus (MacPaw_Privacy Policy.txt, "Updated Sep 04, 2020") ; https://github.com/citp/privacy-policy-historical (macpaw.com.md, 2019 snapshot)
- Deep links and defaults (VERIFIED-2ND): https://github.com/bvanpeski/SystemPreferences/blob/main/macos_preferencepanes-Ventura.md ; Pearcleaner `Pearcleaner/Views/MainWindow.swift` ; https://github.com/yannbertrand/macos-defaults (FXRemoveOldTrashItems)
- XProtect paths (VERIFIED-2ND): macadmins/sofa `tool-scripts/XProtectVersionCheck-swiftDialog.sh` ; jamf/aftermath `systemRecon/SystemReconModule.swift` ; LETHAL-FORENSICS/macos-collector ; Neo23x0/macguard-audit
- Issue: https://github.com/Homebrew/brew/issues/5083 (WebFetch)
- CMM3 Storage Management appex Info.plist (third-party copy): https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/PlugIns/StorageManagement.appex/Contents/Info.plist

**Sibling tracks relied on (VERIFIED-SIB):** `01-overview.md`, `02-smart-care.md`, `03-cleanup.md`, `05-performance.md`, `06-applications.md`, `09-design.md`, `10-internals.md`. Their cited URLs are repeated inline above. (fact-check) Also `07-clutter.md` (Dropbox in 5.3.0; Shredder removed in 5.0) and `04-protection.md` (weak Analytics-tab replica).

**RECALLED (re-check when web access is available):**
- https://support.apple.com/en-us/102624 (Storage settings)
- https://support.apple.com/guide/security/ (XProtect, Remediator)
- https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html
- https://daisydiskapp.com/ ; https://www.titanium-software.fr/en/onyx.html ; https://freemacsoft.net/appcleaner/ ; https://cindori.com/sensei ; https://www.drbuho.com/buhocleaner ; https://nektony.com/mac-cleaner-pro ; https://nektony.com/mac-app-cleaner ; https://www.ccleaner.com/ccleaner-mac ; https://bjango.com/mac/istatmenus/
- https://tmsearch.uspto.gov/ ; https://euipo.europa.eu/eSearch/ ; US Copyright Office Circular 33
- Cases: *Lotus v. Borland* (1995), *Apple v. Microsoft* (1994), *Oracle v. Google* (2021), *Wal-Mart v. Samara* (2000), *TrafFix* (2001), CJEU *SAS Institute* C-406/10 (2012), CJEU *BSA* C-393/09 (2010)

---

## Verification notes

Adversarial fact-check pass, 2026-10-12.

**Conditions.**
- The shared WebSearch budget was already exhausted (0 searches possible).
- Vendor, press, Apple support, USPTO/EUIPO and Google hosts still failed DNS.
- Evidence came from:
  - GitHub-wide code search (MCP);
  - raw GitHub files (official cvelistV5 JSON, Homebrew casks, READMEs, threat-intel KBs, Apple localization glossaries, a privacy-policy corpus);
  - `developer.apple.com` (API doc JSON, App Review Guidelines, archived technotes);
  - MacPaw DevMate release notes on S3;
  - WebFetch of single `github.com` pages.
- About 30 claims were tested. The implementation-critical ones are below.

### Checked and confirmed (no change needed)
| # | Claim | Result |
|---|---|---|
| 1 | CleanMyMac cask 5.7.1, build `50701.0.2609301754`, `CleanMyMac_5.app`, team `S8EX82NJP6`, HealthMonitor/Menu jobs, root Agent helper and LaunchDaemon, Updater LaunchAgent, "CleanMyMac 5 Menu" login item | Confirmed (cask re-fetched) |
| 2 | Competitor cask facts: DaisyDisk 4.34.2 + admin helper; OnyX per-OS builds; AppCleaner 3.7 needs macOS 15 + SmartDelete job; Pearcleaner 5.4.3 / macOS 13 / Sentinel; Sensei 2.1.3 / macOS 14 / Amplitude + Sentry; CCleaner 2.11.194 .pkg with 9 launchd jobs; iStat Menus 7.50.1 / macOS 13 / fans daemon; Stats 3.0.21 / macOS 12 / SMC helper; Nektony 4.0.4 suite and 10.0.1; Disk Inventory X disabled 2026-09-01 | Confirmed |
| 3 | 13 CVEs in CMM X 4.04 + CVE-2019-5011 (CWE-459) in 4.20; no CleanMyMac 5 CVE | Confirmed (scores corrected, see below) |
| 4 | `purge(8)` empties the disk buffer cache only and does not affect malloc/vm_allocate memory | Confirmed (Apple OSS man page) |
| 5 | CVE-2015-5901: Secure Empty Trash improperly deleted files before 10.11 | Confirmed |
| 6 | App Review 1.1.6, 2.3.1(a), 2.3.7, 2.4.5, 3.1.2, 4.1(a)/(c), 4.5.4, 5.2.1, 5.2.5 wording | Confirmed |
| 7 | 4.10.3 stopped RU/BY sales; 4.10.4 added the Uninstaller "Suspicious" group + Ukrainian-theme off switch | Confirmed (DevMate) |
| 8 | 5.0.5 "Free Up Purgeable Space"; 5.0.7 VoiceOver + Reduce Motion | Confirmed (DevMate) |
| 9 | CLI: `optimize ram` "no sudo required"; analytics toggle in `config`; default not stated; 7-day purge preselection; `--force` | Confirmed (README, wiki) |
| 10 | Pearcleaner "On Hold"; Apache-2.0 + Commons Clause; FDA + privileged helper | Confirmed |
| 11 | Stats: fan control legacy/unmaintained; macOS 26 Menu Bar allow-list; Location for Wi-Fi name; own server for public IP | Confirmed |
| 12 | Mole: op-log `~/Library/Logs/mole/operations.log`, `--dry-run`, SQLite-cache loop (#1390), Dock/wallpaper (#995, #1300), GPL-3.0 | Confirmed |
| 13 | PureMac comparison: CleanMyMac "No" on telemetry-free, "Partial" on uninstall Trash support, "No" on purgeable honesty; "No fake urgency" | Confirmed |

### Corrected in place (marked "(corrected)")
1. **CVSS for the 2018 CVEs.** The CNA (Talos) score in the CVE record is **7.1 High** (`PR:N/S:C`). **5.5 Moderate** is the NVD/GHSA score. The Talos range is 0705–0710 and 0715–0721, not a continuous 0705…0721.
2. **Shredder.** It was removed in CleanMyMac 5.0, so CleanMyMac does not "still offer" it. Fixed in the matrix, §3.8, §4.2 C10 and §6.
3. **"Bundle thinning breaks signed apps."** Apple TN2206 says removing `.lproj` files or whole architecture slices does **not** invalidate a code signature. Breakage comes from integrity self-checks, updaters, needed slices (`arm64e`) and over-removal. Fixed in the exec summary, C4 and P7. This contradicts `03-cleanup.md` §5.6, which another pass should fix.
4. **Fake-CleanMyMac malware.** It was not "AMOS/SHAMOS 2024–2025". It was **Cthulhu Stealer** (fake CleanMyMac DMG, 2023–24) and **SHub Stealer** (`cleanmymacos[.]org`, ClickFix, March 2026). SHAMOS used generic fake macOS-help pages.
5. **Cloud Cleanup providers.** 5.2.1 shipped iCloud Drive, Google Drive and OneDrive; Dropbox came in 5.3.0.
6. **Optimize Storage** also keeps only recent Mail attachments (Apple's own string).
7. **CLI naming.** The binaries are `cleanmymac` and `cmm`. `cleanmymac-cli` is the repo and cask name. It needs macOS 11+.
8. **Upgraded from RECALLED to VERIFIED or VERIFIED-2ND:**
   - Storage deep link `com.apple.settings.Storage`;
   - `NSXPCListener.setConnectionCodeSigningRequirement(_:)` (macOS 13);
   - the `SMAppService` APIs;
   - `networkQuality` (macOS 12+);
   - the Gmail Testing-mode 7-day refresh-token expiry;
   - the CCleaner 5.33 compromise (CVE-2017-20201).
9. **Min macOS for CMM 5:** 11+ for the current release, not only "at 5.0 launch".

### Added (marked "(fact-check)")
- **Category-wide root-helper CVE pattern:** Sensei CVE-2024-7915, Pearcleaner CVE-2025-54595, iStat Menus CVE-2025-11921, BuhoCleaner CVE-2026-0924, and Windows CCleaner symlink and insecure-delete bugs. These became a new matrix row, a P0 checklist item and concrete P14 rules: no PID-based auth, no shell verbs, `O_NOFOLLOW` deletes.
- **Apple Storage internals** from Apple localization glossaries: category plug-ins, Applications groups (App Store, Older Versions, Duplicates, Unsupported, Other), iOS Files groups, immediate (non-undoable) delete, low-disk alert, and the Trash setting `FXRemoveOldTrashItems`.
- **XProtect / XProtect Remediator version paths** (incl. the macOS 15+ `/private/var/protected/xprotect/`) and the SOFA feed. The **macOS 26.4 Terminal paste warning**.
- CleanMyMac 3's private `com.apple.storagemanagement` extension ("System Junk").
- **2020 CleanMyMac X privacy-policy** data categories. **CLI EULA** terms: MacPaw Way Ltd., Cyprus law, US$50 cap, class waiver.
- Homebrew #5083 (CleanMyMac deleted `~/Library/Caches/Homebrew`). Apple's "apps should never rely on the existence of cache files" contract.
- Quarantine-attribute CVEs in other MacPaw products (The Unarchiver, XADMaster).
- C20: "Notarized by Apple" used as marketing.
- Mac Sai's use of the name "Smart Scan". Pearcleaner fake-site PSA. Nektony team ID `8DKG4XB37M`. BuhoLaunchpad Sentry trace.
- Checklist additions: duplicate/older app copies, iOS firmware, GarageBand library, Finder 30-day Trash toggle.

### Still uncertain
- Competitor **feature** cells marked R (DaisyDisk, OnyX, AppCleaner, Sensei, BuhoCleaner, Nektony, CCleaner, iStat Menus). Vendor sites and the App Store stayed unreachable.
- Apple Storage labels on **macOS 26/27**. The glossaries are pre-Ventura (exact version unknown), and the Ventura+ list is secondary.
- Trademark registrations, patents and design registrations (USPTO/EUIPO/Google Patents unreachable).
- The **CleanMyMac 5** desktop EULA and privacy policy, and where the analytics toggle lives in the GUI.
- Primary threat-intel pages (Malwarebytes, Cado, CrowdStrike, SentinelOne) were seen only through GitHub mirrors and KBs.
- Talos as discoverer of the 2017 CCleaner compromise. The Jumpshot/FTC history.
- Absence of XProtect or Gatekeeper action against CleanMyMac. Check on device in `XProtect.meta.plist` and `XPScripts.yr`.
- TN2206 was last revised in 2016. Its "removal does not invalidate" rule should be re-tested on macOS 15/26 with `codesign --verify --deep --strict` on a thinned copy before we rely on it.
