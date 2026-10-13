# Spruce — Architecture & Engineering Rules

Spruce is an original macOS utility (cleanup, protection, performance, applications,
clutter, disk map, cloud storage, monitoring) inspired by the *functionality* of
MacPaw's CleanMyMac. Research lives in `docs/research/` (start with `00-SPEC.md` when
present, then the numbered reports).

**Legal guardrails:** never use the CleanMyMac/MacPaw names, logos, illustrations,
icons, sounds or marketing copy. Functionality and generic UI conventions are fine.
Our design system ("Prism") is original — see `docs/research/09-design.md` Part B.

## Targets

| Target | Platform | Contains |
|---|---|---|
| `SpruceCore` | macOS + Linux | Pure logic: models, rule catalogs, PathGuard, FileWalker, algorithms (hashing, leftovers matching, appcast parsing, version compare, health score, space-map layout…). **Foundation only** — no AppKit/IOKit/Darwin-only APIs (guard with `#if canImport(Darwin)` if unavoidable). Unit-tested on Linux in CI. |
| `SpruceMac` | macOS 14+ | System layer: engines that touch the real Mac (NSWorkspace, Trash, IOKit, Mach, SMAppService, Security framework, Spotlight, Process). |
| `Spruce` | macOS 14+ | SwiftUI app: window, sidebar, module screens, menu bar monitor, settings, onboarding. |

`Package.swift` only declares `SpruceMac`/`Spruce` on macOS, so `swift build`/`swift test`
on Linux builds and tests `SpruceCore` alone.

## Directory ownership (parallel development)

Each module owns these folders and may freely create files inside them:

```
Sources/SpruceCore/<Module>/     pure logic + catalogs        (Linux-testable)
Sources/SpruceMac/<Module>/      engine(s) for the module
Sources/Spruce/Modules/<Module>/ SwiftUI screens
Tests/SpruceCoreTests/<Module>/  unit tests for the Core part
```

Modules: `Checkup, Cleanup, Protection, Performance, Applications, Clutter, SpaceMap,
CloudStorage, Toolbox, Activity`, plus `Monitor` (menu bar; `Sources/Spruce/Monitor`,
`Sources/SpruceMac/Monitor`, `Sources/SpruceCore/Monitor`), `Settings` + `Onboarding`
(`Sources/Spruce/Settings`, `Sources/Spruce/Onboarding`), and `DesignSystem`
(`Sources/Spruce/DesignSystem`).

**Shared files** (`*/Shared/*`, `Sources/Spruce/App/*`, `Package.swift`) are owned by
the integrator. Do not edit them; if you need a change, describe it in your report.
Never edit another module's folders.

## Contracts (do not break)

* `SpruceCore/Shared/Models.swift` — `ModuleID`, `SafetyLevel`, `DeletionMethod`,
  `ScanItem`, `ScanGroup`, `ScanProgress`, `ProgressHandler`, `RunOutcome`,
  `ItemFailure`, `CheckupTile`, `TileStatus`, `CheckupContributor`, `SpruceError`.
* `SpruceCore/Shared/Persistence.swift` — `SprucePaths`, `JSONFileStore`,
  `OperationLog`, `SpruceSettings` (ignore list, thresholds, toggles),
  `ActivityEntry`/`ActivityHistory`, `GroupScanner`.
* `SpruceCore/Shared/PathGuard.swift`, `FileWalker.swift` (`FileWalker`, `FileEntry`,
  `DiskUsage`, `PathGlob`), `ByteFormat.swift` (`ByteFormat`, `CountFormat`,
  `DurationFormat`), `SystemSnapshot.swift`.
* `SpruceMac/Shared` — `FileRemover.shared.dispose(...)` (**the only way to delete
  files**), `PrivilegedRunner` (fixed admin commands, `removePaths`), `Shell.run`,
  `Permissions`, `Notifier`, `SettingsStore.shared`, `HistoryStore.shared`.
* `PrivilegedRunner.run([Invocation])` — allowlisted root executables with quoted args
  (launchctl, tmutil, sfltool, profiles, mdutil, killall, kill, purge, dscacheutil,
  pkgutil, log, tccutil). Each executable also has an argument validator
  (`PrivilegedRunner.refusal(for:)`): launchctl job verbs only and never a job macOS ships,
  `tccutil reset <Service> <bundle id>` only, read-only verbs for profiles/log/pkgutil
  (plus `pkgutil --forget <non-Apple id>`), restartable daemons only for killall. Anything
  else throws before the prompt. Need another executable or verb? Ask the integrator.
