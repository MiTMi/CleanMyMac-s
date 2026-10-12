# 01 — Product Overview, History, Editions, Module Map, Onboarding & Settings

Research track: **overview / history / editions / module map / onboarding / settings** for MacPaw's CleanMyMac
(CleanMyMac X 2018–2024, and the redesigned 2024+ "CleanMyMac", internally version 5.x).
Target of our work: an **original, functionally equivalent** macOS utility for a personal Apple Silicon Mac mini
(macOS 14 Sonoma+, incl. 15 Sequoia, 26 Tahoe and — new since Sept 2026 — 27 "Golden Gate").
Research date: **2026-10-12**.

---

## 0. Method, labels and caveats

- **VERIFIED** = stated by a source, cited inline (URL). **INFERRED** = our reasoning or a recommendation for our implementation.
- **Access caveat (important):** in this research environment `macpaw.com`, `cleanmymac.com`, `apps.apple.com`, `setapp.com` and most press sites were **not directly fetchable** (blocked by the egress proxy/DNS). MacPaw pages were therefore verified through search-engine extraction of those exact pages (the URL cited is the page the claim was extracted from). Two primary sources **were fetched directly**: the official Homebrew cask (`raw.githubusercontent.com/Homebrew/homebrew-cask/.../cleanmymac.rb`), MacPaw's DevMate release-notes file on Amazon S3, and MacPaw's own GitHub repo `MacPaw/cleanmymac-cli`. Those are marked "(fetched)".
- **Fact-checker pass (2026-10-12):** DNS-blocked during this pass: `macpaw.com`, `cleanmymac.com`, `updates.cleanmymac.com`, `apps.apple.com`, `setapp.com`, `en.wikipedia.org`, `macrumors.com`, `9to5mac.com`, `tidbits.com`, `talosintelligence.com`, `nvd.nist.gov`, `support.apple.com`, `objective-see.org`, `formulae.brew.sh`. The shared WebSearch budget was already used up, so **no new web searches were possible**. Re-verification therefore relied on the sources that were reachable: GitHub (Homebrew cask history and PRs, the CVE Program's `cvelistV5` repo, GitHub Advisory DB, MacPaw's own repos, and the Mole and Pearcleaner source), the DevMate S3 release notes, and Apple developer documentation (JSON endpoints). Claims that rest only on MacPaw KB pages are left as the original researcher marked them, unless noted otherwise. See "## Verification notes" at the end.
- Where sources disagree (dates in particular: MacPaw's site vs. Mac App Store usually differ by 2–7 days) both values are given.
- Nothing here is copied marketing copy; short UI labels are quoted because we need exact feature names.
- **Do not copy:** names "CleanMyMac", "Moonlock", "Smart Care", MacPaw illustrations, icons, sounds, or copy. We reproduce *functionality and information architecture*, under our own names (see §13).

---

## 1. Executive summary (what matters for the clone)

1. **Current product (Oct 2026):** "CleanMyMac" **5.7.1**, released 2026-10-01, build `50701.0.2609301754`, requires **macOS 11 Big Sur or later**, supports up to **macOS 27 Golden Gate**. VERIFIED (Homebrew cask, fetched: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb ; https://macpaw.com/support/cleanmymac/knowledgebase/operating-systems ; https://cleanmymac.com/). (corrected/clarified) The *current* cask no longer encodes the minimum OS: it says plain `depends_on :macos`; the explicit `depends_on macos: :big_sur` was removed on 2026-09-10 (commit "cleanmymac: depends_on macos: :big_sur -> depends_on :macos", https://github.com/Homebrew/homebrew-cask/commits/main/Casks/c/cleanmymac.rb). INFERRED: that is Homebrew housekeeping (Homebrew itself sets `HOMEBREW_MACOS_OLDEST_ALLOWED="11"`, https://raw.githubusercontent.com/Homebrew/brew/main/Library/Homebrew/brew.sh), not a MacPaw requirement change, so "macOS 11+" still rests on MacPaw's KB. The name "Golden Gate" = macOS 27 is VERIFIED in Homebrew's own version table (`golden_gate: "27"`, https://raw.githubusercontent.com/Homebrew/brew/main/Library/Homebrew/macos_version.rb).
2. **Information architecture (sidebar), current:** Smart Care · Cleanup · Protection · Performance · Applications · My Clutter · Space Lens · Cloud Cleanup · My Tools · My Activity, plus the separate menu-bar app "The Menu". VERIFIED as the feature-table order on https://macpaw.com/support/cleanmymac/knowledgebase/missing-features (exact on-screen order INFERRED to match). Email Cleanup (5.7.0) lives under the Tools area. VERIFIED (https://macpaw.com/how-to/organize-email-inbox)
3. **Core UX pattern:** every module = *Scan → summary **tiles** (recommended actions, pre-selected) → "Review" drill-down list → Run/Remove*. Smart Care runs all modules at once and shows one tile per module. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/smart-care ; Macworld review https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html)
4. **Process architecture:** main app + **Menu** (menu-bar agent) + **Health Monitor** (background agent; also powers real-time malware monitoring) + **Agent** (privileged root helper installed on first root-needing action after admin password) + **Updater** (LaunchAgent for self-update; Sparkle feed) + **Finder Sync extension** (`com.macpaw.CleanMyMac5.FinderSyncExtension`, added by the fact-checker). VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/background-items ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent ; cask, fetched; Finder Sync extension seen in a user's running-process dump, where Menu and Health Monitor both run with the `accessory` activation policy: https://github.com/niklasr22/BrightIntosh/issues/309)
5. **Permissions:** Full Disk Access (strongly requested; needed for full scans, mail attachments, Health monitor disk data), admin password for the Agent, "Allow in the Background" for Menu/Health Monitor, notifications. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access ; https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items)
6. **Settings tabs verified for the 5.x app:** General (Updates), **Scanning** (Smart Care inclusion per module/category/group), **Ignore List**, **Protection**, **Menu**; Notifications tab is verified for X and likely persists. Details §10.
7. **Editions:** MacPaw Store (direct, Sparkle-updated), Mac App Store (sandboxed, reduced features), Setapp (Plus-equivalent). Since July 2025 two plans: **Basic** and **Plus** (Plus adds Protection, Space Lens, Cloud Cleanup, etc.). VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans ; Macworld review above)
8. **For our personal clone (INFERRED):** no licensing/paywall; ship the full "Plus" feature set; direct (non-App-Store) build so we are not sandboxed; macOS 14+ lets us use `SMAppService` for the menu agent, health agent and the privileged daemon (no deprecated `SMJobBless`).

---

## 2. History timeline

