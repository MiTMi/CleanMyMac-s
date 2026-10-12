# 11: Open-source projects to learn from, plus a Swift/macOS API cookbook

> Track: open-source landscape and a concrete Swift API cookbook for building our own CleanMyMac-class app ("the app" below; the name is still to be decided). Target: Apple Silicon Mac mini, macOS 14 Sonoma through macOS 26 Tahoe, Swift 6 and SwiftUI, Developer-ID or local-only distribution (no sandbox).
> Date of research: 2026-10-12.
> Fact-checked on 2026-10-12. Corrected items are marked "(corrected)", and new material is marked "(added)" or "(upgraded)". New sections: §3.12 (more OSS projects) and §4.30 (cookbook additions). The summary is in "Verification notes" at the end.

---

## 0. Method, labels, caveats

**How this was researched.** The shared WebSearch budget for this run was already used up when this track started. Every WebSearch call returned "budget used up", so no search-engine queries could be made. To make up for it, this track relied on primary sources:

- **GitHub code search** (GitHub MCP) to locate files, then **raw source downloads** from `raw.githubusercontent.com`. Over 80 source files were read: Pearcleaner, Mole, Stats, Latest, KnockKnock, czkawka, dupeGuru, MacSai, Radix, PermissionsKit, Sparkle, LaunchAtLogin-Modern, SecureXPC and others.
- **Apple developer documentation JSON** (`developer.apple.com/tutorials/data/documentation/<path>.json`). About 90 symbol pages were fetched to confirm API names, signatures, availability and deprecations.
- **WebFetch** of project pages where the network allowed it, such as GrandPerspective. These sites were unreachable through the egress proxy: titanium-software.fr (OnyX), talosintelligence.com, nvd.nist.gov, wikipedia and sparkle-project.org. As a workaround, CVE text was read from the `CVEProject/cvelistV5` JSON on GitHub.

**Labels used throughout**

| Label | Meaning |
|---|---|
| **VERIFIED-SRC** | I read the actual source file at the cited URL |
| **VERIFIED-README** | Stated in the project's README or LICENSE at the cited URL |
| **VERIFIED-DOC** | Confirmed against Apple's documentation page (symbol, signature, availability) at the cited URL |
| **INFERRED** | My reasoning or recommendation, or widely known behavior I could not re-verify in this session. Test it on the Mac mini |

**Licensing rule for the team (INFERRED, important).**

- Code under **GPL-2/3** (Mole, KnockKnock/BlockBlock/LuLu, Latest, dupeGuru, GrandPerspective, Lemon) may only be studied for ideas, thresholds and path lists. Do **not** copy code from it unless we GPL our app.
- Pearcleaner is **Apache-2.0 + Commons Clause**. That is source-available but not OSI open source, and it forbids monetization. Study it, don't paste from it.
- Code under **MIT/BSD/ISC** (Stats, MacSai, PureMac, Radix, czkawka-core, Sparkle, sindresorhus packages, SecureXPC, PermissionsKit, Clean-Me, eul, GRDB) can be reused if we keep the license notices.
- The snippets in §4 below are original and written for us.

---

## 1. Executive summary (what matters for the build)

