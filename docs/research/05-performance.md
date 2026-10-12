# 05 — Performance: Maintenance Tasks, Login & Background Items, Heavy Consumers

> **Track:** Performance. Covers the vendor's maintenance tasks (RAM, purgeable space, DNS, scripts, Spotlight, permissions, Mail, Time Machine snapshots, disk verification, Launch Services), login and background item management, and the hung-app and heavy-consumer tools. It also gives an implementation spec for our own original app.
> **Target:** our app (not called CleanMyMac) on an Apple Silicon Mac mini running macOS 14 Sonoma, 15 Sequoia or 26 Tahoe. macOS 27 is noted where sources cover it.
> **Date:** 2026-10-12. Related reports in this folder: `01-overview.md` (product structure, processes, permissions), `02-smart-care.md` (one-click "Checkup" flow), `03-cleanup.md` (junk, including Broken Login Items) and `04-protection.md`.

---

## 0. Method, labels, limits

- **VERIFIED** means the source cited inline backs the claim. **INFERRED** means our reasoning or our recommendation for our build. Treat INFERRED items as hypotheses to test on a real Mac.
- **Access limits in this session:**
  - The shared web-search budget was used up before this track started, so **no web searches ran**.
  - `macpaw.com`, `cleanmymac.com`, `support.apple.com`, `eclecticlight.co`, `objective-see.org` and the press sites did not resolve from the sandbox (DNS failure).
  - Every claim about MacPaw's 5.x knowledge base (KB) therefore comes from the sibling reports, which read those pages through search excerpts. Such claims are cited as "KB via 01/02".
  - Reachable sources were fetched directly: GitHub (code, wikis, issues, raw files), `developer.apple.com` (documentation JSON), MacPaw's DevMate release-notes files on S3, Apple's open-source `system_cmds`, and a GitHub mirror of rendered macOS man pages for macOS 11–27.
- **Primary MacPaw material read directly in this session:**
  - The CleanMyMac 3 in-app Help book (MacPaw-authored), mirrored on GitHub. Its "Maintenance" topic is the only full vendor description of each task.
  - DevMate release notes for CleanMyMac X 4.10–4.12.2 and CleanMyMac 5.0–5.2.5.
  - MacPaw's `cleanmymac-cli` README and wiki.
  - The Homebrew cask.
- **Screenshot evidence:** a public third-party dataset (`kafkaGen/dora-ai`) holds full-window screenshots of a recent CleanMyMac X build (INFERRED 4.15.x era, since the Claude desktop app, released late 2024, is visible among its login items) with AI-written screen descriptions. Labels read off those screenshots are cited as **[UIDS]**. They show a real build but carry no version stamp.
- Everything is paraphrased. Our UI must use **our own** names, copy and art (see §11).
- **Fact-check pass (added 2026-10-12):** an adversarial review re-checked the key claims against Apple's open-source XNU, `system_cmds` and `mDNSResponder` code, Apple developer docs, rendered man pages and peer code. It also ran `strings` on **MacPaw's own CleanMyMac 3 binaries** (main app, Menu app, privileged Agent; mirrored at `auspham/mac-essential`), cited as **[CMM3-BIN]**. Web search and `macpaw.com` were again unavailable. Items changed by the review are marked **(corrected)** or **(added in fact-check)**. See "Verification notes" at the end.

### Source key (tags used inline)

