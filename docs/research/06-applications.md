# 06 — Applications: Uninstaller (leftovers logic), Updater, Extensions manager

Track owner: research subagent "06-applications". Date: 2026-10-12.
Target: an original, functionally equivalent app (our own name and branding) for an Apple-silicon Mac mini running macOS 14 Sonoma, macOS 15 Sequoia or macOS 26 Tahoe.

---

## 0. Method, source access and evidence legend

**Access limits in this session**
- The shared WebSearch budget was already used up when this track started, so this track ran **no web searches**.
- These hosts were blocked by the egress proxy:
  - macpaw.com and cleanmymac.com
  - support.apple.com and developer.apple.com (the latter renders only through JavaScript)
  - updates.cleanmymac.com, updateinfo.devmate.com and formulae.brew.sh
- Because of that, this report relies on:
  1. **MacPaw-authored primary material hosted on GitHub or S3**, read directly in this session:
     - the CleanMyMac 3.9 app bundle (in-app Help book, UI `.strings` files, Info.plists), mirrored in a public repo;
     - DevMate release-note pages for CleanMyMac 1.x and CleanMyMac X 4.10–4.12;
     - the official Homebrew cask for CleanMyMac 5;
     - MacPaw's open-source PermissionsKit.
  2. **MacPaw knowledge-base facts verified by sibling tracks** (`01-overview.md`, `02-smart-care.md`, `03-cleanup.md`, `04-protection.md`), re-cited here with their KB URLs.
  3. **Source code read line by line** from four open-source projects: Pearcleaner, Latest, Mole and KnockKnock.
  4. Sparkle and Homebrew documentation, fetched as raw Markdown from their GitHub repos.
- **Fact-check pass (added, same day).** An adversarial fact-checker re-verified about 16 key claims. It used:
  - DevMate S3 notes up to X 4.15.8;
  - real CleanMyMac X screenshots;
  - Apple developer-docs JSON;
  - macOS SDK man pages;
  - GitHub code search.

  Corrections are marked "(corrected)" and additions "(added)". The summary is in "## Verification notes" at the end.

**Evidence legend**

| Tag | Meaning |
|---|---|
| **VERIFIED** | Read in this session from the cited URL or file. |
| **VERIFIED-K** | MacPaw KB fact verified by a sibling report. The KB URL and the sibling report are named. |
| **VERIFIED-OSS** | Read in the cited open-source file at the commit given in §8. |
| **VERIFIED-PX** | (added by fact-checker) Seen in a real CleanMyMac X screenshot (Chinese UI, translated by us). The screenshots are stored in a third-party replica repo: `reference-uninstaller-list.png`, `reference-extensions-intro.png` and `reference-updater-details.png` at https://github.com/ddlmanus/MacOptimizer. The labels are the vendor's; the English wording is our translation. |
| **VERIFIED-APPLE** | (added by fact-checker) Read in Apple's developer documentation (JSON endpoint `developer.apple.com/tutorials/data/documentation/…`) or in a macOS SDK man page (mirror https://github.com/phracker/MacOSX-SDKs, `MacOSX11.3.sdk/usr/share/man/…`). |
| **INFERRED** | Our reasoning, platform knowledge or recommendation. Not checked against a primary source in this session. Treat as a design decision or something to test on device. |

**Shorthand for repeated primary sources**
- `[CMM3-Help-8]`: CleanMyMac 3 Help, "Uninstaller" topic.
  https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-8.html
- `[CMM3-Help-91]`: same Help book, "Extensions" topic (`…/English.lproj/topic-91.html`).
- `[CMM3-Help-94]`: same Help book, "CleanMyMac 3 Menu" topic (`…/English.lproj/topic-94.html`).
- `[CMM3-Strings]`: MacPaw's shipped English UI strings in the same mirror (CleanMyMac 3.9), under `CleanMyMac 3.app/Contents/Resources/`:
  - `Base.lproj/Localizable.strings`
  - `Base.lproj/Alerts.strings`
  - `en.lproj/ApplicationsScanResultsView.strings`
  - `en.lproj/CMIgnoreListPreferencesViewController.strings`
  - `en.lproj/CMMenuPreferencesViewController.strings`
  - `en.lproj/CMUpdatesPreferencesViewController.strings`
- `[CMM3-Bundle]`: CleanMyMac 3.9 `Contents/Info.plist`, `Contents/PlugIns/StorageManagement.appex/Contents/Info.plist`, and the resource file list in the same mirror.
- `[DM-1x]`: CleanMyMac 1.x release notes.
  https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html
- `[DM-X]`: CleanMyMac X 4.10–4.12 release notes.
  https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- `[DM-X15]` (added by fact-checker): CleanMyMac X 4.10.0–**4.15.8** release notes. The build number 41508.0.2409290833 comes from a third-party cask, https://github.com/letuanhai/homebrew-tap/blob/main/Casks/cleanmymac-x.rb.
  https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html
- `[CaskZH]` (added by fact-checker): the CleanMyMac X Chinese-edition cask (4.15.14). It lists the X-era footprint.
  https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb
- `[Cask]`: https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/cleanmymac.rb (raw fetch; version 5.7.1, 50701.0.2609301754)
- `[CaskCookbook]`: https://github.com/Homebrew/brew/blob/main/docs/Cask-Cookbook.md
- `[SparklePub]`: https://github.com/sparkle-project/sparkle-project.github.io/blob/master/documentation/publishing/index.md
- `[SparkleCust]`: https://github.com/sparkle-project/sparkle-project.github.io/blob/master/documentation/customization/index.md

Paraphrase policy: short UI labels are quoted. Longer vendor text is paraphrased.

---

## 1. TL;DR: the facts that drive the implementation