1. **The closest open-source analogues to CleanMyMac are now very mature.** Use them as reference implementations:
   - **MacSai** (BSD-3, Swift 6, 17 modules, privileged helper, separate menu-bar process, 862 tests).
   - **PureMac** (MIT, SwiftUI).
   - **Mole** (GPL-3 shell+Go CLI, about 70k stars; best for path lists, maintenance commands and safety heuristics).
   - **Pearcleaner** (uninstaller and leftover-matching engine).
   - **Stats** (MIT; best for every system-metric reader).

   VERIFIED-README: [MacSai](https://github.com/iliyami/MacSai), [PureMac](https://github.com/momenbasel/PureMac), [Mole](https://github.com/tw93/Mole), [Pearcleaner](https://github.com/alienator88/Pearcleaner), [Stats](https://github.com/exelban/stats).
2. **MacPaw publishes two relevant things.**
   - **`MacPaw/PermissionsKit`** (MIT) shows MacPaw's own Full Disk Access probe: open TCC-protected files and treat EPERM/EACCES as "denied".
   - **`MacPaw/cleanmymac-cli`** (released June 2026) is under a proprietary EULA, *not* open source. Its README still documents MacPaw's own cleanup categories (`clean junk|dev|ai|trash`), the purge defaults (artifacts older than 7 days preselected) and `optimize ram|purgeable`.

   VERIFIED-SRC/README: [PermissionsKit FDA](https://github.com/MacPaw/PermissionsKit/blob/master/PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m), [cleanmymac-cli README](https://github.com/MacPaw/cleanmymac-cli), [cleanmymac-cli LICENSE (EULA)](https://github.com/MacPaw/cleanmymac-cli/blob/main/LICENSE).
3. **Privileged work.** Use `SMAppService.daemon(plistName:)` (macOS 13+) plus `NSXPCConnection` with `setCodeSigningRequirement` / `NSXPCListener.setConnectionCodeSigningRequirement` (macOS 13+). `SMJobBless` and `SMLoginItemSetEnabled` have been deprecated since macOS 13, and `AuthorizationExecuteWithPrivileges` since 10.7. VERIFIED-DOC (see §4.21).
   - Pearcleaner's helper validates clients **by PID** and exposes a **generic `/bin/bash -c` runner** (VERIFIED-SRC). Do not copy that pattern. It is exactly the class of bug behind CleanMyMac X's 2018 Talos CVEs. See 10-internals.md §3.3.
4. **Fast disk scanning.** Start with `FileManager.enumerator(at:includingPropertiesForKeys:)`, prefetching `.totalFileAllocatedSizeKey` and related keys. Add a `getattrlistbulk(2)` fast path, as Radix (MIT) does. Deduplicate hard links by (device, inode). Never trigger iCloud downloads: skip dataless files. Bound concurrency: Mole caps workers at 2–12 after thread exhaustion crashes. VERIFIED-SRC (§3.2, §4.1–4.2).
5. **Memory.** Activity-Monitor-style numbers come from `host_statistics64(HOST_VM_INFO64)`:
   - App = internal − purgeable
   - Cached = external + purgeable
   - Used = App + wired + compressed
   - Pressure comes from sysctl `kern.memorystatus_vm_pressure_level` (1/2/4)

   Stats uses a closely related formula (VERIFIED-SRC). The internal − purgeable mapping is the community consensus: at least six independent OSS monitors label it "Activity Monitor's App Memory" (VERIFIED-SRC in the fact-check, §4.8). Apple does not document it, so still compare against Activity Monitor on the Mac mini.
6. **Per-process CPU on Apple Silicon.** `proc_pid_rusage` reports `ri_user_time`/`ri_system_time` in **mach ticks** (timebase 125/3), not nanoseconds. Convert with `mach_timebase_info`. VERIFIED-SRC from OSS comments (§4.10).
7. **Network counters.** `if_data.ifi_ibytes` from `getifaddrs` is **32-bit and wraps at 4 GiB**. Use sysctl `NET_RT_IFLIST2` → `if_msghdr2.ifm_data` (`if_data64`), as Stats does (VERIFIED-SRC, §4.12).
8. **macOS 15 / 26 / 27 notes.**
   - **(corrected)** `/usr/sbin/periodic` has been **gone since macOS 15 Sequoia**, not only since 26. A forensic test of a 15.6.1 host found no `/usr/sbin/periodic`, no `/etc/periodic` and no `com.apple.periodic-*` jobs ([AppliedIR cron_at.yaml](https://raw.githubusercontent.com/AppliedIR/sift-mcp/main/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml)). 05-performance.md also found the `periodic(8)` man page missing from the 15, 26 and 27 man sets. Mole's and MacSai's code comments say "removed in macOS 26+", but both check for the binary at runtime, so they behave correctly. Our app should do the same: offer the task only when the binary exists, which in practice means macOS 14.
   - **(corrected, added)** On macOS 26, `lsregister -kill` is **removed**. It prints "The -kill option has been removed because it was dangerous and no longer useful" and exits 1, and `-domain` is gone too. MacSai still calls the old form. Use `lsregister -gc` plus `-r` with `-all` or `-apps local,system,user` instead (§4.23). VERIFIED-SRC: several independent measurements on macOS 26, e.g. [MadMartian/Scribobulate README](https://github.com/MadMartian/Scribobulate/blob/master/packaging/macos/README.md) and [kdeldycke/dotfiles](https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh).
   - macOS 26 adds **System Settings → Menu Bar** per-app visibility toggles that can hide our menu extra (VERIFIED-README, Stats FAQ, re-checked).
   - **(added)** macOS 27 is current as of this date. Homebrew calls it `golden_gate`, and OnyX ships a separate 5.1.0 build for it. It also moves the Background Task Management store to **one file per user**, `BackgroundItems-v18-<user UUID>.btm` (§3.7). The app should be built for 27 as well as 14–26.
9. **Mac mini specifics (INFERRED).** There is no battery, so hide battery UI when `IOPSCopyPowerSourcesList` has no internal battery, but support a USB **UPS** power source, as Stats does. There is a fan, but fan speed and temperature need private SMC/IOHID access. `ProcessInfo.thermalState` is the only public signal.

---

## 2. Landscape at a glance

| Project | License | Lang | What to learn | Status (2026) |
|---|---|---|---|---|
| [MacSai](https://github.com/iliyami/MacSai) | **BSD-3** | Swift 6/SwiftUI | Whole-app architecture (App + Kit + XPC Helper + Menu agent), `SafetyGuard`, maintenance task table, duplicate pipeline, APFS clone "Consolidate", treemap | Active, ~1.8k★ |
| [PureMac](https://github.com/momenbasel/PureMac) | **MIT** | Swift/SwiftUI (XcodeGen) | Honest scan philosophy, "purgeable is not junk", Similar Photos (perceptual hash), scheduled clean | Active, ~7k★ |
| [Burrow](https://github.com/caezium/burrow) | MIT app + FSL-1.1 engine | Swift | Native GUI over a Mole-like engine, MCP/agent hooks, SQLite metric history | Active |
| [tw93/Mole](https://github.com/tw93/Mole) | **GPL-3** | Bash + Go | Exhaustive cleanup paths, 20 optimize tasks with exact commands, health score, analyzer scanner (du + mdfind + hard-link dedup), purge artifacts, protection lists, op log | Very active, ~70k★ |
| [Pearcleaner](https://github.com/alienator88/Pearcleaner) | Apache-2.0 **+ Commons Clause** | Swift/SwiftUI | Leftover-matching engine (3 sensitivity levels), search locations, container discovery, Spotlight supplement, per-app conditions, lipo w/o Xcode, Sentinel (auto-clean on Trash) | **On hold** since late 2025 (v5.4.3) |
| [exelban/stats](https://github.com/exelban/stats) | **MIT** | Swift/AppKit | Every metric reader: RAM, CPU, net (64-bit), disk I/O, battery, sensors, top processes | Active |
| [mangerlahn/Latest](https://github.com/mangerlahn/Latest) | **GPL-3** | Swift | Update checker: Sparkle appcast discovery, Mac App Store lookup API, Homebrew cask API | Active |
| [Objective-See KnockKnock](https://github.com/objective-see/KnockKnock) / BlockBlock / LuLu / [DumpBTM](https://github.com/objective-see/DumpBTM) | **GPL-3** | ObjC | Persistence enumeration taxonomy (**20 plugins (corrected)**: 21 header pairs including `PluginBase`), BTM database parsing | Active |
| [czkawka](https://github.com/qarmin/czkawka) | **MIT** (core/GTK/CLI); GPL-3 (Krokiet) | Rust | Duplicate pipeline (size→4 KB head+tail prehash→full hash), hard-link filter, similar images (perceptual hash + BK-tree) | Active |
| [dupeGuru](https://github.com/arsenetar/dupeguru) | **GPL-3** | Python/Qt | Partial digest (16 KB @16 KB), 3-sample digest for >3 MiB, xxh128; picture "blocks" 15×15 | Maintained |
| [GrandPerspective](https://grandperspectiv.sourceforge.net/) | **GPL** | ObjC | Treemap, scan filters (name/path/size/type/hard-link/package), saved scans; v3.8.1 (13 Sep 2026) needs macOS 14+ | Active |
| OnyX (Titanium Software) | Freeware, **closed** | n/a | Catalogue of maintenance tasks (vendor site still unreachable; see §3.9 for a community-sourced 5.x task list) | Active. Separate build per OS: 4.6.2 (14), 4.8.5 (15), 5.0.5 (26), 5.1.0 (27). VERIFIED: [Homebrew cask](https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/o/onyx.rb) |
| [Sparkle 2](https://github.com/sparkle-project/Sparkle) | **MIT**-style | ObjC/Swift | Our own app's self-update (EdDSA-signed appcasts) | Active; runtime macOS 12+ on `2.x` |
| [sindresorhus/LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern), Defaults, KeyboardShortcuts, Settings | **MIT** | Swift | Login-item toggle (SMAppService.mainApp), prefs, hotkeys | Active |
| [trilemma-dev/SecureXPC](https://github.com/trilemma-dev/SecureXPC), [Blessed](https://github.com/trilemma-dev/Blessed) | **MIT** | Swift | Codable XPC routes; checks the actual caller, not PIDs | Stable |
| [orchetect/MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | **MIT** | Swift | Programmatic show/hide of `MenuBarExtra(.window)` | Active |
| [gao-sun/eul](https://github.com/gao-sun/eul) | **MIT** | SwiftUI | Menu-bar system monitor UI ideas | Older |
| [Kevin-De-Koninck/Clean-Me](https://github.com/Kevin-De-Koninck/Clean-Me) | **MIT** | Swift | Tiny early cleaner, shell-driven | Old |
| [Tencent/lemon-cleaner](https://github.com/Tencent/lemon-cleaner) | **GPL-3** (Daemon **GPL-2**) | ObjC | Module split: Monitor, BigOldFile, DuplicateFile, PhotoClean, Uninstaller, PrivacyClean, LoginItemManager, SpaceAnalyse, Hardware | Published 2022 |
| [MacPaw/PermissionsKit](https://github.com/MacPaw/PermissionsKit) | **MIT** | ObjC | MacPaw's FDA probe | Old but valid |
| [MacPaw/cleanmymac-cli](https://github.com/MacPaw/cleanmymac-cli) | **Proprietary EULA** | n/a | Official categories, purge rules | Public beta |
| [colinvkim/Radix](https://github.com/colinvkim/Radix) | **MIT** | Swift | Production `getattrlistbulk` enumerator incl. APFS clone IDs, dataless detection | Active |
| [mas-cli/mas](https://github.com/mas-cli/mas) | MIT | Swift | Mac App Store CLI (outdated/upgrade) | Active |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | Swift | SQLite (MacSai uses it with WAL for history/logs) | Active |
| *(added in fact-check)* [jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app) | **MIT** | Swift/SwiftUI | Trash-only cleaner. Simulators and snapshots are the only non-Trash removals. Ollama blob-aware sizes, Cleaning History, onboarding with FDA | Active, ~1.1k★ |
| *(added)* [dsswift/cmm](https://github.com/dsswift/cmm) | **no LICENSE file** (all rights reserved; ideas only) | Swift (SwiftPM + Makefile) | "Trash only" invariant enforced by a test that greps the source tree, `setiopolicy_np` dataless opt-out, signing/FDA advice, BTM bridge | Active |
| *(added)* [sindresorhus/macos-trash](https://github.com/sindresorhus/macos-trash) + [DSStore](https://github.com/sindresorhus/DSStore) | **MIT** | Swift | Repairs Finder **Put Back** metadata that `trashItem` drops (§4.3) | Active |
| *(added)* [AlexTkDev/MacOSCleaner](https://github.com/AlexTkDev/MacOSCleaner) | Source-available, personal use only | Swift | Another SwiftUI "CleanMyMac alternative" (uninstaller, analyzer, duplicates) | Active, ~120★ |
| *(added)* [vashpan/xcode-dev-cleaner](https://github.com/vashpan/xcode-dev-cleaner) | **GPL-3** | Swift | Xcode junk categories (DerivedData, archives, device support, simulators) | Older |

Licenses were VERIFIED-README/LICENSE by fetching each repo's LICENSE file during this session. Note that MacSai's comparison table calls Mole "MIT", but Mole's LICENSE file is **GPL-3.0** (VERIFIED: [Mole LICENSE](https://github.com/tw93/Mole/blob/main/LICENSE)).

*Fact-check:* the LICENSE files were re-fetched for Mole (GPL-3), Pearcleaner (Apache-2.0 + Commons Clause), Stats (MIT), Latest (GPL-3), MacSai (BSD-3), PureMac (MIT), Radix (MIT), KnockKnock (GPL-3), dupeGuru (GPL-3), czkawka (MIT for core/GTK/CLI, GPL-3 for Krokiet/Cedinia per README) and Sparkle. All match. Star counts were re-read from GitHub search on 2026-10-12: Mole 70,040, Pearcleaner 14,841, PureMac 7,063, MacSai 1,826. Pearcleaner's README still says "Project Status: On Hold", version 5.4.3.

---

## 3. Project deep dives (implementation-relevant details)

### 3.1 Pearcleaner: app uninstaller and leftover matcher

Sources: [README](https://github.com/alienator88/Pearcleaner), [Locations.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/Locations.swift), [AppPathsFetch.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/AppPathsFetch.swift), [Conditions.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/Conditions.swift), [AppInfoFetch.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/AppInfoFetch.swift), [Lipo.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/Lipo.swift), [HelperToolManager.swift](https://github.com/alienator88/Pearcleaner/blob/main/Pearcleaner/Logic/HelperToolManager.swift), [PearcleanerHelper/main.swift](https://github.com/alienator88/Pearcleaner/blob/main/PearcleanerHelper/main.swift). All VERIFIED-SRC.

**Repo layout.** Targets `Pearcleaner`, `PearcleanerHelper` (privileged XPC daemon), `PearcleanerSentinel` (monitors Trash, about 2 MB RAM), `FinderOpen` (Finder extension), `Shared`. It needs Full Disk Access plus the helper. Supports macOS 13 through 26.

**Search locations** (`Locations.apps`). The search set covers:

- Home: `~` and `~/.config`, `~/Documents`, `~/Desktop`, `~/Applications`.
- `~/Library` and its standard subfolders: Application Scripts, Application Support (+CrashReporter, + **every first-level subfolder of Application Support**), Containers, Group Containers, Caches, HTTPStorages, Internet Plug-Ins, LaunchAgents, Logs (+DiagnosticReports), Preferences (+ByHost), PreferencePanes, Saved Application State, Services, WebKit.
- Specific SDK cache folders: `com.crashlytics`, `com.google.SoftwareUpdate`, `com.google.Keystone`, `org.sparkle-project.Sparkle`, `com.segment.analytics`, `SentryCrash`, `Rollbar`, `Amplitude`, `Realm`, `Parse`.
- `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments`.
- System side: `/Applications`, `/Users/Shared` (+`Library/Application Support`), `/Library` and its Application Support, Caches, Extensions, Internet Plug-Ins, LaunchAgents, LaunchDaemons, Logs, Preferences, PrivilegedHelperTools.
- `/private/var/db/receipts`, `/private/tmp`, `/usr/local/{bin,etc,opt,sbin,share,var}`.
- The per-user **Darwin cache and temp dirs** (`/var/folders/.../C` and `/T`).

The search depth is 1, except **`~/Library` and `/Library` are searched to depth 2**. At depth 2 the matcher adds the **vendor parent folder** (e.g. `/Library/Objective-See/` rather than `/Library/Objective-See/LuLu/`) unless the parent is a standard Library subfolder.

**Plugin locations** (`Locations.plugins`). Audio Plug-Ins (Components/HAL/MAS/VST/VST3/CLAP, user and system, Avid/Digidesign), PreferencePanes, QuickLook, Screen Savers, Internet Plug-Ins, CoreImage, ColorPickers, Fonts, Dictionaries, Automator, Safari Extensions, Motion Templates, Spotlight, Services, Address Book Plug-Ins, Contextual Menu Items, Input Methods, Widgets.

**Name normalization (`pearFormat`).** Keep only Unicode alphanumerics and lowercase the result. Return the original string if the result would be empty, so empty strings never match everything. File extensions are stripped before comparison.

**Matching identifiers**, precomputed once per app:

- Formatted bundle ID and the last two bundle components.
- Formatted app name, the app name with trailing version digits stripped ("Bartender 6" → "bartender"), and the letters-only name.
- The `.app` filename.
- The company component of 3-part bundle IDs (`com.knollsoft.Rectangle` → `knollsoft`).
- **Entitlement strings**, e.g. `com.apple.security.application-groups` values, read via `SecCodeCopySigningInformation` with `kSecCSRequirementInformation` (1<<2).
- **Team identifier** (`kSecCodeInfoTeamIdentifier`).
- The **base bundle ID**: drop a trailing `helper|agent|daemon|service|xpc|launcher|updater|installer|uninstaller|login|extension|plugin`.

A bundle ID with one component is only used if it has at least 5 characters.

**Sensitivity levels** (user setting, with a per-app override):

- **Strict:** exact equality of the normalized name with the app name, path name or letters-only name; or `contains(fullBundleID)`.
- **Enhanced:** `contains` matching, plus last-two-bundle-components and the stripped name.
- **Deep:** Enhanced plus company name and team ID.

**Spotlight supplement.** An `NSMetadataQuery` scoped to `NSMetadataQueryUserHomeScope`:

- Strict: `kMDItemDisplayName ==[cd]` name or bundle ID, then post-filtered.
- Enhanced: `kMDItemDisplayName CONTAINS[cd]` or `kMDItemPath CONTAINS[cd]`.
- Deep: also `kMDItemComment`, `kMDItemCreator`, `kMDItemCopyright`, `kMDItemEncodingApplications`, an optional `kMDItemTextContent`, and AND-of-word-parts LIKE matching.

The query runs on a private run loop with a **5 s timeout**, and results are capped at **500**.

**Containers.** Pearcleaner finds them two ways:

- `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` for the app's group container.
- For `~/Library/Containers/<UUID>` directories, it reads `.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier` and compares it with the bundle ID.

The UUID regex is `^[0-9A-F]{8}-...-[0-9A-F]{12}$`, case-insensitive.

**Per-app `Condition`s** are hand-curated include/exclude keywords plus forced paths. For example, Xcode includes `com.apple.dt`, `xcode` and `simulator`, and excludes Xcodes.app / Xcode Cleaner data. Zoom includes `zoom`. Brave includes `brave`.

**Skip rules:**

- Prefixes `mobiledocuments`, `reminders`, `dsstore`, `comapplepasswordmanager`, with an allow-list for certain `comapple*` items.
- Paths `~/.Trash` and `/Library/SystemExtensions`.
- About 100 Library subfolder names are **never deep-searched**: Apple, Biome, Mail, Messages, Safari, Keychains, Mobile Documents, Containers metadata, IntelligencePlatform, and more.

**App inventory metadata** comes from `MDItemCreate` + `MDItemCopyAttribute`, processed in parallel chunks of 15–50 paths. Attributes read: `kMDItemFSCreationDate`, `kMDItemFSContentChangeDate`, **`kMDItemLastUsedDate`**, `kMDItemDateAdded`, `kMDItemDisplayName`, `kMDItemCFBundleIdentifier`, `kMDItemFSName`, `kMDItemLogicalSize`, `kMDItemPhysicalSize`, `kMDItemAppStoreAdamID`.

**App classification:**

- **Sparkle:** Info.plist has `SUFeedURL`/`SUFeedUrl`/`SUPublicEDKey`/`SUPublicDSAKeyFile`/`SUEnableAutomaticChecks`.
- **Setapp:** bundle ID ends with `-setapp`. Excluded from Sparkle updates.
- **App Store:** `Bundle.appStoreReceiptURL` exists, or for wrapped iOS apps `Wrapper/iTunesMetadata.plist` exists.
- **Web app:** `LSTemplateApplication == true` or `CFBundleExecutable == "app_mode_loader"` (Chrome/Edge PWAs).

**Size.** `totalSizeOnDisk` sums `.fileSizeKey` (logical, Finder-like) over an enumerator. That is fine for an app list, but for "space freed" we should use allocated sizes (§4.1).

**Lipo without Xcode.** Pearcleaner parses `fat_header` (big-endian, magic `0xcafebabe`) and 20-byte `fat_arch` records, classifying `cputype` `0x0100000C` = arm64 and `0x01000007` = x86_64, then rewrites the binary to a single slice. That is our "Universal Binaries" feature.

**Privileged helper.** `SMAppService.daemon(plistName: "<id>.plist")`; if `.requiresApproval` it calls `SMAppService.openSystemSettingsLoginItems()`. The launchd plist has `Label`, `BundleProgram=Contents/MacOS/PearcleanerHelper`, `MachServices{<id>:true}` and `AssociatedBundleIdentifiers`. The client uses `NSXPCConnection(machServiceName:options:.privileged)`.

> ⚠️ **Anti-pattern (don't copy).** The helper accepts a client if the code-signing **certificates of `connection.processIdentifier`** match its own. That is PID-based and racy. It then exposes `runCommand(command:)`, which runs **`/bin/bash -c <string>` as root**. We will use `setConnectionCodeSigningRequirement` and typed, validated verbs instead (§4.21).

### 3.2 tw93/Mole: cleanup paths, maintenance commands, safety heuristics (GPL-3, ideas only)

Sources: [README](https://github.com/tw93/Mole), [lib/optimize/catalog.sh](https://github.com/tw93/Mole/blob/main/lib/optimize/catalog.sh), [lib/optimize/tasks.sh](https://github.com/tw93/Mole/blob/main/lib/optimize/tasks.sh), [lib/clean/*.sh](https://github.com/tw93/Mole/tree/main/lib/clean), [lib/core/app_protection.sh](https://github.com/tw93/Mole/blob/main/lib/core/app_protection.sh), [cmd/status/metrics_health.go](https://github.com/tw93/Mole/blob/main/cmd/status/metrics_health.go), [cmd/status/metrics_memory.go](https://github.com/tw93/Mole/blob/main/cmd/status/metrics_memory.go), [cmd/analyze/scanner.go](https://github.com/tw93/Mole/blob/main/cmd/analyze/scanner.go), [cmd/analyze/constants.go](https://github.com/tw93/Mole/blob/main/cmd/analyze/constants.go). All VERIFIED-SRC.

**Commands.** `mo clean | uninstall | optimize | analyze | status | purge | installer | touchid | history`, each with `--dry-run`, `--whitelist` and `--json`.

- Operations are logged to `~/Library/Logs/mole/operations.log`.
- Mole never needs `sudo` up front; it asks only when needed.
- `analyze` moves items to Trash after confirmation.
- A separate proprietary "Mole for Mac" GUI exists at mole.fit.

**Optimize task catalog.** Every task is flagged "safe for automatic execution" and validated at load time:

| Task id | UI name | What it does (command) |
|---|---|---|
| system_maintenance | DNS & Spotlight Check | `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`; `mdutil -s /` status check. DNS flush is **skipped while a VPN is active** |
| cache_refresh | Finder Cache Refresh | Remove `~/Library/Caches/com.apple.iconservices(.store)`; `qlmanage -r cache` then `qlmanage -r` |
| saved_state_cleanup | App State Cleanup | Remove Saved Application State older than **30 days** |
| fix_broken_configs | Broken Config Repair | Fix corrupted preference plists |
| network_optimization | Network Cache Refresh | DNS flush |
| sqlite_vacuum | Database Optimization | `VACUUM` of `~/Library/Mail/V*/MailData/Envelope Index*`, `~/Library/Messages/chat.db`, `~/Library/Safari/History.db`, `TopSites.db`. Skips if the owning app is running, if `file` doesn't say SQLite, if the DB is >100 MB, or if the freelist is tiny. Runs `PRAGMA integrity_check` first |
| prevent_network_dsstore | Prevent Finder .DS_Store | `defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true` (+`DSDontWriteUSBStores`). Reversible with `defaults delete` |
| legacy_overrides_audit | Legacy Overrides | Remove `NSAppSleepDisabled` (global App Nap kill switch) and `com.apple.frameworks.diskimages skip-verify*` left by tweak tools |
| network_stack_optimize | Network Stack Refresh | `sudo route -n flush` + ARP flush |
| disk_permissions_repair | Permission Repair | `sudo diskutil resetUserPermissions / <uid>` |
| spotlight_index_optimize | Spotlight Optimization | `sudo mdutil -E /` only if search is slow ("smart detection") |
| spotlight_orphan_rules_cleanup | Spotlight Orphan Rules | Prune `EnabledPreferenceRules` entries for uninstalled apps |
| periodic_maintenance | Periodic Maintenance | `sudo periodic daily weekly monthly` **if stale; skipped if `periodic` doesn't exist**. Mole's comment says "removed in macOS 26+", but it was actually **removed in macOS 15** (corrected; see §1 item 8) |
| shared_file_list_repair | Shared File Lists | Repair Finder favorites / recent documents (`com.apple.sharedfilelist`) |
| disk_verify | Disk Health | `diskutil verifyVolume /`. **Off by default** (heavy kernel I/O); suggests `sudo diskutil repairVolume /` |
| login_items_audit | Login Items Audit | Find broken login items; last-resort `sudo -n sfltool dumpbtm` |
| quarantine_cleanup | Quarantine Database Cleanup | `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "DELETE FROM LSQuarantineEvent; VACUUM;"` |
| launch_agents_cleanup | Launch Agents Cleanup | **Report** LaunchAgents whose program binary no longer exists. No `launchctl unload` |
| notification_cleanup | Notifications | **(corrected)** The DB path is resolved by `resolve_notification_center_db()`. It prefers `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (comment: "macOS 15+ (Sequoia and later)") and falls back to `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`. It runs only when the DB is **> 50 MB**, then `DELETE FROM record WHERE delivered_date < strftime('%s','now','-30 days'); VACUUM;` and `killall NotificationCenter`. ⚠️ Fact-check finding: `delivered_date` is **Mac absolute time** (seconds since 2001-01-01; [mac_apt notifications.py](https://github.com/ydkhatri/mac_apt/blob/master/plugins/notifications.py) reads it with `ReadMacAbsoluteTime`), but Mole compares it against a Unix-epoch value. INFERRED: the condition is always true, so the task deletes **all** records, not just those older than 30 days. If we adopt this task, subtract 978307200 s (see §4.30.5) |
| coreduet_cleanup | Usage Data | `knowledgeC.db`: delete `ZOBJECT` rows older than 90 days (Core Data epoch 2001-01-01) |

**Health score** (`mo status`). Start at 100 and subtract penalties:

- **CPU** (weight 30): penalty above 50%, full weight above 85%.
- **Memory** (25): above 70%/88%, plus −5 for pressure *warn* and −15 for *critical*.
- **Disk** (20): above 80%/93%. A SMART failure caps the score at 44.
- **Thermal** (15): above 65 °C/85 °C.
- **Disk I/O** (10): above 50/150 MB/s.
- **Battery:** −5 if cycles > 900 or capacity < 60% ("Service Soon"), −2 if > 800 cycles or < 80%.
- **Uptime:** −1 if over 7 days, −3 if over 14 days ("Restart Recommended").

Labels: Excellent ≥ 85, Good ≥ 65, Fair ≥ 45, otherwise "Needs Attention". This is a ready-made, explainable model for our own health indicator (re-implement, don't copy).

**Memory.** Pressure comes from the `memory_pressure` CLI ("normal/warn/critical"). On macOS, "cached" memory is taken from `vm_stat` "File-backed pages" × page size; the header line reports a page size of 16384 on Apple Silicon.

**Disk analyzer (`mo analyze`):**

- Top-level entries are sized with **`du`**, running at most min(4, NumCPU) `du` processes, with a fast in-process walker as fallback.
- **Hard links are counted once** using a `(dev, ino)` set when `Nlink > 1`; actual usage is `st_blocks × 512`.
- **Large files** come from Spotlight: `mdfind -onlyin <root> "kMDItemFSSize >= 104857600"` (100 MB) with a 5 s timeout.
- Worker pool: minimum 2, **maximum 12**. Higher limits caused "failed to create new OS thread" on 184 GB / 261k-file System Library scans.
- Results are cached for 7 days, with admission thresholds (subtree ≥ 100 files and ≥ 10 MB).
- `~/Library/Mobile Documents` (iCloud) is ignored in the overview because `du` blocks there.
- "Fold" dirs (`.git`, `node_modules`, `.venv`, `__pycache__`, `.next`, `target`, ...) are shown as single items.

**Purge:**

- Finds `node_modules`, `target`, `.build`, `build`, `dist` and similar, grouped by project.
- **Anything with activity in the last 7 days is unselected by default.**
- Default roots: `~/Projects`, `~/GitHub`, `~/dev` (custom roots in `~/.config/mole/purge_paths`); the scan goes 6 levels deep.

**Installer finder.** DMG/PKG/MPKG/ISO/XIP/installer ZIPs in Downloads, Desktop, Homebrew caches, iCloud, Mail and Telegram.

**Cleanup paths seen in `lib/clean/{user,caches,system}.sh`:**

- User: `~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, `~/Library/Mail Downloads`, `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`, `~/Library/Updates`, `~/Library/iTunes/{iPhone,iPad,iPod} Software Updates`, `~/Library/Application Support/MobileSync/Backup` (review only), `~/Library/Application Support/CrashReporter`, `~/Library/DiagnosticReports`.
- Developer: `~/Library/Developer/Xcode/{DerivedData,Archives}`, `~/Library/Developer/CoreSimulator/Devices`, `~/.gradle/caches`, `~/.m2/repository`, `~/.nuget/packages`, `~/.ivy2/cache`, `~/Library/pnpm/store`, `~/.conda/pkgs`, `~/anaconda3/pkgs`, `~/.cache/huggingface`, `~/.lmstudio/models` (review), `~/.android/avd`, `~/Library/Android/sdk`, `~/.lima`, `~/.tart/cache`, `~/fvm/versions`, `~/.local/share/mise/installs`, Docker/OrbStack/UTM data.
- Browsers: Chrome/Brave/Arc/Vivaldi/Firefox profile caches.
- Incomplete downloads: `~/Downloads/*.part|*.download|*.crdownload`.
- System side: `/Library/Caches`, `/Library/Logs` (+DiagnosticReports, Adobe, CreativeCloud), `/Library/Updates`, `/private/var/log`, `/private/var/db/diagnostics`, `/private/var/db/DiagnosticPipeline`, `/private/var/db/powerlog`, `/private/var/db/reportmemoryexception/MemoryLimitViolations`.

**Protection heuristics** (`should_protect_path`) to adopt as rules (INFERRED adoption):

- Never touch paths containing `SystemSettings|SystemPreferences|ControlCenter`, `com.apple.Settings*`, `com.apple.Notes*`.
- Keep caches that System Settings and Control Center rendering depend on (`com.apple.systempreferences.cache`, `com.apple.Settings.cache`, `com.apple.controlcenter.cache`). Deleting them causes a **blank-panel bug** on Sonoma/Sequoia.
- Protect local DB state and backups (`.gitconfig.lock/.bak`, shell history backups, Prometheus data).
- Keep a shared "home state" root list, endpoint-security caches and OrbStack runtime paths.
- Keep a `DATA_PROTECTED_BUNDLES` list (password managers and the like).

### 3.3 MacSai: whole-app reference architecture (BSD-3, reusable with notice)

Sources: [README](https://github.com/iliyami/MacSai), [SafetyGuard.swift](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/SafetyGuard.swift), [MaintenanceTask.swift](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/MaintenanceTask.swift), [DuplicateDetection.swift](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/DuplicateDetection.swift), [FileConsolidator.swift](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/FileConsolidator.swift), [SystemStats/*.swift](https://github.com/iliyami/MacSai/tree/main/Sources/MacCleanKit/SystemStats), [SquarifiedTreemap.swift](https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/SquarifiedTreemap.swift). All VERIFIED-SRC/README.

**Targets:**

- `MacClean`: the SwiftUI app, 17 modules.
- `MacCleanKit`: a pure, unit-testable framework.
- `MacCleanHelper`: an XPC LaunchDaemon for root operations.
- `MacCleanMenu`: an independent menu-bar process launched at login.

The build is SwiftPM (`swift build`, `swift test`). The stack is Swift 6 strict concurrency, actors and TaskGroup, GRDB (SQLite, WAL), FSEvents with historical replay, SMAppService + NSXPCConnection, and Mach APIs.

**Modules.** Smart Scan; System Junk (16+ categories incl. language files, broken prefs, broken login items, document versions, iOS backups, Xcode, package-manager/IDE/AI caches, deleted-user leftovers, universal-binary thinning); Mail Attachments (Apple Mail, Outlook, Spark); Trash Bins (incl. external drives); Malware Removal (Quick/Balanced/Deep, curated signatures, "not an antivirus"); Privacy (Safari/Chrome/Firefox history, cookies, cache, with time filters; bookmarks never touched); Saved Wi-Fi; Permissions Overview (read-only TCC by app, deep-links to System Settings); Optimization (login items/launch agents); Maintenance; Uninstaller (+ Reset to Defaults); Extensions; Updater (Sparkle appcasts); Space Lens (squarified treemap); Large & Old Files (>50 MB); Duplicates (+ Consolidate via APFS clones); Shredder.

**Shortcuts:** ⌘R scan, ⌘K clean, ⌘1–⌘9 modules, ⌘, settings.

**`SafetyGuard.validatePath`.** The checks run in order:

1. Reject an empty path or one containing NUL.
2. Resolve symlinks.
3. Canonicalize the firmlinks `/private/{var,tmp,etc}` → `/{var,tmp,etc}`, and *only* those, so `/private/var/db` stays protected.
4. Reject `/System` (SIP).
5. Reject the protected prefixes (`/System`, `/usr`, `/bin`, `/sbin`, ...).
6. Reject user-excluded folders.
7. **Reject if symlink resolution changed the first 3 path components** (TOCTOU / redirect).

A batch is capped at `maxFilesPerOperation`. Orphan deletion is only allowed under Caches, Logs, HTTPStorages, Saved Application State or WebKit; never under preferences, containers or keychains.

**Other safety measures:** a "pre-scan cleanability filter" that drops items we couldn't trash (root-owned children, data-vaulted `~/Library/Caches/com.apple.*`); trash-first deletion with a dry-run; chunked, cancellable cleaning (5k items per chunk); an activity log pruned after 30 days.

**Maintenance tasks** (exact executables):

| Task | Command | Root |
|---|---|---|
| Free Up RAM | `/usr/sbin/purge` | yes |
| Free Up Purgeable Space | `/usr/bin/tmutil thinlocalsnapshots / 999999999999 1` (urgency 1) | n/a |
| Run Maintenance Scripts | `/usr/sbin/periodic daily weekly monthly` (hidden when missing; the binary is absent on 15+, corrected) | yes |
| Verify Startup Disk | `/usr/sbin/diskutil verifyVolume /` | n/a |
| Speed Up Mail | Custom: reindex by deleting the Mail Envelope Index file (Mail rebuilds it) | n/a |
| Rebuild Launch Services | `.../LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user`. **(corrected)** This form fails on macOS 26 ("-kill option has been removed", exit 1); see §4.23 for the replacement | n/a |
| Reindex Spotlight | `/usr/bin/mdutil -E /` | yes |
| Flush DNS Cache | `/usr/bin/dscacheutil -flushcache` | (yes for mDNSResponder HUP) |
| Thin Time Machine Snapshots | `tmutil thinlocalsnapshots / 999999999999 4` (urgency 4) | n/a |
| Reclaim Docker Space | docker CLI from `/usr/local/bin`, `/opt/homebrew/bin` or Docker.app | no |

Removed task: "Repair Disk Permissions". `diskutil repairPermissions` has been gone since 10.11, and `resetUserPermissions` is undocumented and slow.

**Duplicates pipeline:**

1. Group by size, skipping files over 500 MB.
2. Partial SHA-256, keyed `"size-partialHash"`.
3. Full hash.
4. **Deduplicate hard links** by (device, inode).

The app always keeps one "original" per group, so the user can never delete every copy.

**Consolidate.** Re-hash both files (TOCTOU), then `clonefile(master → hidden temp in the copy's directory)`, verify the clone's hash, restore the copy's permissions and mtime, then atomically `rename(temp, copy)`. The reclaimed size is the copy's `totalFileAllocatedSize`. The volume must report `volumeSupportsFileCloningKey`.

**XPC gate.** The helper uses `NSXPCListener.setCodeSigningRequirement` so the kernel rejects callers with the wrong identifier or team.

**Memory "used"** = (active + wired + compressed) × pageSize. **CPU** = summed per-core ticks, with the `natural_t` reinterpreted via `UInt32(bitPattern:)` because a plain conversion traps on negative `Int32`.

### 3.4 PureMac (MIT) and Burrow (MIT app)

Sources: [PureMac README](https://github.com/momenbasel/PureMac), [Burrow README](https://github.com/caezium/burrow). VERIFIED-README.

**PureMac:**

- Uninstaller with a "10-level matching engine" (bundle ID, team ID, entitlements, Spotlight metadata, containers, company name, partial paths).
- Orphan Finder over `~/Library`.
- Smart Scan categories: System Junk, User Cache (dynamically discovered), AI Apps (Ollama, LM Studio), Mail Files, Trash Bins, Large & Old (>100 MB or older than 1 year, **never auto-selected**), Xcode Junk (simulator runtimes via `simctl runtime delete`, never auto-selected), Brew, Node, Docker.
- **Purgeable space is shown but deliberately *not* offered as junk.**
- Duplicates by size + SHA-256, with hard links excluded.
- **Similar Photos** by perceptual hash + color + aspect ratio, capped at 500 images per scan, and **no deletion** (review only).
- Protection checks: Gatekeeper, FileVault, firewall, SIP, XProtect metadata. Unknown results stay unknown.
- Scheduled cleaning with a threshold.
- A CLI with `--dry-run` and `--json`.

**Burrow** is a native app (MIT) bundling a source-available engine whose command surface mirrors Mole. It adds a SQLite metric history, a menu-bar HUD, an Activity log and an MCP server so AI agents can call it.

### 3.5 exelban/stats: system-metric readers (MIT, reusable)

Sources: [Modules/RAM/readers.swift](https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift), [Modules/CPU/readers.swift](https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift), [Modules/Net/readers.swift](https://github.com/exelban/stats/blob/master/Modules/Net/readers.swift), [Modules/Disk/readers.swift](https://github.com/exelban/stats/blob/master/Modules/Disk/readers.swift), [Modules/Battery/readers.swift](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift), [README](https://github.com/exelban/stats). All VERIFIED-SRC.

- **RAM:**
  - `host_info(HOST_BASIC_INFO).max_mem` for the total.
  - `host_statistics64(HOST_VM_INFO64)` for page counts:
    - used = active + inactive + speculative + wired + compressed − purgeable − external
    - app = used − wired − compressed
    - cache = purgeable + external
  - Pressure: `sysctlbyname("kern.memorystatus_vm_pressure_level")`, where 2 = warning, 4 = critical, otherwise normal.
  - Swap: `sysctlbyname("vm.swapusage")` → `xsw_usage`.
  - Top processes come from `/usr/bin/top -l 1 -o mem -stats pid,command,mem`.
  - Grouping by "responsible" app uses the private `responsibility_get_pid_responsible_for_pid`, looked up via `dlsym`.
- **CPU:** `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` deltas per core with `&-` wrapping subtraction, then `vm_deallocate` of the previous buffer. Also `host_statistics(HOST_CPU_LOAD_INFO)`. Top processes come from `ps -Aceo pid,pcpu,comm -r`. Frequency and power use private **IOReport** (`IOReportCreateSubscription` and related).
- **Network:**
  - Primary interface: `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")["PrimaryInterface"]`.
  - Link info: `getifaddrs` + `if_data` for baud and status; `CWWiFiClient` for Wi-Fi rates.
  - **Byte counters: sysctl `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, ifindex]` → `if_msghdr2.ifm_data.ifi_ibytes/obytes` (64-bit).**
  - Per-process traffic: `/usr/bin/nettop`.
- **Disk:**
  - Space: `statfs`. On APFS, "free" = `f_bavail` × `f_bsize` **+ `CSDiskSpaceGetRecoveryEstimate(url)`** (a private CoreServices call giving purgeable space, cached 60 s).
  - Fallbacks: `attributesOfFileSystem` and then `volumeAvailableCapacityForImportantUsageKey`.
  - I/O rates: the IOKit parent's `"Statistics"` dictionary `"Bytes (Read)"`/`"Bytes (Write)"` via `DASession` and `IOBSDNameMatching`.
  - Per-process I/O: `proc_pid_rusage(RUSAGE_INFO_CURRENT)` → `ri_diskio_bytesread/byteswritten` deltas, with PIDs from `ps`.
- **Battery:**
  - `IOPSCopyPowerSourcesInfo`/`IOPSCopyPowerSourcesList`/`IOPSGetPowerSourceDescription`, separating `kIOPSInternalBatteryType` from `kIOPSUPSType` (UPS, relevant for a Mac mini).
  - `IOServiceMatching("AppleSmartBattery")` provides `CycleCount`, `DesignCapacity`, `AppleRawCurrentCapacity`, **`AppleRawMaxCapacity` on Apple Silicon** (instead of `MaxCapacity`) or `NominalChargeCapacity`, and `Temperature`/100 (°C).
  - Health % = round(100 × max / design), capped at 100.
  - Change notifications: `IOPSNotificationCreateRunLoopSource`.
- **macOS 26:** menu items must be enabled in **System Settings → Menu Bar**. The Wi-Fi SSID requires the Location Services permission.

### 3.6 mangerlahn/Latest: how to check other apps for updates (GPL-3, ideas only)

Sources: [MacAppStoreCheckerOperation.swift](https://github.com/mangerlahn/Latest/blob/main/Latest/Model/Update%20Checker%20Extensions/App%20Store/MacAppStoreCheckerOperation.swift), [Sparkle.swift](https://github.com/mangerlahn/Latest/blob/main/Latest/Model/Sparkle/Sparkle.swift), [UpdateRepository.swift](https://github.com/mangerlahn/Latest/blob/main/Latest/Model/Update%20Repository/UpdateRepository.swift). VERIFIED-SRC.

- **Mac App Store apps.** An app qualifies if `Bundle.appStoreReceiptURL` exists, or it is an iOS app whose receipt path contains `WrappedBundle`. The lookup is `GET https://itunes.apple.com/lookup?limit=1&entity=desktopSoftware&country=<region>&bundleId=<id>`, with a fallback to `entity=macSoftware`. Catalyst/iOS apps open the `macappstore://` page.
- **Sparkle apps.** The feed is `Info.plist["SUFeedURL"]` with quotes trimmed. If there is no feed but `Contents/Frameworks/DevMateKit*` exists, use `https://updates.devmate.com/<bundleID>.xml`. Latest drives Sparkle's own `SUAppcastItem` parsing (`displayVersionString`, `versionString`, `minimumSystemVersion`, release notes).
- **Homebrew cask repository.** `https://formulae.brew.sh/api/cask.json`, cached for 1 hour, plus a remote excluded-bundle-ID plist.

### 3.7 Objective-See KnockKnock / BlockBlock / DumpBTM (GPL-3, taxonomy only)

Sources: [KnockKnock Plugins/](https://github.com/objective-see/KnockKnock/tree/master/Plugins), [BTM.m](https://github.com/objective-see/KnockKnock/blob/master/Plugins/BTM.m), [LoginItems.m](https://github.com/objective-see/KnockKnock/blob/master/Plugins/LoginItems.m), [BrowserExtensions.m](https://github.com/objective-see/KnockKnock/blob/master/Plugins/BrowserExtensions.m), [DumpBTM README](https://github.com/objective-see/DumpBTM). VERIFIED-SRC.

- **20 persistence categories (corrected; the earlier "21" counted `PluginBase`)**. Re-counted via GitHub code search of `Plugins/`, which has 21 `.h/.m` pairs including `PluginBase`. The 20 are: AuthorizationPlugins, BrowserExtensions, **BTM** ("Background Managed Tasks"), Cronjobs, DirectoryServicesPlugins, DockTiles, DylibInserts, DylibProxies, EventRules, Extensions, Kexts, **LaunchItems**, LogInOutHooks, **LoginItems**, PeriodicScripts, QuicklookPlugins, ShellConfigs, SpotlightImporters, StartupScripts, SystemExtensions. These map directly onto CleanMyMac's "Login Items / Background Items / Launch Agents" and the malware-scan areas.
  - *(added)* On macOS 15, Apple says "Directory Services plug-in, legacy QuickLook plug-ins, and com.apple.loginitems.plist file are all no longer supported" (VERIFIED: [WWDC24 "What's new in privacy"](https://developer.apple.com/videos/play/wwdc2024/10123/)). On 15+, those three categories can only hold inert leftovers. Show them as "unsupported leftovers", not as active persistence. PeriodicScripts is also inert on 15+, because `periodic` is gone (§1).
- **BTM (macOS 13+).** All login items, agents and daemons are consolidated in **`/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`**, an NSKeyedArchiver binary plist. Apple's dumper is `sfltool dumpbtm`.
  - **(corrected)** It is not root-only. The files are **mode 644** and gated only by TCC (**Full Disk Access**). Two independent OSS readers say so and read them directly without admin rights: [sabharishhh/brim BTMStore.swift](https://github.com/sabharishhh/brim/blob/main/BrimCore/Sources/BrimScan/BTM/BTMStore.swift) and [adamengst/setshot-app BackgroundItems.swift](https://github.com/adamengst/setshot-app/blob/main/SetShot/Services/BackgroundItems.swift) (VERIFIED-SRC, code comments). By contrast, **`sfltool dumpbtm` shows "Allow administrator access for sfltool?" on every run** (same sources). So for our app: read the file directly with FDA, and don't shell out to sfltool.
  - **Format versions (added):**
    - `-v4` on macOS 13.0 and `-v7` on 13.1 ([DumpBTM README](https://github.com/objective-see/DumpBTM)).
    - `-v8` seen on a Sonoma-era script (tiiiecherle/osx_install_config).
    - `-v16` is the last single-file format. SetShot says "A Mac upgraded to 27 keeps its old v16 file", which suggests v16 is macOS 26 (INFERRED).
    - **macOS 27 uses `-v18`, with one file per user: `BackgroundItems-v18-<user UUID>.btm`.** Its root key is `userStore` → `records`. Older files use `store` → `itemsByUserIdentifier` (VERIFIED-SRC, SetShot comments and tests).
    - The user UUID is the directory UUID from `mbr_uid_to_uuid(getuid())`. Machine-wide daemons live under the pseudo-user `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` (VERIFIED-SRC, both readers).
    - **Pick the highest version.** Stale lower-version files stay on disk after an OS upgrade and list removed software.
  - Each record holds UUID, Name, Developer Name, **Team Identifier**, Type (`app 0x2`, `legacy daemon 0x10010`, `curated legacy daemon 0x90010`, `developer 0x20` for grouping records, ...), **Disposition**, Identifier (a code requirement), URL, Executable Path and Associated Bundle IDs.
  - **Disposition bits (refined):** enabled 0x1, allowed 0x2, notified 0x8 (SetShot, matching sfltool's labels), so `[enabled allowed visible notified]` = 11. The **Login Items & Extensions switch is the "allowed" bit (0x2)**. KnockKnock filters on bit 0x1.
  - KnockKnock skips records that are disabled or that carry "embedded item IDs" (parents).
  - Endpoint Security's `ES_EVENT_TYPE_NOTIFY_BTM_LAUNCH_ITEM_ADD` was reported as broken in 2022 (DumpBTM README, linking Apple forum thread 720468). It also needs an ES entitlement, so it is not an option for a personal app. Watch the BTM directory with FSEvents instead (INFERRED).
- **Legacy login items:** `~/Library/Preferences/com.apple.loginitems.plist` (old, **unsupported since macOS 15**, see above) and `~/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm` (newer per-user). Apps' `Contents/Library/LoginItems/` are cross-referenced.
- **Browser extension stores:**
  - `~/Library/Safari/Extensions/`
  - `~/Library/Application Support/Google/Chrome/<profile>/Preferences` and `Secure Preferences`
  - `~/Library/Application Support/Firefox/Profiles/`
  - `~/Library/Application Support/com.operasoftware.Opera/`

### 3.8 czkawka (MIT core) and dupeGuru (GPL-3): duplicates and similar images

Sources: [czkawka README](https://github.com/qarmin/czkawka), [duplicate/mod.rs](https://github.com/qarmin/czkawka/blob/master/czkawka_core/src/tools/duplicate/mod.rs), [similar_images/mod.rs](https://github.com/qarmin/czkawka/blob/master/czkawka_core/src/tools/similar_images/mod.rs), [similar_images/core.rs](https://github.com/qarmin/czkawka/blob/master/czkawka_core/src/tools/similar_images/core.rs), [dupeGuru core/fs.py](https://github.com/arsenetar/dupeguru/blob/master/core/fs.py), [core/pe/matchblock.py](https://github.com/arsenetar/dupeguru/blob/master/core/pe/matchblock.py). VERIFIED-SRC.

**czkawka duplicates.** Check methods are name, size, size+name and hash. Hash types: **Blake3, CRC32, XXH3**. The steps:

1. Group by size.
2. **Prehash** = hash of the first **4 KiB + last 4 KiB** (the whole file if size ≤ 8 KiB). Re-verified in the fact-check: `PREHASHING_BUFFER_SIZE: u64 = 4 * 1024`, tail read via `SeekFrom::Start(tail_offset)`.
3. Full hash, read with a 2 MiB thread buffer (`THREAD_BUFFER_SIZE = 2 * 1024 * 1024`, re-verified).
4. Filter hard links by inode, keeping one per inode.
5. Cache hashes by path, size and mtime.

**czkawka similar images.** `image_hasher` with `HashAlg` ∈ {Mean, Gradient, Blockhash, VertGradient, DoubleGradient}, hash size ∈ {8, 16, 32, 64} and resize filter ∈ {Lanczos3, Nearest, Triangle, Gaussian, CatmullRom}. Groups are built with a **BK-tree under Hamming distance**. Hamming thresholds per preset:

| Preset | 8 | 16 | 32 | 64 |
|---|---|---|---|---|
| Very High | 1 | 2 | 4 | 6 |
| High | 2 | 5 | 10 | 20 |
| Medium | 5 | 15 | 20 | 40 |
| Small | 7 | 30 | 40 | 40 |
| Very Small | 14 | 40 | 40 | 40 |
| Minimal | 40 | 40 | 40 | 40 |

A threshold of 0 ("Original") means identical hashes only.

**dupeGuru.** Full digest with xxh128 (falling back to MD5), read in 1 MiB chunks. **Partial digest = 16 KiB at offset 16 KiB** (`PARTIAL_OFFSET_SIZE = (0x4000, 0x4000)`, re-verified). "Samples" digest (3 × 1 MiB samples) only for files **larger than** 3 MiB (`if size <= MIN_FILE_SIZE` skips it; corrected from "≥"). Digests are cached in SQLite by size and mtime. Picture mode: average colors of a **15 × 15 grid of blocks** per image (8 orientations optional), compared in multiprocessing chunks.

### 3.9 GrandPerspective, OnyX, Lemon, Sparkle, sindresorhus, SecureXPC, PermissionsKit

**GrandPerspective** (GPL, Objective-C; VERIFIED via WebFetch of [grandperspectiv.sourceforge.net](https://grandperspectiv.sourceforge.net/)):

- Treemap with files of the same folder kept together.
- Filters on name, path, size, type, **hard-link status** and package status, used to mask, hide or exclude at scan time.
- Background scanning and drawing; saving and loading of scans; handles hard links (Time Machine backups) and cloud files.
- v3.8.1 (13 Sep 2026) needs macOS 14+.

**OnyX** (Titanium Software): closed-source freeware. The vendor site was unreachable through the proxy, and still was during the fact-check (DNS failure). INFERRED from general knowledge: its Maintenance tab offers verify startup volume, rebuild LaunchServices, rebuild Spotlight index, rebuild Mail index, run periodic scripts, purge caches (system/user/font/dyld), clean logs and similar. Each of these maps to commands already listed in §3.2/§3.3. Treat OnyX only as a checklist.

*Fact-check additions:*

- **Versions (VERIFIED, [Homebrew cask](https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/o/onyx.rb)).** OnyX ships one build per macOS: Big Sur 4.0.2, Monterey 4.2.7, Ventura 4.4.7, Sonoma 4.6.2, Sequoia 4.8.5, Tahoe 5.0.5, macOS 27 5.1.0. Download URLs follow `titanium-software.fr/download/<major>/OnyX.dmg`. Cask description: "Verify system files structure, run miscellaneous maintenance and more".
- **OnyX 5.x layout.** Secondary source: a third-party OnyX guide written for Tahoe, [dogukannparlak/…/OnyX.md](https://github.com/dogukannparlak/Onerdigim-uygulama-ve-eklentiler-macos/blob/main/OnyX.md). This is not vendor-verified, so treat it as INFERRED-community.
  - Top tabs: **OnyX · Maintenance · Utilities · Files · Security · Find · Parameters · Info**. Parameters sub-tabs: General, Finder, Menus, Dock, Login, Applications, Misc.
  - **Maintenance** has three groups, and you pick tasks and then click **Run Tasks** (admin password):
    - **Verifying:** "S.M.A.R.T. status", "Structure of the file system".
    - **Rebuilding:** "Launch Services database", "Spotlight index", "Mailboxes in Mail", "Volume positions on the desktop".
    - **Cleaning:** "System", "Applications", "Internet", "Other". Each has an ⓘ explaining what gets deleted.
  - **No "periodic scripts" task appears in the 5.x list**, which is consistent with `periodic` being removed in 15+.
  - The **Security** tab shows SIP, FileVault, Firewall, Gatekeeper, "Check for security responses", "Automatically install Background Security Improvements", plus "Delete Junk Items" and a "Reload" for XProtect versions.
- **For us (INFERRED):** model our Maintenance list as OnyX-style groups (Verify / Rebuild / Clean), each with an ⓘ explanation, and use an OnyX-style reversible "Parameters" page for hidden `defaults` (12-competitors.md recommends the same).

**Tencent Lemon Cleaner** (GPL-3; LemonDaemon GPL-2; VERIFIED-README [lemon-cleaner](https://github.com/Tencent/lemon-cleaner)). Its module split is a good blueprint for target boundaries: `Lemon` (main), `LemonMonitor` (status bar), `LemonBigOldFile`, `LemonDuplicateFile`, `LemonPhotoClean`, `LemonUninstaller`, `LemonPrivacyClean`, `LemonLoginItemManager`, `LemonSpaceAnalyse`, `LemonFileMove`, `LemonHardware`, `LemonNetSpeed`, `LemonCleaner`. Big files start at > 50 MB.

**Sparkle 2** (MIT-style; VERIFIED-README [Sparkle](https://github.com/sparkle-project/Sparkle)). EdDSA-signed RSS appcasts, delta updates, sandbox support, channels, phased rollouts, critical updates. The runtime needs macOS 12+ on `2.x`. Re-verified: README.markdown on branch `2.x` says "Runtime: macOS 12.0 or later on `2.x`, macOS 10.13 or later on `2.9.6`". Use `generate_appcast` for signatures and deltas. The feed URL lives in Info.plist `SUFeedURL`, and the public key in `SUPublicEDKey`. INFERRED: integrate with `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` and a "Check for Updates…" menu item bound to `updater.checkForUpdates()`. For a purely personal build, Sparkle is optional.

**LaunchAtLogin-Modern** (MIT; VERIFIED-SRC [LaunchAtLogin.swift](https://github.com/sindresorhus/LaunchAtLogin-Modern/blob/main/Sources/LaunchAtLogin/LaunchAtLogin.swift)):

- `isEnabled` = `SMAppService.mainApp.status == .enabled`.
- Enabling calls `register()`, first calling `unregister()` if the item is already enabled, to repair stale registrations.
- `wasLaunchedAtLogin` checks the current Apple Event: `kAEOpenApplication` with `keyAEPropData == keyAELaunchedAsLogInItem`.
- The Mac App Store requires that the user turns the setting on.

**Other packages.** Defaults, KeyboardShortcuts and Settings are all MIT (VERIFIED LICENSE).

**SecureXPC** (MIT; VERIFIED-README [SecureXPC](https://github.com/trilemma-dev/SecureXPC)). Codable routes (`XPCRoute.named(...).withMessageType(...).withReplyType(...)`), servers for SMAppService daemons and agents, async/await. Security checks run against the actual calling process, not its PID.

**PermissionsKit** (MIT, MacPaw; VERIFIED-SRC). See §4.22.

### 3.10 Disk-scanner projects using `getattrlistbulk` (MIT examples)

GitHub code search turned up more than 70 Swift files using `getattrlistbulk` with `ATTR_CMN_RETURNED_ATTRS`. The best one read is [Radix BulkDirectoryEnumerator.swift](https://github.com/colinvkim/Radix/blob/main/Radix/Services/BulkDirectoryEnumerator.swift) (MIT, VERIFIED-SRC). It uses:

- A 64 KiB buffer, `open(path, O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW)` and options `FSOPT_PACK_INVAL_ATTRS | FSOPT_ATTR_CMN_EXTENDED`.
- Common attributes RETURNED_ATTRS, ERROR, NAME, DEVID, OBJTYPE, MODTIME, FNDRINFO (package bit), FLAGS, USERACCESS and FILEID; file attributes LINKCOUNT, TOTALSIZE, ALLOCSIZE and DATAALLOCSIZE; extended attributes REALDEVID, **CLONEID**, **CLONE_REFCNT** and EXT_FLAGS (for APFS clone-aware accounting).
- `EINVAL/ENOTSUP/ENOSYS` as the signal to fall back to `FileManager`.
- **dataless** (iCloud placeholder) detection from `ATTR_CMN_FLAGS`.

### 3.11 MacPaw's own public code

- **PermissionsKit** (MIT). The FDA probe opens with `O_RDONLY`, in order:
  1. `~/Library/Safari/CloudTabs.db`
  2. `~/Library/Safari/Bookmarks.plist`
  3. `~/Library/Application Support/com.apple.TCC/TCC.db`
  4. `/Library/Preferences/com.apple.TimeMachine.plist`

  Any successful open means *authorized*; any `EPERM`/`EACCES` means *denied*; otherwise *not determined*. The "request" just opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, and no completion callback is possible, so you have to poll. Under the sandbox, the real home directory comes from `getpwuid(getuid())`. VERIFIED-SRC (re-verified in the fact-check: lines 69–95 and 125–140 of the .m file).
  - INFERRED caveat: some probes may simply not exist on a given Mac (for example `CloudTabs.db` without iCloud Safari tabs), which gives ENOENT. The user `TCC.db` and listing `~/.Trash` (used by other OSS apps, §4.3) are the dependable probes.
- **cleanmymac-cli** (EULA, not OSS; v1.0.0 beta, cask name "CleanMyMac 5 CLI", needs macOS 11+, binary `CleanMyMac_5_CLI.app` symlinked as `cleanmymac` and `cmm`):
  - `clean` = System Junk + Dev Tools + AI Junk + Trash. **(refined in fact-check)** The README's command table says `clean` runs "system junk, dev-tools junk, and trash", but its prose and sample TUI include **AI Junk**. In the sample, **System Junk and Dev Tools are pre-checked and AI Junk is shown unchecked**, which is a useful default-selection precedent for us.
  - `clean dev` covers Homebrew, npm, Yarn, pnpm, pip, Cargo, Go, CocoaPods, Docker, VS Code, JetBrains, Maven, Gradle, Poetry, uv, Bun, Deno, mise.
  - `clean junk` covers user logs and Xcode DerivedData, Device Support, Module Cache and Documentation Cache.
  - `clean trash` covers system and mounted-volume trash bins.
  - `purge` default roots are `~/Projects`, `~/Code`, `~/dev`, `~/GitHub`, `~/Workspace`; **artifacts older than 7 days are preselected**. Detected artifact names (re-verified): `node_modules`, `.next`, `.turbo`, `target`, `.build`, `.venv`, `venv`, `pycache`, `Pods`, `DerivedData`, `vendor`, `cmake-build-*`.
  - `optimize ram` releases inactive memory **without sudo**; `optimize purgeable` asks macOS to release purgeable space. The mechanism is not documented; see §4.8 for the best available evidence.
  - `ignore add|list|remove <path>`; `--force` skips confirmation; analytics can be toggled in `config`.

  VERIFIED-README.
- Other MacPaw repos: CocoaSprings (spring animations), XADMaster (unarchiving), Setapp-framework. See 10-internals.md for helper and bundle internals.

### 3.12 Additional open-source projects found in the fact-check

These come from GitHub repository and code search; WebSearch was still unavailable. Each entry gives the license and the specific idea worth taking.

- **[jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app)** (MIT, Swift/SwiftUI, macOS 13+, ~1.1k★; VERIFIED-README + LICENSE).
  - Everything goes to the Trash, except "iOS simulators, Time Machine snapshots and the Apple Intelligence models, which the Trash can't hold". Simulators are removed via `simctl`.
  - Model sizes in Ollama count only bytes that would actually be reclaimed (content-addressed blobs shared between models are counted once).
  - Duplicates offer "Keep one of each" with a suggested keeper.
  - Has a Cleaning History that records what was moved and what was skipped, and a first-run onboarding: welcome → permissions (FDA, optional login item) → first scan → review → safe clean.
  - Without FDA, only App Caches and Dev Tools scan. A good pattern for a degraded mode.
  - 05-performance.md used its CacheDelete spike for purgeable-space work.
- **[dsswift/cmm](https://github.com/dsswift/cmm)** ("A simple, free CleanMyMac"; **no LICENSE file found**, so all rights reserved; study only; VERIFIED-README).
  - **Design rules enforced by tests:**
    - "Trash only": zero `removeItem`/`unlink`/`rmdir`, and `DeletionInvariantTests.swift` greps the source tree to prove it.
    - User-level only, with no root helper.
    - Local only.
    - "Honest numbers": APFS clones make totals an upper bound, so the UI says "up to X GB".
  - Junk comes from a curated catalog of about 50 locations in **three safety tiers**, and **only regenerable items are pre-ticked**. Large & Old files are never pre-ticked.
  - Disk Usage is an outline with inline bars rather than a treemap, because a treemap of a whole home folder turns sub-few-hundred-MB items into slivers.
  - A single traversal (about 850k files in about a minute) feeds both Large Files and Disk Usage.
  - The walker opts its thread out of iCloud materialization with **`setiopolicy_np`** (§4.30.1).
  - System-wide agents and daemons are listed but never modified; the app gives the user the `sudo launchctl bootout` command instead.
  - Signing advice is covered in §4.20.
- **[sindresorhus/macos-trash](https://github.com/sindresorhus/macos-trash)** and **[sindresorhus/DSStore](https://github.com/sindresorhus/DSStore)** (both MIT; VERIFIED-SRC). These are the Put Back fix (§4.3). DSStore is a zero-dependency, `Sendable` Swift reader/writer for `.DS_Store` files.
- **Objective-See [AuRevoir](https://github.com/objective-see/AuRevoir)** (Objective-See, GPL family; check before reuse). It reads the Notification Center DB and documents the path move ("db moved to group container (requires FDA)").
- **Other BTM readers to study for the macOS 27 v18 format:**
  - [sabharishhh/brim](https://github.com/sabharishhh/brim): decodes with `NSKeyedUnarchiver` and stand-in classes.
  - [adamengst/setshot-app](https://github.com/adamengst/setshot-app): walks the archive object table without unarchiving, so unknown classes print nothing instead of crashing.
  - [hewigovens/BTMParser](https://github.com/hewigovens/BTMParser): Swift CLI.
  - [log2timeline/plaso](https://github.com/log2timeline/plaso): parser for `BackgroundItems-v[3-9].btm`.
  - Licenses were not checked during the fact-check, so treat them as ideas only until checked.
- **[AlexTkDev/MacOSCleaner](https://github.com/AlexTkDev/MacOSCleaner)**: source-available, "personal use only" license (VERIFIED LICENSE header). Ideas only.
- **[vashpan/xcode-dev-cleaner](https://github.com/vashpan/xcode-dev-cleaner)** (DevCleaner for Xcode; GPL-3, VERIFIED LICENSE). Xcode-specific categories.
- **[AdventDevInc/kudu](https://github.com/AdventDevInc/kudu)** (TypeScript, cross-platform cleaner, ~3.8k★). Not a native reference; listed for completeness.

---

## 4. Swift / macOS API cookbook

All snippets target Swift 6 / macOS 14+ and are **original code written for this report**. They compile in principle, but please build and test each one. Snippets that need `import Darwin` (Foundation re-exports it on macOS) are marked. Every API name was checked against Apple's documentation where Apple documents it (VERIFIED-DOC links given). C-level BSD and Mach calls are VERIFIED against working OSS usage.

### 4.1 Fast recursive directory size (FileManager path)

API facts (VERIFIED-DOC):

- [`URLResourceKey.totalFileAllocatedSizeKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey) (10.7): the total allocated size, including resource fork and metadata.
- [`fileAllocatedSizeKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/fileallocatedsizekey) (10.6): the data fork's allocated size.
- [`totalFileSizeKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/totalfilesizekey) (10.7): logical size.
- [`linkCountKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/linkcountkey) (10.6).
- [`fileResourceIdentifierKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey) (10.7): equal for the same inode on the same filesystem; **not persistent across restarts**.
- [`fileIdentifierKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/fileidentifierkey) (inode, **macOS 13.3+**) and [`volumeIdentifierKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeidentifierkey).
- [`mayShareFileContentKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/maysharefilecontentkey) and [`fileContentIdentifierKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/filecontentidentifierkey) (11.0, APFS clones).
- [`isPurgeableKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/ispurgeablekey) and [`isSparseKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/issparsekey) (11.0).
- [`skipsPackageDescendants`](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerationoptions/skipspackagedescendants).
- [`producesRelativePathURLs`](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerationoptions/producesrelativepathurls) and [`includesDirectoriesPostOrder`](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerationoptions/includesdirectoriespostorder) (10.15).

```swift
import Foundation   // re-exports Darwin (lstat, st_dev, st_ino)

/// What we measured for a subtree.
struct SizeTally: Sendable {
    var allocatedBytes: Int64 = 0   // "space you will get back" (use this for cleanup)
    var logicalBytes: Int64 = 0     // Finder-style "size"
    var fileCount = 0
    var skippedDataless = 0         // iCloud placeholders we did not touch
    var unreadable = 0
}

/// (device, inode) key for hard-link de-duplication.
struct InodeKey: Hashable, Sendable { let dev: Int32; let ino: UInt64 }

/// Thread-safe "seen" set shared by concurrent walkers so a hard link
/// that appears in two subtrees is still counted once.
final class InodeSet: @unchecked Sendable {
    private var set = Set<InodeKey>()
    private let lock = NSLock()
    func insert(_ k: InodeKey) -> Bool { lock.lock(); defer { lock.unlock() }; return set.insert(k).inserted }
}

private let sizeKeys: [URLResourceKey] = [
    .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    .totalFileSizeKey, .fileSizeKey, .linkCountKey,
]

/// Synchronous, cancellable walk. Descends INTO packages (an .app's size must
/// include its contents). Never follows symlinks (FileManager.enumerator
/// doesn't follow them by default).
func measure(_ root: URL, seen: InodeSet, isCancelled: () -> Bool = { Task.isCancelled }) -> SizeTally {
    var t = SizeTally()
    let keySet = Set(sizeKeys)
    guard let walker = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: sizeKeys,
        options: [],                                  // NOT .skipsHiddenFiles: hidden data is real data
        errorHandler: { _, _ in true }                // EPERM etc.: keep going
    ) else { return t }

    for case let url as URL in walker {
        if isCancelled() { break }
        guard let v = try? url.resourceValues(forKeys: keySet) else { t.unreadable += 1; continue }
        if v.isDirectory == true || v.isSymbolicLink == true { continue }

        // Hard links: only pay for an lstat when the link count says we must.
        if let links = v.linkCount, links > 1 {
            var st = stat()
            if lstat(url.path, &st) == 0,
               !seen.insert(InodeKey(dev: st.st_dev, ino: UInt64(st.st_ino))) { continue }
        }
        t.fileCount += 1
        t.allocatedBytes += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        t.logicalBytes   += Int64(v.totalFileSize ?? v.fileSize ?? 0)
    }
    return t
}
```

**Parallelize at the top level with bounded concurrency.** The walk itself is blocking I/O, so keep the fan-out bounded. Mole had to cap workers at 12 to avoid thread exhaustion (VERIFIED-SRC, constants.go).

```swift
/// Sizes each immediate child of `dir` in parallel; returns largest first.
func childSizes(of dir: URL, maxParallel: Int = min(ProcessInfo.processInfo.activeProcessorCount, 8))
async -> [(url: URL, tally: SizeTally)] {
    let children = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
    let seen = InodeSet()
    return await withTaskGroup(of: (URL, SizeTally).self) { group in
        var it = children.makeIterator()
        func addNext() { if let c = it.next() { group.addTask(priority: .utility) { (c, measure(c, seen: seen)) } } }
        for _ in 0..<maxParallel { addNext() }
        var out: [(URL, SizeTally)] = []
        while let r = await group.next() { out.append(r); addNext() }
        return out.sorted { $0.1.allocatedBytes > $1.1.allocatedBytes }
    }
}
```

**Edge cases and rules for scanning (INFERRED unless cited):**

- **iCloud / dataless files.** Reading their content triggers a download. When building lists, check `isUbiquitousItemKey` / `ubiquitousItemDownloadingStatusKey` (VERIFIED-DOC [isUbiquitousItemKey](https://developer.apple.com/documentation/foundation/urlresourcekey/isubiquitousitemkey)) or the `SF_DATALESS` flag (Radix detects dataless files via `ATTR_CMN_FLAGS`, VERIFIED-SRC). Never hash or open such files. Mole skips `~/Library/Mobile Documents` in the overview (VERIFIED-SRC).
- **Firmlinks.** `/System/Volumes/Data` mirrors `/Users`, `/Applications` and other top-level folders. When scanning `/`, skip `/System/Volumes/Data` (or map paths through it) to avoid double counting. Also skip `/Volumes` (external disks), `/dev` and `/private/var/vm` (swap and sleepimage are not reclaimable).
- **Packages.** For *sizes*, descend into them. For *listing* clutter items (Large & Old files), use `.skipsPackageDescendants` and treat each package as a single item.
- **Allocated vs logical.** Use allocated size for "space freed"; show logical size only in file info. APFS clones share blocks, so deleting one clone frees ~0 bytes. If `mayShareFileContentKey == true`, mark the size as "may be shared". Radix reads `ATTR_CMNEXT_CLONEID`/`CLONE_REFCNT` to group clones.
- **Snapshots.** Bytes held by local Time Machine/APFS snapshots aren't freed until the snapshots are thinned. The UI should say "space will be available once macOS releases it".

### 4.2 Faster: `getattrlistbulk(2)`

Use this when scanning whole disks (the Space Lens equivalent). It returns many entries per syscall and avoids building a `URL` per item. Layout rules, VERIFIED-SRC from Radix's comments and parser:

- `ATTR_CMN_RETURNED_ATTRS` always comes first; for bulk calls `ATTR_CMN_ERROR` follows it.
- The remaining attributes follow in bit order within each group (common, then dir, then file).
- `FSOPT_PACK_INVAL_ATTRS` keeps the fixed part stable.
- Each record starts with a `u_int32_t` length.
- Values are 4-byte aligned, so read 64-bit fields with `loadUnaligned`.

**(upgraded in fact-check)** The layout rules are now VERIFIED-DOC against Apple's own man pages in the xnu source ([getattrlist.2](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlist.2), [getattrlistbulk.2](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/getattrlistbulk.2)):

- `ATTR_CMN_NAME` and `ATTR_CMN_RETURNED_ATTRS` are *required*; leaving either out returns EINVAL.
- "The `ATTR_CMN_ERROR` attribute will be after `ATTR_CMN_RETURNED_ATTRS`".
- Attributes appear "in the order that they are described", which matches the bit order.
- "Each attribute is aligned to a 4-byte boundary (including 64-bit data types)".
- `attr_dataoffset` is "the offset in bytes from the attrreference structure to the attribute data".
- `ATTR_FILE_LINKCOUNT` is a `u_int32_t`; `ATTR_FILE_ALLOCSIZE` is an `off_t` holding the physical size of all forks.
- `FSOPT_PACK_INVAL_ATTRS` returns default values for unsupported attributes; check `returned`.

The **code** below has still not been run. Test it on device.

**exFAT / SMB / non-APFS (added, VERIFIED-SRC [xnu vfs_attrlist.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_attrlist.c)).** If a filesystem doesn't natively support bulk attributes, the kernel itself falls back to an **emulated readdir + getattrlist** (`readdirattr`). So the call still works on such volumes, just more slowly, and user-space EINVAL/ENOTSUP fallbacks should be rare. The kernel also takes the slow default path when the caller **does not request `ATTR_CMN_OBJTYPE`**, or requests `ATTR_CMN_UUID`/`GRPUUID`/`EXTENDED_SECURITY`. Always request OBJTYPE and avoid the ACL/UUID attributes.

```swift
import Foundation

struct BulkEntry { let name: String; let isDir: Bool; let isFile: Bool; let isSymlink: Bool
                   let fileID: UInt64; let linkCount: UInt32; let allocSize: Int64; let flags: UInt32 }

/// Lists the immediate children of `dirPath`. Throws on unsupported filesystems
/// (fall back to FileManager in that case).
func bulkList(_ dirPath: String) throws -> [BulkEntry] {
    let fd = open(dirPath, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
    guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    defer { close(fd) }

    var req = attrlist()
    req.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    req.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
                   | attrgroup_t(ATTR_CMN_ERROR) | attrgroup_t(ATTR_CMN_OBJTYPE)
                   | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
    req.fileattr   = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

    let bufSize = 64 * 1024
    let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 8)
    defer { buf.deallocate() }
    var out: [BulkEntry] = []

    while true {
        let n = getattrlistbulk(fd, &req, buf, bufSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
        if n < 0 { throw POSIXError(.init(rawValue: errno) ?? .EIO) }   // EINVAL/ENOTSUP => fallback
        if n == 0 { break }
        var entry = UnsafeRawPointer(buf)
        for _ in 0..<n {
            let length = Int(entry.loadUnaligned(as: UInt32.self))
            var p = entry + 4
            let returned = p.loadUnaligned(as: attribute_set_t.self); p += MemoryLayout<attribute_set_t>.size
            let err = p.loadUnaligned(as: UInt32.self); p += 4
            // attrreference_t: offset is relative to the start of this field
            let nameRefPos = p
            let nameOff = Int(p.loadUnaligned(as: Int32.self)); p += 8
            let name = String(cString: (nameRefPos + nameOff).assumingMemoryBound(to: CChar.self))
            let objType = p.loadUnaligned(as: UInt32.self); p += 4          // fsobj_type_t
            let flags = p.loadUnaligned(as: UInt32.self); p += 4
            let fileID = p.loadUnaligned(as: UInt64.self); p += 8
            var links: UInt32 = 1, alloc: Int64 = 0
            if objType == VREG.rawValue && returned.fileattr != 0 {
                links = p.loadUnaligned(as: UInt32.self); p += 4
                alloc = p.loadUnaligned(as: Int64.self); p += 8
            }
            if err == 0 {
                out.append(BulkEntry(name: name, isDir: objType == VDIR.rawValue, isFile: objType == VREG.rawValue,
                                     isSymlink: objType == VLNK.rawValue, fileID: fileID,
                                     linkCount: links, allocSize: alloc, flags: flags))
            }
            entry += length                          // always advance by the record length
        }
    }
    return out
}
```

Recurse using a work queue of directories. Skip `isSymlink`. Treat `flags & UInt32(SF_DATALESS) != 0` as dataless; `SF_DATALESS` is in `<sys/stat.h>`, so confirm it imports, or use `0x40000000`. Deduplicate files with `linkCount > 1` by (`st_dev` of the directory, `fileID`). Mole keeps `du -sk` as a robust fallback (VERIFIED-SRC).

### 4.3 Moving to Trash, deleting, emptying Trash

VERIFIED-DOC:

- [`FileManager.trashItem(at:resultingItemURL:)`](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)) (10.8), a synchronous throwing call.
- [`NSWorkspace.recycle(_:completionHandler:)`](https://developer.apple.com/documentation/appkit/nsworkspace/recycle(_:completionhandler:)) (10.6), "in the same manner as the Finder". It returns a `[URL: URL]` map from original to trashed location.

```swift
import AppKit

enum RemovalMode: Sendable { case trash, permanent }

struct RemovalOutcome: Sendable { var trashed: [URL: URL] = [:]; var removed: [URL] = []; var failed: [URL: String] = [:] }

/// Always run SafetyGuard (see 4.4) BEFORE calling this.
func remove(_ urls: [URL], mode: RemovalMode) -> RemovalOutcome {
    var out = RemovalOutcome()
    let fm = FileManager.default
    for url in urls {
        do {
            switch mode {
            case .trash:
                var resulting: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &resulting)   // keeps "where did it go" for Undo
                if let r = resulting as URL? { out.trashed[url] = r }
            case .permanent:
                try fm.removeItem(at: url)
                out.removed.append(url)
            }
        } catch {
            out.failed[url] = (error as NSError).localizedDescription   // root-owned => send to helper
        }
    }
    return out
}

/// Async wrapper over NSWorkspace.recycle (main-thread API).
@MainActor
func recycle(_ urls: [URL]) async -> (moved: [URL: URL], error: Error?) {
    await withCheckedContinuation { cont in
        NSWorkspace.shared.recycle(urls) { moved, error in cont.resume(returning: (moved, error)) }
    }
}
```

**Notes:**

- **Put Back (answered in fact-check).** Finder's "Put Back" reads two records that it keeps in the **Trash folder's own `.DS_Store`**: `ptbN` (original file name) and `ptbL` (original parent directory, stored *without* the leading slash; the root is an empty string).
  - `FileManager.trashItem` does write these records, but sindresorhus/macos-trash (MIT, v3.1.0) documents "a macOS bug where only the first file gets Put Back metadata" when several files are trashed. It works around the bug by grouping trashed files per Trash folder (handling external volumes) and writing the missing `ptbN`/`ptbL` records with the MIT [`DSStore`](https://github.com/sindresorhus/DSStore) package. VERIFIED-SRC: [macos-trash main.swift](https://github.com/sindresorhus/macos-trash/blob/main/Sources/trash/main.swift).
  - The macos-trash README also says that the **built-in `/usr/bin/trash` added in macOS 15** has "Put Back" broken, and that their binary "fixes" it.
  - **What we do:** call `trashItem` per item, record the `resultingItemURL` in our own undo log, then patch missing Put Back records the same way. We can depend on `DSStore` (MIT) or write the two records ourselves (§4.30.2). Our own "Restore" uses the log plus `moveItem`. Still test on 14, 15, 26 and 27 whether Finder honours the patched records.
- **Other volumes.** `trashItem` routes items on external volumes to that volume's `.Trashes/<uid>`. **(upgraded)** Mole's filesystem fallback does exactly this: it compares `statfs` `f_fsid` of the target with `$HOME`, uses `~/.Trash` on the same volume, and otherwise uses `<mount>/.Trashes/<uid>` (VERIFIED-SRC, [Mole cmd/analyze/delete.go](https://github.com/tw93/Mole/blob/main/cmd/analyze/delete.go)). Our "Trash Bins" feature should enumerate `~/.Trash` plus `/Volumes/*/.Trashes/<uid>`.
- **iCloud Desktop & Documents (added, INFERRED from an OSS comment).** When Desktop/Documents sync to iCloud, the system trash call sends those items to the **iCloud Drive trash**, not `~/.Trash` ([dvakatsiienko/frame comment](https://github.com/dvakatsiienko/frame/blob/main/schedule/jobs/x-autoclean-screenshots/main.swift)). Our Trash Bins view should also show `~/Library/Mobile Documents/com~apple~CloudDocs/.Trash` (path INFERRED; test it).
- **Listing `~/.Trash`.** **(upgraded to VERIFIED-SRC)** Several independent OSS apps measured that a process without FDA gets `Operation not permitted` (EPERM) when listing `~/.Trash`, e.g. [rstrlnkv/Helm](https://github.com/rstrlnkv/Helm/blob/main/Sources/Modules/Uninstaller/Engine/Ports.swift), [pysdenis/kestrel FullDiskAccess.swift](https://github.com/pysdenis/kestrel/blob/main/Sources/KestrelCore/System/FullDiskAccess.swift) (which uses `~/.Trash` as its FDA probe) and [kdbaustert/DockPlus](https://github.com/kdbaustert/DockPlus/blob/master/Sources/DockPlus/DockModel.swift).
  - DockPlus notes that a `stat` of the folder still works without FDA. On APFS, the directory's link count is 2 plus the number of entries (minus Finder's `.DS_Store`), which tells "empty vs not empty" without FDA (INFERRED; test).
  - Without FDA, offer "Empty Trash" through Finder AppleScript (`tell application "Finder" to empty trash`, which needs the Automation permission). Mole avoids the Finder path over SSH, because it raises a dialog on the physical screen that nobody can answer (VERIFIED-SRC, Mole delete.go comment).
- **`/usr/bin/trash` (macOS 15+, added).** It is VERIFIED to exist via Mole (`const trashBinary = "/usr/bin/trash"`, "macOS 15+ ships trash(8)") and sindresorhus. Mole invokes it by absolute path and never passes `--`, because `trash(8)` reports a missing file named "--" and exits non-zero even though it trashed the target. Inside our app, prefer `FileManager.trashItem`; the CLI is only useful from the helper or scripts.
- **Cleaning caches.** Many cleaners delete cache *contents* permanently (CleanMyMac's System Junk does not go via Trash). Deleting *items inside* a cache folder is safer than deleting the folder itself, because apps expect the folder to exist (INFERRED; Mole's Codex rule only removes children of cache leaf directories, VERIFIED-SRC).
- **Root-owned items** fail with `EPERM`/`EACCES` → batch them to the privileged helper (§4.21), or skip and report them.

### 4.4 Safety guard (must run before every destructive call)

Built on MacSai's `SafetyGuard` design (BSD-3, VERIFIED-SRC) and Mole's protection rules (ideas). The code is original.

```swift
import Foundation

struct SafetyGuard: Sendable {
    enum Refusal: Error, Equatable { case empty, nulByte, sip(String), protected(String), excluded(String),
                                     symlinkRedirect(String), notInAllowedRoot(String), tooMany(Int) }

    var maxItemsPerBatch = 50_000
    var userExcluded: [String] = []
    /// Never touch anything at or below these (after canonicalization).
    var protectedPrefixes: [String] = ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple",
                                       "/Applications/Safari.app", "/Library/Keychains",
                                       NSHomeDirectory() + "/Library/Keychains",
                                       NSHomeDirectory() + "/Library/Mobile Documents",
                                       NSHomeDirectory() + "/Library/Mail/V10/MailData"] // tune per feature
    /// Substrings that are always protected (blank System Settings panel bug etc.).
    var protectedSubstrings = ["com.apple.systempreferences.cache", "com.apple.Settings.cache",
                               "com.apple.controlcenter.cache", "/com.apple.TCC/", "/Keychains/"]

    static func canonical(_ p: String) -> String {
        for f in ["var", "tmp", "etc"] {
            let pre = "/private/\(f)"
            if p == pre { return "/\(f)" }
            if p.hasPrefix(pre + "/") { return "/\(f)" + p.dropFirst(pre.count) }
        }
        return p
    }

    func validate(_ urls: [URL], allowedRoots: [String]) throws {
        if urls.count > maxItemsPerBatch { throw Refusal.tooMany(urls.count) }
        for u in urls { try validate(u, allowedRoots: allowedRoots) }
    }

    func validate(_ url: URL, allowedRoots: [String]) throws {
        let raw = url.path(percentEncoded: false)
        if raw.isEmpty { throw Refusal.empty }
        if raw.contains("\0") { throw Refusal.nulByte }
        let original = Self.canonical(raw)
        let resolved = Self.canonical(url.resolvingSymlinksInPath().path(percentEncoded: false))
        if resolved == "/System" || resolved.hasPrefix("/System/") { throw Refusal.sip(resolved) }
        for p in protectedPrefixes.map(Self.canonical) where resolved == p || resolved.hasPrefix(p + "/") {
            throw Refusal.protected(resolved)
        }
        if protectedSubstrings.contains(where: resolved.contains) { throw Refusal.protected(resolved) }
        for e in userExcluded.map(Self.canonical) where resolved == e || resolved.hasPrefix(e + "/") || original.hasPrefix(e + "/") {
            throw Refusal.excluded(resolved)
        }
        // A symlink that jumps somewhere else entirely is suspicious (TOCTOU / redirect).
        if original != resolved,
           Array(original.split(separator: "/").prefix(2)) != Array(resolved.split(separator: "/").prefix(2)) {
            throw Refusal.symlinkRedirect(resolved)
        }
        // Each feature passes the roots it is allowed to clean (e.g. ~/Library/Caches).
        guard allowedRoots.map(Self.canonical).contains(where: { resolved.hasPrefix($0 + "/") }) else {
            throw Refusal.notInAllowedRoot(resolved)
        }
    }
}
```

**Additional rules (INFERRED, aligned with 10-internals §12):**

- Re-validate **right before** deletion, not only at scan time.
- In the helper, delete with `openat(dirfd, name, O_NOFOLLOW)` + `unlinkat` so a path component can't be swapped between check and use.
- Keep a JSON or SQLite **operation log** of every removal (Mole: `operations.log`; MacSai: a 30-day activity log, VERIFIED-SRC).
- Default to dry-run in development builds.

### 4.5 Volume capacity, "available", purgeable

VERIFIED-DOC:

- [`volumeAvailableCapacityForImportantUsageKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey) (10.13): available bytes, including space the system can free.
- [`volumeAvailableCapacityForOpportunisticUsageKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforopportunisticusagekey) (10.13).
- [`volumeAvailableCapacityKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacitykey) (10.6): raw free space.
- [`volumeTotalCapacityKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumetotalcapacitykey).
- [`volumeIsRootFileSystemKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeisrootfilesystemkey), [`volumeIsInternalKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeisinternalkey), [`volumeLocalizedNameKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumelocalizednamekey).

```swift
import Foundation

struct VolumeSpace: Sendable { let name: String; let total: Int64; let freeRaw: Int64; let availableImportant: Int64
    var purgeableEstimate: Int64 { max(0, availableImportant - freeRaw) }   // INFERRED approximation
    var usedFraction: Double { total > 0 ? Double(total - availableImportant) / Double(total) : 0 } }

func volumeSpace(for url: URL = URL(filePath: "/")) throws -> VolumeSpace {
    var u = url; u.removeAllCachedResourceValues()          // values are cached per URL instance
    let v = try u.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                           .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
    return VolumeSpace(name: v.volumeLocalizedName ?? "Macintosh HD",
                       total: Int64(v.volumeTotalCapacity ?? 0),
                       freeRaw: Int64(v.volumeAvailableCapacity ?? 0),
                       availableImportant: v.volumeAvailableCapacityForImportantUsage ?? 0)
}

/// Mounted, user-visible volumes (for "Trash Bins" on external drives, Space Lens picker).
func mountedVolumes() -> [URL] {
    FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey],
                                          options: [.skipHiddenVolumes]) ?? []
}
```

**Notes:**

- Stats instead computes free space with `statfs` (`f_bavail × f_bsize`) and adds the private `CSDiskSpaceGetRecoveryEstimate` for purgeable space on APFS (VERIFIED-SRC). That function is private, so if we use it, declare it ourselves behind a feature flag.
- PureMac's guidance is a good rule to copy: **show purgeable space, never sell it as junk** (VERIFIED-README).
- To actually free purgeable space, thin local snapshots with `tmutil thinlocalsnapshots / <bytes> <urgency 1–4>` (MacSai, VERIFIED-SRC). CleanMyMac's own CLI exposes `optimize purgeable` (VERIFIED-README).

### 4.6 Darwin per-user cache/temp dirs (`/var/folders/…`)

```swift
import Darwin
func darwinUserDir(_ name: Int32) -> String? {          // _CS_DARWIN_USER_CACHE_DIR / _TEMP_DIR / _DIR
    let len = confstr(name, nil, 0); guard len > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: len)
    return confstr(name, &buf, len) > 0 ? String(cString: buf) : nil
}
let userCacheC = darwinUserDir(_CS_DARWIN_USER_CACHE_DIR)   // .../C/
let userTempT  = darwinUserDir(_CS_DARWIN_USER_TEMP_DIR)    // .../T/  (== FileManager.default.temporaryDirectory)
```

Pearcleaner searches both directories (VERIFIED-SRC, Locations.swift). Mole uses `getconf DARWIN_USER_DIR` to find the Notification Center DB **on macOS 14 and older only** (VERIFIED-SRC). The `confstr` approach is INFERRED; check that the constants import into Swift. If they don't, use their raw values from `<unistd.h>`.

**Notification Center DB path (gap answered, corrected).** Since **macOS 15 Sequoia** the live DB is `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, a **TCC-protected group container**, so FDA is required. Before 15 it was `$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`.

- "Sequoia" is the version given by Mole's `resolve_notification_center_db()` comment ("macOS 15+ (Sequoia and later)", issue #1368), by [mac_apt notifications.py](https://github.com/ydkhatri/mac_apt/blob/master/plugins/notifications.py) ("For Sequoia, this is at …") and by HackTricks.
- Objective-See's AuRevoir and blacktop/ipsw comment the new path as "macOS 26+" instead.
- Either way, resolve it at runtime: try the group-container path first, then the legacy one (§4.30.5). Timestamps in this DB (`record.delivered_date`) are **Mac absolute time** (since 2001-01-01).

### 4.7 Process execution helper (for maintenance commands)

```swift
import Foundation

struct CommandResult: Sendable { let status: Int32; let stdout: String; let stderr: String; let timedOut: Bool }

/// Run an absolute executable with explicit argv (never via a shell string).
func run(_ executable: String, _ args: [String], timeout: Duration = .seconds(60)) async throws -> CommandResult {
    let p = Process()
    p.executableURL = URL(filePath: executable)
    p.arguments = args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    try p.run()
    let timedOut = await withTaskGroup(of: Bool.self) { g in
        g.addTask { p.waitUntilExit(); return false }
        g.addTask { try? await Task.sleep(for: timeout); if p.isRunning { p.terminate() }; return true }
        let first = await g.next()!; g.cancelAll(); return first
    }
    let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return CommandResult(status: p.terminationStatus, stdout: o, stderr: e, timedOut: timedOut)
}
```

INFERRED note: for large outputs, read the pipes concurrently, because a full pipe buffer can deadlock `waitUntilExit`. Check that an executable exists before showing its task: `periodic` is missing on macOS 26 (VERIFIED-SRC, Mole and MacSai).

### 4.8 Memory statistics (Activity Monitor style) and memory pressure

C APIs: `host_statistics64(HOST_VM_INFO64)`, `vm_statistics64`, `sysctl vm.swapusage`, `kern.memorystatus_vm_pressure_level`. All VERIFIED-SRC in Stats.
Pressure events: [`DispatchSource.makeMemoryPressureSource(eventMask:queue:)`](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)); the source starts inactive, so call `activate()` (VERIFIED-DOC).
[`ProcessInfo.physicalMemory`](https://developer.apple.com/documentation/foundation/processinfo/physicalmemory) (VERIFIED-DOC).

```swift
import Foundation   // Darwin/Mach

private let hostPort: mach_port_t = mach_host_self()      // cache: each call returns a new send right

struct MemoryStats: Sendable {
    let total, app, wired, compressed, cachedFiles, free, used, swapUsed, swapTotal: UInt64
    let pressure: Pressure
    enum Pressure: Sendable { case normal, warning, critical }
}

func readMemory() -> MemoryStats? {
    var vm = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(hostPort, HOST_VM_INFO64, $0, &count) }
    }
    guard kr == KERN_SUCCESS else { return nil }

    let page = UInt64(vm_kernel_page_size)                // 16 KiB on Apple Silicon
    let total = ProcessInfo.processInfo.physicalMemory
    let internal   = UInt64(vm.internal_page_count) * page
    let purgeable  = UInt64(vm.purgeable_count) * page
    let external   = UInt64(vm.external_page_count) * page
    let wired      = UInt64(vm.wire_count) * page
    let compressed = UInt64(vm.compressor_page_count) * page
    let app        = internal > purgeable ? internal - purgeable : 0
    let cached     = external + purgeable                  // "Cached Files"
    let used       = app + wired + compressed              // "Memory Used"
    let free       = total > used + cached ? total - used - cached : 0

    var swap = xsw_usage(); var swapLen = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &swapLen, nil, 0)

    var level: Int32 = 0; var levelLen = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelLen, nil, 0)
    let pressure: MemoryStats.Pressure = level >= 4 ? .critical : (level == 2 ? .warning : .normal)

    return MemoryStats(total: total, app: app, wired: wired, compressed: compressed, cachedFiles: cached,
                       free: free, used: used, swapUsed: swap.xsu_used, swapTotal: swap.xsu_total, pressure: pressure)
}

/// Push notifications of pressure changes (cheap; use for "High memory pressure" alerts).
func makePressureSource(_ handler: @escaping @Sendable (DispatchSource.MemoryPressureEvent) -> Void) -> DispatchSourceMemoryPressure {
    let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
    src.setEventHandler { handler(src.data) }
    src.activate()
    return src
}
```

**Labels:**

- VERIFIED-SRC: Stats' formula (used = active+inactive+speculative+wired+compressed−purgeable−external; app = used−wired−compressed; cache = purgeable+external) is algebraically close to the above. Re-verified in the fact-check ([Stats RAM readers.swift](https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift) lines ~48–87). Why it is "close" (INFERRED): pageable pages sit on the active, inactive and speculative queues and are either anonymous (internal) or file-backed (external). So active+inactive+speculative ≈ internal+external, and Stats' "app" reduces to internal − purgeable.
- Note that Stats multiplies by `vm_page_size`, while we use `vm_kernel_page_size`. On Apple Silicon both are 16 KiB for native arm64 processes. Under Rosetta, `vm_page_size` is 4 KiB but the counts are in kernel pages, so `vm_kernel_page_size` is the safe choice (INFERRED).
- VERIFIED-SRC: pressure 2 = warn and 4 = critical (Stats). **Upgraded to kernel-verified:** xnu's `sysctl_memorystatus_vm_pressure_level` returns `convert_internal_pressure_level_to_dispatch_level(...)`. That maps Normal → `NOTE_MEMORYSTATUS_PRESSURE_NORMAL` (1), Warning/Urgent → `…_WARN` (2) and Critical → `…_CRITICAL` (4) ([xnu kern_memorystatus_notify.c](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c)).
- **(upgraded) Community consensus, not Apple-documented.** The internal − purgeable form for Activity Monitor's "App Memory", with "Cached Files" = external + purgeable and "Memory Used" = App + Wired + Compressed, appears with that exact label in many independent OSS monitors, e.g. [ashwch/microverse](https://github.com/ashwch/microverse/blob/main/Sources/SystemCore/SystemMonitor.swift), [kennss/SiliconScope](https://github.com/kennss/SiliconScope/blob/main/Sources/SiliconScopeCore/MemorySampler.swift), [canivel/dynolab](https://github.com/canivel/dynolab/blob/main/app/Sources/DynoKit/Collectors.swift) and [ASTL2022/FanSense](https://github.com/ASTL2022/FanSense/blob/main/DataSources.swift). GitHub code search returned 126 hits for the combination. Still compare against Activity Monitor on the Mac mini before shipping.
- MacSai's simpler "used = active+wired+compressed" (VERIFIED-SRC) reads lower than Activity Monitor.

"Free up RAM": `/usr/sbin/purge` needs root (MacSai, VERIFIED-SRC). CleanMyMac's CLI claims `optimize ram` works **without sudo** (VERIFIED-README). INFERRED: it likely triggers the memory-pressure path rather than `purge`. Our first version should use `purge` via the helper or an admin prompt.

**How the vendor frees RAM without sudo (gap partly answered).** Cross-checked from 05-performance.md, which did the primary work:

- `purge` needs root because the **kernel** `vfs_purge()` returns EPERM unless `kauth_cred_issuser()` (xnu `vfs_syscalls.c`).
- MacPaw's own CleanMyMac 3 menu app has **no `purge` string** and no RAM verb in its root agent. It imports `mmap`, `vm_deallocate`, `host_statistics64` and the dispatch memory-pressure source, and has selectors `cleanMemory`, `aggressiveCleanMemory` and `legacyCleanMemory`. That is an **unprivileged in-process allocation-pressure routine** (VERIFIED for CMM3 in 05; INFERRED for X, 5.x and the CLI, consistent with "no sudo").
- Apple's `/usr/bin/memory_pressure -l warn|critical` does the same without root: it `mmap`s, touches, then `madvise(MADV_FREE)`s pages. The `-S` (simulate) mode needs root (05, from Apple's `memory_pressure.c`).
- So the rootless option is either allocation pressure or `memory_pressure -l warn` for a few seconds. **Recommendation (INFERRED):** offer "Release memory" only when pressure ≥ warn. Implement the rootless allocation-pressure path with a hard cap (for example, stop at pressure = warn or after N seconds), and keep `purge` via the helper as the "deep" variant.

### 4.9 CPU usage (total and per core)

`host_processor_info(PROCESSOR_CPU_LOAD_INFO)` + deltas + `vm_deallocate` is VERIFIED-SRC in Stats and MacSai. The code reuses the cached `hostPort` from §4.8.

```swift
import Foundation

final class CPUSampler: @unchecked Sendable {
    private var previous: [Int32] = []
    private let lock = NSLock()

    /// Returns nil on the first call (needs two samples).
    func sample() -> (total: Double, perCore: [Double])? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                              vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        let current = Array(UnsafeBufferPointer(start: info, count: Int(infoCount)))
        lock.lock(); defer { previous = current; lock.unlock() }
        guard previous.count == current.count else { return nil }

        var perCore: [Double] = []; var busyAll: UInt64 = 0; var totalAll: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(cpuCount) {
            func delta(_ state: Int32) -> UInt64 {
                let i = core * stride + Int(state)
                return UInt64(UInt32(bitPattern: current[i]) &- UInt32(bitPattern: previous[i]))  // wrap-safe
            }
            let busy = delta(CPU_STATE_USER) + delta(CPU_STATE_SYSTEM) + delta(CPU_STATE_NICE)
            let total = busy + delta(CPU_STATE_IDLE)
            perCore.append(total > 0 ? Double(busy) / Double(total) : 0)
            busyAll += busy; totalAll += total
        }
        return (totalAll > 0 ? Double(busyAll) / Double(totalAll) : 0, perCore)
    }
}
```

**Extras:**

- Load average: `getloadavg` (INFERRED).
- P-core and E-core counts: `sysctlbyname("hw.perflevel0.logicalcpu")` (performance) and `"hw.perflevel1.logicalcpu"` (efficiency). **(upgraded to VERIFIED-DOC)** Apple's sysctl reference ([Determining system capabilities](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities)) says to read `hw.nperflevels` first. N runs from 0 to nperflevels−1, and "**Lower values of N indicate higher-performance core types**". Per-level keys are `logicalcpu`, `logicalcpu_max`, `physicalcpu`, `physicalcpu_max`, `cpusperl2`, `l2cachesize` and similar. **Don't hard-code two levels.** Stats treats M5-generation chips as having *three* cluster types (E, M, P = "super"), which would mean `hw.nperflevels` = 3 there (INFERRED from Stats).
- **Per-core ordering (gap answered, VERIFIED-SRC from Stats).** Don't assume an order. Stats reads the IORegistry: it iterates `IOServiceMatching("AppleARMPE")` children named `cpu<N>` and reads each one's `cluster-type` property ("E"/"P" before M5; "E"/"M"/"P" from M5 on). The `<N>` in `cpu<N>` is the index into the `host_processor_info` per-core array. The `cpus` node also carries `e-core-count`/`p-core-count` (`m-core-count` on M5+) ([Stats SystemKit.swift `getCPUCores`](https://github.com/exelban/stats/blob/master/Kit/plugins/SystemKit.swift)). A Swift sketch is in §4.30.3. On M1-family chips the E-cores usually come first, but read `cluster-type` rather than relying on that (INFERRED).
- Uptime: `sysctl kern.boottime` (INFERRED). Mole uses uptime in its health score (VERIFIED-SRC).
- Thermal: [`ProcessInfo.thermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) (VERIFIED-DOC) is the only public signal. Real temperatures and fan RPM need SMC/IOHID (private; Stats does it).

### 4.10 Per-process CPU and memory (the "Heavy consumers" list)

`proc_listallpids`, `proc_pidpath`, `proc_pid_rusage` and `ri_phys_footprint` are VERIFIED-SRC in OSS samplers, for example [jettoai/tally ProcessTreeReaders.swift](https://github.com/jettoai/tally/blob/main/Tally/Core/ProcessTreeReaders.swift). Its comments document two gotchas:

1. `proc_listallpids` returns a **count of PIDs** (not bytes).
2. **On Apple Silicon the timebase is 125/3**, so `ri_user_time`/`ri_system_time` are in mach ticks (about 41.67 ns each); on Intel the ratio is 1/1. **(upgraded to kernel-verified)** xnu fills `ri_user_time = powerinfo.total_user` (`osfmk/kern/bsd_kern.c`), and Apple's own xnu tests convert it with `ns_from_mach(...)` / `abs_to_nanos_host(ri_user_time)` (`tests/recount/recount_perf_tests.c`, `tests/sched/setitimer.c`). So these are mach absolute-time units.

```swift
import Foundation

private let timebase: mach_timebase_info_data_t = { var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb); return tb }()
@inline(__always) func ticksToNanos(_ t: UInt64) -> UInt64 { t * UInt64(timebase.numer) / UInt64(timebase.denom) }

func allPIDs() -> [pid_t] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))   // returns a COUNT
    return pids.prefix(Int(max(n, 0))).filter { $0 > 0 }
}

func executablePath(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)    // PROC_PIDPATHINFO_MAXSIZE
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
}

struct ProcSample: Sendable { let pid: pid_t; let cpuNanos: UInt64; let footprint: UInt64 }

func sampleProcess(_ pid: pid_t) -> ProcSample? {
    var ri = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &ri) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard rc == 0 else { return nil }                    // EPERM for other users' / root processes
    return ProcSample(pid: pid, cpuNanos: ticksToNanos(ri.ri_user_time &+ ri.ri_system_time),
                      footprint: ri.ri_phys_footprint)  // ≈ Activity Monitor "Memory" column
}
// CPU% (Activity Monitor convention, can exceed 100% on multi-core) =
//   Δ(cpuNanos) / Δ(wall-clock nanos) * 100
```

**Grouping by app (INFERRED):** map helpers to their app by walking up the path to the enclosing `.app` (from `proc_pidpath`), or use Stats' approach, the private `responsibility_get_pid_responsible_for_pid` via `dlsym` (VERIFIED-SRC). Without root, processes owned by other users return `EPERM`, so list them without numbers.

### 4.11 Running apps: list, observe, quit

VERIFIED-DOC: [`NSWorkspace.runningApplications`](https://developer.apple.com/documentation/appkit/nsworkspace/runningapplications), [`NSRunningApplication.terminate()`](https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate()) and [`forceTerminate()`](https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate()) (both return `Bool`), [`didLaunchApplicationNotification`](https://developer.apple.com/documentation/appkit/nsworkspace/didlaunchapplicationnotification), and [`NSWorkspace.notificationCenter`](https://developer.apple.com/documentation/appkit/nsworkspace/notificationcenter). Workspace notifications are posted **only** on `NSWorkspace.shared.notificationCenter`, not on `NotificationCenter.default`.

```swift
import AppKit

@MainActor
func regularApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
}

/// Polite quit, then force after a grace period (used before uninstall / for "Quit" in the menu app).
@MainActor
func quit(_ app: NSRunningApplication, grace: Duration = .seconds(5)) async -> Bool {
    if app.isTerminated { return true }
    _ = app.terminate()                                    // sends the quit Apple Event (app may ask to save)
    let deadline = ContinuousClock.now + grace
    while !app.isTerminated && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(200)) }
    if !app.isTerminated { _ = app.forceTerminate() }
    return app.isTerminated
}

@MainActor
func observeLaunches(_ onLaunch: @escaping @Sendable (NSRunningApplication) -> Void) -> NSObjectProtocol {
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                      object: nil, queue: .main) { note in
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { onLaunch(app) }
    }
}
```

For background processes that are not apps, use `kill(pid, SIGTERM)` and then `SIGKILL`. This only works for our own user's processes; root processes need the helper (INFERRED). Sending Apple Events to quit other apps may need the Automation (Apple Events) permission when using `NSAppleScript`. `NSRunningApplication.terminate()` doesn't need it (INFERRED; verify).

### 4.12 Network throughput

Stats reads 64-bit counters via sysctl `NET_RT_IFLIST2` and finds the primary interface via `SCDynamicStoreCopyValue("State:/Network/Global/IPv4")` (VERIFIED-SRC). `if_data` from `getifaddrs` has **32-bit** byte counters that wrap at 4 GiB. **(upgraded to VERIFIED-SRC from xnu headers)** In [`bsd/net/if_var.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/net/if_var.h), `struct if_data` declares `u_int32_t ifi_ibytes/ifi_obytes` while `struct if_data64` uses `u_int64_t`. `if_msghdr2.ifm_data` is an `if_data64` (`bsd/net/if.h`), and `NET_RT_IFLIST2` = 6 and `RTM_IFINFO2` = 0x12 (`sys/socket.h`, `net/route.h`).

```swift
import Foundation
import SystemConfiguration

func primaryInterface() -> String? {
    guard let v = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
    return v["PrimaryInterface"] as? String
}

/// 64-bit cumulative byte counters for all interfaces (index 0 = all).
func interfaceBytes() -> [String: (rx: UInt64, tx: UInt64)] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return [:] }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return [:] }
    var result: [String: (UInt64, UInt64)] = [:]
    buf.withUnsafeBytes { raw in
        var off = 0
        while off + MemoryLayout<if_msghdr>.size <= len {
            let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
            if hdr.ifm_msglen == 0 { break }
            if Int32(hdr.ifm_type) == RTM_IFINFO2, off + MemoryLayout<if_msghdr2>.size <= len {
                let h2 = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(h2.ifm_index), &name) != nil {
                    let n = String(cString: name)
                    if !n.hasPrefix("lo") { result[n] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes) }
                }
            }
            off += Int(hdr.ifm_msglen)
        }
    }
    return result
}
// Rate = (bytes_now - bytes_prev) / Δt ; sample every 1 s in the menu app, 2–5 s otherwise.
```

Avoid double-counting tunnels. Mole routes the network graph through the tunnel interface when the IPv4 default route uses one (VERIFIED-README). For the Mac mini, Ethernet is usually `en0` and Wi-Fi `en1` (INFERRED; always resolve dynamically).

### 4.13 Disk I/O rates

From Stats (VERIFIED-SRC): get the BSD name of the root volume's physical store (DiskArbitration `DASessionCreate` + `DADiskCreateFromBSDName`), walk to the `IOBlockStorageDriver` parent, then read `IORegistryEntryCreateCFProperty(parent, "Statistics")` → `"Bytes (Read)"` and `"Bytes (Write)"`, sampling deltas. Mole's health score penalizes read+write above 50 MB/s, with full weight at 150 MB/s (VERIFIED-SRC).

### 4.14 Battery / power (a Mac mini has none, but handle UPS)

[`IOPSCopyPowerSourcesInfo`](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo) is VERIFIED-DOC. The AppleSmartBattery keys are VERIFIED-SRC (Stats).

```swift
import IOKit.ps
import IOKit

struct PowerInfo: Sendable { var hasInternalBattery = false; var isUPS = false; var percent: Int?; var isCharging = false
                             var onAC = true; var cycleCount: Int?; var healthPercent: Int?; var temperatureC: Double? }

func readPower() -> PowerInfo {
    var p = PowerInfo()
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any] else { continue }
        let type = d[kIOPSTypeKey] as? String
        if type == kIOPSInternalBatteryType { p.hasInternalBattery = true } else if type == kIOPSUPSType { p.isUPS = true }
        p.percent = d[kIOPSCurrentCapacityKey] as? Int
        p.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
        p.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    }
    guard p.hasInternalBattery else { return p }          // Mac mini: stop here (maybe UPS)

    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard svc != 0 else { return p }
    defer { IOObjectRelease(svc) }
    func int(_ k: String) -> Int? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int }
    p.cycleCount = int("CycleCount")
    if let design = int("DesignCapacity"), design > 0,
       let maxCap = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity") {   // NOT "MaxCapacity" on Apple Silicon (it's a %)
        p.healthPercent = min(100, Int((100.0 * Double(maxCap) / Double(design)).rounded()))
    }
    if let t = int("Temperature") { p.temperatureC = Double(t) / 100 }
    return p
}
```

For live updates, use `IOPSNotificationCreateRunLoopSource` (VERIFIED-SRC, Stats). Mole's battery health thresholds: more than 800 cycles or under 80% → "Fair"; more than 900 cycles or under 60% → "Service Soon" (VERIFIED-SRC).

### 4.15 Spotlight metadata (last used, large files, app inventory)

VERIFIED-DOC: [`NSMetadataQuery`](https://developer.apple.com/documentation/foundation/nsmetadataquery), [`MDItemCopyAttribute`](https://developer.apple.com/documentation/coreservices/mditemcopyattribute(_:_:)), and [`kMDItemLastUsedDate`](https://developer.apple.com/documentation/coreservices/kmditemlastuseddate) (updated by LaunchServices whenever a file is opened via LaunchServices).

```swift
import Foundation
import CoreServices

/// One-shot metadata read (fast; good for app lists - Pearcleaner batches these in parallel).
func lastUsed(_ url: URL) -> Date? {
    guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
    return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
}

/// Async wrapper around NSMetadataQuery (must run on a thread with a run loop -> main actor).
@MainActor
func spotlight(_ predicate: NSPredicate, scopes: [Any] = [NSMetadataQueryUserHomeScope],
               timeout: Duration = .seconds(5)) async -> [String] {
    let q = NSMetadataQuery()
    q.predicate = predicate
    q.searchScopes = scopes
    return await withCheckedContinuation { cont in
        var done = false
        var token: NSObjectProtocol?
        func finish() {
            guard !done else { return }; done = true
            q.disableUpdates(); q.stop()
            let paths = (0..<q.resultCount).compactMap { (q.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
            if let token { NotificationCenter.default.removeObserver(token) }
            cont.resume(returning: paths)
        }
        token = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
            MainActor.assumeIsolated { finish() }
        }
        q.start()
        Task { try? await Task.sleep(for: timeout); finish() }     // Pearcleaner uses a 5 s timeout
    }
}

// Examples
// Large files ≥ 100 MB in home (Mole's analyzer does the same via `mdfind -onlyin`):
//   await spotlight(NSPredicate(format: "kMDItemFSSize >= %lld", 100 << 20))
// Leftovers by bundle id:
//   await spotlight(NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@ OR kMDItemPath CONTAINS[cd] %@", name, bundleID))
```

**Caveats (INFERRED):**

- Spotlight can be disabled, or can exclude folders (Privacy list). Always combine it with a filesystem walk; Spotlight is only a supplement.
- `kMDItemLastUsedDate` is missing for apps never opened via LaunchServices. Fall back to `contentAccessDateKey` ([VERIFIED-DOC](https://developer.apple.com/documentation/foundation/urlresourcekey/contentaccessdatekey)), but note that atime updates are lazy on APFS.
- `mdutil -s /` reports the indexing status (Mole, VERIFIED-SRC).

### 4.16 App bundle info, Info.plist keys, architectures

VERIFIED-DOC: [`Bundle.executableArchitectures`](https://developer.apple.com/documentation/foundation/bundle/executablearchitectures), [`NSBundleExecutableArchitectureARM64`](https://developer.apple.com/documentation/foundation/nsbundleexecutablearchitecturearm64) (11.0), [`Bundle.appStoreReceiptURL`](https://developer.apple.com/documentation/foundation/bundle/appstorereceipturl), [`isApplicationKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/isapplicationkey), and [`NSWorkspace.urlForApplication(withBundleIdentifier:)`](https://developer.apple.com/documentation/appkit/nsworkspace/urlforapplication(withbundleidentifier:)).

```swift
import Foundation

struct AppRecord: Sendable, Identifiable {
    var id: String { url.path }
    let url: URL; let bundleID: String?; let name: String; let version: String?; let build: String?
    let minOS: String?; let archs: Set<Int>; let fromAppStore: Bool; let iOSWrapped: Bool
    let usesSparkle: Bool; let isSetapp: Bool; let isWebApp: Bool
    var isUniversal: Bool { archs.contains(NSBundleExecutableArchitectureARM64) && archs.contains(NSBundleExecutableArchitectureX86_64) }
    var isIntelOnly: Bool { !archs.isEmpty && !archs.contains(NSBundleExecutableArchitectureARM64) }
}

func readApp(_ url: URL) -> AppRecord? {
    // Read Info.plist directly; Bundle(url:) caches instances and can go stale after an update
    // (Pearcleaner has a readInfoPlistDirect helper for the same reason - INFERRED motivation).
    let wrapped = FileManager.default.fileExists(atPath: url.appending(path: "Wrapper").path)   // iOS/iPad app on Mac
    let plistURL = url.appending(path: "Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: plistURL) as? [String: Any] ?? Bundle(url: url)?.infoDictionary else { return nil }
    let id = info["CFBundleIdentifier"] as? String
    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
    let archs = Set((Bundle(url: url)?.executableArchitectures ?? []).map(\.intValue))
    let receipt = url.appending(path: "Contents/_MASReceipt/receipt")
    return AppRecord(url: url, bundleID: id, name: name,
                     version: info["CFBundleShortVersionString"] as? String, build: info["CFBundleVersion"] as? String,
                     minOS: info["LSMinimumSystemVersion"] as? String, archs: archs,
                     fromAppStore: FileManager.default.fileExists(atPath: receipt.path) ||
                                   FileManager.default.fileExists(atPath: url.appending(path: "Wrapper/iTunesMetadata.plist").path),
                     iOSWrapped: wrapped,
                     usesSparkle: info["SUFeedURL"] != nil || info["SUPublicEDKey"] != nil || info["SUEnableAutomaticChecks"] != nil,
                     isSetapp: id?.hasSuffix("-setapp") ?? false,
                     isWebApp: (info["LSTemplateApplication"] as? Bool ?? false) || (info["CFBundleExecutable"] as? String) == "app_mode_loader")
}

/// Inventory: /Applications, ~/Applications (+ one level of subfolders like "Utilities", vendor folders).
func installedApps() -> [AppRecord] {
    let roots = [URL(filePath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    var out: [AppRecord] = []
    for root in roots {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isApplicationKey],
                                                     options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
        for case let u as URL in e where u.pathExtension == "app" {
            if e.level > 2 { e.skipDescendants(); continue }
            if let r = readApp(u) { out.append(r) }
        }
    }
    return out
}
```

The Mac App Store receipt path is `Contents/_MASReceipt/receipt`; INFERRED, since `appStoreReceiptURL` points there for MAS apps. The other classification rules are VERIFIED-SRC from Pearcleaner (§3.1).

**Mach-O architecture detection without Bundle** (for "Universal Binaries" thinning). Constants VERIFIED-SRC (Pearcleaner Lipo.swift): `FAT_MAGIC 0xcafebabe` (big-endian header, 20-byte `fat_arch`), CPU type `0x0100000C` arm64 and `0x01000007` x86_64. INFERRED additions: `FAT_MAGIC_64 0xcafebabf` (32-byte `fat_arch_64`) and thin `MH_MAGIC_64 0xfeedfacf` (little-endian on disk).

```swift
func sliceSizes(of executable: URL) throws -> [String: UInt64] {
    let fh = try FileHandle(forReadingFrom: executable); defer { try? fh.close() }
    guard let head = try fh.read(upToCount: 8), head.count == 8 else { return [:] }
    func be32(_ d: Data, _ o: Int) -> UInt32 { d.subdata(in: o..<o+4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian } }
    let magic = be32(head, 0)
    guard magic == 0xCAFEBABE else { return [:] }        // thin binary or FAT_MAGIC_64: handle separately
    let n = Int(be32(head, 4)); guard (1...32).contains(n), let archs = try fh.read(upToCount: n * 20) else { return [:] }
    var result: [String: UInt64] = [:]
    for i in 0..<n {
        let cpu = be32(archs, i * 20), size = be32(archs, i * 20 + 12)
        switch cpu { case 0x0100000C: result["arm64"] = UInt64(size)
                     case 0x01000007: result["x86_64"] = UInt64(size)
                     default: result[String(format: "cpu_%08x", cpu)] = UInt64(size) }
    }
    return result
}
```

**Thinning safety (INFERRED):**

- Never thin Mac App Store apps (receipt or signature checks), Apple apps, apps under `/System` or anything SIP-protected, or iOS wrappers.
- Each Mach-O slice carries its own embedded signature, so extracting one slice usually keeps the signature valid. Still, verify afterwards with `codesign --verify --deep --strict` (or `SecStaticCodeCheckValidity` with `kSecCSCheckAllArchitectures | kSecCSStrictValidate`), and keep the original in Trash until the user confirms.
- MacSai has a `MachOWalker` + `ThinAppBundleOperation` (BSD-3) to study ([Sources](https://github.com/iliyami/MacSai/tree/main/Sources/MacCleanKit/Cleaner)).

### 4.17 Code-signature checks (team ID, Apple-signed, entitlements)

VERIFIED-DOC:

- [`SecStaticCodeCreateWithPath`](https://developer.apple.com/documentation/security/secstaticcodecreatewithpath(_:_:_:)), [`SecStaticCodeCheckValidity`](https://developer.apple.com/documentation/security/secstaticcodecheckvalidity(_:_:_:)), [`SecCodeCopySigningInformation`](https://developer.apple.com/documentation/security/seccodecopysigninginformation(_:_:_:)), [`SecRequirementCreateWithString`](https://developer.apple.com/documentation/security/secrequirementcreatewithstring(_:_:_:)).
- Keys: [`kSecCodeInfoTeamIdentifier`](https://developer.apple.com/documentation/security/kseccodeinfoteamidentifier), [`kSecCodeInfoIdentifier`](https://developer.apple.com/documentation/security/kseccodeinfoidentifier), [`kSecCodeInfoEntitlementsDict`](https://developer.apple.com/documentation/security/kseccodeinfoentitlementsdict), [`kSecCodeInfoFlags`](https://developer.apple.com/documentation/security/kseccodeinfoflags).
- Flags: [`kSecCSCheckAllArchitectures`](https://developer.apple.com/documentation/security/kseccscheckallarchitectures), [`kSecCSStrictValidate`](https://developer.apple.com/documentation/security/kseccsstrictvalidate).

Pearcleaner reads entitlements with flag `1 << 2` (kSecCSRequirementInformation) and team ID with `kSecCSSigningInformation` (VERIFIED-SRC).

```swift
import Security

struct SignatureSummary: Sendable { let isValid: Bool; let identifier: String?; let teamID: String?; let isAppleSigned: Bool; let appGroups: [String] }

func signatureSummary(_ url: URL, deep: Bool = false) -> SignatureSummary? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }

    // Fast check for listing; deep check (validates every resource) only on demand - big apps take seconds.
    let flags: SecCSFlags = deep ? SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
                                 : SecCSFlags(rawValue: kSecCSDoNotValidateResources)
    let valid = SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess

    var infoCF: CFDictionary?
    let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    _ = SecCodeCopySigningInformation(code, infoFlags, &infoCF)
    let info = (infoCF as? [String: Any]) ?? [:]
    let ents = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]

    var appleReq: SecRequirement?
    SecRequirementCreateWithString("anchor apple" as CFString, [], &appleReq)
    let apple = appleReq.map { SecStaticCodeCheckValidity(code, [], $0) == errSecSuccess } ?? false

    return SignatureSummary(isValid: valid, identifier: info[kSecCodeInfoIdentifier as String] as? String,
                            teamID: info[kSecCodeInfoTeamIdentifier as String] as? String, isAppleSigned: apple,
                            appGroups: ents?["com.apple.security.application-groups"] as? [String] ?? [])
}
```

**Uses:**

- The team ID and app groups feed the leftover matcher (§3.1).
- `isAppleSigned` (anchor apple) marks Apple system apps that must not be uninstalled. *(Fact-check caveat, INFERRED.)* Apple's own **Mac App Store** apps (Pages, Keynote, Xcode…) are signed through the App Store chain, so they may not satisfy plain `anchor apple`. For protection purposes, also treat apps whose bundle ID starts with `com.apple.` (and that pass `anchor apple generic`) as "Apple". Check the actual DR with `codesign -d -r- /Applications/Pages.app` on the Mac mini.
- An "invalid/unsigned" badge in the Applications list.

Notarization status (INFERRED): run `/usr/sbin/spctl --assess --type execute -vv <app>` (look for `source=Notarized Developer ID`) or `xcrun stapler validate`.

### 4.18 Sandboxed containers and group containers of other apps

Read `~/Library/Containers/<dir>/.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier` to map UUID-named containers to bundle IDs (VERIFIED-SRC, Pearcleaner). `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` is [VERIFIED-DOC](https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)). INFERRED: since macOS 14, opening other apps' Group Containers / Containers data can trigger the "would like to access data from other apps" prompt unless the app has Full Disk Access. Gate these scans behind FDA.

**(gap answered, upgraded to VERIFIED-DOC)**

- **macOS 14 (app containers).** Apple's WWDC23 "What's new in privacy" ([session 10053](https://developer.apple.com/videos/play/wwdc2023/10053/)) says macOS Sonoma "will ask for permission when your app accesses a file in another app's data container", for containers from a *different developer*.
  - The permission lasts while the app stays open and resets when it quits.
  - Apps that "have already been granted **Full Disk Access**" get **no additional prompt**.
  - Apps signed with the same Team ID are exempt by default. `NSDataAccessSecurityPolicy` in Info.plist can replace the same-team default with an explicit allow-list.
- **macOS 15 (group containers).** WWDC24 ([session 10123](https://developer.apple.com/videos/play/wwdc2024/10123/)) extends this to **app group containers**: "a prompt will be shown when apps from other developers attempt to access your groups shared container". The transcript names no FDA exemption for group containers. INFERRED: FDA covers them as it covers app containers, but test on 15/26/27.
- **Deleting a container (added).** Docker's official uninstall docs show `unlinkat …/Library/Containers/com.docker.docker/.com.apple.containermanagerd.metadata.plist: operation not permitted`, and say to give the deleting process **Full Disk Access** to remove the directory later ([docker/docs desktop/uninstall.md](https://github.com/docker/docs/blob/main/content/manuals/desktop/uninstall.md)). A macOS 26 measurement in an OSS repo found that, without that grant, `sudo rm` (EPERM), `/usr/bin/trash` (-5000 afpAccessDenied) and Finder-AppleScript `delete` (-5000) all fail, while the user's own ⌘⌫ in Finder succeeds ([odakin/claude-config note](https://github.com/odakin/claude-config/blob/main/conventions/macos-post-update-slowdown.md); single source, INFERRED).
- **Rule for our uninstaller:**
  - Require FDA before offering container or group-container leftovers.
  - Without FDA, list them as "needs Full Disk Access" or offer "Reveal in Finder".
  - Never report them as removed when the move failed.

### 4.19 Login items, launch agents and daemons, background items

VERIFIED-DOC:

- [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice) (13.0) with `mainApp`, `agent(plistName:)`, `daemon(plistName:)` (the plist must be in **`Contents/Library/LaunchDaemons`**), `loginItem(identifier:)`, `register()`, `unregister()`, `status`, [`statusForLegacyPlist(at:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/statusforlegacyplist(at:)) and [`openSystemSettingsLoginItems()`](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems()).
- [`SMAppService.Status`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) values `.notRegistered`, `.enabled`, `.requiresApproval`, `.notFound`.
- Apple's overview: agents registered via SMAppService replace plists installed in `~/Library/LaunchAgents` or `/Library/LaunchAgents`, and daemons replace `/Library/LaunchDaemons`.

**(a) Our own login item / menu agent:**

```swift
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on {
            if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() } // repair stale state
            try SMAppService.mainApp.register()
        } else { try SMAppService.mainApp.unregister() }
    }
    /// Separate menu-bar helper app embedded at Contents/Library/LoginItems/<Helper>.app
    static let menuAgent = SMAppService.loginItem(identifier: "com.example.sweeper.menu")
}
```

**(b) Enumerating third-party launch agents and daemons** (the "Launch Agents" view):

```swift
struct LaunchJob: Sendable, Identifiable { var id: String { plist.path }
    let plist: URL; let label: String?; let program: String?; let runAtLoad: Bool; let keepAlive: Bool
    let scope: Scope; let approval: SMAppService.Status
    var isBroken: Bool { program.map { !FileManager.default.fileExists(atPath: $0) } ?? false }  // Mole: report missing binaries
    enum Scope: Sendable { case userAgent, globalAgent, globalDaemon } }

func launchJobs() -> [LaunchJob] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let dirs: [(String, LaunchJob.Scope)] = [("\(home)/Library/LaunchAgents", .userAgent),
                                             ("/Library/LaunchAgents", .globalAgent),
                                             ("/Library/LaunchDaemons", .globalDaemon)]   // /System/... is Apple's: read-only, hide
    var jobs: [LaunchJob] = []
    for (dir, scope) in dirs {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".plist") {
            let url = URL(filePath: dir).appending(path: name)
            guard let d = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
            let program = (d["Program"] as? String) ?? (d["ProgramArguments"] as? [String])?.first
            let keepAlive = (d["KeepAlive"] as? Bool) ?? (d["KeepAlive"] is [String: Any])
            jobs.append(LaunchJob(plist: url, label: d["Label"] as? String, program: program,
                                  runAtLoad: d["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive, scope: scope,
                                  approval: SMAppService.statusForLegacyPlist(at: url)))
        }
    }
    return jobs
}
```

**(c) Turning third-party items off (INFERRED; test each):**

- User agent: `launchctl bootout gui/$(id -u) <plist>` stops it now; `launchctl disable gui/$(id -u)/<label>` keeps it off across logins. Use `enable` + `bootstrap` to undo.
- Global daemon: the same with `system/<label>`, via the helper.
- Items registered by other apps through SMAppService/BTM can't be toggled by third parties. Deep-link the user with `SMAppService.openSystemSettingsLoginItems()`.
- The authoritative list of background items is the BTM database (§3.7). **(corrected)** The `.btm` files themselves need only **FDA** (mode 644), not root. `sfltool dumpbtm` is the part that asks "Allow administrator access for sfltool?" on every run (VERIFIED-SRC, Brim and SetShot comments). Mole only uses `sudo -n sfltool dumpbtm` as a last resort, because running it unprivileged pops a system prompt (VERIFIED-SRC). **Our approach:** decode the highest-version `BackgroundItems-v*.btm` directly with FDA, including the per-user v18 files on macOS 27, and keep `sfltool` out of the normal path.
- Turning an item off in System Settings leaves its launchd plist in place, so the plist directories alone can't show the switch state. Only the BTM `disposition` "allowed" bit (0x2) can (VERIFIED-SRC, SetShot comment).

### 4.20 Full Disk Access check

VERIFIED-SRC: MacPaw PermissionsKit's probe set and the EPERM/EACCES logic (§3.11); the same approach appears in [MacDirStat FullDiskAccess.swift](https://github.com/phalladar/MacDirStat/blob/main/Sources/MacDirStat/Utilities/FullDiskAccess.swift). macOS has **no API to request FDA**.

```swift
import AppKit

enum FDAStatus: Sendable { case granted, denied, unknown }

enum FullDiskAccess {
    private static var home: String { NSHomeDirectory() }   // unsandboxed app => real home
    private static var probes: [String] { [
        "\(home)/Library/Safari/CloudTabs.db",
        "\(home)/Library/Safari/Bookmarks.plist",
        "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
        "/Library/Preferences/com.apple.TimeMachine.plist",
    ] }

    static var status: FDAStatus {
        var result = FDAStatus.unknown
        for path in probes {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return .granted }
            if errno == EPERM || errno == EACCES { result = .denied }
        }
        return result
    }

    @MainActor static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    /// Poll after sending the user to Settings (there is no callback).
    static func waitForGrant(timeout: Duration = .seconds(120)) async -> Bool {
        let end = ContinuousClock.now + timeout
        while ContinuousClock.now < end {
            if status == .granted { return true }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return false
    }
}
```

**Notes:**

- MacSai tells users to **restart the app** after granting FDA (VERIFIED-README). INFERRED: offer a "Relaunch" button using `NSWorkspace.openApplication(at:configuration:)` (VERIFIED-DOC [openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:))) followed by `NSApp.terminate`.
- During development, FDA is tied to the app's code signature and path. Rebuilding with a different ad-hoc signature can silently revoke it (INFERRED). Sign builds with a stable identity.
  - **(gap answered, VERIFIED-DOC)** Apple's [TN3127 "Inside Code Signing: Requirements"](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains that macOS records the app's **designated requirement (DR)** for privacy grants. "Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code", so the grant does **not** survive a rebuild. A build signed with an **Apple Development** identity gets a default DR such that "a privilege … acquired by an existing version of your app is still available to a new version".
  - dsswift/cmm's README adds practical notes (INFERRED-community):
    - A self-signed *Code Signing* certificate (Keychain Access → Certificate Assistant) also gives a stable `certificate leaf` DR.
    - Check it with `codesign -d -r- <app>`: "If you only see a cdhash, your next rebuild breaks FDA".
    - Keep a fixed install location, because grants are also associated with the path.
    - **macOS caches TCC decisions for the lifetime of a process**, so relaunch after the grant. This matches MacSai's "restart the app" advice.

### 4.21 Privileged execution: options and a hardened helper skeleton

| Option | Status | Fit for us |
|---|---|---|
| `SMAppService.daemon(plistName:)` + `NSXPCConnection(machServiceName:options:.privileged)` | **Current** (13.0+) (VERIFIED-DOC [daemon(plistName:)](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:)), [init(machServiceName:options:)](https://developer.apple.com/documentation/foundation/nsxpcconnection/init(machservicename:options:))) | Best. User approves once in Login Items. Requires proper code signing |
| `SMJobBless` | **Deprecated 13.0** (VERIFIED-DOC [SMJobBless](https://developer.apple.com/documentation/servicemanagement/smjobbless(_:_:_:_:))) | No |
| `AuthorizationExecuteWithPrivileges` | **Deprecated 10.7** (VERIFIED-DOC [AEWP](https://developer.apple.com/documentation/security/authorizationexecutewithprivileges)) | No |
| `NSAppleScript("do shell script … with administrator privileges")` | Works; standard admin prompt (VERIFIED-DOC class [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript)) | OK for v1 on a personal Mac (rare tasks: purge, mdutil -E, periodic). INFERRED: the prompt repeats per call; credentials are cached briefly |
| `sudo` + Touch ID (`pam_tid`) | CLI only (Mole ships `mo touchid`, VERIFIED-README) | Not for a GUI |

**Hardened helper essentials:**

- VERIFIED-DOC: [`NSXPCListener.setConnectionCodeSigningRequirement(_:)`](https://developer.apple.com/documentation/foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)) and [`NSXPCConnection.setCodeSigningRequirement(_:)`](https://developer.apple.com/documentation/foundation/nsxpcconnection/setcodesigningrequirement(_:)), both 13.0.
- VERIFIED-SRC: the Pearcleaner helper launchd plist keys.
- INFERRED design (also see 10-internals §11.2–11.3).

```swift
// Shared protocol (in a framework both targets link). Typed verbs only - NO "run this shell string".
@objc protocol HelperProtocol {
    func removeItems(_ paths: [String], reply: @escaping (_ removed: [String], _ failures: [String: String]) -> Void)
    func runMaintenance(_ task: String, reply: @escaping (_ status: Int32, _ output: String) -> Void)   // task = enum rawValue
    func helperVersion(reply: @escaping (String) -> Void)
}

// Helper main.swift (installed by SMAppService.daemon from Contents/Library/LaunchDaemons/com.example.sweeper.helper.plist)
import Foundation
final class Helper: NSObject, NSXPCListenerDelegate, HelperProtocol {
    func listener(_ l: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        c.exportedObject = self
        c.resume(); return true
    }
    func removeItems(_ paths: [String], reply: @escaping ([String], [String: String]) -> Void) {
        // Re-run SafetyGuard here with the helper's own allow-list (e.g. /Library/Caches, /Library/Logs,
        // /private/var/log, /Library/LaunchDaemons/<validated label>.plist). Reject symlinks (lstat),
        // delete via openat(O_NOFOLLOW)+unlinkat, log every action.
        reply([], [:])
    }
    func runMaintenance(_ task: String, reply: @escaping (Int32, String) -> Void) {
        // switch on a closed enum -> fixed executable + fixed argv (see 4.23). Unknown => refuse.
        reply(-1, "unsupported")
    }
    func helperVersion(reply: @escaping (String) -> Void) { reply("1.0.0") }
}
let listener = NSXPCListener(machServiceName: "com.example.sweeper.helper")
listener.setConnectionCodeSigningRequirement(
    #"identifier "com.example.sweeper" and anchor apple generic and certificate leaf[subject.OU] = "TEAMID1234""#)
let delegate = Helper()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
```

```xml
<!-- Contents/Library/LaunchDaemons/com.example.sweeper.helper.plist (keys as in Pearcleaner's helper plist) -->
<dict>
  <key>Label</key><string>com.example.sweeper.helper</string>
  <key>BundleProgram</key><string>Contents/MacOS/SweeperHelper</string>
  <key>MachServices</key><dict><key>com.example.sweeper.helper</key><true/></dict>
  <key>AssociatedBundleIdentifiers</key><array><string>com.example.sweeper</string></array>
</dict>
```

```swift
// App side
import ServiceManagement
let helperService = SMAppService.daemon(plistName: "com.example.sweeper.helper.plist")
func ensureHelper() throws {
    switch helperService.status {
    case .enabled: return
    case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
    default: try helperService.register(); if helperService.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}
func helperProxy() -> HelperProtocol? {
    let c = NSXPCConnection(machServiceName: "com.example.sweeper.helper", options: .privileged)
    c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
    c.setCodeSigningRequirement(#"identifier "com.example.sweeper.helper" and anchor apple generic and certificate leaf[subject.OU] = "TEAMID1234""#)
    c.resume()
    return c.remoteObjectProxyWithErrorHandler { _ in } as? HelperProtocol
}
```

**History behind these rules.** The 2018 CVEs had CleanMyMac X's root helper accepting unvalidated callers. VERIFIED: [CVE-2018-4032 JSON](https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4032.json) describes "improperly validates inputs … modify the file system as root". [CVE-2019-5011](https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2019/5xxx/CVE-2019-5011.json) describes an upgrade that "failed to remove the vulnerable components". So:

- Pin the helper version.
- Re-register on every app update.
- Never expose generic file or shell verbs.

Alternative: **SecureXPC** (MIT) gives Codable routes with caller checks.

**Personal-Mac shortcut (INFERRED).** Ship v1 without a daemon. Run the few root tasks via `NSAppleScript` admin prompts, and keep everything else in the user context. That avoids the SMAppService signing requirements. 10-internals §11.4 recommends the same.

**SMAppService signing for a local-only build (gap answered; INFERRED-strong from several independent OSS reports, not Apple-documented).**

- **Ad-hoc ("Sign to Run Locally") builds cannot register SMAppService agents or daemons.** A Team ID is required. Sources:
  - [AgentiLoop/Agent FAQ](https://github.com/AgentiLoop/Agent/blob/main/docs/FAQ.md): "`SMAppService` requires a Team ID to register the Launch Agent/Daemon helpers".
  - [fosteev/Wayfork design doc](https://github.com/fosteev/Wayfork/blob/main/docs/design/05-daemon.md): "Requires the app to be signed with a real Team ID (Apple Development or Developer ID). Ad-hoc builds cannot use `SMAppService`".
  - [RockxyApp/Rockxy CHANGELOG](https://github.com/RockxyApp/Rockxy/blob/main/CHANGELOG.md): fixed helper "Operation not permitted" "by switching from ad-hoc to Apple Development signing".
- **Apple Development signing works** for a daemon with no restricted entitlements (same sources).
- **Caveats to test:**
  - One project reports that macOS rejected a daemon signed with a **free personal-team** certificate and fell back to `SMJobBless` ([slawek19926/Vitals README](https://github.com/slawek19926/Vitals/blob/main/README.md)).
  - Restricted entitlements (for example virtualization) need Developer ID, or launchd crash-loops with `OS_REASON_EXEC` ([arcboxlabs/arcbox-desktop AGENTS.md](https://github.com/arcboxlabs/arcbox-desktop/blob/main/AGENTS.md)).
  - SMAppService refuses a bundle without a sealed `_CodeSignature/CodeResources`, so re-sign the whole app after embedding the helper ([smykla-skalski/harness](https://github.com/smykla-skalski/harness/blob/main/apps/harness-monitor/Scripts/bundle-daemon-agent.sh)).
- **FDA is per binary.** A grant for one executable does not carry over to the daemon inside the app ([myusuf3/mactouch ADR-0017](https://github.com/myusuf3/mactouch/blob/main/docs/adr/0017-app-ships-the-daemon.md)). If the helper deletes TCC-protected paths, it may need its own FDA entry (INFERRED; test).
- Apple-documented plist rules (VERIFIED-DOC, [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)):
  - Use `BundleProgram`, a path relative to the bundle, instead of `Program`.
  - Bundled plists go in `Contents/Library/LaunchAgents` or `LaunchDaemons`.
  - Legacy plists need `AssociatedBundleIdentifiers`, whose Team ID must match the app.

**Conclusion for the Mac mini build:** sign with an Apple Development identity (a paid team is safest), keep one stable signing identity and install path, and keep the NSAppleScript fallback for machines where registration fails.

### 4.22 Notifications

VERIFIED-DOC: [`UNUserNotificationCenter`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) (10.14), [`requestAuthorization(options:completionHandler:)`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)), and the delegate's [`willPresent`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)).

```swift
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()
    func setUp() async {                      // call from applicationDidFinishLaunching
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        let clean = UNNotificationAction(identifier: "CLEAN_NOW", title: "Clean Up", options: [.foreground])
        c.setNotificationCategories([UNNotificationCategory(identifier: "LOW_DISK", actions: [clean], intentIdentifiers: [])])
        _ = try? await c.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func post(id: String, title: String, body: String, category: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        if let category { content.categoryIdentifier = category }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
    // Show banners even while our app is frontmost
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        if r.actionIdentifier == "CLEAN_NOW" { /* route to Cleanup */ }
    }
}
```

**Notes:**

- Throttle alerts. MacSai sends opt-in, throttled disk and memory alerts, and suppresses a dismissed tip for 30 days (VERIFIED-README).
- INFERRED: `UNUserNotificationCenter` needs a real `.app` bundle with a bundle identifier. A bare SwiftPM executable crashes on `current()`.

### 4.23 Maintenance tasks: command table for our implementation

Merged from Mole and MacSai (VERIFIED-SRC). Root is per those sources; other notes are INFERRED unless cited.

| Our task | Command(s) | Root | Guard / note |
|---|---|---|---|
| Free up RAM | `/usr/sbin/purge` | ✔ | Show before and after memory |
| Release purgeable space | `/usr/bin/tmutil thinlocalsnapshots / 999999999999 1` | – | Urgency 1–4; 4 is aggressive |
| Flush DNS cache | `/usr/bin/dscacheutil -flushcache` + `/usr/bin/killall -HUP mDNSResponder` | ✔ | Mole skips while a VPN is active |
| Reindex Spotlight | `/usr/bin/mdutil -E /` (status: `mdutil -s /`) | ✔ | Long; warn the user |
| Rebuild Launch Services | **(corrected)** `…/LaunchServices.framework/Support/lsregister -gc` then `lsregister -r -all local,system,user` (or `-apps local,system,user`; both spellings are reported, so check `lsregister -h` on the Mac mini). The old `-kill -r -domain …` form fails on macOS 26 with "The -kill option has been removed because it was dangerous and no longer useful" and exit 1 ([Scribobulate](https://github.com/MadMartian/Scribobulate/blob/master/packaging/macos/README.md), [kdeldycke](https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh), [1tuz audit](https://github.com/1tuz/Lead-Aggregator/blob/main/docs/audits/2026-10-04/macos.md)). Reports differ on whether `-gc` drops entries for deleted bundles, so also run `lsregister -u <path>` for known-dead app paths (still supported). Use the `-kill` form only on 14/15, if `lsregister -h` still lists it | – | Fixes duplicate "Open With" entries |
| Refresh QuickLook / icons | `qlmanage -r cache`; `qlmanage -r`; remove `~/Library/Caches/com.apple.iconservices*` | – | |
| Run maintenance scripts | `/usr/sbin/periodic daily weekly monthly` | ✔ | **Hide if missing: absent since macOS 15 (corrected)**, so effectively a macOS 14-only task |
| Verify startup disk | `/usr/sbin/diskutil verifyVolume /` | – | Heavy I/O; Mole leaves it off by default |
| Speed up Mail | Quit Mail, then `PRAGMA integrity_check; VACUUM;` on `~/Library/Mail/V*/MailData/Envelope Index` (needs FDA) | – | Skip if Mail is running or the DB is >100 MB |
| Thin Time Machine snapshots | `tmutil thinlocalsnapshots / 999999999999 4` | – | |
| Clear quarantine history | `sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 "DELETE FROM LSQuarantineEvent; VACUUM;"` | – | Privacy feature |
| Prevent .DS_Store on network/USB | `defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true` (+ USBStores) | – | Reversible |
| Old saved app states | Delete `~/Library/Saved Application State/*` older than 30 days | – | |
| Broken launch agents | Report plists whose program is missing | – | Report-only |
| Reclaim Docker space | `docker system prune` (Docker CLI from known paths) | – | Opt-in |

Use the SQLite C API (`import SQLite3`) instead of shelling out to `sqlite3` (INFERRED).

### 4.24 Menu bar app (`MenuBarExtra` with `.window` style)

VERIFIED-DOC: [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra) (13.0), [`.window` style](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window), [`menuBarExtraStyle(_:)`](https://developer.apple.com/documentation/swiftui/scene/menubarextrastyle(_:)), [`init(_:systemImage:isInserted:content:)`](https://developer.apple.com/documentation/swiftui/menubarextra/init(_:systemimage:isinserted:content:)), [`openWindow`](https://developer.apple.com/documentation/swiftui/environmentvalues/openwindow) (13.0), and [`openSettings`](https://developer.apple.com/documentation/swiftui/environmentvalues/opensettings) (14.0).

```swift
import SwiftUI
import Observation

@Observable @MainActor final class LiveStats {
    var cpu: Double = 0; var memoryUsed: Double = 0; var freeDisk: Int64 = 0
    var history: [CPUPoint] = []
    private let sampler = CPUSampler()
    private var timer: Timer?
    func start(interval: TimeInterval = 2) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
    private func tick() {
        if let s = sampler.sample() { cpu = s.total; history.append(.init(date: .now, value: s.total)); history = history.suffix(60) }
        if let m = readMemory() { memoryUsed = Double(m.used) / Double(m.total) }
        if let v = try? volumeSpace() { freeDisk = v.availableImportant }
    }
}
struct CPUPoint: Identifiable { let id = UUID(); let date: Date; let value: Double }

@main
struct SweeperApp: App {
    @State private var stats = LiveStats()
    @AppStorage("showMenuExtra") private var showMenuExtra = true
    var body: some Scene {
        WindowGroup(id: "main") { ContentView() }
        MenuBarExtra(isInserted: $showMenuExtra) {
            MenuPanel().environment(stats).frame(width: 340)
                .task { stats.start() }
        } label: {
            Label("\(Int(stats.cpu * 100))%", systemImage: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView() }
    }
}

struct MenuPanel: View {
    @Environment(LiveStats.self) private var stats
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CPUChart(points: stats.history)
            HStack { Text("Free"); Spacer(); Text(ByteCountFormatter.string(fromByteCount: stats.freeDisk, countStyle: .file)) }
            Button("Open App") { openWindow(id: "main"); NSApp.activate() }
        }.padding()
    }
}
```

**Architecture notes:**

- CleanMyMac's menu is a **separate process** (see 08-menu-app.md / 10-internals.md), and MacSai's `MacCleanMenu` is also independent (VERIFIED-README).
- For that setup, build a second app target with `LSUIElement = YES`, embed it at `Contents/Library/LoginItems/` and register it with `SMAppService.loginItem(identifier:)`. Share state through an App Group `UserDefaults(suiteName:)` or XPC (INFERRED).
- `MenuBarExtraAccess` (MIT) adds programmatic open and close of the `.window` panel, which plain `MenuBarExtra` lacks.
- **macOS 26:** users can hide menu extras in System Settings → Menu Bar. Detect a missing icon and show a hint (VERIFIED-README, Stats FAQ).

### 4.25 Swift Charts snippets

VERIFIED-DOC: [`LineMark`](https://developer.apple.com/documentation/charts/linemark), [`AreaMark`](https://developer.apple.com/documentation/charts/areamark) and [`BarMark`](https://developer.apple.com/documentation/charts/barmark) are 13.0; [`SectorMark`](https://developer.apple.com/documentation/charts/sectormark) is **14.0** (pie/donut).

```swift
import SwiftUI
import Charts

struct CPUChart: View {
    let points: [CPUPoint]
    var body: some View {
        Chart(points) { p in
            AreaMark(x: .value("Time", p.date), y: .value("CPU", p.value))
                .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", p.date), y: .value("CPU", p.value)).interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 1]) { AxisGridLine(); AxisValueLabel(format: .percent) } }
        .chartXAxis(.hidden)
        .frame(height: 70)
    }
}

struct StorageSlice: Identifiable { let id = UUID(); let category: String; let bytes: Int64 }

struct StorageDonut: View {          // "Storage" overview (Apps / Documents / System Data / Free ...)
    let slices: [StorageSlice]
    var body: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("Bytes", s.bytes), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("Category", s.category))
        }
        .chartLegend(position: .trailing)
        .frame(width: 220, height: 220)
    }
}
```

**Space Lens visual (INFERRED):**

- CleanMyMac's Space Lens is a bubble map; see 07-clutter.md / 09-design.md for the exact visuals.
- Implement it with a circle-packing layout. The d3-hierarchy `pack` algorithm is ISC-licensed and based on Wang et al. 2006.
- Or use a squarified treemap (Bruls, Huizing & van Wijk 2000). MacSai's `SquarifiedTreemap.swift` (BSD-3) is a reference.
- Draw with SwiftUI `Canvas` for thousands of nodes.

### 4.26 Background scheduling and incremental updates

- [`NSBackgroundActivityScheduler`](https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler) (10.10, VERIFIED-DOC) runs low-priority periodic work, but **only while our process is alive**. Host it in the menu agent (INFERRED).

  ```swift
  let scheduler = NSBackgroundActivityScheduler(identifier: "com.example.sweeper.quietscan")
  scheduler.repeats = true
  scheduler.interval = 24 * 60 * 60
  scheduler.tolerance = 2 * 60 * 60
  scheduler.qualityOfService = .utility
  scheduler.schedule { done in
      Task { /* light junk-size estimate; notify if > threshold */ done(.finished) }
  }
  ```
- **FSEvents** ([`FSEventStreamCreate`](https://developer.apple.com/documentation/coreservices/1443980-fseventstreamcreate), VERIFIED-DOC) keeps scan results fresh. MacSai uses "FSEvents with historical replay" (VERIFIED-README): store the last `FSEventStreamEventId` and pass it as `sinceWhen` on the next launch to learn which folders changed while the app was closed. Use flags `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`, plus `kFSEventStreamCreateFlagNoDefer` for the UI (INFERRED).
- **Database.** GRDB (MIT, WAL mode, as in MacSai) or SwiftData for scan history, metric history (Burrow keeps a SQLite metric history) and the operation log (INFERRED choice).

### 4.27 Duplicate finder (Swift pipeline)

The algorithm follows czkawka, dupeGuru and MacSai (VERIFIED-SRC); the code is original.

```swift
import Foundation
import CryptoKit

struct Candidate: Sendable, Hashable { let url: URL; let size: Int64; let dev: Int32; let ino: UInt64 }

/// Head+tail prehash (czkawka uses 4 KiB + 4 KiB; dupeGuru uses 16 KiB at offset 16 KiB).
func prehash(_ c: Candidate, chunk: Int = 4096) throws -> SHA256.Digest {
    let fh = try FileHandle(forReadingFrom: c.url); defer { try? fh.close() }
    var h = SHA256()
    if c.size <= Int64(2 * chunk) { h.update(data: try fh.readToEnd() ?? Data()) }
    else {
        h.update(data: try fh.read(upToCount: chunk) ?? Data())
        try fh.seek(toOffset: UInt64(c.size) - UInt64(chunk))
        h.update(data: try fh.read(upToCount: chunk) ?? Data())
    }
    return h.finalize()
}

func fullHash(_ url: URL, bufferSize: Int = 1 << 20) throws -> SHA256.Digest {
    let fh = try FileHandle(forReadingFrom: url); defer { try? fh.close() }
    var h = SHA256()
    while let d = try fh.read(upToCount: bufferSize), !d.isEmpty { h.update(data: d) }
    return h.finalize()
}

func duplicateGroups(_ files: [Candidate], minSize: Int64 = 1) async -> [[Candidate]] {
    // 1) size buckets; 2) collapse hard links (same dev+ino = same data, not a duplicate)
    let bySize = Dictionary(grouping: files.filter { $0.size >= minSize }, by: \.size).values.filter { $0.count > 1 }
    var stage2: [[Candidate]] = []
    for bucket in bySize {
        var seen = Set<[UInt64]>(); let unique = bucket.filter { seen.insert([UInt64(bitPattern: Int64($0.dev)), $0.ino]).inserted }
        if unique.count > 1 { stage2.append(unique) }
    }
    // 3) prehash, 4) full hash - in parallel, bounded
    var result: [[Candidate]] = []
    for bucket in stage2 {
        let pre = await withTaskGroup(of: (Candidate, SHA256.Digest?).self) { g in
            for c in bucket { g.addTask { (c, try? prehash(c)) } }
            var m: [SHA256.Digest: [Candidate]] = [:]
            for await (c, d) in g { if let d { m[d, default: []].append(c) } }
            return m.values.filter { $0.count > 1 }
        }
        for group in pre {
            let full = await withTaskGroup(of: (Candidate, SHA256.Digest?).self) { g in
                for c in group { g.addTask { (c, try? fullHash(c.url)) } }
                var m: [SHA256.Digest: [Candidate]] = [:]
                for await (c, d) in g { if let d { m[d, default: []].append(c) } }
                return m.values.filter { $0.count > 1 }
            }
            result.append(contentsOf: full)
        }
    }
    return result.sorted { ($0.first?.size ?? 0) * Int64($0.count) > ($1.first?.size ?? 0) * Int64($1.count) }
}
```

**Rules (INFERRED, from the OSS behavior above):**

- Always keep one copy per group (MacSai).
- Re-hash right before deleting (MacSai TOCTOU check).
- Skip dataless iCloud files.
- Skip files above a size cap, or warn about them (MacSai uses 500 MB).
- Cache hashes keyed by (path, size, mtime), as czkawka and dupeGuru do.

**APFS "Consolidate" instead of delete.** VERIFIED-SRC (MacSai), with [`volumeSupportsFileCloningKey`](https://developer.apple.com/documentation/foundation/urlresourcekey/volumesupportsfilecloningkey) VERIFIED-DOC.

```swift
import Foundation
/// Replace `copy` with an APFS clone of `master` (same volume). Space is reclaimed; both paths still exist.
func consolidate(master: URL, copy: URL) throws {
    let tmp = copy.deletingLastPathComponent().appending(path: ".\(copy.lastPathComponent).clone-\(UUID().uuidString)")
    guard clonefile(master.path, tmp.path, 0) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    let attrs = try FileManager.default.attributesOfItem(atPath: copy.path)
    try FileManager.default.setAttributes([.posixPermissions: attrs[.posixPermissions] as Any,
                                           .modificationDate: attrs[.modificationDate] as Any], ofItemAtPath: tmp.path)
    guard rename(tmp.path, copy.path) == 0 else { try? FileManager.default.removeItem(at: tmp); throw POSIXError(.init(rawValue: errno) ?? .EIO) }
}
```

Verify hashes before and after, as MacSai does.

### 4.28 Similar photos (native: Vision)

VERIFIED-DOC: [`VNGenerateImageFeaturePrintRequest`](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest) (10.15) and [`VNFeaturePrintObservation.computeDistance(_:to:)`](https://developer.apple.com/documentation/vision/vnfeatureprintobservation/computedistance(_:to:)) (10.15).

```swift
import Vision

func featurePrint(_ url: URL) throws -> VNFeaturePrintObservation? {
    let req = VNGenerateImageFeaturePrintRequest()
    try VNImageRequestHandler(url: url, options: [:]).perform([req])
    return req.results?.first as? VNFeaturePrintObservation
}
func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
    var d: Float = 0
    return (try? a.computeDistance(&d, to: b)) != nil ? d : nil
}
// Cluster: sort by capture date (kMDItemContentCreationDate / EXIF) and only compare
// neighbours within N seconds - "burst/similar" sets are temporally close. Threshold is
// INFERRED and must be tuned on real photos.
```

**Alternatives and the Photos library:**

- Cheap fallback: a 64-bit dHash (resize to 9×8 grayscale, compare adjacent pixels) plus Hamming distance, grouped with a BK-tree, the same as czkawka's thresholds (§3.8).
- For the **Photos library**, use PhotoKit (`PHAsset` fetches, `NSPhotoLibraryUsageDescription`). [`PHAssetChangeRequest.deleteAssets(_:)`](https://developer.apple.com/documentation/photos/phassetchangerequest/deleteassets(_:)) (10.15, VERIFIED-DOC) moves assets to Recently Deleted after a system confirmation (INFERRED behavior).
- PureMac deliberately makes similarity **review-only** (VERIFIED-README). Consider the same default.

### 4.29 Uninstall flow (putting it together)

INFERRED, with the pieces VERIFIED above.

1. Find the app's running instances by bundle ID and `quit` them (§4.11). Quit its helpers and agents too.
2. Collect leftovers with the Pearcleaner-style matcher (§3.1). Show them grouped by Library subfolder, with sizes (§4.1).
3. Unload launch items that belong to the app: `launchctl bootout gui/<uid> <plist>` for user agents, and through the helper for `/Library/LaunchDaemons`.
4. Move the app and leftovers to Trash (§4.3) and record the undo map.
5. Optionally clean package receipts: `pkgutil --pkgs`, `pkgutil --files <id>`, `pkgutil --forget <id>` (root). Mole has `lib/core/pkg_receipts.sh` and Pearcleaner a PKG manager (VERIFIED: files exist).
6. Optionally run `lsregister -u <appPath>` to drop the LaunchServices registration.
7. **Reset** (keep the app, wipe its data): remove only Caches, Preferences, Saved Application State, HTTPStorages, WebKit and Containers *data*. MacSai has an `AppResetPolicy` (VERIFIED-SRC file list).
8. **Never uninstall** Apple apps (anchor apple, `/System/Applications`), or MAS apps without warning. Protect the app's own bundle (VERIFIED-SRC: MacSai `isProtectedApp`).

### 4.30 Fact-check additions to the cookbook

All code here is original. The constants and behaviors are verified as noted; the code has not been compiled or run, so build and test it.

#### 4.30.1 Scan without downloading iCloud files, bumping atimes or hogging the disk

VERIFIED-SRC: the constants are public `#define`s in [xnu `bsd/sys/resource.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h), outside `resource_private.h`:

- `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` = 3, with `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` = 1.
- `IOPOL_TYPE_VFS_ATIME_UPDATES` = 2, with `IOPOL_ATIME_UPDATES_OFF` = 1.
- `IOPOL_TYPE_DISK` = 0, with `IOPOL_UTILITY` = 4 and `IOPOL_THROTTLE` = 3.
- `IOPOL_SCOPE_PROCESS` = 0 and `IOPOL_SCOPE_THREAD` = 1.
- `SF_DATALESS` = `0x40000000` (`bsd/sys/stat.h`).

dsswift/cmm uses the dataless opt-out so that scanning never materializes evicted iCloud files.

```swift
import Darwin

/// Call once at the top of a dedicated scanner Thread (or once per process in a scanner XPC service).
/// Thread scope only affects the calling OS thread - Swift concurrency Tasks can hop threads,
/// so either run the walker on a dedicated `Thread`, or use IOPOL_SCOPE_PROCESS in a separate scanner process.
func applyScannerIOPolicy(scope: Int32 = IOPOL_SCOPE_THREAD) {
    // 1. Touching an iCloud-evicted ("dataless") file must not trigger a download.
    _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, scope, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    // 2. Reading/hashing must not update access times (keeps "last opened" heuristics honest).
    _ = setiopolicy_np(IOPOL_TYPE_VFS_ATIME_UPDATES, scope, IOPOL_ATIME_UPDATES_OFF)
    // 3. Background scans yield disk bandwidth to the user's foreground work.
    _ = setiopolicy_np(IOPOL_TYPE_DISK, scope, IOPOL_UTILITY)
}
```

INFERRED: with materialization off, opening a dataless file fails (probably EDEADLK or similar) instead of downloading it. Treat that error as "cloud-only, skipped". Keep the `SF_DATALESS` check from §4.2 as the first line of defence.

#### 4.30.2 Repair Finder "Put Back" after `trashItem`

The behavior is VERIFIED-SRC (sindresorhus/macos-trash, §4.3). This sketch uses the MIT `DSStore` package's API as macos-trash calls it: `DSStore.read(from:)`, `record(for:type:)`, `add(_:)`, `write(to:)`, and the record types `.trashPutBackName` and `.trashPutBackLocation`.

```swift
import Foundation
import DSStore   // https://github.com/sindresorhus/DSStore (MIT)

/// `moved` = original URL -> URL returned by FileManager.trashItem(at:resultingItemURL:)
func repairPutBack(_ moved: [URL: URL]) {
    let byTrash = Dictionary(grouping: moved, by: { $0.value.deletingLastPathComponent() })   // ~/.Trash or /Volumes/X/.Trashes/<uid>
    for (trashDir, pairs) in byTrash {
        let storeURL = trashDir.appending(path: ".DS_Store")
        var store: DSStore
        do { store = try DSStore.read(from: storeURL) }
        catch DSStore.Error.fileNotFound { store = DSStore() }      // no store yet: start one
        catch { continue }                                          // unreadable/corrupt: never overwrite other items' records
        var changed = false
        for (original, trashed) in pairs {
            let name = trashed.lastPathComponent
            let parent = original.deletingLastPathComponent().path(percentEncoded: false)
            let location = parent == "/" ? "" : String(parent.dropFirst())          // ptbL has no leading slash
            for (type, value) in [(DSStore.RecordType.trashPutBackName, original.lastPathComponent),
                                  (DSStore.RecordType.trashPutBackLocation, location)] {
                if case .string(let v)? = store.record(for: name, type: type)?.value, v == value { continue }
                store.add(DSStore.Record(filename: name, type: type, value: .string(value)))
                changed = true
            }
        }
        if changed { try? store.write(to: storeURL) }   // Trash dir needs FDA to read/write (§4.3)
    }
}
```

#### 4.30.3 Which per-core slot is an E-core or a P-core

The approach is VERIFIED-SRC from Stats `getCPUCores`; this code is an original re-implementation.

```swift
import IOKit

/// Returns cluster type per logical CPU index as reported by IORegistry ("E", "P", and "M" on M5-class chips).
/// Index i lines up with host_processor_info's per-core order (Stats sorts cpu<N> by N and re-indexes 0...).
func coreClusterTypes() -> [String] {
    var services: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMPE"), &services) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(services) }
    var found: [(n: Int, type: String)] = []
    var svc = IOIteratorNext(services)
    while svc != 0 {
        var kids: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(svc, kIOServicePlane, &kids) == KERN_SUCCESS {
            var child = IOIteratorNext(kids)
            while child != 0 {
                var buf = [CChar](repeating: 0, count: 128)                       // io_name_t
                if IORegistryEntryGetName(child, &buf) == KERN_SUCCESS {
                    let name = String(cString: buf)
                    if name.hasPrefix("cpu"), let n = Int(name.dropFirst(3)),
                       let d = IORegistryEntryCreateCFProperty(child, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                                .takeRetainedValue() as? Data {
                        let t = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
                        found.append((n, t))
                    }
                }
                IOObjectRelease(child); child = IOIteratorNext(kids)
            }
            IOObjectRelease(kids)
        }
        IOObjectRelease(svc); svc = IOIteratorNext(services)
    }
    return found.sorted { $0.n < $1.n }.map(\.type)
}
// Cross-check counts with sysctl: hw.nperflevels, hw.perflevel<N>.logicalcpu (N = 0 is the fastest class).
```

#### 4.30.4 Choosing the Background Task Management store

The behavior is VERIFIED-SRC (Brim and SetShot, §3.7); this code is original. Listing the directory fails with EPERM without FDA.

```swift
import Foundation

let btmDir = URL(filePath: "/private/var/db/com.apple.backgroundtaskmanagement")
let btmMachineStore = "FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE"   // machine-wide daemons

/// Highest format version wins (stale lower versions survive OS upgrades).
/// v18+ (macOS 27): one file per user, "BackgroundItems-v18-<UUID>.btm"; earlier: one shared file.
func btmFiles(currentUserUUID: String?) -> [URL] {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: btmDir.path) else { return [] }
    let parsed: [(v: Int, owner: String?, name: String)] = names.compactMap { n in
        guard n.hasPrefix("BackgroundItems-v"), n.hasSuffix(".btm") else { return nil }
        let body = n.dropFirst("BackgroundItems-v".count).dropLast(".btm".count)
        let parts = body.split(separator: "-", maxSplits: 1)
        guard let first = parts.first, let v = Int(first) else { return nil }
        return (v, parts.count > 1 ? parts[1].uppercased() : nil, n)
    }
    guard let top = parsed.map(\.v).max() else { return [] }
    let newest = parsed.filter { $0.v == top }
    let wanted = newest.filter { $0.owner == nil || $0.owner == currentUserUUID?.uppercased() || $0.owner == btmMachineStore }
    return wanted.map { btmDir.appending(path: $0.name) }
}
// currentUserUUID: the directory UUID for getuid() via mbr_uid_to_uuid (<membership.h>; Brim wraps it in a C shim).
// Decode: PropertyListSerialization -> walk "$objects"/"$top" (SetShot style, crash-proof), or NSKeyedUnarchiver
// with stand-in classes (Brim style). v18 root: userStore.records; older: store.itemsByUserIdentifier[uuid].
// Per record: disposition & 0x2 == "allowed" (the System Settings switch), & 0x1 == enabled.
```

#### 4.30.5 Notification Center DB (path plus correct epoch)

```swift
import Foundation

/// macOS 15+: TCC-protected group container (needs FDA). <= 14: DARWIN_USER_DIR. Uses darwinUserDir() from §4.6.
func notificationCenterDB() -> URL? {
    let fm = FileManager.default
    let modern = fm.homeDirectoryForCurrentUser.appending(path: "Library/Group Containers/group.com.apple.usernoted/db2/db")
    if fm.fileExists(atPath: modern.path) { return modern }
    if let dir = darwinUserDir(_CS_DARWIN_USER_DIR) {
        let legacy = URL(filePath: dir).appending(path: "com.apple.notificationcenter/db2/db")
        if fm.fileExists(atPath: legacy.path) { return legacy }
    }
    return nil
}
/// record.delivered_date is Mac absolute time (seconds since 2001-01-01). Convert before comparing.
let macAbsoluteEpochOffset: Int64 = 978_307_200
let pruneOlderThan30DaysSQL =
    "DELETE FROM record WHERE delivered_date < (strftime('%s','now','-30 days') - 978307200);"
```

INFERRED policy: make this an **opt-in privacy item**, off by default. Run it only while `usernoted` is idle, keep a backup copy of `db`, `db-wal` and `db-shm` first, and never delete the DB file itself.

#### 4.30.6 Launch Services rebuild that works on 14 through 27

This adopts the 1tuz audit's approach: "choose legacy reset only when advertised by help" (VERIFIED-SRC for the error string on 26). It uses `run()` from §4.7.

```swift
let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

func rebuildLaunchServices() async throws {
    let help = try await run(lsregister, ["-h"], timeout: .seconds(10))
    let usage = help.stdout + help.stderr
    if usage.contains("-kill") {                                    // older systems still advertise it
        _ = try await run(lsregister, ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"], timeout: .seconds(300))
    } else {                                                        // macOS 26+: -kill and -domain removed
        _ = try await run(lsregister, ["-gc"], timeout: .seconds(300))
        let domainFlag = usage.contains("-all") ? "-all" : "-apps"  // both spellings reported; prefer what -h lists
        _ = try await run(lsregister, ["-r", domainFlag, "local,system,user"], timeout: .seconds(300))
    }
}
// Dead registrations of a specific app path: lsregister -u <path> (works even after the path is deleted).
```

#### 4.30.7 Default-selection precedents worth copying (summary)

All four are VERIFIED-README:

- **MacPaw's CLI:** AI Junk is shown but unchecked, while System Junk and Dev Tools are checked. Project artifacts younger than 7 days start unchecked.
- **cmm:** only regenerable items are pre-ticked; Large & Old is never pre-ticked.
- **PureMac:** Large & Old and Xcode simulator runtimes are never auto-selected; purgeable space is shown but never sold as junk.
- **purge-app:** everything goes to the Trash except simulators, snapshots and Apple Intelligence models.

INFERRED: adopt the same rule. Pre-select only what the system or app regenerates on its own, and make anything that holds user data (downloads, large files, duplicates, AI models, iOS backups) opt-in.

---

## 5. Recommended dependency set (minimal)

| Need | Choice | Why |
|---|---|---|
| Login item | Direct `SMAppService.mainApp` (§4.19) or LaunchAtLogin-Modern (MIT) | Tiny |
| Privileged ops | v1: `NSAppleScript` admin. v2: SMAppService daemon + NSXPC (or SecureXPC, MIT) | Security (§4.21) |
| Self-update | Sparkle 2 (MIT), optional for a personal build | Standard |
| Persistence | GRDB (MIT) or SwiftData | History, operation log |
| Hotkeys | KeyboardShortcuts (MIT), optional | "Scan" hotkey |
| Menu panel control | MenuBarExtraAccess (MIT), optional | Programmatic open and close |
| Everything else | Apple frameworks only (Foundation, AppKit, SwiftUI, Charts, Vision, IOKit, SystemConfiguration, Security, ServiceManagement, UserNotifications, CryptoKit, SQLite3) | No GPL exposure |

---

## 6. Gaps and things to verify on the Mac mini

Status after the fact-check is shown in *italics*.

1. **Put Back.** Does `FileManager.trashItem` produce Finder "Put Back" on macOS 14, 15 and 26?
   - *Mostly answered:* it writes `ptbN`/`ptbL` records into the Trash `.DS_Store`, but only for the first of several files (macOS bug, per sindresorhus/macos-trash).
   - *Patch it (§4.30.2) and still test Finder's Put Back on 14/15/26/27.*
2. **`getattrlistbulk` layout.** Check the record layout (§4.2) against `FileManager` results on APFS, an exFAT USB stick and SMB shares.
   - *The layout rules are now VERIFIED-DOC (xnu man pages).*
   - *The kernel emulates bulk calls on filesystems without native support, so exFAT and SMB should work, only more slowly.*
   - *The code itself is still untested on device.*
3. **Memory numbers.** Compare App/Wired/Compressed/Cached/Used (§4.8) with Activity Monitor; confirm the page size is 16 KiB.
   - *The mapping is community consensus (≥6 OSS monitors) and the pressure values are kernel-verified.*
   - *The on-device comparison is still pending.*
4. **P/E core sysctls** on M4: `hw.perflevel0/1.logicalcpu` and the per-core ordering from `host_processor_info`.
   - *Answered: `hw.nperflevels` plus "lower N = faster" (Apple docs). Per-core type comes from IORegistry `AppleARMPE` → `cpu<N>` → `cluster-type` (Stats).*
   - *Pending: a sanity check on the Mac mini.*
5. **Rootless RAM release.** How does `cleanmymac optimize ram` release memory without root? Compare `memory_pressure -S -l warn` and other approaches before claiming a rootless "free RAM".
   - *Partly answered via 05-performance.md: CMM3 used in-process allocation pressure (`mmap`/`vm_deallocate`, `aggressiveCleanMemory`).*
   - *`memory_pressure -l` needs no root, but `-S` does.*
   - *The CLI's exact mechanism remains undocumented.*
6. **Signing.** Does `SMAppService.daemon` register with an *Apple Development* signature for a local-only build, or is Developer ID required? Can ad-hoc builds keep FDA across rebuilds?
   - *Answered (INFERRED-strong from OSS): Apple Development works; ad-hoc doesn't; free personal-team certificates are doubtful.*
   - *Ad-hoc FDA does **not** survive rebuilds (TN3127, VERIFIED-DOC).*
7. **Root-only `sfltool dumpbtm`.** Does it work non-interactively from our helper on macOS 26? Has the BTM file version changed (`-v4` on Ventura vs later)?
   - *Answered differently: we don't need sfltool. The `.btm` files are mode 644 and FDA-gated, while sfltool prompts for admin on every run.*
   - *Versions: v4 → v7 (13.1) → v8 → … v16 → v18 per-user on macOS 27.*
   - *Still unverified: whether `sudo -n sfltool dumpbtm` from a root daemon avoids the prompt.*
8. **Container access prompt.** Does reading other apps' Containers metadata trigger the macOS 14+ "access data from other apps" prompt without FDA?
   - *Answered for container data (WWDC23): yes; FDA apps are exempt; same-team apps are exempt.*
   - *Group containers are covered from macOS 15 (WWDC24).*
   - *Unverified: whether reading only `.com.apple.containermanagerd.metadata.plist` triggers it. Deleting it fails without FDA (Docker docs).*
9. **Notification Center DB path** on macOS 15/26 (`$(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db`). Mole still references it, but Apple moves these.
   - *Answered: from macOS 15 (some sources say 26) it is `~/Library/Group Containers/group.com.apple.usernoted/db2/db`, which needs FDA.*
   - *Mole now resolves both paths but has an epoch bug (§3.2).*
10. **OnyX task list.** The vendor site was blocked; re-check it when the network allows.
    - *Partly answered: per-OS versions come from the Homebrew cask, and the 5.x task names from a third-party guide (§3.9).*
    - *Not vendor-verified.*
11. **WebSearch was unavailable** for this track. Re-run searches for reviews and design references, such as the Behance/Dribbble MacPaw case studies, if needed; other tracks cover design.
    - *Still unavailable during the fact-check.*
12. *(new)* **`lsregister` flags on 14/15.** Confirm with `lsregister -h` which of `-kill`, `-all` and `-apps` each OS advertises (§4.30.6).
13. *(new)* **Dataless policy.** Confirm what error `open()` returns for an evicted iCloud file once `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` is set (§4.30.1).
14. *(new)* **iCloud Drive trash.** Confirm where `trashItem` puts items from iCloud-synced Desktop/Documents, and include that location in Trash Bins.
15. *(new)* **macOS 27.** Re-run the whole checklist on 27: BTM v18 per-user files, and any new TCC prompts.

---

## 7. Sources (all fetched during this session)

**Open-source projects (README / LICENSE / source files):**

- Pearcleaner: https://github.com/alienator88/Pearcleaner. Files: `Pearcleaner/Logic/{Locations,AppPathsFetch,Conditions,AppInfoFetch,ReversePathsFetch,Lipo,HelperToolManager,Utilities}.swift`, `PearcleanerHelper/{main.swift,CodesignCheck.swift,com.alienator88.Pearcleaner.PearcleanerHelper.plist}`
- Mole: https://github.com/tw93/Mole (LICENSE GPL-3). Files: `lib/optimize/{catalog,tasks,maintenance}.sh`, `lib/clean/{user,caches,system,dev,app_caches,project}.sh`, `lib/core/{app_protection,file_ops}.sh`, `cmd/status/{metrics_health,metrics_memory}.go`, `cmd/analyze/{scanner,constants}.go`
- MacSai: https://github.com/iliyami/MacSai (BSD-3). Files: `Sources/MacCleanKit/{SafetyGuard,MaintenanceTask,DuplicateDetection,FileConsolidator,SquarifiedTreemap,VolumeInfo}.swift`, `Sources/MacCleanKit/SystemStats/{MemoryStats,CPUStats,DiskStats,NetworkRate}.swift`
- PureMac: https://github.com/momenbasel/PureMac
- Burrow: https://github.com/caezium/burrow
- Stats: https://github.com/exelban/stats. Files: `Modules/{RAM,CPU,Net,Disk,Battery}/readers.swift`
- Latest: https://github.com/mangerlahn/Latest. Files: `Latest/Model/Update Checker Extensions/App Store/MacAppStoreCheckerOperation.swift`, `Latest/Model/Sparkle/Sparkle.swift`, `Latest/Model/Update Repository/UpdateRepository.swift`
- KnockKnock: https://github.com/objective-see/KnockKnock (`Plugins/*.m`). DumpBTM: https://github.com/objective-see/DumpBTM. BlockBlock/LuLu LICENSE files (GPL-3)
- czkawka: https://github.com/qarmin/czkawka. Files: `czkawka_core/src/tools/duplicate/mod.rs`, `czkawka_core/src/tools/similar_images/{mod,core}.rs`
- dupeGuru: https://github.com/arsenetar/dupeguru. Files: `core/fs.py`, `core/pe/matchblock.py`, LICENSE
- GrandPerspective: https://grandperspectiv.sourceforge.net/
- Tencent Lemon Cleaner: https://github.com/Tencent/lemon-cleaner
- Sparkle: https://github.com/sparkle-project/Sparkle (README, LICENSE)
- LaunchAtLogin-Modern: https://github.com/sindresorhus/LaunchAtLogin-Modern (readme, `Sources/LaunchAtLogin/LaunchAtLogin.swift`). Defaults / KeyboardShortcuts / Settings license files
- SecureXPC: https://github.com/trilemma-dev/SecureXPC. Blessed: https://github.com/trilemma-dev/Blessed
- MenuBarExtraAccess: https://github.com/orchetect/MenuBarExtraAccess. eul: https://github.com/gao-sun/eul. Clean-Me: https://github.com/Kevin-De-Koninck/Clean-Me. GRDB: https://github.com/groue/GRDB.swift. mas: https://github.com/mas-cli/mas
- Radix (getattrlistbulk): https://github.com/colinvkim/Radix/blob/main/Radix/Services/BulkDirectoryEnumerator.swift
- MacDirStat FDA probe: https://github.com/phalladar/MacDirStat/blob/main/Sources/MacDirStat/Utilities/FullDiskAccess.swift
- Tally (rusage timebase notes): https://github.com/jettoai/tally/blob/main/Tally/Core/ProcessTreeReaders.swift
- XProtect bundle paths (`/private/var/protected/xprotect/XProtect.bundle`, legacy `/Library/Apple/System/Library/CoreServices/XProtect.bundle`): https://github.com/stuartjash/macos-malware-kb/blob/main/scripts/xprotect-snapshot.sh

**MacPaw:**

- PermissionsKit: https://github.com/MacPaw/PermissionsKit (README, LICENSE MIT, `PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m`)
- CleanMyMac CLI: https://github.com/MacPaw/cleanmymac-cli (README; LICENSE = EULA v1.0, 26 June 2026)
- MacPaw org repo list (GitHub search)

**Security:**

- CVE-2018-4032: https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4032.json
- CVE-2019-5011: https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2019/5xxx/CVE-2019-5011.json
- See also 10-internals.md §3.3 for the full Talos list

**Apple documentation** (symbol pages fetched as JSON from `developer.apple.com/tutorials/data/documentation/...`; human URLs below):

- ServiceManagement: `/documentation/servicemanagement/smappservice` (+ `daemon(plistname:)`, `agent(plistname:)`, `loginitem(identifier:)`, `mainapp`, `status-swift.enum`, `statusforlegacyplist(at:)`, `opensystemsettingsloginitems()`), `/smjobbless(_:_:_:_:)`, `/smloginitemsetenabled(_:_:)`
- Foundation:
  - `nsxpclistener/setconnectioncodesigningrequirement(_:)`, `nsxpcconnection/setcodesigningrequirement(_:)`, `nsxpcconnection/init(machservicename:options:)`, `nsxpclistener/init(machservicename:)`
  - `filemanager/trashitem(at:resultingitemurl:)`, `filemanager/containerurl(forsecurityapplicationgroupidentifier:)`, `filemanager/directoryenumerationoptions/{skipspackagedescendants,producesrelativepathurls,includesdirectoriespostorder}`
  - `urlresourcekey/{totalfileallocatedsizekey,fileallocatedsizekey,totalfilesizekey,linkcountkey,fileresourceidentifierkey,fileidentifierkey,volumeidentifierkey,filecontentidentifierkey,maysharefilecontentkey,ispurgeablekey,issparsekey,volumeavailablecapacityforimportantusagekey,volumeavailablecapacityforopportunisticusagekey,volumeavailablecapacitykey,volumetotalcapacitykey,volumesupportsfilecloningkey,volumeisrootfilesystemkey,volumeisinternalkey,volumelocalizednamekey,isapplicationkey,contentaccessdatekey,addedtodirectorydatekey,isubiquitousitemkey,ubiquitousitemdownloadingstatuskey,ishiddenkey,isregularfilekey,issymboliclinkkey,creationdatekey,contentmodificationdatekey}`
  - `nsmetadataquery`, `bundle/{executablearchitectures,appstorereceipturl}`, `nsbundleexecutablearchitecturearm64`, `processinfo/{physicalmemory,thermalstate-swift.property}`, `nsbackgroundactivityscheduler`, `nsapplescript`, `nsfilecoordinator`
- AppKit: `nsworkspace/{recycle(_:completionhandler:),runningapplications,didlaunchapplicationnotification,notificationcenter,urlforapplication(withbundleidentifier:),openapplication(at:configuration:completionhandler:),open(_:)}`, `nsrunningapplication/{terminate(),forceterminate()}`
- Security: `secstaticcodecreatewithpath(_:_:_:)`, `secstaticcodecheckvalidity(_:_:_:)`, `seccodecopysigninginformation(_:_:_:)`, `seccodecopyguestwithattributes(_:_:_:_:)`, `secrequirementcreatewithstring(_:_:_:)`, `kseccodeinfo{teamidentifier,identifier,entitlementsdict,flags}`, `kseccs{checkallarchitectures,strictvalidate}`, `authorizationexecutewithprivileges`
- CoreServices: `mditemcopyattribute(_:_:)`, `kmditemlastuseddate`, `1443980-fseventstreamcreate`, `file_system_events`
- IOKit: `1523839-iopscopypowersourcesinfo`
- Dispatch: `dispatchsource/makememorypressuresource(eventmask:queue:)`, `dispatchsource/memorypressureevent`
- SwiftUI: `menubarextra`, `menubarextrastyle/window`, `scene/menubarextrastyle(_:)`, `menubarextra/init(_:systemimage:isinserted:content:)`, `environmentvalues/{openwindow,opensettings}`
- Charts: `sectormark`, `linemark`, `areamark`, `barmark`
- UserNotifications: `unusernotificationcenter`, `unusernotificationcenter/requestauthorization(options:completionhandler:)`, `unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)`
- Vision: `vngenerateimagefeatureprintrequest`, `vnfeatureprintobservation/computedistance(_:to:)`
- Photos: `phassetchangerequest/deleteassets(_:)`

**Added in the fact-check (all fetched 2026-10-12):**

- xnu (Apple open source): `bsd/man/man2/getattrlist.2`, `bsd/man/man2/getattrlistbulk.2`, `bsd/vfs/vfs_attrlist.c` (bulk emulation), `bsd/sys/resource.h` (iopolicy constants), `bsd/sys/stat.h` (`SF_DATALESS`), `bsd/net/if_var.h`, `bsd/net/if.h`, `bsd/net/route.h`, `bsd/sys/socket.h`, `bsd/kern/kern_memorystatus_notify.c`, `osfmk/kern/bsd_kern.c` and `tests/recount/*` (via GitHub code search). Base: https://github.com/apple-oss-distributions/xnu
- Apple docs: TN3127 https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements · sysctl capabilities https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities · `fileIdentifierKey`, `trashItem(at:resultingItemURL:)`, `SMAppService.daemon(plistName:)`, `NSXPCListener.setConnectionCodeSigningRequirement(_:)` (JSON re-fetched) · Updating helper executables https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
- WWDC transcripts: https://developer.apple.com/videos/play/wwdc2023/10053/ (app container protection) · https://developer.apple.com/videos/play/wwdc2024/10123/ (group container protection; Directory Services plug-ins, legacy QuickLook plug-ins and `com.apple.loginitems.plist` unsupported)
- Put Back: https://github.com/sindresorhus/macos-trash (readme, `Sources/trash/main.swift`, `Sources/trash/Utilities.swift`, `Package.swift`, license) · https://github.com/sindresorhus/DSStore (readme, license)
- BTM: https://github.com/objective-see/DumpBTM (README) · https://github.com/objective-see/KnockKnock/blob/master/Plugins/BTM.m · https://github.com/adamengst/setshot-app (`SetShot/Services/BackgroundItems.swift`, `SetShotTests/BackgroundItemsTests.swift`) · https://github.com/sabharishhh/brim (`BrimCore/Sources/BrimScan/BTM/BTMStore.swift`)
- Notification Center: https://github.com/tw93/Mole/blob/main/lib/optimize/tasks.sh (`resolve_notification_center_db`, SQL) · https://github.com/ydkhatri/mac_apt/blob/master/plugins/notifications.py · Objective-See AuRevoir `Database.m` and blacktop/ipsw `pkg/notif/notif.go` (via code search)
- periodic removal: https://raw.githubusercontent.com/AppliedIR/sift-mcp/main/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml · MacSai `Sources/MacCleanKit/MaintenanceTask.swift` · 05-performance.md §4.4
- lsregister on macOS 26: https://github.com/MadMartian/Scribobulate/blob/master/packaging/macos/README.md · https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh · https://github.com/1tuz/Lead-Aggregator/blob/main/docs/audits/2026-10-04/macos.md · https://github.com/vraravam/dotfiles/blob/master/scripts/osx-defaults.sh · chriskraviz/griffel `scripts/reset-app.sh`
- Memory and CPU: https://github.com/exelban/stats (`Modules/RAM/readers.swift`, `Modules/CPU/readers.swift`, `Kit/plugins/SystemKit.swift`, README FAQ) · App Memory consensus: ashwch/microverse, kennss/SiliconScope, canivel/dynolab, ASTL2022/FanSense, jasonwong1991/WonderBox, zzoko/PerformanceHUD (via code search)
- SMAppService signing reports: https://github.com/AgentiLoop/Agent/blob/main/docs/FAQ.md · https://github.com/fosteev/Wayfork/blob/main/docs/design/05-daemon.md · https://github.com/RockxyApp/Rockxy/blob/main/CHANGELOG.md · https://github.com/slawek19926/Vitals/blob/main/README.md · https://github.com/arcboxlabs/arcbox-desktop/blob/main/AGENTS.md · https://github.com/smykla-skalski/harness/blob/main/apps/harness-monitor/Scripts/bundle-daemon-agent.sh · https://github.com/myusuf3/mactouch/blob/main/docs/adr/0017-app-ships-the-daemon.md
- Trash and FDA measurements: rstrlnkv/Helm, pysdenis/kestrel, kdbaustert/DockPlus, dvakatsiienko/frame (via code search) · Docker container-deletion note: https://github.com/docker/docs/blob/main/content/manuals/desktop/uninstall.md · odakin/claude-config `conventions/macos-post-update-slowdown.md`
- Mole: `cmd/analyze/constants.go`, `cmd/analyze/delete.go`, `lib/optimize/catalog.sh`, `lib/optimize/tasks.sh` (re-fetched)
- OnyX: https://raw.githubusercontent.com/Homebrew/homebrew-cask/main/Casks/o/onyx.rb · https://github.com/dogukannparlak/Onerdigim-uygulama-ve-eklentiler-macos/blob/main/OnyX.md (third-party guide)
- GrandPerspective: https://grandperspectiv.sourceforge.net/ (re-fetched: 3.8.1, 13 Sep 2026, macOS 14+, GPL)
- Sparkle: https://raw.githubusercontent.com/sparkle-project/Sparkle/2.x/README.markdown
- MacPaw: https://github.com/MacPaw/cleanmymac-cli (README re-fetched) · PermissionsKit `MPFullDiskAccessAuthorizer.m` (re-fetched)
- More OSS cleaners: https://github.com/jithin-sabu/purge-app · https://github.com/dsswift/cmm · https://github.com/AlexTkDev/MacOSCleaner · https://github.com/vashpan/xcode-dev-cleaner · https://github.com/AdventDevInc/kudu
- czkawka `czkawka_core/src/tools/duplicate/mod.rs` and README license section; dupeGuru `core/fs.py` and `core/pe/matchblock.py`; LaunchAtLogin-Modern `LaunchAtLogin.swift`; Pearcleaner `PearcleanerHelper/main.swift`, `CodesignCheck.swift`, README and LICENSE.md (all re-fetched)

---

## Verification notes

**Constraints.** WebSearch was still unavailable during the fact-check, because the shared 200-search budget was used up. The vendor sites titanium-software.fr and formulae.brew.sh failed (DNS failure / proxy 403), and `gh api` and GitHub MCP file reads were limited to this repo. Verification therefore used WebFetch (developer.apple.com, sourceforge), `raw.githubusercontent.com` downloads, GitHub repository and code search, and Apple's open-source xnu tree.

**Claims checked (about 25) and outcome:**

| # | Claim | Outcome |
|---|---|---|
| 1 | Mole is GPL-3, ~70k★; Pearcleaner is Apache-2.0 + Commons Clause, "On Hold", 5.4.3 | Confirmed (70,040★; README status re-read) |
| 2 | MacSai BSD-3, 17 modules, 862 tests, macOS 14+; PureMac MIT ~7k★ | Confirmed |
| 3 | `periodic` gone "on macOS 26" | **Corrected:** gone since **macOS 15** (forensic test of 15.6.1, plus man-page sets in 05) |
| 4 | `lsregister -kill -r -domain …` for Rebuild Launch Services | **Corrected:** `-kill`/`-domain` removed on macOS 26 (error string plus exit 1, several measurements). Replaced with `-gc` + `-r -all/-apps`, help-gated (§4.23, §4.30.6) |
| 5 | KnockKnock has 21 persistence plugins | **Corrected:** 20 (21 file pairs include `PluginBase`) |
| 6 | BTM file is root-only | **Corrected:** mode 644, FDA-gated. `sfltool` is what prompts for admin. Version history and macOS 27 per-user v18 files added |
| 7 | Notification Center DB at `DARWIN_USER_DIR/com.apple.notificationcenter/db2/db` | **Corrected:** group container `group.com.apple.usernoted` since macOS 15 (some say 26). Found an epoch bug in Mole's prune SQL |
| 8 | `getattrlistbulk` layout INFERRED | **Upgraded** to VERIFIED-DOC (xnu man pages). Kernel emulation for non-native filesystems added |
| 9 | Stats RAM formula and pressure 1/2/4 | Confirmed; pressure mapping verified in xnu |
| 10 | Activity Monitor App Memory = internal − purgeable | **Upgraded** from INFERRED to community-consensus VERIFIED-SRC; Apple does not document it |
| 11 | `ri_user_time` in mach ticks (125/3) | Confirmed in xnu (`total_user`; tests convert with `ns_from_mach`) |
| 12 | `if_data` counters 32-bit; IFLIST2 64-bit | **Upgraded** to VERIFIED-SRC from xnu headers |
| 13 | `fileIdentifierKey` macOS 13.3; `trashItem` 10.8; `SMAppService.daemon` 13.0, plist in `Contents/Library/LaunchDaemons`; `setConnectionCodeSigningRequirement` 13.0 | Confirmed (Apple doc JSON) |
| 14 | P/E sysctls INFERRED | **Upgraded** to VERIFIED-DOC (`hw.nperflevels`, lower N = faster). Per-core mapping via IORegistry (Stats) added |
| 15 | czkawka prehash 4 KiB head + tail, 2 MiB buffer; MIT core | Confirmed |
| 16 | dupeGuru partial 16 KiB at 16 KiB; samples for files ≥ 3 MiB | Confirmed; "≥" **corrected** to ">" |
| 17 | Sparkle 2.x runtime macOS 12+ | Confirmed (2.9.6 line supports 10.13+) |
| 18 | GrandPerspective 3.8.1, 13 Sep 2026, macOS 14+ | Confirmed |
| 19 | PermissionsKit FDA probe paths and EPERM/EACCES logic | Confirmed |
| 20 | LaunchAtLogin-Modern unregister-then-register | Confirmed |
| 21 | Pearcleaner helper: PID-based check plus `/bin/bash -c` | Confirmed (`SecCodeCopyGuestWithAttributes` with `kSecGuestAttributePid`) |
| 22 | Mole worker pool 2–12; Mobile Documents skipped | Confirmed (`constants.go`) |
| 23 | cleanmymac-cli categories and purge defaults | Confirmed; refined (AI Junk unchecked in sample; full artifact list) |
| 24 | `~/.Trash` listing needs FDA (INFERRED) | **Upgraded** to VERIFIED-SRC (several OSS measurements) |
| 25 | Container prompt on macOS 14 (INFERRED) | **Upgraded** to VERIFIED-DOC (WWDC23; FDA exempt). Group containers on 15 (WWDC24) |

**Gaps filled:**

- Put Back mechanics and the batch bug, with a repair snippet.
- FDA across rebuilds (TN3127).
- SMAppService signing for local builds (OSS consensus).
- BTM versions, permissions and the macOS 27 layout.
- Notification Center path.
- Container prompt and deletion rules.
- P/E core mapping.
- Bulk-attribute behavior on non-APFS volumes.
- OnyX per-OS versions and 5.x task names (third-party).
- Rootless RAM release evidence (cross-referenced from 05).
- New OSS references and seven cookbook additions (§4.30).

**Still uncertain:**

- The exact mechanism of `cleanmymac optimize ram`.
- Whether Finder honours patched Put Back records on 26/27.
- Whether reading only a container's metadata plist triggers the TCC prompt.
- Whether free personal-team signing works for SMAppService daemons.
- `sfltool` behavior from a root daemon.
- Which of `-all`/`-apps` `lsregister` advertises on each OS.
- The `open()` error code for dataless files with materialization off.
- The iCloud Drive trash location.
- Whether the Notification Center move happened in 15 or 26. Sources disagree; the runtime check covers both.
- Vendor confirmation of OnyX's task list.
- The licenses of Brim, SetShot and BTMParser.
- None of the snippets has been compiled; build and test all of them on the Mac mini (Apple Silicon, macOS 14–27).