| Tag | URL |
|---|---|
| [CMM3-9] | https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-9.html (MacPaw's CleanMyMac 3 Help, "Maintenance") |
| [DM5] | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html |
| [DM4] | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html |
| [CLI] | https://github.com/MacPaw/cleanmymac-cli and https://github.com/MacPaw/cleanmymac-cli/wiki/Commands |
| [CASK] | https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb |
| [UIDS] | https://github.com/kafkaGen/dora-ai/tree/main/datasets/routes (routes 1, 7, 8: `image.png` + `node_desc.json`) and https://github.com/kafkaGen/dora-ai/blob/main/help/neo4j/import/graph_export.json |
| [KB-MT] / [KB-OPT] / [KB-SC] | https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks , …/optimization , …/smart-care (via 01/02) |
| [KB-X-MT] / [KB-X-OPT] | https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance , https://macpaw.com/support/cleanmymac-x/knowledgebase/optimization (via 01) |
| [KB-MISS] | https://macpaw.com/support/cleanmymac/knowledgebase/missing-features (via 01) |
| [KB-PROC] | https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes (via 01/02) |
| [MAN-v] | https://github.com/vitorgalvao/macos-man-pages/tree/main/macOS/ (`<v>/man1\|man8/<page>`, rendered from macOS v = 14, 15, 26, 27) |
| [PURGE-SRC] | https://github.com/apple-oss-distributions/system_cmds/blob/main/purge/purge.c and …/purge/purge.8 |
| [A-SMAS] | https://developer.apple.com/documentation/servicemanagement/smappservice (+ `/register()`, `/statusforlegacyplist(at:)`, `/status-swift.enum`, `/opensystemsettingsloginitems()`) |
| [A-NSRA] | https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate() and …/forceterminate() |
| [A-MLI] | https://developer.apple.com/documentation/devicemanagement/servicemanagementmanagedloginitems |
| [A-VOL] | https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey |
| [MOLE-T] / [MOLE-C] / [MOLE-SA] | https://github.com/tw93/Mole/blob/main/lib/optimize/tasks.sh , …/lib/optimize/catalog.sh , …/SECURITY_AUDIT.md |
| [LEMON-RAM] / [LEMON-LI] / [LEMON-XPC] | https://github.com/Tencent/lemon-cleaner/blob/master/localPod/QMCoreFunction/QMCoreFunction/Classes/Utility/QMPurgeRAM.m , …/localPod/QMAppLoginItemManage/QMAppLoginItemManage/Classes/QMLoginItemManager.m , …/Tools/LemonDaemon/LemonDaemon/DaemonXpcService/LMXPCFunction.m |
| [STATS-RAM] / [STATS-CPU] / [STATS-BAT] | https://github.com/exelban/stats/blob/master/Modules/RAM/readers.swift , …/Modules/CPU/readers.swift , …/Modules/Battery/readers.swift |
| [HS] / [FQUA] | https://github.com/Hammerspoon/hammerspoon/blob/master/Hammerspoon/HSuicore.m , https://github.com/rentzsch/ForceQuitUnresponsiveApps |
| [OSQ] | https://github.com/osquery/osquery/blob/master/osquery/tables/system/darwin/startup_items.mm |
| [DUMPBTM] | https://github.com/objective-see/DumpBTM |
| [PP-BTM] | https://github.com/WallyMagill/permission-pulse/blob/main/docs/_btm-schema-dump-tahoe-26.md |
| [GP-BTM] | https://github.com/sweeden-ttu/GlobPretect/blob/main/docs/VPN_BTM_CLI.md |
| [BTM-TBD] | https://github.com/alexey-lysiuk/macos-sdk/blob/main/MacOSX26.5.sdk/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/BackgroundTaskManagement.tbd |
| [ENT-BTM] | https://github.com/apple-oss-distributions/system_cmds/blob/main/atrun/atrun.entitlements |
| [LS-KILL] | https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh , https://github.com/MadMartian/Scribobulate/blob/master/packaging/macos/README.md (corrected: the branch is `master`; the `main` URL returns 404) |
| [PERIODIC-15] | https://github.com/AppliedIR/sift-mcp/blob/main/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml |
| [MACSAI] | https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/MaintenanceTask.swift , issues https://github.com/iliyami/MacSai/issues/129 and /82 |
| [CD-PMD3] / [CD-SPIKE] | https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/device_link.py , https://github.com/jithin-sabu/purge-app/blob/main/spikes/apple-intelligence-models/Sources/aimodels/CacheDeleteCheck.swift (+ the spike's README.md, which records results on macOS 27.0) |
| [CMM3-BIN] (added in fact-check) | MacPaw-built binaries of CleanMyMac 3 (x86_64, ~3.9), read with `strings`: main app `https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203`, Menu app `…/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/MacOS/CleanMyMac%203%20Menu` (+ its `Resources/Base.lproj/Health.strings`), privileged Agent `…/Contents/Library/LaunchServices/com.macpaw.CleanMyMac3.Agent` |
| [CMM3-0DAY] (added in fact-check) | Chi Chou, "CleanMyMac3 Local Privilege Escalation" (2018), archived with the Agent's XPC protocol dump: https://github.com/vulncheck-oss/0day.today.archive/blob/main/local-exploits/30785.txt |
| [XNU] (added in fact-check) | https://github.com/apple-oss-distributions/xnu : `bsd/vfs/vfs_syscalls.c` (`vfs_purge`), `bsd/kern/kern_memorystatus_notify.c` (pressure sysctls), `bsd/kern/kern_newsysctl.c` (sysctl write rule), `bsd/sys/event_private.h` |
| [MP-SRC] (added in fact-check) | https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c and `memory_pressure.1` |
| [MDNS-SRC] (added in fact-check) | https://github.com/apple-oss-distributions/mDNSResponder/blob/mDNSResponder-2200.140.11/mDNSMacOSX/daemon.c (SIGHUP handler) |
| [BTM-LIVE] (added in fact-check) | https://github.com/J-Park-Associates/Tax-Info-Request-List-Pilot/blob/6f6410be32ae5fac84ad4ae3f871e8895f8621dc/pilot/SPEC-mac-rerun1-fixes.md (macOS 26.6), https://github.com/fpcMotif/nix-darwin/blob/90855ed4d1768955000e849df0b6c547a825b701/PANIC.md , https://github.com/plow-pbc/tkmx-client/blob/0a6b48a0e29f935baa4ccc7a509cdfc580bb153b/reporter/doctor.ts , https://github.com/BookCatKid/MacPerms/blob/9195c32e2595eab8d89fc2f417b953b4e7bb46c0/Sources/OtherModel.swift |
| [CD-LOG] (added in fact-check) | Unified-log capture on macOS 26.6.2 showing `CleanMyMac_5_HealthMonitor` as a CacheDelete client: https://github.com/pabloguia/XCodeVault/blob/15bd48e15b8f0894ede4e153f864a7122c88b326/docs/research/evidence/e18-simctl-log-erase-macos26.6.2-25G83-xcode26.5-x86_64-superseded-20260915T202842.txt |
| [CD-TBD] (added in fact-check) | https://github.com/alexey-lysiuk/macos-sdk/blob/main/MacOSX26.5.sdk/System/Library/PrivateFrameworks/CacheDelete.framework/Versions/A/CacheDelete.tbd |
| [LS-GC] (added in fact-check) | https://github.com/chriskraviz/griffel/blob/dc00d630a6cd01b36ab7f546f776e993fae0f1e4/scripts/reset-app.sh , https://github.com/vraravam/dotfiles/blob/ef39047f30c394ac1dc94f282688cef895f822c4/scripts/osx-defaults.sh , https://github.com/jeffmurphy/markdown-quicklook/blob/1d5cb0d1acdb4c551fba164f635052153aed8d32/openspec/changes/archive/2026-09-27-add-markdown-quicklook-preview/design.md |
| [TM-LIST] (added in fact-check) | https://github.com/jithin-sabu/purge-app/blob/6cbd228152f24c080916af9f19d152475c138209/PurgeTests/LocalSnapshotReaderTests.swift |

---

## 1. TL;DR: what matters for implementation

1. **Three generations of the same feature set.**
   - **CleanMyMac 3** had a single "Maintenance" module with 7 tasks.
   - **CleanMyMac X** split it into two sidebar items under a "Speed" heading:
     - **Optimization**: Login Items, Launch Agents, Heavy Consumers, Hung Applications.
     - **Maintenance**: the task list.
   - **CleanMyMac 5.x** merges both into one **Performance** module, which holds **Maintenance Tasks** plus **Login Items** and **Background Items**. The menu-bar app ("Menu") and the Health Monitor agent carry the CPU/memory top-consumer lists and unresponsive-app alerts.
   - VERIFIED: [CMM3-9]; [UIDS] routes 7/8; [KB-MT], [KB-OPT] via 01/02; [DM4] 4.11.0 Menu notes.
2. **Vendor task names across generations** (exact labels):
   - Free Up RAM, Free Up Purgeable Space, Flush DNS Cache, Speed Up Mail, Reindex Spotlight, Repair Disk Permissions.
   - Time Machine Snapshot Thinning (X label) / Thin Time Machine Snapshots (5.x KB wording via 01).
   - Run Maintenance Scripts, Verify Startup Disk, Rebuild Launch Services (Database).
   - VERIFIED: [UIDS] 8_1; [CMM3-9]; [KB-MT] via 01.
3. **On a recent X build, only 7 tasks were listed:** RAM, Purgeable, DNS, Mail, Spotlight, Permissions and TM thinning. Run Maintenance Scripts, Verify Startup Disk and Rebuild Launch Services were absent on that macOS. The vendor therefore filters the catalog by OS capability. VERIFIED [UIDS] 8_1 ("Run · 7 tasks").
4. **"Free Up RAM" is mostly theatre on Apple Silicon.**
   - Apple's own `purge(8)` is documented as forcing the **disk cache** to be flushed, to approximate a cold boot for performance analysis. It "does not affect anonymous memory". Its source is one call to `vfs_purge()`. VERIFIED [PURGE-SRC].
   - **(corrected: citation)** The root requirement is not in `purge.c`. It is in the kernel: `vfs_purge()` returns `EPERM` unless `kauth_cred_issuser()`. The same function also flushes file-backed VM pagers when the sysctl `vfs.purge_vm_pagers` is set (default on). VERIFIED [XNU] `vfs_syscalls.c`.
   - MacPaw's CLI says `optimize ram` "releases inactive memory" and needs **no sudo**. The mechanism is not documented. VERIFIED [CLI].
   - **(added in fact-check)** MacPaw's own CleanMyMac 3 Menu app ("Free Up" next to Memory) contains no `purge` string, and its root Agent has no RAM verb. The Menu binary imports `mmap`, `vm_deallocate`, `host_statistics64` and the dispatch memory-pressure source, and has selectors `cleanMemory`, `aggressiveCleanMemory`, `legacyCleanMemory` and `pidThatCleansMemory`. VERIFIED [CMM3-BIN], [CMM3-0DAY].
   - So the vendor's RAM release is an **unprivileged, in-process allocation-pressure routine**, with an "aggressive" and a "legacy" variant. VERIFIED for CMM3. INFERRED for X, 5.x and the CLI, which is consistent with the CLI's "no sudo". The same technique is VERIFIED in Tencent Lemon [LEMON-RAM] and in Apple's own `memory_pressure -l` [MP-SRC].
5. **Purgeable space.**
   - MacPaw reintroduced **Free Up Purgeable Space** in 5.0.5 (Feb 2025). They describe purgeable data as cached, temporary or re-downloadable files that are safe to remove when space is needed. VERIFIED [DM5].
   - The CLI wording is "asks macOS to release" purgeable space. VERIFIED [CLI].
   - INFERRED: the CLI calls the private CacheDelete service (`CacheDeletePurgeSpaceWithInfo`, keys `CACHE_DELETE_VOLUME/AMOUNT/URGENCY_LIMIT`, VERIFIED [CD-PMD3] [CD-SPIKE]) and/or `tmutil thinlocalsnapshots`.
   - **(added in fact-check)** A unified-log capture on macOS 26.6.2 shows the process `CleanMyMac_5_HealthMonitor` logging under `com.apple.cache_delete:client`, querying per-service amounts. The same lines appear for another monitor app, "System Monitor". VERIFIED [CD-LOG]. The vendor's 5.x background agent therefore links CacheDelete and calls it as an ordinary client. INFERRED: this is the purgeable-space query behind its disk readout, and the purge task uses the same framework.
6. **`periodic` is gone from macOS 15+.**
   - The `periodic(8)` man page exists in the macOS 13 and 14 man sets and is **absent from 15, 26 and 27**. VERIFIED [MAN-v] (re-checked per version in the fact-check).
   - A forensic test of 15.6.1 found no `/usr/sbin/periodic`, no `/etc/periodic` and no `com.apple.periodic-*` jobs. VERIFIED [PERIODIC-15].
   - Some tools say "removed in 26" ([MOLE-T], [MACSAI] issue #129). Either way, **detect at runtime and hide the task on 15+**.
7. **`lsregister -kill` was removed.** On macOS 26 it prints that the option "has been removed because it was dangerous and no longer useful" and exits non-zero. Still accepted: `-gc`, `-r` with `-all`/`-apps local,system,user`, `-f <path>` and `-u <path>`. VERIFIED [LS-KILL].
   - **(corrected)** `-gc` is **not** a full replacement. On macOS 26 it leaves records whose bundle no longer exists. Those "ghosts" are only cleared by `lsregister -u <path>` per stale path, found with `lsregister -dump` plus an existence check. Verify by reading the dump back, not by the exit status. VERIFIED [LS-GC] (griffel) and [LS-KILL] (Scribobulate: 20 of 20 stale records cleared by `-u`, none by `-kill`).
   - Which macOS first dropped `-kill` is unverified. The confirmed observations are on macOS 26. Detect support at runtime from `lsregister -h` output, as one audited script does ([LS-KILL] Lead-Aggregator).
8. **Repair Disk Permissions is obsolete as Apple meant it.**
   - `diskutil verifyPermissions`/`repairPermissions` were removed in OS X 10.11. VERIFIED [MAN-26] `diskutil.8`.
   - The only surviving verb is the undocumented `diskutil resetUserPermissions / <uid>`; it is not in the 14 or 26 man page (VERIFIED by absence). Mole runs it only when home-folder ownership or writability is wrong (VERIFIED [MOLE-T]).
   - The vendor still lists the task in X and 5.x (VERIFIED [UIDS], [KB-MT] via 01).
   - **(added in fact-check)** In CleanMyMac 3 the task had two implementations: `CMResetUserPermissionsTask` (`/usr/sbin/diskutil` + `resetUserPermissions`) and `CMRepairPackagesTask` (`/usr/libexec/repair_packages --repair --standard-pkgs` through the root Agent's `repairPermissionsWithReply:`). VERIFIED [CMM3-BIN]. `repair_packages` has no man page on macOS 11 or later (VERIFIED [MAN-v] by 404). The private method `-[DMRepairDisk beginResetUserPermissionsForDisk:forUID:level:]` is still in DiskManagement.framework on macOS 26.6 (VERIFIED: https://github.com/blacktop/ipsw-diffs/blob/main/macOS/26_6_25G5043d_vs_26_6_25G5052e/DYLIBS/System/Library/PrivateFrameworks/DiskManagement.framework/Versions/A/DiskManagement.md). INFERRED: today's vendor task is the `resetUserPermissions` path.
9. **Spotlight reindex is `mdutil -E /`, which needs root.** The man page says it erases the local store, which is rebuilt "if appropriate". VERIFIED [MAN-26] `mdutil.1`; root requirement VERIFIED by [MACSAI] code comments. The vendor itself warns that reindexing is time- and resource-heavy and Spotlight is unavailable meanwhile (VERIFIED [CMM3-9]).
10. **DNS flush.** The command is `dscacheutil -flushcache` plus `killall -HUP mDNSResponder`, run as root. VERIFIED [MOLE-T].
    - **(added in fact-check)** Apple's macOS `mDNSResponder` source handles SIGHUP as "Purge cache": it purges every cache record, then restarts unicast and multicast queries. VERIFIED [MDNS-SRC]. The query restart is why VPN clients notice.
    - MacPaw's CMM3 Agent used the same pair (`/usr/sbin/dscacheutil -flushcache`, `/usr/bin/killall -HUP`), plus the 10.10-only `discoveryutil mdnsflushcache` / `udnsflushcaches`. VERIFIED [CMM3-BIN].
    - Edge case: the SIGHUP makes VPN clients that watch DNS configuration (for example WireGuard) reconnect, so Mole skips the flush when a VPN is active. VERIFIED [MOLE-T].
11. **Login/background items on macOS 13+ live in Background Task Management (BTM).**
    - Store: `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm`, an NSKeyedArchiver file with root key `store`. Version v16 on Tahoe, with v13 kept alongside. It is readable **with Full Disk Access, without root**. VERIFIED [PP-BTM] [OSQ] [DUMPBTM].
    - There is **no supported per-item toggle** for other apps' items. `sfltool` offers only `dumpbtm` (read) and `resetbtm` (reset everything). VERIFIED [GP-BTM].
    - The private BTM management API is gated by the Apple-only entitlement `com.apple.private.backgroundtaskmanagement.manage`. VERIFIED [ENT-BTM].
12. **What a third-party manager can actually do on 13+:**
    - Disable or enable launchd jobs with `launchctl bootout|disable|enable|bootstrap`. Disables persist across boots. VERIFIED [MAN-26] `launchctl.1`.
      - **(clarified in fact-check)** The man page says `enable|disable` "may only target services within the system domain or user and user-login domains". It does not list `gui/<uid>`. In practice `launchctl disable gui/$UID/<label>` is used in production (Tencent Lemon [LEMON-LI]; slpcat's script notes the overrides land in `disabled.<uid>.plist`). Test it on 14/15/26, and fall back to `user/<uid>/<label>`.
      - **(added in fact-check)** A launchd override and the BTM "Allow in the Background" switch are **two separate databases**. Turning the switch off unloads a plist agent and keeps the plist, while `launchctl print-disabled` still reports the label as enabled. A BTM-disallowed daemon is refused at every boot even with no launchd override. VERIFIED [BTM-LIVE] (macOS 26.6 and others; details in §6.4).
    - Delete plist files (needs the helper for `/Library`).
    - Remove legacy "Open at Login" items through System Events AppleScript. VERIFIED [MOLE-T] [LEMON-LI].
    - Read the allowed state with `SMAppService.statusForLegacyPlist(at:)`. VERIFIED [A-SMAS].
    - **Deep-link to System Settings** for `SMAppService`-registered items of other apps. Lemon explicitly gave up toggling embedded LoginItems on macOS 13+. VERIFIED [LEMON-LI].
13. **Hung apps.** Activity Monitor-style "not responding" status comes from the WindowServer. Hammerspoon calls the private `CGSEventIsAppUnresponsive(CGSMainConnectionID(), &psn)`; ForceQuitUnresponsiveApps subscribes to `kCGSNotificationAppUnresponsive` via `CGSRegisterNotifyProc`. VERIFIED [HS] [FQUA].
    - **(added in fact-check)** MacPaw's own CMM3 Menu (`CMHungAppsMonitor`) imports exactly these symbols: `CGSEventIsAppUnresponsive`, `CGSMainConnectionID`, `CGSRegisterNotifyProc`, `CGSRemoveNotifyProc` and `GetProcessForPID`. VERIFIED [CMM3-BIN]. The vendor uses the same private WindowServer path.
14. **Heavy consumers.** Proven approaches:
    - `ps -Aceo pid,pcpu,comm -r` for CPU, `top -l 1 -o mem -stats pid,command,mem` for memory and `top -o power` for energy. VERIFIED [STATS-CPU] [STATS-RAM] [STATS-BAT].
    - `host_statistics64(HOST_VM_INFO64)` plus `sysctl kern.memorystatus_vm_pressure_level` (2 = warn, 4 = critical) for system memory. VERIFIED [STATS-RAM].
    - Quit with `NSRunningApplication.terminate()`, then `forceTerminate()`. Both return `false` from a sandboxed app, so **our app must not be sandboxed**. VERIFIED [A-NSRA].
15. **Safety lessons from the vendor's own history.**
    - Talos found that CleanMyMac X's root helper exposed generic file operations, including a `removeLaunchdAgentAtPath` primitive (CVE-2018-4042), with no caller validation. VERIFIED (02-smart-care.md, Talos links). **(re-verified)** CVE-2018-4042 maps to TALOS-2018-0716 in the official CVE record, and the archived Talos spotlight names `removeLaunchdAgentAtPath` for that ID (https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4042.json ; https://github.com/EFI-Demo/Endpoint-Forecasting-and-Interpreting, file "Vulnerability Spotlight Multiple privilege escalation vulnerabilities in CleanMyMac X.txt").
    - **(added in fact-check)** A year earlier, CMM3's Agent let any local process run `/usr/sbin/periodic` on an attacker-chosen directory, which is root code execution. VERIFIED [CMM3-0DAY].
    - Our helper must expose **task-specific** methods only (`flushDNS()`, `purgeDiskCache()`, `thinSnapshots(bytes:urgency:)`, `bootoutDaemon(label:)`…) with code-signing checks on the caller.

---

## 2. Feature history: what the vendor shipped, when

| Generation | Container | Tasks / tools | Source |
|---|---|---|---|
| CleanMyMac 3 (2015–2018) | Sidebar module **Maintenance** (alongside Privacy, Extensions, Shredder, Dashboard, Menu) | Run Maintenance Scripts · Repair Disk Permissions · Verify Startup Disk · Speed Up Mail · Rebuild Launch Services Database · Reindex Spotlight · Flush DNS Cache. Selected with checkboxes, then **Run**. **Action › Refresh** re-evaluates the list. | VERIFIED [CMM3-9] |
| CleanMyMac X (2018–2024) | Sidebar heading **Speed** with **Optimization** and **Maintenance** | Optimization: **Login Items, Launch Agents, Heavy Consumers, Hung Applications**. Maintenance: Free Up RAM · Free Up Purgeable Space · Flush DNS Cache · Speed Up Mail · Reindex Spotlight · Repair Disk Permissions · Time Machine Snapshot Thinning, plus Run Maintenance Scripts / Verify Startup Disk / Rebuild Launch Services where supported. | VERIFIED [UIDS] 7_1, 7_2, 8_1; [KB-X-OPT], [KB-X-MT] via 01 |
| X Smart Scan | "Speed" part of the one-click scan | It ran **Flush DNS Cache** and **Free Up RAM** after System Junk and Trash ("Optimizing Your System…"). | VERIFIED [UIDS] 1_5 |
| X Menu 4.11.0 (June 2022) | Menu-bar app | CPU panel: load, **top-consuming apps**, uptime, unusual spikes. Memory panel: available RAM, which apps use it, quick free-up. | VERIFIED [DM4] |
| CleanMyMac 5.0 (Oct 2024) | Sidebar module **Performance** | **Maintenance Tasks** ("View All Tasks"), a "weekly maintenance" bundle with **Review** / **Run Tasks**, and **Login Items** + **Background Items** with reversible enable/disable and permanent remove. | VERIFIED [KB-MT], [KB-OPT] via 01/02 |
| 5.0.5 (2025-02-10) | Performance | **Free Up Purgeable Space** added (described as cached, temporary and re-downloadable data; essential files untouched). | VERIFIED [DM5] for the feature. **(corrected)** The DevMate notes carry no dates; the date comes from 01-overview (whats-new and Homebrew). |
| 5.x Smart Care | Performance tile | Suggests periodic maintenance scripts and Flush DNS Cache; all tasks selected by default. | VERIFIED [KB-SC] via 02 |
| 5.x Health Monitor | Background agent | Alerts on low disk, **high memory usage** and **unresponsive apps**. | VERIFIED [KB-PROC] via 01/02 |
| 5.x Mac App Store edition | — | Some maintenance tasks missing. Login items and launch agents can only be reviewed, not disabled. **(corrected)** Launch agents can still be uninstalled (01-overview: "launch agents uninstalled"; 13-helpcenter agrees). | VERIFIED [KB-MISS] via 01 |
| CleanMyMac 3 internals (added in fact-check) | App + root Agent | Agent XPC verbs: `flushDNSWithReply:`, `startSpotlightReindexWithReply:`, `runPeriodicScript:withReply:`, `repairPermissionsWithReply:`, `removeSMLoginItem:withReply:`, `removeGlobalLoginItemForAppWithPath:withReply:`, `enable/disable/removeLaunchdAgentAtPath:withReply:`, `start/stopStartupItem:withReply:`. App classes: `CMDNSMaintenanceScanner`, `CMSpotlightMaintenanceScanner`, `CMPeriodicMaintenanceScanner`, `CMMailMaintenanceScanner`, `CMLSDBRebuildMaintenanceScanner`, `CMResetUserPermissionsTask`, `CMRepairPackagesTask`. No RAM or `purge` verb in the Agent. | VERIFIED [CMM3-BIN], [CMM3-0DAY] |
| CleanMyMac CLI 1.0 beta (2026) | `cleanmymac optimize [ram\|purgeable]` | RAM: "releases inactive memory", no sudo. Purgeable: "asks macOS to release" purgeable space. | VERIFIED [CLI] |

INFERRED: the 5.x catalog is the X catalog minus tasks the OS cannot run. Treat 5.x as presenting "Run Maintenance Scripts" only on macOS ≤ 14 (01-overview says "≤13"; the man-page evidence in §4.4 says the binary still ships on 14). Verify Startup Disk and Rebuild Launch Services appear to be gone in 5.x; 01-overview could not confirm them on the KB page.

---

## 3. Vendor UI structure (for reference, not for copying)

### 3.1 X "Maintenance" screen (VERIFIED [UIDS] routes/8/1–4)

- **Header:** back button ("Intro", later "Start Over"), centered title "Maintenance", an "Assistant" pill at top right.
- **Left column:** a vertical list of task rows. Each row has a **round checkbox**, a large colored icon and the task name. On that machine all 7 were checked. INFERRED: the vendor preselects every available task, consistent with 5.x Smart Care "all tasks selected by default" (VERIFIED via 02).
- **Right detail pane** for the focused row:
  - a large title;
  - a 2–3 sentence explanation;
  - a "Usage recommendations:" bulleted list. For RAM: the system feels slow, or you need to open a heavy app or file;
  - **"Last run date: Today at 12:58"** pinned near the bottom.
- **Bottom center:** a large **circular "Run" button** with a counter label beside it ("7 tasks").
- **Pre-flight conflict dialog:** "Some applications should be quit." It lists apps (e.g. Mail, with a per-app **Quit** button) and offers **Ignore** and **Quit All**. Speed Up Mail triggers it. VERIFIED [UIDS] 8_2.
- **Progress view:**
  - headline "Performing maintenance tasks…";
  - each row shows state on the right: `•••` = queued, "Running…" + spinner, "Done ✓";
  - the circular button becomes **Stop** with a progress ring.
  - VERIFIED [UIDS] 8_3.
- **Completion:**
  - "Done", "✓ 6 tasks completed" (one of 7 did not complete; INFERRED: skipped via Ignore or failed) and "Your Mac should now run smoother.";
  - a **Share Results** button and a cross-sell card;
  - **"⚠ View Log"** at bottom left, shown with a warning glyph. INFERRED: the glyph means at least one task reported a problem.
  - VERIFIED [UIDS] 8_4.

### 3.2 X "Optimization" screens (VERIFIED [UIDS] routes/7/1–2)

- **Intro screen:** module title, a one-line pitch, two feature bullets (manage the launch agents of your apps; take control of login items) and a primary button **"View All 11 Items…"**. The count is the total across categories.
- **List screen:**
  - **Middle column:** categories with round checkboxes: **Login Items**, **Launch Agents**, **Heavy Consumers**, **Hung Applications**. Hung Applications is greyed out when empty. "Sort by Name ▾" sits above.
  - **Right column:**
    - category title and description;
    - its own "Sort by Name ▾";
    - rows with checkbox, app icon, name and a status dot + "Enabled". Login item rows read like "<App>.app Login Item"; on macOS 13+ these are BTM app/login-item records;
    - **(corrected)** the **Search** field sits in the window's top toolbar, between the "Optimization" title and the "Assistant" pill, not in the right column's header (re-checked on [UIDS] 7_2 `image.png`). The category description reads, paraphrased, "manage the apps that open automatically at every login".
  - **Bottom:** circular **"Perform"** button, disabled until something is checked.
  - INFERRED: the action (Disable/Enable/Remove/Quit) is chosen per category. The exact action picker is not visible in the screenshots, so this is a **GAP**.

### 3.3 5.x Performance (VERIFIED in outline, [KB-MT]/[KB-OPT] via 01/02; layout details GAP)

- The landing view shows a recommended **weekly maintenance** set with **Review** and **Run Tasks**, plus **View All Tasks** for the full list.
- **Login Items** and **Background Items** are separate lists. Enable/disable is reversible; **remove** is permanent and confirmed.
- Smart Care's Performance tile shows the number of maintenance tasks and runs them with the other tiles. 5.2.6+ adds Smart Insights (on-device explanations) for unfamiliar items, including in Performance (VERIFIED via 01).

### 3.4 Our original layout (INFERRED recommendation)

- **One module, two tabs:**
  - **"Routines"** (maintenance tasks): a card grid or list with a "Recommended now" section on top.
  - **"Startup & Background"**: a single unified table of login items, agents and daemons, with segmented filters (All · Open at Login · Agents · Daemons · Helpers) and a status column (Allowed / Disabled / Broken / Managed).
- **A third tab, "Activity"** (heavy consumers + not responding), shares its data source with our menu-bar Monitor.
- Keep the vendor's good interaction ideas, which are generic patterns:
  - checkbox per task;
  - detail pane with "when to run this";
  - last-run timestamp;
  - pre-flight "quit these apps" sheet;
  - per-row live status;
  - cancellable run;
  - summary plus log.
- Do not reuse their wording, circular-button art, gradients or icons.

---

## 4. Maintenance task catalog

Per task: what the vendor says (paraphrased), status on macOS 14/15/26, exact implementation, root needs, side effects, a recommendation rule for our "Recommended now" logic, and our inclusion decision. "Helper" means our privileged `SMAppService.daemon` helper (§8).

### 4.1 Free Up RAM

- **Vendor intent:**
  - When memory fills up, apps and files open slowly. The task makes the system push unused data out of RAM.
  - Run it when the Mac feels slow or before opening a heavy app or file. VERIFIED [UIDS] 8_1.
  - In X Smart Scan it ran automatically after junk removal. VERIFIED [UIDS] 1_5.
- **Mechanisms (choose deliberately):**
  1. **`/usr/sbin/purge`** (root).
     - Source: `int rv = vfs_purge(); if (rv) perror("Unable to purge disk buffers")`.
     - The man page says it forces the disk cache to be flushed and emptied, approximating a cold buffer cache for performance analysis, and does **not** affect `malloc`/`vm_allocate` memory. VERIFIED [PURGE-SRC].
     - It still ships on 14/15/26/27 (`purge.8` present in all). VERIFIED [MAN-v].
     - Without root it fails with "Unable to purge disk buffers: Operation not permitted". VERIFIED (error string in [PURGE-SRC]; EPERM reported by https://github.com/nzbfast/nzbfast/blob/main/bench/component/README.md). **(corrected: stronger source)** The kernel check is `if (!kauth_cred_issuser(kauth_cred_get())) return EPERM;` in `vfs_purge()`. After iterating all mounts it also calls `vm_purge_filebacked_pagers()` when `vfs.purge_vm_pagers` is set (default TRUE). VERIFIED [XNU].
     - Tencent Lemon calls `purge` from its root daemon (`MCCMD_PURGE_MEMORY` → `system("purge")`). VERIFIED [LEMON-XPC].
  2. **Allocation pressure** (no root). Lemon's `purgeRamByHugeMMAPFree` works as follows. VERIFIED [LEMON-RAM]:
     - reads `host_statistics` free + inactive + purgeable page counts;
     - `mmap`s that many bytes as anonymous memory and writes one byte per page;
     - `munmap`s, then calls `malloc_zone_pressure_relief(malloc_default_zone(), 0)`;
     - is rate-limited to once per 10 s;
     - reports the gain as the before/after difference in free pages after a 1 s wait.
     - Fallbacks are malloc-based variants. Comments note an older `syscall(455)` path (root, ≥10.9) was dropped.
  3. **`memory_pressure` tool** (`/usr/bin/memory_pressure`). It can apply real pressure (`-l warn|critical`, or `-p <percent_free>`) or **simulate** a pressure level for N seconds (`-S -l warn -s N`). VERIFIED [MAN-26] `memory_pressure.1`.
     - **(corrected: was UNVERIFIED, now VERIFIED from source [MP-SRC], [XNU])**
       - **`-S` (simulate) needs root.** It writes the sysctl `kern.memorypressure_manual_trigger`. That OID is `CTLFLAG_WR` without `CTLFLAG_ANYBODY`, and XNU's generic rule rejects writes to such OIDs unless `proc_suser()` passes. The tool's own source comment says to use `sudo sysctl -w kern.memorypressure_manual_trigger=…`.
       - **What `-S` does:** it sends `(TEST_LOW_MEMORY_PURGEABLE_TRIGGER_ALL << 16) | level`. The kernel then sets the global pressure level, purges **all purgeable VM objects** (when purge-on-warning/critical is configured) and notifies **every** process registered for pressure events. After `-s` seconds it resets the level to normal. This is a stronger and cleaner "free RAM" than `purge`: apps drop their own caches, and purgeable memory is reclaimed without touching the file cache. It is still a debugging interface.
       - **`-l` / `-p` (real pressure) need no root.** The tool `mmap`s an anonymous range, touches pages with `memset`, and releases them with `madvise(MADV_FREE)`. Apple's own tool thus implements the allocation-pressure technique of mechanism 2. In `-p` mode it may `mlock` pages, which is subject to the memlock limit.
- **MacPaw CLI:** `optimize ram` "releases inactive memory" and needs no sudo. VERIFIED [CLI]. INFERRED: this matches mechanism 2 or `memory_pressure -l`, not `purge` and not `-S`.
- **Vendor GUI (added in fact-check):** CMM3's Menu "Free Up" has no `purge` string, imports `mmap`/`vm_deallocate`, and exposes `aggressiveCleanMemory`/`legacyCleanMemory`. It records its own PID as `pidThatCleansMemory` while cleaning, so the heavy-memory alert ignores the pressure it creates. It watches pressure through `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` and `kern.memorystatus_vm_pressure_level`. The UI shows "Freeing Up…". VERIFIED [CMM3-BIN]. INFERRED for X and 5.x: same family of unprivileged allocation pressure.
- **Effectiveness on Apple Silicon (INFERRED, supported by Apple's own man page):**
  - macOS uses free RAM as file cache and compresses idle anonymous pages.
  - `purge` empties the file cache, so the next launches re-read from SSD (slower, briefly).
  - Allocation pressure briefly *forces* compression/swap of other apps' memory, then lets the kernel reuse it. The "freed GB" number is real but transient.
  - The honest benefit: relief when memory pressure is already red and swapping thrashes, plus the "number goes up" feeling users expect.
- **Our implementation (INFERRED):**
  - **Default:** "Release memory" uses `purge` via the helper (parity with the vendor's root helper), **only offered** when memory pressure is ≥ warn (`kern.memorystatus_vm_pressure_level` ≥ 2) or swap used > 2 GB.
  - Otherwise, show "Memory is healthy, nothing to do" (unchecked) with an explanation.
  - Always measure and show *before → after* "available" memory: `free + inactive + purgeable + speculative` pages (formula style from [STATS-RAM]).
  - **Better advice first:** list the top 5 memory users with **Quit** buttons (§7).
  - **Non-root path for the menu-bar Monitor:** the mmap trick, capped at `min(free+inactive+purgeable, 25% of RAM)`. Run it on a background thread with a 15 s timeout, as Lemon does, and never when pressure is critical.
  - **(added in fact-check)** Alternative root path: the helper runs `/usr/bin/memory_pressure -S -l warn -s 5`. All apps get a pressure notification and purgeable VM is reclaimed, with no file-cache flush. Keep it behind a feature flag, since it is a test interface, and measure it against `purge` on 14/15/26.
  - Mark our own process as "the cleaner" while a release runs (the vendor's `pidThatCleansMemory` pattern), so our Health agent does not fire a high-memory alert caused by our own allocation.
- **Root:** `purge` yes; `memory_pressure -S` yes (VERIFIED); mmap trick and `memory_pressure -l` no.

### 4.2 Free Up Purgeable Space

- **Vendor intent:**
  - Purgeable data is cached, temporary or re-downloadable and safe to remove when more storage is needed. Freeing it doesn't touch essential files or apps. VERIFIED [DM5] (5.0.5).
  - The task already existed in late X builds. VERIFIED [UIDS] 8_1/8_3.
  - The CLI "asks macOS to release disk space that is already marked as purgeable". VERIFIED [CLI].
- **What "purgeable" is (INFERRED, supported):**
  - Space the `deleted` daemon (CacheDelete) can reclaim on demand: Time Machine local snapshots, iCloud Optimized Storage originals, system/app caches registered with CacheDelete, and so on.
  - Finder's "Available" includes it, while `statfs`/`df` free space doesn't. VERIFIED (community explanation): https://github.com/tzarebczan/diskhound/blob/main/src/shared/macStorageAccounting.ts.
  - **Measure** it as `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` on `/` ([A-VOL]; INFERRED formula, same as 02-smart-care.md).
  - Apple flags these keys as "required reason" APIs for privacy manifests. That matters only for App Store builds. VERIFIED [A-VOL].
- **Mechanisms:**
  1. **CacheDelete private API** (`/System/Library/PrivateFrameworks/CacheDelete.framework`).
     - `CacheDeletePurgeSpaceWithInfo(dict, replyBlock)` takes `CACHE_DELETE_VOLUME` (e.g. "/"), `CACHE_DELETE_AMOUNT` (bytes wanted), `CACHE_DELETE_URGENCY_LIMIT` (int) and optionally `CACHE_DELETE_SERVICES` (array of service IDs).
     - Service definitions live in `/System/Library/CacheDelete` (plists with `CACHE_DELETE_ID`).
     - The reply's top-level `CACHE_DELETE_AMOUNT` is the bytes reclaimed.
     - `CacheDeleteCopyPurgeableSpaceWithInfo` queries without purging.
     - On macOS 27.0 the synchronous purge call crashed. Use the reply-block form.
     - VERIFIED [CD-PMD3] (Apple's DeviceLink uses exactly these keys) and [CD-SPIKE].
     - Private API: dlopen + dlsym, feature-flag it, and wrap every call in a timeout.
     - **(added in fact-check)** The macOS 26.5 SDK stub exports `CacheDeletePurgeSpaceWithInfo` **and a separate** `CacheDeletePurgeSpaceWithInfoSync`. It also exports `CacheDeleteCopyPurgeableSpaceWithInfo`, `CacheDeleteCopyItemizedPurgeableSpaceWithInfo`, `CacheDeletePurgeAsync`, `CacheDeleteCancelPurge`, `CacheDeleteCopyAvailableSpaceForVolume` and others. VERIFIED [CD-TBD]. INFERRED: the macOS 27 crash came from calling the block-taking symbol as if it were synchronous. Resolve both symbols and prefer the block form.
     - **(added in fact-check)** The reply block gets a dictionary with `CACHE_DELETE_AMOUNT` and `CACHE_DELETE_VOLUME`. On failure the dictionary holds `CACHE_DELETE_ERROR` ("Failed to purge space: …"). VERIFIED from a decompiled iOS 26.1 CacheDelete (https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete/CacheDeletePurgeSpaceWithInfo.mm). The client forwards to the `deleted` daemon (`clientPurge:replyBlock:`).
     - **(added in fact-check)** A **query** reply on macOS 27.0 had `CACHE_DELETE_AMOUNT`, `CACHE_DELETE_FREESPACE`, `CACHE_DELETE_NONPURGEABLE_AMOUNT` and `CACHE_DELETE_VOLUME`. The service filter `CACHE_DELETE_SERVICES` was honoured (e.g. `com.apple.mobileassetd.cache-delete`). VERIFIED [CD-SPIKE] README.
  2. **`tmutil thinlocalsnapshots / <bytes> <urgency>`** (urgency 1–4; public; root). It only covers Time Machine snapshots. VERIFIED [MAN-26] `tmutil.8`; root requirement VERIFIED by [MACSAI] code comment. **(clarified)** The man page itself only says "several, but not all, verbs require root and Full Disk Access" and does not list the local-snapshot verbs individually. Treat root plus FDA as required.
     - MacSai uses urgency **1** for "purgeable" and **4** for "thin snapshots". VERIFIED [MACSAI].
  3. **Disk-fill trick** (write a huge temp file until `deleted` purges, then delete it). INFERRED: it works but is risky on nearly-full disks. **Do not implement.**
- **Our implementation (INFERRED):**
  - Step 1: measure purgeable as above.
  - Step 2: if ≥ 1 GB, run CacheDelete with `AMOUNT = purgeable`, `URGENCY_LIMIT = 3`, async with a 120 s timeout.
  - Step 3: if CacheDelete is unavailable, fall back to `tmutil thinlocalsnapshots / <purgeable> 1` via the helper.
  - Re-measure after 2 s and 10 s, since reclamation lags.
  - Show "Recovered X GB". If < 10% of the target, explain that macOS keeps some purgeable data until it actually needs the space.
  - Recommend the task only when purgeable ≥ 5 GB or free space < 15%.
- **Root:** `tmutil` thinning needs root.
  - **(updated in fact-check)** The CacheDelete **query** works from an unprivileged client. Evidence: the vendor's per-user `CleanMyMac_5_HealthMonitor` agent on 26.6.2 [CD-LOG], and a user-run CLI spike on 27.0 [CD-SPIKE].
  - Whether an unentitled, non-root client may **purge** all services is still UNVERIFIED. The framework has entitlement-gated calls (`CacheDeleteSetEntitledReservation`; an Apple-private `com.apple.private.CacheDelete` entitlement exists, per https://github.com/hack-different/apple-knowledge/blob/main/_data/entitlements.yaml).
  - Plan: try the purge from the app first. If the amount reclaimed is 0 or an error comes back, retry from the root helper, then fall back to `tmutil`.

### 4.3 Flush DNS Cache

- **Vendor intent:** the local DNS cache can hold stale records. Flush after DNS changes, when some sites won't connect, or when browsing slows randomly. VERIFIED [CMM3-9]. X Smart Scan ran it automatically. VERIFIED [UIDS] 1_5.
- **Command (macOS 14/15/26):** `dscacheutil -flushcache; killall -HUP mDNSResponder` as root. VERIFIED [MOLE-T]; also 02-smart-care.md (Namecheap).
  - `dscacheutil(1)` describes `-flushcache` as flushing the entire Directory Service cache and says it "should only be used in extreme cases". VERIFIED [MAN-26].
  - `mDNSResponder` has been the system unicast DNS resolver and reply cache since 10.6. VERIFIED [MAN-26] `mDNSResponder.8`. That page documents SIGUSR1/2 and SIGINFO but not SIGHUP.
  - **(corrected: no longer just "community practice")** Apple's open-source macOS daemon registers SIGHUP with the comment "(Debugging) Purge the cache…". Its handler logs "SIGHUP: Purge cache", calls `mDNS_PurgeCacheResourceRecord` on every record, then `mDNSCoreRestartQueries`. VERIFIED [MDNS-SRC] (tag 2200.140.11, the macOS 14 era; the newest tags no longer publish the `mDNSMacOSX` folder).
  - Signalling a daemon owned by another user needs root (standard `kill(2)` rule).
  - The vendor's CMM3 Agent shipped `-flushcache`, `/usr/bin/killall` + `-HUP`, and `/usr/sbin/discoveryutil` with `mdnsflushcache`/`udnsflushcaches` (OS X 10.10 only). VERIFIED [CMM3-BIN].
- **Edge cases:**
  - **Active VPN:** WireGuard-style clients treat the SIGHUP as a network change and reconnect. Mole skips the flush when (a) `scutil --nc list` shows a `(Connected)` system VPN, or (b) the default route's interface is `utun*`. It also skips when the VPN state is unknown. VERIFIED [MOLE-T].
  - Bare `utun*` interfaces alone are not proof of a VPN: iCloud Private Relay, Continuity and AirDrop create them too. VERIFIED [MOLE-T] comments.
- **Our implementation:** a helper method `flushDNS()` running both steps. The VPN probe runs in the app (no root); show "Skipped: VPN connected" with a "Run anyway" override. Recommend the task weekly (low risk) and after network-config changes (INFERRED). **Root:** yes.

### 4.4 Run Maintenance Scripts (`periodic`)

- **Vendor intent:** these are the daily/weekly/monthly routines macOS runs: deleting temp files, rotating logs and rebuilding system databases. The vendor called them fast and fine to run every day. VERIFIED [CMM3-9]. 5.x Smart Care suggests them. VERIFIED [KB-SC] via 02.
- **Status:**
  - macOS 14: present. `periodic(8)` is in the 14 man set. VERIFIED [MAN-14].
  - macOS 15+: removed. No man page on 15/26/27 (VERIFIED [MAN-v]). A 15.6.1 host had no `/etc/periodic`, no `/usr/sbin/periodic` and no `com.apple.periodic-daily|weekly|monthly` jobs (VERIFIED [PERIODIC-15]). heise reported the removal for Sequoia (VERIFIED via 02).
  - On Tahoe, running it gives `/bin/sh: /usr/sbin/periodic: No such file or directory`. VERIFIED [MACSAI] issue #129.
  - Mole's comment says "removed in macOS 26+". INFERRED: their comment is imprecise, and runtime detection makes it moot.
- **Command (≤14):** `periodic daily weekly monthly` as root. Mole treats it as stale when `/var/log/daily.out` is missing or older than 7 days. VERIFIED [MOLE-T].
- **Vendor implementation (added in fact-check):** CMM3's root Agent ran `/usr/sbin/periodic <arg>` via `runPeriodicScript:withReply:`. The app passed `daily`, `weekly` and `monthly`, and read `/var/log/%@.out` (`daily.out`, `weekly.out`, `monthly.out`) to judge staleness. VERIFIED [CMM3-BIN].
  - **Security lesson:** the Agent accepted *any* argument. `periodic` runs every script in a directory it is given, so passing a temp folder gave local root code execution (reported April 2018). VERIFIED [CMM3-0DAY].
  - Our helper must take no argument for this call and hard-code `daily weekly monthly`.
- **Our implementation:** show the task only if `FileManager.isExecutableFile(atPath: "/usr/sbin/periodic")`. Run it through the helper with a 10 min timeout and capture stderr into the log. On 15+ it is hidden, not just greyed out; the vendor's X build already filtered unavailable tasks ([UIDS]). **Root:** yes.

### 4.5 Reindex Spotlight

- **Vendor intent:** a complete reindex improves Spotlight speed and accuracy when search slows or misses existing files. It is time- and resource-intensive, and Spotlight is unavailable until it finishes. VERIFIED [CMM3-9].
- **Commands:**
  - Status: `mdutil -s /`, which prints "Indexing enabled." or "Indexing disabled.".
  - Rebuild: `mdutil -E /`. The man page says `-E` erases each local store for the volumes given and rebuilds them if appropriate. `-i on|off` toggles indexing, `-a` covers all volumes and `-X` removes the index directory without disabling. VERIFIED [MAN-26] `mdutil.1`.
  - Root required. VERIFIED [MACSAI] comment: "mdutil -E … silently fail[s] without it".
  - **Vendor (added in fact-check):** CMM3's Agent exposes `startSpotlightReindexWithReply:` and embeds `/usr/bin/mdutil`. The app also embeds `/usr/bin/mdimport` and has a `CMSpotlightIndexingObserver` to follow progress. VERIFIED [CMM3-BIN]. The exact argv is not recoverable from strings. INFERRED: `mdutil -E /`.
- **Smart trigger (from Mole):**
  - Only consider a rebuild if indexing is enabled and the Mac is on AC power. A Mac mini is always on AC.
  - Probe `mdfind "kMDItemFSName == 'Applications'"` twice, one second apart.
  - If both probes take > 3 s or time out, offer the rebuild and say it may take 1–2 hours.
  - VERIFIED [MOLE-T].
- **Our implementation:** never preselect it; recommend it only when the probe is slow or the user reports missing results. Run it via the helper. Afterwards poll `mdutil -s /` and watch `mds_stores` CPU to show "Indexing in progress…" in the Monitor (INFERRED). **Root:** yes.

### 4.6 Repair Disk Permissions

- **Vendor intent:** corrupted permissions after bad shutdowns or installers cause access errors and app malfunctions (question-mark Dock icons, apps won't launch). Run it when those symptoms appear. VERIFIED [CMM3-9]. Still listed in X and 5.x. VERIFIED [UIDS] 8_1, [KB-MT] via 01.
- **Reality:**
  - `diskutil verifyPermissions`/`repairPermissions` were removed in 10.11. VERIFIED [MAN-26] `diskutil.8`.
  - System files are on the sealed, read-only System volume (INFERRED platform fact; see 03-cleanup.md).
  - The only surviving verb is undocumented: `diskutil resetUserPermissions / <uid>` (absent from the 14 and 26 man pages, VERIFIED by search). It resets the ownership/permissions/ACLs of the user's home.
  - MacSai removed the task after it failed on modern macOS; they call `resetUserPermissions` undocumented, deprecated, slow and ACL-incomplete. VERIFIED [MACSAI] code comment and issue #82.
- **Mole's gated approach:**
  - Repair only if the owner of `$HOME` isn't `$USER`, or `$HOME`, `~/Library` or `~/Library/Preferences` isn't writable.
  - Then run `sudo diskutil resetUserPermissions / $(id -u)`.
  - VERIFIED [MOLE-T].
- **Vendor implementation (added in fact-check):** CMM3 shipped `CMResetUserPermissionsTask` (strings `/usr/sbin/diskutil`, `resetUserPermissions`) and `CMRepairPackagesTask`. The latter used `/usr/libexec/repair_packages --repair --standard-pkgs` via the Agent's `repairPermissionsWithReply:` (reply `BOOL, int, NSString*`), for pre-10.11 systems. VERIFIED [CMM3-BIN], [CMM3-0DAY].
  - INFERRED for X/5.x: on 10.11+ the task is the home-folder reset, `diskutil resetUserPermissions / <uid>`. The system half became impossible after SIP and the sealed volume.
  - `repair_packages` has no man page on macOS 11+ (VERIFIED by 404 in [MAN-v]).
- **Apple's documented recipe (added in fact-check):** Apple's support article HT203538 gives `chflags -R nouchg ~` then `diskutil resetUserPermissions / \`id -u\``, and says to run `chflags` first when the reset fails with error -69841. VERIFIED via scripts that cite HT203538: https://github.com/tiiiecherle/osx_install_config/blob/master/07_backup_and_restore_script/permissions/ownerships_and_permissions_restore.sh , https://github.com/eliekh05/guides/blob/main/guides/fix-operation-not-permitted-terminal-macos.html. `support.apple.com` was unreachable.
  - The backing private method `-[DMRepairDisk beginResetUserPermissionsForDisk:forUID:level:]` is still present on macOS 26.6 (ipsw-diffs, §1 item 8).
- **Our implementation (INFERRED):** keep a **"Check home-folder permissions"** task.
  - Detection (no root) uses Mole's rule plus `stat` checks on `~/Library/{Caches,Application Support,Containers}`.
  - If a problem is found, offer `chflags -R nouchg ~` (user) and then `resetUserPermissions` via the helper. Warn that it can take minutes and will reset custom ACLs.
  - If none, show "No permission problems found". That is honest and close to what the vendor's task does on modern macOS (the CMM3 implementation is VERIFIED; for 5.x it is INFERRED).
- **Root:** yes, for the reset.

### 4.7 Speed Up Mail

- **Vendor intent:**
  - Reindex Mail's envelope database to fix message display problems and slow search, without touching email.
  - For big mailboxes it can take up to a couple of hours, so empty Junk and Trash first.
  - Run it when search is slow or misses messages, or when messages won't delete, move or display.
  - VERIFIED [CMM3-9].
  - X shows a "quit these apps" sheet listing Mail before running. VERIFIED [UIDS] 8_2.
- **Files:** `~/Library/Mail/V10/MailData/Envelope Index` (+ `-wal`, `-shm`); **V10 = macOS 13+**. VERIFIED: https://github.com/precursorca/Munki-SelfService-On-Demand/blob/master/pkgsinfo/on_demand/PS-mail_optimizer-1.0.6.plist. Glob `V*` to stay version-proof (as [MOLE-T] does).
  - **(added in fact-check)** V10 is still current from Ventura through Tahoe; one project probes V11 first as a guard against a future bump. VERIFIED: https://github.com/tacogips/apple-gateway/blob/ac0dd8f0f5f100e2f4d4e44a2c18f49d11a0c1cd/design-docs/specs/design-apple-mail.md.
- **Vendor implementation (added in fact-check):** CMM3 opened `~/Library/Mail/<Vn>/MailData/Envelope Index` with FMDB (property `envelopeDB`) and ran **`VACUUM;`**. Nearby strings: `MailData`, `Envelope Index`, `/Library/Mail/%@/`, `envelopeIndexURL`, `VACUUM;`. VERIFIED [CMM3-BIN] (`CMMailMaintenanceScanner`, `CMMailIndexNode`). The vendor's "Speed Up Mail" was therefore a VACUUM in the user process, not a delete-and-rebuild.
- **Two implementations seen in the wild:**
  - (A) **VACUUM.** Quit Mail, then run `sqlite3 "<Envelope Index>" "VACUUM;"`; MDM self-service scripts do this.
    - Mole adds safety: skip when Mail, Safari or Messages is running; skip sidecar files; confirm SQLite via `file -b`; skip DBs > 100 MB; skip when `freelist_count/page_count < 5%`; run `PRAGMA integrity_check` first; 20 s timeout. VERIFIED [MOLE-T].
    - Mole's path protection blocks `~/Library/Mail` anyway, so it never actually compacts Mail. VERIFIED (test text in https://github.com/Tiavina22/hoopix/blob/main/test/features/optimize/data/sqlite_vacuum_task_test.dart).
  - (B) **Full rebuild.** Delete the Envelope Index files with Mail quit, and Mail rebuilds them at next launch (MacSai: "Mail envelope index removed. Mail will rebuild it on next launch"). VERIFIED [MACSAI] MaintenanceModule.swift.
    - **(corrected)** The earlier inference that the vendor's "up to a couple of hours" wording matched (B) is contradicted by the CMM3 binary, which runs `VACUUM;` on the Envelope Index (see "Vendor implementation" above). The long-duration warning is generic caution for very large mailboxes. Our default (A) matches the vendor.
- **Our implementation (INFERRED):**
  - **Default** = (A) without a size cap. VACUUM on a 2 GB index takes seconds to a minute on Apple Silicon SSD. Keep the integrity check and the before/after size readout.
  - **Advanced** = (B) "Rebuild Mail index", with an explicit warning that search and unread counts will be wrong until the rebuild finishes.
  - Both require **Full Disk Access**, since `~/Library/Mail` is TCC-protected.
  - The pre-flight quits Mail via `NSRunningApplication.terminate()` after the user confirms. Wait up to 10 s, then fail rather than force-quit.
- **Root:** no.

### 4.8 Thin Time Machine Snapshots ("Time Machine Snapshot Thinning")

- **Vendor:** present in X and 5.x. VERIFIED [UIDS] 8_1; [KB-MT] via 01.
- **Commands** (`tmutil(8)`, identical on 14/15/26; the 27 page differs only in its footer line; VERIFIED [MAN-v], re-diffed in the fact-check):
  - `tmutil listlocalsnapshots <mount_point>` lists snapshots.
  - `tmutil listlocalsnapshotdates [<mount_point>]` lists dates as `YYYY-MM-DD-HHMMSS`.
  - `tmutil deletelocalsnapshots {<mount_point> | <date>}`: a date deletes that snapshot on all mounted disks; a disk deletes all its local snapshots.
  - `tmutil thinlocalsnapshots <mount_point> [purge_amount] [urgency]` reclaims `purge_amount` bytes at urgency 1–4.
  - The man page says several verbs need root and Full Disk Access.
- **Safety:**
  - Local snapshots are recovery points. Mole removed snapshot deletion because it "deletes user Time Machine recovery points, breaks backup continuity". VERIFIED [MOLE-T].
  - Only Time Machine's own snapshots are in scope. Never touch OS-update snapshots or others listed by `diskutil apfs listSnapshots /` (INFERRED).
  - **(corrected)** The scope rule was too narrow, and the parser needs filtering:
    - `tmutil listlocalsnapshots /` prints a header ("Snapshots for volume group containing disk /:").
    - It lists the **`com.apple.os.update-…`** snapshots (including `com.apple.os.update-MSUPrepareUpdate`) next to Time Machine's.
    - Time Machine snapshots end in **`.local`** or **`.backup`**. The `.backup` one is kept from the last backup; a stuck 140 GB `.backup` snapshot has been reported.
    - VERIFIED [TM-LIST].
    - Match `^com\.apple\.TimeMachine\.(\d{4}-\d{2}-\d{2}-\d{6})\.(local|backup)$`, validate the date, and ignore everything else.
  - Snapshots belong to the Data volume of the volume group (`/System/Volumes/Data`). `/` resolves to the group (VERIFIED: https://github.com/kimono-koans/httm/blob/52e9d9c82d92c6deb47d43f4f0a7aec220cdd054/scripts/equine.bash).
- **Our implementation (INFERRED):**
  - **Default "thin"** = `tmutil thinlocalsnapshots / <bytes> 4` via the helper, where `bytes = 1e12` means "as much as possible". That lets Time Machine pick what to drop.
  - **Advanced** = a per-snapshot list (date, age) with "Delete selected" (`deletelocalsnapshots <date>`). The newest snapshot is unchecked and tagged "most recent".
  - Recommend when snapshots exist **and** (free space < 15% or purgeable ≥ 10 GB).
  - The task is hidden when there are no snapshots. It is still visible but unchecked if Time Machine isn't configured: `tmutil destinationinfo` reports "No destinations configured" (INFERRED).
- **Root:** yes.

### 4.9 Verify Startup Disk

- **Vendor intent:** check the startup disk's file system; if repairs are needed, guide the user to Recovery. Run it periodically, or after slow I/O, corrupted files or trouble finding data. VERIFIED [CMM3-9]. Absent from the X build in [UIDS]; 01-overview notes it as unavailable on APFS per the KB.
- **Command:** `diskutil verifyVolume /`. The man page says the appropriate `fsck` runs, the underlying APFS container is verified first, "live" verify of the boot volume is supported in certain cases, and ownership of the disk is required. Live **repair** is not supported. VERIFIED [MAN-26] `diskutil.8`. MacSai runs it without root (VERIFIED [MACSAI]).
- **Vendor (added in fact-check):** CMM3's app embeds `/usr/sbin/diskutil` with `verifyVolume` and `repairVolume`. VERIFIED [CMM3-BIN]. INFERRED: `repairVolume` was only offered for non-boot volumes. For the boot volume, the vendor's KB text points to Recovery ([CMM3-9]).
- **Risk:** Mole disables it by default. Verifying can trigger kernel-level I/O that cannot be interrupted by SIGKILL when APFS inconsistencies exist, freezing the system. It parses "appears to be OK" and, on errors, tells the user to run `diskutil repairVolume /`. VERIFIED [MOLE-T].
- **Our implementation (INFERRED):** an **advanced, opt-in** "Check disk" tool, never in run-all or Checkup.
  - Confirm with a warning that the Mac may be unresponsive for a few minutes.
  - Run with a 15 min watchdog.
  - On error, show "Use Disk Utility › First Aid from macOS Recovery" with a link to Apple's steps. We cannot repair the live boot volume.
- **Root:** not needed for verify.

### 4.10 Rebuild Launch Services

- **Vendor intent:** Launch Services maps file types to default apps. Corruption causes files opening in the wrong app, wrong icons, and duplicate or outdated "Open With" entries. VERIFIED [CMM3-9]. Not in the X build list [UIDS] or the 5.x list (via 01).
- **Status:**
  - The classic `lsregister -kill -r -domain local -domain system -domain user` **fails on macOS 26**: `-kill` was removed, and `-domain` is gone from the usage, replaced by `-all <comma list>`. It answers that the option was dangerous and no longer useful, and "changes nothing". VERIFIED [LS-KILL] (measured on Darwin 25.0.5) and https://github.com/1tuz/Lead-Aggregator/blob/main/docs/audits/2026-10-04/macos.md.
  - Supported now: `lsregister -gc` (garbage-collect stale records), `lsregister -r -apps local,system,user` (rescan), `lsregister -f <app>` (force-register) and `lsregister -u <app>` (unregister). VERIFIED (same sources).
  - **(corrected)** Three refinements, all VERIFIED [LS-GC] and [LS-KILL]:
    - `-gc` does **not** drop records whose bundle path no longer exists, which are the usual "ghost" Open With entries (griffel, macOS 26). Per-path `-u` does, even when the path is already gone (Scribobulate, 20 of 20).
    - `-u` exits non-zero for a path it holds no registration for, so check the result with `lsregister -dump`, not the exit code. 02-smart-care notes Mole sees `-10814` from `-u` on 15+ for apps already gone.
    - `-domain` is said to be missing from the usage text (kdeldycke). One 2026-09 project still ran `-r -domain local -domain system -domain user` successfully, and another reports that `-kill -r …` still performs the `-r` part while exiting non-zero (jeffmurphy, vraravam). Use `-all`/`-apps` and treat `-domain` as legacy.
  - Path: `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`.
- **Vendor (added in fact-check):** CMM3's `CMLSDBRebuildMaintenanceScanner`/`CMLaunchServicesManager` logs "Rebuild Launch Services DB invoked." and embeds the arguments `-kill`, `-domain`, `local`, `system`, `user` and `-seed`. That means `lsregister -kill -seed -domain local -domain system -domain user` (argument order INFERRED), run as the user and not through the Agent. VERIFIED [CMM3-BIN]. This exact command fails on macOS 26.
- **Risk:** Mole stopped domain-wide rescans because a rebuild made a running Network Extension VPN look newly installed. It only does `-u` + `-gc` for uninstalled apps. VERIFIED [MOLE-SA].
- **Our implementation (INFERRED, corrected):** an advanced tool "Fix 'Open With' duplicates" (user context, no root):
  1. Parse `lsregister -dump` for `path:` lines that point to `.app` bundles.
  2. For each path that no longer exists (and is not on an unmounted `/Volumes/<disk>`), run `lsregister -u <path>`.
  3. Run `lsregister -gc`.
  4. Re-dump to report what was cleared.
  - An optional "Re-register this app" action (`-f`) lives in the Applications module.
  - **Never** use `-kill` or a domain-wide `-r` in automated runs.

### 4.11 Clear font caches (not a vendor task; evaluated per brief)

- **Command:** `atsutil databases -remove` for the current user, or with `sudo` for system-wide. Then `atsutil server -shutdown` and `atsutil server -ping`, then log out. VERIFIED: https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/reset_all_font_caches/reset_all_font_caches.sh , https://github.com/aerobounce/Japantown/blob/master/utils/remove-font-caches.sh. No `atsutil` man page exists in the 14–27 man sets (VERIFIED by 404).
- **Risk:** Mole removed "Font Cache Rebuild" because it could corrupt font rendering with no reliable benefit. VERIFIED [MOLE-SA].
- **Decision (INFERRED):** a troubleshooting-only tool in "Toolbox" ("Reset font caches, then log out"), not a maintenance task.

### 4.12 Other candidate routines (from open-source peers)

| Routine | Command / method | Root | Our decision (INFERRED) | Source |
|---|---|---|---|---|
| Refresh Finder previews | `qlmanage -r cache` (thumbnails) + `qlmanage -r` (generators); optionally remove `~/Library/Caches/com.apple.QuickLook.thumbnailcache` | no | Advanced tool | VERIFIED [MOLE-T]; `qlmanage.1` present in [MAN-26] |
| Repair broken preference plists | `plutil -lint` in batches of 512 over `~/Library/Preferences` (+ `ByHost`), skipping `com.apple.*`, `.GlobalPreferences*`, `loginwindow.plist`; delete only unparseable files | no | Belongs to Cleanup › Broken Preferences (03) | VERIFIED [MOLE-T] maintenance.sh |
| Repair shared file lists | `plutil -lint` on `~/Library/Application Support/com.apple.sharedfilelist/**/*.sfl2\|sfl3` excluding `ApplicationRecentDocuments`; remove corrupt ones | no (FDA may be needed) | Advanced | VERIFIED [MOLE-T] |
| Report broken launch agents | Agents in `~/Library/LaunchAgents` whose absolute `ProgramArguments[0]`/`Program` is missing, unless on an unmounted `/Volumes/<disk>`; bare names (`node`) are not broken; **report, don't delete** | no | In Startup & Background as "Broken" badge | VERIFIED [MOLE-T] |
| Report broken login items | System Events login items whose app can't be resolved by path, Spotlight, filesystem name or `sfltool dumpbtm` | no (dumpbtm needs root) | Broken badge + remove action | VERIFIED [MOLE-T] |
| Network stack refresh | `route -n flush`, `arp -a -d` (root), skipped under VPN | yes | **No.** It disrupts connections. | VERIFIED [MOLE-T] |
| Swap cleanup, dyld cache update, killing system services, Dock DB reset, radio refresh | — | — | **Never.** Mole removed these as crash, data-loss or UX risks. | VERIFIED [MOLE-T], [MOLE-SA] |

### 4.13 Summary matrix

| Task (our label idea) | macOS 14 | 15 | 26 | Command/API | Root | Default selected | Recommend when (INFERRED) |
|---|---|---|---|---|---|---|---|
| Release memory | ✓ | ✓ | ✓ | `purge` (helper) / `memory_pressure -S` (helper, flagged) / mmap pressure | yes / yes / no | only if pressure ≥ warn | pressure ≥ 2 for ≥ 5 min or swap > 2 GB |
| Reclaim purgeable space | ✓ | ✓ | ✓ | CacheDelete (private) → `tmutil thinlocalsnapshots / N 1` | maybe / yes | yes if ≥ 5 GB | purgeable ≥ 5 GB or free < 15% |
| Refresh DNS | ✓ | ✓ | ✓ | `dscacheutil -flushcache` + `killall -HUP mDNSResponder` | yes | yes (no VPN) | weekly; skip under VPN |
| Run maintenance scripts | ✓ | ✗ | ✗ | `periodic daily weekly monthly` | yes | yes (14 only) | `daily.out` > 7 days old |
| Rebuild search index | ✓ | ✓ | ✓ | `mdutil -E /` | yes | no | `mdfind` probe slow twice |
| Check home permissions | ✓ | ✓ | ✓ | detect → `diskutil resetUserPermissions / uid` | yes | only if a problem is found | ownership/writability problem |
| Compact Mail database | ✓ | ✓ | ✓ | quit Mail → `PRAGMA integrity_check` → `VACUUM` | no (FDA) | yes if freelist ≥ 5% | freelist ≥ 5% or index > 1 GB |
| Thin TM snapshots | ✓ | ✓ | ✓ | `tmutil thinlocalsnapshots / 1e12 4` | yes | no | snapshots exist and space is low |
| Check disk (advanced) | ✓ | ✓ | ✓ | `diskutil verifyVolume /` | no | never | manual only |
| Fix Open With (advanced) | ✓ | ✓ | ✓ | `lsregister -dump` → `-u <missing path>` → `-gc` (corrected) | no | never | manual only |
| Reset font caches (Toolbox) | ✓ | ✓ | ✓ | `atsutil databases -remove` … | optional | never | manual only |

### 4.14 Consolidated command reference: vendor then and now, us (added in fact-check)

Full-path commands, privilege level and evidence. "Vendor (CMM3)" comes from MacPaw's own binaries [CMM3-BIN]/[CMM3-0DAY]. X and 5.x internals were not inspectable (no binaries reachable), so the 5.x column is INFERRED unless stated.

| Task (vendor label) | Vendor (CMM3, VERIFIED) | Modern macOS 14/15/26 command or API | Admin? | Notes |
|---|---|---|---|---|
| Free Up RAM | In-process allocation pressure (`mmap`/`vm_deallocate`; `aggressiveCleanMemory`/`legacyCleanMemory`); no `purge`, no Agent verb | (a) `/usr/sbin/purge`; (b) `/usr/bin/memory_pressure -S -l warn -s N`; (c) unprivileged `mmap`+touch+`munmap` or `memory_pressure -l warn` | (a) root (XNU `vfs_purge` EPERM); (b) root (sysctl write); (c) no | The CLI claims "no sudo" [CLI], which points to (c) |
| Free Up Purgeable Space | n/a (5.0.5+ task) | `CacheDeletePurgeSpaceWithInfo` (private, block reply; `…Sync` variant exists) → fallback `/usr/bin/tmutil thinlocalsnapshots / <bytes> <1-4>` | CacheDelete query: no (VERIFIED). Purge: UNVERIFIED. `tmutil`: root + FDA | The 5.x HealthMonitor is a CacheDelete client [CD-LOG] |
| Flush DNS Cache | Agent `flushDNSWithReply:` → `/usr/sbin/dscacheutil -flushcache` + `/usr/bin/killall -HUP mDNSResponder` (+ 10.10 `discoveryutil`) | same two commands | root | SIGHUP = purge cache + restart queries [MDNS-SRC]; skip under VPN [MOLE-T] |
| Run Maintenance Scripts | Agent `runPeriodicScript:` → `/usr/sbin/periodic` with `daily`, `weekly`, `monthly`; staleness from `/var/log/{daily,weekly,monthly}.out` | `/usr/sbin/periodic daily weekly monthly` **only if the binary exists** (13/14) | root | Gone on 15+. The vendor's helper took an arbitrary argument, which was a root exploit [CMM3-0DAY] |
| Reindex Spotlight | Agent `startSpotlightReindexWithReply:` (`/usr/bin/mdutil`); app has `mdimport` + `CMSpotlightIndexingObserver` | `/usr/bin/mdutil -E /`; status `mdutil -s /` | root | Spotlight is unavailable while it rebuilds |
| Repair Disk Permissions | `diskutil resetUserPermissions` (`CMResetUserPermissionsTask`); pre-10.11 `/usr/libexec/repair_packages --repair --standard-pkgs` (Agent) | `chflags -R nouchg ~`; `/usr/sbin/diskutil resetUserPermissions / <uid>` | Apple's recipe runs as the user; Mole and others use sudo. Run via the helper for reliability | System permissions cannot be repaired (SIP/SSV) |
| Speed Up Mail | FMDB `VACUUM;` on `~/Library/Mail/<Vn>/MailData/Envelope Index` (user process) | Quit Mail → `PRAGMA integrity_check` → `VACUUM` (SQLite) | no (FDA) | V10 covers 13–26 |
| Thin TM Snapshots | n/a in CMM3 | `/usr/bin/tmutil thinlocalsnapshots / <bytes> 4`; list with `tmutil listlocalsnapshots /`; delete with `tmutil deletelocalsnapshots <YYYY-MM-DD-HHMMSS>` | root + FDA | Filter out `com.apple.os.update-*`; keep `.local`/`.backup` [TM-LIST] |
| Verify Startup Disk | `/usr/sbin/diskutil verifyVolume` (+ `repairVolume`) | `/usr/sbin/diskutil verifyVolume /` | no | Can stall I/O [MOLE-T]; live repair is unsupported |
| Rebuild Launch Services | `lsregister -kill -seed -domain local -domain system -domain user` (user context) | `lsregister -dump` → `-u <stale path>` → `-gc`; optional `-r -apps local,system,user` | no | `-kill` removed on 26 [LS-KILL] |

---

## 5. Are these tasks effective or safe on Apple Silicon (14/15/26)? Criticism

- **RAM purging.**
  - Apple's documentation of `purge` positions it as a benchmarking aid that empties the disk cache and doesn't touch app memory. VERIFIED [PURGE-SRC].
  - INFERRED consequences:
    - "Freed" RAM is mostly evicted file cache that macOS would have reused anyway.
    - Subsequent launches get slower until the cache refills.
    - On unified-memory Apple Silicon with fast SSD swap and a memory compressor, sustained gains are negligible.
  - The genuinely useful action is quitting the specific heavy apps (§7). Our UX must say so and must not run RAM purges silently in the background.
- **Purgeable space.** macOS reclaims purgeable space on demand. Forcing it early only means re-downloading or rebuilding later. It mainly helps installers and VMs that read raw free space. VERIFIED (community explanation): https://github.com/coreyhaines31/diskforecast/blob/main/site/purgeable-space-mac.html. Keep it threshold-gated.
- **DNS flush.** Harmless apart from the VPN reconnect. Benefit is limited to real DNS problems. VERIFIED [MOLE-T]; `dscacheutil` man advises use "only in extreme cases" [MAN-26].
- **Maintenance scripts.** Pointless on 15+ (gone). On 14, launchd/`newsyslog`/`aslmanager` already do the work. Mole removed its own "maintenance scripts" task because log rotation is automatic via launchd. VERIFIED [MOLE-T] comment.
- **Spotlight reindex.** Heavy (CPU, I/O, battery on laptops) and leaves search empty for hours. Only for broken search. VERIFIED [CMM3-9] [MOLE-T].
- **Permissions repair.** The system part is impossible (sealed system volume); the home reset is undocumented. Only useful for real home-folder ownership problems. VERIFIED [MAN-26] [MACSAI] [MOLE-T].
- **Launch Services rebuild.** The old flag is removed; rescans can disturb Network Extensions. VERIFIED [LS-KILL] [MOLE-SA].
- **Time Machine thinning.** Destroys recovery points. Only when space is genuinely needed. VERIFIED [MOLE-T].
- **Font cache reset.** Can corrupt rendering. VERIFIED [MOLE-SA].
- **Security of the root helper.** Any of these tasks run through a privileged helper. The vendor's 2018–2019 Talos CVEs show how a generic helper becomes a local root exploit. VERIFIED (02-smart-care.md §9; Talos TALOS-2018-0716, TALOS-2019-0759).
- **General.** Some auditing tools classify Mac "cleaner" suites as unnecessary bundleware. VERIFIED (opinion): https://github.com/Chi944/pc-audit/blob/main/audit-macos.sh.
- **Product stance for our app (INFERRED):** be the honest version.
  - Every task shows "What it does / When it helps / Side effects".
  - The recommended set is evidence-based.
  - Advanced tasks never run in bulk.

---

## 6. Login Items & Background Items management

### 6.1 Taxonomy on macOS 13+ (what a "startup item" can be)

| Kind | Where it lives | How it's registered | Disable mechanism available to us |
|---|---|---|---|
| App "Open at Login" (modern) | BTM record type `app` (0x2) | `SMAppService.mainApp.register()` (13+) | None public. Deep-link to Settings. |
| App "Open at Login" (legacy) | BTM, imported from shared file list `com.apple.LSSharedFileList.SessionLoginItems` | `LSSharedFileListInsertItemURL` (deprecated) / System Events | **Remove** via System Events `delete login item "<name>"` (Automation permission). VERIFIED [MOLE-T]; https://github.com/mullvad/mullvadvpn-app/blob/main/dist-assets/uninstall_macos.sh |
| Embedded login-item helper app | `<App>.app/Contents/Library/LoginItems/*.app`, BTM type `login item` (0x4) | `SMAppService.loginItem(identifier:)` / `SMLoginItemSetEnabled` | None public on 13+. Lemon returns an empty list on 13+ because only the app itself can register them. VERIFIED [LEMON-LI] |
| User launch agent | `~/Library/LaunchAgents/*.plist` | file drop (legacy) | `launchctl bootout/disable gui/$UID/<label>`; delete plist (no root) |
| Global launch agent | `/Library/LaunchAgents/*.plist` (root-owned) | installer | `launchctl` in each user's `gui/` domain; delete plist (helper) |
| Launch daemon | `/Library/LaunchDaemons/*.plist` | installer | `launchctl bootout/disable system/<label>` (helper); delete plist (helper) |
| App-embedded agent/daemon | `<App>.app/Contents/Library/LaunchAgents\|LaunchDaemons/*.plist` | `SMAppService.agent/daemon(plistName:)` | `launchctl disable` works on the label (INFERRED); deleting means uninstalling the app |
| Privileged helper tool binaries | `/Library/PrivilegedHelperTools/*` (paired with a daemon plist) | `SMJobBless` (deprecated) | Removed together with its daemon plist (helper) |
| Other BTM types | Spotlight importers (0x40), Quick Look (0x800), cron | — | Read-only display |
| Legacy StartupItems | `/Library/StartupItems/`, `/System/Library/StartupItems/` | obsolete | Read-only display (osquery still scans them) |

VERIFIED:
- Type values from [OSQ]: UserItem 0x1, App 0x2, LoginItem 0x4, Agent 0x8, Daemon 0x10, Developer 0x20, Spotlight 0x40, Quicklook 0x800, Legacy 0x10000, Curated 0x80000.
- Real samples: "legacy daemon (0x10010)", "curated legacy daemon (0x90010)", "developer (0x20)", "app (0x2)". [PP-BTM] [DUMPBTM]
- `SMAppService` replaces `SMLoginItemSetEnabled` for login items and replaces dropping plists into `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`. [A-SMAS]

### 6.2 The BTM store (read path for our inventory)

- **Location:** `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v<N>.btm`, root-owned. Versions VERIFIED:
  - 13.0: v4 (HackTricks via search hit); 13.1: v7 ([DUMPBTM]).
  - 15.2: v13 (https://github.com/zaewc/Lumen/blob/main/docs/research/03-macos-platform.md citing mac_apt).
  - Tahoe 26: **v13 and v16 coexist**; pick the highest number ([PP-BTM]). osquery picks the most recently modified `.btm` ([OSQ]). INFERRED: do both, highest version first and newest mtime as tiebreak.
- **Access:** reading needs **Full Disk Access**, no sudo ([PP-BTM]; [DUMPBTM] notes the FDA requirement).
  - `sfltool dumpbtm` needs root. Run unprivileged, it pops a "sfltool wants to make changes" admin dialog, so Mole calls it only under an existing `sudo -n` session ([MOLE-T]).
  - Its public man page documents only `archive`. VERIFIED [MAN-26] `sfltool.1`.
  - The binary also accepts `dumpbtm|resetbtm|resetlist|list|list-info|clear|csinfo` ([GP-BTM]).
- **Format:**
  - NSKeyedArchiver; `$top` = `{store: UID, version: N}`.
  - The root object is private class **`Storage`**. Fields: `itemsByUserIdentifier` (dict: user UUID → array of `ItemRecord`), `userSettingsByUserIdentifier`, and `mdmPaloadsByIdentifier` (sic, Apple's typo).
  - Sentinel user UUIDs: `FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE` (UID −2 bucket) and `FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000` (system).
  - `ItemRecord` fields: `identifier`, `name`, `developerName`, `bundleIdentifier`, `teamIdentifier`, `container` (parent), `type`, `disposition`, `flags` (0x1 legacy, 0x4 curated), `url`, `executablePath`, `programArguments`, `associatedBundleIdentifiers`, `items` (children of developer groups), `uuid`, `generation`, `modificationDate`, `designatedRequirement`, `sha256`, `bookmark`.
  - Identifiers look like `16.com.docker.vmnetd`. INFERRED: the prefix is the type number (16 = daemon, 8 = agent).
  - Decode with `NSKeyedUnarchiver`, `requiresSecureCoding = false`, mapping class names "Storage"/"ItemRecord" to our own shim classes and decoding key `"store"`. osquery instead `dlopen`s `backgroundtaskmanagementd` so the real `Storage` class resolves.
  - VERIFIED [PP-BTM] [OSQ].
- **Disposition bits:** 0x1 enabled, 0x2 **allowed** (the "Allow in the Background" switch), 0x4 hidden, 0x8 notified.
  - Turning the switch off clears the allowed bit, e.g. `[enabled, disallowed, notified]`.
  - VERIFIED [OSQ] [GP-BTM]; sample `0xb` = enabled+allowed+notified, `0x2` = disabled+allowed ([PP-BTM]).
- **Writing BTM is not possible for us:**
  - No CLI exists for per-item changes ([GP-BTM]).
  - The private framework exports `BTMManager`, `BTMLoginItemController`, `BTMBackgroundItemController`… ([BTM-TBD]), but management requires the private entitlement `com.apple.private.backgroundtaskmanagement.manage`. Apple's own `atrun`, `cron` and Activity Monitor carry it. VERIFIED [ENT-BTM] (+ Activity Monitor entitlements dump https://github.com/rreichel3/macOS-Data-Aggregator/blob/main/data/Activity%20Monitor/entitlements.plist).
  - **Do not edit `.btm` files**: the store is SIP/root-protected and editing is unsupported ([GP-BTM]).
- **MDM:** the `com.apple.servicemanagement` payload (`ServiceManagementManagedLoginItems`, macOS 13+) auto-enables and auto-allows items matched by BundleIdentifier[Prefix], Label[Prefix] or TeamIdentifier. VERIFIED [A-MLI]. INFERRED: show these as "Managed by your organization" with no toggle.

### 6.3 Inventory algorithm for our "Startup & Background" list (INFERRED design)

1. **BTM pass (needs FDA).** Decode the store and keep the current user's UUID bucket (from `dscl . -read /Users/$USER GeneratedUID`, or by matching `ConsoleUserUID`) plus the system buckets.
   - Each record yields name, developer, team ID, type, allowed/enabled flags, URL/executable, parent group and associated bundle IDs.
   - Hide `developer` (0x20) group rows; use them as section headers ("Docker", "Adobe Creative Cloud").
2. **launchd plist pass (no FDA needed for the plist dirs).** Enumerate `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`.
   - Parse `Label`, `Program`/`ProgramArguments[0]`, `RunAtLoad`, `KeepAlive`, `StartInterval`, `Disabled` and `AssociatedBundleIdentifiers`.
   - Skip non-dict or label-less plists, as Lemon does ([LEMON-LI]).
   - Map to an owning app: first by a bundle-ID substring of the file name, then by `.app/` in the program path (Lemon's two-step match, [LEMON-LI]), then by BTM `associatedBundleIdentifiers`.
3. **Runtime state.**
   - Loaded or running: `launchctl print gui/$UID/<label>` (user) and, via the helper, `launchctl print system/<label>`. Parse `state = running` and `pid = N`.
   - Disabled overrides: `launchctl print-disabled gui/$UID` and `… system`. Accept both `"label" => disabled` (new) and `=> true` (old). VERIFIED: https://github.com/gastownhall/gascity/blob/main/cmd/gc/cmd_supervisor_lifecycle.go.
   - Persisted overrides live in `/private/var/db/com.apple.xpc.launchd/disabled.plist` and `disabled.<uid>.plist`. VERIFIED: https://github.com/slpcat/macos_config/blob/master/Disable-Sequoia-Bloatware.sh.
4. **Allowed state without FDA:** `SMAppService.statusForLegacyPlist(at: url)` returns `.enabled`, `.requiresApproval`, `.notRegistered` or `.notFound` for an earlier-OS-style login item plist. VERIFIED [A-SMAS]. INFERRED: `.requiresApproval` = the user disallowed it in Settings.
5. **Legacy login items:** AppleScript via `NSAppleScript` or `osascript`: `tell application "System Events" to get {name, path} of every login item`. Mole's script returns `name<TAB>POSIX path`. VERIFIED [MOLE-T]. Needs the **Automation** permission for System Events.
6. **App-bundle pass:** for each app in `/Applications` and `~/Applications`, list `Contents/Library/{LoginItems,LaunchAgents,LaunchDaemons}` to attribute SMAppService items when BTM is unreadable (no FDA). INFERRED; Lemon did this for pre-13 ([LEMON-LI]).
7. **Merge key:** BTM `url` or `executablePath` ⇄ plist path ⇄ label. Status precedence: Managed (MDM) > Not allowed (BTM allowed bit clear) > Disabled (launchd override) > Loaded/Running > Enabled.
8. **Broken detection (Mole's conservative rules, VERIFIED [MOLE-T]):**
   - Agent: an absolute program path that doesn't exist, and is not on an unmounted `/Volumes/<disk>`. Bare command names don't count.
   - Login item: unresolvable after path, Spotlight (`mdfind kMDItemCFBundleIdentifier`), filesystem-name and BTM checks. If any probe was incomplete, report "unknown", not "broken".

### 6.4 Actions and exact commands (INFERRED, built on VERIFIED primitives)

| Action | User agent (`~/Library/LaunchAgents`) | Global agent (`/Library/LaunchAgents`) | Daemon (`/Library/LaunchDaemons`) | Legacy login item | SMAppService item of another app |
|---|---|---|---|---|---|
| **Disable** (reversible) | `launchctl bootout gui/$UID/<label>` then `launchctl disable gui/$UID/<label>` | same commands in the console user's `gui/<uid>` domain (no root needed for your own gui domain) | helper: `launchctl bootout system/<label>` + `launchctl disable system/<label>` | n/a (remove only) | Not possible. Button "Open Login Items Settings" → `SMAppService.openSystemSettingsLoginItems()` or `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` |
| **Enable** | `launchctl enable gui/$UID/<label>` then `launchctl bootstrap gui/$UID <plist>` | same | helper: `launchctl enable system/<label>` + `launchctl bootstrap system <plist>` | re-add: System Events `make login item at end with properties {path:"…", hidden:false}` | Settings deep-link |
| **Remove** (permanent) | disable as above, then move the plist to Trash (keep a copy in our undo store) | helper: bootout, then move plist to `/Library/…/.Trash`-equivalent quarantine folder | helper: bootout, remove the plist and the matching `/Library/PrivilegedHelperTools/<label>` binary, only when the label/team ID match | `tell application "System Events" to delete login item "<name>"` | "Uninstall app" (Applications module) |
| **Quit now** (no persistence change) | `launchctl kill SIGTERM gui/$UID/<label>` | same | helper: `launchctl kill SIGTERM system/<label>` | quit the app (§7) | quit the app (§7) |

- **VERIFIED primitives:**
  - `launchctl.1` (26) defines `bootstrap|bootout domain-target [paths]|service-target`; `enable|disable service-target`, which persists across boots and works only in the system, user and user-login domains; `print-disabled`; `kill`; `kickstart -k`.
  - It labels `load|unload [-w]` as legacy, with `bootstrap|bootout|enable|disable` recommended. [MAN-26]
  - Lemon's production code uses `launchctl disable gui/$UID/<label>; launchctl unload <plist>` for user items and `launchctl enable system/<label> && launchctl load <plist>` via its daemon for system items. [LEMON-LI] [LEMON-XPC]
  - The System Events login-item delete is used by Mullvad's uninstaller and Mole's audit.
- **BTM interplay (corrected: the first point is now VERIFIED by four independent field reports [BTM-LIVE]; the rest stays INFERRED):**
  - **Switch off → unload, plist kept, launchd override untouched.** On macOS 26.6, turning a user agent off under Login Items › Allow in the Background unloaded it and left its file in `~/Library/LaunchAgents`. `launchctl print-disabled gui/<uid>` kept reporting `enabled`, while `sfltool dumpbtm` showed the item as disallowed. VERIFIED [BTM-LIVE] (J-Park).
  - **Disallowed is durable across boots.** With disposition `[enabled, disallowed, notified]`, BTM refuses to load a daemon at every boot, even though `launchctl print-disabled system` says `enabled`, "a *different* database". A manual `launchctl bootstrap` restores the job **for the current boot only**. Only the Settings UI clears the flag, since the store is SIP-protected. VERIFIED [BTM-LIVE] (nix-darwin PANIC.md). tkmx-client reports the same for a LaunchAgent held at `[enabled, disallowed]`.
  - **Diagnostics without root:** `log show --last 1d --predicate 'subsystem == "com.apple.backgroundtaskmanagement"'` shows `registerLaunchItem: found existing item … disposition=[…]` lines. VERIFIED [BTM-LIVE] (nix-darwin). Use this as a fallback when the `.btm` store is unreadable (no FDA).
  - **Writing BTM per item requires SIP off.** The MacPerms tool edits `.btm` archives directly (switch on = enabled+allowed, switch off = clear only allowed, cascading to child records). It labels these edits as "requiring SIP disabled", and on enable it also clears stale launchd overrides. VERIFIED [BTM-LIVE] (MacPerms). This confirms there is no supported path for us.
  - The reverse case (a launchd disable override while BTM shows "allowed") follows from the separation: Settings will still show the item as allowed. INFERRED, consistent with the above.
  - Our UI must show both facts ("Allowed in Settings ✓ · Disabled by Kempt ✓") to avoid confusing the user. A self-healing app may also re-register an agent the user switched off, flipping the switch back on (J-Park observed this with its own app). Treat "plist present + not loaded + BTM disallowed" as "Switched off in Settings", never as "broken".
  - Some daemons with a `KeepAlive` parent app will be re-registered by their app. Warn about that and offer "Disable & quit <App>".
- **How the vendor handled other apps' SMLoginItems (added in fact-check):**
  - Before macOS 13, CMM3's root Agent had `removeSMLoginItem:withReply:` and the string `_com.apple.SMLoginItemBookmarks`. That is launchd's per-user login-item override store, which it edited as root. VERIFIED [CMM3-BIN].
  - On macOS 13+ that store moved into BTM behind the private `…backgroundtaskmanagement.manage` entitlement [ENT-BTM]. INFERRED: the direct-download 5.x cannot toggle `SMAppService` main-app and login-item helpers of other apps. It can only `launchctl`-disable plist-backed agents and daemons, or remove them. Its "Background Items" list most likely means those plist-backed jobs. The **gap stays open** until a 5.x binary or screenshot shows the action on an `SMAppService` main-app or login-item helper record.
- **Undo store (INFERRED):** for every change, save the label, domain, original plist bytes (for removals), previous disposition and a timestamp in our App Group container. "Restore" re-installs the plist with its original owner and mode (`root:wheel 0644` for `/Library`) and re-enables it. The vendor's 5.x semantics (disable reversible, remove permanent) are matched, plus a safety net.

### 6.5 Safety rules (INFERRED, several directly from VERIFIED peer practice)

- Never list or touch anything under `/System/Library/LaunchAgents|LaunchDaemons`, or any `com.apple.*` label or Apple-team-ID item. Display them read-only behind a "Show Apple items" toggle, if at all.
- Validate reverse-DNS labels and use **boundary-aware** bundle-ID matching (`com.example` must not match `com.example123`) before tying a plist to an app. VERIFIED as Mole practice [MOLE-SA].
- Never delete a broken agent automatically. Report it and require an explicit Remove; the plist may be the only copy of the user's config. VERIFIED rationale [MOLE-T].
- Treat **security and IT software** (EDR, MDM agents, VPN daemons, backup agents) as "caution" items:
  - detect by curated team-ID/label lists plus the BTM `curated` flag;
  - require an extra confirmation;
  - default to *Disable* rather than *Remove*.
- MDM-managed items ([A-MLI]) cannot be changed.
- Never disable our own Menu/Health/Helper items from this list; show them with a lock and an explanation.
- All root operations go through the helper's typed API.
  - The helper re-resolves paths with no symlink following, checks that the path is inside the allowed roots (`/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`), and checks that the plist's `Label` equals the requested label.
  - VERIFIED need: CVE-2018-4042 `removeLaunchdAgentAtPath` (02-smart-care.md).

### 6.6 Vendor-specific observations to match

- **X list:** rows read "<App>.app Login Item" with a green "Enabled" status, sorted by name, with search, "Perform" and category checkboxes. VERIFIED [UIDS] 7_2.
- **5.x:** Login Items vs Background Items are separate. Enable/disable is reversible; removal is permanent. VERIFIED [KB-OPT] via 01.
- **"Broken Login Items"** is a Cleanup › System Junk group (not in the App Store edition). VERIFIED via 01/03. Our list should cross-link: the "Broken" badge here and the cleanup group there should be the same data.
- **Background Items Added:** when *our* app registers its Menu, Health and Helper items, macOS posts the "Background Items Added" notification, and the user can block them under General › Login Items & Extensions › Allow in the Background. VERIFIED via 01.
  - Detect it with `SMAppService.status == .requiresApproval` and show a fix-it banner with `openSystemSettingsLoginItems()`. [A-SMAS]
  - Daemons don't bootstrap until an admin approves; `register()` returns `kSMErrorLaunchDeniedByUser` if not approved. VERIFIED [A-SMAS] `register()`.

---

## 7. Heavy consumers, hung applications, quitting apps

### 7.1 Vendor behavior

- X Optimization had **Heavy Consumers** and **Hung Applications** categories next to login items and agents. Hung Applications greys out when none exist. VERIFIED [UIDS] 7_2. The vendor homepage copy (archived in a scraped repo) pitched quitting heavy consumers and hung apps to free memory. VERIFIED (paraphrased): https://github.com/Flopsi69/crs/blob/master/cleanMyMac/new_homepage/index.js.
- X Menu (4.11.0+) CPU panel: top-consuming apps, uptime, spikes. Memory panel: available memory, which apps use it, quick free-up. VERIFIED [DM4].
- 5.x Health Monitor notifies about high memory usage and **unresponsive apps** even when the main app is closed. VERIFIED [KB-PROC] via 01/02.
- INFERRED: in 5.x the hung and heavy lists live in the Menu and in notifications rather than in Performance. 01-overview recommends keeping them in both places for our app.
- **Vendor alert criteria (added in fact-check; CMM3 era, VERIFIED [CMM3-BIN] `Health.strings` + Menu binary):**
  - **High memory:**
    - The notification is titled "Heavy memory usage". It fires when the Mac is "running out of both physical and virtual memory" (the alert's gauge label is "RAM + Swap", state "Almost full").
    - The monitor (`CMRAMUsageMonitor`, `CMHeavyRAMUsageIssue`) tracks `ramOccupancyFraction`, `swapOccupancyFraction` and `usedSwapSize`. It also tracks pressure via `kern.memorystatus_vm_pressure_level` and a dispatch memory-pressure source.
    - It has a `thresholdTimeInterval` (the condition must persist) and a `timeIntervalToAllowAlertAfter` (cool-down).
    - It suppresses itself while the app's own cleaner runs (`pidThatCleansMemory`).
    - **Numeric thresholds are not in the strings.** Gap 9 stays open for exact numbers.
  - **Unresponsive apps:** `CMHungAppsMonitor` uses `CGSEventIsAppUnresponsive` plus `CGSRegisterNotifyProc`. Alert actions are "Quit", "Force Quit All" and "Ignore ▾" (For Now / Forever). There are per-app and per-session ignore lists (`ignoreHungApps:`, `ignoreHungAppSessions:`). A debugger check (`isBeingDebug`) avoids flagging apps paused in a debugger. No timeout value is visible.
  - INFERRED: 5.x Health Monitor keeps this design (01/08 report the same alert set).

### 7.2 Metrics: exact APIs

- **System memory (VERIFIED [STATS-RAM]):**
  - `host_statistics64(mach_host_self(), HOST_VM_INFO64, …)` gives `active`, `inactive`, `speculative`, `wire_count`, `compressor_page_count`, `purgeable_count` and `external_page_count`, each × `vm_page_size`.
  - Used = active + inactive + speculative + wired + compressed − purgeable − external. Free = total − used. Cache = purgeable + external. **(corrected)** Stats takes total from `host_info(HOST_BASIC_INFO).max_mem`, not `hw.memsize`. Both give physical RAM; either is fine.
  - Pressure: `sysctlbyname("kern.memorystatus_vm_pressure_level")`, mapped as **2 → warning, 4 → critical**, anything else normal. **(added in fact-check)** Confirmed in XNU: the handler returns `NOTE_MEMORYSTATUS_PRESSURE_NORMAL/WARN/CRITICAL` = 0x1/0x2/0x4. The internal "urgent" level maps to WARN. On macOS the read needs no privilege; the `PRIV_VM_PRESSURE` check applies only to non-macOS targets. VERIFIED [XNU].
  - Swap: `sysctlbyname("vm.swapusage")` → `xsw_usage`.
- **Event-driven pressure (INFERRED):** `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue:)` in the Health agent triggers "high memory" alerts. Debounce for 2–5 min to avoid noise.
- **Per-process CPU:**
  - Stats runs `/bin/ps -Aceo pid,pcpu,comm -r` and takes the top N. VERIFIED [STATS-CPU].
  - Precise alternative (INFERRED): `proc_listallpids` + `proc_pid_rusage(pid, RUSAGE_INFO_V4, …)`. Sample `ri_user_time + ri_system_time` twice, Δ / Δwall × 100. Stats uses `proc_pid_rusage` for disk I/O, VERIFIED (same repo, `Modules/Disk/readers.swift`).
  - Other users' processes (root daemons) need root for `proc_pid_rusage`. Use `ps`/`top` output or the helper for those (INFERRED).
- **Per-process memory:**
  - Stats runs `/usr/bin/top -l 1 -o mem -stats pid,command,mem`. VERIFIED [STATS-RAM].
  - INFERRED: Activity Monitor's "Memory" column corresponds to `ri_phys_footprint` from `proc_pid_rusage`; prefer it.
- **Energy:** `top -o power -l 2 -n N -stats pid,command,power`. Two samples are needed because the first sample has no rate. VERIFIED [STATS-BAT].
- **Grouping by app (INFERRED, per Stats):** aggregate helper processes into the "responsible" app (Stats calls a `getResponsiblePid` helper and then `NSRunningApplication(processIdentifier:)` for the name and icon, VERIFIED [STATS-RAM]). Chrome or Electron renderers then roll up into one row. **(added in fact-check)** `getResponsiblePid` resolves the private libSystem symbol `responsibility_get_pid_responsible_for_pid` via `dlsym(RTLD_DEFAULT, …)` and falls back to the child PID when it is missing or returns -1. VERIFIED [STATS-RAM].

### 7.3 Hung (not responding) detection

- **WindowServer private API (VERIFIED, two independent open-source uses):**
  - Poll: `CGSEventIsAppUnresponsive(CGSMainConnectionID(), &psn)`, where `psn` comes from the deprecated `GetProcessForPID(pid, &psn)`. [HS]
  - Push: `CGSRegisterNotifyProc(callback, kCGSNotificationAppUnresponsive, NULL)`. The callback gets `CGSProcessNotificationData` with the `pid`. [FQUA]
  - The headers also declare `CGSEventSetAppIsUnresponsiveNotificationTimeout(cid, seconds)`. VERIFIED: https://github.com/rentzsch/ForceQuitUnresponsiveApps/blob/master/CGSInternal/CGSMisc.h.
  - Both CGS calls are undocumented SkyLight/CoreGraphics symbols. Resolve them via `dlsym`, and disable the feature gracefully if missing (INFERRED).
- **Public fallback (INFERRED):** use AX with Accessibility permission. Set `AXUIElementSetMessagingTimeout(appElement, 2.0)` and read `kAXFocusedWindowAttribute`; `kAXErrorCannotComplete` repeated for > 5 s means hung.
- **Our rule (INFERRED):** "Not responding" = unresponsive for ≥ 5 s, re-checked every 2 s. Show it in the Activity tab and the menu-bar Monitor, and notify once per incident: "<App> is not responding. Force Quit?".

### 7.4 Quitting

- **Apps:**
  - `NSRunningApplication.terminate()` sends a normal quit. It may return before exit, so observe `isTerminated`.
  - If the app is still alive after 10 s, offer `forceTerminate()`.
  - Both return `false` from sandboxed apps. VERIFIED [A-NSRA].
  - For hung apps, go straight to Force Quit (with confirmation). Unsaved changes will be lost; say so.
- **Non-app processes** (heavy daemons or agents owned by the user): `kill(pid, SIGTERM)`, then `SIGKILL` after 5 s.
- **Root processes:** not offered by default. In "Advanced", only via the helper and only for processes whose executable is outside `/System`, `/usr` and `/sbin` and whose team ID is not Apple (INFERRED).
- **Protect list (INFERRED):** `kernel_task`, `launchd`, `WindowServer`, `loginwindow`, `Finder` (offer Relaunch instead), `Dock`, `SystemUIServer`, `mds*`, `backupd`, `softwareupdated` and our own processes.

### 7.5 "Heavy consumer" thresholds & UX (INFERRED)

- **CPU heavy:** average > 50% of one core over the last 30 s, or > 20% sustained for 10 min (background drain).
- **Memory heavy:** footprint > 1.5 GB, or > 10% of RAM. On an 8 GB mini, also flag the top memory user whenever pressure ≥ warn.
- **Energy heavy (laptops mostly; still useful on a mini for thermals):** `top` power > 20 sustained.
- **UX:**
  - Activity tab table: App · CPU % · Memory · Energy · Uptime · status (Responding / Not responding).
  - Row actions: Quit · Force Quit · Reveal in Finder · "Why is this heavy?" (Smart-Insights-style on-device explanation, optional).

---

## 8. Permissions, privilege model, required entitlements

| Need | Why | How (INFERRED unless cited) |
|---|---|---|
| **Not sandboxed** (Developer ID + notarized) | `terminate()` of other apps, `launchctl`, reading other apps' data | Sandboxed apps can't terminate other apps. VERIFIED [A-NSRA]. The vendor's App Store edition loses tasks and login-item control. VERIFIED [KB-MISS] via 01 |
| **Full Disk Access** | BTM store, `~/Library/Mail`, Safari/Messages DBs, some `tmutil` verbs | Onboarding flow from 01-overview.md §9; `tmutil` FDA note VERIFIED [MAN-26] |
| **Automation → System Events** | Legacy login items list/remove | `NSAppleEventsUsageDescription`; first use triggers the consent prompt |
| **Accessibility** (optional) | AX-based hung detection fallback | Only if the CGS path is unavailable |
| **Admin / root** | `purge`, DNS flush, `periodic`, `mdutil -E`, `tmutil thin/delete`, `resetUserPermissions`, system-domain `launchctl`, `/Library` plist removal | `SMAppService.daemon(plistName:)` helper with XPC. Register on first root task; handle `.requiresApproval`. VERIFIED [A-SMAS]. The vendor installs its "Agent" on first need (VERIFIED via 01). Avoid stacked password prompts: one approval, then XPC (MacSai fixed "stacked password prompts", VERIFIED [MACSAI] #82) |
| **Background item** | Health agent for pressure/hung alerts | `SMAppService.agent`; user can disallow it, so detect and show a banner |

**Helper XPC protocol (INFERRED, task-specific only):**

```swift
@objc protocol PerfHelperProtocol {
    func purgeDiskCache(reply: @escaping (Int32) -> Void)                        // /usr/sbin/purge
    func simulateMemoryPressure(seconds: Int, reply: @escaping (Int32) -> Void)  // (added) memory_pressure -S -l warn -s 1...10, feature-flagged
    func purgePurgeableSpace(bytes: UInt64, reply: @escaping (Int64, String?) -> Void) // (added) CacheDelete retry as root, if the in-app call reclaims 0
    func flushDNS(reply: @escaping (Int32) -> Void)                              // dscacheutil + HUP mDNSResponder
    func runPeriodic(reply: @escaping (Int32, String) -> Void)                   // only if /usr/sbin/periodic exists; argv hard-coded "daily weekly monthly" (the vendor's arg-taking verb was a root exploit, [CMM3-0DAY])
    func rebuildSpotlight(volume: String, reply: @escaping (Int32) -> Void)      // volume must be "/" or a mounted local volume
    func thinLocalSnapshots(bytes: UInt64, urgency: Int, reply: @escaping (Int32, String) -> Void) // urgency 1...4
    func deleteLocalSnapshot(date: String, reply: @escaping (Int32) -> Void)     // ^\d{4}-\d{2}-\d{2}-\d{6}$
    func resetHomePermissions(uid: uid_t, reply: @escaping (Int32) -> Void)      // uid must equal caller's audit-token uid
    func launchdSystem(action: String, label: String, reply: @escaping (Int32, String) -> Void) // bootout|disable|enable|bootstrap
    func removeLaunchItem(label: String, plistPath: String, reply: @escaping (Int32) -> Void) // allow-listed roots + Label match
}
```

- **Caller validation:** check the audit token's code-signing requirement against our team ID. Use `NSXPCConnection.setCodeSigningRequirement` on macOS 13+ (INFERRED API choice).
- **Execution:** run each command with an absolute path, a fixed argv (no shell) and a timeout.
- **Logging:** log to `os_log` and to our "View Log" file.

---

## 9. Implementation spec (Swift, INFERRED)

### 9.1 Model

```swift
enum TaskRisk { case safe, noticeable, advanced }        // advanced = never in bulk runs
enum TaskAvailability { case available, unavailable(reason: String), hidden }

protocol MaintenanceRoutine: Identifiable, Sendable {
    var id: String { get }                     // "memory", "purgeable", "dns", "periodic", "spotlight", "homePerms", "mail", "tmThin", "diskVerify", "lsGC"
    var risk: TaskRisk { get }
    var needsRoot: Bool { get }
    var needsFullDiskAccess: Bool { get }
    var appsToQuit: [String] { get }           // bundle IDs, e.g. ["com.apple.mail"]
    func availability(os: OperatingSystemVersion) async -> TaskAvailability
    func assess() async -> Assessment          // recommended? + evidence ("Memory pressure: warning for 12 min")
    func run(progress: @Sendable (String) -> Void) async throws -> RoutineResult  // cancellable
}

struct Assessment { let recommended: Bool; let evidence: String; let estimatedDuration: Duration? }
struct RoutineResult { let status: Status; let detail: String; let measuredGain: Measurement<UnitInformationStorage>? }
enum Status { case done, skipped(String), failed(String), partial(String) }
```

### 9.2 Run pipeline (mirrors vendor UX, our wording)

1. **Select.** Recommended routines are preselected. Advanced routines can't be multi-selected with others.
2. **Pre-flight.**
   - Collect `appsToQuit` and show the sheet "Quit these apps first?" with per-app **Quit**, **Quit All** and **Skip task**. The vendor's sheet: Quit / Ignore / Quit All, VERIFIED [UIDS] 8_2.
   - Ensure FDA and helper approval. Missing either marks the affected routines "Needs permission" with a fix button.
3. **Execute sequentially.** Row states: queued `•••` → running (spinner + live detail) → done ✓ / skipped / failed. The primary button becomes **Stop**.
   - Cancellation stops after the current command. `mdutil -E` and `periodic` aren't interruptible mid-way, so tell the user.
   - Order (INFERRED): Mail compaction (after quitting Mail) → DNS → periodic → purgeable → TM thin → memory last, so the RAM "after" number isn't eaten by the other tasks → Spotlight rebuild (long tail, runs in the background).
4. **Summary.** "N routines completed", per-routine detail and measured gains (memory available, disk recovered), plus a **View Log** link that shows a warning glyph when anything failed or was skipped. Store `lastRun` per routine and show it in the detail pane ("Last run: today 12:58" pattern, VERIFIED [UIDS] 8_1).
5. **Checkup integration.** The Performance tile = count of `assess().recommended`. Running from Checkup executes only `.safe` routines.

### 9.3 Snippets for the non-obvious parts

**Memory pressure + available memory** (pattern from [STATS-RAM]):

```swift
func memorySnapshot() -> (pressure: Int, availableBytes: UInt64, swapUsed: UInt64)? {
    var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
    guard kr == KERN_SUCCESS else { return nil }
    let page = UInt64(vm_page_size)
    let avail = (UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)) * page
    var level: Int32 = 0; var sz = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &sz, nil, 0)   // 1 normal, 2 warn, 4 critical
    var swap = xsw_usage(); var ssz = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &ssz, nil, 0)
    return (Int(level), avail, swap.xsu_used)
}
```

**Purgeable estimate** ([A-VOL]; formula INFERRED):

```swift
let v = try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
let purgeable = max(0, (v.volumeAvailableCapacityForImportantUsage ?? 0) - Int64(v.volumeAvailableCapacity ?? 0))
```

**CacheDelete purge** (private, feature-flagged; keys VERIFIED [CD-PMD3] [CD-SPIKE]):

```swift
typealias PurgeFn = @convention(c) (CFDictionary, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
if let h = dlopen("/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete", RTLD_LAZY),
   let sym = dlsym(h, "CacheDeletePurgeSpaceWithInfo") {
    let purge = unsafeBitCast(sym, to: PurgeFn.self)
    let info: [String: Any] = ["CACHE_DELETE_VOLUME": "/", "CACHE_DELETE_AMOUNT": NSNumber(value: purgeable), "CACHE_DELETE_URGENCY_LIMIT": 3]
    purge(info as CFDictionary) { reply in /* read reply["CACHE_DELETE_AMOUNT"]; enforce our own timeout */ }
}
```

(The reply-block signature is INFERRED from [CD-SPIKE]'s note that the purge "takes a reply block". Validate it on 14/15/26 before enabling.)

**Hung detection** (private CGS; pattern VERIFIED [HS]):

```swift
typealias MainConnFn = @convention(c) () -> Int32
typealias UnrespFn  = @convention(c) (Int32, UnsafePointer<ProcessSerialNumber>) -> Bool
// dlsym(RTLD_DEFAULT, "CGSMainConnectionID") / "CGSEventIsAppUnresponsive"; GetProcessForPID(pid, &psn) (deprecated, still present)
```

**BTM decode** (shim approach VERIFIED [PP-BTM]):

```swift
final class BTMStorageShim: NSObject, NSCoding { var items: [String: [BTMItemShim]] = [:]
    required init?(coder: NSCoder) { items = coder.decodeObject(forKey: "itemsByUserIdentifier") as? [String: [BTMItemShim]] ?? [:] }
    func encode(with coder: NSCoder) {} }
// BTMItemShim decodes: identifier, name, developerName, bundleIdentifier, teamIdentifier, container, type, disposition, flags, url, executablePath, associatedBundleIdentifiers
let u = try NSKeyedUnarchiver(forReadingFrom: data); u.requiresSecureCoding = false
u.setClass(BTMStorageShim.self, forClassName: "Storage"); u.setClass(BTMItemShim.self, forClassName: "ItemRecord")
let store = u.decodeObject(forKey: "store") as? BTMStorageShim
```

---

## 10. Edge cases & test matrix (INFERRED)

| Case | Expected behavior |
|---|---|
| macOS 15/26: `/usr/sbin/periodic` missing | Routine hidden. The Checkup tile never counts it. |
| macOS 26: `lsregister -kill` | Never called. The Open-With fix uses `-gc` only. |
| VPN connected (WireGuard, IKEv2) | DNS refresh skipped with a reason; "Run anyway" option. |
| Mail running | Pre-flight sheet. If the user picks Skip, the Mail task is reported "skipped". |
| No FDA | Mail compaction and BTM inventory show "Needs Full Disk Access"; inventory falls back to plist + System Events + app-bundle passes. |
| Helper not approved (`.requiresApproval`) | Root routines show "Needs approval" with a deep link to Login Items settings. |
| Time Machine not configured / no snapshots | TM routine hidden; purgeable routine still runs CacheDelete. |
| Very low disk (< 2 GB free) | Allowed: purgeable and TM thinning, recommended first. Avoided: Mail VACUUM, which needs temporary space roughly the DB size. |
| Spotlight disabled (`mdutil -s` "Indexing disabled") | Rebuild routine unavailable, with an explanation. |
| MDM-managed login item | Lock badge, no actions. |
| Agent program on an unplugged external drive | Not "broken". |
| Multiple users logged in | `gui/<uid>` actions only for the console user. Daemons affect everyone, so warn. |
| 8 GB vs 16+ GB Mac mini | Memory thresholds scale with RAM: percentage-based plus a pressure-level gate. |
| Repeat RAM release within 10 s | Rate-limited (Lemon uses a 10 s guard, VERIFIED [LEMON-RAM]). |
| Tool missing or renamed by a future macOS | `availability()` checks executables, so the routine shows "Not available on this macOS" instead of raw shell errors (the MacSai #129 lesson). |
| (added) `tmutil listlocalsnapshots /` shows only `com.apple.os.update-*` | No Time Machine snapshots: TM routine hidden. Never count or delete update snapshots [TM-LIST]. |
| (added) Agent plist present, not loaded, BTM disposition disallowed | Status "Switched off in Settings", with a deep link. Not "Broken", and not re-enabled by `launchctl` (it would only last one boot) [BTM-LIVE]. |
| (added) `lsregister -u` exits non-zero | Don't report failure from the exit code. Re-read `lsregister -dump` to decide [LS-KILL]. |
| (added) Heavy-memory alert while our own RAM release runs | Suppressed (vendor `pidThatCleansMemory` pattern, [CMM3-BIN]). |
| (added) CacheDelete purge from the app returns 0 or `CACHE_DELETE_ERROR` | Retry once via the helper, then fall back to `tmutil thinlocalsnapshots`. Show the raw error in View Log. |

---

## 11. Naming for our app (INFERRED)

- Don't reuse "Free Up RAM", "Speed Up Mail", "Heavy Consumers", "Hung Applications", "Maintenance Scripts" as-is, and don't reuse their descriptions.
- Suggested labels: **Release memory**, **Reclaim purgeable space**, **Refresh DNS**, **Run system housekeeping** (macOS 14 only), **Rebuild search index**, **Check home-folder permissions**, **Compact Mail database** / **Rebuild Mail index**, **Thin Time Machine snapshots**, **Check startup disk**, **Fix "Open With" menu**.
- Tabs: **Routines**, **Startup & Background**, **Activity**. Statuses: **Allowed**, **Disabled**, **Not allowed in Settings**, **Managed**, **Broken**. Activity statuses: **Busy CPU**, **High memory**, **Not responding**.

---

## 12. Gaps / open questions

Status after the fact-check is in **bold brackets**.

1. **5.x screens:** the exact layout and labels of 5.x Performance (weekly bundle card, task detail copy, Login vs Background Items columns, action buttons) have not been seen directly. macpaw.com was unreachable, and the screenshots are X-era. **[Still open. macpaw.com and web search were unavailable again. The X Optimization screenshot was re-read: no per-row action picker is visible, only "Perform".]**
2. **Free Up RAM mechanism in the vendor's GUI and CLI:** `purge`, allocation pressure or `memory_pressure`? Unknown. The CLI claims no sudo. **[Largely answered: CMM3's Menu uses in-process allocation pressure (`mmap`, `aggressiveCleanMemory`/`legacyCleanMemory`), with no `purge` anywhere and no root verb (VERIFIED [CMM3-BIN]). X/5/CLI are INFERRED to be the same family, consistent with "no sudo".]**
3. **Purgeable mechanism in the vendor's app:** CacheDelete vs `tmutil` vs disk-fill. Unknown. **[Partly answered: the 5.x HealthMonitor is a CacheDelete client on 26.6.2 (VERIFIED [CD-LOG]). The purge call itself is INFERRED to be CacheDelete.]**
4. **Disabling other apps' SMAppService login items:** how (or whether) the vendor does it on 13+, given the private entitlement. The X screenshot shows such items with "Enabled" status, but not the action applied to them. **[Pre-13 answered: root edit of `_com.apple.SMLoginItemBookmarks` (VERIFIED [CMM3-BIN]). 13+ still open; INFERRED not possible without SIP off (MacPerms) or the private entitlement.]**
5. **Repair Disk Permissions today:** what exactly the vendor's task does on 14/15/26. **[Answered for CMM3: `diskutil resetUserPermissions` (+ legacy `repair_packages`). INFERRED unchanged in 5.x.]**
6. **Run Maintenance Scripts on 5.x and macOS 14:** whether the task is shown (01-overview says ≤13; the man pages show `periodic` still on 14). **[Still open. Re-checked: `periodic.8` is present for 13 and 14 and absent for 15+. Our rule stays "show when `/usr/sbin/periodic` exists".]**
7. **Root needs for `memory_pressure -S` and for CacheDelete** from a non-root app: test on hardware. **[`-S` needs root (VERIFIED from XNU and the tool's source). CacheDelete query works unprivileged (VERIFIED). CacheDelete purge without root is still UNVERIFIED.]**
8. **BTM `disposition` vs launchd disable overrides:** exact interplay on 14/15/26. Test matrix needed. **[Answered for 26.x: separate databases; switch-off unloads and keeps the plist; disallowed blocks every boot; `print-disabled` does not reflect it (VERIFIED [BTM-LIVE]). 14/15 assumed the same; confirm on hardware.]**
9. **Health Monitor thresholds:** the vendor's thresholds for "high memory" and "unresponsive" alerts are not published. **[Criteria answered for CMM3 (RAM + swap both nearly full, persisting for a threshold interval; CGS unresponsive state). Numbers still open.]**

---

## 13. Sources

**MacPaw primary (fetched this session):**
- CleanMyMac 3 Help, Maintenance topic (MacPaw-authored, GitHub mirror): https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-9.html
- DevMate release notes: CleanMyMac 5.0–5.2.5 https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html ; CleanMyMac X 4.10–4.12.2 https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- CleanMyMac CLI: https://github.com/MacPaw/cleanmymac-cli , https://github.com/MacPaw/cleanmymac-cli/wiki/Commands , https://github.com/MacPaw/cleanmymac-cli/wiki/FAQ
- Homebrew cask: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb

**MacPaw KB (via sibling reports 01/02, search excerpts):** https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks , …/optimization , …/smart-care , …/missing-features , …/cleanmymac-processes , …/background-items , …/allow-background-items ; https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance , …/optimization

**Vendor UI screenshots (third-party dataset):** https://github.com/kafkaGen/dora-ai/tree/main/datasets/routes/7 , …/routes/8 , …/routes/1 ; descriptions https://github.com/kafkaGen/dora-ai/blob/main/help/neo4j/import/graph_export.json

**Apple:**
- Developer docs (JSON-rendered): https://developer.apple.com/documentation/servicemanagement/smappservice (and register(), statusForLegacyPlist(at:), Status, openSystemSettingsLoginItems()) ; https://developer.apple.com/documentation/appkit/nsrunningapplication/terminate() ; https://developer.apple.com/documentation/appkit/nsrunningapplication/forceterminate() ; https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacityforimportantusagekey ; https://developer.apple.com/documentation/devicemanagement/servicemanagementmanagedloginitems
- Open source: https://github.com/apple-oss-distributions/system_cmds/blob/main/purge/purge.c , https://github.com/apple-oss-distributions/system_cmds/blob/main/purge/purge.8 , https://github.com/apple-oss-distributions/system_cmds/blob/main/atrun/atrun.entitlements
- Man pages (rendered, macOS 14/15/26/27): https://github.com/vitorgalvao/macos-man-pages (tmutil.8, mdutil.1, diskutil.8, launchctl.1, sfltool.1, dscacheutil.1, mDNSResponder.8, memory_pressure.1, purge.8, qlmanage.1, periodic.8 [14 only])

**Open-source implementations and analyses:**
- Mole: https://github.com/tw93/Mole/blob/main/lib/optimize/tasks.sh , …/lib/optimize/maintenance.sh , …/lib/optimize/catalog.sh , …/SECURITY_AUDIT.md
- Tencent Lemon Cleaner: https://github.com/Tencent/lemon-cleaner (QMPurgeRAM.m, QMLoginItemManager.m, LMXPCFunction.m)
- Stats: https://github.com/exelban/stats (Modules/RAM, CPU, Battery, Disk readers)
- Hammerspoon: https://github.com/Hammerspoon/hammerspoon/blob/master/Hammerspoon/HSuicore.m ; ForceQuitUnresponsiveApps: https://github.com/rentzsch/ForceQuitUnresponsiveApps
- osquery startup_items: https://github.com/osquery/osquery/blob/master/osquery/tables/system/darwin/startup_items.mm
- Objective-See DumpBTM: https://github.com/objective-see/DumpBTM
- BTM schema on Tahoe: https://github.com/WallyMagill/permission-pulse/blob/main/docs/_btm-schema-dump-tahoe-26.md ; sfltool verbs: https://github.com/sweeden-ttu/GlobPretect/blob/main/docs/VPN_BTM_CLI.md ; BTM versions: https://github.com/zaewc/Lumen/blob/main/docs/research/03-macos-platform.md
- BTM private framework exports: https://github.com/alexey-lysiuk/macos-sdk/blob/main/MacOSX26.5.sdk/System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Versions/A/BackgroundTaskManagement.tbd
- lsregister `-kill` removal: https://github.com/kdeldycke/dotfiles/blob/main/macos-config.sh , https://github.com/MadMartian/Scribobulate/blob/main/packaging/macos/README.md , https://github.com/1tuz/Lead-Aggregator/blob/main/docs/audits/2026-10-04/macos.md
- periodic removal on 15.x: https://github.com/AppliedIR/sift-mcp/blob/main/packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml ; heise (via 02): https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html
- MacSai (open-source clone; tasks, severities, issues): https://github.com/iliyami/MacSai/blob/main/Sources/MacCleanKit/MaintenanceTask.swift , https://github.com/iliyami/MacSai/issues/129 , https://github.com/iliyami/MacSai/issues/82
- CacheDelete: https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/device_link.py , https://github.com/jithin-sabu/purge-app/blob/main/spikes/apple-intelligence-models/Sources/aimodels/CacheDeleteCheck.swift
- Mail Envelope Index V10: https://github.com/precursorca/Munki-SelfService-On-Demand/blob/master/pkgsinfo/on_demand/PS-mail_optimizer-1.0.6.plist ; Mole Mail protection test: https://github.com/Tiavina22/hoopix/blob/main/test/features/optimize/data/sqlite_vacuum_task_test.dart
- Font caches: https://github.com/rtrouton/rtrouton_scripts/blob/master/rtrouton_scripts/reset_all_font_caches/reset_all_font_caches.sh , https://github.com/aerobounce/Japantown/blob/master/utils/remove-font-caches.sh
- Purgeable explanations: https://github.com/tzarebczan/diskhound/blob/main/src/shared/macStorageAccounting.ts , https://github.com/coreyhaines31/diskforecast/blob/main/site/purgeable-space-mac.html
- launchctl print-disabled spellings: https://github.com/gastownhall/gascity/blob/main/cmd/gc/cmd_supervisor_lifecycle.go ; disabled.plist path: https://github.com/slpcat/macos_config/blob/master/Disable-Sequoia-Bloatware.sh
- Login Items deep link: https://github.com/github/CopilotForXcode/blob/main/Tool/Sources/XPCShared/XPCCommunicationBridge.swift ; System Events delete: https://github.com/mullvad/mullvadvpn-app/blob/main/dist-assets/uninstall_macos.sh
- Activity Monitor entitlements dump: https://github.com/rreichel3/macOS-Data-Aggregator/blob/main/data/Activity%20Monitor/entitlements.plist
- Security history (via 02): https://blog.talosintelligence.com/vulnerability-spotlight-cleanmymac-x/ , https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716 , https://www.talosintelligence.com/vulnerability_reports/TALOS-2019-0759

**Added in the fact-check pass (all fetched this session):**
- MacPaw CMM3 binaries (strings): https://github.com/auspham/mac-essential/tree/master/CleanMyMac%203.app (main executable, `CleanMyMac 3 Menu.app`, `Contents/Library/LaunchServices/com.macpaw.CleanMyMac3.Agent`, Menu `Base.lproj/Health.strings`, `en.lproj/RAMUsageAlert.strings`)
- CMM3 Agent exploit and XPC protocol: https://github.com/vulncheck-oss/0day.today.archive/blob/main/local-exploits/30785.txt
- XNU: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/vfs/vfs_syscalls.c , …/bsd/kern/kern_memorystatus_notify.c , …/bsd/kern/kern_newsysctl.c , …/bsd/sys/event_private.h
- memory_pressure: https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c
- mDNSResponder SIGHUP: https://github.com/apple-oss-distributions/mDNSResponder/blob/mDNSResponder-2200.140.11/mDNSMacOSX/daemon.c
- CacheDelete: SDK stub https://github.com/alexey-lysiuk/macos-sdk/blob/main/MacOSX26.5.sdk/System/Library/PrivateFrameworks/CacheDelete.framework/Versions/A/CacheDelete.tbd ; decompiled reply handling https://github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore/blob/main/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete/CacheDeletePurgeSpaceWithInfo.mm ; spike results https://github.com/jithin-sabu/purge-app/blob/main/spikes/apple-intelligence-models/README.md ; vendor client log https://github.com/pabloguia/XCodeVault/blob/15bd48e15b8f0894ede4e153f864a7122c88b326/docs/research/evidence/e18-simctl-log-erase-macos26.6.2-25G83-xcode26.5-x86_64-superseded-20260915T202842.txt
- BTM vs launchd overrides: https://github.com/J-Park-Associates/Tax-Info-Request-List-Pilot/blob/6f6410be32ae5fac84ad4ae3f871e8895f8621dc/pilot/SPEC-mac-rerun1-fixes.md , https://github.com/fpcMotif/nix-darwin/blob/90855ed4d1768955000e849df0b6c547a825b701/PANIC.md , https://github.com/plow-pbc/tkmx-client/blob/0a6b48a0e29f935baa4ccc7a509cdfc580bb153b/reporter/doctor.ts , https://github.com/BookCatKid/MacPerms/blob/9195c32e2595eab8d89fc2f417b953b4e7bb46c0/Sources/OtherModel.swift
- lsregister: https://github.com/chriskraviz/griffel/blob/dc00d630a6cd01b36ab7f546f776e993fae0f1e4/scripts/reset-app.sh , https://github.com/vraravam/dotfiles/blob/ef39047f30c394ac1dc94f282688cef895f822c4/scripts/osx-defaults.sh , https://github.com/jeffmurphy/markdown-quicklook/blob/1d5cb0d1acdb4c551fba164f635052153aed8d32/openspec/changes/archive/2026-09-27-add-markdown-quicklook-preview/design.md
- tmutil output format: https://github.com/jithin-sabu/purge-app/blob/6cbd228152f24c080916af9f19d152475c138209/PurgeTests/LocalSnapshotReaderTests.swift
- Home-permissions recipe (HT203538 cited): https://github.com/tiiiecherle/osx_install_config/blob/master/07_backup_and_restore_script/permissions/ownerships_and_permissions_restore.sh ; DiskManagement symbol on 26.6: https://github.com/blacktop/ipsw-diffs/blob/main/macOS/26_6_25G5043d_vs_26_6_25G5052e/DYLIBS/System/Library/PrivateFrameworks/DiskManagement.framework/Versions/A/DiskManagement.md
- Mail V10 through Tahoe: https://github.com/tacogips/apple-gateway/blob/ac0dd8f0f5f100e2f4d4e44a2c18f49d11a0c1cd/design-docs/specs/design-apple-mail.md
- CVE record: https://raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4042.json
- Apple developer docs re-read (JSON): SMAppService `register()`, `statusForLegacyPlist(at:)`, `openSystemSettingsLoginItems()`, `unregister(completionHandler:)`; NSRunningApplication `terminate()`/`forceTerminate()`; `volumeAvailableCapacityForImportantUsageKey`

---

## Verification notes

Adversarial fact-check, 2026-10-12. WebSearch was unavailable (shared budget exhausted). `macpaw.com`, `support.apple.com`, `talosintelligence.com`, `heise.de` and `cli.cleanmymac.com` did not resolve or were blocked by the proxy. Reachable: GitHub (code search, raw files, git clone), `developer.apple.com` documentation JSON, MacPaw's DevMate S3 notes, the rendered man-page mirror, and the CVE list on GitHub.

### Claims checked

| # | Claim | Method | Result |
|---|---|---|---|
| 1 | `purge(8)` empties the disk cache, leaves anonymous memory alone, needs root | `purge.c`/`purge.8`, XNU `vfs_purge()` | **Confirmed.** The root citation was moved to XNU (`kauth_cred_issuser` → EPERM). **Added:** it also flushes file-backed VM pagers (`vfs.purge_vm_pagers`). |
| 2 | `memory_pressure -S` root need "UNVERIFIED" | `memory_pressure.c`, XNU sysctl rules | **Corrected → VERIFIED root** (non-ANYBODY sysctl write). Documented what `-S` actually does and that `-l`/`-p` need no root. |
| 3 | Vendor RAM mechanism unknown | `strings` on CMM3 Menu and Agent | **Answered for CMM3:** in-process allocation pressure, no `purge`, no root verb. |
| 4 | `kern.memorystatus_vm_pressure_level` 1/2/4 | XNU + `event_private.h` | **Confirmed**, readable unprivileged on macOS. |
| 5 | DNS flush = `dscacheutil -flushcache` + `killall -HUP mDNSResponder`; HUP is "community practice" | `dscacheutil.1`, `mDNSResponder.8`, Apple `daemon.c`, CMM3 Agent strings | **Confirmed; upgraded:** SIGHUP purges the cache and restarts queries per Apple source. The vendor used the same commands. |
| 6 | `periodic` present on 14, gone on 15+ | per-version man-page fetch (13/14/15/26/27), forensic YAML, MacSai #129 | **Confirmed** (also present on 13). The vendor's argv and log-staleness logic were added. |
| 7 | `mdutil -E /`, root | `mdutil.1` (26), MacSai | **Confirmed.** Vendor strings added. |
| 8 | `diskutil verify/repairPermissions` removed in 10.11; `resetUserPermissions` undocumented | `diskutil.8` (14 and 26) grep | **Confirmed.** **Added:** the vendor's CMM3 implementation, Apple's HT203538 recipe, and the private method still present in 26.6. |
| 9 | Speed Up Mail: vendor likely does a rebuild, not VACUUM | CMM3 main-binary strings | **Corrected:** the vendor ran `VACUUM;` via FMDB on `Envelope Index`. |
| 10 | Mail V10 = macOS 13+ | Munki plist + an independent spec | **Confirmed** through Tahoe. |
| 11 | `tmutil` local-snapshot verbs and urgency 1–4; man page identical 14–27 | man pages diffed | **Confirmed** (27 differs only in its footer). **Corrected:** the list includes `com.apple.os.update-*`, and TM names end in `.local` **or** `.backup`. |
| 12 | `lsregister -kill` removed; `-gc` is the replacement | 14 GitHub hits for the error text | **Removal confirmed on 26. Corrected:** `-gc` does not clear ghosts of deleted bundles; use `-dump` + `-u`. Exit codes are unreliable. Which macOS first removed `-kill` remains unknown. The vendor's old argv was added. |
| 13 | `launchctl enable/disable` persist; usable for `gui/<uid>` | `launchctl.1` (26), Lemon source, slpcat | **Clarified:** the man page lists only system/user/user-login domains; `gui/` is practice, not documentation. |
| 14 | BTM disposition bits, type values, store and entitlement | osquery source, `atrun.entitlements`, Activity Monitor entitlements, `sfltool.1` | **Confirmed.** `sfltool.1` documents only `archive` (a third-party doc claiming more is wrong). |
| 15 | BTM "allowed" vs launchd override interplay (INFERRED) | four field reports | **Upgraded to VERIFIED for 26.x** (separate DBs; durable disallow; manual bootstrap lasts one boot; SIP needed for per-item writes). |
| 16 | `SMAppService` APIs (`statusForLegacyPlist`, `openSystemSettingsLoginItems`, `register` approval semantics) | Apple docs JSON | **Confirmed** (macOS 13.0+). |
| 17 | `NSRunningApplication.terminate/forceTerminate` return false when sandboxed | Apple docs JSON | **Confirmed.** |
| 18 | CacheDelete keys and reply-block form | SDK `.tbd`, decompiled iOS 26.1, spike README | **Confirmed. Added:** the `…Sync` symbol, error key `CACHE_DELETE_ERROR`, query reply keys, and that the query works unprivileged. The vendor's 5.x HealthMonitor is a CacheDelete client. |
| 19 | Hung detection via CGS private API | Hammerspoon/FQUA + CMM3 Menu imports | **Confirmed. Added:** the vendor uses the same five symbols. |
| 20 | Stats formulas and commands (`ps -Aceo …`, `top -o mem/power`, pressure mapping) | Stats source | **Confirmed.** Minor correction: total RAM comes from `host_basic_info.max_mem`. Responsible-PID private symbol added. |
| 21 | CVE-2018-4042 = `removeLaunchdAgentAtPath` | CVE JSON + archived Talos text | **Confirmed.** |
| 22 | X Maintenance screen: 7 tasks, quit-apps sheet, completion "6 tasks" | `node_desc.json` 8_1–8_4 and screenshot 7_2 | **Confirmed.** Search-field location corrected. |
| 23 | 5.0.5 "Free Up Purgeable Space" (2025-02-10) | DevMate notes | **Feature confirmed.** The notes are undated, so the date was re-attributed to 01-overview. |
| 24 | MAS edition: review only | sibling 01/13 | **Corrected:** launch agents can still be uninstalled. |
| 25 | Source URL for Scribobulate | HTTP check | **Corrected** to the `master` branch. |
| 26 | Markdown tables | Column-count lint | **Corrected** four rows whose pipe characters inside code spans broke GFM tables. They are now backslash-escaped. |

### What remains uncertain

- Every 5.x screen detail and label (no reachable 5.x screenshots or KB pages).
- Whether 5.x shows "Run Maintenance Scripts" on macOS 14. The vendor KB via 01 says "≤13". The tool exists on 14.
- Whether an unentitled, non-root process may run a full CacheDelete **purge**, and whether `memory_pressure -S` measurably beats `purge` on Apple Silicon. Both need a hardware test.
- Whether the direct 5.x build can act on other apps' `SMAppService` main-app and login-item helper records. INFERRED no.
- The macOS version that first removed `lsregister -kill` (observed only on 26), and whether `-domain` is still silently accepted.
- Numeric thresholds for the vendor's high-memory and hung-app alerts.
- All CMM3 binary findings describe a 2018-era product. Carrying them over to X/5.x is INFERRED, though it is consistent with the 5.x CLI ("no sudo" RAM) and the 26.6 CacheDelete log.