| Year / date | Release | Notes | Status |
|---|---|---|---|
| 2008 (Jan or July — sources conflict) | **CleanMyMac** (later "CleanMyMac Classic") | Written by Oleksandr Kosovan as a student; MacPaw founded 2008 (Kyiv). Shareware: full scan, clean up to 500 MB free. | VERIFIED (https://en.wikipedia.org/wiki/CleanMyMac ; https://macpaw.com/leadership/oleksandr-kosovan ; https://macpaw.com/support/cleanmymac-classic/knowledgebase/cleanmymac-shareware-program) |
| March 2013 (some sources say 2012) | **CleanMyMac 2** | Single source for date. | INFERRED (downgraded: only one secondary mirror, https://wiki2.org/en/CleanMyMac; the fact-checker could not re-check it because Wikipedia was unreachable) |
| April 2015 | **CleanMyMac 3** | Added iTunes junk, mail attachments, cookies, browser extensions removal; menu-bar "CleanMyMac 3 Menu". Preferences tabs: General, Smart Cleanup, Scheduler, CleanMyMac 3 Menu, Updates, Ignore List. Runs on macOS 10.9–10.14. | VERIFIED (https://en.wikipedia.org/wiki/CleanMyMac ; CMM3 manual https://www.scribd.com/document/290796048/Manual-Cleanmymac ; https://macpaw.com/support/cleanmymac/knowledgebase/operating-systems) |
| Sept 2018 | **CleanMyMac X** (4.0, "10th anniversary edition") | Smart Scan, Assistant, Updater, Malware Removal, reworked Menu; annual subscription model introduced alongside one-time licence. | VERIFIED (https://macpaw.com/news/cleanmymac-x-has-arrived ; https://macpaw.com/news/cleanmymac-anniversary ; https://www.mactrast.com/2018/09/macpaws-new-cleanmymac-x-offers-faster-mac-cleaning-new-malware-removal-option-more/amp/) |
| Dec 2018 – Jan 2019 | 4.0.4 → patched | (corrected) Cisco Talos found **13** privilege-escalation CVEs in the **helper service of CleanMyMac X 4.04** (improper input validation, so any local user could change the file system as root): **CVE-2018-4032 to -4037** (TALOS-2018-0705 to -0710) and **CVE-2018-4041 to -4047** (TALOS-2018-0715 to -0721). CVE-2018-4038 to -4040 belong to other products. Public disclosure / CVE publication **2019-01-10**. The earlier "patched 2018-12-27" date could not be re-verified. Lesson for our helper design (§12). | VERIFIED (CVE records, fetched: https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4032.json , …/CVE-2018-4041.json , …/CVE-2018-4042.json , …/CVE-2018-4047.json ; non-CleanMyMac IDs: …/CVE-2018-4038.json , …/CVE-2018-4040.json ; GitHub advisories https://github.com/advisories?query=CleanMyMac) |
| Mar 2019 | 4.2.0 | (added) **CVE-2019-5011** (TALOS-2019-0759): in CleanMyMac X **4.20**, updating to the latest version did **not remove the older, vulnerable helper components** (CWE-459, incomplete cleanup), so a local user could still change the file system as root. NVD published 2019-03-21. | VERIFIED (https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2019/5xxx/CVE-2019-5011.json ; https://github.com/advisories/GHSA-8xx8-72q4-m3hg) |
| 2019 | 4.4.0 | **Space Lens** leaves beta. | VERIFIED (https://macpaw.com/news/cleanmymac-x-update-4.4.0) ; year INFERRED |
| 2020-04-28 | Mac App Store edition | Sandboxed edition without Photo Junk, Maintenance, Updater, Shredder. | VERIFIED (https://9to5mac.com/2020/04/28/clean-my-mac-x/ ; https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features) |
| 2021 | — | CleanMyMac X wins Red Dot (Brands & Communication Design) and UX Design Awards; design cues: subtle 3D parallax, micro-animations, hover effects, atmospheric sounds. | VERIFIED (https://www.iphoneincanada.ca/2021/08/17/cleanmymac-red-dot-award-2021/ ; https://macpaw.com/news/cleanmymac-received-ux-design-awards) |
| 2022 | 4.10.x | 4.10.0: updated Assistant with timely Recommendations and extended statistics. Recommendations also appear in the Menu, and iPhone/iPad apps show on M1 Macs. (corrected: the DevMate notes do not say the recommendations are managed in Preferences.) 4.10.3: sales stopped in Russia/Belarus. 4.10.4: "Suspicious" group in Uninstaller (apps from RU/BY developers); Ukrainian theme with off-switch in Preferences. | VERIFIED (DevMate notes, fetched: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html) |
| June 2022 | 4.11.0 | Redesigned **Menu** app (CPU, Memory, Storage, Battery, Protection panels; Network Monitor and Connected Devices announced for later); 4.11.0 also dropped macOS 10.10/10.11. 4.11.1: fuller Chrome privacy cleanup, better leftover removal in Uninstaller. 4.11.2: Network Monitor with Speed Test, and (corrected) **Zoom** support in Updater. 4.11.3: traffic readout, **Chrome** in Updater. 4.11.4: better update notifications. | VERIFIED (same DevMate file, re-fetched by the fact-checker ; https://9to5mac.com/2022/06/30/cleanmymac-x-new-menu-bar-app/) |
| Oct 2022 | 4.12.1 | macOS Ventura compatibility. | VERIFIED (same DevMate file) |
| 2023 | 4.13.0 / 4.14 | 4.13: Connected Devices + External Drives in Menu; iPhone backups in System Junk. 4.14 (July 2023): security component rebranded **Moonlock Engine** (MacPaw's security division). 4.14.3 (2023-10-09): Sonoma support. | VERIFIED (https://tidbits.com/watchlist/cleanmymac-4-14/ ; https://macpaw.com/support/cleanmymac/knowledgebase/moonlock-engine ; https://macpaw.com/cleanmymac-x/whats-new) |
| 2024 | 4.15.x | 4.15.0: configurable protection scan settings, Moonlock Engine 1.2.0; 4.15.4 (2024-06-20) Moonlock 1.3.0; 4.15.8 (2024-10-01). Later 4.15.12 (2025-04-23) and 4.15.14 (zh cask). | VERIFIED (https://mac.filehorse.com/download-cleanmymac/ ; https://macpaw.com/cleanmymac-x/whats-new ; https://cleanmymac-x.macupdate.com/app/mac/30017/cleanmymac/old-versions ; https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb (fetched)) |
| **2024-10-16** | **"CleanMyMac" (5.0)** — "X" dropped | Complete rebuild: six modules + assistant + 25+ tools; tile-based results; "3D animated interface"; redesigned Menu; macOS 11+; min. display 1280×800 (download page says 1200×800). Launch price $39.95/yr or $119.95 one-time. Existing X subscribers/Setapp upgraded free; X one-time owners up to 50% off. | VERIFIED (https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/ ; https://macpaw.com/news/introducing-new-cleanmymac ; https://www.prnewswire.com/news-releases/macpaw-launches-new-cleanmymac-the-smart-effortless-app-for-mac-care-302275058.html ; https://macpaw.com/support/cleanmymac/knowledgebase/upgrade) |
| 2025 | 5.0.5 → 5.2.10 | Purgeable Space task, VoiceOver/Reduce Motion, Space Lens returns, Cloud Cleanup, **Basic/Plus plans (July 2025)**, Smart Insights (Apple Intelligence). The last 2025 build is 5.2.10 (2025-11-27, added by the fact-checker) and 5.3.0 (2025-12-17). | §6 |
| 2026 | 5.3 → 5.7.1 | Dropbox/OneDrive, My Activity, My Tools, Applications background scan, Notification Center, **CleanMyMac CLI** (public beta, July 2026, separate product), Email Cleanup (Gmail). CleanMyMac X development ended (last supported macOS = Tahoe 26). CleanMyMac Business sunset 2026-07-14. | §6 ; https://macpaw.com/support/cleanmymac-x/knowledgebase/operating-systems ; https://macpaw.com/support/cleanmymac-business/knowledgebase |

---

## 3. Current version, system requirements, identifiers

### 3.1 Version & requirements
- Latest: **5.7.1 — 2026-10-01**. VERIFIED (https://macpaw.com/cleanmymac/whats-new ; https://cleanmymac.com/)
- Homebrew `cleanmymac` cask: `version "5.7.1,50701.0.2609301754"`. VERIFIED (fetched cask)
- Build-number scheme `MMmmpp.0.YYMMDDHHMM` (e.g. 5.6.0 → `50600.0.2608201300`, 5.5.4 → `50504.0.2605291449`, 5.2.5 → `50205.0.2509241440`, 5.0.4 → `50004.0.2412161309` and a rebuild `50004.0.2412181205`, 5.0.0 → `50000.0.2410151250`). Values VERIFIED (cask; Homebrew commit titles https://github.com/Homebrew/homebrew-cask/commits/main/Casks/c/cleanmymac.rb ; https://macappdownload.com/cleanmymac-5-5-4/ ; DevMate URL; 5.0.0 notes re-fetched at https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50000.0.2410151250/releasenotes.html). The decoding (major/minor/patch + build timestamp) is INFERRED but consistent: every build timestamp falls on or just before the date Homebrew picked that version up. A version can ship more than one build (5.0.4 had three Homebrew bumps).
- **Supported macOS:** Golden Gate 27, Tahoe 26, Sequoia 15, Sonoma 14, Ventura 13, Monterey 12, Big Sur 11. Catalina and earlier unsupported. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/operating-systems)
- Disk: ~320 MB; min display 1200×800 (download page) / 1280×800 (MacRumors, Setapp, upgrade KB). VERIFIED (https://macpaw.com/download/cleanmymac ; https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/)
- Universal app (Apple Silicon + Intel) — INFERRED (MacPaw distributes one zip per version; Moonlock claims M1/M2 speedups per https://www.g2.com/products/moonlock/discuss).
- Smart Insights needs Apple Silicon + macOS Tahoe 26+ + Apple Intelligence enabled. VERIFIED (https://macpaw.com/news/introducing-smart-insights ; https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller)

### 3.2 Identifiers, files and processes (direct edition) — VERIFIED from the Homebrew cask (fetched)
| Item | Value |
|---|---|
| App bundle name on disk | `CleanMyMac_5.app` (Homebrew renames to `CleanMyMac.app`) |
| Bundle IDs | `com.macpaw.CleanMyMac5`, `com.macpaw.CleanMyMac5.HealthMonitor`, `com.macpaw.CleanMyMac5.Menu` |
| Login item name | `CleanMyMac 5 Menu` |
| Privileged helper | `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` + `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` |
| Self-updater | `~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist`; Sparkle appcast `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml`; downloads `.../releases/CleanMyMac5_<build>.zip`; `auto_updates true` |
| Team ID | `S8EX82NJP6` (App Group `S8EX82NJP6.com.macpaw.CleanMyMac5`) |
| User data | `~/Library/Application Support/CleanMyMac_5`, `~/Library/Caches/com.macpaw.CleanMyMac5`, `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5`, `~/Library/Application Scripts/S8EX82NJP6.com.macpaw.CleanMyMac5`, `~/Library/HTTPStorages/com.macpaw.CleanMyMac5(.binarycookies)`, `~/Library/Logs/com.macpaw.CleanMyMac5`, `~/Library/Preferences/com.macpaw.CleanMyMac5.plist`, `~/Library/Saved Application State/com.macpaw.CleanMyMac5.savedState` |
| Shared data | `/Users/Shared/CleanMyMac_5` |
| Mac App Store ID | `id1339170533` (https://apps.apple.com/us/app/cleanmymac/id1339170533?mt=12) |
| CLI (separate) | `CleanMyMac_5_CLI.app`, binaries `cleanmymac` / `cmm`, group container `S8EX82NJP6.com.macpaw.CleanMyMac5.CLI`, host `cli.cleanmymac.com`, macOS 11+ (fetched: https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb). Re-fetched by the fact-checker: cask `version "1.0.0"`, display name "CleanMyMac 5 CLI", download `https://cli.cleanmymac.com/1.0.0/CleanMyMac-CLI-1.0.0.zip`, `depends_on macos: :big_sur`; one executable `Contents/MacOS/CleanMyMac_5_CLI` symlinked as both `cleanmymac` and `cmm`. It entered Homebrew's main cask repo on 2026-07-21. |
| Finder Sync extension (added) | `CleanMyMac_5_FinderSyncExtension`, bundle ID `com.macpaw.CleanMyMac5.FinderSyncExtension`. The same process dump lists "CleanMyMac Health Monitor" and "CleanMyMac Menu" as `accessory` apps (no Dock icon). VERIFIED (https://github.com/niklasr22/BrightIntosh/issues/309). What the extension does (Finder badges or context-menu items) is INFERRED / unknown. |
| Launchd labels Homebrew unloads | Only `com.macpaw.CleanMyMac5.HealthMonitor` and `com.macpaw.CleanMyMac5.Menu`. The Updater appears only as a zap-time plist, and the Agent as files to delete. VERIFIED (cask, fetched). |

**X-era comparison (added by fact-checker), VERIFIED from the `cleanmymac-zh` cask (CleanMyMac X Chinese edition 4.15.14), fetched at https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb:** bundle prefix `com.macpaw.zh.CleanMyMac4`. The launchd components were **Agent, HealthMonitor, Menu, Scheduler, Updater**. There was also a Notification Center widget (`…CleanMyMac4.CleanMyMacWidget`, with its own container), a Photos-library private folder for Photo Junk (`~/Pictures/Photos Library.photoslibrary/private/com.macpaw.zh.CleanMyMac4`), and shared data in `/Users/Shared/CleanMyMac-X` and `/Users/Shared/CleanMyMac-X Menu`. So X had a **Scheduler** agent (scheduled scans) and a **widget**. Neither appears in the 5.x cask (INFERRED: both dropped in 5.x).

**Helper install style (INFERRED from cask paths):** 5.x still installs its root helper the pre-macOS-13 way, with a binary in `/Library/PrivilegedHelperTools/` plus a plist in `/Library/LaunchDaemons/` (SMJobBless-era layout). It does not use a daemon plist inside the app bundle (`Contents/Library/LaunchDaemons`), as `SMAppService` expects.

INFERRED for our app: mirror this layout under our own reverse-DNS prefix, e.g. `com.<us>.<App>` main, `.Menu` (LoginItem in `Contents/Library/LoginItems`), `.HealthMonitor` (LaunchAgent plist in `Contents/Library/LaunchAgents`, registered with `SMAppService.agent(plistName:)`), `.Helper` (LaunchDaemon plist in `Contents/Library/LaunchDaemons`, `SMAppService.daemon(plistName:)`), shared App Group container for settings/ignore list/history so all processes read the same state.

---

## 4. Distribution channels, plans, pricing, licensing

### 4.1 Channels
| Channel | Notes | Status |
|---|---|---|
| **MacPaw Store** (direct download DMG/zip) | Full feature set; Basic or Plus; subscription or one-time; plans for 1, 2 or 5 Macs; activate by signing in with MacPaw Account (X also accepted activation numbers); move activation between Macs manually; >5 Macs via support. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/editions ; https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation ; https://macpaw.com/support/cleanmymac/knowledgebase/purchase-options) |
| **Mac App Store** | Sandboxed → reduced features (§4.3); Basic or Plus via IAP; works on all Macs on the Apple Account; 7-day trial then auto-charge; updates via App Store. | VERIFIED (https://apps.apple.com/us/app/cleanmymac/id1339170533?mt=12 ; https://macpaw.com/support/cleanmymac/knowledgebase/missing-features) |
| **Setapp** | Subscription only, full Plus-equivalent feature set; future major upgrades included; Setapp listing shows macOS 11+, 1280×800; "from $9.99/mo" (Setapp) or $9.95/mo app-only. | VERIFIED (https://setapp.com/apps/cleanmymac ; https://macpaw.com/support/cleanmymac/knowledgebase/purchase-options) |
| **Homebrew cask** `cleanmymac` | Third-party packaging of the direct edition (the cask is our best source for file paths). | VERIFIED (fetched) |
| **CleanMyMac X Chinese edition** (added) | A separate, still-X-based build for the Chinese market: homepage `mycleanmymac.com`, bundle `com.macpaw.zh.CleanMyMac4`, distributed as `CleanMyMacXChinese.dmg` via DevMate, Homebrew cask `cleanmymac-zh` (conflicts with `cleanmymac`). It was at **4.15.14** on 2025-12-02, so the "X" line was still maintained for China after 5.0 launched. | VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb, fetched ; Homebrew PR list https://github.com/Homebrew/homebrew-cask/pulls?q=cleanmymac+is%3Apr) |
| CleanMyMac **Business** | Fleet/MDM edition (Jamf integration, automation of Smart Scan / Malware Scan / App Updates) — discontinued, sunset 2026-07-14. | VERIFIED (https://macpaw.com/support/cleanmymac-business/knowledgebase ; https://marketplace.jamf.com/details/cleanmymac-business) |
| CleanMyMac **CLI** | Public beta (v1.0.0; the cask entered homebrew-cask 2026-07-21), `brew install --cask cleanmymac-cli`, proprietary. MacPaw positions it as a developer-focused companion, not a replacement for the desktop app. The README states no price. | VERIFIED (https://github.com/MacPaw/cleanmymac-cli (fetched) ; https://alternativeto.net/news/2026/7/macpaw-launches-cleanmymac-cli-to-clean-developers-caches-leftovers-and-other-junk-files/) |

### 4.2 Plans & pricing
- **Basic vs Plus (since July 2025).** Basic ≈ disk-space focus: Smart Care, Cleanup, Performance, Applications, Menu monitors. Plus adds **Protection** (malware removal + privacy), **Space Lens**, **Cloud Cleanup** (Plus-exclusive from 2025-07-29), duplicates/My Clutter features per some reviews. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans ; https://www.popsci.com/gear/cleanmymac-software-black-friday-deal/ ; https://macpaw.com/cleanmymac/whats-new). Exact row-by-row table not retrieved — GAP.
- **Prices reported by Macworld:** Basic (1 Mac) $9.95/mo, $47.50/yr, $119.95 one-time; Plus (1 Mac) $15.95/mo, $71.40/yr, $195.95 one-time. Older single-tier prices: $39.95/yr (1 Mac), $63.95/yr (2), $127.95/yr (5), $119.95 one-time. VERIFIED (https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html ; https://cybernews.com/resources/macpaw-cleanmymac-review/) — prices vary by region/date.
- **Trial:** 7 days, full functionality, on all three marketplaces. Without trial/plan: every module can *scan*, but cleanup/maintenance/optimization are locked; malware is found but not removed. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/editions ; https://macpaw.com/support/cleanmymac-x/knowledgebase/trial)
- **Activation UI:** "Unlock Full Version" button in the window's upper-right, or menu **CleanMyMac › Activate**; dialog offers 7-day trial / Buy / "I already have a license"; then MacPaw Account email+password. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation)
- **Upgrade policy from X:** subscribers switch free (X licence deactivated); one-time owners get up to 50% off and keep X; CMM 2/3/Classic owners 50% via support. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/upgrade)

INFERRED for our clone: drop all licensing, trial and "Unlock" UI. Keep a hidden internal `FeatureTier` enum only if we ever want a "lite" build. Notification Center's "offers" channel is not needed.

### 4.3 Mac App Store edition limitations (useful as a "what needs privileges" checklist)
VERIFIED from https://macpaw.com/support/cleanmymac/knowledgebase/missing-features, https://macpaw.com/support/cleanmymac/knowledgebase/disk-no-health-and-temperature, https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller, https://macpaw.com/support/cleanmymac/knowledgebase/optimization:

| Area | Missing / restricted in App Store edition |
|---|---|
| Cleanup › System Junk | System Cache Files, System Log Files, Language Files, Universal Binaries, Broken Login Items, Deleted Users, iOS Device Backups (kept: User Cache, User Logs, Xcode Junk, Document Versions, Broken Preferences) |
| Cleanup › Trash Bins / Mail Attachments | available in all editions |
| Protection | no real-time Protection Monitor / malware alerts; Safari privacy items, Wi-Fi network cleanup and app-permission management restricted |
| Performance | some maintenance tasks missing; login items/launch agents can only be reviewed (launch agents uninstalled), not disabled/removed |
| Applications | cannot delete App Store app binaries (only reset); no Leftovers; no App Store/macOS updates via Updater |
| Menu | no Disk Health & Temperature monitors (sandbox) |
| X-era modules absent | Photo Junk, Maintenance, Updater, Shredder |

INFERRED: our direct build should implement everything in this table; these are exactly the features that need FDA, root helper, or non-sandboxed access.

---

## 5. Module map — current CleanMyMac (5.x, as of 5.7.1)

### 5.1 Sidebar / navigation order
VERIFIED feature-table order (https://macpaw.com/support/cleanmymac/knowledgebase/missing-features):
`Smart Care · Cleanup · Protection · Performance · Applications · My Clutter · Space Lens · Cloud Cleanup · My Tools · My Activity · The Menu`
- 2024 launch sidebar had six modules (Smart Care, Cleanup, Protection, Performance, Applications, My Clutter) + an **Assistant** entry at the bottom-left. VERIFIED (https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/ ; https://9to5mac.com/2024/10/16/macpaw-releases-major-update-to-cleanmymac-with-fresh-design-and-new-features/ ; https://www.macobserver.com/mac/macpaw-refreshes-cleanmymac/)
- Space Lens is "a sidebar item" (KB) — VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/space-lens). Cloud Cleanup is chosen from the sidebar — VERIFIED (https://macpaw.com/how-to/icloud-drive-taking-up-space). Email Cleanup: "go to Tools in the sidebar, choose Email Cleanup" — VERIFIED (https://macpaw.com/how-to/organize-email-inbox).
- Global chrome: **bell icon → Notification Center** (5.6.0), "Unlock Full Version" (unlicensed), Smart Insights buttons on items (Tahoe). VERIFIED (https://macpaw.com/cleanmymac/whats-new ; https://macpaw.com/news/introducing-smart-insights)
- KB "Concepts and usage" structure: Basics (Smart Care, My Tools, Mac health, uninstalling) · Protection (malware removal, privacy, app permissions, potentially unwanted applications, scan depth) · Performance · Applications · Clutter · Space Lens · Cloud Cleanup · Email cleanup · The Menu (performance, battery, storage, network, connected devices). VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/concepts-and-usage ; https://macpaw.com/support/cleanmymac/knowledgebase)

INFERRED recommended sidebar for our app (grouped, with section headers):
```
[Overview]   Smart Scan (our Smart Care) · Activity (our My Activity)
[Modules]    Cleanup · Protection · Performance · Applications · Clutter
[Storage]    Space Map (Space Lens) · Cloud Storage (Cloud Cleanup)
[Tools]      Tools hub (favourites + all tools incl. Email/Shredder/etc.)
(bottom)     Health/Assistant status pill · Notification bell · Settings gear
```

### 5.2 Module → sub-features → one-line description

| Module | Sub-features / categories (exact names where verified) | One-line description | Source / status |
|---|---|---|---|
| **Smart Care** | One-click scan running five routines: Cleanup (junk), Protection (malware), Performance (maintenance tasks), Applications (app updates), My Clutter (duplicates). Result **tiles** per module; every task selected by default; uncheck a tile to skip; **Review** opens per-tile detail; **Run**; "Start Over". Excluded modules (via Settings › Scanning) still show as dimmed tiles. Never deletes user files/app data unless the user chooses. Recommends app updates excluding system apps/macOS. | Unified scan-and-fix dashboard. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/smart-care ; https://www.macobserver.com/mac/macpaw-refreshes-cleanmymac/) |
| **Cleanup** | **System Junk** groups: User Cache Files, System Cache Files, User Log Files, System Log Files, Language Files, Universal Binaries, Xcode Junk, Document Versions, iOS Device Backups, Broken Preferences, Broken Login Items, Deleted Users. **Mail Attachments** (local copies only; re-downloadable from Mail). **Trash Bins**: Startup Drive Trash, External Drive Trash, Local Mail Trash. | Remove auto-generated junk, local mail-attachment copies, all trashes. By default only auto-generated system/app data is offered. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/missing-features ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety ; https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk) |
| **Protection** | **Malware Removal** (Moonlock Engine; viruses, adware, spyware, keyloggers, worms, Trojans, ransomware, **potentially unwanted applications**; scan modes Quick / Balanced / Deep). **Privacy** (browsing history, cookies, downloads history, autofill, search queries, last-session tabs, grouped per browser — Safari/Chrome/Firefox; Recent Items: recently accessed servers, launched apps, opened documents; asks to quit browser first). **App Permissions** (review camera, microphone, files/folders, FDA, etc.; recommended ones shown as tiles). Background: **real-time Malware Monitor** + **background scanning**. | Malware scan/remove, privacy traces cleanup, permission audit. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal ; https://macpaw.com/support/cleanmymac/knowledgebase/privacy ; https://macpaw.com/support/cleanmymac/knowledgebase/app-permissions ; https://macpaw.com/support/cleanmymac/knowledgebase/real-time-monitoring-on-off) |
| **Performance** | **Maintenance Tasks** ("View All Tasks"): Free Up RAM, Free Up Purgeable Space (5.0.5+), Flush DNS Cache, Reindex Spotlight, Run Maintenance Scripts / Periodic Scripts (macOS ≤13 only per MacPaw KB; fact-checker note: the `periodic` tool itself still exists on 14/15 and is **gone on macOS 26+**, according to the open-source Mole, which checks `command -v periodic` before running `sudo periodic daily weekly monthly` and skips it if missing: https://raw.githubusercontent.com/tw93/Mole/main/lib/optimize/tasks.sh), Repair Disk Permissions, Speed Up Mail, Thin Time Machine Snapshots (+ X-era Verify Startup Disk, unavailable on APFS). **Login Items** and **Background Items** (enable/disable reversibly; remove permanently). | One-click macOS maintenance + startup items manager. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks ; https://macpaw.com/support/cleanmymac/knowledgebase/optimization ; https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance) |
| **Applications** | Scan → tiles of apps to review/update/remove → **Manage My Applications**. Categories: **Uninstaller** (groups: All Applications, **Unused** = not opened in 6 months, **Suspicious**, …; removes components outside /Applications; system apps on ignore list by default; "reset" app), **Updater** (groups: App Store Updates, Sparkle Updates, Custom Updates, macOS Updates), **Leftovers** (service files of manually removed apps), **Installation files/Installers**. Background scanning so you can act before scan completes (5.5.5). Smart Insights icon next to app names (Tahoe). | Full uninstall, leftovers, installers, updates. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller ; https://macpaw.com/cleanmymac/whats-new) |
| **My Clutter** | Choose location (home, disk, external drive) → scan → **Review All Files**: **Large & Old Files** (sort by size/kind/date accessed), **Duplicates** (content comparison), **Similar Images**, **Downloads** (old DMGs, archives, documents). "Smart Selection" pre-picks the user-side copies; avoids system files. | Personal-file declutter. | VERIFIED-vendor (https://cleanmymac.com/blog/duplicate-file-finder-mac ; https://macpaw.com/how-to/delete-junk-files-on-mac ; https://macpaw.com/support/cleanmymac/knowledgebase/free-up-more-space) |
| **Space Lens** | Pick volume/folder → **Scan** → bubble map (folders as bubbles sized largest→smallest), zoom in, select & remove. Returned in 5.1.0 after being absent in 5.0. Also used by Cloud Cleanup for cloud drives. | Visual disk-usage explorer. | VERIFIED (fetched DevMate notes; https://macpaw.com/support/cleanmymac/knowledgebase/space-lens) |
| **Cloud Cleanup** | Providers: iCloud Drive, Google Drive, OneDrive (5.2.1), Dropbox (5.3.x). Connect account (Google via browser OAuth). Views: Space Lens map + Large Files list per account. Actions: **Remove** (delete from cloud), remove from Mac+cloud, **Unsync** (free local copy, keep in cloud). Google Drive only sees files from Google's official desktop client. Plus-only. | Clean cloud storage and local synced copies. | VERIFIED (fetched DevMate notes; https://macpaw.com/how-to/icloud-drive-taking-up-space ; https://www.iphoneincanada.ca/2025/07/29/cleanmymac-now-helps-you-clean-up-your-cloud-storage-too/ ; https://chrischinchilla.com/blog/2026/cleaning-cloud-storage-with-cleanmymac/) |
| **My Tools** (5.5.0) | Search bar; **Favourites** (star any tool) + **Other Tools**; also openable from the Menu. Example tools: Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions, Email Cleanup. | Pinnable hub of individual tools. | VERIFIED (https://macpaw.com/news/my-tools-cleanmymac ; https://cleanmymac.com/blog/cleanmymac-vs-cleanmymac-x ; App Store notes) |
| **Email Cleanup** (5.7.0, under Tools) | Gmail sign-in (Google OAuth); finds newsletters, promotions, spam, trash, old drafts, large attachments; top senders; **Unsubscribe** (optionally + remove existing), **Archive**, **Move to Trash**; every action confirmed. | Inbox declutter for Gmail. | VERIFIED (https://macpaw.com/cleanmymac/whats-new ; https://macpaw.com/how-to/organize-email-inbox) |
| **My Activity** (5.4.0) | Dashboard: local space cleaned, cloud space freed, malware scans & threats found, items scanned, **time saved** estimate, month-over-month changes, **Health Score** + recommendations. | Progress/stats dashboard. | VERIFIED (https://macpaw.com/news/my-activity-cleanmymac ; https://macpaw.com/support/cleanmymac/knowledgebase/mac-health) |
| **Assistant / Mac Health** | Health score **Excellent · Good · Fair · Requires Attention · Critical** from disk space, threats, battery health, system load, other HW metrics, FDA granted?, recent scan?; recommendations (e.g. "Allow Access" for FDA); maintenance reminders. | Health rating + to-do recommendations. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/mac-health ; https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access ; MacRumors launch article) |
| **The Menu** (menu-bar app) | Monitors: **Health**, **Protection** (Sonar status; real-time/background scan; DB status), **Storage** (free space, disk health & temperature, empty Trash; startup volume only), **Memory** (Free Up, pressure, swap, top apps), **Battery** (health = actual/design mAh; ≥80% Normal, ≤79% Warning, ≤10% Critical — fact-checker: not re-verifiable here, and the "≤10% Critical" band probably refers to *charge*, not health; treat these thresholds as INFERRED), **CPU** (load, temp, top consumers), **Network**, **Connected Devices** (cable/BT/Wi-Fi; up to 3; <20% battery red & on top). Recommendations + weekly cleanup reminders (toggle in Settings › Menu). | Always-on system monitor & quick actions. | VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu ; https://macpaw.com/support/cleanmymac/knowledgebase/devices-monitoring ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-recommendations) |
| **Notification Center** (5.6.0) | Bell icon; product news, offers, messages kept for later. | In-app inbox. | VERIFIED (https://macpaw.com/cleanmymac/whats-new) |
| **Smart Insights** (5.2.6/5.2.7) | Button on unfamiliar items (Cleanup, Protection, Performance, Applications) → Apple Foundation Model explains what it is and whether safe to remove; on-device. | AI explanations. | VERIFIED (https://macpaw.com/news/introducing-smart-insights) |
| **Screen Cleaning Mode** | Temporarily locks keyboard & trackpad while wiping the screen. Appears in App Store "Added" notes (attributed to 5.7.1 / 5.4.0 in different snapshots); MacPaw page listed it as "coming". | Device-cleaning helper. | INFERRED (downgraded from VERIFIED-conflicting: the only source is an App Store snapshot that attributes the feature to two different versions. The App Store was unreachable for re-checking, and the feature is absent from every fetched DevMate note and Homebrew record.) |
| **Accessibility** | VoiceOver support; Reduce Motion honoured (5.0.7). | — | VERIFIED (fetched DevMate notes) |
| **Shredder** | **Removed** in 5.0 (present in X). | Secure delete. | VERIFIED (https://thesweetbits.com/?p=8100 ; Macworld) |
| **CLI (separate)** | `clean` (junk, dev, ai, trash), `purge` (project artifacts, default folders `~/Projects ~/Code ~/dev ~/GitHub ~/Workspace`; >7 days preselected), `analyze`, `optimize ram|purgeable`, `ignore add/list/remove`, `config` (analytics). | Terminal companion. | VERIFIED (https://github.com/MacPaw/cleanmymac-cli, fetched; re-verified by the fact-checker at https://github.com/MacPaw/cleanmymac-cli/wiki/Commands : bare `clean` scans every category; `trash` = system Trash plus Trash on mounted volumes; bare `optimize` runs every task; `--force` applies to `clean`/`purge`; ignored paths are excluded from `clean`, `purge` and `analyze`) |

INFERRED implementation hints (for other tracks to refine): Free Up RAM → `/usr/sbin/purge` (root, via helper); Flush DNS → `dscacheutil -flushcache; killall -HUP mDNSResponder` (root); Reindex Spotlight → `mdutil -E /` (root); Thin TM snapshots → `tmutil listlocalsnapshots /` + `tmutil deletelocalsnapshots <date>` or `tmutil thinlocalsnapshots / <bytes> 4`; Periodic scripts → `periodic daily weekly monthly` only on macOS ≤13; Repair Disk Permissions is effectively obsolete under SIP (offer `diskutil resetUserPermissions / $(id -u)` only as advanced); login/background items → `SMAppService.statusForLegacyPlist`, `~/Library/LaunchAgents`, `/Library/LaunchAgents|LaunchDaemons`, `sfltool dumpbtm` (read-only inspection).

Fact-checker cross-check against the open-source Mole (`tw93/Mole`, `lib/optimize/tasks.sh`, fetched https://raw.githubusercontent.com/tw93/Mole/main/lib/optimize/tasks.sh):
- VERIFIED in shipping code: `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`. Mole skips this under an active VPN, because the SIGHUP drops mDNSResponder's cache. Also verified: `mdutil -s /` to check, then `sudo mdutil -E /` to reindex; `sudo diskutil resetUserPermissions / <uid>`; `qlmanage -r cache` and `qlmanage -r` to reset QuickLook; `tmutil listlocalsnapshots /` to list snapshots; and `sudo periodic daily weekly monthly`, run only if the last `/var/log/daily.out` is more than 7 days old.
- (corrected) `sfltool dumpbtm` is **not** a silent read-only call for a normal user. Run without root it triggers an admin-password dialog ("sfltool wants to make changes"), so Mole only calls it as `sudo -n sfltool dumpbtm`. Our app should run it through the privileged helper, or rely on `SMAppService` plus the plist folders instead.
- (corrected) Periodic scripts: test whether `/usr/sbin/periodic` exists rather than hard-coding "macOS ≤13". It is still present on 14 and 15 and gone on 26+ (per Mole). Hiding it on 14/15 is MacPaw's product choice.
- Mole deliberately removed a swap/VM cleanup task as a crash risk ("Direct virtual memory operations pose system crash risk"). Do not implement swap-file deletion.

---

## 6. Release notes / what's new, 2024–2026 (every known version)

Sources: Homebrew cask commit/PR history (fact-checker; best source for direct-edition ship dates: https://github.com/Homebrew/homebrew-cask/commits/main/Casks/c/cleanmymac.rb), MacPaw What's New (https://macpaw.com/cleanmymac/whats-new), DevMate notes fetched from S3 (https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html), Mac App Store version history (https://apps.apple.com/us/app/cleanmymac/id1339170533?mt=12), Homebrew/third-party version trackers. "Fixes" = "fixed minor issues and known crashes".

| Version | Date (MacPaw / App Store) | What's new | Status |
|---|---|---|---|
| 5.0.0 | 2024-10-16 | New app: six modules, assistant, 25+ tools, tiles UI, My Clutter (large/old, duplicates, similar images, downloads), Protection w/ grouped app permissions, redesigned Menu, Applications incl. app & macOS updates. | VERIFIED (MacRumors; MacPaw news; Homebrew PR "cleanmymac 5.0.0" merged 2024-10-16; DevMate 5.0.0 notes list no individual features) |
| 5.0.1 | 2024-10-29 | Fixes | VERIFIED (Homebrew PR 2024-10-29) |
| 5.0.2 | (corrected) 2024-11-05 (Homebrew) / 2024-11-07 (earlier claim) | Fixes | VERIFIED |
| 5.0.3 | (corrected) 2024-11-12 (Homebrew) / 2024-11-13 (earlier claim) | Fixes | VERIFIED |
| 5.0.4 | (corrected) 2024-12-13; rebuilt 2024-12-16 (`50004.0.2412161309`) and 2024-12-26 (`50004.0.2412181205`) | Fixes | VERIFIED (DevMate; Homebrew PRs https://github.com/Homebrew/homebrew-cask/pulls?q=is%3Apr+%22cleanmymac+5.0%22) |
| 5.0.5 | 2025-02-10 | **Free Up Purgeable Space** maintenance task (removes cached/temporary/re-downloadable data). | VERIFIED (DevMate; whats-new; Homebrew) |
| 5.0.6 | 2025-03-05 | Fixes | VERIFIED |
| 5.0.7 | (corrected) 2025-03-27 | **VoiceOver** support; **Reduce Motion** respected. | VERIFIED (DevMate; Homebrew) |
| 5.0.8 / 5.0.9 | (corrected) 2025-04-29 / 2025-05-13 | Fixes / minor behind-the-scenes improvements | VERIFIED (DevMate; Homebrew) |
| 5.1.0 | 2025-06-12 | **Space Lens returns** — bubble storage map with zoom. (App Store attributes "Welcome back, Space Lens" to 5.1.1, 2025-07-04.) | VERIFIED (DevMate; whats-new; Homebrew 2025-06-12) |
| 5.1.1 | (corrected) 2025-06-27 (direct, Homebrew) / 2025-07-04 (App Store) | Minor improvements | VERIFIED |
| 5.2.0 / 5.2.2 | — | (added) **Never shipped in the direct channel.** Neither the cumulative DevMate notes up to 5.2.5 nor Homebrew's history (which goes 5.1.1 → 5.2.1 → 5.2.3) contain them. INFERRED: the numbers were skipped, or were App Store/internal-only builds. | VERIFIED absence (DevMate S3 notes 50205…, Homebrew commits) |
| (plans) | July 2025 | **Basic / Plus** plans introduced. | VERIFIED (Macworld) |
| 5.2.1 | 2025-07-29 (App Store 2025-08-01) | **Cloud Cleanup** (iCloud Drive, Google Drive, OneDrive): delete cloud files, remove from Mac+cloud, unsync. Plus-only. | VERIFIED (DevMate; https://www.prnewswire.com/news-releases/macpaw-introduces-cloud-cleanup-cleanmymacs-latest-feature-for-smarter-cloud-storage-302514024.html) |
| 5.2.3–5.2.5 | 2025-08-14 / 2025-09-04 / 2025-09-25 (Homebrew; 5.2.5 build 2025-09-24) | Fixes | VERIFIED (DevMate; Homebrew) |
| 5.2.6 | (corrected) **2025-10-17** (Homebrew; the 2025-10-20 date from MacPaw's page is later than Homebrew's pickup, so it is probably a page/announcement date) | **Smart Insights** (Apple Intelligence explanations of system files). App Store lists it under 5.2.7. | VERIFIED |
| 5.2.7–5.2.9 | 2025-10-23 / 2025-10-28 / 2025-10-31 (Homebrew) | Fixes | VERIFIED (whats-new; Wikipedia; Homebrew) |
| 5.2.10 | (added) 2025-11-27 | Release notes not found (INFERRED: fixes) | VERIFIED existence (Homebrew PR "cleanmymac 5.2.10") |
| 5.3.0 | 2025-12-17 (MacPaw & Homebrew) / 2026-01-22 (App Store) | **Dropbox** support + improved **OneDrive** integration in Cloud Cleanup (App Store attributes Dropbox to 5.3.1). INFERRED resolution: Dropbox shipped in **5.3.0** in the direct edition. The App Store got 5.3.0 five weeks late and 5.3.1 days later, so its attribution most likely reflects that lag. | VERIFIED-conflicting (date of 5.3.0 direct release VERIFIED by Homebrew) |
| 5.3.1 | 2026-01-28 / 01-30 | Fixes (+Dropbox per App Store) | VERIFIED (Homebrew 2026-01-28) |
| 5.4.0 | 2026-02-26 / 03-03 | **My Activity** dashboard. | VERIFIED (original researcher; not in Homebrew history, which has a gap from 2026-01-28 to 2026-05-12) |
| 5.5.0 | 2026-04-02 | **My Tools** hub (favourites, search, quick switching). | VERIFIED (original researcher; same Homebrew gap) |
| 5.5.1 – 5.5.4 | 2026-04-21 … (corrected) 5.5.4 build timestamp **2026-05-29 14:49**, Homebrew 2026-06-03/05; the earlier "05-25" date for 5.5.4 cannot be right, since it precedes the build | Fixes | VERIFIED (Homebrew PR "cleanmymac 5.5.4,50504.0.2605291449") |
| 5.5.5 | 2026-07-09 | **Applications module scans in background** (act on apps/leftovers/installers before scan ends). | VERIFIED |
| 5.5.6 | 2026-07-10 | Fixes | VERIFIED |
| 5.5.7 | 2026-07-22 | Fixes | VERIFIED |
| (CLI) | ~2026-07-21 | **CleanMyMac CLI** public beta (separate product, v1.0.0). | VERIFIED |
| 5.6.0 | 2026-08-17 / 08-21 (Homebrew 2026-08-21; build `50600.0.2608201300` = 2026-08-20 13:00, so "08-17" is doubtful unless the first build was replaced) | **Notification Center** (bell icon). | VERIFIED (feature: original researcher; date: Homebrew) |
| 5.6.1 | 2026-09-02 (Homebrew) | Notes not found. | VERIFIED existence/date; notes GAP |
| 5.7.0 | 2026-09-25 | **Email Cleanup** (Gmail): newsletters, promotions, spam, old drafts; unsubscribe/trash/archive; top senders. | VERIFIED (Homebrew 2026-09-25) |
| 5.7.1 | 2026-10-01 | Fixes; App Store lists **Screen Cleaning Mode** (INFERRED, see §5.2). Supports macOS 27 Golden Gate (name VERIFIED in Homebrew `macos_version.rb`; the 2026-09-14 release date is not re-verified). | VERIFIED (Homebrew 2026-10-01; build 2026-09-30 17:54) |
| "Coming next" (as stated on What's New) | — | Smarter detection of leftover **AI tool / AI agent data** (caches, logs, temp files); CLI integration; Cloud Cleanup improvements. | VERIFIED-forward-looking |

---

## 7. CleanMyMac X (4.x) module list — for comparison

VERIFIED sidebar structure (headings Cleanup / Protection / Speed / Applications / Files): https://afb.org/aw/21/6/17076 ; ignore-list scope https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-safety ; App Store limits https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features ; Optimization items https://macpaw.com/support/cleanmymac-x/knowledgebase/optimization.

| X section | X module | What it did | Where it went in 5.x |
|---|---|---|---|
| — | **Smart Scan** | One-click: cleanup + protection + speed; summary with Review Details per scanner | → **Smart Care** (now 5 routines incl. updates & duplicates) |
| Cleanup | **System Junk** | caches, logs, language files, universal binaries, Xcode, broken prefs/login items, document versions, iOS backups, deleted users | → Cleanup › System Junk |
| Cleanup | **Photo Junk** | Photos/iPhoto caches & previews | dropped as separate module (INFERRED: partly merged into System Junk caches) |
| Cleanup | **Mail Attachments** | local attachment copies | → Cleanup |
| Cleanup | **iTunes Junk** | iOS backups, broken downloads, old software updates | → System Junk (iOS Device Backups) |
| Cleanup | **Trash Bins** | all trashes | → Cleanup |
| Protection | **Malware Removal** | Moonlock engine | → Protection |
| Protection | **Privacy** | browser data, recent items, Wi-Fi networks, chats | → Protection › Privacy |
| Speed | **Optimization** | Login Items, Launch Agents, Hung Applications, Heavy Consumers | → Performance (Login/Background Items); hung/heavy apps → Menu monitors |
| Speed | **Maintenance** | maintenance scripts, DNS, Spotlight, RAM, permissions, Mail, TM snapshots | → Performance › Maintenance Tasks |
| Applications | **Uninstaller** | full uninstall, leftovers, reset, Suspicious group | → Applications |
| Applications | **Updater** | Sparkle/App Store/Chrome/Zoom updates | → Applications (Updater) |
| Applications | **Extensions** | Safari/browser extensions, plug-ins, Spotlight/QuickLook/prefpanes | not listed in 5.x module table (GAP — possibly in Protection/Applications). Fact-checker: no 5.x source mentions an Extensions manager. The 5.x bundle does contain a **Finder Sync extension** (§3.2), but that is MacPaw's own Finder integration, not a manager for the user's extensions. Still a GAP. |
| — | **Scheduler** (added) | background agent for scheduled scans/reminders (launchd label `…CleanMyMac4.Scheduler`) | absent from the 5.x cask (INFERRED dropped; reminders moved to Menu "Recommendations") — VERIFIED X-side from the `cleanmymac-zh` cask |
| — | **Widget** (added) | Notification Center widget (`…CleanMyMac4.CleanMyMacWidget`) | absent from the 5.x cask — INFERRED dropped |
| Files | **Space Lens** | sunburst-ish bubble map | dropped in 5.0, back in 5.1 as own sidebar item |
| Files | **Large & Old Files** | biggest/least-used files | → My Clutter |
| Files | **Shredder** | secure erase, fix "can't delete" files | **removed** |
| — | **Assistant** | recommendations (4.10+) | → Assistant / Health / My Activity |
| — | **Menu** | CPU/Memory/Storage/Battery/Protection/Network/Devices | → The Menu |

INFERRED for our clone: implement the union — keep **Shredder** (as a Tool), **Extensions** manager (as a Tool or under Applications), and **Hung/Heavy apps** (in Menu + Performance) since our goal is a "perfect" functional equivalent; users valued them.

---

## 8. Background components & runtime architecture

VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/background-items ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-helper-tool):
- **CleanMyMac Menu** — background item; if disallowed in *System Settings › General › Login Items & Extensions › Allow in the Background*, the Menu won't open and the Settings toggle does nothing.
- **Health Monitor** — background item collecting memory, disk space, battery, CPU, network, unresponsive apps, Trash level; drives Menu indicators and alerts (low disk space, high memory, unresponsive apps, "uninstall completely?" when an app is dragged to Trash); **also powers real-time malware monitoring and background scans**.
- **Agent** — privileged helper; macOS treats it as a helper tool, not a background item; installed when the user first runs an operation needing root (admin password prompt); used to delete system files, uninstall some apps, remove launch agents, flush DNS, clear system caches; inactive unless needed; exits when the app quits; privilege-separated design.
- **Updater** — keeps the app itself updated (X-era: woke every 6 h). Separate from the Updater *module*.
- After install macOS shows a "Background Items Added" notification. VERIFIED (https://macpaw.com/how-to/stop-background-items-added-mac)

INFERRED design for ours (macOS 14+):
- `SMAppService.mainApp` not needed; `SMAppService.loginItem(identifier:)` for the Menu helper app; `SMAppService.agent(plistName:)` for the Health Monitor; `SMAppService.daemon(plistName:)` for the root Helper (requires user approval in Login Items; detect `.requiresApproval` and deep-link with `SMAppService.openSystemSettingsLoginItems()`).
- XPC between processes; helper validates caller by **code-signing requirement** (team ID + bundle ID) using `NSXPCConnection.setCodeSigningRequirement(_:)` (macOS 13+). Helper exposes a minimal, allow-listed API (see §12).
  - Fact-checker VERIFIED (Apple docs JSON): `SMAppService` (`mainApp`, `loginItem(identifier:)`, `agent(plistName:)`, `daemon(plistName:)`, `status`, `register()`, `unregister()` / `unregister(completionHandler:)`, `openSystemSettingsLoginItems()`, `statusForLegacyPlist(at:)`) are all **macOS 13.0+** (https://developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice.json). `daemon(plistName:)` needs the plist in the app's `Contents/Library/LaunchDaemons` (https://developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice/daemon(plistname:).json). `NSXPCConnection.setCodeSigningRequirement(_:)` is macOS 13.0+, must be called before `resume()`, may be called only once, and invalidates the connection on mismatch (https://developer.apple.com/tutorials/data/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:).json). There is also a listener-wide `NSXPCListener.setConnectionCodeSigningRequirement(_:)` (macOS 13.0+) (https://developer.apple.com/tutorials/data/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:).json).
  - Apple's migration guide (VERIFIED, https://developer.apple.com/tutorials/data/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos.json): in agent/daemon plists use **`BundleProgram`** (a bundle-relative path, e.g. `Contents/Resources/mydaemon`) instead of `Program`. Use `AssociatedBundleIdentifiers` only for plists that live outside the bundle. **Register the daemon first**: once the user approves it with admin authentication, the other helpers in the same bundle are approved too, so the user sees fewer prompts. Check status at every launch and call `openSystemSettingsLoginItems()` if approval is missing.
  - INFERRED trade-off: the lazy helper install in §9.2 means one extra approval prompt later. If we want only one prompt, register the daemon during onboarding's Menu-bar step.
  - From CVE-2019-5011 (§2): on every app update, the helper must report its version over XPC. The app must `unregister()` and re-register a stale helper, and must delete any legacy `/Library/PrivilegedHelperTools/<id>` + `/Library/LaunchDaemons/<id>.plist` left by older builds.
- Self-update: Sparkle 2 (or none, for a personal build).

---

## 9. First-launch onboarding flow

### 9.1 What is verified
1. Install: open DMG → drag app to Applications → launch. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation)
2. Licence state: "Unlock Full Version" (top-right) / *CleanMyMac › Activate* → trial / buy / existing licence → MacPaw Account sign-in. VERIFIED (same)
3. Background items registered → macOS "Background Items Added" notification; Menu and Health Monitor must be allowed in the background. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items)
4. **Full Disk Access:** MacPaw advises to *run a Smart Care scan first* because during the scan the app registers its components with macOS (so they appear in the FDA list), then System Settings › Privacy & Security › Full Disk Access › toggle CleanMyMac › Touch ID/password. Shortcut: Assistant shows a Full Disk Access recommendation with an **Allow Access** button. Without FDA, the app cannot scan all areas (junk & malware), email-attachment malware scanning is unavailable and the Health monitor lacks disk data. Older macOS (Mojave–Monterey): Security & Privacy › Privacy › FDA, unlock, add components. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access ; https://macpaw.com/support/cleanmymac-x/knowledgebase/full-disk-access ; https://macpaw.com/support/cleanmymac/knowledgebase/protection-scan-options)
5. Without FDA, users report repeated per-folder prompts (Downloads, Desktop, etc.) on first scan. VERIFIED (X-era review https://macmyths.com/cleanmymac-x-review/)
6. **Admin password / Agent** is requested lazily — the first time an operation needs root. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent)
7. Mac Health score explicitly factors "has FDA been granted" and "recent scan", nudging the user to finish onboarding. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/mac-health)
8. Exact welcome-screen copy/sequence of 5.x: **not found** (GAP).
9. (added) **How MacPaw itself detects and requests FDA**, VERIFIED from MacPaw's open-source **PermissionsKit** (MIT, © 2018 MacPaw; https://github.com/MacPaw/PermissionsKit ; source fetched from https://raw.githubusercontent.com/MacPaw/PermissionsKit/master/PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m):
   - **Detection**: `open(path, O_RDONLY)` on each of `~/Library/Safari/CloudTabs.db`, `~/Library/Safari/Bookmarks.plist`, `~/Library/Application Support/com.apple.TCC/TCC.db` and `/Library/Preferences/com.apple.TimeMachine.plist`. If any file opens, the status is **Authorized**. If none opens and at least one fails with `EPERM`/`EACCES`, it is **Denied**. Otherwise it is **NotDetermined** (for example, the files do not exist). Before 10.14 FDA is reported as authorized. In a sandbox, the real home folder comes from `getpwuid(getuid())`, not `NSHomeDirectory()`.
   - **Request**: there is no API for FDA. The library just opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and never calls a completion handler, so the app must **poll**, or re-check when it becomes active again.
   - This is exactly the pattern for our §9.2 step 3 (now VERIFIED rather than INFERRED for the URL and the probe files).

### 9.2 Recommended onboarding for our app (INFERRED)
| Step | Screen | Behaviour |
|---|---|---|
| 0 | Launch-location check | If not in `/Applications`, offer "Move to Applications" (helper registration via SMAppService requires a stable path). |
| 1 | **Welcome** | App name, original illustration/animation, one sentence, `Get Started`. Respect Reduce Motion. |
| 2 | **What it does** (optional 3 cards) | Clean · Protect · Speed up. `Skip`. |
| 3 | **Full Disk Access** | Explain why (scan caches of other apps, Mail, Safari, Trash). Button `Open System Settings` → `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Before opening, attempt a read of a TCC-protected path (e.g. `~/Library/Safari/Bookmarks.plist` or `~/Library/Mail`) so the app appears in the list. Use the same four-file probe as MacPaw's PermissionsKit (§9.1 item 9), and check on `NSApplication.didBecomeActiveNotification` as well as by timer. Show a small floating panel with our app icon that the user can drag into the list. Poll every 1–2 s (re-try protected read) and auto-advance when granted. `Later` allowed — mark Health as "Requires Attention". |
| 4 | **Notifications** | `UNUserNotificationCenter.requestAuthorization([.alert, .sound, .badge])` with a pre-prompt explaining alerts (low disk, threats found, app moved to Trash). |
| 5 | **Menu bar monitor** | Toggle "Show monitor in menu bar" + "Open at login" → register login item / health agent with SMAppService; explain the system "Background Items Added" notice. |
| 6 | **Privileged helper** | Do **not** install at onboarding; register on first root task with an in-app explainer sheet, then `SMAppService.daemon(...).register()`; if `.requiresApproval`, guide to Login Items. |
| 7 | **First scan** | Land on Smart Scan with a large circular `Scan` button; after scan, show tiles. |
| — | Re-entry | Settings › General › "Show onboarding again"; Health widget shows outstanding permissions. |

---

## 10. Settings / Preferences — every known option

Opened via *CleanMyMac › Settings…* (⌘,). Tab names below are VERIFIED for the 5.x app unless marked X-era.

| Tab | Options (verified) | Source |
|---|---|---|
| **General** | **Updates** section: "Automatically keep CleanMyMac up to date" checkbox (App Store edition: handled by App Store). (Other General options not documented — GAP.) | https://macpaw.com/support/cleanmymac/knowledgebase/general (+ X-era KB) |
| **Scanning** | Left pane lists **Smart Care**; uncheck modules / categories / groups to exclude them from Smart Care (dimmed tiles). X-era: per-module subcategory toggles, e.g. System Junk groups. | https://macpaw.com/support/cleanmymac/knowledgebase/smart-care ; https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk |
| **Ignore List** | Per-category lists: **Cleanup** (System Junk, Mail Attachments), **Protection** (Malware Removal), **Applications** (Uninstaller, Updater), **My Clutter** (Duplicates, Similar Images, Downloads). System apps pre-added (hidden from Uninstaller). Items also added via context action in results. X-era scope: System Junk, Photo Junk, Mail Attachments, iTunes Junk, Malware Removal, Updater, Large & Old Files, Uninstaller. | https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety ; https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller |
| **Protection** | **Enable Malware Monitor** (real-time; recommended on); **background scanning** on/off; **scan mode** Quick / Balanced / Deep (Deep monthly recommended); extra locations: **Scan DMG disk images**, **Scan email attachments** (needs FDA), **Scan archives**, **Scan USB drives**, **iCloud files**. | https://macpaw.com/support/cleanmymac/knowledgebase/real-time-monitoring-on-off ; https://macpaw.com/support/cleanmymac/knowledgebase/background-scanning-on-off ; https://macpaw.com/support/cleanmymac/knowledgebase/protection-scan-options |
| **Menu** | **Enable Menu** on/off; **Recommendations** on/off (feature suggestions + weekly cleanup reminders). TidBITS noted Menu settings are very limited. | https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-on-off ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu-recommendations ; https://tidbits.com/watchlist/cleanmymac-5-0/ |
| **Notifications** (X-era; likely still present) | Checkbox list of alerts: low free space, high memory/RAM warnings, unresponsive apps, Trash size, malware detected, app updates available, "uninstall completely" on app-to-Trash. | https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu ; https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes |
| Assistant (X-era) | Manage Recommendations (4.10+); Ukrainian theme toggle (4.10.4). | DevMate notes (fetched) |
| Language | No in-app picker; follows macOS; per-app language via System Settings › General › Language & Region › Applications. 12 languages: zh-Hans, nl, fr, de, en, it, ja, ko, pl, pt-BR, es, uk. | https://macpaw.com/support/cleanmymac/knowledgebase/languages |
| Units | Temperature unit follows System Settings › Language & Region › Temperature. | https://macpaw.com/support/cleanmymac/knowledgebase/cpu-temperature |
| Appearance | No theme setting found for 5.x (follows system) — GAP/INFERRED. | — |

### 10.1 Recommended Settings spec for our app (INFERRED; superset)
- **General:** Open at login; Show menu-bar monitor; Show Dock icon (LSUIElement switching via `NSApp.setActivationPolicy`); Appearance: System / Light / Dark; Play sounds; Confirm before removal (default on); Removal method: Move to Trash (default) / Delete immediately; Check for updates automatically; Reset all settings; Show onboarding again.
- **Scanning:** Smart Scan composition (module → category → group tree with tri-state checkboxes); System Junk group toggles; minimum age for logs/caches (e.g. 0/7/30 days); Large file threshold (default 50 MB / 100 MB); "Old" threshold (default 1 year); Duplicates minimum size; Similar-images sensitivity; Scan external volumes.
- **Ignore List:** tabbed lists per category (same as MacPaw's) + "+" (add path via NSOpenPanel), "−", drag-and-drop; also "Ignore" context-menu action in every results list. Persist as bookmark/URL + rule type (path prefix, bundle ID, glob).
- **Protection:** real-time monitor; background scan schedule (daily/weekly); scan depth Quick/Balanced/Deep; extra locations (DMG, archives, mail attachments, USB, iCloud Drive); quarantine vs delete.
- **Menu:** enable; which monitors to show; menu-bar label (icon only / CPU % / RAM / free space); recommendations & weekly reminder; low-battery device threshold (20%).
- **Notifications:** per alert toggles + thresholds (free space < X GB, memory pressure ≥ yellow/red for N min, Trash > X GB, app unresponsive > N s, threat found, app updates available, app moved to Trash → offer full uninstall).
- **Privacy/Diagnostics:** local history (My Activity) retention; clear history; no analytics by default.
- **Advanced:** helper status (installed/approved/version, Reinstall, Remove), FDA status with deep link, log export.
- **Language:** follow system (provide per-app language via Info.plist localizations).

---

## 11. Health score, Assistant & My Activity — spec notes

- Five bands: Excellent, Good, Fair, Requires Attention, Critical. VERIFIED (https://macpaw.com/support/cleanmymac/knowledgebase/mac-health). Numeric cutoffs not published — GAP.
- Inputs (VERIFIED): free disk space, threats, battery health, system load (CPU/RAM), other HW/system metrics, FDA granted, recent scan.
- INFERRED scoring for ours: start 100; −30 active threat; −20 free space <10% (−10 <20%); −10 FDA missing; −10 no scan in 14 days; −10 memory pressure red sustained; −5 disk SMART warning; −5 helper not approved; bands ≥90 Excellent, 75–89 Good, 60–74 Fair, 40–59 Requires Attention, <40 Critical. Each deduction produces a recommendation card with a one-click fix.
- My Activity (INFERRED storage): append-only local event log (`scan`, `clean{bytes}`, `threats{n}`, `cloudFreed{bytes}`, `taskRun`) in the App Group container; monthly aggregates; "time saved" = Σ(items reviewed × est. seconds/item) — MacPaw's formula unpublished (GAP).

---

## 12. Safety & security principles (verified behaviours → our rules)

VERIFIED:
- Default offers only auto-generated system/app data; user files never removed unless chosen. (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety)
- System apps cannot be removed and are pre-ignored. (https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller)
- Browser must be quit before privacy cleanup. (https://macpaw.com/support/cleanmymac/knowledgebase/privacy)
- Login item removal is permanent; disabling is reversible. (https://macpaw.com/support/cleanmymac/knowledgebase/optimization)
- Mail attachments: only local copies removed. (https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk)
- Language-file removal once broke an app's code signature (AirBuddy, fixed in 4.10.7). (DevMate notes, fetched)
- CLI: nothing deleted until confirmed; `--force` skips; purge preselects only >7-day-old artifacts; ignore list respected everywhere; protected system locations excluded. (https://github.com/MacPaw/cleanmymac-cli/wiki/Safety-and-Privacy, fetched)
- 2018 Talos CVEs: the root helper exposed generic `removeItemAtPath`, `moveItemAtPath`, `truncateFileAtPath`, `enableLaunchdAgentAtPath`, `removePackageWithID`, etc., without validating the caller or the path → any local process could act as root. (https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716) — Fact-checker: the **13 CVE records** confirm "helper service of CleanMyMac X 4.04, improper input validation → modify the file system as root" (§2). The **specific method names** could not be re-verified because talosintelligence.com was unreachable, so treat the list of names as VERIFIED-weak.
- (added) CVE-2019-5011: CleanMyMac X 4.20's update left the old vulnerable helper in place, i.e. a helper outlived its app version. (https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2019/5xxx/CVE-2019-5011.json)

INFERRED rules for our implementation:
1. Helper API must be **task-specific** (e.g. `flushDNS()`, `runPurge()`, `deleteSystemCaches(ids:)`), never generic file ops; every path must be re-resolved (realpath, no symlink following) and matched against a hard-coded allow-list of roots; caller verified by code-signing requirement.
2. Never touch: `/System`, `/usr` (except `/usr/local` user-installed), `/bin`, `/sbin`, SIP-protected paths, `~/Library/Mobile Documents` (iCloud) except via Cloud module, Photos libraries contents, Keychains, `~/Library/Containers/*/Data/Documents`.
3. Default action = Move to Trash (`FileManager.trashItem`) for user-space items; permanent delete only for caches/logs and only after confirmation; log every removal to the activity log.
4. Skip universal-binary thinning and language-file removal for signed/notarized apps by default (code-signature breakage risk on Apple Silicon); if offered, re-verify signature (`codesign --verify`) and keep a backup.
5. Refuse to clean files of running apps (check `NSRunningApplication` by bundle ID) — prompt to quit.
6. (added, from CVE-2019-5011) Version the helper's XPC protocol. On launch, compare the helper's version with the app's. If they differ, unregister, remove the old helper and re-register before any privileged call, and never leave orphaned helper binaries behind.
7. (added, from Mole) Never delete swap/VM files. Skip the DNS flush while a VPN is active (or warn first). Gate every root-only command behind the helper rather than shelling out to `sudo`.

---

## 13. Naming & branding guidance (INFERRED)

- Do **not** use "CleanMyMac", "Clean My Mac", "MacPaw", "Moonlock", "Smart Care", "My Clutter", "Space Lens", "Sonar" or MacPaw's sidebar icon designs.
- Our equivalents: Smart Care → **Smart Scan**/“Checkup”; My Clutter → **Clutter**/“Files”; Space Lens → **Space Map**; Cloud Cleanup → **Cloud Storage**; My Tools → **Toolbox**; My Activity → **Activity**; The Menu → **Monitor**; Moonlock Engine → our own signature/heuristics engine name.
- Candidate app names (verify trademark/App Store availability before final choice): "Kempt", "Spruce", "Tidewater", "Mintleaf", "Brisk Care".

---

## 14. Gaps / open questions

1. Exact on-screen 5.7.x sidebar order, icons and whether "Assistant" still exists as its own entry vs. folded into My Activity/Health.
2. Full Basic-vs-Plus feature table rows; current live prices.
3. 5.x **General** and **Notifications** settings tab contents (only Updates checkbox verified); whether there is any appearance/theme or sound option.
4. Release notes for 5.2.0, 5.2.2, 5.6.1; definitive version for Screen Cleaning Mode and Dropbox (5.3.0 vs 5.3.1).
5. Exact first-launch welcome screens of 5.x (copy, number of steps).
6. Whether X's **Extensions** module exists anywhere in 5.x.
7. Health score numeric thresholds; "time saved" formula.
8. "Suspicious" group's current definition in 5.x (X-era: apps from RU/BY developers).

### 14.1 Fact-checker follow-up on each gap (2026-10-12)
| # | Gap | Result of this pass |
|---|---|---|
| 1 | 5.7.x sidebar order / Assistant | **Unresolved.** No reachable source shows a 5.7 screenshot or KB text. INFERRED best guess for our build: keep the KB feature-table order (Smart Care → Cleanup → Protection → Performance → Applications → My Clutter → Space Lens → Cloud Cleanup → My Tools → My Activity), with the health/assistant status as a bottom-of-sidebar widget, as at the 2024 launch. |
| 2 | Basic vs Plus table, live prices | **Unresolved** (vendor and store pages blocked). Keep the Macworld figures as dated, region-dependent data. Irrelevant for a personal clone (§4.2). |
| 3 | General/Notifications tabs, theme/sound | **Unresolved.** No 5.x evidence of a theme picker. X-era design used "atmospheric sounds" (Red Dot write-up, §2); whether 5.x has a sound toggle is unknown. INFERRED: provide Appearance and Sounds toggles anyway (§10.1). |
| 4 | 5.2.0 / 5.2.2 / 5.6.1 notes; Screen Cleaning Mode; Dropbox version | **Partly resolved.** 5.2.0 and 5.2.2 never shipped in the direct channel: they are missing from both the cumulative DevMate notes and Homebrew's history. 5.6.1 shipped 2026-09-02 (Homebrew); its notes are still missing. Dropbox: 5.3.0 shipped directly on 2025-12-17, so INFERRED Dropbox = 5.3.0, with the App Store attribution to 5.3.1 explained by App Store lag. Screen Cleaning Mode: still unconfirmed; downgraded to INFERRED. |
| 5 | First-launch welcome screens | **Unresolved.** Added verified FDA detection and request mechanics from MacPaw's PermissionsKit (§9.1 item 9). |
| 6 | Extensions module in 5.x | **Unresolved.** New finding: 5.x ships a Finder Sync extension (`com.macpaw.CleanMyMac5.FinderSyncExtension`). That is a different thing from X's Extensions manager. |
| 7 | Health score thresholds; "time saved" formula | **Unresolved.** Keep our INFERRED scoring (§11). |
| 8 | "Suspicious" in 5.x | X-era definition re-VERIFIED from DevMate 4.10.4 notes: apps "tied to Russian or Belarusian developers". The 5.x definition is **unresolved**. INFERRED: for our clone, define "Suspicious" technically (unsigned / ad-hoc signed / not notarized / quarantine-flagged / Gatekeeper-rejected apps via `SecStaticCodeCheckValidity` + `spctl --assess`), not by developer nationality. |
| 9 | Proxy block | Confirmed and wider than first reported (list in §0). |

---

## 15. Source list (primary first)

Primary / MacPaw:
- https://macpaw.com/cleanmymac/whats-new — 5.x release notes
- https://macpaw.com/cleanmymac-x/whats-new — X release notes
- https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html (fetched)
- https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html (fetched)
- https://macpaw.com/support/cleanmymac/knowledgebase (index), …/concepts-and-usage, …/smart-care, …/missing-features, …/feature-plans, …/editions, …/purchase-options, …/installation-activation, …/upgrade, …/operating-systems, …/full-disk-access, …/background-items, …/allow-background-items, …/cleanmymac-processes, …/cleanmymac-agent, …/cleanmymac-helper-tool, …/cleanmymac-safety, …/uninstaller, …/maintenance-tasks, …/optimization, …/privacy, …/app-permissions, …/malware-removal, …/real-time-monitoring-on-off, …/background-scanning-on-off, …/protection-scan-options, …/space-lens, …/cleanmymac-menu, …/the-menu, …/cleanmymac-menu-on-off, …/cleanmymac-menu-recommendations, …/devices-monitoring, …/mac-health, …/languages, …/cpu-temperature, …/disk-no-health-and-temperature, …/moonlock-engine, …/free-up-more-space
- https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features, …/system-junk, …/cleanmymac-safety, …/cleanmymac-x-menu, …/trial, …/full-disk-access, …/maintenance, …/operating-systems
- https://macpaw.com/news/introducing-new-cleanmymac ; https://macpaw.com/news/my-activity-cleanmymac ; https://macpaw.com/news/my-tools-cleanmymac ; https://macpaw.com/news/introducing-smart-insights ; https://macpaw.com/news/cleanmymac-cli ; https://macpaw.com/news/cleanmymac-x-has-arrived ; https://macpaw.com/news/cleanmymac-x-update-4.4.0 ; https://macpaw.com/news/cleanmymac-anniversary ; https://macpaw.com/news/cleanmymac-received-ux-design-awards
- https://macpaw.com/how-to/organize-email-inbox ; https://macpaw.com/how-to/icloud-drive-taking-up-space ; https://macpaw.com/how-to/stop-background-items-added-mac
- https://macpaw.com/download/cleanmymac ; https://cleanmymac.com/ ; https://cleanmymac.com/blog/cleanmymac-vs-cleanmymac-x ; https://cleanmymac.com/blog/duplicate-file-finder-mac
- https://github.com/MacPaw/cleanmymac-cli and wiki (fetched)
- https://apps.apple.com/us/app/cleanmymac/id1339170533?mt=12 ; https://setapp.com/apps/cleanmymac
- Homebrew casks (fetched): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb ; …/cleanmymac-zh.rb ; https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb

Press / reviews:
- https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/
- https://9to5mac.com/2024/10/16/macpaw-releases-major-update-to-cleanmymac-with-fresh-design-and-new-features/
- https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/
- https://tidbits.com/watchlist/cleanmymac-5-0/ ; https://tidbits.com/watchlist/cleanmymac-4-14/
- https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html
- https://www.macobserver.com/mac/macpaw-refreshes-cleanmymac/
- https://9to5mac.com/2020/04/28/clean-my-mac-x/ ; https://9to5mac.com/2022/06/30/cleanmymac-x-new-menu-bar-app/
- https://www.prnewswire.com/news-releases/macpaw-introduces-cloud-cleanup-cleanmymacs-latest-feature-for-smarter-cloud-storage-302514024.html
- https://www.iphoneincanada.ca/2025/07/29/cleanmymac-now-helps-you-clean-up-your-cloud-storage-too/ ; https://chrischinchilla.com/blog/2026/cleaning-cloud-storage-with-cleanmymac/
- https://thesweetbits.com/tools/cleanmymac-review/ ; https://afb.org/aw/21/6/17076 ; https://en.wikipedia.org/wiki/CleanMyMac

Security:
- https://talosintelligence.com/vulnerability_reports/TALOS-2018-0715 … -0721 ; https://vulnerability.cert.dk/vuln/fkie_cve-2018-4044

Open-source references for implementation:
- https://github.com/MacPaw/cleanmymac-cli (proprietary, docs only)
- https://github.com/tw93/Mole (GPL-3.0; clean/uninstall/optimize/analyze/status/purge/installer; dry-run, whitelist `~/.config/mole/whitelist`, operations log `~/Library/Logs/mole/operations.log`)
- https://github.com/alienator88/Pearcleaner (Apache-2.0 + Commons Clause; uninstaller + orphaned files + "Sentinel" Trash monitor; FDA + privileged helper; macOS 13+) — licence forbids reuse in a monetised product; fine to study. Re-checked by the fact-checker: development is **on hold** at v5.4.3; supports macOS 13–15 and 26. Also includes app lipo, translation pruning, a PKG manager, a Homebrew manager, and a Finder extension for right-click uninstall.
- https://github.com/MacPaw/PermissionsKit (MIT, MacPaw) — FDA detection and deep link (§9.1 item 9). **Licence-compatible, so it can be reused directly.**
- Mole (`tw93/Mole`), re-checked: GPL-3.0, macOS 12+, Intel + Apple Silicon; optimize tasks live in `lib/optimize/tasks.sh` (commands quoted in §5).

Fact-checker additional sources (all fetched):
- Homebrew cask history: https://github.com/Homebrew/homebrew-cask/commits/main/Casks/c/cleanmymac.rb ; PR lists https://github.com/Homebrew/homebrew-cask/pulls?q=cleanmymac+is%3Apr and https://github.com/Homebrew/homebrew-cask/pulls?q=is%3Apr+%22cleanmymac+5.0%22
- Homebrew macOS names: https://raw.githubusercontent.com/Homebrew/brew/main/Library/Homebrew/macos_version.rb ; https://raw.githubusercontent.com/Homebrew/brew/main/Library/Homebrew/brew.sh
- CVE records: https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-40{32,33,38,40,41,42,47}.json ; https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2019/5xxx/CVE-2019-5011.json ; https://github.com/advisories?query=CleanMyMac
- Apple docs (JSON): servicemanagement/smappservice, …/daemon(plistname:), …/statusforlegacyplist(at:), …/updating-helper-executables-from-earlier-versions-of-macos ; foundation/nsxpcconnection/setcodesigningrequirement(_:) ; foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)
- Running-process evidence for 5.x components: https://github.com/niklasr22/BrightIntosh/issues/309
- CLI wiki: https://github.com/MacPaw/cleanmymac-cli/wiki/Commands ; https://github.com/MacPaw/cleanmymac-cli/wiki/Safety-and-Privacy

---

## Verification notes

Adversarial fact-check performed 2026-10-12. Constraints: the shared WebSearch budget was exhausted before this pass, so zero searches ran. MacPaw, App Store, Setapp, Wikipedia, press, Talos and NVD hosts were DNS-blocked. Everything below was checked with direct fetches of GitHub, raw.githubusercontent.com, the DevMate S3 bucket and developer.apple.com JSON.

**Checked and confirmed (claim → evidence)**
1. Latest version 5.7.1, build `50701.0.2609301754`, Sparkle feed and download URL pattern, `auto_updates true` → current Homebrew cask (fetched).
2. Bundle IDs, login-item name, helper paths, Updater LaunchAgent, App Group/Team ID `S8EX82NJP6`, every zap path → same cask.
3. macOS 27 is named "Golden Gate" → Homebrew `macos_version.rb`.
4. Direct-edition ship dates for 5.0.0–5.3.1 and 5.5.4–5.7.1 → Homebrew commit and PR history.
5. 5.0.5 Purgeable Space, 5.0.7 VoiceOver/Reduce Motion, 5.1.0 Space Lens, 5.2.1 Cloud Cleanup (iCloud/Google Drive/OneDrive; delete / remove from Mac+cloud / unsync) → DevMate notes (re-fetched).
6. X 4.10.0–4.12.2 history (Assistant recommendations, RU/BY sales stop, Suspicious group, Ukrainian theme toggle, AirBuddy signing fix, Menu redesign, 10.10/10.11 dropped in 4.11.0, Network Monitor, Chrome/Zoom in Updater, Ventura) → DevMate X notes (re-fetched).
7. CLI: cask contents, commands, default purge folders, 7-day preselection, `--force`, ignore semantics, local processing and analytics toggle → MacPaw tap cask + CLI wiki.
8. `SMAppService` API surface and macOS 13 availability; `daemon(plistName:)` plist location; `BundleProgram`; register-daemon-first guidance; `NSXPCConnection.setCodeSigningRequirement` and `NSXPCListener.setConnectionCodeSigningRequirement` (macOS 13) → Apple docs.
9. FDA deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` and probe-file detection → MacPaw PermissionsKit source.
10. Maintenance commands (DNS flush, `mdutil`, `diskutil resetUserPermissions`, `qlmanage -r`, `tmutil listlocalsnapshots`, `periodic`) → Mole source.
11. Pearcleaner licence, minimum macOS and features; Mole licence and paths → their READMEs.

**Corrected in place (marked "(corrected)")**
- Talos CVEs: 13 CVEs, 4032–4037 and 4041–4047 (not "~10, 4032…4047"); public 2019-01-10. The "patched 2018-12-27" date is unverified. Added CVE-2019-5011 (4.20, stale helper after update).
- `sfltool dumpbtm` requires admin/root (it prompts otherwise), so it is not a silent read-only call.
- Periodic scripts: availability depends on the tool being present (it is still on 14/15 and removed in 26+), not a fixed "≤13" rule.
- 4.11.2 added Zoom to Updater (Chrome came in 4.11.3); 4.10.0 recommendations show in the Menu (no "manage in Preferences" claim).
- Release dates: 5.0.2 (11-05), 5.0.3 (11-12), 5.0.4 (12-13, with rebuilds), 5.0.7 (03-27), 5.0.8 (04-29), 5.0.9 (05-13), 5.1.1 (06-27 direct), 5.2.3/5.2.4 dates, 5.2.6 (10-17, not 10-20), 5.5.4 (build 05-29, so "05-25" is impossible), 5.6.0 (the build date 08-20 conflicts with "08-17"), 5.6.1 (09-02).
- Homebrew min-OS: the current cask no longer pins Big Sur (housekeeping change on 2026-09-10).

**Added (not in the original report)**
- 5.2.10 (2025-11-27); 5.2.0 and 5.2.2 confirmed absent from the direct channel.
- 5.x **Finder Sync extension** component; Menu and Health Monitor run as `accessory` apps.
- X-era **Scheduler** agent and **Notification Center widget**; X Chinese edition (`cleanmymac-zh`, mycleanmymac.com, 4.15.14 in Dec 2025) as an extra distribution channel.
- 5.x root helper uses the legacy `/Library/PrivilegedHelperTools` + `/Library/LaunchDaemons` layout (INFERRED from cask).
- MacPaw PermissionsKit (MIT) as a reusable FDA component; helper-versioning and VPN/swap safety rules.

**Downgraded to INFERRED**
- CleanMyMac 2 release date (single mirror source).
- Screen Cleaning Mode (single, self-contradicting App Store snapshot).
- Menu battery thresholds (flagged; "≤10% Critical" looks like charge, not health).
- Talos helper method names are kept but labelled VERIFIED-weak (the CVE records do not name methods).

**Still uncertain (needs a session with macpaw.com / App Store access or a real Mac running 5.7.1)**
- Exact 5.7.x sidebar order, icons and the Assistant's placement; the Basic-vs-Plus table and current prices; General/Notifications settings contents and any theme/sound options; first-launch screens; whether an Extensions manager exists in 5.x; Health score cutoffs and the "time saved" formula; the 5.x "Suspicious" definition; release notes for 5.2.10 and 5.6.1; the 5.4.0/5.5.0–5.5.3 dates (missing from Homebrew history); the Mac App Store edition's 2020-04-28 debut date; every MacPaw-KB-only claim (KB-sourced rows in §§4, 5, 8–10), which rest on the original researcher's search-engine extraction.
- Best next step (INFERRED): install the 5.7.1 trial on the Mac mini, record the sidebar and Settings panes, and dump the bundle (`Contents/Library`, `Contents/PlugIns`, `Info.plist`, `.lproj` string keys for structure only, without copying text) to settle gaps 1, 3, 5 and 6.
