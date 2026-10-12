# 08 — Menu Bar App, Health Monitoring, Notifications and Assistant

> **Track:** the always-on menu-bar companion ("The Menu" in the vendor's product), the background health agent behind it, the alerts it raises, and the "Assistant" / AI features.
> **Target:** our own app (not called CleanMyMac) for an Apple Silicon **Mac mini** on macOS 14 Sonoma, 15 Sequoia, 26 Tahoe, and where noted macOS 27 ("Golden Gate", shipped Sept 2026 per 01-overview).
> **Date:** 2026-10-12.

---

## 0. Method, labels and limits

**Network constraints in this session.**
- The agent proxy blocks macpaw.com, cleanmymac.com, apps.apple.com, setapp.com and all the usual review sites (MacStories, 9to5Mac, TidBITS, Macworld). WebFetch returned DNS errors for them and curl got `403 CONNECT`.
- The shared web-search budget was already used up when this track started, so no new WebSearch queries were possible.
- What *was* reachable:
  - github.com and raw.githubusercontent.com, including GitHub code search across all public repos;
  - MacPaw's own DevMate release-note pages and Sparkle appcasts on `s3-us-west-2.amazonaws.com/updateinfo.devmate.com/…`;
  - the sibling reports in this folder, whose agents could still read MacPaw KB pages.

**Labels used on every claim.**

| Label | Meaning |
|---|---|
| **VERIFIED** | I read the cited source in this session: a fetched page, a raw file, or a MacPaw-shipped strings or release-note file. |
| **VERIFIED-X** | Read from a GitHub code-search excerpt (the text fragment the search API returned), not the whole file. |
| **VERIFIED-K** | A MacPaw KB or review fact that a **sibling report** verified (01-overview, 02-smart-care, 04-protection, 05-performance, 06-applications). The KB URL and the sibling are named. |
| **INFERRED** | Our reasoning, platform knowledge or design recommendation. Validate it on a real Mac before treating it as fact. |

**Fact-check pass (2026-10-12, second session).** An adversarial fact-checker re-tested ~25 implementation-critical claims. macpaw.com, cleanmymac.com, updates.cleanmymac.com, updates.devmate.com and the review sites were still unreachable (DNS failures), and the shared WebSearch budget was exhausted. Reachable and used instead: Apple's developer-documentation JSON (`developer.apple.com/tutorials/data/documentation/…json`), the open-source xnu and system_cmds trees (`github.com/apple-oss-distributions/…`), a public macOS SDK header mirror (`github.com/alexey-lysiuk/macos-sdk`), macOS man-page mirrors (`github.com/vitorgalvao/macos-man-pages`), exelban/stats raw files, the DevMate S3 appcasts and release notes, GitHub code search, and the CleanMyMac 3 Menu binary in the public `auspham/mac-essential` mirror (string/symbol listing only). Corrections are marked **(corrected)** in place. A summary is in the final "Verification notes" section.

**Paraphrase policy.** Only short UI labels are quoted ("Free Up", "Ignore Forever", …). Longer vendor text is paraphrased. Nothing here should be copied into our UI. §11 covers naming.

### 0.1 Source key

| Tag | Source |
|---|---|
| [CMM3-H94] | CleanMyMac 3 Help, topic "CleanMyMac 3 Menu": https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html (fetched raw) |
| [CMM3-PREF] | Shipped strings `CMMenuPreferencesViewController.strings` (3.9): https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/en.lproj/CMMenuPreferencesViewController.strings (fetched raw) |
| [CMM3-MENU] | The **CleanMyMac 3 Menu.app** bundle inside the same mirror (`CleanMyMac 3.app/Contents/MacOS/CleanMyMac 3 Menu.app/`). I read `_CodeSignature/CodeResources` (the resource file list), `Resources/Base.lproj/Health.strings`, `Resources/Base.lproj/Localizable.strings` and `Resources/en.lproj/{LowDiskSpaceAlert, RAMUsageAlert, RAMUsageIndicator, HungAppsAlert, SMARTAlert, BatteryHealthAlert, BatteryUsageIndicator, DiskIndicator, TrashSizeAlert, TrashSizeIndicator, TrashedAppAlert, MainMenu}.strings`. All fetched raw. |
| [DM-X] | CleanMyMac X release notes 4.10.0 → 4.15.8 (MacPaw-hosted): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html (fetched) |
| [DM-5] | CleanMyMac 5 release notes 5.0.0 → 5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html (fetched) |
| [AC-5] | CleanMyMac 5 Sparkle appcast: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml (fetched; stops at 5.3.1, `minimumSystemVersion` 11.0) |
| [CASK5] | Homebrew cask, CleanMyMac 5.7.1: https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/cleanmymac.rb (fetched raw) |
| [CASKX] | Homebrew-style cask, CleanMyMac X 4.15.8: https://github.com/letuanhai/homebrew-tap/blob/HEAD/Casks/cleanmymac-x.rb (fetched raw) |
| [FLEET] | Fleet uninstall script: https://github.com/fleetdm/fleet/blob/main/ee/maintained-apps/inputs/homebrew/scripts/cleanmymac-uninstall.sh (VERIFIED-X) |
| [AGENT-PLIST] | A user's backup of `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist`: https://github.com/MYunFeiYang/zbookpowerg7/blob/HEAD/docs/backups/cleanmymac5-residue-2026-09-18/com.macpaw.CleanMyMac5.Agent.plist (fetched) |
| [X-LAYOUT] | X bundle layout from scripts that patch it, e.g. https://github.com/shwang1114/InjectLib (`config.json`, `tool/cmm.sh`) and https://github.com/h4rk8s/Surge (`Custom/Reject.list`). Paths only, VERIFIED-X. Nothing from these repos is endorsed or used. |
| [LOGDIRS] | Log folder names seen in a cleanup log: https://github.com/andreychev/dotfiles/blob/HEAD/.config/mole/operations.log (VERIFIED-X) |
| [PROC-OBS] | Third-party process listings that include CleanMyMac 5's agents: https://github.com/OpenAgentsInc/openagents (`docs/kev/measurements/…`, `docs/gym/measurements/…`) and https://github.com/francescotinti/php-rust (`wp18x-harness/*.out`). VERIFIED-X. |
| [S-…] | **exelban/stats**, raw files fetched from `master` on 2026-10-12: `Modules/RAM/readers.swift` [S-RAM], `Modules/CPU/readers.swift` [S-CPU], `Modules/Net/readers.swift` [S-NET], `Modules/Battery/readers.swift` [S-BAT], `Modules/Bluetooth/readers.swift` [S-BT], `Modules/Disk/readers.swift` + `header.h` [S-DISK], `Modules/Sensors/readers.swift`, `reader.m`, `bridge.h` [S-SENS], `SMC/smc.swift` [S-SMC], `Kit/module/notifications.swift` [S-NOTIF], `Kit/module/popup.swift` [S-POPUP], `Kit/helpers.swift`, `Kit/plugins/SystemKit.swift` [S-KIT]. Plus `Modules/Disk/preview.swift` (VERIFIED-X). Repo: https://github.com/exelban/stats |
| [MACSAI] | Open-source CleanMyMac-style app with a separate menu-bar process: https://github.com/iliyami/MacSai (README fetched) |
| [ENEY] | Third-party write-ups of MacPaw's separate AI product "Eney": https://github.com/dpawlan/ai-assistant-benchmark/tree/main/data/agents/eney, plus a TechCrunch 2026-08-05 headline quoted in GitHub-hosted news digests (VERIFIED-X) |

---

## 1. TL;DR: what matters for implementation

1. **The menu-bar companion is a separate app with its own process**, plus a separate headless **Health Monitor** agent, a root **Agent** (privileged helper) and an **Updater** LaunchAgent.
   - CleanMyMac 5: launchd labels `com.macpaw.CleanMyMac5.Menu` and `com.macpaw.CleanMyMac5.HealthMonitor`, login item "CleanMyMac 5 Menu", helper `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`. VERIFIED [CASK5], [FLEET], [AGENT-PLIST].
   - Both agents run as children of launchd (ppid 1). VERIFIED-X [PROC-OBS].
2. **What the Menu monitors, by generation.**
   - CMM3: Startup disk, Memory, Battery and Trash, with "Free Up" (RAM) and "Empty Trash". VERIFIED [CMM3-H94].
   - X 4.11 (2022): rebuilt with CPU, Memory, Storage, Battery and Protection. VERIFIED [DM-X].
   - X 4.11.2–4.11.4: Network Monitor with Speed Test and traffic totals. VERIFIED [DM-X].
   - X 4.13: Connected Devices and External Drives. VERIFIED [DM-X].
   - 5.x: a grid of tiles covering Health, Protection, Storage, Memory, Battery, CPU, Network and Connected Devices. VERIFIED-K (01-overview §5.2 citing https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu and …/devices-monitoring; 02-smart-care §2 citing MacStories and 9to5Mac).
3. **The Health Monitor raises the alerts, not the Menu UI.**
   - It collects memory, disk, battery, CPU, network, unresponsive-app and Trash data.
   - It alerts on low disk space, high memory use and unresponsive apps, and offers "uninstall completely" when an app is dragged to the Trash.
   - It also powers real-time malware monitoring.
   - VERIFIED-K (01-overview §8, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes).
4. **Alert catalogue across generations** (all VERIFIED; sources in §6):
   - low free disk space;
   - Trash over a size limit;
   - an app moved to the Trash (offer complete uninstall);
   - unresponsive apps (Force Quit All);
   - heavy memory use (RAM + swap almost full);
   - critical S.M.A.R.T. / low SSD life / high disk temperature;
   - battery failing;
   - battery-drain spike, showing time to empty and offering Low Power Mode and display dimming;
   - low battery on Bluetooth devices;
   - app updates available, listing the top outdated apps;
   - malware found;
   - weekly cleanup reminders and feature recommendations.
5. **Snooze model (CMM3; INFERRED to persist).** Each alert has a split button "Ignore ▾" with "Ignore For Now", "Ignore Forever" and, for slow-changing hardware issues, "Remind in a Week". There is also "Learn More…", plus a global "Reset All Warnings". VERIFIED [CMM3-MENU], [CMM3-PREF].
6. **Settings are deliberately thin.**
   - 5.x Settings › Menu has **Enable Menu** and **Recommendations** (feature suggestions plus weekly cleanup reminders). VERIFIED-K (01-overview §10).
   - CMM3 had thresholds: "Warn when free space is less than" (Don't Warn, 500 MB … 100 GB), "Notify when Trash size exceeds", an "Offer to correctly uninstall applications" toggle and an "App monitor" toggle for hung apps. VERIFIED [CMM3-PREF].
7. **If background items are disallowed** (System Settings › General › Login Items & Extensions › Allow in the Background), the Menu won't open and the Settings toggle does nothing. VERIFIED-K (01-overview §8, https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items).
8. **Assistant.**
   - X 4.10.0 (released 21 Dec 2021 per the X appcast; (corrected) previously given as 2022) added an Assistant panel (upper-right of the main window) with "timely Recommendations" and usage statistics. Its recommendations also appear in the Menu and can be managed in Preferences. VERIFIED [DM-X].
   - 5.x has an Assistant entry plus a **Mac Health** score in five bands (Excellent → Critical) with fix-it recommendations. VERIFIED-K (01-overview §5.2, §11).
9. **AI.**
   - The only AI feature found in CleanMyMac is **Smart Insights** (5.2.6, Oct 2025). Powered by Apple Intelligence, it explains what a system file is, why it matters and whether you need it. VERIFIED [DM-5]. Requirements per 01-overview: Apple Silicon, macOS 26, Apple Intelligence on.
   - **No chat assistant inside CleanMyMac was found.** MacPaw's conversational, agentic assistant is a separate product, **Eney**, with an on-device version announced with Liquid AI in Aug 2026. VERIFIED-X [ENEY].
10. **Metrics: every number the Menu shows can come from public or semi-public macOS APIs.** exelban/stats proves each path in open source (§5).
    - Mach: `host_statistics64`, `host_processor_info`.
    - sysctls: `kern.memorystatus_vm_pressure_level`, `vm.swapusage`, `kern.boottime`, `NET_RT_IFLIST2`.
    - libproc: `proc_pid_rusage`.
    - IOKit: `AppleSmartBattery`, `IOPowerSources`, `AppleDeviceManagementHIDEventService` for Bluetooth battery, `AppleSMC`, the NVMe SMART plug-in, and `IOHIDEventSystemClient` for Apple-Silicon temperatures.
    - SystemConfiguration, CoreWLAN, DiskArbitration and IOBluetooth.
11. **Mac mini specifics (INFERRED).**
    - There is **no internal battery**: hide the Battery tile, but show a **UPS** if one is attached (stats handles `kIOPSUPSType`, VERIFIED [S-BAT]).
    - Ethernet is often the primary interface.
    - **Bluetooth peripheral batteries** (Magic Keyboard, Mouse, Trackpad, AirPods) and **external drives** matter most on a mini.
12. **Resource budget is a differentiator.** Third-party listings show CleanMyMac 5's HealthMonitor at **422,352 KiB RSS (≈412 MiB)** and samples of **≈3–19 % CPU** (observed 2.9, 4.4, 6.8, 8.1, 14.9, 19.3 %), with the Menu around 2.5 %. (corrected: was "about 422 MB" and "4–19 %".) VERIFIED-X [PROC-OBS]. Target for ours (INFERRED): **< 40 MB RSS and < 0.3 % average CPU while the popover is closed.** No `ps`, `top` or `nettop` subprocesses while closed.

---

## 2. Product history of the menu-bar companion

| Generation | What the Menu had | Status / source |
|---|---|---|
| **CleanMyMac 3** (2015–2018) | Status icon appears on first launch and stays after the main app quits. **Metrics:** Startup disk (free space, drive health, your free-space threshold; click opens Finder), Memory (free/total; click opens Activity Monitor), Battery (charge, health, capacity; click opens Energy Saver), Trash (system plus external-drive Trash size against your limit; click opens Trash). **Actions:** hover Memory → "Free Up"; hover Trash → "Empty Trash". Gear menu: About, Preferences, Provide Feedback, Reset All Warnings, Quit. Turning the Menu off means losing most notifications; Scheduler reminders still fire. The Menu's Trash total can differ from the Trash Bins module, which also counts app trash folders. | VERIFIED [CMM3-H94], [CMM3-MENU] `MainMenu.strings` |
| CMM3 alert set | Low free space, Trash over threshold, uninstall offer for apps dragged to the Trash, disk-failure (S.M.A.R.T.) warning, disk overheating, battery failure, heavy memory, non-responding apps. All can be ignored or postponed. | VERIFIED [CMM3-H94] |
| CMM3 resources | Separate nib views per indicator and per alert: `DiskIndicator`, `RAMUsageIndicator`, `BatteryUsageIndicator`, `TrashSizeIndicator`, `LowDiskSpaceAlert`, `RAMUsageAlert`, `HungAppsAlert`, `SMARTAlert`, `BatteryHealthAlert`, `TrashSizeAlert`, `TrashedAppAlert`. Template status icons `MenubarIconTemplate.tiff` and `MenubarIconPressedTemplate.tiff`. A bundled `Library/LaunchServices/com.macpaw.CleanMyMac3.Agent` helper. | VERIFIED [CMM3-MENU] |
| **CleanMyMac X 4.0** (2018) | "Reworked Menu". | VERIFIED-K (01-overview §3) |
| **X 4.10.0** (Dec 2021 build) | Assistant recommendations shown **in the Menu** (managed in Preferences). | VERIFIED [DM-X] |
| **X 4.11.0** (mid-2022) | Menu rebuilt and expanded: **CPU** (load, top-consuming apps, uptime, unusual spikes), **Memory** (available, which apps use it, quick free-up), **Storage** (available space, drive temperature, drive condition), **Battery** (cycles, health, time to full), **Protection** (how protected, which monitors are on, when the malware DB was last updated). Network Monitor and Connected Devices were promised for the next release. | VERIFIED [DM-X] |
| X 4.11.2 / 4.11.3 / 4.11.4 | **Network Monitor** returns with **Speed Test** and more connection details. Speed units clarified; adds **traffic amounts**. Bug fixes. Better app-update notifications. | VERIFIED [DM-X] |
| X 4.12.4 | **Battery drain alert** for sudden bursts of consumption. | VERIFIED [DM-X] |
| **X 4.13.0** (Mar 2023) | **Connected Devices** section: wired and wireless peripherals (headphones, speakers, mice, keyboards, trackpads, phones), battery or storage state, **connect/disconnect**. Not in the App Store edition. **External Drives** section: manage connected storage and clean junk on it in place. | VERIFIED [DM-X] |
| X 4.13.6 | Battery-drain alerts show **time until full discharge**. **Display Dimming** and **Low Power Mode** can be switched on from CleanMyMac (macOS 12+). Trash Monitor fixes. | VERIFIED [DM-X] |
| X 4.14.0 (Jul 2023) | **Low battery alerts for Bluetooth devices** (not in the App Store edition). App-update notification lists your **top outdated apps**. | VERIFIED [DM-X] |
| X 4.14.2 | Improved **heavy memory usage alert** with quick release. | VERIFIED [DM-X] |
| X (4.x) Notifications prefs | Weekly cleanup reminders; tips about unused features; full-uninstall prompt; overfilled Trash and cluttered drives (including external); low-RAM warnings. Configurable from the Menu or Preferences › Notifications. | VERIFIED-K (02-smart-care §6.1, https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu) |
| X widget | X shipped a widget extension, `com.macpaw.CleanMyMac4.CleanMyMacWidget` (container and Application Scripts in the cask's zap list). No equivalent appears in the 5.x cask. | VERIFIED [CASKX], [CASK5] |
| **CleanMyMac 5.0** (Oct 2024) | "Redesigned Menu" as a grid of tiles. KB groups The Menu into performance, battery, storage, network and connected devices. | VERIFIED-K (01-overview §5.1, §6; 02-smart-care §2) |
| 5.x Menu sections | **Health**; **Protection** (real-time / background scan status, DB status); **Storage** (free space, disk health and temperature, empty Trash; startup volume only); **Memory** (Free Up, pressure, swap, top apps); **Battery** (health = actual / design mAh, with Normal / Warning / Critical bands); **CPU** (load, temperature, top consumers); **Network**; **Connected Devices** (cable, Bluetooth or Wi-Fi; up to 3 shown; devices under 20 % battery shown red and sorted on top). Recommendations and weekly cleanup reminders toggle in Settings › Menu. | VERIFIED-K (01-overview §5.2 citing …/cleanmymac-menu, …/devices-monitoring, …/cleanmymac-menu-recommendations) |
| 5.5.0 (Apr 2026) | **My Tools** hub can also be opened **from the Menu**. | VERIFIED-K (01-overview §5.2, https://macpaw.com/news/my-tools-cleanmymac) |
| 5.0–5.3.1 release notes | No Menu-specific items. | VERIFIED [DM-5] |
| KB troubleshooting | An article titled "Troubleshoot the CleanMyMac Menu not loading correctly" (`…/knowledgebase/menu-no-elements`). Per the citing note, the Menu shows no elements until it has loaded. | VERIFIED-X (title and URL only, cited in https://github.com/venomousmoog/lintel/blob/HEAD/docs/research/2026-07-06-feasibility-findings.md) |

---

## 3. Process architecture

### 3.1 Vendor (for reference)

**CleanMyMac X bundle nesting.** VERIFIED-X [X-LAYOUT].
```
CleanMyMac X.app/Contents/Library/LoginItems/CleanMyMac X Menu.app
    └─ Contents/Library/LoginItems/CleanMyMac X HealthMonitor.app
    └─ Contents/Library/LaunchServices/com.macpaw.CleanMyMac4.Agent   (SMJobBless helper)
CleanMyMac X.app/Contents/Library/LaunchServices/com.macpaw.CleanMyMac4.Agent
```
- The Menu's `Info.plist` carries an `SMPrivilegedExecutables` entry for the Agent, so the **Menu itself can install and talk to the root helper**.
- The Menu links a `CMMNotifications.framework`.
- X launchd labels: `.Agent`, `.HealthMonitor`, `.Menu`, `.Scheduler`, `.Updater`. VERIFIED [CASKX].

**CleanMyMac 5.** VERIFIED [CASK5], [FLEET], [AGENT-PLIST], VERIFIED-X [LOGDIRS], [PROC-OBS].
- App: `/Applications/CleanMyMac_5.app` (bundle ID `com.macpaw.CleanMyMac5`). (corrected/clarified) That is the bundle name inside MacPaw's zip; Finder shows it as "CleanMyMac". The Homebrew cask installs it as **`/Applications/CleanMyMac.app`** (`app "CleanMyMac_#{version.major}.app", target: "CleanMyMac.app"`, with the comment that the name differs between Finder and the shell). VERIFIED (cask re-fetched raw this session). Code that looks for the vendor app (e.g. a migration or "conflicting cleaner" check) must try both paths, or better, resolve it by bundle ID with `NSWorkspace.urlForApplication(withBundleIdentifier:)`.
- Agents: `com.macpaw.CleanMyMac5.Menu` and `com.macpaw.CleanMyMac5.HealthMonitor`. They are removed with `launchctl remove` and have **no plist file** in `~/Library/LaunchAgents`, which suggests they are registered dynamically. Process names equal the bundle IDs.
- Root helper: `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` with `MachServices` set to `com.macpaw.CleanMyMac5.Agent` and `Program` set to `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`.
- Updater: `~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist`.
- Shared App Group container `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/` holds logs under `Library/Logs/CleanMyMac_5`, `…/CleanMyMac_5_Menu` and `…/CleanMyMac_5_HealthMonitor`. The three processes share one container.
- **Separation of duties:** the Health Monitor keeps alerting and malware-watching even when the Menu UI is off. VERIFIED-K (01-overview §8).
- **Respawn:** one cleanup guide notes that killed CleanMyMac processes come back within seconds, and stops them with `launchctl bootout gui/$UID/com.macpaw.CleanMyMac5.{Menu,HealthMonitor}`. VERIFIED-X (https://github.com/ArshiaEcho/janitor, `fix-blocks-mac.md`). (corrected) The earlier explanation, "KeepAlive on both agents", is not needed: Apple documents that a **LoginItem** registered through `SMAppService.register()` "starts immediately and on subsequent logins" and that if it "crashes or exits with a non-zero status, the system relaunches it". VERIFIED (https://developer.apple.com/documentation/servicemanagement/smappservice/register()). A `kill`/SIGTERM is not a clean exit, so the job comes back. The legacy `SMLoginItemSetEnabled` login items behave the same way. INFERRED: the vendor's agents get this from login-item registration, not from a hand-written KeepAlive plist. That fits the absence of any plist in `~/Library/LaunchAgents`, and the `gui/$UID` domain used by `bootout`.
- **Per-process preferences and caches.** The Menu and the Health Monitor each have their **own** defaults domain (`com.macpaw.CleanMyMac5.Menu`, `com.macpaw.CleanMyMac5.HealthMonitor`), next to the main app's `com.macpaw.CleanMyMac5`. VERIFIED-X (a `defaults domains` export: https://github.com/tracycsmith/refineo-laptop-config/blob/HEAD/exports/macos-settings/defaults-domains.txt). Each also has `~/Library/Caches/com.macpaw.CleanMyMac5.{Menu,HealthMonitor}`, and the Health Monitor has its own `~/Library/HTTPStorages/com.macpaw.CleanMyMac5.HealthMonitor`, so it makes its own network requests (malware DB or telemetry, INFERRED). VERIFIED-X (https://github.com/themoretheless/ppduster/blob/HEAD/rules/apps-personal.yaml). Note that the Homebrew `zap` list does not remove these per-process files.
- **Login-item nesting (Background Task Management).** An `sfltool dumpbtm` dump of CleanMyMac X shows the Menu registered as an app login item and the Health Monitor as a **nested login item whose parent is the Menu**. VERIFIED-K (sibling 10-internals §2.2, citing a dump at https://github.com/jinrenjie/blog). So turning the Menu off in System Settings › Login Items & Extensions also disables the Health Monitor. That matches the KB's "allow background items" troubleshooting.
- **The Mac App Store edition's Menu has no Disk Health or Temperature** (sandbox). VERIFIED-K (13-helpcenter §3.25/§3.33, citing …/knowledgebase/missing-features and …/disk-no-health-and-temperature).

### 3.1.1 What the CleanMyMac 3 Menu binary links against (added by fact-check)

The `CleanMyMac 3 Menu` Mach-O (x86_64) in the public mirror was downloaded and only listed with `strings` (nothing was executed). Its import table and selector names show how MacPaw's own menu agent got its data. VERIFIED (binary at `https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/MacOS/CleanMyMac%203%20Menu`):
- **Hung apps:** imports the private SkyLight/CoreGraphics symbols `CGSMainConnectionID`, `CGSRegisterNotifyProc`, `CGSRemoveNotifyProc` and `CGSEventIsAppUnresponsive`, plus `GetProcessForPID`. Classes `CMHungAppsMonitor`, `CMHungAppIssue`, a `permanentlyIgnoredApps` store, and the menu labels "Ignore This Session" / "Ignore Listed Apps" / "Ignore Apps". So CMM3 subscribed to the window server's app-unresponsive notification and confirmed with `CGSEventIsAppUnresponsive`; it did not use AX polling. This answers gap 9 for CMM3. INFERRED: X and 5.x probably keep the same approach.
- **Memory:** `kern.memorystatus_vm_pressure_level` (with the log "Did fail to get memory pressure…"), `__dispatch_source_type_memorypressure`, `host_statistics64`, `vm_page_size`, and the properties `usedSwapSize` / `swapOccupancyFraction`. That fits the "RAM + Swap almost full" alert.
- **CPU:** `host_processor_info`.
- **Storage:** `CSDiskSpaceGetRecoveryEstimate` (purgeable space, the same SPI stats uses), `statfs`-family calls, DiskArbitration (`DASessionCreate`, `DADiskCreateFromVolumePath`, `DADiskCreateFromBSDName`, `DADiskCopyDescription`), `IOCreatePlugInInterfaceForService` (SMART), `NSWorkspaceDidMount/DidUnmountNotification`.
- **Free-space hysteresis:** the log strings "Free disk space %@ is under the threshold of %@. Alert was shown." and "Free disk space monitor: Free space is close to threshold. Ignoring.", plus `isCloseToThreshold` and `defaultThresholdForRootDiskVolume`. The monitor de-bounces near the threshold, and the default threshold is computed per root volume rather than fixed.
- **Battery:** `IOPSCopyPowerSourcesInfo/List`, `IOPSGetPowerSourceDescription`, `IOPMCopyBatteryInfo`, IORegistry `AppleSmartBattery`, and `BatteryHealthCondition` with the values "Check Battery" / "Permanent Battery Failure".
- **Trash watching:** `__dispatch_source_type_vnode` (kqueue vnode sources, not FSEvents).
- **Plumbing:** `SMJobBless`, `SMLoginItemSetEnabled`, `SCNetworkReachability*`, `CGWindowListCopyWindowInfo`, `kill`.

### 3.2 Ours (INFERRED recommendation)

```
OurApp.app                          main window (modules), Settings
 ├─ Contents/Library/LoginItems/OurMonitor.app   LSUIElement agent:
 │     • status item + popover UI ("Monitor")
 │     • sampling engine + alert engine ("Sentinel")
 │     • reminder scheduler, recommendation engine
 ├─ Contents/Library/LaunchDaemons/com.our.helper.plist  → root helper (SMAppService.daemon)
 └─ Shared: App Group container group.com.our.app  (settings, snapshots, alert state, activity log)
```

- **Use one agent process, not two.**
  - Keep the status item optional: Settings › Monitor › "Show in menu bar". When it is hidden, the agent still runs for alerts.
  - That gives the vendor's separation (alerts work without the Menu UI) at half the RAM and with no IPC between UI and sampler.
  - Split into two processes later only if malware watching becomes heavy (see 04-protection).
- **Registration (macOS 13+).**
  - Register with `SMAppService.loginItem(identifier: "com.our.app.monitor")`. The helper bundle must sit in the main app's `Contents/Library/LoginItems`. VERIFIED (https://developer.apple.com/documentation/servicemanagement/smappservice/loginitem(identifier:), macOS 13.0+).
  - Read `.status` (`.enabled`, `.requiresApproval`, `.notRegistered`, `.notFound`). VERIFIED (the four cases of `SMAppService.Status`: https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum).
  - If the status is `.requiresApproval`, show a banner with a button that calls `SMAppService.openSystemSettingsLoginItems()` (VERIFIED, macOS 13.0+). This mirrors the vendor's "Allow in the Background" troubleshooting.
- **Do not set unconditional KeepAlive.** Respect the user quitting the agent from its menu.
  - (added) A LoginItem registered with `SMAppService` already gets **relaunch on crash or non-zero exit** (VERIFIED, `register()` docs). So "Quit Monitor" must end with exit status 0 (`NSApp.terminate(nil)` does). Then it stays down until the next login or until the main app re-opens it with `NSWorkspace.openApplication(at:configuration:)`.
  - If we hand-write a LaunchAgent instead, use `KeepAlive = { SuccessfulExit = false }`.
- **IPC.**
  - Main app ↔ agent: `NSXPCConnection` to a Mach service the agent vends, for "free up memory", "empty Trash", "refresh now" and "open module X".
  - For one-way invalidations: shared `UserDefaults(suiteName:)` plus `DistributedNotificationCenter` pings.
  - Agent → root helper: the same XPC client the main app uses (05-performance and 01-overview §8, §12 cover the helper's allow-listed API).
- **Deep links.** URL scheme `ourapp://module/cleanup?autostart=1`, `ourapp://applications/updater` and so on. The popover and notification actions open the main app on the right screen.

---

## 4. The popover: sections, layout and behavior

### 4.1 Status item

- **Vendor:**
  - A monochrome template icon (CMM3 `MenubarIconTemplate.tiff` plus a pressed variant). VERIFIED [CMM3-MENU].
  - Whether 5.x can show text such as CPU % next to the icon is not documented. GAP. TidBITS called 5.x Menu settings very limited. VERIFIED-K (01-overview §10).
- **Ours (INFERRED):**
  - Use `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)` with an SF Symbol-style **original** template glyph.
  - Optional compact readout. Settings › Monitor › "Menu bar shows": Icon only (default) / Free disk / Memory pressure / CPU % / Network ↑↓.
  - Tint the icon only for **active** problems: amber for warning, red for critical. Keep it monochrome otherwise to respect menu-bar conventions.
  - Left-click toggles the popover. Right-click (or ⌥-click) shows a small `NSMenu`: Open App, Settings…, Pause Alerts for 1 h / Until Tomorrow, Quit Monitor.
  - (added) **The status item can disappear without the agent quitting.** Apple documents that a SwiftUI `MenuBarExtra`-only app is terminated automatically if the user removes the extra from the menu bar. VERIFIED (https://developer.apple.com/documentation/swiftui/menubarextra). That is another reason to use an `NSStatusItem` in an agent that must keep alerting. Set `item.behavior = []` (no `.removalAllowed`) unless we persist an "icon hidden" state. INFERRED: on macOS 26 the user can also hide third-party menu-bar items in System Settings (a Menu Bar pane), and a crowded or notched menu bar can truncate items. Detect `item.isVisible == false` or a zero-width button window, and offer the global hotkey from §10 plus a "Show monitor icon" button in the main app.

### 4.2 Container and look

- **Vendor:** 5.x uses a tile grid. X 4.11+ used vertical sections that expand to detail views. VERIFIED-K (02-smart-care §2) for the tiles. The X expand behavior is INFERRED from the per-section detail described in [DM-X].
- **Stats** uses a custom titled, borderless `NSWindow` subclass (`PopupWindow`, `.fullSizeContentView`, `collectionBehavior = .moveToActiveSpace`) instead of `NSPopover`. Its header has an activity button, a title and a settings button. VERIFIED [S-POPUP].
- **Ours (INFERRED):**
  - **Window:** an `NSPanel` (`[.nonactivatingPanel, .fullSizeContentView]`, `level = .popUpMenu`, `hidesOnDeactivate`-like behavior via a global click monitor) anchored under the status item. Content is SwiftUI (`NSHostingView`).
    - Prefer this over `MenuBarExtra(.window)`, which offers no programmatic open/close and no right-click.
    - Prefer it over `NSPopover`, whose arrow and inset look dated on Tahoe.
  - **Size:** 360 pt wide; height fits content up to `min(640, screen.visibleFrame.height - 40)`, then scrolls.
  - **Material:**
    - macOS 14/15: `.regularMaterial` / `NSVisualEffectView(.popover)`.
    - macOS 26+: Liquid Glass (`.glassEffect()` on cards), with `if #available(macOS 26, *)` and `accessibilityReduceTransparency` fallbacks.
  - **Layout:**
    ```
    ┌ Header: [health dot] "All good" / "2 issues" · [Open App] [⚙︎]
    ├ Alert strip (only when something is wrong; max 2 rows, "…N more")
    ├ Grid 2 × N of cards: Protection | Storage
    │                      Memory     | CPU
    │                      Network    | Battery/UPS (hidden if none)
    │                      Devices (full width, up to 3 rows)
    │                      Drives  (full width, one row per external volume, Eject)
    ├ Recommendation card (dismissible; one at a time)
    └ Footer: Quick tools row (Free Up Memory · Empty Trash · Smart Scan · Tools ▸)
    ```
  - **Cards:** title, one big number, a sparkline (last 60 samples) or a ring gauge, a status line, and **one** primary action. Clicking a card pushes a **detail page** inside the popover (a `NavigationStack`-style transition) with lists such as top processes, volumes or devices. A back chevron returns.
  - **Refresh policy:** sample at "live" cadence only while the panel is visible (§5.11). On open, render the last cached snapshot immediately, then refresh. This avoids the vendor's "no elements until loaded" state.
  - **Accessibility:** every card is an accessibility element with label and value ("Memory, 62 percent used, pressure normal"). Respect Reduce Motion for sparklines and transitions. 5.0.7 added VoiceOver and Reduce Motion, VERIFIED [DM-5].

### 4.3 Header / Health

- **Vendor:**
  - 5.x Menu shows **Health**, the same Mac Health status as the main app.
  - Bands: Excellent / Good / Fair / Requires Attention / Critical.
  - Inputs: free space, threats, battery health, system load, other HW metrics, FDA granted, recent scan.
  - VERIFIED-K (01-overview §5.2, §11; https://macpaw.com/support/cleanmymac/knowledgebase/mac-health).
- **Ours:** reuse the scoring in 01-overview §11 (start at 100, deductions per issue). Header text is the band. Tapping it opens a detail page listing each deduction with a fix button (§8.5).

### 4.4 Protection card

- **Vendor:**
  - X 4.11: how protected the Mac is, which monitors are on, malware DB last update. VERIFIED [DM-X].
  - 5.x: real-time monitor and background-scan status plus DB status. VERIFIED-K (01-overview §5.2).
- **Ours:** shield state (On / Off / Needs FDA), last scan ("3 days ago"), threats found (0 / N), signature DB date. Action: "Scan" (Quick) or "Review N threats". Data comes from the Protection engine's shared state (04-protection).

### 4.5 Storage card

- **Vendor:**
  - CMM3: free space, drive health, your threshold. The tooltip explains that "Available" counts free plus purgeable space the system can release. VERIFIED [CMM3-MENU] `Health.strings` (`DiskFreeSpace_tooltip`).
  - X 4.11 adds drive temperature and condition. VERIFIED [DM-X].
  - (added) In X, the storage section's **Free Up** button starts a Smart Scan immediately (it does not just open the app). VERIFIED-K (13-helpcenter §3.42, citing https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu). Our "Clean Up…" action should likewise open the main window **and start** the scan (`ourapp://smartscan?autostart=1`).
  - 5.x: free space, disk health, temperature, empty Trash; startup volume only. VERIFIED-K (01-overview §5.2).
- **Ours:**
  - Big number: available on the startup volume (`volumeAvailableCapacityForImportantUsage`), with a ring for used/total.
  - Status line: "Healthy · 38 °C · SSD life 98 %" (§5.4).
  - Actions: **Empty Trash** (shows Trash size, §5.10) and "Clean Up…" (deep link).
  - Detail page: purgeable estimate, Trash breakdown (startup plus external), SMART fields (power-on hours, data written, unsafe shutdowns, media errors).

### 4.6 Memory card

- **Vendor:**
  - CMM3: free/total plus "Free Up". The legend explains **Wired / Active / Inactive / Compressed**. Shows "Freeing Up…" while running. VERIFIED [CMM3-MENU] (`RAMUsageIndicator.strings`, `Health.strings`).
  - X 4.11: available RAM, which apps use it, how to free it. VERIFIED [DM-X].
  - 5.x: Free Up, pressure, swap, top apps. VERIFIED-K (01-overview §5.2).
- **Ours:**
  - Big number: memory pressure state (Normal / Elevated / Critical), plus a bar of used/total split into App, Wired, Compressed and Cached.
  - Status line: "Swap 1.2 GB".
  - Action: **Free Up**, which reports before → after "available". Mechanism and caveats are in 05-performance §4.1.
  - Detail page: top 5 apps by footprint (grouped by responsible app) with Quit / Force Quit.

### 4.7 CPU card

- **Vendor:**
  - X 4.11: load, top-consuming apps, uptime, unusual spikes. VERIFIED [DM-X].
  - 5.x: load, temperature, top consumers. VERIFIED-K (01-overview §5.2).
  - CPU temperature uses the unit set in System Settings › Language & Region. VERIFIED-K (01-overview §10, https://macpaw.com/support/cleanmymac/knowledgebase/cpu-temperature).
- **Ours:**
  - Big number: total CPU %, with a sparkline (user plus system).
  - Status line: "52 °C · up 6 d 4 h · load 2.1".
  - Detail page: per-core bars (P and E clusters separated), top 5 processes, thermal state, uptime.
  - Spikes: mark a sparkline point red when CPU > 80 % for ≥ 10 s.

### 4.8 Network card

- **Vendor:**
  - X 4.11.2+: Network Monitor with **Speed Test** and connection details. 4.11.3 added traffic amounts. VERIFIED [DM-X].
  - The exact 5.x fields are not available to us. GAP.
- **Ours:**
  - Big numbers: ↓ and ↑ throughput (auto units: B/s, KB/s, MB/s; or bits, per a setting).
  - Status line: "Ethernet · 1 Gb/s" or "Wi-Fi ‘Home’ · −52 dBm".
  - Detail page:
    - interface, local IPv4/IPv6, router, DNS servers;
    - public IP (opt-in fetch);
    - session totals (↓/↑ since login, resettable);
    - top 5 apps by traffic (only while the page is open);
    - **Speed Test** button (download, upload, responsiveness) via `networkQuality` (§5.5).

### 4.9 Battery card (hidden on a Mac mini unless a UPS is present)

- **Vendor:**
  - CMM3: charge, health, capacity in mAh, "Charged", "Not Charging", "Calculating…", "h:mm Until Full", "h:mm Remaining". VERIFIED [CMM3-MENU] `Health.strings`.
  - X 4.11: cycles, health, time to full. VERIFIED [DM-X].
  - 5.x: health = actual / design capacity, with bands. VERIFIED-K (01-overview §5.2). That row states ≥ 80 % Normal, ≤ 79 % Warning, ≤ 10 % Critical. (corrected: downgraded to INFERRED.) 01-overview's own fact-checker could not re-verify these numbers either, and the KB was unreachable again in this pass. INFERRED: "Normal / Warning" are **health** bands that match Apple's 80 % "Service Recommended" convention, while "≤ 10 % Critical" is almost certainly **charge**, because no battery reads 10 % health and still works. Our spec uses health < 80 % → warning and charge ≤ 10 % → critical, as two separate signals.
- **Ours:**
  - Laptops: level, state, time remaining, cycles, health %, condition, temperature, adapter W.
  - **Mac mini:** show a UPS card only when `IOPSCopyPowerSourcesList` contains a `UPS` source: level, "On UPS power" / "On AC", time remaining if reported. Otherwise omit the card entirely.

### 4.10 Connected Devices card

- **Vendor:**
  - X 4.13: all kinds of wired and wireless peripherals, battery or storage, connect/disconnect. Not in the App Store edition. VERIFIED [DM-X].
  - 5.x: cable, Bluetooth or Wi-Fi devices; up to 3 shown; under 20 % shown red and sorted on top. VERIFIED-K (01-overview §5.2, …/devices-monitoring).
- **Ours:**
  - Up to 3 rows: device glyph, name, battery % (AirPods: L / R / Case), connection type.
  - Sort: low battery (< 20 %) first, then connected, then name. "Show all" opens the detail page.
  - Row action menu: Connect / Disconnect (Bluetooth), "Open Bluetooth Settings".

### 4.11 External Drives card

- **Vendor:** X 4.13: manage connected storage and clean junk on it in place. VERIFIED [DM-X].
- **Ours:**
  - One row per mounted external volume: name, free / total, a ring, an **Eject** button (⏏).
  - Overflow menu: "Clean junk on this drive" (Trash and system junk on that volume; see 03-cleanup) and "Reveal in Finder".
  - While ejecting, show a spinner. If it fails, show "In use by: <app>" (dissenter info, §5.4).

### 4.12 Recommendations, reminders and quick tools

- **Vendor:**
  - Assistant recommendations in the Menu (X 4.10+). VERIFIED [DM-X].
  - 5.x Settings › Menu › Recommendations covers feature suggestions plus weekly cleanup reminders. VERIFIED-K (01-overview §10).
  - My Tools can be opened from the Menu (5.5). VERIFIED-K.
- **Ours:**
  - One recommendation card at a time: "Trash holds 7.4 GB" → Empty Trash; "No scan in 14 days" → Run Smart Scan; "3 app updates" → Review.
  - Dismissing suppresses that rule for 30 days, the same as [MACSAI]'s behavior (VERIFIED README).
  - The footer quick-tools row is user-configurable (the four most used tools).

---

## 5. Getting each metric in Swift

> All code is **INFERRED** reference code written for this report. API facts are VERIFIED against exelban/stats where tagged. Cache `mach_host_self()` once: every call returns a new send right, so stats keeps a global `machHostPort`. Run samplers off the main thread, and publish `Sendable` snapshots to the UI actor.

### 5.1 Memory

**What stats does** (VERIFIED [S-RAM]):
- `host_info(HOST_BASIC_INFO)` → `max_mem` for total.
- `host_statistics64(HOST_VM_INFO64)` → counts × `vm_page_size`.
- `used = active + inactive + speculative + wired + compressed − purgeable − external`
- `app = used − wired − compressed`, `cache = purgeable + external`, `free = total − used`.
- Pressure: `sysctlbyname("kern.memorystatus_vm_pressure_level")`, mapped **2 → warning, 4 → critical**, anything else normal. Re-VERIFIED in xnu (`bsd/kern/kern_memorystatus_notify.c`, `sysctl_memorystatus_vm_pressure_level`):
  - The handler returns `convert_internal_pressure_level_to_dispatch_level(...)`, i.e. `NOTE_MEMORYSTATUS_PRESSURE_NORMAL = 0x1`, `…_WARN = 0x2`, `…_CRITICAL = 0x4` (`bsd/sys/event_private.h`).
  - The kernel's internal `kVMPressureUrgent` level is **folded into WARN**.
  - On release kernels the OID is registered with `CTLFLAG_MASKED`. It does **not** appear in `sysctl -a` but is readable by name. On macOS no privilege check applies (the `priv_check_cred` call is `#if !XNU_TARGET_OS_OSX`).
  - Sources: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c and https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/event_private.h.
- Swap: `sysctlbyname("vm.swapusage")` → `struct xsw_usage { xsu_total, xsu_avail, xsu_used, xsu_pagesize, xsu_encrypted }`. VERIFIED (xnu `bsd/sys/sysctl.h`). (corrected) `swapins` / `swapouts` do **not** come from `vm.swapusage`. stats reads them from the same `vm_statistics64` (`HOST_VM_INFO64`) result as the page counts. VERIFIED [S-RAM].

```swift
import Darwin

let hostPort = mach_host_self()          // cache once

struct MemorySnapshot: Sendable {
    var total, used, app, wired, compressed, cached, free: UInt64
    var swapUsed, swapTotal: UInt64
    var pressure: Pressure
}
enum Pressure: Int32, Sendable { case normal = 1, warning = 2, critical = 4 }

func sysctlValue<T>(_ name: String, _ initial: T) -> T? {
    var v = initial; var size = MemoryLayout<T>.size
    return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
}

func readMemory() -> MemorySnapshot? {
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return nil }
    let page = UInt64(vm_kernel_page_size)            // 16 KiB on Apple Silicon
    let total = ProcessInfo.processInfo.physicalMemory
    let active = UInt64(vm.active_count) * page, inactive = UInt64(vm.inactive_count) * page
    let spec = UInt64(vm.speculative_count) * page, wired = UInt64(vm.wire_count) * page
    let comp = UInt64(vm.compressor_page_count) * page
    let purg = UInt64(vm.purgeable_count) * page, ext = UInt64(vm.external_page_count) * page
    let gross = active + inactive + spec + wired + comp
    let used = gross > purg + ext ? gross - purg - ext : 0     // stats formula, clamped
    var swap = xsw_usage()
    _ = withUnsafeMutablePointer(to: &swap) { p -> Int32 in
        var s = MemoryLayout<xsw_usage>.size; return sysctlbyname("vm.swapusage", p, &s, nil, 0) }
    let level = sysctlValue("kern.memorystatus_vm_pressure_level", Int32(1)) ?? 1
    return MemorySnapshot(total: total, used: used, app: used &- wired &- comp, wired: wired,
                          compressed: comp, cached: purg + ext, free: total &- used,
                          swapUsed: swap.xsu_used, swapTotal: swap.xsu_total,
                          pressure: Pressure(rawValue: level) ?? .normal)
}
```

**Event-driven alerts (INFERRED).** The agent should **not** poll for alerts. Use the kernel's pressure events:

```swift
let pressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .global(qos: .utility))
pressureSource.setEventHandler { [weak engine] in engine?.memoryPressureChanged(pressureSource.data) }
pressureSource.activate()
```

**More INFERRED notes.**
- `kern.memorystatus_level` is the "system-wide memory free percentage" that `memory_pressure` prints. It makes a good 0–100 gauge. (Upgraded to VERIFIED.) `memory_pressure.c` prints "System-wide memory free percentage" from `memorystatus_get_level()`, and the kernel side copies out the same `memorystatus_level` variable that `SYSCTL_INT(_kern, OID_AUTO, memorystatus_level, …)` exports. Sources: https://github.com/apple-oss-distributions/system_cmds/blob/main/memory_pressure/memory_pressure.c and xnu `bsd/kern/kern_memorystatus.c`.
- The public `DispatchSource.makeMemoryPressureSource(eventMask:queue:)` is VERIFIED (https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)). The source starts **inactive**, so call `activate()`. The kernel also has a private `NOTE_MEMORYSTATUS_LOW_SWAP (0x8)`, but it is not in the public `MemoryPressureEvent` mask, so poll `vm.swapusage` (60 s) for swap alerts. INFERRED.
- The CMM3 heavy-memory alert was about **RAM + swap** being nearly full. VERIFIED [CMM3-MENU] (`RAMUsageAlert.strings`: "RAM + Swap", "Almost full"; `Health.strings` RAM notification). Our trigger combines pressure with swap (§6).

### 5.2 CPU load, cores, uptime, load average

**What stats does** (VERIFIED [S-CPU]):
- `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` gives per-CPU tick arrays of `CPU_STATE_MAX` entries (USER, SYSTEM, IDLE, NICE).
- Per-core usage = Δ(user + system + nice) / Δ(total) between samples.
- **`vm_deallocate` the previous array.**
- Totals come from `HOST_CPU_LOAD_INFO`.
- Hyperthreading is detected via `hw.physicalcpu` ≠ `hw.logicalcpu` (always false on Apple Silicon).
- Per-cluster grouping uses core types (efficiency vs performance).
- CPU frequency uses the private **IOReport** API (`IOReportCopyChannelsInGroup`, `IOReportCreateSubscription`, `IOReportCreateSamplesDelta`, channel names `ECPU*` / `PCPU*`).
- Thermal limits come from `pmset -g therm`.
- Load average: stats runs `/usr/bin/uptime` every 15 s. VERIFIED. Prefer `getloadavg()` (INFERRED).
- Boot time: stats uses `sysctl([CTL_KERN, KERN_BOOTTIME])` → `timeval`. VERIFIED [S-KIT].

```swift
final class CPUSampler {
    private var prev: [UInt32] = []                       // flattened ticks
    func sample() -> (total: Double, perCore: [Double])? {
        var n: natural_t = 0, info: processor_info_array_t?, infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &n, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                              vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        let cur = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { prev = cur }
        guard prev.count == cur.count else { return nil }  // first sample primes
        var per: [Double] = [], busyAll = 0.0, totAll = 0.0
        for c in 0..<Int(n) {
            let b = Int(CPU_STATE_MAX) * c
            let d = { (i: Int32) in Double(cur[b + Int(i)] &- self.prev[b + Int(i)]) }
            let busy = d(CPU_STATE_USER) + d(CPU_STATE_SYSTEM) + d(CPU_STATE_NICE)
            let tot = busy + d(CPU_STATE_IDLE)
            per.append(tot > 0 ? busy / tot : 0); busyAll += busy; totAll += tot
        }
        return (totAll > 0 ? busyAll / totAll : 0, per)
    }
}
// Clusters (INFERRED): sysctl hw.nperflevels, hw.perflevel0.logicalcpu (P), hw.perflevel1.logicalcpu (E).
// Load: var l = [Double](repeating: 0, count: 3); getloadavg(&l, 3)
// Uptime: Date().timeIntervalSince(bootTime) using kern.boottime (counts sleep; matches Activity Monitor).
```

- (added) **Do not assume exactly two core clusters.** Current stats code knows a third core type (`.super`, with the IOReport channel prefix `MCPU` used for performance cores when "super" cores exist) for the newest chips. VERIFIED [S-CPU] (`sCoreCount`, `sCoreFreqs`, `usageSCores`). Iterate `hw.nperflevels` and read `hw.perflevel<N>.logicalcpu` / `hw.perflevel<N>.name` for every N rather than hard-coding P and E. INFERRED.

### 5.3 Top processes (CPU, memory, energy, disk) and grouping

**What stats does** (VERIFIED):
- CPU: `/bin/ps -Aceo pid,pcpu,comm -r` [S-CPU].
- Memory: `/usr/bin/top -l 1 -o mem -n N -stats pid,command,mem` [S-RAM].
- Energy: `top -o power -l 2 …`, parsing the **second** sample [S-BAT].
- Per-process disk I/O: `proc_pid_rusage(pid, RUSAGE_INFO_CURRENT)` → `ri_diskio_bytesread` / `ri_diskio_byteswritten` [S-DISK].
- Grouping: helpers are grouped under the app that owns them via the private `responsibility_get_pid_responsible_for_pid`, resolved with `dlsym`, then `NSRunningApplication(processIdentifier:)` for name and icon [S-RAM].

**Ours (INFERRED): no subprocesses.** Use libproc directly, sampling twice ≥ 1 s apart:

```swift
import Darwin

struct ProcSample { let pid: pid_t; let cpuTicks: UInt64; let footprint: UInt64; let diskR: UInt64; let diskW: UInt64 }

func listPIDs() -> [pid_t] {
    let n = proc_listallpids(nil, 0); guard n > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(n) + 32)
    let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
    return Array(pids.prefix(Int(max(got, 0)))).filter { $0 > 0 }
}

func rusage(_ pid: pid_t) -> ProcSample? {
    var ri = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &ri) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard rc == 0 else { return nil }        // EPERM for some root/other-user pids → skip or use helper
    return ProcSample(pid: pid, cpuTicks: ri.ri_user_time + ri.ri_system_time,
                      footprint: ri.ri_phys_footprint,          // ≈ Activity Monitor "Memory"
                      diskR: ri.ri_diskio_bytesread, diskW: ri.ri_diskio_byteswritten)
}

// ri_user_time/ri_system_time are mach-absolute-time units on Apple Silicon (timebase 125/3);
// convert: ns = ticks * numer / denom (mach_timebase_info). CPU% = Δns / Δwall_ns * 100 (per core).
```

**Grouping and UI (INFERRED):**
- Fold helpers into the owning app (use `responsibility_get_pid_responsible_for_pid` behind `dlsym`, falling back to the pid itself). Show the app icon via `NSRunningApplication.icon`.
- Exclude our own pids and kernel_task from "Quit" actions. 05-performance §7.4 has the protect list.
- Energy: `ri_billed_energy` / `ri_energy_nj` (newer `rusage_info_v6`) can stand in for `top`'s POWER column. Fall back to the `top -l 2` approach only in the detail page.
  - (Upgraded to VERIFIED: field names checked in xnu `bsd/sys/resource.h` and in the macOS SDK headers 13.3, 14.5, 15.5 and 26.5.)
  - `RUSAGE_INFO_CURRENT` is `RUSAGE_INFO_V6` in all four SDKs.
  - `ri_billed_energy` / `ri_serviced_energy` exist since **v4**.
  - **v6** adds `ri_user_ptime`, `ri_system_ptime`, `ri_pinstructions`, `ri_pcycles`, **`ri_energy_nj`**, **`ri_penergy_nj`** (P-core share), `ri_secure_time_in_system` and `ri_secure_ptime_in_system`.
  - The 15.x and later SDKs also carve `ri_neural_footprint`, `ri_lifetime_max_neural_footprint` and `ri_interval_max_neural_footprint` out of the reserved tail (`ri_reserved[9]` remains). The struct size is unchanged, so one `rusage_info_v6` read works on macOS 14 through 27.
  - Sources: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h and `https://raw.githubusercontent.com/alexey-lysiuk/macos-sdk/main/MacOSX<ver>.sdk/usr/include/sys/resource.h`.
  - INFERRED: switch the sample code above to `rusage_info_v6` / `RUSAGE_INFO_V6` and compute energy rate = Δ`ri_energy_nj` / Δt (nJ/s = nW).
- The note that `ri_user_time` / `ri_system_time` come back in Mach ticks on Apple Silicon (convert with `mach_timebase_info`) is backed by several independent open-source process monitors that do exactly this conversion. VERIFIED-X (GitHub code search: e.g. `makepad/makepad apps/task/src/backend/macos.rs`, `agentmuxai/agentmux crates/procstats/src/macos.rs`).

### 5.4 Storage: capacity, purgeable, health, temperature, volumes, eject

**Capacity.**
- VERIFIED [S-DISK]:
  - `statfs` gives `f_blocks × f_bsize` (total) and `f_bavail × f_bsize` (available).
  - On APFS, stats adds purgeable from `CSDiskSpaceGetRecoveryEstimate(url)` (CoreServices SPI, cached for 60 s).
  - Otherwise it uses `URLResourceValues.volumeAvailableCapacityForImportantUsage`.
- Ours (INFERRED): display `volumeAvailableCapacityForImportantUsageKey`, which matches Finder's "Available" and already includes purgeable. Also show `volumeAvailableCapacityKey` (truly free) in the detail page. This mirrors CMM3's free-vs-available tooltip (VERIFIED [CMM3-MENU]).

**Disk health and temperature (NVMe SMART).** VERIFIED [S-DISK]:
- Find the IOMedia's parent with property **"NVMe SMART Capable" = true**.
- Call `IOCreatePlugInInterfaceForService(disk, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, …)`, then `QueryInterface(kIONVMeSMARTInterfaceID)`, then `SMARTReadData(&nvme_smart_log)`.
- UUIDs as used by stats: user client `AA0FA6F9-C2D6-457F-B10B-59A13253292F`, interface `CCD1DB19-FD9A-4DAF-BF95-12454B230AB6`.
- Fields:
  - `temperature` (Kelvin, little-endian 2 bytes) → °C = K − 273;
  - `percent_used` → **life = 100 − percent_used**;
  - `critical_warning`, `avail_spare` / `spare_thresh`;
  - `data_units_read` / `written` × 512 000 bytes;
  - `power_on_hours`, `power_cycles`, `unsafe_shutdowns`, `media_errors`.
- ATA SMART (`kIOATASMARTUserClientTypeID`) is used for older SATA drives. It is **off by default** in stats (`Disk_ATASMART` defaults to false), while NVMe SMART is on by default. VERIFIED [S-DISK].

INFERRED for health and SMART:
- **Health states:** Good (`critical_warning == 0 && life > 10 && spare ≥ thresh`); Warning (life ≤ 10 % or spare < threshold); Critical (`critical_warning != 0` or media errors increasing).
- These map to CMM3's "Critical S.M.A.R.T diagnostics!", "Low SSD life!" and "High disk temperature!" alerts. VERIFIED [CMM3-MENU] `Health.strings`.
- Read SMART every 5–10 min. stats defaults to 30 s on its own interval (VERIFIED [S-DISK]); that is too frequent for an always-on agent.

**Throughput (optional).** `IOBlockStorageDriver` property `Statistics` → `Bytes (Read)` / `Bytes (Write)`, as deltas. VERIFIED [S-DISK].

**Volumes and eject.**
- VERIFIED:
  - stats enumerates mounted volumes with DiskArbitration (`DASessionCreate`, `DADiskCreateFromVolumePath`, `DADiskCopyDescription` → `kDADiskDescriptionMediaRemovableKey`, `…VolumeNameKey`, `…VolumeKindKey`, `…DeviceProtocolKey`, `…MediaEncryptedKey`) [S-DISK].
  - It ejects with `NSWorkspace.shared.unmountAndEjectDevice(at:)` (`Modules/Disk/preview.swift`, VERIFIED-X).
- INFERRED:
  - Watch `NSWorkspace.didMountNotification` / `didUnmountNotification`, or `DARegisterDiskAppearedCallback`, instead of polling.
  - List volumes with `FileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey], options: [.skipHiddenVolumes])` and filter `volumeIsInternal == false`.
  - For a proper "in use by" message, use `DADiskUnmount(disk, kDADiskUnmountOptionDefault, callback, ctx)`. A dissenter's status string tells you the volume is busy; then `lsof +f -- /Volumes/X` (read-only) can name the process.
    - VERIFIED in the macOS 26.5 SDK `DADisk.h`: `kDADiskUnmountOptionForce = 0x00080000` and `kDADiskUnmountOptionWhole = 0x00000001`, plus `DARegisterDiskAppearedCallback`.
    - `kDAReturnBusy` exists as a dissenter status code. The header uses it for mounting a disk that is already mounted. INFERRED: a busy unmount returns `kDAReturnBusy` (sometimes `kDAReturnNotPermitted`), and `DADissenterGetStatusString` may carry a reason. Log both and fall back to `lsof`.
    - Use `kDADiskUnmountOptionWhole` before `DADiskEject` so every partition of a multi-volume drive is unmounted.

### 5.5 Network: throughput, interface, IPs, Wi-Fi, per-app, speed test

**Primary interface.** `SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4")["PrimaryInterface"]`. VERIFIED [S-NET]. The same dictionary has `Router` (INFERRED). DNS servers are at `State:/Network/Service/<id>/DNS` (VERIFIED [S-NET]) or `State:/Network/Global/DNS` → `ServerAddresses` (INFERRED).

**Byte counters, avoiding the 4 GiB wrap.**
- stats reads `sysctl([CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, ifindex])` and walks `if_msghdr` records to the `RTM_IFINFO2` entry, then uses `if_msghdr2.ifm_data.ifi_ibytes` / `ifi_obytes`, which are **64-bit**. VERIFIED [S-NET].
- `getifaddrs` → `ifa_data` (`struct if_data`) has **32-bit** counters that wrap at 4 GiB. Use `getifaddrs` only for flags, addresses and `ifi_baudrate`. (Upgraded to VERIFIED.) In xnu `bsd/net/if_var.h`, `struct if_data` declares `u_int32_t ifi_ibytes/ifi_obytes` and `struct if_data64` declares `u_int64_t`. `bsd/net/if.h` shows `struct if_msghdr2 { … struct if_data64 ifm_data; }`.
- stats drops deltas above 1.5 × link rate as reconnect glitches. VERIFIED [S-NET]. Copy that guard.

```swift
func interfaceBytes(_ name: String) -> (rx: UInt64, tx: UInt64)? {
    let idx = if_nametoindex(name); guard idx != 0 else { return nil }
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(idx)]
    var len = 0
    guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
    var off = 0
    while off + MemoryLayout<if_msghdr>.size <= len {
        let hdr = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: if_msghdr.self) }
        if Int32(hdr.ifm_type) == RTM_IFINFO2 {
            let h2 = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self) }
            if UInt32(h2.ifm_index) == idx { return (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes) }
        }
        guard hdr.ifm_msglen > 0 else { break }
        off += Int(hdr.ifm_msglen)
    }
    return nil
}
```

**Local IP.** `getifaddrs` with `AF_INET` / `AF_INET6` on the primary interface → `getnameinfo(…, NI_NUMERICHOST)`. VERIFIED that stats does this (`getLocalIP`) [S-NET].

**Public IP.**
- stats shells out to `curl -s -4 https://api.mac-stats.com/ip` (and `-6`). VERIFIED [S-NET].
- Ours (INFERRED):
  - Use `URLSession` to a user-configurable endpoint, default off ("Show public IP" toggle) because it contacts a third party.
  - Refresh on `NWPathMonitor` path changes, at most every 10 min.

**Reachability.** stats has a reachability helper plus an ICMP / HTTP connectivity checker (default ICMP host `1.1.1.1`, HTTP host `https://google.com`). VERIFIED [S-NET]. Ours: `NWPathMonitor` (public) for status, with no pinging by default (INFERRED).

**Wi-Fi details.**
- VERIFIED [S-NET]:
  - stats uses CoreWLAN: `CWWiFiClient.shared().interface(withName:)` → `ssid()`, `bssid()`, `transmitRate()`.
  - It observes `.ssidDidChange` events.
  - It requests **Location** authorization via `CLLocationManager`, because SSID comes back nil or `"<redacted>"` without it. It treats `"<redacted>"` as unusable.
- Ours (INFERRED):
  - Also read `rssiValue()`, `noiseMeasurement()`, `wlanChannel()?.channelNumber`, `security()`.
  - Ask for Location only when the user opens the Network detail page. Add `NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription`.
  - Ethernet link speed: `SCNetworkInterfaceCopyMediaOptions` → `kSCPropNetEthernetMediaSubType` (VERIFIED [S-NET]).

**Per-app traffic.**
- No public API. stats parses `/usr/bin/nettop -P -L 1 -n -k …` CSV (column 1 bytes in, column 2 bytes out, per `name.pid`) and diffs successive runs. VERIFIED [S-NET].
- Ours (INFERRED): run it only while the Network detail page is visible, with a 5 s timeout. The private `NetworkStatistics.framework` is the in-process alternative.

**Speed Test (upgraded: flags and keys VERIFIED from Apple's man pages for macOS 14, 15, 26 and 27).**
- macOS 12+ ships `/usr/bin/networkQuality` (INFERRED; the man page carries a 2020 date).
- **Flags on macOS 15 / 26 / 27** (identical man pages):
  - `-c [filename]`: JSON output, to stdout by default.
  - `-s`: sequential instead of parallel upload/download.
  - `-u` / `-d`: skip the upload or download test (each implies `-s`).
  - `-I <interface>`: bind to an interface, e.g. `en0`.
  - `-M <seconds>`: maximum run time.
  - `-f h1|h2|h3|L4S|noL4S`: force a protocol.
  - `-p`: use iCloud Private Relay.
  - `-k`: skip TLS verification.
  - `-C <config URL>`: use a custom server.
  - `-b` / `-B`: Bonjour servers.
- **macOS 14 differs:** no `-M`, `-b` or `-B`, and `-c` takes no filename. VERIFIED (https://github.com/vitorgalvao/macos-man-pages/blob/main/macOS/14/man8/networkQuality.8 vs `.../macOS/15/...`, `/26/`, `/27/`). Use only `-c`, `-s`, `-I` if we must run on 14, and enforce our own timeout.
- **Documented JSON keys** (macOS 15–27):
  - `dl_throughput`, `ul_throughput`;
  - `responsiveness` (RPM; the combined value);
  - `dl_responsiveness` / `ul_responsiveness` (**only with `-s`**);
  - `base_rtt` (ms; the macOS 14 man page misspells it `base_rt`);
  - `dl_flows`, `ul_flows`, `interface_name`, `os_version`, `start_date`, `end_date`;
  - `il_h2_req_resp`, `il_tcp_handshake_443`, `il_tls_handshake`;
  - the `lud_*` latency-under-load arrays;
  - on failure, `error_code` and `error_domain`.
  - The page notes the list is not exhaustive.
- **Units (corrected):** the macOS 15/26/27 man pages say throughput is in **bits per second**. The macOS 14 page says bytes per second. INFERRED: treat the value as bits/s, as the macOS 15+ docs and the open-source parser below do. Sanity-check once on device against the human-readable `networkQuality` output, which prints Mbps.
- An open-source Swift wrapper also reads the undocumented keys `dl_bytes_transferred`, `ul_bytes_transferred` and `cli_options`. VERIFIED-X (https://github.com/jtn0123/OpenTaskManager/blob/HEAD/Packages/OTMKit/Sources/OTMKit/System/NetworkQuality.swift). Treat them as optional.
- **UI.** Show a progress state (about 10–20 s; pass `-M 30` on 15+) and a Cancel button that terminates the process. Never auto-run: each test saturates the link and uses data.

### 5.6 Battery and UPS (laptops; UPS on a Mac mini)

**What stats reads** (VERIFIED [S-BAT]):
- `IOPSCopyPowerSourcesInfo` + `IOPSCopyPowerSourcesList` + `IOPSGetPowerSourceDescription`. It picks `kIOPSTypeKey == kIOPSInternalBatteryType` and separately a **`kIOPSUPSType`** source.
- From the description:
  - `kIOPSPowerSourceStateKey` ("AC Power" / "Battery Power"; UPS: "UPS Power");
  - `kIOPSIsChargedKey`, `kIOPSCurrentCapacityKey` (%);
  - `kIOPSTimeToEmptyKey` / `kIOPSTimeToFullChargeKey` (minutes);
  - `"Optimized Battery Charging Engaged"`;
  - `kIOPSBatteryHealthKey` (Intel only).
- From IORegistry `AppleSmartBattery`:
  - `IsCharging`, `CycleCount`, `DesignCapacity`;
  - **`AppleRawMaxCapacity` on Apple Silicon** (`MaxCapacity` on Intel), falling back to `NominalChargeCapacity` / `BatteryData.FullChargeCapacity`;
  - `AppleRawCurrentCapacity`, `Amperage` (mA), `Voltage` (mV), `Temperature` (centi-°C);
  - `AdapterDetails.AdapterVoltage`, `ChargerData.{ChargingCurrent, ChargingVoltage, NotChargingReason}`.
- Health % = `round(100 × maxCapacity / designCapacity)`, capped at 100.
- Adapter watts via `IOPSCopyExternalPowerAdapterDetails()[kIOPSPowerAdapterWattsKey]`.
- On ARM, SMC keys `PPBR` (battery power) and `PDTR` (adapter power).
- **Change notifications:** `IOPSNotificationCreateRunLoopSource(callback, ctx)` added to a run loop, so there is no polling.

**INFERRED additions:**
- `kIOPSBatteryHealthConditionKey` (`"BatteryHealthCondition"`) drives a "battery failing" alert. That is the CMM3 "Your battery is failing!" equivalent (VERIFIED [CMM3-MENU]). (corrected)
  - The SDK defines only **two** values for this key: `kIOPSCheckBatteryValue = "Check Battery"` and `kIOPSPermanentFailureValue = "Permanent Battery Failure"`. VERIFIED (macOS 26.5 SDK `IOKit.framework/Headers/ps/IOPSKeys.h`). The CMM3 binary checks exactly these two strings (§3.1.1).
  - "Service Recommended" is a System Settings label, not a value of this key. INFERRED mapping: treat health < 80 % or either condition value as "service".
  - `kIOPSBatteryHealthKey` ("Good" / "Fair" / "Poor") is what stats reads on Intel only.
- `IOPSGetTimeRemainingEstimate()` returns `kIOPSTimeRemainingUnknown` (−1.0) while macOS is "Calculating…" on battery or UPS. Show that literal state, as CMM3 did (VERIFIED [CMM3-MENU]). (added) It returns **`kIOPSTimeRemainingUnlimited` (−2.0) on AC or any unlimited source**. VERIFIED (SDK `IOPowerSources.h`). A Mac mini will normally always get −2, so render "On AC power", never "−2 min".
- (added) **UPS detection on a Mac mini.** `IOPSGetProvidingPowerSourceType(snapshot)` returns one of `"AC Power"`, `"Battery Power"` or **`"UPS Power"`** (`kIOPMUPSPowerKey`). VERIFIED (SDK `IOPowerSources.h`). Use it as the `ups.onBattery` trigger.
  - The per-source `kIOPSPowerSourceStateKey` is documented only as `"AC Power"`, `"Battery Power"` or `"Off Line"` (SDK `IOPSKeys.h`).
  - stats compares the UPS source's state with `"UPS Power"` [S-BAT]. INFERRED: that comparison may never match, so prefer the providing-type API, or check the UPS source for `"Battery Power"`.
  - `pmset -u haltlevel|haltafter|haltremain` holds the UPS emergency-shutdown thresholds, and `pmset -g ups` / `pmset -g ps` print them and the UPS status. VERIFIED (macOS 26 `pmset(1)`: https://github.com/vitorgalvao/macos-man-pages/blob/main/macOS/26/man1/pmset.1). Show them read-only in the UPS detail page.
- Low Power Mode state: `ProcessInfo.processInfo.isLowPowerModeEnabled` (macOS 12.0+, VERIFIED: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled) plus `.NSProcessInfoPowerStateDidChange`.
  - Toggling needs root, so route it through the helper. Offer it in the drain alert, as X 4.13.6 did (VERIFIED [DM-X]).
  - (corrected) `lowpowermode` is **not documented** in the macOS 26 `pmset(1)` man page. It is a widely used but undocumented key (`sudo pmset -a lowpowermode 1`). VERIFIED-X (many dotfiles on GitHub).
  - Newer systems expose a **`powermode`** key (0 = automatic, 1 = low power, 2 = high power, INFERRED meanings). One public measurement log describes a **Mac mini on AC power with `pmset` powermode 1** and `isLowPowerModeEnabled == true`. VERIFIED-X (https://github.com/LouisVasseur/SPLICE/blob/HEAD/experimental/scaleli/results/gre_mac_2026-10-06/README.md). So Low Power Mode **is** available on current Apple Silicon desktops.
  - Read `pmset -g` (or `pmset -g cap`), then write whichever of `powermode` / `lowpowermode` the machine lists. Hide the action if neither is listed.
- **Mac mini:** `IOPSCopyPowerSourcesList` normally contains no internal battery, so render nothing. A USB HID UPS appears as `kIOPSUPSType`, and the card then shows level, source, and time to empty if provided.

### 5.7 Bluetooth and other connected-device batteries

stats combines **five sources** (VERIFIED [S-BT]). Use the same layering (INFERRED order):

| # | Source | Gives | Notes |
|---|---|---|---|
| 1 | `IOBluetoothDevice.pairedDevices()` | name, `addressString`, `isConnected()`, `isPaired()` | Device list and connection state. Connect / disconnect via `openConnection()` / `closeConnection()` (INFERRED). |
| 2 | IORegistry class **`AppleDeviceManagementHIDEventService`**, filtered to `BluetoothDevice == true` | `Product`, **`BatteryPercent`**, `DeviceAddress` / `SerialNumber` / `BD_ADDR`, `VendorID`, `ProductID` | Best source for Magic Keyboard, Mouse and Trackpad. Live, with no subprocess. |
| 3 | `UserDefaults(suiteName: "/Library/Preferences/com.apple.Bluetooth")` → `DeviceCache`, `PairedDevices`, `CoreBluetoothCache` | `BatteryPercent`, `BatteryPercentCase`, `BatteryPercentLeft`, `BatteryPercentRight` | AirPods and Beats split batteries. May be stale or absent on newer macOS (INFERRED). |
| 4 | `pmset -g accps -xml` (cached 10 s) | per-accessory `Name`, `Current Capacity`, `Accessory Identifier`, `Part Identifier` (Left / Right / Case), `Group Identifier`, `Is Charging` | Reliable for AirPods parts. Subprocess. |
| 5 | `system_profiler SPBluetoothDataType -json` (cached 30 s) | `device_batteryLevelLeft` / `Right` / `Case` / `Main` | Slow (seconds). Detail page only. |
| 6 | CoreBluetooth GATT **Battery Service 0x180F**, characteristic **0x2A19** | BLE peripherals that expose standard battery | Needs `NSBluetoothAlwaysUsageDescription` and the user's Bluetooth permission. stats pauses on sleep and resumes on wake. |

```swift
import IOKit

func hidBluetoothBatteries() -> [(name: String, percent: Int, address: String?)] {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else { return [] }
    defer { IOObjectRelease(iter) }
    var out: [(String, Int, String?)] = []
    var svc = IOIteratorNext(iter)
    while svc != 0 {
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let d = props?.takeRetainedValue() as? [String: Any],
           (d["BluetoothDevice"] as? Bool) == true,
           let name = d["Product"] as? String, let pct = d["BatteryPercent"] as? Int {
            out.append((name, pct, d["DeviceAddress"] as? String))
        }
        IOObjectRelease(svc); svc = IOIteratorNext(iter)
    }
    return out
}
```

**Wired and mobile devices (INFERRED):**
- USB storage arrives through §5.4 volumes.
- iPhone and iPad over cable: detect via IOKit USB matching (`IOUSBHostDevice` with Apple vendor ID `0x05AC` and an iPhone product name), or `system_profiler SPUSBDataType -json`.
- The vendor shows "battery or storage" for mobile devices (VERIFIED [DM-X]). Getting iPhone battery needs the private MobileDevice framework. **Skip it**: show the connection only.

### 5.8 Temperatures (Apple Silicon) and thermal state

**Option A: SMC** (VERIFIED [S-SMC], [S-CPU]).
- `IOServiceMatching("AppleSMC")` → `IOServiceOpen` → `IOConnectCallStructMethod(conn, 2 /*kernelIndex*/, SMCKeyData_t …)`.
- Inner commands: **readKeyInfo = 9**, **readBytes = 5**, readIndex = 8.
- Decode by data type: `flt `, `sp78`, `fpe2`, `ui8 `/`ui16`/`ui32`, `sp1e…spf0`.
- CPU temperature: stats tries Intel keys `TC0D`/`TC0E`/`TC0F`/`TC0P`/`TC0H` (if < 110 °C). Otherwise it averages a per-generation list:
  - **M1:** `Tp09 Tp0T Tp01 Tp05 Tp0D Tp0H Tp0L Tp0P Tp0X Tp0b`
  - **M2:** `Tp1h Tp1t Tp1p Tp1l Tp01 Tp05 Tp09 Tp0D Tp0X Tp0b Tp0f Tp0j`
  - **M3:** `Te05 Te0L Te0P Te0S Tf04 Tf09 Tf0A Tf0B Tf0D Tf0E Tf44 Tf49 Tf4A Tf4B Tf4D Tf4E`
  - **M4:** `Te05 Te09 Te0H Te0S Tp01 Tp05 Tp09 Tp0D Tp0V Tp0Y Tp0b Tp0e`
  - **M5:** `Tp00 Tp04 Tp08 Tp0C Tp0G Tp0K Tp0O Tp0R Tp0U Tp0X Tp0a Tp0d Tp0g Tp0j Tp0m Tp0p Tp0u Tp0y`
- Battery temperature fallback: `TB1T` / `TB2T`. Fan: `F0Ac` etc. (in smc.swift).

**Option B: IOHIDEventSystem (private symbols, declared in a bridging header)** (VERIFIED [S-SENS]).
- Create a client with `IOHIDEventSystemClientCreate(kCFAllocatorDefault)`.
- `IOHIDEventSystemClientSetMatching(client, {PrimaryUsagePage: 0xff00, PrimaryUsage: 0x0005})`.
- `IOHIDEventSystemClientCopyServices(client)`, then for each service: `IOHIDServiceClientCopyProperty(svc, "Product")` gives the sensor name; `IOHIDServiceClientCopyEvent(svc, 15 /*kIOHIDEventTypeTemperature*/, 0, 0)` and `IOHIDEventGetFloatValue(ev, 15 << 16)` give °C.
- Re-discover services every 60 s (5 s if events were missing).
- Voltage and current: page `0xff08`, usages `0x0003` / `0x0002`, event type 25.
- stats averages names starting with `pACC MTR Temp` / `eACC MTR Temp` (CPU), `GPU MTR Temp` (GPU) and `SOC MTR Temp` (SoC average and hottest). It rejects values ≥ 110 °C or < 0, and ignores M2 CPU readings outside 10–120 °C.

```c
// bridging header (C) — private IOKit symbols, as declared by stats/MenuMeters
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
int  IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef, CFDictionaryRef);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef, CFStringRef);
double IOHIDEventGetFloatValue(IOHIDEventRef, int32_t);
```

**Disk temperature:** NVMe SMART (§5.4).

**INFERRED recommendations:**
- Use `ProcessInfo.processInfo.thermalState` (`.nominal` / `.fair` / `.serious` / `.critical`, plus `thermalStateDidChangeNotification`) as the **public** signal for "Mac is hot" alerts.
- Use SMC / HID numbers only for display, and wrap them in "unsupported on this model" handling, since key names change every chip generation (see the lists above).
- Format with `Measurement(value:unit: .celsius)` and `MeasurementFormatter`, which follows the locale and the System Settings temperature unit, as the vendor does (VERIFIED-K).

### 5.9 Unresponsive apps

Covered in 05-performance §7.3:
- private `CGSEventIsAppUnresponsive` polling, or a `CGSRegisterNotifyProc(kCGSNotificationAppUnresponsive)` push;
- an AX messaging-timeout fallback;
- rule: unresponsive ≥ 5 s.

The vendor's CMM3 alert lists "Non-responsive applications" with **Quit**, **Force Quit All** and "Ignore ▾" → "Ignore For Now" / "Ignore Forever". VERIFIED [CMM3-MENU] `HungAppsAlert.strings` (re-fetched in this pass). The "App monitor" preference turns it on or off (VERIFIED [CMM3-PREF]).

**(added) How the vendor detected hangs, and the private API shape.**
- The CMM3 Menu imports `CGSMainConnectionID`, `CGSRegisterNotifyProc`, `CGSRemoveNotifyProc`, `CGSEventIsAppUnresponsive` and `GetProcessForPID` (§3.1.1). So it used the **window-server push notification**, not AX polling. VERIFIED (binary symbols).
- It also has code-built menu items "Ignore This Session" / "Ignore Listed Apps" (strings in the binary) for alerts that list several apps.
- Community headers declare the following. VERIFIED-X (https://github.com/sirg3/CGSInternal/blob/master/CGSInternal/CGSNotifications.h, …/CGSMisc.h; the same declarations in `NUIKit/CGSInternal` and `linearmouse/linearmouse`):
  - `kCGSNotificationAppUnresponsive = 750` and `kCGSNotificationAppResponsive = 751`;
  - the callback payload `CGSProcessNotificationData { minorVersion, majorVersion, length, cid, pid, psn }`;
  - `bool CGSEventIsAppUnresponsive(CGSConnectionID, const ProcessSerialNumber *)`;
  - `CGSEventSetAppIsUnresponsiveNotificationTimeout(CGSConnectionID, double)`.
- INFERRED for our build:
  - Register for 750/751 with `CGSRegisterNotifyProc` resolved via `dlsym` from SkyLight. The payload carries the **pid**, so the deprecated `GetProcessForPID` is not needed.
  - Start a 5 s timer on 750 and cancel it on 751.
  - Fall back to a 10 s AX ping (`AXUIElementCopyAttributeValue` with a 1 s messaging timeout) on frontmost GUI apps only if symbol lookup fails. The headers date from 2008 and can drift, so wrap everything in availability checks.

### 5.10 Trash size and Empty Trash

- **Vendor:**
  - CMM3 shows system Trash plus external-drive Trash against your limit, with "Overfilled", "%@ Used" and "Empty Trash".
  - The Menu total excludes app trash folders that the Trash Bins module counts.
  - VERIFIED [CMM3-H94], [CMM3-MENU].
  - X had a "Trash Monitor" (fixes in 4.13.6, VERIFIED [DM-X]).
- **Ours (INFERRED):**
  - Size = sum of `totalFileAllocatedSize` over `~/.Trash` plus `/Volumes/*/.Trashes/<uid>`.
  - Listing `~/.Trash` requires **Full Disk Access** on modern macOS. Without FDA, show "—" and a "Grant access" link. (Upgraded to VERIFIED-X: several independent tools report `ls ~/.Trash` → "Operation not permitted" until FDA is granted, e.g. https://github.com/viniciussouzao/tidymymac/blob/HEAD/docs/TROUBLESHOOTING.md and https://github.com/sodadata/tutorial-demo-project/blob/HEAD/README.md.)
  - Recompute on an FSEvents stream for `~/.Trash`, coalesced to 30 s, not by polling. (CMM3 used kqueue vnode dispatch sources instead (§3.1.1). Either works; FSEvents also covers `/Volumes/*/.Trashes/<uid>`.)
  - Empty: the agent (which has FDA) removes each child of the Trash folders with `FileManager.removeItem(at:)`, showing a progress bar. Items it can't remove (locked, owned by root) are reported, not forced. Optional fallback: the Apple Event `tell application "Finder" to empty trash` (needs `NSAppleEventsUsageDescription` plus Automation consent).
  - Always confirm first: "Permanently erase 7.4 GB in Trash?"

### 5.11 Sampling cadence and cost budget (INFERRED)

| Metric | Popover open | Popover closed (agent) | Mechanism when closed |
|---|---|---|---|
| CPU total / per-core | 1 s | — (only if a CPU alert is enabled: 10 s, 30 s window) | `host_processor_info` |
| Top processes | 2 s (detail page only) | none | libproc |
| Memory | 2 s | event-driven | `DispatchSource` memory pressure, plus a 60 s check for swap |
| Disk free | 5 s | 5 min, plus after large file events | `URLResourceValues` |
| SMART / temperatures | 10 s (detail) | 10 min | IOKit |
| Network rates | 1 s | none (session totals: 60 s) | IFLIST2 |
| Battery / UPS | event-driven | event-driven | `IOPSNotificationCreateRunLoopSource` |
| Bluetooth batteries | 30 s | 10 min (low-battery alert) | IORegistry HID, plus `pmset` every 30 min |
| Volumes | event-driven | event-driven | NSWorkspace mount notifications |
| Trash | on open | FSEvents, coalesced 30 s | FSEvents |
| Hung apps | — | push | CGS notify proc |

- Pause timers on `NSWorkspace.willSleepNotification` and resume them on `didWakeNotification` (stats does this for Bluetooth, VERIFIED [S-BT]).
- Use `DispatchSourceTimer` with leeway ≥ 10 % so the system can coalesce wakeups.
- Never spawn subprocesses while the popover is closed.

---

## 6. Notifications and alerts

### 6.1 How the vendor presents alerts

- **CMM3 / X style.** Custom alert views live in the Menu app: one nib per alert type (VERIFIED [CMM3-MENU]). INFERRED: they drop down from the status item as HUD panels.
- **Common controls** (VERIFIED [CMM3-MENU]):
  - primary action ("Launch CleanMyMac", "Empty Trash", "Uninstall Completely", "Force Quit All", "Free Up");
  - "View in CleanMyMac";
  - "Dismiss";
  - "Learn More…";
  - **"Ignore ▾"** with **Ignore For Now**, **Ignore Forever** and, for hardware conditions, **Remind in a Week**.
  - Progress, Done and Failure tabs appear inside the alert for Trash emptying and uninstalling. For example: "Uninstallation Failed" / "Some of the related items could not be removed."
- **Reset.** "Reset All Warnings" (gear menu) and "Reset Health and Monitoring" (Preferences) clear the ignore states. VERIFIED [CMM3-MENU], [CMM3-PREF].
- **5.x.** The Health Monitor posts macOS notifications even when the main app is closed. VERIFIED-K (01-overview §8). Release 5.6.0 added an **in-app Notification Center** (bell icon) for product news, offers and messages. VERIFIED-K (01-overview §6). For us it is just an "inbox" pattern; we have no marketing messages.

### 6.2 Alert catalogue: vendor evidence and our spec

Thresholds marked **ours** are INFERRED defaults. Every alert can be toggled in Settings › Notifications.

| ID (ours) | Trigger (ours) | Vendor evidence | Our actions (`UNNotificationAction`s) | Throttle / snooze |
|---|---|---|---|---|
| `disk.low` | Startup volume available < **min(50 GB, max(10 GB, 5 %))** ((corrected) capped at 50 GB, see §14.3); critical < max(3 GB, 2 %) | CMM3: "You are running out of disk space!" plus "Launch CleanMyMac"; threshold popup Don't Warn / 500 MB … 100 GB (VERIFIED [CMM3-MENU], [CMM3-PREF]). 5.x Health Monitor low-disk alert (VERIFIED-K). | **Clean Up…** (opens Smart Scan) · **Empty Trash (x GB)** if the Trash is large · Snooze 1 day | Once per 24 h per band; re-arm when available rises 20 % above the threshold (hysteresis) |
| `trash.large` | Trash > **5 GB** (setting: Off / 1 / 2 / 5 / 10 / 20 GB) | CMM3: "It's time to empty your Trash!", message that the Trash exceeded your limit, buttons "Empty Trash", "View in CleanMyMac", "Dismiss" (VERIFIED [CMM3-MENU]). X: overfilled Trash alerts (VERIFIED-K). | **Empty Trash** (always opens a confirmation in the popover first) · Remind in a Week | Once per 7 days unless size doubles |
| `app.trashed` | A `.app` appears in `~/.Trash` (FSEvents) | CMM3: "Uninstall applications correctly." with "Uninstall Completely" / "View in CleanMyMac" / "Dismiss" and progress / failure states (VERIFIED [CMM3-MENU]). Preference "Offer to correctly uninstall applications" (VERIFIED [CMM3-PREF]). 5.x Health Monitor offers it (VERIFIED-K 01 §8; 06-applications §2). | **Remove Leftovers…** (opens the Uninstaller leftovers view for that bundle ID; never auto-deletes) · Don't Ask for This App | Once per bundle ID |
| `memory.heavy` | Pressure **critical ≥ 60 s**, or warning ≥ 5 min with swap used > 50 % of RAM | CMM3: "Heavy memory usage", "RAM + Swap", "Almost full", suggesting you quit apps (VERIFIED [CMM3-MENU]). X 4.14.2 heavy-memory alert with quick release (VERIFIED [DM-X]). 5.x Health Monitor (VERIFIED-K). | **Show Top Apps** (opens the popover Memory page) · **Free Up** · Ignore for 1 h | Once per 2 h; re-arm after 10 min at normal |
| `app.hung` | A GUI app unresponsive ≥ **5 s** (re-check 2 s) | CMM3: "Non-responsive applications"; force quit or wait; "Quit", "Force Quit All", Ignore For Now / Forever (VERIFIED [CMM3-MENU]). 5.x Health Monitor (VERIFIED-K). | **Force Quit** (destructive) · **Wait** · Never for This App | Once per incident per pid |
| `cpu.heavy` (optional, default off) | One app > 80 % of a core for 2 min, or total > 90 % for 5 min | X 4.11 "unusual activity spikes" (VERIFIED [DM-X]); no explicit alert found (GAP) | **Show App** · Quit · Ignore App | Once per app per 6 h |
| `disk.smart` | NVMe `critical_warning ≠ 0`, or media errors rising | CMM3: "Critical S.M.A.R.T diagnostics!" (VERIFIED [CMM3-MENU]) | **Learn More** (in-app page: back up now; Time Machine link) · Remind in a Week | Weekly |
| `disk.life` | SSD life ≤ 10 % | CMM3: "Low SSD life!", tooltip "%@ SSD life is %li%%" (VERIFIED [CMM3-MENU]) | Learn More · Remind in a Week | Weekly |
| `disk.hot` | NVMe temperature > 70 °C for ≥ 5 min, or `thermalState ≥ .serious` | CMM3: "High disk temperature!", tooltip "%@ temperature exceeds %@" (VERIFIED [CMM3-MENU]) | Show Top Disk Apps · Ignore Today | Daily |
| `battery.failing` | `BatteryHealthCondition` ∈ {Check Battery, Permanent Failure} or health < 80 % (laptop only) | CMM3: "Your battery is failing!" (VERIFIED [CMM3-MENU]); 5.x Warning band ≤ 79 % (VERIFIED-K) | Learn More · Remind in a Week · Ignore Forever | Weekly |
| `battery.drain` (laptop) | Discharge power > 2 × the 30-min median for 3 min | X 4.12.4 drain alert; 4.13.6 shows time to empty and offers Display Dimming and Low Power Mode (VERIFIED [DM-X]) | **Show Energy Users** · **Low Power Mode** (via helper) · Dim Display | Once per discharge session |
| `ups.onBattery` (mini) | UPS source switches to "UPS Power" | (ours; stats reads UPS state, VERIFIED [S-BAT]) | Show Status · (time-sensitive) | Each transition |
| `bt.lowBattery` | Connected device < **20 %** (setting 10 / 15 / 20 / 30) | X 4.14.0 low battery alerts for Bluetooth devices (VERIFIED [DM-X]); 5.x red under 20 % (VERIFIED-K) | Dismiss | Once per device per charge cycle (re-arm above 50 %) |
| `updates.available` | Updater finds ≥ 1 non-ignored update (daily check) | X 4.11.4 and 4.14.0: informative update notifications listing top outdated apps (VERIFIED [DM-X]) | **Review Updates** · Update All (opens Updater) · Later | Once per day; aggregate into one notification with app names in the body |
| `threat.found` | Real-time or background scan finds malware or a PUA | Malware Monitor posts a notification (VERIFIED-K 04-protection §1) | **Review** · **Remove** (opens the app; never silent) | Each finding; time-sensitive |
| `reminder.cleanup` | No Smart Scan for N days (default 7) | Weekly cleanup reminders in X Menu and 5.x Settings › Menu › Recommendations (VERIFIED-K) | **Scan Now** · Remind Me Tomorrow · Turn Off | Per schedule (02-smart-care §6.2) |
| `drive.connected` (optional) | External volume mounted with > 1 GB Trash or junk | X: cluttered external drives alert plus External Drives "clean junk" (VERIFIED-K, [DM-X]) | Clean Drive… · Eject | Once per volume UUID per 7 days |
| `monitor.off` | Our agent is disabled or `.requiresApproval` | Vendor KB: Menu won't open if background disallowed (VERIFIED-K) | Banner in the main app (not a notification) | — |

### 6.3 Implementation (INFERRED, built on VERIFIED stats patterns)

- **Hysteresis.** stats' `NotificationsWrapper.checkDouble` fires only after **N consecutive** readings beyond the threshold (default `consecutive: 2`). It removes the delivered notification once the value recovers, and uses stable IDs `Stats_<module>_<id>` so a new post replaces the old. VERIFIED [S-NOTIF]. Do the same with request identifiers `alert.<id>.<subject>`.
- **Authorization.** Request `[.alert, .sound, .badge]` **once**, from onboarding (01-overview §9.2). stats calls `requestAuthorization` before every post (VERIFIED [S-NOTIF]); don't copy that.
- **Categories and actions.** Register once at agent launch:

```swift
import UserNotifications

enum AlertCategory: String { case diskLow, memoryHeavy, appHung, appTrashed, updates, threat, reminder, generic }

func registerCategories() {
    let c = UNUserNotificationCenter.current()
    func a(_ id: String, _ title: String, _ opts: UNNotificationActionOptions = []) -> UNNotificationAction {
        UNNotificationAction(identifier: id, title: title, options: opts)
    }
    c.setNotificationCategories([
        UNNotificationCategory(identifier: AlertCategory.diskLow.rawValue,
            actions: [a("cleanup", "Clean Up…", .foreground), a("emptyTrash", "Empty Trash"), a("snooze1d", "Snooze 1 Day")],
            intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: AlertCategory.appHung.rawValue,
            actions: [a("forceQuit", "Force Quit", .destructive), a("wait", "Wait"), a("never", "Never for This App")],
            intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: AlertCategory.memoryHeavy.rawValue,
            actions: [a("topApps", "Show Top Apps"), a("freeUp", "Free Up"), a("ignore1h", "Ignore for 1 Hour")],
            intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: AlertCategory.reminder.rawValue,
            actions: [a("scanNow", "Scan Now", .foreground), a("tomorrow", "Remind Me Tomorrow"), a("off", "Turn Off")],
            intentIdentifiers: [], options: []),
        // … updates, threat, appTrashed, generic
    ])
}

func post(_ id: String, category: AlertCategory, title: String, body: String,
          userInfo: [String: Any] = [:], timeSensitive: Bool = false) {
    let content = UNMutableNotificationContent()
    content.title = title; content.body = body; content.userInfo = userInfo
    content.categoryIdentifier = category.rawValue
    content.threadIdentifier = category.rawValue            // groups in Notification Center
    content.sound = .default        // .defaultCritical needs the Critical Alerts entitlement; don't use it
    if timeSensitive { content.interruptionLevel = .timeSensitive } // needs time-sensitive entitlement
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
}
```

- **Delegate.**
  - The agent sets `UNUserNotificationCenter.current().delegate`.
  - In `willPresent`, return `[.banner, .list, .sound]` so alerts show even though the agent is "active".
  - In `didReceive`, route action IDs. Most open `ourapp://…` deep links. `forceQuit`, `freeUp` and `emptyTrash` run in the agent, which asks the helper where root is needed.
  - **Destructive actions from a banner must still be safe:** "Empty Trash" from a notification brings up a confirmation sheet in the popover. Force Quit is allowed directly, since the user picked a destructive action on a named app.
- **Scheduled reminders without a running process.** Use `UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 10, weekday: 2), repeats: true)` for the weekly cleanup reminder. It fires even if the agent is not running. Cancel or reschedule it after every completed scan.
- **Focus and noise.**
  - Reserve `.timeSensitive` for `threat.found`, `ups.onBattery` and critical disk-low. That requires the `com.apple.developer.usernotifications.time-sensitive` entitlement.
    - VERIFIED: `UNNotificationInterruptionLevel.timeSensitive` is macOS 12.0+, and the user can turn time-sensitive breakthrough off (https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive).
    - VERIFIED-X: the entitlement key appears in about 826 public `.entitlements` files (GitHub code search). Apple's entitlements index lists Critical Alerts and filtering keys but no page for this one, so add it through Xcode's "Time Sensitive Notifications" capability rather than by hand. INFERRED.
  - `UNCalendarNotificationTrigger` is macOS 10.14+ and the system delivers it at the matching date. VERIFIED (https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger).
  - Everything else is `.active`.
  - Add a global "Pause alerts" (1 h / until tomorrow / until re-enabled) in the status-item right-click menu and in Settings.
- **Ignore store.** `[alertID: IgnoreState]` in the App Group defaults, where `IgnoreState` is `.untilRecovered | .until(Date) | .forever | .forSubject(Set<String>) | .thisSession` (added: CMM3 had "Ignore This Session", §3.1.1; clear it at agent launch). Add a **"Reset All Warnings"** button in Settings › Notifications. That's a generic phrase, but the vendor also used it, so consider "Reset ignored alerts".

---

## 7. Settings: Monitor and Notifications

### 7.1 Vendor

- **CMM3 Preferences › Menu** (VERIFIED [CMM3-PREF]):
  - "CleanMyMac 3 Menu" ON/OFF;
  - "Warn when free space is less than:" (Don't Warn, 500 MB, 1, 2, 3, 5, 10, 15, 20, 30, 50, 100 GB);
  - "Notify when Trash size exceeds:" (Don't Notify plus sizes);
  - "Uninstaller: Offer to correctly uninstall applications";
  - "App monitor: Notify about hung applications";
  - "Reset Health and Monitoring: Reset All Warnings".
  - Features are disabled when running from a disk image.
- **X Preferences:** Menu tab plus a **Notifications** tab (alert toggles, reminder frequency), and an **Assistant** tab (recommendations; also the Ukrainian theme toggle in 4.10.4). VERIFIED-K (02-smart-care §6.1, §8; 01-overview §10) and [DM-X].
- **5.x Settings › Menu:** **Enable Menu** and **Recommendations**. That's all that was verified. VERIFIED-K (01-overview §10). Whether 5.x has a Notifications tab is a GAP.

### 7.2 Ours (INFERRED): a superset that stays small

**Settings › Monitor**
- [x] Run monitor at login. Status shown: Enabled / Needs approval → "Open Login Items…".
- [x] Show in menu bar. Menu bar shows: Icon · Free disk · Memory pressure · CPU % · Network ↑↓.
- Cards (drag to reorder, toggle): Protection · Storage · Memory · CPU · Network · Battery/UPS · Devices · Drives · Recommendation.
- Units: network in bytes or bits.
- [ ] Show public IP address (contacts \<endpoint\>).
- [x] Recommendations in the monitor.

**Settings › Notifications**
- Master switch, with the system authorization status and an "Open Notification Settings" link.
- Per-alert rows: toggle plus threshold control (popup) plus "Ignored items (n) › Manage".
- Cleanup reminder: Off / every 3 days / weekly (default) / every 2 weeks / monthly, plus time of day (shared with 02-smart-care).
- Quiet hours (follow Focus by default).
- "Reset ignored alerts".

Persist in `UserDefaults(suiteName: "group.com.our.app")`. Keys: `monitor.enabled`, `monitor.showStatusItem`, `monitor.statusText`, `monitor.cards`, `alerts.<id>.enabled`, `alerts.<id>.threshold`, `alerts.ignore`, `reminder.interval`, `reminder.hour`, `privacy.publicIP`.

---

## 8. Assistant, Mac Health and AI

### 8.1 CleanMyMac X Assistant (2018–2024)

- Introduced with X in 2018; overhauled in **4.10.0** (VERIFIED [DM-X], 01-overview §3):
  - lives in the app's **upper-right corner** and expands to a "full view" (4.10.4 fixed its animation);
  - "timely Recommendations" to keep the Mac in shape;
  - **extended statistics** of your CleanMyMac use;
  - recommendations mirrored in the **Menu**, manageable in Preferences.
- Behavior (VERIFIED-K, 02-smart-care §6.1, https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-assistant): personalized suggestions and "scheduled maintenance" reminders. Yellow buttons mark the most relevant tasks. It can be silenced in Preferences › Assistant.
- INFERRED: it is a **rule engine**, not AI. Conditions such as last scan date, junk size, Trash size, outdated apps, unused apps and threats map to a call to action.

### 8.2 CleanMyMac 5 Assistant and Mac Health (2024+)

- An **Assistant** entry sits at the bottom-left of the 5.0 sidebar. VERIFIED-K (01-overview §5.1 citing MacStories, 9to5Mac, MacObserver).
- **Mac Health** bands: Excellent · Good · Fair · Requires Attention · Critical.
  - Inputs: free disk space, threats, battery health, system load, other HW and system metrics, whether FDA is granted, whether a recent scan exists.
  - Recommendations carry one-click actions, e.g. "Allow Access" for FDA.
  - VERIFIED-K (01-overview §5.2, §11, https://macpaw.com/support/cleanmymac/knowledgebase/mac-health, …/full-disk-access).
- A reviewer felt the score mostly tracked scan recency. VERIFIED-K (02-smart-care §5).
- **My Activity** (5.4.0) shows the Health Score and recommendations alongside totals: space cleaned, threats, "time saved". VERIFIED-K (01-overview §5.2).
- The exact 5.7 placement (standalone Assistant vs. folded into My Activity) is a GAP (01-overview §14).

### 8.3 Smart Insights: the AI feature (5.2.6, Oct 2025)

- Release notes say Smart Insights is powered by Apple Intelligence and gives helpful information about **system files**: what an item is, why it matters and whether you need it. VERIFIED [DM-5].
- Details (VERIFIED-K, 01-overview §5.2; https://macpaw.com/news/introducing-smart-insights):
  - an info button next to unfamiliar items in Cleanup, Protection, Performance and Applications;
  - runs **on-device** with Apple's Foundation Model;
  - requires Apple Silicon, macOS 26 Tahoe and Apple Intelligence enabled.
- **No chat or conversational assistant exists inside CleanMyMac** in anything we could read (release notes to 5.3.1, the sibling-verified KB through 5.7.1). Negative finding; the 5.4–5.7 notes were only available via 01-overview's summary.
- MacPaw's agent-style assistant is a **separate product, Eney**: a "proactive AI assistant for Mac" that works across apps and connectors. In Aug 2026 MacPaw announced a local version built on Liquid AI models plus its own on-device inference stack. VERIFIED-X [ENEY].

### 8.4 What to build: our "Advisor" (INFERRED)

#### 8.4.1 Rule-based recommendations (all macOS versions)

| Rule ID | Condition | Card text (ours) | Action | Cooldown after dismiss |
|---|---|---|---|---|
| `scan.stale` | No Smart Scan in 14 days | "It's been 2 weeks since your last checkup" | Run Smart Scan | 7 d |
| `trash.big` | Trash > 2 GB | "Trash is holding 7.4 GB" | Empty Trash | 7 d |
| `fda.missing` | FDA not granted | "Grant Full Disk Access for complete scans" | Open Privacy settings | 3 d |
| `helper.approval` | Helper `.requiresApproval` | "Allow the helper to run maintenance tasks" | Open Login Items | 3 d |
| `updates.n` | N app updates | "3 apps have updates" | Review Updates | 1 d |
| `apps.unused` | Apps not opened in 180 days, total > 2 GB | "5 apps unused for 6 months (4.1 GB)" | Review in Uninstaller | 30 d |
| `downloads.old` | ~/Downloads has > 2 GB older than 90 days | "Old downloads take 3.2 GB" | Review Downloads | 30 d |
| `swap.high` | Swap > 50 % of RAM for 1 h | "Your Mac is swapping, close heavy apps" | Show Top Apps | 1 d |
| `disk.lowSoon` | Free-space trend crosses the threshold within 14 days (linear fit of daily samples) | "At this rate you'll run low in ~10 days" | Clean Up | 7 d |
| `bt.low` | Device < 20 % | "Magic Mouse at 12 %" | — | until charged |
| `threat.db` | Signature DB older than 14 days | "Protection database is out of date" | Update now | 1 d |
| `backup.none` | `tmutil latestbackup` empty or older than 14 days (read-only) | "No recent Time Machine backup" | Open Time Machine settings | 14 d |

- Store dismissals in the App Group. Show at most **one** card in the popover and up to 5 in the main app's Health view.
- The score deductions in 01-overview §11 double as recommendations.

#### 8.4.2 Optional on-device "Explain" (macOS 26+, Apple Intelligence)

This is our Smart-Insights-style feature, offered on items in Cleanup, Startup items, processes and alerts.

```swift
import FoundationModels   // macOS 26+

@Generable struct ItemInsight {
    @Guide(description: "One sentence: what this item is and which app or system component owns it")
    var whatItIs: String
    @Guide(description: "Why it exists / what happens if removed")
    var impact: String
    @Guide(description: "safe, caution, or keep")
    var verdict: String
}

func explain(path: String, facts: String) async throws -> ItemInsight? {
    guard case .available = SystemLanguageModel.default.availability else { return nil } // hide button otherwise
    let session = LanguageModelSession(instructions: """
        You explain macOS files and processes to non-experts. Be factual and brief. \
        If unsure, say so and choose "caution". Never recommend deleting user documents.
        """)
    let prompt = "Item: \(path)\nFacts: \(facts)"   // facts = bundle ID, owner app, size, age, signer
    return try await session.respond(to: prompt, generating: ItemInsight.self).content
}
```

- **Guardrails:**
  - The model's `verdict` **never** changes what is selected or deleted. Our deterministic safety tiers (03-cleanup) decide.
  - Show a "Generated on device" label.
  - Cache answers per (path pattern, bundle ID).
  - Keep the hand-off small. The context window is **4096 tokens per `LanguageModelSession`**, counting input and output together. VERIFIED (TN3193: https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window). Read `SystemLanguageModel.default.contextSize` at runtime instead of hard-coding it. The property is documented with `@backDeployed(before: macOS 26.4)` (https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize). VERIFIED.
- **Availability:** hide the button when the model is unavailable (`.unavailable(.deviceNotEligible / .appleIntelligenceNotEnabled / .modelNotReady)`). (Upgraded to VERIFIED: these are exactly the three documented `SystemLanguageModel.Availability.UnavailableReason` cases, macOS 26.0+: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason.)
- **API shape** (VERIFIED from the docs JSON):
  - `@Generable(description:)` and `@Guide(description:)` are macros.
  - `LanguageModelSession.init(model: = .default, tools: = [], instructions:)` takes an `@InstructionsBuilder` closure.
  - `respond(to:generating:includeSchemaInPrompt:options:)` returns `Response<Content>` with `.content`.
  - `Tool` is a protocol with `name`, `description` and `call(arguments:)`.
  - INFERRED: a plain-string `instructions:` overload is used in Apple's samples. If the SDK rejects the string literal in the code above, wrap it as `LanguageModelSession { "…" }`.
  - The macOS 27 SDK adds dynamic profiles (`init(profile:history:)`), which we don't need.

#### 8.4.3 Optional "Ask your Mac" chat (stretch; opt-in)

- A small chat sheet in the main app (not the popover) backed by `LanguageModelSession` with **read-only tools** (`Tool` protocol): `getStorageSummary`, `getTopProcesses`, `getMemory`, `getBatteryHealth`, `listStartupItems`, `getLastScan`.
- The model may **suggest** an action. Execution always goes through the normal UI with its confirmation, e.g. "Open Startup Items with 'Dropbox Helper' highlighted".
- This goes beyond the vendor (whose chat-style assistant is a different product) and should ship disabled by default.

---

## 9. Implementation blueprint (INFERRED)

### 9.1 Targets and bundle

| Target | Type | Key settings |
|---|---|---|
| `OurApp` | macOS app | Developer ID, hardened runtime, **not sandboxed** (needs AppleSMC, IORegistry, other apps' caches, FDA). App Group `group.com.our.app`. |
| `OurMonitor` | macOS app embedded at `Contents/Library/LoginItems/` | `LSUIElement = YES`; same App Group; `NSBluetoothAlwaysUsageDescription`; `NSLocationUsageDescription` (Wi-Fi name); `NSAppleEventsUsageDescription` (optional Finder Trash); optional time-sensitive notifications entitlement. Registered via `SMAppService.loginItem(identifier:)`. |
| `OurHelper` | root daemon (`SMAppService.daemon(plistName:)`) | Allow-listed XPC API: `purge`, `setLowPowerMode`, `flushDNS`, … (05-performance) |
| `OurKit` | framework / Swift package | Samplers (§5), models, alert engine, recommendation engine; shared by app and monitor |

### 9.2 Status item and panel skeleton

```swift
import AppKit
import SwiftUI

@MainActor final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: .init(x: 0, y: 0, width: 360, height: 520),
                        styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                        backing: .buffered, defer: true)
        p.isFloatingPanel = true; p.level = .popUpMenu
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.backgroundColor = .clear; p.hasShadow = true; p.isOpaque = false
        p.contentView = NSHostingView(rootView: MonitorRootView(model: model))
        return p
    }()
    private var outsideClick: Any?
    let model: MonitorModel

    init(model: MonitorModel) {
        self.model = model; super.init()
        item.button?.image = NSImage(named: "StatusGlyph")      // our original template image
        item.button?.image?.isTemplate = true
        item.button?.target = self; item.button?.action = #selector(toggle(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        panel.isVisible ? close() : open()
    }
    private func open() {
        guard let button = item.button, let win = button.window else { return }
        let r = win.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: min(r.midX - size.width / 2, (win.screen?.visibleFrame.maxX ?? r.maxX) - size.width - 8),
                                     y: r.minY - size.height - 6))
        model.setLive(true)                                     // switch samplers to live cadence
        panel.orderFrontRegardless()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }
    private func close() {
        panel.orderOut(nil); model.setLive(false)
        if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
    }
    private func showContextMenu() { /* Open App, Settings…, Pause Alerts ▸, Quit Monitor */ }
}
```

Also handle `Esc` to close and VoiceOver focus on open. Re-anchor the panel on `NSApplication.didChangeScreenParametersNotification`.

### 9.3 Model and engines

- `MonitorModel` (`@Observable`, MainActor) holds the latest `SystemSnapshot` structs.
- `SamplerHub` (an actor) owns timers and event sources (§5.11) and switches between `.live` and `.background` profiles.
- `AlertEngine` (an actor) is fed snapshots and events. It evaluates rules with hysteresis, consults the ignore store and posts notifications (§6.3). It also writes the activity log (01-overview §11: My Activity).
- `RecommendationEngine` is a pure function `(Snapshot, History, Settings) -> [Recommendation]`, unit-testable with fixtures.
- Ring buffers hold 120 samples per sparkline metric, in memory only.

### 9.4 Permissions summary

| Capability | Needed for | How we ask |
|---|---|---|
| Notifications | all alerts | onboarding pre-prompt → `requestAuthorization` |
| Full Disk Access | Trash size, mail junk, some caches | onboarding step with a deep link (01-overview §9) |
| Bluetooth | device batteries via IOBluetooth / CoreBluetooth | on first opening of the Devices card |
| Location (When In Use) | Wi-Fi SSID | on first opening of the Network detail page |
| Automation (Finder) | optional Empty Trash fallback | only if FileManager removal fails |
| Login Items / background | monitor at login | `SMAppService` + banner when `.requiresApproval` |
| Admin (helper) | Free Up memory via `purge`, Low Power Mode toggle | lazily, on first use (01-overview §9) |

---

## 10. Edge cases and test matrix (INFERRED)

| Scenario | Expected |
|---|---|
| Mac mini, no battery, no UPS | No Battery card, no battery alerts, no "battery" deductions in the health score |
| Mac mini with a USB UPS | UPS card; `ups.onBattery` alert on transition; time to empty if reported |
| Ethernet primary, Wi-Fi off | Network card shows "Ethernet · 1 Gb/s" (or 10 Gb/s on 10GbE minis); no Location prompt |
| Location denied | SSID shown as "Wi-Fi" plus an "Allow to show network name" link; never `<redacted>` |
| VPN active (utun) | Primary interface may become `utun*`. Show the underlying physical interface's throughput (stats can halve VPN double-counting; VERIFIED [S-NET] "VPNMode") |
| Bluetooth off or denied | Devices card shows "Bluetooth is off" / "Allow Bluetooth access"; no polling |
| AirPods in the case | L / R / Case percentages via `pmset -g accps` or the cache; hide parts reporting 0 or missing |
| External drive busy on eject | Error with the dissenting process name; no force-unmount unless the user confirms "Force Eject" (`kDADiskUnmountOptionForce`) |
| FDA missing | Trash size "—" plus a grant link; Health "Requires Attention" deduction; no crash on EPERM |
| Sleep / wake | Timers paused; first post-wake network delta discarded (counter jump guard); BLE rescan |
| Fast user switching | Each user has their own agent; alerts post only for the console user (`SCDynamicStoreCopyConsoleUser`) |
| Display reconfigured or menu bar hidden (full-screen app) | Panel re-anchors; `.fullScreenAuxiliary` lets it show over full-screen apps |
| Notch or crowded menu bar | Status item may be hidden by the system. Offer a global hotkey (default off) to open the monitor |
| macOS 14 vs 26 | Liquid Glass only on 26+; Foundation Models features hidden below 26 or without Apple Intelligence |
| New chip generation (unknown SMC keys) | CPU temperature row hidden; thermal state still shown |
| 8 GB mini under pressure | Memory alerts honor hysteresis; Free Up offered only when pressure ≥ warning (05-performance §4.1) |
| Agent killed by the user | Not resurrected until the next login or the main app's "Start monitor" (no unconditional KeepAlive) |
| Locale with °F and comma decimals | MeasurementFormatter and ByteCountFormatter handle it |

---

## 11. Naming and originality (INFERRED)

- Do **not** call the menu-bar app "The Menu", "CleanMyMac Menu" or "Health Monitor". Don't use MacPaw's tile illustrations, 3D icons, gradients or copy.
  - Suggested names: **Monitor** (UI) and **Sentinel** (alert engine). "Advisor" or "Insights" for the Assistant, not "Assistant" or "Smart Insights". "Explain" for the on-device AI button.
- Write alert copy in plain, original language. Short generic labels ("Empty Trash", "Force Quit", "Free Up") are standard macOS vocabulary and fine.
- Visual language: our own palette, our own glyph, and system SF Symbols for metric icons (`cpu`, `memorychip`, `internaldrive`, `network`, `battery.75`, `keyboard`, `externaldrive`, `shield`).

---

## 12. Gaps and open questions

Status after the fact-check pass is in **bold brackets**.

1. The exact 5.x Menu tile list, order, labels and detail-view contents (macpaw.com blocked in this session; only sibling-verified summaries). **[Still open. macpaw.com was still blocked (DNS), and no mirror of the 5.x KB text or of the 5.x Menu bundle's strings was found on GitHub. Next step: install the 5.7.1 trial on the Mac mini and record the Menu.]**
2. Whether 5.x has a **Notifications** settings tab with per-alert thresholds, and the default thresholds of each 5.x alert. CMM3 had choices but no recorded defaults. **[Partly answered for CMM3 only. CMM3's free-space threshold is computed per volume (`defaultThresholdForRootDiskVolume`) with a "close to threshold" de-bounce (§3.1.1). 5.x remains open. The 5.x Menu and Health Monitor keep their own defaults domains (§3.1), so `defaults read com.macpaw.CleanMyMac5.HealthMonitor` on a test Mac would reveal the threshold keys.]**
3. The 5.x Network tile fields (IP? Wi-Fi name? speed test still present?). **[Still open.]**
4. Whether 5.x can show text (CPU %, free space) in the menu bar next to the icon. **[Still open.]**
5. Whether 5.x still surfaces Connected Devices "connect/disconnect" (X 4.13) and External Drives "clean junk". **[Still open for 5.x. The X 4.13.0 wording ("connect or disconnect", "clean junk from it right on the spot") was re-VERIFIED in the DevMate notes. 13-helpcenter's devices-monitoring summary mentions only display (up to 3 devices; red under 20 %), not connect/disconnect.]**
6. Release notes for 5.4–5.7.1 beyond the headlines in 01-overview (the S3 appcast stops at 5.3.1; later feeds are on `updates.cleanmymac.com`, which is blocked here). **[Still open. The S3 appcast was re-fetched and still ends at 5.3.1 (28 Jan 2026). updates.cleanmymac.com and updates.devmate.com both fail DNS here, and a bucket listing is refused (403). The 5.0.0–5.3.1 notes were re-read: no Menu or notification items.]**
7. Exact Mac Health score thresholds and battery band semantics (01-overview's "≤ 10 % Critical" may refer to charge). **[Not verifiable. Downgraded to INFERRED (§4.9). Our reading: health < 80 % → Warning; charge ≤ 10 % → Critical.]**
8. Whether the 5.x Assistant still exists as a separate sidebar entry in 5.7 or has moved into My Activity. **[Still open. Same conclusion as 01-overview §14.]**
9. Whether the Health Monitor uses the CGS hung-app notification or AX polling (resource samples suggest it is fairly heavy; [PROC-OBS]). **[Answered for CMM3: it used the CGS notify proc plus `CGSEventIsAppUnresponsive` (binary imports, §3.1.1 and §5.9). INFERRED for 5.x.]**
10. JSON key names of `networkQuality -c` on macOS 26/27, and `rusage_info_v6` energy fields. Verify on device. **[Answered from Apple's man pages (macOS 14/15/26/27) and the xnu/SDK headers (§5.3, §5.5). The only on-device check left is the bits-vs-bytes unit of `dl_throughput`, where the macOS 14 and 15+ man pages disagree.]**

---

## 13. Sources

**MacPaw-shipped files and release notes (fetched)**
- CleanMyMac 3 Help, "CleanMyMac 3 Menu": https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html
- CleanMyMac 3 Menu preferences strings: https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/en.lproj/CMMenuPreferencesViewController.strings
- CleanMyMac 3 Menu.app resources: https://github.com/auspham/mac-essential/tree/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents (CodeResources, `Resources/Base.lproj/Health.strings`, `Resources/Base.lproj/Localizable.strings`, `Resources/en.lproj/*Alert.strings`, `*Indicator.strings`, `MainMenu.strings`)
- CleanMyMac X release notes 4.10–4.15.8: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html
- CleanMyMac X release notes 4.10–4.12.2: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- CleanMyMac 5 release notes 5.0.0–5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
- CleanMyMac 5 release notes 5.0.0–5.2.5: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html
- Appcasts: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml , https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml

**Packaging and footprint**
- Homebrew cask (5.7.1): https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/cleanmymac.rb
- X 4.15.8 cask: https://github.com/letuanhai/homebrew-tap/blob/HEAD/Casks/cleanmymac-x.rb
- Fleet uninstall script: https://github.com/fleetdm/fleet/blob/main/ee/maintained-apps/inputs/homebrew/scripts/cleanmymac-uninstall.sh
- Agent LaunchDaemon plist backup: https://github.com/MYunFeiYang/zbookpowerg7/blob/HEAD/docs/backups/cleanmymac5-residue-2026-09-18/com.macpaw.CleanMyMac5.Agent.plist
- X bundle layout (paths only): https://github.com/shwang1114/InjectLib , https://github.com/h4rk8s/Surge/blob/HEAD/Custom/Reject.list
- Log folders: https://github.com/andreychev/dotfiles/blob/HEAD/.config/mole/operations.log
- Process observations: https://github.com/OpenAgentsInc/openagents (docs/kev/measurements/data/candidate-4b/http-eager-quiet-host.json; docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-*.txt), https://github.com/francescotinti/php-rust (wp176/wp181/wp182 harness outputs)
- Respawn note: https://github.com/ArshiaEcho/janitor/blob/HEAD/plugins/janitor/skills/janitor-device/references/fix-blocks-mac.md
- KB title "menu-no-elements" (via citation): https://github.com/venomousmoog/lintel/blob/HEAD/docs/research/2026-07-06-feasibility-findings.md

**Open source implementation references (fetched)**
- exelban/stats: https://github.com/exelban/stats
  - `Modules/RAM/readers.swift`, `Modules/CPU/readers.swift`, `Modules/Net/readers.swift`, `Modules/Battery/readers.swift`, `Modules/Bluetooth/readers.swift`, `Modules/Disk/readers.swift`, `Modules/Disk/header.h`, `Modules/Disk/preview.swift`, `Modules/Sensors/readers.swift`, `Modules/Sensors/reader.m`, `Modules/Sensors/bridge.h`, `SMC/smc.swift`, `Kit/module/notifications.swift`, `Kit/module/popup.swift`, `Kit/helpers.swift`, `Kit/plugins/SystemKit.swift`
- Mac Sai (menu-bar process, throttled alerts, 30-day dismissals): https://github.com/iliyami/MacSai

**AI context**
- Eney (MacPaw's separate assistant): https://github.com/dpawlan/ai-assistant-benchmark/tree/main/data/agents/eney ; TechCrunch, "MacPaw taps Liquid AI to offer on-device inference…", 2026-08-05 (as quoted in https://github.com/guzus/ai-research-arm/blob/HEAD/research/rss/2026-08-05.md)

**Sibling reports relied on (VERIFIED-K):** `01-overview.md` (§5.2 The Menu row, §8 background components, §10 settings, §11 health), `02-smart-care.md` (§2, §6 reminders), `04-protection.md` (§1 monitor), `05-performance.md` (§4.1 Free Up RAM, §7 heavy and hung apps), `06-applications.md` (§2 trash-drop uninstall, Updater notifications).

---

## 14. Fact-check additions: things the first pass missed

Most additions were placed inline and are marked "(added)". This section lists them in one place and adds the items that did not fit anywhere else.

### 14.1 Inline additions (index)

| Topic | Where | Label |
|---|---|---|
| Homebrew installs `/Applications/CleanMyMac.app` (renamed from `CleanMyMac_5.app`) | §3.1 | VERIFIED |
| Agents respawn because LoginItems get relaunched on crash or non-zero exit; no KeepAlive needed | §3.1, §3.2 | VERIFIED (Apple docs) |
| Menu and Health Monitor each have their own defaults domain, Caches and HTTPStorages | §3.1 | VERIFIED-X |
| Health Monitor is a login item nested under the Menu (BTM) | §3.1 | VERIFIED-K (10-internals) |
| Mac App Store edition: Menu has no disk health or temperature | §3.1 | VERIFIED-K |
| What the CMM3 Menu binary links against (CGS hang detection, memory-pressure sources, purgeable SPI, vnode Trash watch, free-space hysteresis) | §3.1.1 | VERIFIED (binary symbols) |
| `MenuBarExtra`-only apps are terminated when the extra is removed; handle a hidden status item | §4.1 | VERIFIED + INFERRED |
| X storage "Free Up" starts Smart Scan at once | §4.5 | VERIFIED-K |
| Pressure sysctl semantics (Urgent → Warn, `CTLFLAG_MASKED`); `xsw_usage` fields; swapins/swapouts source | §5.1 | VERIFIED (xnu) |
| Third core type on the newest chips; iterate `hw.nperflevels` | §5.2 | VERIFIED [S-CPU] + INFERRED |
| `rusage_info_v6` energy fields across SDKs 13.3 → 26.5 | §5.3 | VERIFIED (headers) |
| DiskArbitration unmount option values; `kDADiskUnmountOptionWhole` before eject | §5.4 | VERIFIED (SDK) |
| `networkQuality` flags and keys per macOS version; bits vs bytes | §5.5 | VERIFIED (man pages) |
| Battery health-condition values; `kIOPSTimeRemainingUnlimited`; UPS via `IOPSGetProvidingPowerSourceType`; `pmset -u` UPS thresholds; `powermode` vs `lowpowermode` on a Mac mini | §5.6 | VERIFIED / VERIFIED-X |
| CGS unresponsive-app constants (750 / 751) and payload with pid | §5.9 | VERIFIED-X |
| Time-sensitive level macOS 12+; calendar triggers macOS 10.14+ | §6.3 | VERIFIED |
| Foundation Models: 4096-token window, `contextSize`, UnavailableReason cases, API shape | §8.4.2 | VERIFIED |

### 14.2 Extra alerts and states worth adding to our catalogue (§6.2)

All of these are INFERRED design decisions unless marked otherwise.

| ID (ours) | Trigger | Why |
|---|---|---|
| `ups.low` (mini) | UPS on battery **and** level ≤ (`pmset -g ups` haltlevel + 10 %), or time remaining ≤ haltremain + 5 min | Warn before macOS's own emergency shutdown. The halt thresholds are VERIFIED in `pmset(1)` (§5.6). |
| `thermal.serious` | `ProcessInfo.thermalState` ≥ `.serious` for ≥ 2 min (`thermalStateDidChangeNotification`, no polling) | A public "Mac is hot" signal. CMM3 only had a disk-temperature alert (VERIFIED [CMM3-MENU]). On a mini this usually means blocked airflow. |
| `notifications.denied` | `UNUserNotificationCenter.getNotificationSettings()` shows `.denied`, or `alertSetting == .disabled` | Without it every alert above silently fails. Show a banner in Settings › Notifications and in the popover header, not a notification. |
| `monitor.iconHidden` | Status item not visible (§4.1) | The agent keeps running, but users can't reach it. Offer the hotkey and a "Show icon" fix. |
| `helper.outdated` | The helper's XPC version is lower than the app's | Free Up and Low Power Mode actions would fail. Prompt a reinstall (05-performance helper). |

### 14.3 Settings the vendor implies but we must decide (INFERRED)

- **Per-alert ignore granularity.** CMM3 had four kinds of ignore: for now, forever, this session, and per listed app (`permanentlyIgnoredApps`) (§3.1.1, §5.9). Our `IgnoreState` in §6.3 already covers `.untilRecovered`, `.until(Date)`, `.forever` and `.forSubject(Set)`. Add **`.thisSession`** (cleared at agent launch) to match.
- **Hysteresis band.** CMM3 logs "close to threshold. Ignoring." Keep our 20 % re-arm rule for disk-low (§6.2).
- **Threshold default for disk-low.** CMM3 computed a per-volume default rather than a fixed number. Our `max(10 GB, 5 %)` is in the same spirit. On 256 GB minis that is 12.8 GB, on 2 TB minis 100 GB. Cap it at **50 GB** so large drives don't nag. (Changed from §6.2's uncapped rule.)

---

## Verification notes

**Environment.** The fact-check ran on 2026-10-12. macpaw.com, cleanmymac.com, updates.cleanmymac.com, updates.devmate.com, apps.apple.com and the review sites (9to5Mac and others) all failed DNS. The shared WebSearch budget was already exhausted (0 searches possible). Archive or reader services were deliberately not used. Verification therefore relied on the sources listed below, all fetched in this pass.

**Claims checked (≈25) and outcome**

| # | Claim | Result | Evidence |
|---|---|---|---|
| 1 | Vendor launchd labels, login item, helper path (5.x) | Confirmed | Homebrew cask re-fetched raw |
| 2 | 5.x app path `/Applications/CleanMyMac_5.app` | **Clarified (corrected):** the cask renames it to `CleanMyMac.app` | Cask `app … target:` |
| 3 | Agents respawn "via KeepAlive" | **Corrected:** login-item relaunch semantics | Apple `SMAppService.register()` docs |
| 4 | X 4.10 date "2022" | **Corrected:** 21 Dec 2021 | X Sparkle appcast (S3) |
| 5 | X 4.11 / 4.11.2–4 / 4.12.4 / 4.13.0 / 4.13.6 / 4.14.0 / 4.14.2 Menu and alert features and dates | Confirmed | DevMate X release notes + X appcast (S3) |
| 6 | 5.0.7 VoiceOver / Reduce Motion; 5.2.6 Smart Insights; no Menu items through 5.3.1 | Confirmed | DevMate 5.x notes (S3) |
| 7 | HealthMonitor 422 MB RSS and 4–19 % CPU | **Corrected precision:** 422,352 KiB (≈412 MiB), ≈3–19 % | GitHub code-search excerpts |
| 8 | `kern.memorystatus_vm_pressure_level` 1/2/4 mapping | Confirmed, with added detail (Urgent → Warn, MASKED) | xnu source |
| 9 | `vm.swapusage` "also returns swapins/swapouts" | **Corrected:** they come from `vm_statistics64` | stats RAM reader; xnu `sysctl.h` |
| 10 | `kern.memorystatus_level` = memory_pressure's free % | Upgraded to VERIFIED | system_cmds + xnu |
| 11 | `getifaddrs` 32-bit vs IFLIST2 64-bit counters | Upgraded to VERIFIED | xnu `if_var.h`, `if.h` |
| 12 | `networkQuality -c` keys and flags | Upgraded to VERIFIED; **units corrected** (bits/s on 15+; the 14 man page says bytes/s) | man pages 14/15/26/27 |
| 13 | `rusage_info_v6` energy field names | Upgraded to VERIFIED | xnu + SDK headers 13.3/14.5/15.5/26.5 |
| 14 | `kIOPSBatteryHealthConditionKey` values incl. "Service Recommended" | **Corrected:** only "Check Battery" and "Permanent Battery Failure" exist | SDK `IOPSKeys.h` |
| 15 | `IOPSGetTimeRemainingEstimate` −1 | Confirmed; added −2 Unlimited on AC | SDK `IOPowerSources.h` |
| 16 | UPS detection via the `"UPS Power"` state | Refined: use `IOPSGetProvidingPowerSourceType`; per-source states documented differently | SDK headers |
| 17 | `pmset -a lowpowermode 1` | **Corrected:** undocumented in `pmset(1)`; `powermode` key seen on a Mac mini | man page; GitHub excerpts |
| 18 | `SMAppService` status cases, `openSystemSettingsLoginItems()`, `loginItem(identifier:)` location rule | Confirmed | Apple docs JSON |
| 19 | `UNNotificationInterruptionLevel.timeSensitive` + entitlement | Level confirmed (macOS 12+); entitlement key VERIFIED-X only | Apple docs; GitHub code search |
| 20 | Foundation Models availability cases, ~4K context, API names | Confirmed (4096 tokens; `contextSize` API) | Apple docs JSON, TN3193 |
| 21 | stats implementation details (NVMe SMART UUIDs/fields, HID sensor pages and names, SMC command indices, per-chip key lists, Bluetooth five-source layering + TTLs, notification hysteresis, PopupWindow, nettop / public-IP / 1.5× guard) | Confirmed line by line | exelban/stats raw files |
| 22 | `DADiskUnmount` / force option | Confirmed; added option values | SDK `DADisk.h` |
| 23 | `~/.Trash` needs FDA | Upgraded to VERIFIED-X | multiple tool docs |
| 24 | 5.x battery bands (≥ 80 / ≤ 79 / ≤ 10 %) | **Downgraded to INFERRED** | KB unreachable; sibling fact-checker concurs |
| 25 | CMM3 hung-app alert labels; free-space / Trash / RAM alert strings | Confirmed (strings re-fetched) | mirror `.strings` files |

**Gaps answered (of the 10 reported):** #9 (hung-app detection: CGS notify, for CMM3) and #10 (networkQuality keys; rusage_info_v6 fields). #2 and #5 partly answered. #1, #3, #4, #6, #7 and #8 remain open because every MacPaw-hosted 5.x source was unreachable and no third-party mirror of the 5.x KB or bundle strings exists on GitHub. The one AI-written third-party summary found (gaowujian/obsidian-vault) was judged unreliable and not used as evidence.

**Remaining uncertainty and how to close it (INFERRED next steps on the Mac mini)**
1. Install the CleanMyMac 5.7.1 trial. Screenshot every Menu tile and detail view. Run `defaults read com.macpaw.CleanMyMac5.Menu` and `defaults read com.macpaw.CleanMyMac5.HealthMonitor` (keys only) to learn the alert toggles and thresholds.
2. Run `nm -u` / `strings` on `CleanMyMac_5.app/Contents/Library/LoginItems/*HealthMonitor.app/Contents/MacOS/*` (symbols only, nothing copied) to confirm that 5.x still uses `CGSRegisterNotifyProc` and to see which IOKit or SMC paths it uses.
3. Run `networkQuality -c` once on macOS 15+ and compare `dl_throughput` with the Mbps figure in the human-readable output, to settle bits vs bytes.
4. Run `pmset -g` on the mini to confirm whether it lists `powermode` or `lowpowermode`.
5. Check whether macOS 26/27 System Settings exposes per-app menu-bar visibility, and how `NSStatusItem.isVisible` reports it.

**Sources fetched in this pass**
- Homebrew cask (raw): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb ; X cask: https://raw.githubusercontent.com/letuanhai/homebrew-tap/HEAD/Casks/cleanmymac-x.rb
- DevMate S3: …/com.macpaw.CleanMyMac5/updates.xml, …/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html, …/com.macpaw.CleanMyMac4/updates.xml, …/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html (host `s3-us-west-2.amazonaws.com/updateinfo.devmate.com`)
- xnu: `bsd/sys/resource.h`, `bsd/sys/sysctl.h`, `bsd/net/if.h`, `bsd/net/if_var.h`, `bsd/kern/kern_memorystatus_notify.c`, `bsd/kern/kern_memorystatus.c`, `bsd/sys/event_private.h` at https://github.com/apple-oss-distributions/xnu ; `memory_pressure/memory_pressure.c` at https://github.com/apple-oss-distributions/system_cmds
- SDK headers: https://github.com/alexey-lysiuk/macos-sdk (`MacOSX26.5.sdk/.../IOKit.framework/.../ps/IOPSKeys.h`, `IOPowerSources.h`, `DiskArbitration.framework/.../DADisk.h`, `usr/include/sys/resource.h` for 13.3/14.5/15.5/26.5)
- Man pages: https://github.com/vitorgalvao/macos-man-pages (`macOS/{14,15,26,27}/man8/networkQuality.8`, `macOS/26/man1/pmset.1`)
- Apple docs JSON (developer.apple.com/tutorials/data/documentation/…): `servicemanagement/smappservice/status-swift.enum`, `…/opensystemsettingsloginitems()`, `…/loginitem(identifier:)`, `…/register()`, `servicemanagement/smloginitemsetenabled(_:_:)`, `usernotifications/unnotificationinterruptionlevel/timesensitive`, `usernotifications/uncalendarnotificationtrigger`, `dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)`, `appkit/nsworkspace/unmountandejectdevice(at:)`, `swiftui/menubarextra`, `corewlan/cwinterface/ssid()`, `foundation/processinfo/islowpowermodeenabled`, `iokit/kiopsbatteryhealthconditionkey`, `foundationmodels/…` (availability, UnavailableReason, contextSize, LanguageModelSession, Generable, Guide, Tool, respond), `technotes/tn3193-managing-the-on-device-foundation-model-s-context-window`
- exelban/stats raw (master): `Modules/{RAM,CPU,Net,Battery,Bluetooth,Disk,Sensors}/readers.swift`, `Modules/Disk/header.h`, `Modules/Sensors/reader.m`, `SMC/smc.swift`, `Kit/module/notifications.swift`, `Kit/module/popup.swift`, `Kit/helpers.swift`, `Kit/plugins/SystemKit.swift`
- CMM3 mirror: `CleanMyMac 3 Menu.app/Contents/MacOS/CleanMyMac 3 Menu` (symbols / strings only), `Resources/en.lproj/{HungAppsAlert,RAMUsageAlert,LowDiskSpaceAlert}.strings`, `Resources/Base.lproj/Health.strings` at https://github.com/auspham/mac-essential
- CGS headers: https://github.com/sirg3/CGSInternal (`CGSNotifications.h`, `CGSMisc.h`)
- networkQuality parser: https://github.com/jtn0123/OpenTaskManager ; https://github.com/macadmins/osquery-extension (`tables/networkquality/networkquality.go`)
- GitHub code-search excerpts (VERIFIED-X): process listings (OpenAgentsInc/openagents, francescotinti/php-rust), defaults domains (tracycsmith/refineo-laptop-config), cache paths (themoretheless/ppduster), `launchctl bootout` (ArshiaEcho/janitor), Mac mini `powermode` (LouisVasseur/SPLICE), FDA on `~/.Trash` (viniciussouzao/tidymymac, sodadata/tutorial-demo-project), time-sensitive entitlement usage