* `CategoryDescriptor` (Models.swift). The Cleanup module must provide
  `public enum CleanupCatalog { public static var categories: [CategoryDescriptor] }`
  in `Sources/SpruceCore/Cleanup/`; Settings uses it.
* Engine type names + `public init()`: `CleanupEngine`, `ProtectionEngine`,
  `PerformanceEngine`, `ApplicationsEngine`, `ClutterEngine` (all conform to
  `CheckupContributor` and `GroupScanner`), `SpaceMapEngine`, `CloudStorageEngine`,
  `SystemMonitor.shared` (`snapshot`, `start/stop/refresh`).
* App layer: `AppModel` (environment object with engines, stores, `selection`,
  `open(_:tool:)`, `pendingTool`), `ScanFlowModel`, and the view names
  `<Module>View`, `MonitorMenuView`, `MonitorMenuLabel`, `SettingsView`,
  `OnboardingView(onFinish:)`.
* Design system components (restyle freely, keep names/params): `ModulePalette` via
  `module.palette`, `Ink`, `StatusColor`, `SpruceFont`, `Spacing`, `Radius`, `Motion`,
  `LivingCanvas`, `ActionOrb`, `ProgressRing`, `HeroLens`, `GlassCard`,
  `SpruceCheckbox`, `SizeBadge`, `StatusPill`, `CapsuleButton`, `SectionHeader`,
  `ItemIcon`, `ScreenHeader`, `ModuleIdleView`, `IdleFeature`, `ScanningView`,
  `ReviewSplitView`, `ItemRow`, `ResultsFooter`, `DoneView`, `EmptyStateView`,
  `FailureView`, `ResultTile`, `ScanFlowScreen`.

## Navigation & tool identifiers

`AppModel.open(_ module:, tool:)` sets `selection` and `pendingTool`. A module view
must, on appear and when `pendingTool` changes, check for one of *its* tool ids, open
that tool, and set `model.pendingTool = nil`. Tool ids:

| Module | Tool ids |
|---|---|
| Checkup | `checkup.scan` (starts a scan when idle) |
| Cleanup | `cleanup.systemJunk`, `cleanup.mailAttachments`, `cleanup.trash` |
| Protection | `protection.malware`, `protection.privacy`, `protection.permissions` |
| Performance | `performance.maintenance`, `performance.loginItems`, `performance.backgroundItems`, `performance.consumers` |
| Applications | `applications.uninstaller`, `applications.updater`, `applications.leftovers`, `applications.installers`, `applications.extensions` |
| Clutter | `clutter.largeOld`, `clutter.duplicates`, `clutter.similarImages`, `clutter.downloads` |
| Space Map | `spaceMap` |
| Cloud Storage | `cloudStorage` |
| Toolbox-only tools | `toolbox.shredder`, `toolbox.screenCleaning`, `toolbox.emptyTrash`, `toolbox.freeRAM`, `toolbox.flushDNS` |

## Checkup integration

Each `CheckupContributor` keeps the reviewable result of its last `checkupScan` in
`checkupReview: [ScanGroup]` (selection editable from the Checkup review sheet);
`checkupRun` acts only on the *selected* items in `checkupReview`. Default selection
follows the safety rules below.

## Integration notes (from finished modules — read if you build Settings, Onboarding, Toolbox or Activity)

* **Admin Trash:** `PrivilegedRunner.trashPaths(_:guardian:options:)` moves root-owned items
  into the user's Trash (one prompt); `FileRemover.dispose(..., escalate: true)` uses it
  automatically for `.trash` items that fail with a permission error, and `removePaths` for
  `.remove` items. Items keep their owner (root never runs `chown`): they land in a new
  root-owned folder "Spruce Admin Trash …" inside the Trash, so emptying it asks for the
  password again (`FileRemover.emptyTrash` escalates). Items on another disk are refused.
  Both root scripts re-check, by device + inode, the parent folder and the item they act
  on, so a path swapped during the password prompt can't redirect root.
* **Where root may act:** escalation only happens where `PathGuard.checkPrivileged(_:method:options:)`
  allows it — the home folder, `/Applications`, vendor folders in `/Library` (Application
  Support, Caches, Logs, Preferences, Launch*, PrivilegedHelperTools, plug-in folders,
  Developer), `/Users/Shared`, `/opt`, system logs/temp, the user's own `$TMPDIR`/cache
  folder and external `.Trashes/<uid>`. Other permission failures are reported per item.