1. **The vendor's Applications area has four pillars in 5.x.** VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller, via 01-overview.md §5.2):
   - **Uninstaller**: complete uninstall or reset of apps.
   - **Updater**: app updates.
   - **Leftovers**: service files of apps that were already removed by hand.
   - **Installation files**: leftover installers.

   The flow is: scan → tiles → "Manage My Applications". Since 5.5.5 the scan runs in the background, so you can act before it finishes. VERIFIED-K (https://macpaw.com/cleanmymac/whats-new).
2. **Uninstaller groups we must reproduce:**
   - **All Applications**.
   - **Unused**: not opened for **6 months**. VERIFIED-K (uninstaller KB). This group is **5.x only**: it is absent from the X 4.15 screenshot (VERIFIED-PX).
   - **Suspicious**: added in X 4.10.4 for apps "associated with or owned by Russian or Belarusian developers". VERIFIED ([DM-X], re-fetched).
   - (corrected) **iPhone & iPad apps on Apple silicon**: the Uninstaller *lists* them. VERIFIED ([DM-X] 4.10.0). Whether they have their own sidebar group is INFERRED.
   - (corrected) **Steam games**: the Uninstaller *lists* them. VERIFIED: [DM-X] 4.10.0 fixed a "doubling of Steam apps" bug, and CMM3 rows carry a "Steam Application" label. A dedicated "Steam" group is INFERRED.
   - (corrected) **The X sidebar layout is now VERIFIED-PX** from a real CleanMyMac X screenshot:
     - top block: "All Applications" (count), **"Leftovers"** (count), "Suspicious" (no count when empty), **"Selected"**;
     - header **"Stores"**: "App Store" (count) and "Other" (count);
     - header **"Vendors"**: one row per vendor (e.g. Google, MacPaw, JetBrains) plus "Other".
   - Intel-only and 32-bit groups do **not** appear in that screenshot, so they stay INFERRED (our addition).
3. **System apps are hidden and can be reset but not uninstalled.** They are on the Ignore List by default ("Ignore system applications" under Ignore List › Uninstaller). Once you un-ignore them, they can be **reset** but **not uninstalled**. VERIFIED ([CMM3-Help-8], [CMM3-Strings]).
   The 5.x KB still puts system apps on the ignore list by default. VERIFIED-K (uninstaller KB).
4. **There are two "Smart Selector" modes.** VERIFIED ([CMM3-Strings], `ApplicationsScanResultsView.strings`):
   - **Complete Uninstallation**: selects *all* application items.
   - **Application Reset**: selects all related items **but keeps the main binary**, so the app starts clean next launch ([CMM3-Help-8]).

   The main button relabels itself **Uninstall / Reset / Remove**, depending on whether apps, a reset, or loose files are selected. VERIFIED ([CMM3-Help-8]).
5. **Vendor behaviors to match.** VERIFIED ([DM-1x]):
   - quit running apps first, with a "Skip" option in the "Quit Application" dialog;
   - remove the app's **Dock icon**;
   - uninstall **Mac App Store** apps;
   - handle **sandboxed** apps "accurately";
   - an **installer-package deinstaller** (drag a `.pkg` in);
   - uninstallers for **Launch Agents, Daemons, Startup Items**;
   - **auto-scan for leftovers when an app is moved to Trash**;
   - a **Knowledge base** that improves Uninstaller and Leftovers accuracy.
6. **Trash monitoring is a Menu/agent feature.** It is an "Uninstaller" toggle labelled "Offer to correctly uninstall applications": dropping an app into the Trash triggers an offer to uninstall it with all related items. VERIFIED ([CMM3-Strings] `CMMenuPreferencesViewController.strings`; [CMM3-Help-94]).
   In 5.x the **Health Monitor** background item drives this prompt. VERIFIED-K (01-overview.md §8, https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes).
7. **The vendor's own footprint is a test case for our leftover engine.** It spans many locations. VERIFIED ([Cask], re-fetched 2026-10-12):
   - (corrected) Only the Updater has a plist file: `~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist` (zap). `com.macpaw.CleanMyMac5.HealthMonitor` and `.Menu` are launchd **labels** that the cask unloads with `launchctl`; no plist path is given for them. INFERRED: they are registered from inside the bundle (`SMAppService`/`Contents/Library/LaunchAgents`), so the leftover engine must find them through `BundleProgram`/`AssociatedBundleIdentifiers`, not by filename;
   - a LaunchDaemon plist `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist` plus `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`;
   - plain bundle-ID folders: `~/Library/Caches/com.macpaw.CleanMyMac5`, `~/Library/Logs/com.macpaw.CleanMyMac5`, `~/Library/Preferences/com.macpaw.CleanMyMac5.plist`, and a **name-based** `~/Library/Application Support/CleanMyMac_5` (added);
   - (added) the shipped bundle is `CleanMyMac_5.app`, and the cask renames it to `CleanMyMac.app` because "app name is different in the Finder and in a shell". Name matching must therefore try the file name, `CFBundleName`, `CFBundleDisplayName` **and** the underscore/space variants;
   - **Team-ID-prefixed** `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5` and `~/Library/Application Scripts/S8EX82NJP6.com.macpaw.CleanMyMac5`;
   - `HTTPStorages/<id>` and `HTTPStorages/<id>.binarycookies`;
   - `Saved Application State/<id>.savedState`;
   - `/Users/Shared/CleanMyMac_5`;
   - a login item named "CleanMyMac 5 Menu".
8. **The Updater has four sources: App Store, Sparkle, Custom, macOS.** The 5.x group names are "App Store Updates", "Sparkle Updates", "Custom Updates" and "macOS Updates". The App Store edition lists neither App Store nor macOS updates. Smart Care's Applications tile counts app updates *excluding system apps and macOS updates*. VERIFIED-K:
   - https://macpaw.com/support/cleanmymac-x/knowledgebase/updater
   - https://macpaw.com/support/cleanmymac/knowledgebase/smart-care

   Via 02-smart-care.md and 01-overview.md.

   "Custom" covers vendor updaters that are not Sparkle. X 4.11.2 added **Zoom** and 4.11.3 added **Chrome**. VERIFIED ([DM-X]).
9. **Extensions (CMM3 module) categories.** VERIFIED ([CMM3-Help-91], [CMM3-Strings]):
   - Widgets
   - Safari Extensions and Safari Plugins
   - Chrome Extensions
   - Internet Plugins
   - QuickLook Plugins
   - Spotlight Plugins
   - Finder Plugins
   - Preference Panes
   - Screen Savers
   - Dictionaries
   - Mail Plugins
   - Contacts/Address Book Plugins
   - Audio Plugins ("MAS, AU, and VST")
   - QuickTime Player Plugins
   - iTunes plugins
   - Growl Plugins
   - Login Items
   - Launch Agents
   - Services
   - (corrected) "Siri Activity" (disable only; the strings also have "Siri in menu bar"). VERIFIED ([CMM3-Strings] `Localizable.strings`, re-read).

   Behavior:
   - Nothing is auto-selected.
   - Each item has **Enabled/Disabled** state: hover "Enabled" to get a "Disable" button.
   - **Disable is reversible; Remove cannot be undone.**
   - Some Chrome extensions are read-only, and the app points you to Chrome's own Extensions settings.
   - Enabling or disabling some items requires an admin password.
10. **In 5.x, Login Items and Background Items live under Performance.** They can be enabled or disabled reversibly, or removed permanently. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/optimization, via 01-overview.md).
    No 5.x "Extensions" module was found (GAP, as also flagged in 01-overview.md). (added) The 5.x **My Tools** hub lists Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions and Email Cleanup, with no Extensions tool (VERIFIED-K, https://macpaw.com/news/my-tools-cleanmymac via 01-overview.md). That supports "Extensions was dropped in 5.x", but it is not proof. For a "perfect" equivalent we ship Extensions as a tool under Applications. INFERRED.
11. **Two leftover-matching philosophies exist in open source. We should combine them.** VERIFIED-OSS:
    - **Pearcleaner** normalizes names (lowercase alphanumerics only) and matches app name, bundle ID, entitlements and binary names against the entries of about 70 roots, with three sensitivity levels and a Spotlight supplement.
    - **Mole** builds **exact path templates**, matches bundle IDs only at **dot boundaries**, and treats a LaunchAgent as owned only when the label equals the bundle ID or the plist's program lives inside the app bundle.

    Our engine should generate candidates the Pearcleaner way, require Mole-grade proof before default-selecting, and add a curated knowledge base. Homebrew cask `zap` stanzas are BSD-2 licensed and usable for that. INFERRED.
12. **Updater algorithms are proven in open source.** VERIFIED-OSS (Latest, Pearcleaner):
    - **Sparkle**: read `SUFeedURL` from Info.plist (strip quotes); fall back to DevMate `https://updates.devmate.com/<bundleID>.xml` when `DevMateKit.framework` is present; drive Sparkle's own `SPUUpdater` with a headless user driver.
    - **Mac App Store**: detect the `_MASReceipt` (or `WrappedBundle`/`iTunesMetadata.plist` for iOS apps), then query `https://itunes.apple.com/lookup?bundleId=…&country=…&entity=desktopSoftware`, falling back to `macSoftware`.
    - **Homebrew**: map Caskroom JSON `artifacts.app` to installed apps and compare against the **Info.plist version (ground truth)**.
    - **"Database" updates for everything else**: Latest uses Homebrew's `cask.json` as the version database.

---

## 2. Vendor history of the Applications features

| Era / version | Applications-related facts | Status |
|---|---|---|
| CleanMyMac 1.7.0 | Uninstallers for Growl, Launch Agents, Daemons, Startup Items. Auto-scan for leftovers when an app is moved to Trash. Ignore List auto-update. | VERIFIED [DM-1x] |
| 1.7.2 / 1.7.3 | "Scripting Additions" scanning added to Plugins. "Package Deinstaller": drag installer packages in to remove what they installed. | VERIFIED [DM-1x] |
| 1.8.0 / 1.8.1 | Startup Items editor in the plug-ins extension. Leftovers search includes broken launch items. "System libraries and extensions filter" for the Uninstaller. | VERIFIED [DM-1x] |
| 1.9.0 | Dock icons removed on app uninstall. Improved Leftovers search. | VERIFIED [DM-1x] |
| 1.9.2 | Uninstaller finds more related resources. "Skip" option in the "Quit Application" dialog. "Safari Extensions" cleaner in Plugins of "Manage Extensions". | VERIFIED [DM-1x] |
| 1.9.3 / 1.9.4 | Improved Widgets uninstaller. Mac App Store apps uninstall correctly. Update manager can update ignore lists, the knowledge base and the app itself. | VERIFIED [DM-1x] |
| 1.10.0 / 1.10.8 / 1.10.9 / 1.10.10 | Knowledge base gives more accurate Uninstaller and Leftovers results. Sandboxed apps uninstall accurately. Xcode uninstalls correctly. Dock-icon removal bug fixed. | VERIFIED [DM-1x] |
| CleanMyMac 3 (2015–2018) | Uninstaller: complete uninstall, reset, view unsupported apps, reset system apps. Extensions module (§5.1). Menu "Uninstaller" Trash prompt. Setapp-aware uninstall warning. | VERIFIED [CMM3-Help-8/91/94], [CMM3-Strings] |
| CleanMyMac X 4.10.0 (2022) | Uninstaller shows iPhone & iPad apps on M1 Macs. Steam apps no longer appear twice. | VERIFIED [DM-X] |
| X 4.10.4 | New Uninstaller category **Suspicious** (apps tied to companies of a particular origin). | VERIFIED [DM-X] |
| X 4.11.1–4.12.2 | Better removal of leftover data. Updater can update Zoom (4.11.2) and Chrome (4.11.3). Better update notifications (4.11.4). Fixed updates offered after already installed (4.12.2). | VERIFIED [DM-X] (re-fetched) |
| X 4.13.0 (added) | "Removing related Launch Agents and Daemons when an application gets uninstalled" (Improved). | VERIFIED [DM-X15] |
| X 4.13.6 (added) | **Updater no longer suggests updates that your macOS version does not support.** Microsoft Outlook and **Microsoft AutoUpdate** "get scanned properly". "Minor Trash Monitor … issues fixed". Whether "Trash Monitor" means the uninstall-on-trash prompt or the overfilled-Trash alert is unclear. | VERIFIED [DM-X15]; meaning of "Trash Monitor" INFERRED |
| X 4.14.0 (added) | The app-update notification "became more informative and lists your top outdated applications". | VERIFIED [DM-X15] |
| X 4.15.4 (added) | "Sort applications by last open date in the Uninstaller module". | VERIFIED [DM-X15] |
| X 4.15.x Uninstaller UI (added) | Sidebar: All Applications · Leftovers · Suspicious · Selected · **Stores** (App Store, Other) · **Vendors** (per vendor, Other). List: title, subtitle, "Sort by Name ▾", rows with a round checkbox, icon, name, chevron › and size. | VERIFIED-PX (`reference-uninstaller-list.png`) |
| X Mac App Store edition (2020) | No Updater module. | VERIFIED-K (https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features, via 01-overview.md) |
| CleanMyMac 5.x (2024+) | Applications module with Uninstaller / Updater / Leftovers / Installation files. App Store edition can't delete App Store app binaries (reset only), has no Leftovers, and no App Store or macOS updates. Applications scans run in the background (5.5.5). Smart Insights icon beside app names (macOS 26 + Apple Intelligence). | VERIFIED-K (uninstaller and missing-features KB; https://macpaw.com/cleanmymac/whats-new; https://macpaw.com/news/introducing-smart-insights, via 01-overview.md) |

**Vendor architecture hints from the CMM3 bundle.** VERIFIED [CMM3-Bundle]:
- A `KnowledgeBase.pem` and an `info.cmmkb` file ship in Resources.
- `SMPrivilegedExecutables` declares the helper `com.macpaw.CleanMyMac3.Agent` (classic SMJobBless).
- XPC services ship in the bundle: `IconsService` and `LipoService`.
- A `StorageManagement.appex` uses extension point `com.apple.storagemanagement`, which integrates into macOS Storage Management.

INFERRED: the `.cmmkb` file is the signed "Safety Database / Knowledge base" that holds per-app rules and ignore lists. We design our own (§3.11).

---

## 3. Uninstaller: spec for our clone

### 3.1 Vendor behaviors to reproduce (verified)

**Listing**
- The Uninstaller lists **all custom apps, including those outside the Applications folder**. VERIFIED [CMM3-Help-8].
- Per-row labels include "Steam Application" and "System Application". VERIFIED [CMM3-Strings].

**Sort options**
- "Name", "Kind", "Size", "Last Launch Date", "Selection", each Ascending or Descending. VERIFIED [CMM3-Strings].
- The Help suggests "Sort by Last Launch Date" to find rarely used apps. VERIFIED [CMM3-Help-8].
- (added) In X the default list sort is "Sort by Name" (VERIFIED-PX). Sorting by last open date was (re)added in 4.15.4 (VERIFIED [DM-X15]).

**X-era list layout** (added; VERIFIED-PX `reference-uninstaller-list.png`)
- On entering the Uninstaller list, the main app sidebar is replaced by a "‹ back" control and a **filter column** (groups listed in §1 item 2).
- The main pane shows:
  - a bold group title, e.g. "All Applications";
  - a one-line subtitle, which paraphrases as "every app installed on your Mac is listed below";
  - a right-aligned "Sort by Name ▾";
  - one row per app: round checkbox · 32 pt icon · name · disclosure chevron › (opens that app's file list) · total size.
- Group counts are right-aligned in the filter column, and empty groups show no count.

**Per-file and per-app actions**
- Per file: "Reveal in Finder" and Quick Look. VERIFIED [CMM3-Help-8].
- Per app: "Keep", "Launch", "Reveal in Finder", "Add to Ignore List". VERIFIED [CMM3-Strings].

**List actions and selection**
- **Action › Refresh** loses the current selection. Search filters as you type. VERIFIED [CMM3-Help-8].
- The app never removes anything on its own; the user decides per app. Deselecting an app or file excludes it. VERIFIED [CMM3-Help-8].

**Confirmation dialogs** (CMM3). VERIFIED [CMM3-Strings] `Alerts.strings`:
- Single app: are you sure you want to permanently uninstall "%@" and all its related items?
- Reset: are you sure you want to reset "%@" by removing all of its related items?
- Informative line: "You can't undo this action."
- Multi-app caution: the Uninstaller removes apps completely.
- Setapp case: selecting Setapp plus N of its apps warns that the apps won't work without the main Setapp app.

**Log titles**: "Uninstallation Log" and "Removal Log". VERIFIED [CMM3-Strings].

**Self-uninstall** is a special case: the app warns that it will close and remove itself. VERIFIED [CMM3-Strings].

INFERRED: we will move items to the Trash and offer Undo (§3.8) instead of "can't undo". This is a deliberate safety improvement.

### 3.2 App discovery (where apps come from)

| Source | How | Notes | Status |
|---|---|---|---|
| `/Applications` and `~/Applications`, recursively | Walk the directory, skipping symlinks and package descendants. | Pearcleaner's defaults are exactly these two paths, plus user-added folders. It skips symlinked `.app` items and "restricted" paths (`/Applications/Safari`, `/Applications/Utilities`, itself). | VERIFIED-OSS `Views/Settings/Folders.swift:419`, `Logic/Logic.swift:133` `getSortedApps`, `Logic/Utilities.swift:149` `isRestricted` |
| Latest's default folders | `FileManager.urls(for: .applicationDirectory, in: [.localDomainMask, .userDomainMask])` plus custom folders. A `DispatchSource` `.write` watcher on each folder re-collects after a 10 s debounce. Skips any path containing `Setapp`. Excludes Safari web apps (`com.apple.Safari.WebApp`). | Good model for live refresh. | VERIFIED-OSS Latest `Model/Directory/AppDirectoryStore.swift:33`, `AppDirectory.swift:39`, `AppLibrary.swift:37`, `BundleCollector.swift:16–21` |
| Spotlight metadata | Batch `MDItemCreate` / `MDItemCopyAttribute` for `kMDItemDisplayName`, `kMDItemCFBundleIdentifier`, `kMDItemLogicalSize`, `kMDItemPhysicalSize`, `kMDItemLastUsedDate`, `kMDItemDateAdded`, `kMDItemFSCreationDate`, `kMDItemFSContentChangeDate`, `kMDItemAppStoreAdamID`. | Fast and gives "last opened" for the **Unused** group. Fall back to reading Info.plist from disk for freshly installed apps. | VERIFIED-OSS Pearcleaner `Logic/AppInfoFetch.swift:392` `getMDLSMetadata` |
| Whole-disk catalogue (INFERRED) | `NSMetadataQuery` with `kMDItemContentTypeTree == "com.apple.application-bundle"` over local volumes. | Finds apps in odd places, matching the vendor's "outside the Applications folder" behavior. Exclude `/System`, `/Library/Apple`, Xcode-embedded simulator apps, and bundles inside other bundles. | INFERRED |
| iOS/iPadOS apps (Apple silicon) | An `.app` containing `Wrapper/` with an inner `.app` and `Wrapper/iTunesMetadata.plist`. The receipt path contains `WrappedBundle`. | Show as "iPhone & iPad apps". The container is `~/Library/Containers/<UUID>`, identified by `.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier`. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:318–343`, `AppPathsFetch.swift:143` `getAllContainers`; Latest `MacAppStoreCheckerOperation.swift:90`; vendor behavior VERIFIED [DM-X] |
| Web apps | Info.plist `LSTemplateApplication == true` or `CFBundleExecutable == "app_mode_loader"` (Chromium PWAs). Safari web apps use bundle ID `com.apple.Safari.WebApp.*`. | For web apps, Pearcleaner only scans containers and bundle-ID matches. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:345`; Latest `BundleCollector.swift:19` |
| Steam games | `~/Applications/<Game>.app` launchers whose `Contents/MacOS/run.sh` contains `steam://run/<id>`. The real game is in `~/Library/Application Support/Steam/steamapps/common/<Game>`, with manifest `steamapps/appmanifest_<id>.acf`. | Uninstall must remove the launcher, the game folder and the manifest. Steam itself should then be told to refresh. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:593`, `AppPathsFetch.swift:334–355` |
| Setapp apps | Bundle ID ends with `-setapp`. They live under `/Applications/Setapp/`. | Excluded from Sparkle checks. Uninstall them through Setapp, or warn as the vendor does. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:308`; Latest `BundleCollector.swift:16`; vendor warning VERIFIED [CMM3-Strings] |
| Homebrew casks | Glob `/opt/homebrew/Caskroom/*/.metadata/*/*/Casks/*.json` (`/usr/local/Caskroom` on Intel). Map `artifacts[].app` (string or `{target:}`), `name[]` and `uninstall.quit` IDs to apps. Read the `auto_updates` flag. | Badge "Homebrew". Offer `brew uninstall --zap --cask <token>` as an alternative removal path. | VERIFIED-OSS Pearcleaner `Logic/Logic.swift:888` `buildCaskLookupTable`, `Views/FilesView/FilesView.swift:307–330` |

### 3.3 Per-app metadata (data model)

```swift
struct InstalledApp: Identifiable, Hashable {
  let id: URL                 // bundle URL (for wrapped iOS apps: the outer .app)
  let bundleID: String        // CFBundleIdentifier
  let name: String            // kMDItemDisplayName minus ".app", else CFBundleName / filename
  let executableName: String? // CFBundleExecutable
  let version: String         // CFBundleShortVersionString (fallback CFBundleVersion)
  let build: String?          // CFBundleVersion
  let teamID: String?         // SecCodeCopySigningInformation → kSecCodeInfoTeamIdentifier
  let vendor: String?         // see derivation below
  let signing: SigningState   // .appleSystem, .appStore, .developerIDNotarized, .developerID, .adhoc, .unsigned, .broken
  let arch: Arch              // .arm64, .x86_64, .universal, .i386(32-bit), .ppc, .unknown
  let kind: AppKind           // .regular, .appStore, .iOSWrapped, .webApp, .steam, .setapp, .system
  let source: InstallSource   // .appStore, .homebrew(token), .pkg(ids), .dragAndDrop, .setapp, .steam
  let sizeOnDisk: Int64
  let lastUsed: Date?         // kMDItemLastUsedDate
  let dateAdded: Date?        // kMDItemDateAdded
  let appGroups: [String]     // entitlement com.apple.security.application-groups
  let iCloudContainers: [String] // com.apple.developer.icloud-container-identifiers
  let embeddedBundleIDs: [String] // Contents/{Library/LoginItems,Library/LaunchServices,XPCServices,PlugIns,Helpers,Frameworks/*.app}
  let privilegedHelpers: [String] // Info.plist SMPrivilegedExecutables keys
  let sparkleFeed: URL?
  let isRunning: Bool
}
```

Where each field comes from:

| Field | Source | Status |
|---|---|---|
| Entitlement groups and iCloud containers | `SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation(…, kSecCSEntitlements)` → `kSecCodeInfoEntitlementsDict`. Pearcleaner also adds `Contents/MacOS/*` binary names and nested `Contents/*/*.app` names (and their binaries) of 5 characters or more, excluding `crashhandler`, `crash handler` and `electron`. It deliberately skips path-based entitlements because they match generic folder names. | VERIFIED-OSS `AppInfoFetch.swift:691` `getEntitlements` |
| Team ID | `SecCodeCopySigningInformation(…, kSecCSSigningInformation)` → `kSecCodeInfoTeamIdentifier` | VERIFIED-OSS `AppInfoFetch.swift:788` |
| Architecture | Read the main executable's Mach-O header. Fat magic `0xCAFEBABE` → iterate `fat_arch` entries (cputype `0x0100000C` = arm64, `0x01000007` = x86_64); thin `0xFEEDFACF`/`0xCFFAEDFE` = 64-bit; `0xFEEDFACE`/`0xCEFAEDFE` = 32-bit. Extend: cputype 7 (i386) or 18 (PPC) with 32-bit magic → "Unsupported (32-bit)". | VERIFIED-OSS `Logic/Utilities.swift:159`; i386/PPC extension INFERRED |
| App Store | `Bundle.appStoreReceiptURL` exists (`Contents/_MASReceipt/receipt`), or `Wrapper/iTunesMetadata.plist` for iOS apps. Adam ID from `kMDItemAppStoreAdamID`. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:318`; Latest `MacAppStoreCheckerOperation.swift:71–91` |
| Sparkle | Info.plist has any of `SUFeedURL`, `SUFeedUrl`, `SUPublicEDKey`, `SUPublicDSAKeyFile`, `SUEnableAutomaticChecks`, and the bundle ID does not end in `-setapp`. | VERIFIED-OSS Pearcleaner `AppInfoFetch.swift:288` |
| Vendor (INFERRED) | 1) Apple-signed → "Apple". 2) Developer ID leaf certificate subject, e.g. "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC". 3) App Store → iTunes lookup `sellerName`/`artistName`, cached. 4) Fallback: second component of a 3-part bundle ID. Pearcleaner uses step 4 as its "company" token in Deep mode (`AppPathsFetch.swift:88–95`). | INFERRED, with partial VERIFIED-OSS |
| Running | `NSWorkspace.shared.runningApplications` filtered by bundle ID. Also check helper and embedded IDs. | VERIFIED-OSS `Logic/Utilities.swift:363` `killApp` |
| Unused | `lastUsed` older than 180 days (vendor: "not opened in 6 months", VERIFIED-K). If `lastUsed == nil`, fall back to `dateAdded`/creation date older than 180 days, flagged "Never opened". | INFERRED rule on top of the VERIFIED-K threshold |

### 3.4 Uninstaller groups (sidebar filters) for our clone

| Group | Rule | Default visible | Status |
|---|---|---|---|
| All Applications | Every non-ignored app | yes | VERIFIED-K (uninstaller KB); VERIFIED-PX (X) |
| Unused | `lastUsed` (or added date) older than 180 days | yes | VERIFIED-K threshold (5.x only; absent in X 4.15, VERIFIED-PX); rule INFERRED |
| Leftovers | Orphaned files from apps no longer installed (§3.9). (corrected) In X it is a **row in the Uninstaller filter column**, with a count, directly under All Applications. In 5.x it is its own Applications category. | yes | VERIFIED-PX (X position); VERIFIED-K (5.x, uninstaller KB); [CMM3-Strings] "Application Leftovers" |
| Suspicious | Vendor: apps associated with or owned by Russian or Belarusian developers (X 4.10.4). Ours: security heuristics (unsigned or ad-hoc; signature broken; certificate revoked; Gatekeeper rejects (`spctl --assess` fails); team ID on our signed PUA/adware list; hides from the Dock but registers launch daemons; installs browser extensions or configuration profiles). Optionally a user-editable vendor/team-ID blocklist to emulate the vendor's original meaning. | yes (no count when empty, VERIFIED-PX) | Vendor meaning VERIFIED [DM-X]; our heuristics INFERRED |
| (corrected) Stores ▸ App Store / Other | Header "Stores" with two rows: "App Store" (`kind == .appStore`, incl. wrapped iOS apps) and "Other" (everything else) | yes | VERIFIED-PX (X) |
| iPhone & iPad apps | `kind == .iOSWrapped` | if any | Listing VERIFIED [DM-X]; separate group INFERRED (corrected) |
| Steam | `kind == .steam` | if any | Listing VERIFIED [DM-X]; separate group INFERRED (corrected) |
| Setapp, Homebrew | by source (could be extra rows under "Stores") | if any | INFERRED |
| Intel-only | `arch == .x86_64` (needs Rosetta). (corrected) Apple says Rosetta stays available as a general-purpose tool **through macOS 27**; after that only a subset remains, aimed at older unmaintained games. So these apps are "at risk". | if any | Rosetta timeline VERIFIED-APPLE (https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment); the group itself is INFERRED (not in the X screenshot) |
| Unsupported (32-bit / PPC) | Cannot launch on macOS 10.15+. CMM3 had a "Show Unsupported" toggle (strings) / "View unsupported apps" (Help) and an "Unsupported" label. | if any | VERIFIED [CMM3-Help-8], [CMM3-Strings] (re-read); rule INFERRED |
| Vendors ▸ | (corrected) Header "Vendors": one row per vendor with a count, then **"Other"** for apps with no recognised vendor. Our sort: by count, then name. | expanded in X | VERIFIED-PX (X); vendor derivation INFERRED (§3.3) |
| Selected | Apps with a pending action. (corrected) In X it is always listed, under Suspicious. | yes | VERIFIED-PX (X) |
| System apps | Hidden by default. A toggle mirrors "Ignore system applications". **Reset only.** | hidden | VERIFIED [CMM3-Help-8], [CMM3-Strings] |

**System-app rule (INFERRED implementation)**
- These count as system apps:
  - everything under `/System/Applications` and `/System/Library/CoreServices` (on the sealed system volume, so it can't be deleted anyway);
  - (corrected) `/Applications/Safari.app`, which on macOS 13+ is a **symlink**, not a firmlink: `/Applications/Safari.app -> ../System/Cryptexes/App/System/Applications/Safari.app` (the App cryptex). VERIFIED-OSS (dotfiles and app-indexer notes: https://github.com/paulmillr/dotfiles `scripts/macos/dock.sh`; https://github.com/Xpycode/LLM-Directions `cookbook/96-macos-app-indexer-cryptex-symlink.md`). Consequence: a discovery walk that skips symlinked `.app` items (as Pearcleaner's does) never sees Safari. That is fine for uninstall, but System-app **Reset** must resolve the symlink.
- These Apple apps *can* be uninstalled: Xcode (`com.apple.dt.*`), Final Cut Pro, Motion, Compressor, Logic Pro, GarageBand, iMovie, Pages/Numbers/Keynote, MainStage, macOS Server (`com.apple.server.*`, added), Swift Playgrounds. Mole maintains exactly this list as `APPLE_UNINSTALLABLE_APPS`. VERIFIED-OSS Mole `lib/core/app_protection_data.sh:163` (re-fetched at `main`).
- Treat these as **"use the official uninstaller"** apps: EDR/MDM/VPN suites such as CrowdStrike, SentinelOne, ESET, Jamf, Palo Alto GlobalProtect and Cisco Secure Client. Mole's `OFFICIAL_UNINSTALLER_RULES` covers them, and it refuses to touch their caches. VERIFIED-OSS Mole `app_protection_data.sh:179–205`. We show a banner "Use the vendor's uninstaller" with a button that opens it, if one is found in the bundle or `/Applications`.

### 3.5 Leftover detection engine (core algorithm)

#### 3.5.1 Identity tokens derived per app (INFERRED design; components VERIFIED-OSS)

| Token | Example | Used for |
|---|---|---|
| `bundleID` | `com.knollsoft.Rectangle` | exact and boundary matches |
| `bundleIDBase` | Strip a last component in {helper, agent, daemon, service, xpc, launcher, updater, installer, uninstaller, login, extension, plugin} when the ID has 4+ parts. | launchd and helper matching. VERIFIED-OSS Pearcleaner `AppPathsFetch.swift:105–121` |
| `teamPrefixedIDs` | `S8EX82NJP6.com.macpaw.CleanMyMac5` | Group Containers and Application Scripts (VERIFIED example in [Cask]) |
| `appGroups`, `iCloudContainers` | `group.com.foo.shared`, `iCloud.com.foo` | Group Containers, Mobile Documents (info only) |
| `embeddedBundleIDs` | helper apps, XPC services, `.appex`, login items | Containers, Application Scripts, Preferences, HTTPStorages, WebKit, ByHost. VERIFIED-OSS Mole `app_protection.sh:1475–1516` |
| `privilegedHelpers` | Info.plist `SMPrivilegedExecutables` keys | exact names in `/Library/PrivilegedHelperTools` and `/Library/LaunchDaemons`. VERIFIED [CMM3-Bundle] shows the key format; matching is INFERRED |
| `nameVariants` | "Maestro Studio" → `Maestro Studio`, `MaestroStudio`, `Maestro_Studio`, `Maestro-Studio`, lowercase forms; base name with channel suffix removed (Nightly, Beta, Alpha, Dev, Canary, Preview, Insider, Edge, Stable, Release, RC, LTS, Developer Edition, Technology Preview); trailing version digits removed ("Bartender 6" → "Bartender") | literal templates. VERIFIED-OSS Mole `app_protection.sh:1117–1136`; Pearcleaner `AppPathsFetch.swift:17–24` |
| `normalized` | lowercase alphanumerics only (`pearFormat`) | fuzzy pass. VERIFIED-OSS Pearcleaner `Logic/Utilities.swift:703` |
| `vendorToken` | `knollsoft` (2nd component of a 3-part bundle ID), team ID | vendor folders (`~/Library/Application Support/<Vendor>/<App>`), Deep mode only |

#### 3.5.2 Candidate generators

**Generator A: exact templates** (Mole style; high precision). For each path that exists, add it.
- User domain:
  - `~/Library/Application Support/{bundleID, name*}`
  - `~/Library/Caches/{bundleID, name*}`
  - `~/Library/Logs/{bundleID, name*}`
  - `~/Library/Preferences/{bundleID}.plist` and `{name}.plist`
  - `~/Library/Saved Application State/{bundleID}.savedState`
  - `~/Library/Containers/{bundleID}`
  - `~/Library/WebKit/{bundleID}` and `~/Library/WebKit/com.apple.WebKit.WebContent/{bundleID}`
  - `~/Library/HTTPStorages/{bundleID}` and `{bundleID}.binarycookies`
  - `~/Library/Cookies/{bundleID}.binarycookies`
  - `~/Library/Application Scripts/{bundleID}`
  - `~/Library/Autosave Information/{bundleID}`
  - `~/Library/SyncedPreferences/{bundleID}.plist`
  - `~/Library/Caches/com.apple.nsurlsessiond/Downloads/{bundleID}`
  - plug-in folders: `~/Library/{Services/*.workflow, QuickLook/*.qlgenerator, Internet Plug-Ins/*.plugin, Audio/Plug-Ins/{Components,VST,VST3}/…, PreferencePanes/*.prefPane, Input Methods/*.app, Screen Savers/*.saver, Frameworks/*.framework, Contextual Menu Items/*.plugin, Spotlight/*.mdimporter, ColorPickers/*.colorPicker, Address Book Plug-Ins/*.bundle, Mail/Bundles/*.mailbundle}` named after the app
  - XDG folders `~/.config/<name>`, `~/.cache/<name>`, `~/.local/share/<name>`, **only through knowledge-base rules** (see safety)
- System domain:
  - `/Library/{Application Support, Caches, Logs}/{name, bundleID}`
  - `/Library/Preferences/{bundleID}.plist`
  - `/Library/LaunchAgents/{bundleID}.plist` and `/Library/LaunchDaemons/{bundleID}.plist`
  - `/Library/Receipts/{bundleID}.{bom,plist}`
  - `/Library/{Frameworks, Internet Plug-Ins, Input Methods, Audio/Plug-Ins/*, QuickLook, PreferencePanes, Screen Savers}/<name>.*`
  - `/Library/Extensions/<name>.kext`
  - `/Library/StartupItems/<name>`

VERIFIED-OSS Mole `app_protection.sh:1099–1290` (`find_app_files`) and `:1903–1990` (`find_app_system_files`).

**Generator B: boundary scans** (bundle-ID prefix at a dot boundary). Scan these one level deep, keeping names that equal the bundle ID, start with `bundleID.`, or end with `.bundleID` / contain `.bundleID.` (Mole's `mole_name_has_bundle_id_boundary`, VERIFIED-OSS `lib/core/base.sh:958–981`):
- `~/Library/Preferences/ByHost/*.plist`
- `~/Library/Group Containers/*`
- `~/Library/Application Scripts/*`
- `~/Library/Containers/*`
- `~/Library/Application Support/FileProvider/*`
- `/Library/LaunchAgents/*.plist` and `/Library/LaunchDaemons/*.plist`
- `/Library/PrivilegedHelperTools/*`
- `/private/var/db/receipts/*`

The "ends with" form catches `S8EX82NJP6.com.macpaw.CleanMyMac5`. Recent-documents lists are matched exactly: `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/<bundleID>.sfl{2,3,4}`. VERIFIED-OSS Mole `app_protection.sh:1375–1478`.

**Generator C: sandbox container metadata.** For `~/Library/Containers/<UUID>` folders (iOS apps, some extensions), read `.com.apple.containermanagerd.metadata.plist` → `MCMMetadataIdentifier` and compare it to the bundle ID or an embedded ID. Also call `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` for each app group. VERIFIED-OSS Pearcleaner `AppPathsFetch.swift:143–183`.
- (added) **Caveat: that call is only a path builder.** On macOS it "always" returns a URL of the expected form, even for an invalid group, so **check existence** before adding a candidate. VERIFIED-APPLE (https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)).
- (added) **Why Group Containers pile up:** Apple documents that on macOS the system creates `~/Library/Group Containers/<group-id>` on first use and **never removes it**, whereas iOS deletes it when the last app in the group goes. So group containers are prime orphan candidates. VERIFIED-APPLE (same page).

**Generator D: fuzzy directory walk** (Pearcleaner style; high recall, needs review).
- Iterate about 70 roots. Depth 1 for most; **depth 2 for `~/Library` and `/Library` roots** to catch vendor folders such as `/Library/Objective-See/LuLu` or `~/Library/Microsoft/Edge`. When the match is at depth 2 under a non-standard parent, add the **parent vendor folder**.
- Skip a large set of Apple/system folder names during the deep pass (`skipDeepSearch`).
- Normalize each entry name (extension stripped for files) and match it against the app's tokens:
  - **Strict**: the normalized name *equals* the app name, path name or letters-only name; or it *contains* the full bundle ID; or it equals an entitlement/binary token.
  - **Enhanced**: adds *contains* matching, the bundle ID's last two components, and the stripped name.
  - **Deep**: adds the company token and the team ID.
- Per-app overrides (`conditions`) include, exclude or force paths. Examples:
  - Chrome includes "google" and "chrome" but excludes "iterm" and "monochrome".
  - Firefox excludes "thunderbird".
  - VS Code force-includes `~/Library/Application Support/Code/`.
  - JetBrains force-includes `~/Library/{Application Support,Caches,Logs}/JetBrains/`.
- Global skips: `.Trash`, `/Library/SystemExtensions`, the Apple password manager browser-extension helper, the names "mobiledocuments", "reminders", "dsstore" and "comapplepasswordmanager". Some `com.apple.*` items are allowed (Configurator, dt, iWork, SF Symbols, TestFlight, sharedfilelist).

VERIFIED-OSS Pearcleaner `Logic/Locations.swift:58–131` (the roots), `AppPathsFetch.swift:190–259` (depth rules), `:323–448` (`specificCondition`), `Logic/Conditions.swift:45–215` (overrides and skips), `:218–257` (`skipDeepSearch`).

**Generator E: Spotlight supplement.** `NSMetadataQuery` in the user's home scope:
- Strict: `kMDItemDisplayName ==[cd] name OR ==[cd] bundleID`, then a post-filter for exact normalized equality.
- Enhanced: `kMDItemDisplayName CONTAINS[cd] name OR kMDItemPath CONTAINS[cd] bundleID`.
- Deep: also comment, creator, copyright and encoding-applications fields, all-words `LIKE`, and optionally `kMDItemTextContent`.
- Limits: 5 s timeout, 500 results maximum.

VERIFIED-OSS Pearcleaner `AppPathsFetch.swift:490–623`.

INFERRED: show Spotlight-only hits as **"Possibly related"**, unchecked.

**Generator F: launchd ownership proof.** For every `*.plist` in `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons` (never `com.apple.*`, never symlinks), the plist is **owned** if any of these hold:
- the filename is `<bundleID>.plist` or starts with `<bundleID>.`;
- `Program`, or `ProgramArguments[0]`, resolves (after `realpath`, with `..` rejected) to a file **inside the app bundle**.

INFERRED additions:
- `BundleProgram` (relative to the app; used by `SMAppService` agents);
- `AssociatedBundleIdentifiers` containing the bundle ID;
- the label equals an `SMPrivilegedExecutables` key.

Name-only matches need the app name to be at least 5 characters and not a common word (Music, Notes, Helper, Agent, Update, Sync, …). VERIFIED-OSS Mole `app_protection.sh:783–831` (`mole_uninstall_launch_agent_owned_by_app`), `app_protection_data.sh:627` (common words).

**Generator G: package receipts.**
- Find receipts whose identifier starts with the bundle ID or a known pkg ID (from a cask `uninstall.pkgutil` or the knowledge base): `pkgutil --pkgs`, or the `/private/var/db/receipts/*.bom|*.plist` names. (added) `pkgutil --pkgs=REGEXP` filters server-side; the `=` is required. VERIFIED-APPLE (`pkgutil.1`).
- (corrected) List payload files with `pkgutil --files <id>` or `lsbom -f -s <bom>`. The paths are **relative to the package's install location, not to `/`**. Prefix each path with the receipt's volume plus install location:
  - from `pkgutil --pkg-info <id>` (`volume:` and `location:` lines);
  - or from the receipt plist key `InstallPrefixPath`.

  VERIFIED-OSS: https://github.com/deploymenttheory/go-macos-pkg `pkg/receipts/receipts.go` ("relative to the install location. InstallLocation on the receipt says where that is") and `internal/cli/receipts.go` (`InstallLocation: r.InstallPrefixPath`). Mole simply strips the leading `.` and assumes `/`. That is right for the common `location: /` case but wrong for packages installed to e.g. `Applications` or `Library/…`. Our engine must honour the prefix.
- Keep only existing, **allowlisted** paths: reject `..`, top-level dirs like `/Applications` and `/Library`, and shared system dirs.
- Remove the payload, then **`pkgutil --forget <id>`**. The man page says `--forget` discards the receipt data "but do[es] not touch the installed files", so it is only the last step. VERIFIED-APPLE (`pkgutil.1`).
- Pearcleaner reads receipts through private PackageKit (`PKReceipt`, `PKBOM`).

VERIFIED-OSS Mole `app_protection.sh:2176–2300` (`find_app_receipt_files`); Pearcleaner `Logic/PKG/PKGManager.swift`, `Logic/Brew/HomebrewUninstaller.swift:498–519` (files → trash → forget).

**Generator H: Homebrew cask `zap`/`uninstall` stanzas** (knowledge-base feed).
- Stanza keys run in this order: `early_script`, `launchctl`, `quit`, `signal`, `login_item`, `kext`, `script`, `pkgutil`, `delete`, `trash`, `rmdir`.
- `zap` is for the fuller removal of `~/Library` preferences, caches and shared resources such as updaters. It must not hit files the user created directly.

VERIFIED [CaskCookbook]. Homebrew-cask is BSD-2-Clause. VERIFIED (https://github.com/Homebrew/homebrew-cask/blob/master/LICENSE).

INFERRED: we ship a pre-processed index `bundleID/appName → {zapTrash[], pkgutil[], launchctl[], quit[], loginItem[]}` built from `formulae.brew.sh/api/cask.json`, refreshed weekly, with attribution. Latest already parses `artifacts.app`, `zap.trash`, `uninstall.quit`, `uninstall.pkgutil` and `uninstall.delete` from that JSON. VERIFIED-OSS Latest `Model/Update Repository/UpdateRepository+Entry.swift:121–205`.

**Generator I: our curated knowledge base.** Signed JSON rules per bundle ID: include, exclude, force-include, force-exclude, shared-with, "use official uninstaller" and "reset keeps". See §3.11. This mirrors the vendor's knowledge base (VERIFIED [DM-1x] 1.10.0; existence of `info.cmmkb` VERIFIED [CMM3-Bundle]).

**Generator J: miscellaneous** (INFERRED):
- `/usr/local/bin` and `/opt/homebrew/bin` **symlinks whose target is inside the app bundle** (`code`, `subl`, `docker`, …). Pearcleaner scans `/usr/local/{bin,etc,opt,sbin,share,var}` by name (VERIFIED-OSS `Locations.swift:116–121`); we only accept symlinks into the bundle.
- Crash reports `~/Library/Logs/DiagnosticReports/<ExecutableName>[-_]*.{ips,crash,diag}` and `/Library/Logs/DiagnosticReports/…`. Pearcleaner lists both directories (VERIFIED-OSS `Locations.swift:84, 112`).
- `~/Library/Application Support/CrashReporter/<Executable>_<UUID>.plist`.
- Darwin per-user dirs `$(getconf DARWIN_USER_CACHE_DIR)/<bundleID>` and `$(getconf DARWIN_USER_TEMP_DIR)/<bundleID>`. Pearcleaner resolves them with `getconf` (VERIFIED-OSS `Logic/Logic.swift:353` `darwinCT`); we use `confstr(_CS_DARWIN_USER_CACHE_DIR)` instead of a shell.
- `/Users/Shared/<name>`. The vendor's own cask zaps `/Users/Shared/CleanMyMac_5` (VERIFIED [Cask]).

#### 3.5.3 Evidence scoring and default selection (INFERRED design)

| Score | Evidence | Default in "Complete uninstall" |
|---|---|---|
| 100 (Owned) | App bundle itself; exact bundle-ID template; bundle-ID boundary match; container metadata match; launchd plist proven owned; receipt whose payload contains the app path; knowledge-base or cask `zap` exact path | **checked** |
| 80 (Strong) | Exact match on an embedded ID, app group, team-prefixed ID or privileged-helper key; exact match on the app name (5+ chars, not a common word) in a standard Library subfolder; vendor-nested `<Vendor>/<App>` where the vendor token comes from the bundle ID | **checked**, unless "shared" (below) |
| 50 (Likely) | Fuzzy contains-match (Enhanced); stripped-name match; bundle ID's last-two-components match | unchecked, listed under "Possibly related" |
| 25 (Weak) | Company or team-ID substring (Deep); Spotlight-only hit | hidden unless sensitivity is Deep |

**Shared-ownership guard.** If a candidate also scores at least 50 for **another installed app** (for example a shared Office group container `UBF8T346G9.Office`, `~/Library/Application Support/Google` used by Chrome and Drive, `JetBrains/` used by several IDEs, or Xcode vs Xcode-beta), mark it "Shared with <App>" and **uncheck** it. Mole implements a sibling guard for Xcode vs Xcode-beta (`MOLE_UNINSTALL_SIBLING_SURVIVES`, VERIFIED-OSS `app_protection.sh:1576–1592`). Pearcleaner encodes the Xcode, Chrome/Edge and Firefox/Thunderbird exclusions (VERIFIED-OSS `Conditions.swift:45–205`).

**Collapse rule.** After collecting, sort paths and drop any path that is a child of an already-selected path. VERIFIED-OSS Pearcleaner `AppPathsFetch.swift:668–680`.

**Sizes.** Use `kMDItemLogicalSize` for files and bundles. For plain directories use real on-disk totals (Spotlight reports wrong sizes for folders). VERIFIED-OSS Pearcleaner `AppPathsFetch.swift:889–909`.

#### 3.5.4 Master table of leftover locations

Column key:
- **U** = default in Complete Uninstall.
- **R** = default in Reset.
- **O** = included in the orphan (Leftovers) scan.
- Root column: ✓ = needs root (via the helper); — = no root needed.

Status: locations are VERIFIED-OSS where a Pearcleaner `Locations.swift`, Mole `find_app_*` or [Cask] reference exists, and INFERRED otherwise. Default columns are our INFERRED policy.

| # | Location | Match | Root | U | R | O | Notes |
|---|---|---|---|---|---|---|---|
| 1 | The `.app` bundle (or outer `.app` for iOS apps; Steam launcher + `steamapps/common/<Game>`) | identity | if root-owned (App Store, pkg installs) | ✔ | ✘ keep | — | Reset "keeps the main binary" (VERIFIED [CMM3-Strings]) |
| 2 | `~/Library/Application Support/<id or name or Vendor/App>` | A, B, D | — | ✔ | ✔ (warn: user data) | ✔ | |
| 3 | `~/Library/Caches/<id or name>`, `<id>.ShipIt` (Squirrel/Electron updater), `com.apple.nsurlsessiond/Downloads/<id>` | A, D | — | ✔ | ✔ | ✔ | |
| 4 | `~/Library/Preferences/<id>.plist`, `<id>.*.plist` | A, B | — | ✔ | ✔ | ✔ | also run `defaults delete <id>` to flush cfprefsd (Mole does: VERIFIED-OSS `lib/uninstall/batch.sh:2689–2696`) |
| 5 | `~/Library/Preferences/ByHost/<id>.<HW-UUID>.plist` | B | — | ✔ | ✔ | ✔ | |
| 6 | `~/Library/Containers/<id>`, `<embeddedID>`, `<UUID>` via metadata | A, B, C | — (FDA or App Data consent) | ✔ | ✔ (warn: sandboxed apps keep documents here) | ✔ | |
| 7 | `~/Library/Group Containers/<TeamID>.<id>`, `group.<id>`, entitlement groups | B, C | — | ✔ unless shared | ✔ unless shared | ✔ | team-prefixed example VERIFIED [Cask] |
| 8 | `~/Library/Application Scripts/<id>`, `<TeamID>.<id>` | A, B | — | ✔ | ✔ | ✔ | example VERIFIED [Cask] |
| 9 | `~/Library/Saved Application State/<id>.savedState` | A | — | ✔ | ✔ | ✔ | |
| 10 | `~/Library/HTTPStorages/<id>`, `<id>.binarycookies` | A | — | ✔ | ✔ | ✔ | example VERIFIED [Cask] |
| 11 | `~/Library/WebKit/<id>`, `~/Library/Cookies/<id>.binarycookies` | A | — | ✔ | ✔ | ✔ | |
| 12 | `~/Library/Logs/<id or name>`, `~/Library/Logs/DiagnosticReports/<exe>*` | A, J | — | ✔ | ✔ | ✔ | |
| 13 | `~/Library/LaunchAgents/<label>.plist` | F | — | ✔ (unload first) | ☐ | ✔ (broken if target missing) | |
| 14 | `~/Library/{Internet Plug-Ins, PreferencePanes, Screen Savers, QuickLook, Spotlight, Services, Input Methods, ColorPickers, Contextual Menu Items, Address Book Plug-Ins, Mail/Bundles, Audio/Plug-Ins/*}/…` | A, D | — | ✔ | ☐ | ✔ | the same items appear in the Extensions manager |
| 15 | `~/Library/Application Support/CrashReporter/<exe>_*.plist` | J | — | ✔ | ✔ | ✔ | |
| 16 | `…/com.apple.sharedfilelist/…ApplicationRecentDocuments/<id>.sfl2/3/4` | B exact | — | ✔ | ✔ | ✔ | |
| 17 | `~/Library/Autosave Information/<id>` | A | — | ☐ (may hold unsaved documents) | ☐ | ☐ | |
| 18 | `~/Library/SyncedPreferences/<id>.plist` | A | — | ✔ | ✔ | ✔ | |
| 19 | `~/Library/Application Support/FileProvider/<extID>` | B | — | ☐ (cloud-sync state) | ☐ | ☐ | |
| 20 | `~/Library/Mobile Documents/<TeamID>~<id with ~>` (iCloud Drive app folder) | iCloud entitlements | — | **never** (shown as info) | never | never | user documents in iCloud |
| 21 | `~/.config/<name>`, `~/.cache/<name>`, `~/.local/share/<name>`, `~/.<name>` | knowledge base only | — | ☐ | ☐ | ☐ | Mole warns that names like "Local" or "Docker" collide with CLI tools (VERIFIED-OSS `app_protection.sh:1144–1151`) |
| 22 | `DARWIN_USER_CACHE_DIR/<id>`, `DARWIN_USER_TEMP_DIR/<id>` | A | — | ✔ | ✔ | ✔ | never for EDR/MDM bundles (Mole `ENDPOINT_SECURITY_BUNDLE_PREFIXES`) |
| 23 | `/Library/Application Support/<id, name, Vendor/App>` | A, D | ✓ | ✔ | ☐ | ✔ | |
| 24 | `/Library/Caches/<id or name>`, `/Library/Logs/<id or name>`, `/Library/Logs/DiagnosticReports/<exe>*` | A, J | ✓ | ✔ | ✔ | ✔ | |
| 25 | `/Library/Preferences/<id>.plist` | A | ✓ | ✔ | ✔ | ✔ | |
| 26 | `/Library/LaunchAgents/*.plist`, `/Library/LaunchDaemons/*.plist` | F | ✓ | ✔ (bootout first) | ☐ | ✔ | |
| 27 | `/Library/PrivilegedHelperTools/<id or label>` | B, `SMPrivilegedExecutables` | ✓ | ✔ | ☐ | ✔ (orphan if parent app missing) | example VERIFIED [Cask] |
| 28 | `/private/var/db/receipts/<pkgid>.{bom,plist}` | G | ✓ | ✔ via `pkgutil --forget` | ✘ | ✔ (receipt whose payload is gone) | |
| 29 | `/Library/Receipts/<name>.pkg` (legacy) | A | ✓ | ✔ | ✘ | ✔ | |
| 30 | `/Library/{Internet Plug-Ins, PreferencePanes, Screen Savers, QuickLook, Spotlight, Input Methods, Audio/Plug-Ins/*, Services, Contextual Menu Items}` | A, D | ✓ | ✔ | ☐ | ✔ | |
| 31 | `/Library/Frameworks/<name>.framework` | A | ✓ | ☐ (frameworks may be shared) | ✘ | ☐ | |
| 32 | `/Library/Extensions/<name>.kext` | A, cask `kext` | ✓ | ☐ needs `kmutil` unload and a reboot | ✘ | ☐ | |
| 33 | `/Library/SystemExtensions/<UUID>/*.systemextension` | `/Library/SystemExtensions/db.plist` | SIP-protected | **cannot delete** ourselves. Ask the host app to deactivate it, or send the user to System Settings › General › Login Items & Extensions › ⋯ › "Delete Extension", then restart (corrected/added, see §3.13) | ✘ | info | §5.2 row 24 |
| 34 | `/Users/Shared/<name>` | A, cask | maybe | ☐ | ✘ | ☐ | |
| 35 | `/usr/local/bin/*`, `/opt/homebrew/bin/*` symlinks into the bundle | J | ✓ (`/usr/local`) | ✔ | ✘ | ✔ (dangling) | |
| 36 | `/private/tmp/<id or name>*` | A | — | ✔ | ✔ | ✔ | |
| 37 (added) | `~/Library/Preferences/<TeamID>.<group-or-id>*.plist`: team-prefixed app-group defaults suites written by non-sandboxed apps | B ("ends with"/contains `.bundleID`) | — | ✔ unless shared | ✔ unless shared | ✔ | VERIFIED: the X cask zaps `~/Library/Preferences/*.com.macpaw.zh.CleanMyMac4*.plist` [CaskZH] |
| 38 (added) | `~/Library/Caches/com.apple.helpd/SDMHelpData/Other/<Language>/HelpSDMIndexFile/<id>.help*` (Help Viewer index of the app's help book) | B exact | — | ✔ | ✔ | ✔ | VERIFIED path pattern [CaskZH] |
| 39 (added) | `~/Pictures/Photos Library.photoslibrary/private/<id>` (per-app data that PhotoKit clients keep inside the Photos library) | exact bundle ID | — (FDA) | ☐ review | ☐ | ☐ | VERIFIED example [CaskZH]. Never default-select: it is inside a library that Photos manages (INFERRED) |
| 40 (added) | App-extension and widget containers: `~/Library/Containers/<id>.<ExtensionName>` and `~/Library/Application Scripts/<id>.<ExtensionName>` | A/B through embedded IDs | — | ✔ | ✔ | ✔ | VERIFIED example: X widget `com.macpaw.zh.CleanMyMac4.CleanMyMacWidget` [CaskZH] |
| 41 (added) | Third-party crash-SDK caches keyed by app: e.g. `~/Library/Caches/com.plausiblelabs.crashreporter.data/<id>`, `~/Library/Caches/com.crashlytics.data/<id>`, `~/Library/Caches/SentryCrash/<AppName>` | B exact | — | ✔ | ✔ | ✔ | INFERRED (common on real Macs; verify per SDK). Note: Pearcleaner's orphan `skipReverse` list contains "sentry", so a naive reverse scan misses these |

**Never touch** (INFERRED, with partial VERIFIED-OSS):
- Keychains (`~/Library/Keychains`)
- Mail, Messages, Photos, Calendars and Contacts libraries
- `/System` and the whole sealed system volume
- `/Library/Apple`
- `/Library/Managed Preferences` (MDM)
- `com.apple.*` items, except those on the allow-list
- `~/Library/Mobile Documents`
- `/private/var/db/com.apple.backgroundtaskmanagement` and `/private/var/db/com.apple.xpc.launchd/disabled.*`
- TCC databases (edit only through `tccutil`)
- Pearcleaner's "blocked roots": `/`, `/Applications`, `/Library`, `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/private`, `/opt`, `$HOME` and the configured app folders themselves (VERIFIED-OSS `Logic/UndoManager.swift:24–57`)
- Library roots matched with an empty token (Mole's safety `case`, VERIFIED-OSS `app_protection.sh:1316–1334`)

#### 3.5.5 Non-file registrations to clean (INFERRED unless noted)

| Registration | Action |
|---|---|
| Loaded launchd jobs | User: `launchctl bootout gui/$UID/<label>`. System: `launchctl bootout system/<label>` (helper). Legacy: `launchctl unload <plist>` (Mole: VERIFIED-OSS `lib/uninstall/batch.sh:378–424`). Login-item helpers: `launchctl bootout gui/$UID/<helperID>`, never for `com.apple.*` (VERIFIED-OSS `batch.sh:340–366`). The `bootstrap \| bootout <domain-target> [service-path …] \| <service-target>` syntax is VERIFIED-APPLE (`launchctl.1`, 11.3 SDK). |
| Legacy login items ("Open at Login") | AppleScript to System Events: delete login items whose name equals the app name, iterating in reverse. Needs Automation consent. VERIFIED-OSS Mole `batch.sh:595–636`; the vendor cask's `login_item:` stanza does the same (VERIFIED [Cask]). |
| BTM records (`SMAppService` login and background items) | No public API to remove another app's records. macOS prunes records for removed apps at next login. Mole only warns when a job is still loaded and deliberately avoids `sfltool dumpbtm`, which prompts for admin. VERIFIED-OSS `batch.sh:110–150` (the claim is Mole's). Never run `sfltool resetbtm` (03-cleanup.md). |
| LaunchServices | `lsregister -u <app path>` before deletion, then `lsregister -gc`. Avoid a full `-kill -r` rebuild, which can kill running extensions such as VPN packet tunnels. VERIFIED-OSS Mole `batch.sh:562–592`. |
| Dock tile | Remove `persistent-apps` entries whose `tile-data.file-data._CFURLString` points at the app (or whose `bundle-identifier` matches), write back, then `killall Dock`. The vendor removes Dock icons on uninstall (VERIFIED [DM-1x] 1.9.0); the mechanism is INFERRED. |
| cfprefsd cache | `defaults delete <bundleID>` if the domain exists (VERIFIED-OSS Mole `batch.sh:2689–2696`). Do this for Reset too, otherwise the app may read cached preferences after its plist is gone. |
| TCC grants | Optional: `tccutil reset All <bundleID>`, which removes stale privacy rows. Default **off** with a checkbox ("Also reset privacy permissions"). (corrected/verified) Syntax: `tccutil reset SERVICE [BUNDLE_ID]`. With a bundle ID, "the service will be reset for that bundle only", and the man page's own example is `tccutil reset All com.apple.Terminal`. VERIFIED-APPLE (`tccutil.1`, 11.3 SDK). **Scope warnings:** (1) **Never omit the bundle ID.** `tccutil reset SystemPolicyAppBundles` with no ID wipes *every* App Management grant on the Mac (VERIFIED-OSS, practitioner reports: https://github.com/entorenee/dotfiles `README.md`, nix-darwin `modules/system/applications.nix`). (2) Practitioner scripts reset per-bundle entries of system-wide services (`ScreenCapture`, `SystemPolicyAppBundles`, `DeveloperTool`) **without sudo** (https://github.com/futile/nixos-config `hosts/hm-cf/setup-macos-permissions.sh`). So run it as the console user first. Whether a root (helper) call is needed for some services on 14/15/26 is INFERRED; test on the Mac mini. |
| (added) Notification Center registration | After an app is deleted, its entry often lingers under System Settings › Notifications, stored in `~/Library/Preferences/com.apple.ncprefs.plist` (`apps[]` with `bundle-id`). INFERRED: **do not edit it by default**. It is a cfprefsd-managed system preference, and a bad write can reset every app's notification settings. At most, offer an advanced "Clean notification list" that edits it with `CFPreferences` and then restarts `usernoted`. |
| (added) System extensions | Not removable by us. See §3.13 and §5.2 row 24. Read `systemextensionsctl list` before and after uninstalling, and report "will finish after restart" when the state is `terminated waiting to uninstall on reboot`. |
| Package receipts | `pkgutil --forget <id>` after the payload is removed (VERIFIED-OSS Pearcleaner `HomebrewUninstaller.swift:518`). |
| Homebrew cask record | If the app came from a cask, offer `brew uninstall --cask --zap <token>` as the user, never root. Otherwise brew still lists the cask as installed. VERIFIED-OSS Pearcleaner `FilesView.swift:312–329`. |
| Quick Look and Spotlight caches | `qlmanage -r cache` after removing Quick Look generators. Spotlight re-imports on its own. |

### 3.6 Execution pipeline (ordered; INFERRED, built on VERIFIED-OSS pieces)

1. **Plan.** Build an `UninstallPlan` of items (path, category, score, needsRoot, action) plus registrations.
   - Validate every path: absolute; no `..`; not a blocked root; not a symlink escaping its parent (resolve with `realpath` and compare the parent); not on the sealed system volume; not under SIP (detect with `stat` flags or by catching `EPERM` early).
   - Pearcleaner clears the immutable flag before trashing (VERIFIED-OSS `Logic/Logic.swift:504–547`).
   - (added) **App Management tripwire.** On Sequoia, even a *no-op* `removexattr` on a signed `.app` raises the App Management prompt "<App> was prevented from modifying apps on your Mac". VERIFIED-OSS: https://github.com/zhom/donutbrowser `src-tauri/src/extraction.rs` (comment). So never touch xattrs or flags inside another app's bundle "just in case". Read first (`getxattr`, `stat` `st_flags`) and only modify what must change. Updates into bundles signed by the **same** team do not prompt (VERIFIED-OSS: https://github.com/Nightbr/factorai `apps/docs/docs/troubleshooting.md`). Since our app has a different team from every app we uninstall, expect the prompt (§3.12).
2. **Confirm.** Show a sheet with:
   - app count, total size and item counts per category;
   - a warning when user data is included (Application Support, Containers, Group Containers);
   - a "Move to Trash" option (default) or "Delete immediately" (advanced).
3. **Quit running processes.** Covers the app, its helpers, and login items listed in `embeddedBundleIDs`.
   - First a polite AppleEvent quit (`tell application id "<id>" to quit` or `NSRunningApplication.terminate()`).
   - Wait up to about 5 s, polling every 0.1 s.
   - If the app is still alive, show a dialog with **Force Quit**, **Skip** and **Cancel**. The vendor offered "Skip" (VERIFIED [DM-1x] 1.9.2). Mole's graceful-quit ladder: VERIFIED-OSS `app_protection.sh:2375–2420`. Pearcleaner only calls `terminate()` (VERIFIED-OSS `Utilities.swift:363`).
   - Skip means: keep the app bundle and still-locked files, and remove the rest.
4. **Pause Trash monitoring** so our own trashing doesn't trigger the prompt. Pearcleaner posts distributed notifications `Pearcleaner.StopFileWatcher` and `Pearcleaner.StartFileWatcher` (VERIFIED-OSS `FilesView.swift:224, 301`; `PearcleanerSentinel/main.swift:26–37`).
5. **Tear down registrations.** launchd bootout, legacy login items, kext unload (prompt for reboot), and `lsregister -u`.
6. **Run the official uninstaller** for knowledge-base "official uninstaller" apps and cask `uninstall.script` entries, after asking the user.
7. **Move files to the Trash.**
   - User-owned files: `FileManager.trashItem(at:resultingItemURL:)`, keeping the returned URLs for Undo.
   - Root-owned files: through the helper, `rename(2)` into `~/.Trash/<App>_<yyyy-MM-dd_HH-mm-ss>/`, de-duplicating names with `-1`, `-2`, ….
   - Pearcleaner groups everything for one app into a timestamped Trash folder, records the moves in a persistent undo history and plays the trash sound (VERIFIED-OSS `Logic/UndoManager.swift:62–175`).
8. **Clean up the system side.** `pkgutil --forget`, `defaults delete`, Dock tile removal, optional `tccutil`, optional `brew uninstall --zap`.
9. **Verify.** Re-stat every path and report three states:
   - removed;
   - "partially removed", with the reason (permission denied, SIP, in use, needs App Management);
   - "skipped".

   The vendor shows "This item was cleaned partially" (see 02-smart-care.md).
10. **Refresh and record.**
    - Drop the app from the list. Pearcleaner distinguishes a **full delete** (bundle removed) from a **semi delete** (only some files), and keeps the app listed after a semi delete (VERIFIED-OSS `FilesView.swift:248–290`).
    - Add the run to our history: who, what, when and where in the Trash, so Undo and Restore work.

### 3.7 Reset (back to first-run state)

**Vendor semantics**
- Reset selects all related items but **keeps the main binary**. VERIFIED [CMM3-Strings].
- The app then starts clean next time. VERIFIED [CMM3-Help-8].
- System apps can be reset. VERIFIED [CMM3-Help-8].
- The App Store edition of 5.x can only reset App Store apps, not delete them. VERIFIED-K (missing-features / uninstaller KB, via 01-overview.md §4.3).

**Our Reset profile (INFERRED)**
- **Select:** rows 2–12, 15, 16, 18 and 22 of the master table, plus `defaults delete <id>`, plus removal of the Saved Application State.
- **Keep:** the bundle, launch agents and helpers (the app may need them, and some reinstall themselves), plug-ins, receipts, `/Library/*` items, and anything shared.
- **Quit the app first.** Reset must not run while the app is open, because the app would rewrite its preferences on quit.
- **Warn** when Containers or Application Support hold documents. Show the largest subfolders, and offer "Keep documents" (excludes `Containers/<id>/Data/Documents`).
- **System apps:** only user-domain items (e.g. `~/Library/Containers/com.apple.Notes`). For Apple apps with SIP- or TCC-protected containers, show "Can't reset: protected by macOS" when `EPERM` is returned. Prefer a short safe list (preferences, caches, saved state) for Apple apps.

### 3.8 Undo and restore (INFERRED; Pearcleaner precedent)

- Keep an in-session `UndoManager` plus a persistent history:

```json
{
  "app": "…",
  "trashFolder": "…",
  "pairs": [ { "original": "…", "trashed": "…" } ]
}
```

- **Restore** moves items back (through the helper for root paths) and removes the empty Trash folder. VERIFIED-OSS Pearcleaner `Logic/UndoManager.swift:176–228`, `Logic/UndoHistoryManager.swift`.
- After the user empties the Trash, mark history entries "not restorable".

### 3.9 Leftovers: files of apps that are already gone (orphan scan)

**Vendor**
- A "Leftovers" scanner exists. Its description says files left by previously uninstalled apps are gathered for review. VERIFIED [CMM3-Strings].
- In CMM3 it lived in System Junk as "Application Leftovers" and was **never selected by default** (03-cleanup.md, VERIFIED-V).
- In 5.x it is an Applications group described as "service files of manually removed apps". VERIFIED-K (uninstaller KB).
- (added) In X it is the second row of the Uninstaller filter column, with a count (8 in the reference screenshot). VERIFIED-PX.
- In 1.8.1 Leftovers learned to include broken launch items. VERIFIED [DM-1x].
- (added, gap 4) **Default selection in 5.x** could not be verified: macpaw.com stayed unreachable, and the 5.0–5.2 DevMate notes have no Applications items. The only primary evidence is CMM3, where Leftovers were never pre-selected (VERIFIED, 13-helpcenter.md §4.2). The Uninstaller and Extensions modules also never pre-select. INFERRED for 5.x: keep the conservative default. Only the "high-confidence" groups in §3.9 step 6 may be checked, and offer a setting "Never pre-select leftovers" that defaults **on** for vendor parity.
- (added, gap 4) **"Link to app" in the vendor:** no evidence in CMM3 strings or the X/5 release notes. The CMM3 strings only have a generic per-item "Add to Ignore List". INFERRED: the vendor has no such feature. Pearcleaner's "Link to app" (below) is the precedent we copy, as an optional extra.

**Pearcleaner's algorithm** (VERIFIED-OSS `Logic/ReversePathsFetch.swift`, `Logic/Locations.swift:133–156`, `Logic/Conditions.swift:260`):
1. Roots, scanned at one level only:
   - `~/Library/{Application Scripts, Application Support, Application Support/Caches, …ApplicationRecentDocuments, Containers, Caches, HTTPStorages, Internet Plug-Ins, LaunchAgents, Logs, Preferences, PreferencePanes, Preferences/ByHost, Saved Application State, WebKit}`
   - `/Users/Shared/Library/Application Support`
   - `/Library/{Application Support, Application Support/CrashReporter, Internet Plug-Ins, LaunchAgents, LaunchDaemons, PrivilegedHelperTools}`
2. For each entry, drop it if any of these hold:
   - it is on the user exclusion list, or its path contains "dsstore";
   - its name is a 32-hex UUID;
   - its normalized name contains any of about 200 `skipReverse` tokens (apple, temporary, icloud, google, microsoft, mozilla, homebrew, sparkle, sentry, webkit, cache, …);
   - its file type is unsupported;
   - it is "related to an installed app": the normalized path contains the bundle ID, name or entitlement token (each at least 5 chars) of any installed app, or a container UUID maps to an installed bundle ID;
   - it is covered by a per-app `conditions` include for an installed app.
3. Stream results in batches of 10.
4. A "Link to app" action associates an orphan with an installed app and removes it from future orphan scans. Associations persist in UserDefaults (`ZombieFileStorage`, `Logic/AppState.swift:571`).
5. The UI disclaimer says the search is best-guess, so the user should confirm (`Views/ZombieView/ZombieView.swift:304`).

**Our improved orphan algorithm (INFERRED)**
1. **Installed index.** Collect every `.app` on all mounted local volumes (Spotlight `com.apple.application-bundle`, plus the configured folders) with: bundle IDs, `bundleIDBase`, embedded IDs, app groups, team IDs, normalized names, executable names and privileged-helper labels.
   - Also index running processes' bundle IDs.
   - Also index Homebrew formula names, so the `~/.config` folders of CLI tools are kept.
   - Also index known system daemon labels.
2. **Candidate extraction.** For each top-level entry in the roots, derive an `ownerKey`:
   - reverse-DNS-like names (2+ dots, valid by Mole's `^[A-Za-z0-9][-A-Za-z0-9]*(\.[A-Za-z0-9][-A-Za-z0-9]*)+$`, VERIFIED-OSS `base.sh:958`) → bundle-ID owner; strip `TeamID.`, `group.` and `.plist` / `.savedState` / `.binarycookies` / ByHost `.<UUID>` suffixes;
   - container UUID → `MCMMetadataIdentifier`;
   - plain names → name owner.
3. **Orphan decision.** An item is an orphan when:
   - its owner key is **not** prefix-matched, at a dot boundary, by any indexed ID or group;
   - for name owners, no indexed normalized name equals it or contains it (5-char minimum);
   - it is not Apple (`com.apple.*`, Apple service names);
   - it is not on the never-touch list or the knowledge-base "system" list;
   - it has no live launchd job or running process.
4. **High-confidence orphans** (eligible for smart-select):
   - reverse-DNS owner, not modified for 30 or more days, and never seen in the installed index during the last N scans (keep a "seen apps" history so apps on a disconnected external drive don't produce false orphans);
   - **broken launchd plists** whose `Program`/`ProgramArguments[0]` no longer exists;
   - `/Library/PrivilegedHelperTools/*` whose LaunchDaemon references a missing parent app;
   - receipts (`pkgutil --pkgs`) whose payload directories are all gone.
5. **Group by owner.** One row per owner key (e.g. "com.example.Foo, 6 items, 812 MB"), expandable to paths. Show the likely app name from the knowledge base, from cask names, or from `CFBundleName` in leftover Saved State.
6. **Defaults.** High-confidence groups are **checked**. Everything else is **unchecked**. This is a deliberate middle ground between CMM3 (never checked) and an aggressive clean.

### 3.10 Trash monitor: "uninstall completely?" when an app is trashed

- **Vendor:** a Menu/agent preference offers a correct uninstall whenever you put an app into the Trash. VERIFIED [CMM3-Strings], [CMM3-Help-94]. In 5.x the Health Monitor agent posts it. VERIFIED-K (01-overview.md §8).
- **Pearcleaner's approach** (VERIFIED-OSS `PearcleanerSentinel/main.swift`, `FileWatcher.swift`, `com.alienator88.PearcleanerSentinel.plist`, `Logic/Logic.swift:1368`):
  - a tiny LaunchAgent (`RunAtLoad` + `KeepAlive`, `AssociatedBundleIdentifiers`) registered through `SMAppService.agent(plistName:)`;
  - an `FSEventStreamCreate` on `~/.Trash` with `kFSEventStreamCreateFlagFileEvents`;
  - for any `.app` event, it checks the item is really in the Trash with `FileManager.getRelationship(_:of: .trashDirectory, in: .userDomainMask, toItemAt:)` and opens the main app via a deep link `pear://openApp?path=…`.
- **Ours (INFERRED):**
  - Run the watcher inside our background "Health Agent" (§7).
  - On a trashed `.app`, read its bundle ID **from the trashed bundle** (it still exists in the Trash) and run the leftover engine.
  - Post a `UNUserNotification` with actions **"Remove leftovers (N MB)"** and **"Ignore"**.
  - Remember "Don't ask again for this app".
  - External volumes: also watch `/Volumes/*/.Trashes/<uid>`.
  - (corrected: now VERIFIED-OSS) **`~/.Trash` is TCC-protected.** Without Full Disk Access, reads return "Operation not permitted" (EPERM). Several independent projects document this, e.g. https://github.com/viniciussouzao/tidymymac `docs/TROUBLESHOOTING.md`, https://github.com/nickj-11/fleetos-downloads-janitor `bin/janitor.sh` ("macOS protects ~/Downloads and ~/.Trash"), and https://github.com/sodadata/tutorial-demo-project `README.md`. The watcher must read the trashed bundle's `Info.plist` to get its bundle ID, so **the agent process needs FDA**.
  - INFERRED: grant FDA to the agent's own code identity, or make the main app the TCC "responsible process" by launching the agent as an embedded login item. Whether FSEvents still delivers raw path events for `~/.Trash` without FDA is untested; do not rely on it. Detect missing FDA in the agent (`open(2)` → `EPERM`) and show "Trash monitoring needs Full Disk Access".

### 3.11 Our knowledge base (vendor-equivalent "Safety Database")

The vendor ships a signed KB and updates it in the background: "Enable background updates of CleanMyMac 3's Safety Database". VERIFIED [CMM3-Strings], [CMM3-Bundle].

Our schema (INFERRED):

```json
{
  "version": 2026101201,
  "signature": "ed25519:…",
  "apps": {
    "com.google.Chrome": {
      "names": ["Google Chrome"],
      "include": ["~/Library/Application Support/Google/Chrome", "~/Library/Caches/Google/Chrome"],
      "exclude": ["~/Library/Application Support/Google/Drive*"],
      "sharedWith": ["com.google.drivefs"],
      "launchd": ["com.google.keystone.agent", "com.google.keystone.xpcservice"],
      "pkgutil": ["com.google.pkg.Keystone"],
      "resetKeep": ["~/Library/Application Support/Google/Chrome/*/Bookmarks"],
      "officialUninstaller": null,
      "updater": { "type": "keystone", "productID": "com.google.Chrome" }
    }
  },
  "neverTouch": ["~/Library/Keychains", "~/Library/Mobile Documents", "…"],
  "appleAllowRemove": ["com.apple.dt.*", "com.apple.iWork.*", "…"],
  "officialUninstallerVendors": [{ "teamID": "X9E956P446", "name": "CrowdStrike" }]
}
```

- **Seed sources:** Homebrew cask `zap`/`uninstall` (BSD-2), our own observations, and Pearcleaner's `conditions` as *ideas only* (its license forbids reuse in a sold product; §8.5).
- **Updates:** download a signed JSON (Ed25519, as Sparkle does) at most daily. Fall back to the bundled copy.

### 3.12 Permissions the Uninstaller needs

| Permission | Why | How to detect / request | Status |
|---|---|---|---|
| Full Disk Access | Read other apps' Containers and Group Containers, `~/Library/Mail`-adjacent paths, `~/.Trash`, TCC-protected folders, system TCC.db | No public API. Try opening protected files. (corrected) MacPaw's PermissionsKit calls `open(path, O_RDONLY)` on four files: `~/Library/Safari/CloudTabs.db`, `~/Library/Safari/Bookmarks.plist`, the **user** TCC.db `~/Library/Application Support/com.apple.TCC/TCC.db` (not the system one), and `/Library/Preferences/com.apple.TimeMachine.plist`. Any successful open means Authorized; `EPERM`/`EACCES` on an existing file means Denied. It opens the pane with `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. Pearcleaner instead checks `FileManager.isReadableFile` on the **system** `/Library/Application Support/com.apple.TCC/TCC.db`. Prefer PermissionsKit's `open(2)` approach, because `access(2)`-style checks look only at POSIX permissions. Poll on app activation. | VERIFIED-OSS (re-read): https://github.com/MacPaw/PermissionsKit `PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m` (MIT); Pearcleaner `Logic/Utilities.swift:790`. The `isReadableFile` caveat is INFERRED |
| App Management (macOS 13+) | Modify other apps' bundles in `/Applications` (and, INFERRED, possibly move or delete them; test on device) | Watch for `EPERM` on trash attempts. Deep-link to System Settings › Privacy & Security › App Management. The TCC service is `kTCCServiceSystemPolicyAppBundles` (Pearcleaner's TCC name map). (added) Verified behaviours: (a) the grant belongs to the **responsible process**, so a helper or agent launched by us may need its own grant (VERIFIED-OSS: https://github.com/Vincent-HD/.nixfiles `docs/research/macos-nix-darwin-patterns.md`, "Pattern 8"); (b) even touching a file inside a bundle, or a no-op xattr removal, triggers it (same source; donutbrowser comment in §3.6); (c) Sparkle's `Autoupdate` gets "kTCCServiceSystemPolicyAppBundles denied" when updating without the grant (VERIFIED-OSS: https://github.com/techgocodingnow/upwork-buddy-project `docs/UPDATES.md`). This also matters for our **Updater** (§4.2.4). | VERIFIED-OSS Pearcleaner `Logic/TCC/TCCModels.swift:95`; behaviours above VERIFIED-OSS (practitioner reports); "delete needs App Management" INFERRED |
| App Data (macOS 14+) | Access another app's container. A consent prompt appears unless FDA is granted. | Covered by FDA. TCC service `kTCCServiceSystemPolicyAppData`. | VERIFIED-OSS `TCCModels.swift:96`; behavior INFERRED |
| Admin rights | `/Library/*`, root-owned App Store or pkg bundles, receipts, LaunchDaemons | Privileged helper registered with `SMAppService.daemon(plistName:)`. Handle `.requiresApproval` by calling `SMAppService.openSystemSettingsLoginItems()`. Validate the XPC client's code signature. | VERIFIED-OSS Pearcleaner `Logic/HelperToolManager.swift:57–104`, `PearcleanerHelper/main.swift:29–94`, `CodesignCheck.swift` |
| Automation (System Events) | Delete legacy login items; quit apps through Apple Events | `NSAppleEventsUsageDescription`; first use triggers the consent prompt | VERIFIED-OSS Mole `batch.sh:595–636` (AppleScript); entitlement INFERRED |
| Notifications | Trash-monitor prompt, "updates available" | `UNUserNotificationCenter.requestAuthorization` | INFERRED (01-overview.md §7) |

**Vendor parallel.** CleanMyMac's privileged **Agent** is installed the first time a root operation is needed. It is used to delete system files, **uninstall some apps** and **remove launch agents**. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent, via 01-overview.md §8).

**Security lesson.** Pearcleaner's helper exposes `runCommand(command:)`, which runs arbitrary `/bin/bash -c` as root, gated only by a code-signing comparison (VERIFIED-OSS `PearcleanerHelper/main.swift:48–68`). CleanMyMac's own helper has had Talos-reported vulnerabilities (TALOS-2018-0716, cited in 03-cleanup.md). Our helper must expose **only typed, policy-checked operations** (§7).

### 3.13 Edge cases checklist (INFERRED)

- **App running from a disk image or App Translocation** (`/private/var/folders/.../AppTranslocation/...`): resolve the original path with `SecTranslocateCreateOriginalPathForURL` or by checking the `com.apple.quarantine` flags, and never delete the read-only DMG. (clarified) `SecTranslocateCreateOriginalPathForURL` is exported by Security.framework (it appears in `Security.tbd`) but has **no public header**, so it is SPI. Load it with `dlsym` and keep a fallback. VERIFIED-OSS (macOS 11 SDK `.tbd` in https://github.com/phracker/MacOSX-SDKs).
- **App on an external volume:** allowed. Leftovers live on the boot volume.
- **Multiple copies of one bundle ID** (Xcode and Xcode-beta, or an app in both `/Applications` and `~/Applications`): apply the sibling guard and keep shared data.
- **App Store apps:** the bundle is root-owned and needs the helper or App Management. **Do not** delete `~/Library/Containers/<id>` when only "Reset" is asked.
- **iOS apps:** remove the outer `.app` (wrapper); the container is the UUID folder from metadata.
- **Electron apps:** `~/Library/Application Support/<Name>`, `~/Library/Caches/<id>.ShipIt`, `~/Library/Saved Application State/<id>.savedState`. Helper bundles use IDs like `<id>.helper`, `<id>.helper.Renderer` and `<id>.helper.GPU`; the boundary match covers them.
- **Apps with system extensions** (VPN, Endpoint Security, DriverKit): we cannot remove the extension. List the item from `/Library/SystemExtensions/db.plist`. KnockKnock parses this database and keeps `activated_enabled` entries (VERIFIED-OSS `Plugins/SystemExtensions.m:22, 48–75`). (corrected; gap 5 answered, with a conflict):
  - **Apple's documentation** says "The system automatically uninstalls any system extensions when the user deletes the corresponding app", and that the host can also submit a deactivation request (`OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier:queue:)`). VERIFIED-APPLE (https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers; the framework overview says deleting the app deletes the extension).
  - **Field measurement on macOS 27 (2026-09)** says deleting the container app *on its own* did **not** remove a network extension: macOS kept running it. It could still be removed in System Settings › General › Login Items & Extensions › Network Extensions › ⋯ › **"Delete Extension"**, and removal finished at the next restart. Until then `systemextensionsctl list` shows `terminated waiting to uninstall on reboot`. VERIFIED-OSS (https://github.com/jo-duchan/tapflow `docs/testing/network-control.md`, `docs/operate/network-extension.md`).
  - **`systemextensionsctl uninstall <teamID> <bundleID>` is refused while SIP is on**, and so is `reset`. VERIFIED-OSS (tapflow, above; https://github.com/ivpn/desktop-app `ui/References/macOS/HelperProjects/SplitTunnelExtension/README.md`).
  - INFERRED reconciliation: Finder-initiated deletion probably triggers the automatic uninstall, while `rm` or a programmatic move may not. **Our flow:**
    1. Before trashing, offer "Open <App> to turn off its extension". Many VPN and EDR apps have a deactivate button.
    2. Trash the app.
    3. Run `systemextensionsctl list`. If the extension is still active, show a card with a button that opens Login Items & Extensions ("Delete Extension", then restart).
  - Test on the Mac mini with a free network-extension app.
- **Kexts:** unload with `kmutil unload -b <id>` (helper), delete, and prompt for a reboot. The auxiliary kernel collection rebuilds on reboot.
- **Configuration profiles installed by the app** (adware, MDM): show them as info and open System Settings › Profiles. Never remove MDM-managed ones.
- **Locked files** (`uchg`): clear the flag (Pearcleaner does, VERIFIED-OSS `Logic.swift:504–547`). Never touch `schg` or SIP-restricted items.
- **Our own app:** a self-uninstall path with the same engine. It must unregister the agent and helper (`SMAppService.unregister()`) **before** trashing. Pearcleaner unloads Sentinel, finds its own files and exits (VERIFIED-OSS `Logic/Logic.swift:1341–1366`).
- **Setapp:** selecting Setapp together with Setapp-managed apps triggers the vendor-style warning (VERIFIED [CMM3-Strings]).
- (added) **pkg installed to a non-root location:** compute payload paths as volume + `InstallPrefixPath` + BOM path (§3.5.2 Generator G). Never assume `/`.
- (added) **Group-container probe side effects:** `containerURL(forSecurityApplicationGroupIdentifier:)` returns a path even for groups that do not exist. On 14+ an actual read of another team's container can raise the "access data from other apps" (App Data) prompt unless we hold FDA. Probe existence with `lstat` on the path, and only list contents after the FDA check.

### 3.14 Installation files (added by fact-checker; answers gap 6 as far as possible)

**Vendor facts**
- 5.x has an Applications category "Installation files" for leftover installers. VERIFIED-K (uninstaller KB, via 01-overview.md and 13-helpcenter.md §3.4).
- X had "Unused Disk Images" and "Old Updates" inside System Junk. 5.x's 12-group System Junk list drops them. So installers most likely moved to Applications › Installation files, and other downloads to My Clutter › Downloads (03-cleanup.md §5.12–5.13; still INFERRED there).
- The exact 5.x rules (file types, age threshold, default selection) are **not verified**: macpaw.com was unreachable and no 5.x release note mentions them.

**Our rules (INFERRED; one owner per file, coordinated with 03-cleanup.md)**

| Item | Match rule | Age gate | Default | Owner |
|---|---|---|---|---|
| Disk images | `~/Downloads/**` (depth ≤ 3) and optionally `~/Desktop`: `.dmg .iso .sparseimage .sparsebundle .img`. Exclude images currently attached (`hdiutil info -plist` → `images[].image-path`). | `kMDItemLastUsedDate`/`kMDItemDateAdded` > 7 d (03-cleanup.md uses 7 d, after MacSai) | ☐. ✔ only when the image's app is already installed (name match `Foo-1.2.dmg` ↔ `Foo.app`, or the bundle ID read from the mounted image on demand) **and** the image is > 30 d old | **Applications › Installation files**. 03-cleanup's `unusedDiskImages` must defer to this group (one owner per file) |
| Flat packages | `.pkg .mpkg` in the same folders | > 7 d | ☐. ✔ if a receipt with a matching ID exists (`pkgutil --pkgs`) and is older than the file | Installation files |
| App archives | `.zip .tar.gz .tgz .xip` whose top-level entry is a `.app` (read the archive's index with `zipinfo -1` or libarchive; never extract) | > 7 d | ☐. ✔ if that app is installed | Installation files; other archives belong to My Clutter › Downloads |
| macOS installers | `/Applications/Install macOS *.app` (`com.apple.InstallAssistant.*`) | > 14 d, not running, not the installed OS (Mole rule, 03-cleanup.md §5.13) | ☐ | Installation files (03-cleanup.md lists it under Old Updates; move ownership here) |
| Never | `/Library/Updates`, `/macOS Install Data`, Sparkle `PersistentDownloads` younger than 10 d, MAU `Clones.noindex` | — | never | (03-cleanup.md §5.13) |

- Show each row with the matched app's icon and "App installed ✓ / not installed". Deleting goes to the Trash.
- Ignore-list key: the file path. Our 5.x-style Ignore List › Applications gets an "Installation files" section (INFERRED; the vendor's documented Applications sections are Uninstaller and Updater).

---

## 4. Updater

### 4.1 Vendor facts

- **Sources and groups.** Sources are App Store, Sparkle, Custom and macOS. The 5.x groups are "App Store Updates", "Sparkle Updates", "Custom Updates" and "macOS Updates". VERIFIED-K (https://macpaw.com/support/cleanmymac-x/knowledgebase/updater; uninstaller KB; via 02-smart-care.md and 01-overview.md).
- **App Store edition:** no App Store or macOS updates. VERIFIED-K.
- **Smart Care's Applications tile** counts available app updates, excluding system apps and macOS updates, all selected by default. **Run** updates the selected apps. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/smart-care, via 02-smart-care.md).
- **Custom-updater support:** Zoom (4.11.2) and Chrome (4.11.3). VERIFIED [DM-X]. (added) 4.13.6 fixed scanning of Microsoft Outlook and **Microsoft AutoUpdate**. INFERRED: MAU-managed Office apps are handled as a "custom" source. VERIFIED [DM-X15].
- (added) **macOS-compatibility filter:** since X 4.13.6 the Updater "won't suggest application updates that are not supported by your macOS version". VERIFIED [DM-X15]. This matches our minimum-OS gate (§4.3).
- (added) **Notifications:** since 4.14.0 the update notification lists the user's **top outdated apps**. VERIFIED [DM-X15].
- (added) **X Updater detail screen** (VERIFIED-PX `reference-updater-details.png`, an App Store app):
  - left list: a "Select All" chip, "Sort by Last Opened ▾", and rows with ⓘ · icon · name · "Version <new>";
  - right pane: the app name as title; a line "Version 4.1.5 ✈ 4.1.11 | <release date> | 454.5 MB"; a horizontally scrolling **screenshot carousel**; a "Recent updates:" release-notes block.
  - INFERRED: for App Store apps these fields map one-to-one onto the iTunes lookup fields `version`, `currentVersionReleaseDate`, `fileSizeBytes`, `screenshotUrls` and `releaseNotes` (§4.2.2).
- (gap 3) **Major or paid updates** and the full **"Custom Updates" app list** remain unverified (macpaw.com unreachable). The only confirmed custom targets are Zoom, Chrome and (scan-level) Microsoft AutoUpdate/Outlook. Nothing primary says how the vendor treats paid major upgrades. Our §4.4 policy stays INFERRED.
- **Bug history:** an update was offered after it was already installed (fixed in 4.12.2). The lesson for us: re-read the installed version **uncached** after every update. Latest flushes the bundle cache with `_CFBundleFlushBundleCaches`. VERIFIED [DM-X]; VERIFIED-OSS Latest `BundleCollector.swift:84–92`.
- **Ignore List › Applications › Updater** exists. VERIFIED-K (https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety, via 01/02).
- **The vendor's self-updater** is a separate LaunchAgent (`com.macpaw.CleanMyMac5.Updater`). In the X era it woke every 6 h. VERIFIED [Cask]; VERIFIED-K (https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes).

### 4.2 Source detection and update-check algorithms

Precedence when an app matches several sources: Latest checks **App Store → Sparkle → Homebrew/database** and uses the first that matches. VERIFIED-OSS Latest `Model/UpdateCheckCoordinator.swift:144–160`. Pearcleaner shows all sources and lets you hide a source per app. VERIFIED-OSS `UpdateManager.swift:202–270`.

#### 4.2.1 Sparkle

- **Feed URL**, in order:
  1. `Info.plist SUFeedURL` (strip `'` and `"` quotes).
  2. If `Contents/Frameworks/DevMateKit.framework` exists: `https://updates.devmate.com/<bundleID>.xml`.
  3. INFERRED: the app's own defaults `SUFeedURL` (`defaults read <id> SUFeedURL`), because apps may set the feed at runtime, e.g. through `SUDefaultsDomain`. VERIFIED-K for the key ([SparkleCust]).

  VERIFIED-OSS Latest `Model/Sparkle/Sparkle.swift:13–40`; Pearcleaner `SparkleUpdateChecker.swift:126–148`.
- **Check engine:** create an `SPUUpdater(hostBundle: appBundle, applicationBundle: appBundle, userDriver: headlessDriver, delegate: self)`, call `start()`, then `checkForUpdates()`.
  - The headless driver answers the permission request with automatic checks off and no system profile.
  - `showUpdateFound` means an update exists.
  - `showUpdateNotFoundWithError` carrying `SUNoUpdateError` and `SPULatestAppcastItemFoundKey` gives the latest item and the reason.

  VERIFIED-OSS Latest `SparkleCheckerOperation.swift`; Pearcleaner `SparkleUpdateChecker.swift:164–470`.
- **Item selection** (Pearcleaner's `bestValidUpdate`, VERIFIED-OSS `:487–590`):
  1. Sort items newest-first by display version.
  2. Skip items whose `minimumSystemVersion` is greater than the current macOS.
  3. Skip non-"release" `sparkle:channel` items unless pre-releases are enabled. Allowed channels then are beta, alpha, nightly, rc and dev.
  4. Skip pre-release-looking version names.
  5. The first remaining item is an update if its display version is greater than the installed one **or** its `sparkle:version` compares (numerically) greater than the installed `CFBundleVersion`.
- **Appcast fields to honor** ([SparklePub], VERIFIED):
  - `sparkle:version` (compared with `CFBundleVersion`) and `sparkle:shortVersionString` (shown to users);
  - `sparkle:minimumSystemVersion` and `sparkle:maximumSystemVersion`;
  - `sparkle:hardwareRequirements` (`arm64`, Sparkle 2.9+; re-verified);
  - `sparkle:minimumUpdateVersion` (Sparkle 2.9+, re-verified);
  - (added) `sparkle:ignoreSkippedUpgradesBelowVersion` (Sparkle 2.1+): re-offers a major upgrade the user skipped earlier;
  - `sparkle:channel`;
  - `sparkle:criticalUpdate`;
  - `sparkle:informationalUpdate` (offer a download link only);
  - `sparkle:phasedRolloutInterval` (ignored for manual checks);
  - `sparkle:minimumAutoupdateVersion` (installed versions below it cannot auto-update: a **major upgrade**);
  - release notes from `description` (HTML, plain-text or markdown), `sparkle:releaseNotesLink` and `sparkle:fullReleaseNotesLink`;
  - `enclosure url/length/type/sparkle:edSignature`.
- **Concurrency:** Latest runs 10 checks at once. Pearcleaner batches by CPU count (5–50). VERIFIED-OSS Latest `UpdateCheckCoordinator.swift:78`; Pearcleaner `SparkleUpdateChecker.swift:68`.

#### 4.2.2 Mac App Store

- **Detect:** `Bundle.appStoreReceiptURL` exists, or iOS apps (receipt path contains `WrappedBundle`, or `Wrapper/iTunesMetadata.plist`). Skip `com.apple.InstallAssistant*` (macOS installers). VERIFIED-OSS Latest `MacAppStoreCheckerOperation.swift:20–28, 57, 71–91`.
- **Query:** `GET https://itunes.apple.com/lookup?bundleId=<id>&country=<region>&entity=desktopSoftware&limit=1`, falling back to `entity=macSoftware`.
  - `desktopSoftware` is more accurate for Mac-native apps. `macSoftware` also covers Catalyst and iOS apps but may return iPad metadata.
  - Pearcleaner uses `id=<adamID>` when known, picks `macSoftware` only for wrapped iOS apps, and retries the regions CN, US, HK, JP, KR and SG.
  - Fields: `version`, `trackId`, `trackViewUrl`, `releaseNotes`, `currentVersionReleaseDate`, `minimumOsVersion`. (added) The detail UI also needs `screenshotUrls` / `ipadScreenshotUrls`, `sellerName` (vendor) and `fileSizeBytes`. Field names VERIFIED-OSS (e.g. https://github.com/pxx917144686/APP `APP/Services/Network/iTunesAPI.swift`, https://github.com/PlayCover/PlayCover `PlayCover/Model/ITunesResponse.swift`).
  - (added) **Only use the iTunes result for apps that carry an App Store receipt.** A directly downloaded build with the same bundle ID would otherwise get App Store metadata and a false "update". The CleanMyMac X replica notes the same rule. VERIFIED-OSS secondary: https://github.com/ddlmanus/MacOptimizer `AppUninstaller/AppUpdaterView.swift`.

  VERIFIED-OSS Latest `:113–175, 205–247`; Pearcleaner `AppStoreUpdateChecker.swift:18, 82–330`.
- **Action:** open `macappstore://` (Latest rewrites `https` to `macappstore` in `trackViewUrl`), or `macappstore://showUpdatesPage`. VERIFIED-OSS Latest `:241`; updates page INFERRED.
  - Latest's in-app update uses private CommerceKit/StoreFoundation (`CKPurchaseController`, `SSPurchase`, `CKDownloadQueue`) (VERIFIED-OSS `Model/Updater/MacAppStoreUpdateOperation.swift`). That is fragile across macOS releases, so we hand off to the App Store app (INFERRED).
  - iOS apps must always be updated through the App Store (VERIFIED-OSS Latest `:96–101`).

#### 4.2.3 Homebrew casks

- **Installed casks:** scan Caskroom (`.metadata/<version>/<timestamp>/Casks/<token>.json` and `INSTALL_RECEIPT.json`).
- **Outdated:** fetch `https://formulae.brew.sh/api/cask/<token>.json`, or the whole `cask.json`, rather than the slow `brew outdated`.
- **Compare** the **actual Info.plist version** against the latest cask version, after stripping brew revision suffixes. This avoids false positives for apps that updated themselves.
- **Optional filter:** hide casks with `auto_updates: true`, which update themselves through Sparkle.
- **Action:** `brew upgrade --cask <token>` as the user.

VERIFIED-OSS Pearcleaner `HomebrewUpdateChecker.swift:9–130`, `Brew/HomebrewController.swift:395–410, 752`; Latest `UpdateRepository.swift:213`. The `auto_updates` meaning is VERIFIED [CaskCookbook].

#### 4.2.4 "Custom" / database updates (apps with no Sparkle and no App Store)

- **Latest's approach** (VERIFIED-OSS `UpdateRepository.swift`, `UpdateRepository+Entry.swift`):
  - Download `https://formulae.brew.sh/api/cask.json` and cache it for **1 hour**.
  - Build entries `{names, bundleIdentifiers, version, token, minimumOS}`:
    - names come from `artifacts.app` (or `uninstall.delete` paths ending in `.app`);
    - bundle IDs come from `zap.trash` path basenames, `uninstall.quit` and `uninstall.pkgutil`;
    - the version is parsed from `"<ver>,<build>"`;
    - the minimum OS comes from `depends_on.macos[">="]`.
  - Match by `.app` filename. If several entries match, disambiguate by bundle ID, and give up if still ambiguous.
  - Skip a remote list of unsupported bundle IDs (`ExcludedAppIdentifiers.plist`, e.g. Spotify, Android Studio, Eclipse packages, Eclectic Light apps).
  - Action: open the app, so it updates itself.
- **Ours (INFERRED): "Custom updaters"**, keyed by knowledge-base `updater.type`:
  - `keystone`: Google apps with `KSProductID` in Info.plist. Launch the app's Keystone agent, or open the app's "About" window.
  - `msautoupdate`: Microsoft AutoUpdate (`com.microsoft.autoupdate2`). Run `msupdate --install --apps <id>` if present, else open MAU.
  - `electron-updater`: `Contents/Resources/app-update.yml` gives `provider` / `url` / `owner` / `repo`. Fetch `latest-mac.yml` (`version:`).
  - `squirrel`: Squirrel/ShipIt with a vendor-specific JSON endpoint, configured in the knowledge base.
  - `zoom`, `mozilla`, `jetbrains-toolbox`, `adobe-cc`: open the vendor updater.
  - `homebrew-db`: Latest-style version lookup only, with the action "Download" (open homepage).
  - **Install** for direct-download updates: download the archive (dmg/zip/pkg); verify the code signature and **team ID equals the installed app's team ID**, plus notarization (`SecStaticCodeCheckValidity` + `spctl --assess --type execute`); swap atomically with `FileManager.replaceItemAt`; relaunch if it was running.
  - (added) **Replacing another vendor's bundle needs App Management.** Our team ID differs from the app's, so macOS shows the "prevented from modifying apps" prompt and denies the write until the user enables our app under Privacy & Security › App Management. Sparkle's own `Autoupdate` hits exactly this (VERIFIED-OSS, see §3.12). Pre-flight: if the App Management grant is missing, prefer "Open app to update" (the app updates itself under its own team) over an in-place swap.

#### 4.2.5 macOS updates

INFERRED:
- List with `softwareupdate --list` (no admin needed). Parse `* Label:` lines and the following `Title, Version, Size, Recommended, Action: restart` line.
- Open System Settings › General › Software Update via `x-apple.systempreferences:com.apple.Software-Update-Settings.extension`.
- Never install macOS in-app: Apple silicon requires an owner's credentials.
- Exclude macOS updates from the Smart-Scan count, as the vendor does (VERIFIED-K).

### 4.3 Version comparison (VERIFIED-OSS, Latest-derived; Pearcleaner copies the same algorithm)

- **Tokenizing:** a `Version` holds `versionNumber` and `buildNumber`. Strings are split by a `Scanner` into **segments**: numeric and string *atoms*, separated by separators. VERIFIED-OSS Latest `Model/Version/Version.swift`; Pearcleaner `AppsUpdater/VersionComparison.swift`.
- **Comparison rules:**
  - Build numbers are compared when both sides have one and the build differs from the version string.
  - Numbers compare numerically; strings compare lexically.
  - String vs number: the string is *older* (`1.2A < 1.2.2`).
  - Trailing `.0` equals nothing (`1.2 == 1.2.0`).
  - A longer numeric tail is newer (`1.2.2 > 1.2`).
- **`sanitize(with:)`** handles feeds that append the build number to the version string.
- **`VersionParser`** strips decorations. VERIFIED-OSS Latest `Model/Version/VersionParser.swift`, `Tests/VersionParserTest.swift:16–33`:
  - build forms: `IU-1234` → `1234`; `1.2/1234` → `1234`; `1.2 (r1234)` → `1234`;
  - version forms: `v1234`, `Build 1234`, `1.2-HEAD-abc`, `1.2-stable.abc`, `1.2.osx14`, `-release`, `-latest`, `-demo`;
  - combined cask versions `1.2,312` or `1.2-312`.
- **Pre-release detection:** a Sparkle channel other than "release", or SemVer-like tags (alpha, beta, rc, dev, nightly, preview). VERIFIED-OSS Pearcleaner `SparkleUpdateChecker.swift:218–238`.
- **Minimum-OS gate:** Latest marks an update unavailable when `minimumOSVersion` is greater than the running OS (`ProcessInfo.isOperatingSystemAtLeast`). VERIFIED-OSS Latest `Model/Update.swift:51–58`.

INFERRED: we show such updates in a separate "Requires macOS X" state, disabled.

### 4.4 Major vs minor updates (INFERRED)

Flag an update as **major** when any of these hold:
- the first numeric component increases (e.g. 5.x → 6.0);
- the appcast's `sparkle:minimumAutoupdateVersion` is greater than the installed `CFBundleVersion` (VERIFIED field semantics, [SparklePub]);
- the knowledge base flags it as a paid upgrade.

Major updates appear in their own section, **unchecked** by default, with a note that they may need a new license. Minor updates are checked by default, which matches the vendor's "all updates selected" Smart Care behavior (VERIFIED-K).

### 4.5 Ignore, skip, hide (INFERRED; OSS precedent VERIFIED-OSS)

- **Pearcleaner's model:**
  - `ignoredApps: [bundleID: [source: version?]]`, persisted as JSON in UserDefaults;
  - `nil` = ignore permanently for that source; a string = **skip only that version** until a newer one appears;
  - separate toggles: show unsupported, show current, include pre-releases, include formulae, show auto-updating casks.

  VERIFIED-OSS `AppsUpdater/UpdateManager.swift:32–33, 202–270`, `UpdaterSettings.swift`.
- **Latest:** a simple ignored-bundle-ID set (`IgnoredAppsKey`); ignored apps are excluded from "updatable" counts. VERIFIED-OSS `Model/AppDataStore.swift:84–170`.
- **Ours:**
  - per-app context menu: "Skip This Version", "Ignore Updates for This App", "Ignore From This Source";
  - an "Ignored" sidebar group;
  - entries are mirrored into Settings › Ignore List › Updater (vendor parity, VERIFIED-K).

### 4.6 Scheduling, caching and notifications (INFERRED)

- Run background checks every 6 h (vendor cadence for its own updater, VERIFIED-K), with jitter.
- Use `If-None-Match`/`ETag` caching for appcasts, a 5 s connect timeout and a 20 s total timeout.
- Cache iTunes lookups for 6 h and `cask.json` for 1 h (Latest uses 1 h, VERIFIED-OSS).
- Post "N app updates available" through the agent. The vendor's X Menu had an "app updates available" notification (VERIFIED-K, 01-overview.md §7).

### 4.7 Updater UI (INFERRED)

- **Sidebar:** All Updates · App Store · Sparkle · Homebrew · Other (custom) · macOS · Ignored.
- **Rows:** checkbox, icon, name, "installed → available", a source badge, a "Running" badge, size if known, release date, and a disclosure for release notes (HTML in a sandboxed `WKWebView`).
- **Footer:** "Update (N)".
- **Per row:** a progress state machine `idle → checking → downloading → extracting → installing → verifying → completed | failed(reason)` (Pearcleaner's `UpdateStatus`, VERIFIED-OSS `Models.swift:35–64`).
- **Running apps:** ask "Quit & Update / Update Later".
- (added) **Detail pane**, mirroring the verified X layout (§4.1):
  - a title;
  - an "installed → available | date | size" line;
  - a screenshot carousel (App Store apps only; Sparkle feeds have no screenshots, so use release notes only);
  - a release-notes block.
- (added) **List controls:** "Select All" and "Sort by Last Opened" (the vendor's X default, VERIFIED-PX), plus Name and Size.

---

## 5. Extensions manager

### 5.1 Vendor facts

- **CMM3 Extensions module scope:** remove or disable widgets, app plug-ins, preference panes, dictionaries, screen savers and login items. VERIFIED [CMM3-Help-91], [CMM3-Strings].
- **Groups shown** ([CMM3-Strings] labels, VERIFIED):
  - Widgets
  - QuickTime Player Plugins
  - Safari Plugins
  - QuickLook Plugins
  - Finder Plugins
  - Spotlight Plugins
  - iTunes plugins
  - Address Book / Contacts Plugins
  - Screen Savers
  - Dictionaries
  - Mail Plugins
  - Audio Plugins ("MAS, AU, and VST")
  - Growl Plugins
  - Login Items
  - Safari Extensions
  - Chrome Extensions
  - Internet Plugins
  - Launch Agents
  - Preference Panes
  - Services and "Siri Activity" ([CMM3-Help-91]; label corrected from the strings)
  - (added) The module blurb reads "Remove or disable your Widgets, Application Plugins, Preference Panes, Dictionaries, Screen Savers, and Login Items". Its clean-log header is "Removing Extensions". The read-only Chrome popover says the item "can be removed from the Extensions section of Google Chrome's Settings". VERIFIED ([CMM3-Strings], re-read)
- **Interaction** (VERIFIED [CMM3-Help-91], [CMM3-Strings]):
  - "View All Extensions"; "Sort by"; Action › Refresh; search.
  - **Nothing pre-selected.** Select All / Deselect All per group. **Remove** deletes.
  - State buttons "Enabled", "Disabled", "Enable", "Disable": hover Enabled to reveal Disable.
  - Disabled items can be re-enabled. Removal cannot be undone ("You can't undo this action").
  - Some enable or disable operations ask for administrator authorization.
  - Some **Chrome extensions are read-only**; the app tells you to remove them in Chrome's Extensions settings.
  - **Siri** can only be disabled (system app).
- **CleanMyMac 1.x:** "Manage Extensions" with Plugins including **Safari Extensions** (1.9.2) and **Scripting Additions** (1.7.2), plus a **Startup Items editor** (1.8.0). VERIFIED [DM-1x].
- **CleanMyMac 5.x:** **Login Items** and **Background Items** are in Performance, with reversible enable/disable and permanent removal. VERIFIED-K (optimization KB). The App Store edition can only review login items and launch agents. VERIFIED-K (01-overview.md §4.3).
- **CleanMyMac X:** had an **Extensions** module under Applications (01-overview.md §5.3 legacy table). (corrected; gap 2 partly answered):
  - **Intro screen** (VERIFIED-PX `reference-extensions-intro.png`, translated): the title "Extensions"; a subtitle about controlling system extensions such as widgets, plug-ins and dictionaries; two benefit rows, "Remove extensions correctly" (safely remove unwanted extensions **and all related items**) and "Disable extensions as needed" (disable temporarily instead of removing); one button, "View Extensions". The art is a puzzle-piece glyph on a pink→violet disc.
  - **Category list** (VERIFIED-OSS, secondary): a pixel replica built from X screenshots implements exactly **Safari Extensions, Internet Plug-ins, Preference Panes, Spotlight Plugins**. Its Chinese descriptions are the vendor's own and still name CleanMyMac. It scans `~/Library/Safari/Extensions`, `{~,}/Library/Internet Plug-Ins`, `{~,}/Library/PreferencePanes` and `{~,}/Library/Spotlight` (https://github.com/ddlmanus/MacOptimizer `AppUninstaller/ExtensionsReplicaView.swift`). INFERRED: X showed only **non-empty** categories, so on other Macs the CMM3 set (Widgets, QuickLook, Screen Savers, Dictionaries, Login Items, Launch Agents, Services, Chrome…) probably appeared too. Chrome/Firefox handling in X is unverified.
  - **5.x:** no Extensions UI found. My Tools lists no Extensions tool; Login Items and Background Items moved to Performance (VERIFIED-K). This is still a GAP (no 5.x screen evidence either way).

### 5.2 Category catalogue: locations, enumeration, enable/disable and removal

Status per row is INFERRED (platform knowledge), except where VERIFIED-OSS evidence is cited in the row.

**Rows 1–4: browser extensions**

1. **Safari extensions (modern: app extensions and Web Extensions)**
   - Locations: `.appex` inside host apps (`Contents/PlugIns/*.appex`).
   - Enumerate: `pluginkit -mAvv -p com.apple.Safari.extension` and `-p com.apple.Safari.content-blocker` (KnockKnock, VERIFIED-OSS `Plugins/BrowserExtensions.m:182–200`, L194). Add `com.apple.Safari.web-extension` (INFERRED).
   - Enable/disable: the user toggles them in Safari › Settings › Extensions. Our "Disable" = `pluginkit -e ignore -i <extID>`. Pearcleaner uses `pluginkit -e use|ignore -i` for its own Finder extension (VERIFIED-OSS `Logic/Logic.swift:797`).
   - Remove: delete the host app, or open Safari Settings. A Safari extension can't exist without its host app.
   - Notes: run `pluginkit` as the console user (KnockKnock note).
2. **Safari legacy `.safariextz`**
   - Locations: `~/Library/Safari/Extensions/` (KnockKnock path, VERIFIED-OSS `BrowserExtensions.m:24`).
   - Enable/disable: n/a (unsupported since Safari 12).
   - Remove: delete the file.
   - Notes: junk on modern macOS.
3. **Chrome and Chromium browsers**
   - Locations: `~/Library/Application Support/Google/Chrome/<Default | Profile N>/Extensions/<id>/<ver>/manifest.json`. Profiles are listed in `Local State` (`profile.info_cache`).
   - Other browsers' roots: Edge `Microsoft Edge/`, Brave `BraveSoftware/Brave-Browser/`, Vivaldi `Vivaldi/`, Opera `com.operasoftware.Opera/`, Arc `Arc/User Data/`, Chromium `Chromium/`.
   - Enumerate: parse `Preferences` and `Secure Preferences` → `extensions.settings.<id>` (`state`, `was_installed_by_default`, `manifest.name/description`, `location`, `from_webstore`). KnockKnock reads both files per profile and skips disabled and default-installed items (VERIFIED-OSS `BrowserExtensions.m:30–38, 377–531`).
   - Enable/disable: **don't edit `Secure Preferences`** (it is HMAC-protected, and Chrome resets tampered settings). Open `chrome://extensions/?id=<id>` or the profile's Extensions page. The vendor marks some items read-only and redirects to Chrome (VERIFIED [CMM3-Strings]).
   - Remove: with the browser **closed**, delete `Extensions/<id>` and remove the `extensions.settings.<id>` entry from `Preferences` (not Secure). Otherwise redirect to Chrome.
   - Also list `External Extensions/*.json` in `~/Library/Application Support/Google/Chrome/` and `/Library/Application Support/Google/Chrome/`, plus policy force-installs (`/Library/Managed Preferences/com.google.Chrome.plist` `ExtensionInstallForcelist`). These are adware vectors: flag them and show the owning profile or app.
4. **Firefox**
   - Locations: `~/Library/Application Support/Firefox/Profiles/<profile>/extensions/<id>.xpi`, plus `extensions.json` and `addons.json`. Profiles are listed in `profiles.ini`.
   - Enumerate: parse `extensions.json` (`addons[]`: `id`, `active`, `userDisabled`, `defaultLocale.name`, `path`). KnockKnock reads `addons.json` and `extensions.json` and resolves `<id>` or `<id>.xpi` (VERIFIED-OSS `BrowserExtensions.m:43, 573–825`).
   - Enable/disable: open `about:addons`. Editing `userDisabled` while Firefox is closed is unsupported and may be reverted.
   - Remove: with Firefox closed, delete the `.xpi`. Firefox drops the entry at next start.

**Rows 5–9: system app extensions and plug-ins**

5. **Other app extensions** (Finder Sync, Share, Action, Photo Editing, File Provider, Quick Look `.appex`, Spotlight import `.appex`, Widgets)
   - Locations: inside host apps' `Contents/PlugIns/*.appex`.
   - Enumerate: `pluginkit -mAvv` (all), or `-p <extension point>` (e.g. `com.apple.FinderSync`, `com.apple.share-services`, `com.apple.quicklook.preview`, `com.apple.quicklook.thumbnail`, `com.apple.widgetkit-extension`, `com.apple.fileprovider-nonui`). KnockKnock's "Extensions and Widgets" runs `pluginkit -vmA` (VERIFIED-OSS `Plugins/Extensions.m:5–68`).
   - Enable/disable: `pluginkit -e ignore|use -i <id>`. System Settings › General › Login Items & Extensions › Extensions (Sequoia/Tahoe).
   - Remove: remove the host app only.
   - Notes: per-user election. (verified) `pluginkit` acts "for the current user". Elections are `use`, `ignore` and **`default`** (added: use `default` to restore the system choice rather than forcing `use`). They apply "to all plug-ins with given identifier". `-i` is shorthand for `NSExtensionIdentifier=`, `-p` for `NSExtensionPointName=`, and `-A`/`-D` show all versions and duplicates. VERIFIED-APPLE (`pluginkit.8`, 11.3 SDK).
6. **Quick Look generators (legacy)**
   - Locations: `/Library/QuickLook`, `~/Library/QuickLook`, `*.qlgenerator`. Pearcleaner's plug-in category (VERIFIED-OSS `Locations.swift:181–185`).
   - Enumerate: `qlmanage -m plugins`. KnockKnock resolves `_QLCopyServerStatistics` (VERIFIED-OSS `Plugins/QuicklookPlugins.m`). `qlmanage -m` "gets all sort of information on Quick Look server including the list of detected generators", and `qlmanage -r` "resets Quick Look Server and all Quick Look client's generator cache". VERIFIED-APPLE (`qlmanage.1`). `-r cache` (thumbnail cache) is documented only in `qlmanage -h` (INFERRED).
   - Enable/disable: move to our Disabled vault, then `qlmanage -r`.
   - Remove: trash, then `qlmanage -r` and `qlmanage -r cache`.
   - Notes: (corrected: now VERIFIED-OSS) **`.qlgenerator` plug-ins are no longer supported on macOS 15 Sequoia and later**; Quick Look app extensions (`.appex`) replace them. Generator authors state this, citing Eclectic Light and Michael Tsai: https://github.com/haokaiyang/Mac-QuickLook `README.md`; https://github.com/srirangav/qlZipInfo `README.txt` ("MacOS X Sequoia (15.x) and newer are not supported because they no longer support the Quicklook generator framework"); https://github.com/sbarex/SourceCodeSyntaxHighlight `README.md`. On the 14/15/26 target, show every `.qlgenerator` on 15+ as **"Obsolete – not loaded by this macOS"** and suggest removal (still unchecked). On 14 they still load.
7. **Spotlight importers**
   - Locations: `/Library/Spotlight`, `~/Library/Spotlight`, app-embedded `Contents/Library/Spotlight/*.mdimporter`. `/System/Library/Spotlight` is read-only (KnockKnock dirs, VERIFIED-OSS `Plugins/SpotlightImporters.m:20`).
   - Enumerate: `mdimport -L` (registered importers). VERIFIED-APPLE (`mdimport.1`: "-L Print the list of installed importers").
   - Enable/disable: vault move, then `mdimport -r <importer path>` or let Spotlight re-scan. VERIFIED-APPLE (`mdimport.1`: `-r` asks the server to reimport files for the UTIs that the listed plug-in claims).
   - Remove: trash (helper for `/Library`).
8. **Preference panes**
   - Locations: `/Library/PreferencePanes`, `~/Library/PreferencePanes`, `*.prefPane` (Pearcleaner, VERIFIED-OSS `Locations.swift:175–179`).
   - Enumerate: walk the directories and read Info.plist (`CFBundleName`, `NSPrefPaneIconLabel`).
   - Enable/disable: vault move (then System Settings shows it gone).
   - Remove: trash (quit System Settings first).
   - Notes: the vendor highlights their scattered support files, so pair them with the leftover engine.
9. **Screen savers**
   - Locations: `/Library/Screen Savers`, `~/Library/Screen Savers`, `*.saver` (VERIFIED-OSS `Locations.swift:187–191`).
   - Enable/disable: vault move. The vendor offered disable (VERIFIED [CMM3-Help-91]).
   - Remove: trash. Reset the screen-saver selection if it was active (`com.apple.screensaver` ByHost `moduleDict`).

**Rows 10–17: user-installable add-ons**

10. **Internet plug-ins (NPAPI)**
    - Locations: `/Library/Internet Plug-Ins`, `~/Library/Internet Plug-Ins`, `*.plugin` and `*.webplugin` (VERIFIED-OSS `Locations.swift:193–197`; `PluginsView.swift:685–686`).
    - Enable/disable: vault move. Remove: trash.
    - Notes: no browser loads NPAPI any more, so these are pure leftovers (Flash, Java, Silverlight). Default "suggest removal" (still unchecked).
11. **Widgets**
    - Modern: WidgetKit `.appex` in host apps. Legacy: `.wdgt` in `/Library/Widgets` and `~/Library/Widgets` (Dashboard; removed in Catalina) (VERIFIED-OSS `Locations.swift:268–272`).
    - Enumerate: `pluginkit -mAvv -p com.apple.widgetkit-extension`.
    - Enable/disable: `pluginkit -e ignore` (modern); vault (legacy).
    - Remove: host app (modern); trash (legacy).
12. **Services** (Finder/app Services menu)
    - Locations: `~/Library/Services/*.workflow|*.service`, `/Library/Services`, and app-declared `NSServices` in Info.plist.
    - Enumerate: walk the directories, plus `pbs -dump`/`-debug` (INFERRED).
    - Enable/disable: write `~/Library/Preferences/pbs.plist` `NSServicesStatus["<bundleID> - <menu title> - <message>"] = {enabled_context_menu: false, enabled_services_menu: false, presentation_modes: {...}}`, then `/System/Library/CoreServices/pbs -flush`.
    - Remove: trash workflows. App services go with their host app.
    - Notes: the vendor lists Services as disable-only (VERIFIED [CMM3-Help-91]).
13. **Dictionaries**
    - Locations: `~/Library/Dictionaries`, `/Library/Dictionaries`, `*.dictionary`. Apple's are in `/System/Library/AssetsV2/...` (read-only) (VERIFIED-OSS `Locations.swift:220–224`).
    - Enable/disable: vault move, or Dictionary.app › Settings toggles (`com.apple.DictionaryServices`).
    - Remove: trash (user and `/Library` only).
14. **Input methods and keyboard layouts**
    - Locations: `/Library/Input Methods`, `~/Library/Input Methods` (`.app` or `.bundle`); `~/Library/Keyboard Layouts` (VERIFIED-OSS `Locations.swift:262–266`).
    - Enable/disable: remove from System Settings › Keyboard › Input Sources first (`com.apple.HIToolbox` `AppleEnabledInputSources`).
    - Remove: trash after removing the source.
    - Notes: Mole protects input methods during cleanup (VERIFIED-OSS `app_protection_data.sh:207–215`).
15. **Color pickers, Core Image filters, Automator actions, Contextual Menu Items, Address Book plug-ins, Mail bundles**
    - Locations: `{/,~/}Library/{ColorPickers, CoreImage, Automator, Contextual Menu Items, Address Book Plug-Ins, Mail/Bundles}` (VERIFIED-OSS `Locations.swift:199–260`).
    - Enable/disable: vault move. Mail bundles: `com.apple.mail` `EnableBundles`.
    - Remove: trash.
    - Notes: Contextual Menu Items are dead since 10.6; Mail bundles were replaced by MailKit `.appex`.
16. **Audio plug-ins**
    - Locations: `{~/,/}Library/Audio/Plug-Ins/{Components (AU), VST, VST3, CLAP, HAL, MAS}`, `/Library/Application Support/{Avid/Audio/Plug-Ins, Digidesign/Plug-Ins}` (AAX) (VERIFIED-OSS `Locations.swift:159–173`).
    - Enumerate: walk the directories. For AU, use `auval -a` (INFERRED).
    - Enable/disable: vault move. Restart `coreaudiod` after HAL changes (`sudo killall coreaudiod`).
    - Remove: trash.
    - Notes: the vendor managed "MAS, AU, and VST" (VERIFIED [CMM3-Strings]). Warn when a DAW is running.
17. **Fonts installed by apps**
    - Locations: `~/Library/Fonts`, `/Library/Fonts` (Pearcleaner lists `~/Library/Fonts`, VERIFIED-OSS `Locations.swift:213–216`).
    - Enumerate: CoreText `CTFontManagerCopyAvailableFontURLs`.
    - Enable/disable: Font Book disable (`CTFontManagerUnregisterFontsForURL` with scope `.user`).
    - Remove: trash.
    - Notes: optional category, default hidden.

**Rows 18–25: startup and system-level items**

18. **Login items (Open at Login)**
    - Locations:
      - BTM database `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` (root);
      - legacy `~/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm` and `~/Library/Preferences/com.apple.loginitems.plist`;
      - `Contents/Library/LoginItems/*.app` inside apps.

      (KnockKnock, VERIFIED-OSS `Plugins/LoginItems.m:25–28, 534–540`; BTM fields VERIFIED-OSS `Libraries/BTM/dumpBTM.h:11–34`.)
    - Enumerate: System Events `login items` (Automation); `sfltool dumpbtm` (root, prompts); or parse BTM through a helper. KnockKnock skips items whose `disposition & 0x1` is unset (not enabled), VERIFIED-OSS `Plugins/BTM.m:97`.
    - Enable/disable: no public API for other apps' `SMAppService` items. Deep-link to System Settings › General › Login Items & Extensions. For legacy items, System Events `delete login item`.
    - Remove: legacy: delete through System Events. `SMAppService` items: remove the app or tell the user. Never `sfltool resetbtm`.
    - Notes: the vendor 5.x places this in Performance (VERIFIED-K).
19. **Launch agents and daemons**
    - Locations: `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, and embedded `Contents/Library/{LaunchAgents,LaunchDaemons}` and `Contents/Resources/{LaunchAgents,LaunchDaemons}` (`SMAppService` and others) (Pearcleaner `DaemonView.swift:375–440`, VERIFIED-OSS).
    - Enumerate: read plists (`Label`, `Program`, `ProgramArguments`, `BundleProgram`, `RunAtLoad`, `KeepAlive`, `StartInterval`). Runtime state from `launchctl list` (user) and `sudo launchctl list` (system), or `launchctl print gui/$UID/<label>`.
    - Enable/disable:
      - Disable: `launchctl disable gui/$UID/<label>` (or `system/<label>`), then `launchctl bootout …`. Persistent overrides are stored by launchd.
      - Enable: `launchctl enable …`, then `launchctl bootstrap gui/$UID <plist>`.
      - (verified/added) The man page says the disabled state "persists across boots". It also says `enable`/`disable` "may only target services within the system domain or user and user-login domains" (VERIFIED-APPLE `launchctl.1`). In practice `gui/<uid>/<label>` is widely used and works (VERIFIED-OSS, e.g. https://github.com/itlackey/akm `src/tasks/backends/launchd.ts`). Fall back to `user/<uid>/<label>` if `gui/` returns an error.
      - (added) **Order matters:** a leftover disable override makes a later `bootstrap` fail silently ("Service is disabled"), so always `enable` before `bootstrap` (VERIFIED-OSS https://github.com/rclone/rclone-ui `src-tauri/src/scheduler/launchd.rs`). A plist that contains `<key>Disabled</key><true/>` makes `bootstrap` fail with "Bootstrap failed: 5: Input/output error" (VERIFIED-OSS https://github.com/armanisadeghi/ai-matrx `scripts/night/plists/…`).
      - (added) **Ownership rules:** plists in `/Library/LaunchAgents` must be owned by root, those in `~/Library/LaunchAgents` by the user, and all LaunchDaemons by root. Group and world write are refused (VERIFIED-APPLE `launchctl.1`, `load` section). Our vault restore must put back exact owner and mode, or launchd refuses the job.
      - Pearcleaner uses the legacy `load`/`unload`, `enable`/`disable`, `kickstart -k` and `remove`, with sudo for daemons and system domains (VERIFIED-OSS `DaemonView.swift:962–1040`).
    - Remove: bootout, then trash the plist (and its helper binary if it lives outside an app).
    - Notes: never touch `com.apple.*` or `/System`. Flag **broken** items whose `Program` is missing.
20. **Privileged helper tools**
    - Locations: `/Library/PrivilegedHelperTools/*`.
    - Enumerate: walk the directory and map each helper to the `/Library/LaunchDaemons/<label>.plist` that references it.
    - Enable/disable: through its LaunchDaemon. Remove: daemon bootout, then trash both.
    - Notes: orphan when the parent app is gone.
21. **Startup items (legacy)**
    - Locations: `/Library/StartupItems` (VERIFIED-OSS Mole `find_app_system_files`).
    - Remove: trash. Notes: dead since 10.10; leftovers.
22. **Scripting additions**
    - Locations: `/Library/ScriptingAdditions/*.osax`, `~/Library/ScriptingAdditions`.
    - Enable/disable: vault. Remove: trash.
    - Notes: the vendor scanned these in 1.7.2 (VERIFIED [DM-1x]). Third-party OSAX are mostly blocked on modern macOS.
23. **Kernel extensions**
    - Locations: `/Library/Extensions/*.kext` (KnockKnock, VERIFIED-OSS `Plugins/Kexts.m:20`).
    - Enumerate: `kmutil showloaded`; `kmutil inspect`. VERIFIED-APPLE (`kmutil.8`).
    - Enable/disable: `kmutil unload -b <id>` (helper); needs a reboot. VERIFIED-APPLE (`kmutil.8`: `unload` takes `-b`/`--bundle-identifier`; it fails if another loaded kext depends on this one).
    - Remove: trash, then rebuild the auxiliary kernel collection on reboot.
    - Notes: review only, with strong warnings.
24. **System extensions** (DriverKit, Network, Endpoint Security)
    - Locations: `/Library/SystemExtensions/<UUID>/*.systemextension`, database `/Library/SystemExtensions/db.plist` (KnockKnock, VERIFIED-OSS `Plugins/SystemExtensions.m:22`).
    - Enumerate: `systemextensionsctl list`, or parse `db.plist` (`extensions[]`: `state == "activated_enabled"`, `originPath`).
    - Enable/disable: only the host app can deactivate (`OSSystemExtensionRequest`). Network extensions can be toggled in System Settings › Network › Filters/VPN.
    - Remove: not possible from a third-party app. `systemextensionsctl uninstall` (and `reset`) is refused with SIP on (now VERIFIED-OSS, §3.13). Show "Open host app", "Open Login Items & Extensions" (where the user can pick ⋯ › "Delete Extension" and restart; VERIFIED-OSS, tapflow docs, macOS 27) and "Reveal".
    - Notes: read-only category. Apple says deleting the host app uninstalls its extensions (VERIFIED-APPLE), but see the §3.13 conflict note.
25. **Authorization plug-ins, Directory Services plug-ins, Dock tile plug-ins**
    - Locations: `/Library/Security/SecurityAgentPlugins/*.bundle`; Directory Services plug-ins; apps whose Info.plist has `NSDockTilePlugIn` (KnockKnock, VERIFIED-OSS `AuthorizationPlugins.m:22`, `DockTiles.m:22`).
    - Enable/disable: n/a.
    - Remove: review only. Breaking these can lock out login.
    - Notes: show in an "Advanced" group, default hidden.

### 5.3 Disable mechanics: the "Disabled vault" (INFERRED design)

- **File-based plug-ins** (prefPane, saver, qlgenerator, mdimporter, plugin, dictionary, osax, audio plug-ins, colorPicker, fonts):
  - "Disable" moves the item to `~/Library/Application Support/<OurApp>/Disabled/<category>/<UUID>/<item>` for user-domain items, or `/Library/Application Support/<OurApp>/Disabled/...` for system items (via the helper).
  - A `manifest.json` records `{originalPath, owner, group, mode, xattrs, disabledAt}`.
  - "Enable" restores to the original path. Refuse if something new is now at that path.
  - Then run the category refresh command (`qlmanage -r`, `mdimport -r`, `pbs -flush`, `killall coreaudiod`, or quit and reopen System Settings).
  - This gives the vendor's semantics: disabling is reversible, removing is permanent (VERIFIED [CMM3-Help-91]).
- **`.appex`:** `pluginkit -e ignore|use -i <id>`. These are per-user elections, with no file moves. VERIFIED-OSS usage in Pearcleaner `Logic.swift:797`.
- **launchd:** `launchctl disable` plus `bootout`, so the item survives a reboot disabled. Enable reverses it, with `enable` **before** `bootstrap` (see §5.2 row 19).
- **Browser extensions:** redirect to the browser's own UI for enable and disable (vendor precedent for read-only Chrome items, VERIFIED [CMM3-Strings]). Removal is supported only while the browser is closed (detect it with `NSRunningApplication` and offer "Quit browser").
- **Admin prompts:** system-domain items go through the helper, which mirrors the vendor's "authorize to enable/disable this extension" alert (VERIFIED [CMM3-Strings]).

### 5.4 Extensions UI (INFERRED)

- **Intro screen** (vendor pattern, VERIFIED-PX): a title, a one-line scope, two benefit rows (remove correctly / disable temporarily), and one primary button. We write our own copy and draw our own art.
- **Left:** a category list with counts and icons; show only non-empty categories (INFERRED from the X replica). Pearcleaner's SF Symbols are a good reference (VERIFIED-OSS `PluginsView.swift:618–640`), e.g. Safari "safari", QuickLook "eye", Spotlight "magnifyingglass", Audio "music.note", Screen Savers "photo.on.rectangle.angled", Services "gear".
- **Main pane:**
  - rows: checkbox, icon, name, owning app (resolved through the leftover engine's reverse lookup), size (computed lazily on row appear, as Pearcleaner does), modified date, an Enabled/Disabled pill (the hover turns it into an action, vendor-style), Reveal, and Info (path, bundle ID, signer, team ID);
  - **nothing pre-selected**; Select All / Deselect All per group;
  - footer **Remove**, with a confirmation that says items go to the Trash.
- **Toolbar:** search, Sort (Name, Category, Size, Date Modified, as in Pearcleaner `PluginSortOption`), Refresh.
- **Badges:** "Broken" (missing target), "Obsolete" (NPAPI, legacy QL, Dashboard), "Unsigned", "Managed by MDM" (read-only).

---

## 6. Applications module: our screens and states (INFERRED; mirrors the vendor flow)

1. **Applications home (scan screen).**
   - "Scan" runs four scanners in parallel: app catalogue, update checks, orphan scan and installers scan.
   - Results stream into **tiles** as they arrive: "N apps (X GB)", "M updates", "K leftovers (Y MB)", "J installers (Z GB)". Vendor flow: tiles, then "Manage My Applications", with background scanning since 5.5.5 (VERIFIED-K).
   - Each tile has "Review"; the footer has the primary button "Manage Applications".
2. **Manage window (3-pane).**
   - **Sidebar sections:** Uninstaller (§3.4 groups, laid out like the verified X filter column: a top block, then "Stores", then "Vendors") · Updater (§4.7) · Leftovers · Installers (§3.14) · Extensions (§5).
   - **List pane:** sort and search.
   - **Detail pane:**
     - app header (icon, name, version, vendor, signature status, source badges, last opened, size);
     - a **mode selector**: "Uninstall completely" / "Reset" / "Custom". These are our own wording, functionally equal to the vendor's "Complete Uninstallation" / "Application Reset" Smart Selector;
     - the **grouped item tree**, with Pearcleaner-like categories (Application Bundles, Preferences, Caches, Application Support, Containers, Logs, Launch Agents & Daemons, Saved Application State, Internet Plug-Ins, Application Scripts, System Files, User Files, Other; VERIFIED-OSS `Views/FilesView/FileCategory.swift:13–126`), each with tri-state checkbox, count and size; rows with Reveal, Quick Look and "Add to Ignore List";
     - a collapsed **"Possibly related"** section for scores 25–69.
   - **Footer:** "Selected: N items, X GB" and a context primary button: **Uninstall** (any app has the bundle selected), **Reset** (Reset mode only), **Remove** (loose files only). This mirrors the vendor's relabeling (VERIFIED [CMM3-Help-8]).
3. **Running-app dialog:** "Quit", "Force Quit", "Skip" (keep locked items), "Cancel".
4. **Progress:** per-app steps (Quitting → Unloading services → Moving to Trash → Cleaning up → Verifying). Log titles "Uninstall Log" and "Removal Log".
5. **Results:** per app "Removed X GB", "Partially removed: 2 items need App Management permission [Grant]", "Reset complete". Buttons: **Undo** (restore from Trash), **Show in Trash**, **Done**.
6. **Empty states:** e.g. "No apps available to uninstall", "No leftovers found". The vendor has playful empty states (VERIFIED [CMM3-Strings]). Write our own copy.
7. **Smart Insights equivalent** (optional, macOS 26 with Apple Intelligence): an info button beside unknown items that asks the on-device Foundation Models framework to explain the item. Vendor feature VERIFIED-K (https://macpaw.com/news/introducing-smart-insights); the API choice is INFERRED.

---

## 7. Recommended implementation architecture (INFERRED)

```
App (SwiftUI, non-sandboxed, Developer ID / local signing)
├── AppCatalogService        // discovery (§3.2), metadata (§3.3), FSEvents/DispatchSource refresh
├── LeftoverEngine
│   ├── TokenFactory         // §3.5.1
│   ├── Generators A–J       // §3.5.2 (async, cancellable, per-root timeouts)
│   ├── Scorer + SharedGuard // §3.5.3
│   └── KnowledgeBase        // signed JSON + cask zap index (§3.11)
├── OrphanScanner            // §3.9 (uses AppCatalog index + "seen apps" history)
├── UninstallPlanner/Executor// §3.6 (plan → confirm → quit → teardown → trash → verify → record)
├── UndoStore                // persistent history (§3.8)
├── UpdateEngine
│   ├── SparkleProvider      // Sparkle.framework headless SPUUpdater, or own appcast parser
│   ├── AppStoreProvider     // iTunes lookup
│   ├── HomebrewProvider     // Caskroom + formulae API
│   ├── CustomProvider       // KB-driven vendor updaters + cask.json DB
│   └── MacOSProvider        // softwareupdate --list
├── VersionKit               // own implementation of the §4.3 semantics (do not copy GPL code)
├── ExtensionsCatalog        // providers per §5.2 row + DisabledVault (§5.3)
├── HealthAgent (LaunchAgent via SMAppService.agent) // Trash monitor (§3.10), update checks, notifications
└── PrivilegedHelper (LaunchDaemon via SMAppService.daemon, NSXPC)
```

Helper XPC interface: typed operations only, no shell strings.

```swift
@objc protocol HelperXPC {
  func trashItems(_ paths: [String], intoTrashFolderNamed: String,
                  reply: @escaping (_ moved: [String: String], _ errors: [String: String]) -> Void)
  func restoreItems(_ pairs: [String: String], reply: @escaping ([String: String]) -> Void)
  func launchctlBootout(domain: String, label: String, reply: @escaping (Int32) -> Void) // "system" or "gui/<uid>"
  func launchctlSetEnabled(domain: String, label: String, enabled: Bool, reply: @escaping (Int32) -> Void)
  func pkgForget(_ packageID: String, reply: @escaping (Int32) -> Void)
  func pkgFiles(_ packageID: String, reply: @escaping ([String]) -> Void)
  func moveToVault(_ path: String, vaultID: String, reply: @escaping (String?) -> Void)
  func restoreFromVault(_ vaultID: String, reply: @escaping (String?) -> Void)
  func kextUnload(bundleID: String, reply: @escaping (Int32) -> Void)
}
```

**Helper policy**
- Accept only the main app: `NSXPCConnection.setCodeSigningRequirement("anchor apple generic and identifier \"<ours>\" and certificate leaf[subject.OU] = \"<TEAMID>\"")` on macOS 13+.
- Paths must be absolute and canonical, under allowlisted roots (`/Applications`, `/Library/{Application Support,Caches,Logs,Preferences,LaunchAgents,LaunchDaemons,PrivilegedHelperTools,Extensions,Internet Plug-Ins,PreferencePanes,Screen Savers,QuickLook,Spotlight,Audio,Input Methods,Services,Frameworks,Receipts,ScriptingAdditions}`, `/private/var/db/receipts`, `/Users/Shared`, `/usr/local/bin`), and not a root itself.
- Labels must match the reverse-DNS regex and must not be `com.apple.*`.
- Log every operation to `/Library/Logs/<OurApp>/helper.log`.

Pearcleaner and the vendor show why this matters (§3.12).

**Concurrency and performance targets**
- App catalogue: under 1.5 s for 300 apps, using metadata first and the expensive work later. Pearcleaner's two-phase "mini → full" `AppInfo` loading is the model (VERIFIED-OSS `Logic/Logic.swift:229–330`).
- Leftover search per app: under 2 s. Use a task group per root, an overall deadline, and lazy size computation.
- Orphan scan: under 10 s, streaming results.

---

## 8. Open-source deep dives (file references)

### 8.1 Pearcleaner (alienator88/Pearcleaner)

Commit `7724df7`, 2026-06-22. Apache-2.0 with **Commons Clause**. The project is "On Hold". VERIFIED-OSS `README.md`, `LICENSE.md`.

| File | What to learn |
|---|---|
| `Pearcleaner/Logic/Locations.swift` | `standardLibrarySubdirectories` (L25). `apps` search roots (L58–131), which include `~/Documents`, `~/Desktop` (Steam shortcuts), `~/.config`, Steam dirs, recent-documents, `/usr/local/*`, `/private/tmp` and Darwin cache/temp dirs; Application Support subfolders are appended dynamically (filtered by `listAppSupportDirectories`). `reverse` roots for orphans (L133–156). `plugins` categories with paths (L158–273). |
| `Logic/AppPathsFetch.swift` | `cachedIdentifiers` construction (L73–131). `getAllContainers` (L143). `processLocation` depth rules and the vendor-folder parent rule (L190–259). `specificCondition` matching logic (L323–448). `isValidBundleIdentifier` (single-component IDs need 5+ chars, L481). Spotlight supplement (L490–623). `finalizeCollection` (outliers, exclusions, child-path collapse, L626–700 (collapse loop L668–680)). Post-processing sizes and icons (L759–820). Spotlight vs manual size (L889–909). |
| `Logic/Conditions.swift` | Per-app `Condition{bundle_id, include, exclude, includeForce, excludeForce}` (L45–200). `skipConditions` (L207). `skipDeepSearch` (L218). `skipReverse` token list (L260). |
| `Logic/ReversePathsFetch.swift` | Orphan search: `processItem` (L207), `isRelatedToInstalledApp` (5-char minimum; container UUID mapping, L227), `isExcludedByConditions` (L257), UUID filter (L280), streaming batches. |
| `Logic/AppInfoFetch.swift` | Metadata fast path, two-phase loading, Sparkle, Setapp and App Store detection (L288–343), web apps (L345), `getMDLSMetadata` (L392), Steam (L593), entitlements and binary names (L691), team ID (L788). |
| `Logic/Logic.swift` | `getSortedApps` (L133). `darwinCT` (L353). `listAppSupportDirectories`, which excludes `com.apple*` and an Apple folder list (L383). `moveFilesToTrash` and immutable-flag handling (L474–547). Cask lookup table (L829–1000). Finder extension toggle through `pluginkit` (L797). Self-uninstall (L1341). Sentinel agent through `SMAppService.agent` (L1368). |
| `Logic/UndoManager.swift` | Blocked-root validation (L24). Trash bundle folder plus `mv` through helper or Authorization, with undo registration (L62–175). Restore (L176). |
| `Views/FilesView/FilesView.swift`, `FileCategory.swift` | Uninstall flow: stop watcher → `killApp` → trash → full/semi delete → Homebrew zap → next queued app (L213–360). Category grouping (L13–126). |
| `PearcleanerSentinel/*` | FSEvents on `~/.Trash`, `isInTrash` relationship check, deep link. KeepAlive LaunchAgent plist. |
| `PearcleanerHelper/*`, `Logic/HelperToolManager.swift` | `SMAppService.daemon` registration and approval flow; XPC listener; code-signing match. **Anti-pattern:** arbitrary bash `runCommand`. |
| `Logic/PKG/PKGManager.swift`, `Logic/Brew/HomebrewUninstaller.swift` | Receipts through private PackageKit (`PKReceipt`, `PKBOM`). Cask uninstall directive handling, including `pkgutil --files` → trash → `--forget` (L498–519). |
| `Views/PluginsView.swift` | Category scan, extension filters per category (`shouldIncludeFile`, L664–760), deletion through the same Trash pipeline. |
| `Views/DaemonView.swift` | Launch-item inventory (user, global and system dirs, plus plists embedded in apps); `launchctl list` runtime status; load, unload, enable, disable, kickstart and remove actions (L962–1040). |
| `Logic/AppsUpdater/*` | `SparkleUpdateChecker.swift` (headless SPUUpdater, `bestValidUpdate`). `AppStoreUpdateChecker.swift` (iTunes lookup, regions). `HomebrewUpdateChecker.swift` (Info.plist version as ground truth). `VersionComparison.swift`. `UpdateManager.swift` (ignore and skip-version storage). `Models.swift` (sources and status machine). `UpdaterSettings.swift` (toggles). |
| `FinderOpen/FinderOpen.swift` | Finder Sync extension adding "Uninstall" to the context menu of a single `.app`, opening the main app through a URL scheme. INFERRED: a nice optional feature for us. |

### 8.2 Latest (mangerlahn/Latest)

Commit `1301cf6`, 2026-07-18. **GPL-3.0**. VERIFIED-OSS `LICENSE`, `README.md`.

| File | What to learn |
|---|---|
| `Latest/Model/Directory/AppDirectoryStore.swift` | Default folders from `.applicationDirectory` in local and user domains, plus user-added folders. |
| `Model/Directory/AppDirectory.swift`, `AppLibrary.swift` | Per-folder `DispatchSource` `.write` watcher; 10 s coalescing; initial `DispatchGroup`. |
| `Model/Directory/BundleCollector.swift` | Enumerator with `.skipsPackageDescendants`. Excludes Setapp folders and Safari web apps. Uncached `CFBundleVersion` through `_CFBundleFlushBundleCaches`. Requires name, ID, version and a source. |
| `Model/UpdateCheckCoordinator.swift` | Operation queue (10 concurrent). Source precedence App Store → Sparkle → Homebrew-repository. |
| `Model/Update Checker Extensions/App Store/MacAppStoreCheckerOperation.swift` | Receipt and `WrappedBundle` detection; `desktopSoftware` → `macSoftware` fallback; `macappstore://` URL; minimum OS; iOS apps open the App Store instead of updating in-app. |
| `Model/Update Checker Extensions/Sparkle/SparkleCheckerOperation.swift`, `Model/Sparkle/Sparkle.swift` | Headless `SPUUserDriver`; feed URL with DevMate fallback; mapping of release notes and minimum OS. |
| `Model/Update Repository/UpdateRepository.swift`, `+Entry.swift` | Homebrew `cask.json` as a version database; name and bundle-ID extraction from artifacts, `zap` and `uninstall`; ambiguity resolution; 1 h cache; remote unsupported list. |
| `Model/Version/Version.swift`, `VersionParser.swift`, `Tests/*` | Version semantics and parser patterns, with tests. |
| `Model/Update.swift`, `Model/AppDataStore.swift` | `updateAvailable` with the minimum-OS gate; ignored-apps set. |
| `Model/Updater/SparkleUpdateOperation.swift`, `MacAppStoreUpdateOperation.swift` | Installing a third-party app's Sparkle update by replying `.install` from a custom user driver. Private CommerceKit purchase/download flow for App Store apps (fragile). |

### 8.3 Mole (tw93/Mole)

Commit `49475f1`, 2026-10-11. **GPL-3.0**. The uninstall logic is the most safety-hardened of the three.

| File | What to learn |
|---|---|
| `lib/core/app_protection.sh:1099–1900` `find_app_files` | Exact path templates, name variants, bundle-leaf derivation guard (L1205–1245), ByHost, Group Containers, derived extension roots, recent-docs, embedded IDs, launch-agent ownership phases. |
| `lib/core/app_protection.sh:1903–2175` `find_app_system_files` | `/Library` templates, vendor-nested, `/Users/Shared`, LaunchAgents/Daemons by bundle ID and by name (with guards), PrivilegedHelperTools, receipts. |
| `lib/core/app_protection.sh:783–831` | Proof of launchd ownership. |
| `lib/core/app_protection.sh:2176–2300` | Receipt BOM payload discovery with allowlist and traversal protection. |
| `lib/core/base.sh:958–981` | Reverse-DNS validation and dot-boundary helpers. |
| `lib/core/app_protection_data.sh` | `SYSTEM_CRITICAL_BUNDLES`, `APPLE_UNINSTALLABLE_APPS`, `OFFICIAL_UNINSTALLER_RULES`, `ENDPOINT_SECURITY_BUNDLE_PREFIXES`, `DATA_PROTECTED_BUNDLES`, `LAUNCH_AGENT_NAME_COMMON_WORDS`. |
| `lib/uninstall/batch.sh` | Teardown: login-item helper bootout (L340–366), launch-plist unload with identity re-check (L378–424), `lsregister -u` and `-gc` (L562–592), System Events login-item deletion (L595–636), `defaults delete` (L2689–2696), BTM residue rationale (L110–150). |

### 8.4 KnockKnock (objective-see/KnockKnock)

Commit `914f2c0`, 2026-09-15. **GPL-3.0**. A persistence enumerator, useful for Extensions inventory techniques.

`Plugins/BrowserExtensions.m`, `Extensions.m`, `QuicklookPlugins.m`, `SpotlightImporters.m`, `SystemExtensions.m`, `Kexts.m`, `LoginItems.m`, `BTM.m`, `LaunchItems.m`, `DockTiles.m`, `AuthorizationPlugins.m` and `Libraries/BTM/dumpBTM.h`. Details are cited in §5.2.

### 8.5 Licensing implications (INFERRED legal hygiene)

- **Latest, Mole and KnockKnock (GPL-3.0):** study the algorithms; **do not copy code** into our app unless the whole app is GPL.
- **Pearcleaner (Apache-2.0 + Commons Clause):** forbids selling a product whose value derives from it. Its personal use is fine, but **don't copy code**; reimplement.
- **Homebrew-cask data (BSD-2-Clause):** OK to ingest with attribution.
- **Sparkle framework (MIT):** OK to link for the headless checker and installer.
- **MacPaw strings and Help text:** used here only as research evidence. **Never ship the vendor's wording, names, icons or illustrations.**

---

## 9. Test matrix for the Mac mini (INFERRED)

| Case | Expectation |
|---|---|
| Uninstall a Sparkle app (e.g. Rectangle) | Removes the bundle, `~/Library/Preferences/com.knollsoft.Rectangle.plist`, `Caches/com.knollsoft.Rectangle`, `HTTPStorages/…`, the login item. Nothing from other apps. |
| Uninstall an App Store app (e.g. Amphetamine) | Helper/App Management path; container `~/Library/Containers/com.if.Amphetamine` removed; receipt not applicable. |
| Uninstall a pkg-installed app with a daemon (e.g. a VPN client) | Daemon bootout; PrivilegedHelperTools item removed; `pkgutil --forget`; system extension flagged as "deactivate in app". |
| Uninstall Electron (Slack/VS Code) | `ShipIt` caches and helper `<id>.helper*` data; VS Code `~/Library/Application Support/Code` via knowledge-base force include; `/usr/local/bin/code` symlink. |
| Uninstall Xcode-beta while Xcode is installed | Shared Developer folders and `com.apple.dt.*` preferences **kept** (sibling guard). |
| Microsoft Word only (Excel installed) | `UBF8T346G9.Office` group container **unchecked, "Shared with Excel"**. |
| Reset Safari / Notes (system) | User-domain prefs and caches only; SIP/TCC-protected parts reported. |
| iPad app on Apple silicon | Outer `.app` and UUID container removed. |
| Trash-drag of an app | Notification within 2 s; action removes leftovers. |
| Orphans after manual delete | `com.example.App` items grouped and high-confidence checked; Homebrew CLI `~/.config/<tool>` **not** flagged. |
| Updates | Sparkle app with beta channel hidden unless toggle on; App Store app shows `trackViewUrl`; brew cask auto-updated app not shown as outdated; major bump unchecked. |
| Extensions | Disable/enable a screen saver round-trips byte-identical; `pluginkit` ignore hides a Finder Sync extension; Chrome extension removal blocked while Chrome runs. |
| (added) App with a network/system extension | Pre-uninstall card offers "turn off in app". After trashing, `systemextensionsctl list` is checked; a lingering extension yields the "Delete Extension in Login Items & Extensions, then restart" card. |
| (added) `.qlgenerator` on macOS 15/26 | Listed as "Obsolete – not loaded"; removal works; `qlmanage -r` runs. |
| (added) pkg with non-`/` install location | Payload paths resolved with `InstallPrefixPath`; nothing outside the prefix is touched; `pkgutil --forget` last. |
| (added) Trash monitor without FDA | Agent detects EPERM on `~/.Trash` and asks for FDA; no false "nothing found". |
| (added) Updater in-place install without App Management | The pre-flight sees no grant and offers "Open app to update" instead of a failing swap. |
| (added) Vendor footprint (CleanMyMac 5 cask list, §1 item 7) | Engine finds `HealthMonitor`/`Menu` jobs via `AssociatedBundleIdentifiers`/`BundleProgram`, the name-based `Application Support/CleanMyMac_5`, and the Team-ID-prefixed group container. |

---

## 10. Gaps and open questions

Status after the fact-check pass (2026-10-12) is given in brackets.

1. **Exact CleanMyMac X/5 Uninstaller sidebar groups.** [**X: ANSWERED, VERIFIED-PX.** The groups are All Applications · Leftovers · Suspicious · Selected · Stores (App Store, Other) · Vendors (…, Other). No Intel or 32-bit group appears. **5.x: still open.** Only All Applications, Unused and Suspicious are confirmed (VERIFIED-K). Whether 5.x keeps Stores and Vendors is unknown. Check https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller when it is reachable.]
2. **CleanMyMac X Extensions module category list, and any 5.x Extensions UI.** [**PARTLY ANSWERED.** The X intro screen is VERIFIED-PX. X categories seen: Safari Extensions, Internet Plug-ins, Preference Panes, Spotlight Plugins (replica built from screenshots, VERIFIED-OSS secondary). The full X list is still unverified. 5.x: no Extensions tool in My Tools (VERIFIED-K), so it is probably dropped (INFERRED). Check https://macpaw.com/support/cleanmymac-x/knowledgebase/extensions.]
3. **How the vendor's Updater treats "major" (paid) updates and its "Custom Updates" database.** [**PARTLY ANSWERED.** It hides updates that the running macOS does not support (4.13.6). The custom targets are Zoom, Chrome and Microsoft AutoUpdate/Outlook scanning (4.13.6), and notifications list top outdated apps (4.14.0); all VERIFIED [DM-X15]. Paid-major handling and the full list are still unknown.]
4. **How 5.x's Leftovers decides default selection, and whether "Link to app" exists.** [**OPEN** for 5.x. CMM3 never pre-selected (VERIFIED). No vendor "link" feature was found in any primary text (INFERRED: absent).]
5. **Platform behaviors to confirm on the Mac mini:**
   - App Management prompts when trashing other apps' bundles on macOS 14, 15 and 26. [**PARTLY.** Modifying contents, or even a no-op xattr change, triggers it on Sequoia, and same-team updates do not (VERIFIED-OSS). Whether moving or deleting the whole bundle triggers it is still a device test.]
   - Whether `~/.Trash` FSEvents need FDA. [**ANSWERED for reads.** Reading `~/.Trash` without FDA gives EPERM (VERIFIED-OSS), so the agent needs FDA. Raw FSEvents delivery without FDA is untested.]
   - Quick Look generator support status on Sequoia and Tahoe. [**ANSWERED.** Unsupported on 15+ (VERIFIED-OSS).]
   - Whether deleting a host app removes its system extension automatically. [**CONFLICT.** Apple says yes (VERIFIED-APPLE). A macOS 27 field test says app deletion alone left a network extension running; it was removed through System Settings › Login Items & Extensions › "Delete Extension" plus a restart. `systemextensionsctl uninstall` is refused with SIP on (VERIFIED-OSS). Test on device.]
   - The `tccutil reset All <id>` scope. [**ANSWERED (syntax and per-bundle scope, VERIFIED-APPLE).** Omitting the ID wipes the service for all apps (VERIFIED-OSS). Per-bundle resets of system-wide services work without sudo in practitioner scripts. Behaviour of a root call is still untested.]
6. **"Installation files" group rules.** [**OPEN for the vendor.** Our rules are now specified in §3.14 and coordinated with 03-cleanup.md §5.12–5.13.]
7. (added) **5.x Uninstaller detail-pane layout** (file categories, Reset control placement, Smart Insights button): no 5.x screenshot or text was reachable.
8. (added) **Vendor handling of system extensions and Notification Center entries on uninstall:** unknown.

---

## 11. Sources

**MacPaw primary (read this session)**
- CleanMyMac 3.9 in-app Help (MacPaw-authored), mirror repo https://github.com/auspham/mac-essential (commit 7004fca):
  - topic-8 Uninstaller: https://github.com/auspham/mac-essential/blob/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-8.html
  - topic-91 Extensions: …/English.lproj/topic-91.html
  - topic-94 CleanMyMac 3 Menu: …/English.lproj/topic-94.html
  - topic-9 Maintenance and index/overview: …/topic-9.html, …/index.html
- CleanMyMac 3.9 UI strings and plists (same mirror):
  - `Contents/Resources/Base.lproj/Localizable.strings`
  - `Base.lproj/Alerts.strings`
  - `en.lproj/ApplicationsScanResultsView.strings`
  - `en.lproj/CMIgnoreListPreferencesViewController.strings`
  - `en.lproj/CMMenuPreferencesViewController.strings`
  - `en.lproj/CMUpdatesPreferencesViewController.strings`
  - `Contents/Info.plist`
  - `Contents/PlugIns/StorageManagement.appex/Contents/Info.plist`
- DevMate release notes:
  - CleanMyMac 1.x: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html
  - CleanMyMac X 4.10–4.12: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
  - CleanMyMac 5.0–5.2: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html (no Applications items)
- MacPaw PermissionsKit: https://github.com/MacPaw/PermissionsKit
- MacPaw CleanMyMac CLI (no leftovers or uninstall commands): https://github.com/MacPaw/cleanmymac-cli and https://github.com/MacPaw/cleanmymac-cli/wiki/Commands

**MacPaw KB (via sibling reports 01/02/03/04; macpaw.com unreachable from this sandbox)**
- https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller
- https://macpaw.com/support/cleanmymac-x/knowledgebase/updater
- https://macpaw.com/support/cleanmymac/knowledgebase/smart-care
- https://macpaw.com/support/cleanmymac/knowledgebase/missing-features
- https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features
- https://macpaw.com/support/cleanmymac/knowledgebase/optimization
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-agent
- https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes
- https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes
- https://macpaw.com/cleanmymac/whats-new
- https://macpaw.com/news/introducing-smart-insights

**Homebrew and Sparkle**
- CleanMyMac cask: https://github.com/Homebrew/homebrew-cask/blob/master/Casks/c/cleanmymac.rb
- homebrew-cask license (BSD-2-Clause): https://github.com/Homebrew/homebrew-cask/blob/master/LICENSE
- Cask Cookbook: https://github.com/Homebrew/brew/blob/main/docs/Cask-Cookbook.md
- Sparkle publishing docs: https://github.com/sparkle-project/sparkle-project.github.io/blob/master/documentation/publishing/index.md
- Sparkle customization docs: https://github.com/sparkle-project/sparkle-project.github.io/blob/master/documentation/customization/index.md

**Open-source code (cloned and read)**
- https://github.com/alienator88/Pearcleaner (7724df7)
- https://github.com/mangerlahn/Latest (1301cf6)
- https://github.com/tw93/Mole (49475f1)
- https://github.com/objective-see/KnockKnock (914f2c0)

**Security reference (via 03-cleanup.md)**
- https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716

**Added by the fact-checker (fetched 2026-10-12)**
- DevMate X 4.10–4.15.8 notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41508.0.2409290833/releasenotes.html
- CleanMyMac X Chinese cask: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb
- CleanMyMac X screenshots (VERIFIED-PX): https://github.com/ddlmanus/MacOptimizer (`reference-uninstaller-list.png`, `reference-extensions-intro.png`, `reference-updater-details.png`)
- Replica code (secondary): https://github.com/ddlmanus/MacOptimizer/blob/main/AppUninstaller/ExtensionsReplicaView.swift and `…/AppUpdaterView.swift`
- Apple docs (JSON endpoints):
  - https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
  - https://developer.apple.com/documentation/systemextensions
  - https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers
  - https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
  - https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- macOS 11.3 SDK man pages (`tccutil.1`, `pkgutil.1`, `launchctl.1`, `qlmanage.1`, `mdimport.1`, `kmutil.8`, `pluginkit.8`): https://github.com/phracker/MacOSX-SDKs/tree/master/MacOSX11.3.sdk/usr/share/man
- Quick Look generators unsupported on 15+: https://github.com/haokaiyang/Mac-QuickLook , https://github.com/srirangav/qlZipInfo , https://github.com/sbarex/SourceCodeSyntaxHighlight
- System extensions: https://github.com/jo-duchan/tapflow (`docs/testing/network-control.md`), https://github.com/ivpn/desktop-app (`ui/References/macOS/HelperProjects/SplitTunnelExtension/README.md`)
- App Management behaviour: https://github.com/zhom/donutbrowser (`src-tauri/src/extraction.rs`), https://github.com/Vincent-HD/.nixfiles (`docs/research/macos-nix-darwin-patterns.md`), https://github.com/techgocodingnow/upwork-buddy-project (`docs/UPDATES.md`), https://github.com/Nightbr/factorai (`apps/docs/docs/troubleshooting.md`)
- tccutil scope: https://github.com/entorenee/dotfiles (`README.md`), https://github.com/futile/nixos-config (`hosts/hm-cf/setup-macos-permissions.sh`)
- pkg receipts: https://github.com/deploymenttheory/go-macos-pkg (`pkg/receipts/receipts.go`, `internal/cli/receipts.go`)
- Safari symlink: https://github.com/paulmillr/dotfiles (`scripts/macos/dock.sh`), https://github.com/Xpycode/LLM-Directions (`cookbook/96-macos-app-indexer-cryptex-symlink.md`)
- `~/.Trash` and FDA: https://github.com/viniciussouzao/tidymymac (`docs/TROUBLESHOOTING.md`), https://github.com/nickj-11/fleetos-downloads-janitor (`bin/janitor.sh`)
- launchd ordering: https://github.com/rclone/rclone-ui (`src-tauri/src/scheduler/launchd.rs`), https://github.com/itlackey/akm (`src/tasks/backends/launchd.ts`)
- PermissionsKit FDA probe (re-read): https://github.com/MacPaw/PermissionsKit/blob/master/PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m

---

## Verification notes

**Fact-check pass, 2026-10-12. Access conditions:**
- The shared WebSearch budget was already exhausted, so this pass ran no web searches.
- macpaw.com, cleanmymac.com, apps.apple.com, itunes.apple.com, support.apple.com, eclecticlight.co and all review sites were blocked by the egress proxy.
- Reachable: GitHub (raw files plus code search), Apple's developer-docs JSON endpoints, and the DevMate S3 bucket.
- Every check below therefore used primary vendor material on S3/GitHub, Apple docs and man pages, the vendor's own screenshots, and open-source code.

**Claims checked (16) and outcome**

| # | Claim | Outcome |
|---|---|---|
| 1 | X 4.10.0 iPhone/iPad apps, Steam fix; 4.10.4 Suspicious; 4.11.2 Zoom; 4.11.3 Chrome; 4.11.4 notifications; 4.12.2 fix (`[DM-X]`) | **Confirmed** (re-fetched). The Suspicious origin is now quoted as Russian/Belarusian developers. |
| 2 | Uninstaller groups Steam and iPhone & iPad are VERIFIED | **Corrected.** Only *listing* is verified; dedicated groups downgraded to INFERRED. |
| 3 | Leftovers, App Store, Vendors, Selected are INFERRED | **Upgraded** to VERIFIED-PX (X screenshot). The layout includes a "Stores" header (App Store / Other) and "Other" under Vendors. Intel and 32-bit groups are not present (stay INFERRED). |
| 4 | Vendor cask footprint: "LaunchAgents .HealthMonitor, .Menu, .Updater" | **Corrected.** Only the Updater has a LaunchAgents plist; HealthMonitor and Menu are launchctl labels. Missing cask paths added, plus the `CleanMyMac_5.app` naming quirk. |
| 5 | CMM3 strings (Smart Selector modes, Ignore system applications, Trash offer toggle, extension categories) | **Confirmed** (re-read). "Siri" corrected to "Siri Activity". |
| 6 | `pkgutil --files` paths are relative to `/` | **Corrected.** They are relative to the install location (`InstallPrefixPath` / `--pkg-info location`). |
| 7 | `tccutil reset All <id>` scope unknown | **Verified** syntax and per-bundle semantics (man page). Added the warning that omitting the ID wipes every app's grant for that service. |
| 8 | Quick Look generators "believed unsupported on Sequoia+" (INFERRED) | **Upgraded.** VERIFIED-OSS: unsupported on macOS 15+. |
| 9 | macOS removes system extensions when the host app is deleted (INFERRED) | **Mixed.** Apple docs say yes; a macOS 27 field test says no for plain deletion. `systemextensionsctl uninstall` refused with SIP on (verified). Both views and a safe flow are documented. |
| 10 | `~/.Trash` needs FDA (INFERRED) | **Upgraded.** Reads return EPERM without FDA (VERIFIED-OSS, multiple sources). |
| 11 | Rosetta "phased down after macOS 27", from memory | **Verified and precised** from Apple's Rosetta page. |
| 12 | `/Applications/Safari.app` is a firmlink into the Cryptex | **Corrected.** It is a symlink to `../System/Cryptexes/App/System/Applications/Safari.app`. |
| 13 | PermissionsKit probes "the system TCC.db" | **Corrected.** It opens the *user* TCC.db (plus Safari and Time Machine files) with `open(2)`. Pearcleaner is the one that checks the system TCC.db. |
| 14 | `pluginkit -e use\|ignore -i`, `launchctl bootout/bootstrap/disable`, `kmutil unload -b`, `mdimport -L/-r`, `qlmanage -r/-m` | **Confirmed** against man pages. Added the `default` election, the launchd enable-before-bootstrap ordering, the `Disabled` key failure, and plist ownership rules. Noted the man page's domain wording for `disable` and the `user/` fallback. |
| 15 | Sparkle appcast keys (`hardwareRequirements` 2.9+, `minimumAutoupdateVersion`, `minimumUpdateVersion` 2.9+, informational, critical, phased rollout) | **Confirmed** (Sparkle docs re-fetched). Added `ignoreSkippedUpgradesBelowVersion`. |
| 16 | Latest: `SUFeedURL` with DevMate fallback, `desktopSoftware` → `macSoftware`, cask.json 1 h cache, excluded-IDs list; Pearcleaner Sentinel FSEvents on `~/.Trash` and TCC names; Mole `APPLE_UNINSTALLABLE_APPS` | **Confirmed** by spot-reading current sources. Line numbers may have drifted from the commits in §8. Mole's list also contains `com.apple.server.*`. |

**Added content** (new primary facts and missed items):
- X 4.13.0, 4.13.6, 4.14.0 and 4.15.4 Applications-related notes.
- The X Uninstaller list layout, Extensions intro and Updater detail screen.
- New leftover locations:
  - Team-ID-prefixed preference plists;
  - Help Viewer index caches;
  - the Photos-library private folder;
  - extension containers;
  - crash-SDK caches.
- Notification Center and system-extension handling.
- App Management tripwires for the Uninstaller and the Updater.
- A rule to use iTunes lookup results only for receipt-bearing apps, plus extra iTunes fields.
- The `containerURL` caveat, and Apple's statement that macOS never removes group containers.
- SecTranslocate is SPI.
- The Installation files spec (§3.14).
- New test-matrix rows.

**Still uncertain:**
- 5.x Uninstaller sidebar beyond All/Unused/Suspicious.
- The full X Extensions category list, and whether 5.x has any Extensions UI.
- Vendor treatment of paid major updates, and the full Custom Updates list.
- 5.x Leftovers and Installation-files default selection and rules.
- Whether moving or deleting a whole app bundle (as opposed to modifying it) triggers App Management on 14/15/26.
- Whether FSEvents on `~/.Trash` work without FDA.
- Root vs user `tccutil` behaviour for system-wide services.
- Whether a programmatic trash of a host app triggers automatic system-extension removal.

All of these are marked INFERRED or GAP in the body. They need either macpaw.com access or tests on the Mac mini.

## Addendum (gap-fill)

See `20-gap-03-cmm5-applications-clutter-spacelens-cloud.md` §2 (2026-10-12). Summary:
- **Corrections to §1 item 2 and §3.4.** Real X screenshots show **Unused** in 2020 and in late 4.15 builds, so it is not 5.x-only. **Steam** appears as a *Stores* row when Steam games are installed. A **32-Bit** row existed in 2020 and was later dropped. In 5.x, **Leftovers** is its own pane in the Manage My Applications window, not a filter row.
- **§10 gaps 1, 4 and 7.** Answered at medium or low confidence: the 5.x tiles, the three-pane manager, the group list, the Leftovers default (one-click Remove, so leftovers are pre-approved) and details of the per-app resource list.
- **§4.2.4 vs 13 §3.41 (in-place install).** The vendor's Updater installs Sparkle and Custom updates **in-app**, as a progress queue; macOS updates are notify-only. Spruce's rule from now on:
  - Sparkle apps are updated by driving the target app's own feed through an embedded Sparkle `SPUUpdater` (the Latest pattern), gated on App Management;
  - App Store and macOS updates are hand-offs;
  - no custom bundle swap in v1.

## Addendum (gap-fill, 20-gap-08)

See `20-gap-08-cmm5-menus-shortcuts-integrations.md` §7 (2026-10-12) on §3.10, the trash monitor.
- **Exact CMM3 prompt** (parsed `TrashedAppAlert.nib`):
  - title "Uninstall applications correctly.";
  - one row per trashed app: icon, name, related-files count, size;
  - **Uninstall Completely** (↩) runs the removal *inside the alert* (Progress, Done and Failure tabs);
  - **View in CleanMyMac** hands off to the Uninstaller;
  - **Dismiss** (Esc) is wired to `ignoreForever:`.
- **Watched folders:** `~/.Trash`, per-volume `.Trashes` and an iCloud-style `Documents/.Trash/`.
- 5.x moves the offer to the Health Monitor; its presentation is unknown.
- **Our spec** adds these rules (its §7.4):
  - suppress when the same bundle ID is still installed elsewhere, so shared data is never offered;
  - withdraw the prompt on Put Back;
  - batch apps trashed together;
  - plain dismissal is not a silent "ignore forever".
- **Drop targets:** X fixed Uninstaller drag-and-drop in 4.0.2 and 4.5.3 (VERIFIED DevMate). Both CMM3 and X accept any file on the Dock icon (`CFBundleDocumentTypes` "AnyFile").
