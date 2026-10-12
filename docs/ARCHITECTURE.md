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
  pkgutil, log). Need another executable? Ask the integrator in your report.
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

## Safety rules (non-negotiable)

1. **All deletions go through `FileRemover.dispose`**, which re-checks every path with
   `PathGuard` right before acting. Never call `FileManager.removeItem`/`trashItem` on
   scan results directly.
2. **Default to Trash.** `DeletionMethod.remove` is only for regenerable data inside
   PathGuard's permanent zones (caches, logs, temp, trash contents, build products).
3. **Pre-select only `safe` items.** `review` items are shown unchecked (exception:
   duplicate "smart selection" may pre-select the redundant copies). `risky` items are
   never pre-selected and need explicit confirmation.
4. **Never modify app bundles** (no language-file stripping, no `lipo` thinning) — it
   breaks code signatures. Show such savings as informational at most.
5. **Root only via `PrivilegedRunner`** with fixed commands; no persistent daemon.
6. **Honour the ignore list** (`SpruceSettings.filteringIgnored`, `isIgnored`).
7. **Skip data of running apps** where deleting would corrupt state (browser privacy
   cleanup requires the browser to be quit; offer to quit it).
8. **No telemetry, no network calls** except: update checks (Sparkle appcasts, iTunes
   lookup API, Homebrew API) when the user opens Updater / enables update checks.
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