* **PathGuard (tightened):** system state in `/private/var` (except `log`, `tmp` and the
  per-user `T`/`C` folders in `/private/var/folders`), `/Library/Preferences/com.apple.*`,
  `SystemConfiguration`, `OpenDirectory`, `Logging` and `/Library/Managed Preferences`
  are refused for every method. iOS backups and Xcode archives are no longer permanent
  zones (Trash only). Inside the user's Trash, name markers (wallet, 1password…) don't
  block emptying. `PathGuard.key` / `isStrictlyInside` / `isInsideOrEqual` are public.
* **Stop:** after a cancelled run `FileRemover` never prompts for administrator rights; the
  items it had queued for the prompt fail with `FileRemover.stoppedReason`, and
  `PrivilegedRunner` refuses to start a prompt once the task is cancelled.
* **Trash accounting and Put Back:** `RunOutcome.trashedBytes` / `trashedCount` (part of
  `freedBytes` that only returns once the Trash is emptied) and `trashRunIDs` (decode as
  zero/empty from older files; `RunOutcome.merged` sums them — engines that build their own
  outcome from `dispose` results copy them: Cleanup, Protection's threat removal and privacy
  cleaner do). `TrashLedger.shared` records where every trashed item went:
  `restorable(runIDs:)`, `putBack(runIDs:)`, `TrashLedger.openTrash()`. `DoneView` shows a
  Trash card for any outcome with trashed items ("N items (X) are in the Trash. Empty the
  Trash to get the space back." + Open Trash / Put Back All); pass `flow:` when the outcome
  is a `ScanFlowModel` run so Put Back goes through `ScanFlowModel.putBack()` (`canPutBack`,
  `restorableCount`, `isPuttingBack`, `putBackResult` stay in the flow), otherwise the card
  uses `TrashLedger` itself. `putBackConfirmation:` makes it ask first (removed threats).
  Cleanup's outcome counts moved-to-Trash bytes in `freedBytes` like every module; its
  `.other` "Emptied the Trash" history record carries no Trash fields.
  `RunOutcome.didAnything` = processed or freed > 0.
* **AppleScript:** in-process `NSAppleScript` must run through `AppleScriptExecutor.shared`
  (one serial queue; `run(_:)`, or `queue` + `executeNow(_:)`). `PrivilegedRunner` does.
* **History:** `HistoryStore.record(_ entries: [ActivityEntry])` records several entries with
  one save; saves are coalesced (~1 s, background, compact JSON) and records made off the
  main thread are applied on the main thread. `ScanFlowModel` records a run only when
  `didAnything`, and every finished scan as `.scan` unless it is created with
  `recordsScanHistory: false` (Protection's malware flow: the engine records `.malwareScan`,
  which `ActivityHealth.unresolvedThreats` reads). `HistoryStore.flush()` runs at quit.
* **Alerts:** `Notifier.post(id:title:body:module:tool:kind:)` adds a "Review" action that opens
  `module`/`tool` (routed by the AppDelegate, which reopens a closed main window via
  `AppModel.showMainWindow()`). Sounds follow Settings › Play sounds. Every alert is also
  kept in the in-app Notification Center (`InboxStore.shared`, bell in the sidebar, ⇧⌘N);
  `Notifier.keep(kind:title:body:module:tool:)` adds an inbox-only message (never offers
  or news). Finished runs recorded with `HistoryStore.record(_:kind:)` and Checkup markers
  appear there as results. `AppModel.shared` is the single app model.
* **History kinds:** `ActivityEntry.Kind.checkup` is a zero-byte marker for a whole Checkup
  run (bytes live on the per-module entries with the same date — don't count it twice);
  `.startupItems` = login/background items turned off or removed.
* **Settings fields to expose:** `SpruceSettings.notifyHighCPU` (Notifications tab; the
  menu bar bell toggles the same value). Protection tab: `threatFeedEnabled` (Download threat
  list, with Check Now → `ProtectionEngine.checkThreatListNow()`), the VirusTotal key
  (Keychain, through the engine — never a settings field) and `virusTotalAutoCheck`. Protection scan depth: show
  `ProtectionScanDepth.allCases` with `.title`, `.coverage`, `.speed`, `.purpose` (stored as
  "quick" / "balanced" / "deep" in `SpruceSettings.scanDepth`).
* **Onboarding** must call `Permissions.requestNotificationAuthorization()` (monitor and
  protection alerts are invisible until authorised).
* **Cleanup ownership:** a row's `CleanupMetadataKey.owner` may name several apps joined
  with `CleanupOwnership.ownerSeparator` ("|") — the `Firefox`/`Mozilla` folders belong
  to every Firefox channel (release, Beta, Developer Edition, Nightly). Use
  `CleanupOwnership.matches(owner:bundleID:)` / `isRunning` / `owners(in:)` rather than
  comparing the string.
* **Toolbox:** Free Up RAM / Flush DNS should call
  `model.performance.runTasks([.freeRAM], progress:)` / `runTasks([.flushDNS], progress:)`
  (never throws; `PerformanceRunSummary.outcome(_:)` converts results to a `RunOutcome`).
* **Health score:** `AppModel.healthReport` (`ActivityHealth.assess(model.healthInput())`) is
  the one Mac Health score. The sidebar pill reads it; Activity's gauge and the menu bar
  header/status icon should read it too (the monitor's `SystemMonitor.shared.health` stays
  the system part of it and the source of the live issue lines).
* **Main menu:** File (Quick Look ⌘Y, Reveal ⇧⌘R, Copy Path ⌥⌘C, Ignore), Edit (Select All
  Items, Deselect All ⌥⌘A, Select Recommended), View (Notification Center ⇧⌘N, Mac Health),
  Scan (Scan Again ⌘R, Stop ⌘., Run Selected… ⌘↩), Go (⌘1–⌘9, Activity ⇧⌘A) and Help
  (Help window `id: "help"` with `AppModel.showHelp(_:)`, Keyboard Shortcuts ⌘/). Screens
  enable Scan/Edit items by publishing `.focusedSceneValue(\.spruceFlow, SpruceFlowActions(…))`
  (`ScanFlowModel.menuActions` builds one — Scan Again, Stop, Select All / Deselect All /
  Select Recommended (`ScanFlowModel.selectRecommended()` = safe items only); `reviewAndRun`
  must only open the screen's own confirmation, so leave it nil where the screen's orb runs
  without one). `ScanFlowScreen`, `CheckupView` (tiles; Run Selected… asks, then
  `requestRun()`), Cleanup and Protection's tools publish it. `ReviewSplitView` publishes
  `.focusedSceneValue(\.spruceRows, …)` for the row under the pointer (or last clicked;
  `ItemRow(onHover:)`), so File › Quick Look / Reveal / Copy Path / Ignore act on it.
  Never bind ⌘⌫ / ⇧⌘⌫ or any shortcut that deletes without its confirmation.
* **Files from Finder:** Services ("Uninstall with Spruce", "Map Folder with Spruce", "Find
  Clutter with Spruce", "Shred with Spruce"), drops on the Dock icon and Open With call
  `AppModel.openFiles(_:as:)`, which navigates (`.app` → `applications.uninstaller`, `.pkg` →
  `applications.installers`, folder → `spaceMap`, other → `toolbox.shredder`; the Clutter
  Service passes `FileDestination.clutter` explicitly) and puts the files in
  `AppModel.pendingFiles` (with `pendingFilesModule`). The target module takes them with
  `model.takePendingFiles(for: <its ModuleID>)` (only while it is on screen; it clears them)
  and shows them — Uninstaller opens that app's detail, Space Map roots its map there (a file
  maps its folder), Clutter adds the folders to its scan locations, Shredder stages them
  unchecked. Drops on a module's window do the same: Applications (apps, installers), Space
  Map (a folder, also on the location cards) and Clutter (folders → locations, with a toast).
  Never start a removal from a Service or a drop (mapping a folder is fine; Clutter only adds
  locations and waits for Scan).
* **Space Map selection:** `SpaceMapCatalog.protectionReason(for:guardian:settings:access:)`
  with `SpaceMapPermissions.moveAccess(ofPath:)` refuses, before selection (lock + tooltip),
  items locked in Finder or by macOS, and items the user can't move themselves (root-owned,
  unwritable folder, sticky folder) outside `PathGuard.isInPrivilegedZone`, where
  `FileRemover` would refuse to escalate anyway.
* **Protection detection sources** (`ProtectionEngine.detection`, observable, main thread):
  the malware scan and real-time protection run on top of the built-in catalog:
  * **Apple's XProtect rules** — `XProtect.yara` from
    `/private/var/protected/xprotect/XProtect.bundle/Contents/Resources/` (macOS 15+, preferred)
    or `/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/`, run by
    Spruce's own YARA engine (`YaraRuleSet` in `SpruceCore/Protection/Yara*.swift`, no
    third-party code; regular-expression strings are supported, with YARA's 4 KB match
    reach). Rules using syntax the engine doesn't support (base64 strings, `matches`, the
    pe/macho/math modules, `entrypoint`…) are skipped one by one with a reason, together
    with the rules that refer to them; matching, hashing and condition work are capped so a
    rule can't hang a scan, and nesting is capped so a rule can't overflow the stack.
    `ProtectionAppleRulesLoader` compiles the file once per size + date + inode; rules that
    match harmless sample files are switched off (`ProtectionRuleSource`). Matches on
    Apple-signed files are ignored. Status: `detection.appleRules` (`ProtectionAppleRulesStatus`:
    path, XProtect version, active and skipped rule counts, or why it's unavailable).
  * **Threat list** — `ThreatFeed/feed.json` (families and indicators in the catalog's own
    kinds, strictly validated: over-broad paths, names, team IDs or hashes are refused) and
    `ThreatFeed/rules.yara`, downloaded by `ProtectionThreatFeedUpdater` (HTTPS only, 20 s,
    ≤ 5 MB / 2 MB, ETag requests) into `~/Library/Application Support/Spruce/ThreatFeed/`
    (`ProtectionThreatFeedCache`, atomic writes, damaged copies ignored, never an older
    version). It can only add detections: built-in families and indicators win, downloaded
    indicators never flag Apple-signed files, downloaded rules don't run on code with a valid
    developer identity, patterns pointing into the user's own files (Documents, Photos,
    iCloud Drive…) are refused, and findings only the list detects
    (`ProtectionThreatFinding.isThreatListOnly`) are never pre-selected. While the list is
    off its cached files aren't even parsed. Checked at most once a day before a scan (the
    scan waits ≤ 2.5 s, then goes on with the cached copy) and by
    `ProtectionEngine.checkThreatListNow()`; a failed check keeps the cached or built-in data.
    `SpruceSettings.threatFeedEnabled` (default on) turns downloads and the cached copy off.
  * **VirusTotal** — the user's own API key lives only in the Keychain (generic password,
    service `app.spruce.virustotal`, account `api-key`; never in settings, defaults, logs or
    the repo). `ProtectionVirusTotalClient` sends `GET /api/v3/files/{sha256}` only, enforces
    the public limits (4 a minute, 500 a day, counted in user defaults whichever key is saved,
    key checks included; a 429 pauses lookups)
    and remembers answers per hash for a week (a day for unknown files). After a scan, while
    `SpruceSettings.virusTotalAutoCheck` is on (default) and a key is saved, up to 40
    heuristic and rule-based findings with a program file are looked up in the background;
    answers land on the engine's reports and Checkup rows, in `detection` and as
    `ProtectionEngine.virusTotalNotification`. They add a reason line and raise a flagged
    file to High severity but never change what is selected. UI APIs: `saveVirusTotalKey`
    (validates with the EICAR test file's hash), `removeVirusTotalKey`,
    `validateVirusTotalKey`, `checkWithVirusTotal(_:)`, `cachedVirusTotalVerdict(for:)`,
    `virusTotalPage(for:)`; row helpers `ScanItem.applyVirusTotal`, `[ScanGroup].applyVirusTotal`.
* **Links:** `spruce://open/<module>[?tool=<tool id>]`, `spruce://checkup[?autostart=1]`,
  `spruce://inbox` (navigation only; tool ids must belong to the module). The Dock menu
  offers Run Checkup, Empty Trash…, Free Up Memory… (they open the tool, which confirms)
  and Open ▸ module. The Info.plist keys for links (`CFBundleURLTypes`), Services
  (`NSServices`) and document types (`CFBundleDocumentTypes`) live in `Support/Info.plist`;
  `scripts/build-app.sh` checks they are there.

## Safety rules (non-negotiable)

1. **All deletions go through `FileRemover.dispose`**, which re-checks every path with
   `PathGuard` right before acting. Never call `FileManager.removeItem`/`trashItem` on
   scan results directly. One exception: Xcode simulator runtimes (Cleanup › Xcode Junk ›
   Simulator Runtimes) are disk images macOS manages, so `CleanupScanner.expand` refuses
   them and `CleanupEngine.clean` asks Xcode's own tool to remove them
   (`simctl runtime delete <UUID>`, run from `xcode-select -p`, never through `xcrun`;
   identifiers are checked with `CleanupSimulatorRuntimes.isValidIdentifier`). They are
   listed only for Cleanup itself (not Checkup), unchecked, and blocked while a simulator runs.
2. **Default to Trash.** `DeletionMethod.remove` is only for regenerable data inside
   PathGuard's permanent zones (caches, logs, temp, trash contents, build products).
3. **Pre-select only `safe` items.** `review` items are shown unchecked (exception:
   duplicate "smart selection" may pre-select the redundant copies). Like CleanMyMac,
   Xcode Device Support is `review` (Xcode takes a while to copy the symbols again). `risky` items are
   never pre-selected and need explicit confirmation.
4. **Never modify app bundles** (no language-file stripping, no `lipo` thinning) — it
   breaks code signatures. Show such savings as informational at most.
5. **Root only via `PrivilegedRunner`** with fixed commands; no persistent daemon.
6. **Honour the ignore list** (`SpruceSettings.filteringIgnored`, `isIgnored`).
7. **Never remove data of a running app** where deleting would corrupt state (browser
   privacy cleanup requires the browser to be quit; offer to quit it). Cleanup rules say
   how an open app's rows behave (`CleanupRule.RunningPolicy`): `~/Library/Caches` and
   container caches are selected like CleanMyMac 5's and Clean / Run asks to quit the app
   first (`quitToClean`). That applies only when every open app holding the row can be
   quit from the sheet (`CleanupContext.quittableBundleIDs`, not background-only). Such a
   row's age limit shrinks to `CleanupScanner.quitFirstFloor` (5 minutes) while the app
   is open and when it is expanded after the app quit; the engine skips it while the app
   is open and re-checks running apps right before removing. Group-container caches stay
   `skip` (extensions sharing them are invisible to the check). Week-old logs (`allow`)
   don't need the app closed. Everything else is listed unchecked while its app is open.
8. **No telemetry, no network calls** except: update checks (Sparkle appcasts, iTunes
   lookup API, Homebrew API) when the user opens Updater; while Settings › Notifications ›
   App updates is on, also when Checkup scans Applications and in a daily background check
   (`NSBackgroundActivityScheduler`); downloading a Sparkle update archive
   (HTTPS, EdDSA-verified) when the user presses Update or runs selected updates from
   Checkup; Protection's threat list (`ThreatFeed/feed.json` and `rules.yara` from this
   project's GitHub repository, HTTPS, at most once a day before a malware scan or when the
   user presses Check Now, while Settings › Protection › Download threat list is on — on by
   default); and VirusTotal file lookups, only after the user saved their own API key
   (Keychain only): automatic after a scan for heuristic and rule-based findings while
   Settings › Protection › Check findings automatically is on, and when the user presses
   Check with VirusTotal. A lookup sends a file's **SHA-256 only** — files are never
   uploaded. Apple's XProtect rules are read from macOS and need no network. Nothing else
   about the Mac or its files is ever sent.
9. Record every destructive action (FileRemover does this) and every run in history.

## Coding conventions

* Swift 5 language mode (tools 5.10), macOS 14 deployment target. Guard macOS 15+
  APIs with `if #available(macOS 15, *)`. Don't use APIs newer than the macOS 15 SDK
  unless guarded by `#if canImport(...)` (CI builds with Xcode 16 / macOS 15 SDK).
* No third-party dependencies.
* Engines: `public final class`, `async` APIs, heavy work off the main actor
  (`Task.detached` or plain async functions; never block the main thread).
  UI state lives in `@Observable @MainActor` models in the app target.
* Views: SwiftUI, dark canvas, use design-system components/tokens; every screen
  follows idle → scanning → results → running → done.
* Keep Core types `public` (they cross module boundaries) and `Sendable` where easy.
* Tests: XCTest in `Tests/SpruceCoreTests/<Module>/`, using temporary directories,
  never the real home folder.

## Build

```
swift build                 # debug build of everything (macOS) / Core only (Linux)
swift test                  # Core unit tests
./scripts/test-core-linux.sh   # Core build + tests on Linux via Docker (this container)
./scripts/build-app.sh      # build/Spruce.app (+ zip), ad-hoc signed
```
