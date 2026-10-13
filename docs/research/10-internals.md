# 10 — Technical Architecture & Internals of CleanMyMac

Research track: **internals** — app bundle & process architecture, privileged helper, XPC protocol,
Full Disk Access, sandboxing, Safety Database / knowledge base, scan engine, update mechanism,
telemetry, frameworks — plus a recommended architecture for our original clone.

Target of our work: an **original, functionally-equivalent** macOS utility ("our app") for a personal
Apple-Silicon Mac mini (macOS 14 Sonoma+, incl. 15 Sequoia, 26 Tahoe, 27 "Golden Gate").
Research date: **2026-10-12**.

---

## 0. Method, labels, caveats

- **VERIFIED** = stated by a cited source (URL inline). **VERIFIED-BIN** = extracted by us this session from an
  on-disk MacPaw binary/bundle (path + how). **INFERRED** = our reasoning / recommendation for our clone.
- **Access caveat:** `macpaw.com`, `cleanmymac.com`, `talosintelligence.com`, `nvd.nist.gov`, `developer.apple.com`
  HTML, `objective-see.org`, and most press were **blocked** by the egress proxy this session. I worked around this with:
  - the **official CVE JSON** from `CVEProject/cvelistV5` (GitHub, fetched);
  - an **archived copy of the Cisco Talos "Vulnerability Spotlight … CleanMyMac X" blog** (GitHub mirror, fetched);
  - an archived copy of the **0day.today CleanMyMac3 LPE advisory** (describes the XPC interface);
  - **MacPaw's own CleanMyMac 3 app bundle** committed to a public GitHub repo (`auspham/mac-essential`) — I downloaded and ran `strings`/`plutil`-style parsing on the real `CleanMyMac 3.app` main binary, the **privileged Agent Mach-O**, the embedded launchd/Info plists, and the knowledge-base files;
  - MacPaw's **CleanMyMac 5 Agent launchd plist** and **provisioning profiles** committed to public repos;
  - the **Homebrew casks** (`cleanmymac`, `cleanmymac-zh`, `cleanmymac-cli`), **Fleet/IntuneBrew uninstall scripts**, a **`sfltool dumpbtm`** dump, a **`system_profiler` app list**, process/netstat captures, and **Apple's developer documentation JSON** (`developer.apple.com/tutorials/data/...json`, fetched) for `SMAppService`, XPC code-signing requirements, `SMJobBless`.
  - **MacPaw's own open-source** `PermissionsKit` (Full Disk Access detection) and `cleanmymac-cli` repos (fetched).
- **Fact-check pass (same day, adversarial):** WebSearch was already exhausted for this session, and `macpaw.com` still failed (DNS failure in WebFetch, proxy 403 via curl). The fact-checker re-verified claims from primary artifacts instead: the Homebrew cask, Apple doc JSON, CVE JSON, the archived Talos posts, the CMM3 binaries (re-run `strings` plus `openssl` on `KnowledgeBase.pem` and a byte analysis of `info.cmmkb`), PermissionsKit source, Sparkle source, a legacy DevMate Sparkle appcast for 5.x, and GitHub code search. Items fixed in place are marked **(corrected)**. New material is marked **(added)**. See "Verification notes" at the end.
- Paraphrased throughout; short symbol names / labels quoted because we need them exact. No exploit code is reproduced.
- **Do not copy** the names "CleanMyMac", "Moonlock", "Smart Care", MacPaw bundle IDs, team ID `S8EX82NJP6`,
  provisioning profiles, icons, the knowledge-base contents, or marketing copy. We reproduce *architecture and behaviour* under our own identifiers.

---

## 1. Executive summary (what matters for the clone)

1. **Multi-process, privilege-separated design.** CleanMyMac is **not** one process. Current 5.x ships: the **main app**, a **menu-bar app** ("The Menu"), a **Health Monitor** background agent, a **privileged root Agent** (helper), a user **Updater** LaunchAgent, and a **Finder Sync extension**. VERIFIED-BIN / VERIFIED (cask; provisioning profiles; process capture; §2). **(corrected)** A `com.macpaw.moonlock.engine` Endpoint-Security system extension was seen running beside CMM5 on one Mac. It was absent on another CMM5 Mac whose Menu, HealthMonitor and FinderSync were all running. It may belong to MacPaw's standalone Moonlock app instead. So "5.x ships an ES system extension" is **INFERRED / unresolved**, not verified (see §2.1 and track 04 §1.6).
2. **The root helper is a classic `launchd` Mach-service XPC daemon.** On X/3 it was installed with **`SMJobBless`** and lived at `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac<N>.Agent` with `/Library/LaunchDaemons/com.macpaw.CleanMyMac<N>.Agent.plist`. The 5.x Agent plist exposes a `MachServices` key `com.macpaw.CleanMyMac5.Agent`. VERIFIED-BIN (plists; cask). **(added)** Three independent signals say 5.x still uses `SMJobBless`:
   - its on-disk plist has exactly the shape SMJobBless writes;
   - the helper ships at `Contents/Library/LaunchServices/com.macpaw.CleanMyMac5.Agent`;
   - third-party tooling rewrites the app's `SMPrivilegedExecutables` key.

   Details in §3.1; the conclusion is INFERRED-HIGH. The helper exposes an **Objective-C `NSXPCInterface` protocol** (`CMPrivilegedOperation(s)`) of ~40 intent methods (`removeItemAtPath:…`, `removeLaunchdAgentAtPath:…`, `flushDNSWithReply:`, `runPeriodicScript:…`, etc.). VERIFIED-BIN (Agent strings) / VERIFIED (Talos, 0day).
3. **2018 Talos disclosure is the central lesson:** the X 4.04 helper **did not validate the calling application at all**, so any local process could invoke root file-deletion verbs → 13 CVEs (CVE-2018-4032…4037, 4041…4047; "Improper Input Validation"), plus CVE-2019-5011: upgrading to 4.20 left the old vulnerable helper (corrected: that one is CWE-459 "Incomplete Cleanup"). All score CVSS 7.1. VERIFIED (CVE JSON re-fetched; Talos blog). **Our helper must do the opposite:** per-connection code-signing requirement + intent-level verbs + path re-validation.
4. **Full Disk Access is the key permission.** MacPaw open-sourced its own detector (`PermissionsKit`): it tries to `open()` a set of TCC-protected files (`~/Library/Safari/Bookmarks.plist`, `~/Library/Safari/CloudTabs.db`, **`~/Library/Application Support/com.apple.TCC/TCC.db`** (corrected: the *user* TCC.db, not `/Library/…`), `/Library/Preferences/com.apple.TimeMachine.plist`) and maps `EPERM/EACCES` → denied, success → authorized; it deep-links to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`. VERIFIED (PermissionsKit source).
5. **Editions differ by sandbox:**
   - The direct (MacPaw Store / Homebrew) edition is **not sandboxed** and Sparkle-updates itself.
   - The Setapp edition is also unsandboxed, with its own SMJobBless Agent, but Setapp delivers its app updates (corrected: Setapp was wrongly grouped with the Sparkle self-updaters).
   - The **Mac App Store edition is sandboxed**, has no root Agent, and loses Updater/Shredder/etc.

   VERIFIED (prior tracks; cask; InjectLib config; EtreCheck MAS layout).
6. **Safety Database / "knowledge base"** is an encrypted data file shipped in the bundle and updated in the background. **(corrected)** On CMM3 it was `info.cmmkb`:
   - It is a **SQLCipher-encrypted SQLite database**, opened through FMDB's `FMEncryptedDatabase`. The binary statically links SQLCipher (`sqlcipher_export`, `PRAGMA kdf_iter = 4000`, `PRAGMA cipher_use_hmac = OFF`). The file is 435,200 bytes, exactly 425 pages of 1024 bytes, with no SQLite header.
   - KB updates arrive through a **second Sparkle (DevMate) updater instance** (`_kbUpdater`, next to `_mainUpdater`) for a pseudo-bundle `com.macpaw.CleanMyMac3.KnowledgeBase` ("CleanMyMac Safety DataBase"). Archives are named `CMMKB-<ver>.zip`. They are checked with `SUPublicDSAKeyFile` = `KnowledgeBase.pem`, a **DSA-1024** public key.
   - The earlier claim that the KB is "RSA-verified, AES-decrypted via `CCCrypt`" misattributed strings. The RSA, AES-256 and "Invalid signature." strings belong to DevMate's **Kevlar license validator**, not the KB. VERIFIED-BIN (fact-check `strings`/`openssl asn1parse`/byte analysis).
7. **Update mechanism = Sparkle-family.** CMM3/X used MacPaw's **DevMate** fork of Sparkle (`DevMateKit.framework`, `Autoupdate.app`, classes `DM_SUUpdater`). 5.x uses **Sparkle 2** (`Sparkle.framework/Versions/B` — the `B` framework version is Sparkle 2's layout), with appcast `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml`. A dedicated **Updater LaunchAgent** wakes every **21600 s (6 h)**. VERIFIED-BIN (bundle, InjectLib config) / VERIFIED (cask; launchd plist capture; Sparkle `ConfigFramework.xcconfig`). **(added)** A legacy DevMate-hosted feed covers 5.0.0 (2024-10-15) through 5.3.1 (2026-01-28) (§8). It has `minimumSystemVersion` 11.0, binary **delta** updates, release notes in 13 languages, and **no EdDSA/DSA signatures**. Sparkle accepts that only through its Apple-code-signing path: same Developer ID team.
8. **Telemetry:** analytics go to `api-lytics.macpaw.com` (VERIFIED-BIN: in the CMM3 binary). Other hosts:
   - `catalina.macpaw.com`;
   - `cmd-cdn.cleanmymac.com` (host VERIFIED in CDN rule sets; **(corrected)** its role as the knowledge-base CDN is INFERRED from the name only);
   - `speedtest.macpaw.com` for the Menu speed test.

   CMM3 also had Google-Analytics-for-OS-X (corrected: not found in a re-run of `strings`; downgraded to INFERRED from MacPaw's repo list).
9. **Language/frameworks:** CleanMyMac is **Objective-C + AppKit** historically (CMM3/X: `NSPrincipalClass = CMApplication`, Storyboard/XIB). The 2024 "CleanMyMac 5" rebuild is a new codebase (MacPaw's current public code is Swift/SwiftUI-centric). For **our clone** we choose **Swift + SwiftUI** throughout. INFERRED + VERIFIED-BIN (CMM3 Info.plist).
10. **Our recommended architecture (macOS 14+):** SwiftUI app + a **single privileged LaunchDaemon helper** registered with **`SMAppService.daemon(plistName:)`**, reached over **`NSXPCConnection`** hardened with **`setConnectionCodeSigningRequirement(_:)`**; the Menu/Health agents via **`SMAppService.loginItem`/`.agent`**; FDA detection + deep link à la PermissionsKit; no sandbox (direct build). For personal use, prefer a **self-signed code-signing certificate** over pure ad-hoc signing (corrected): ad-hoc code cannot satisfy certificate-based XPC requirements, and its TCC grants reset on every rebuild (§11.6). For a personal Mac mini you may even **skip the daemon** and use occasional `AppleScript "do shell script … with administrator privileges"`; trade-offs in §11.4 (corrected section reference).

---

## 2. Process & bundle architecture (what is actually installed)

### 2.1 CleanMyMac 5 (current) — components, bundle IDs, on-disk paths

VERIFIED from the Homebrew `cleanmymac` cask (fetched `raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb`), the **Fleet uninstall script** (`fleetdm/fleet .../cleanmymac-uninstall.sh`), a `system_profiler`/process capture (`TaliskerMan/Monitro`, `OpenAgentsInc/openagents`), `sfltool dumpbtm`, and the three **provisioning profiles** committed to `eliekh05/provision-files` (decoded this session):

| Component | Type | Identifier / path |
|---|---|---|
| Main app | `.app` | On-disk bundle `/Applications/CleanMyMac_5.app` (MacPaw's own download); Finder shows "CleanMyMac". The **Homebrew cask renames it to `/Applications/CleanMyMac.app`**: its comment says the name differs between Finder and shell (corrected). Bundle id **`com.macpaw.CleanMyMac5`**; executable `Contents/MacOS/CleanMyMac_5` (VERIFIED: process captures). ~389 MB (5.6.0) |
| The Menu | login item `.app` | `…/Contents/Library/LoginItems/…`; bundle id **`com.macpaw.CleanMyMac5.Menu`**; login-item display name "CleanMyMac 5 Menu" |
| Health Monitor | login item `.app` | `CleanMyMac_5.app/Contents/Library/LoginItems/CleanMyMac_5_HealthMonitor.app`; bundle id **`com.macpaw.CleanMyMac5.HealthMonitor`**. (corrected) In 5.x it sits in the main app's LoginItems; the source is the `eliekh05/provision-files` guide, corroborated by the MAS layout. In X it was nested under the Menu (§2.2) |
| Finder Sync extension | `.appex` | `…/Contents/PlugIns/CleanMyMac_5_FinderSyncExtension.appex`; bundle id **`com.macpaw.CleanMyMac5.FinderSyncExtension`** (entitlement incl. `com.apple.security.application-groups`). **(added)** It is **sandboxed** (all app extensions are): it leaves `~/Library/Containers/com.macpaw.CleanMyMac5.FinderSyncExtension` and `~/Library/Application Scripts/com.macpaw.CleanMyMac5.FinderSyncExtension`. VERIFIED (`earthinversion/Mac-apps-self-manage` leftover scan) |
| Privileged Agent | root LaunchDaemon helper | **`/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`** (~2.2 MB in 5.6.0) + **`/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist`**; label/Mach-service `com.macpaw.CleanMyMac5.Agent`. **(added)** Source copy inside the bundle: `CleanMyMac_5.app/Contents/Library/LaunchServices/com.macpaw.CleanMyMac5.Agent`, which is the SMJobBless location. VERIFIED (InjectLib `helperFile`) |
| Updater | user LaunchAgent | **`~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist`**; wakes every 21600 s; launchd label in the `gui/<uid>` domain |
| Moonlock Engine **(corrected: attribution unresolved)** | Endpoint-Security System Extension | `/Library/SystemExtensions/<UUID>/com.macpaw.moonlock.engine.systemextension/Contents/MacOS/com.macpaw.moonlock.engine` (runs as **root**). Seen beside a running CMM5 in one capture (`TaliskerMan/Monitro`). **Absent** in another CMM5 capture (`OpenAgentsInc/openagents`, 2026-09-20). It may belong to the standalone Moonlock app (`com.macpaw.moonlock`, shipped from `dl.devmate.com/com.macpaw.moonlock/Moonlock.dmg`). INFERRED |
| CLI (separate product) | `.app` + symlinks | `CleanMyMac_5_CLI.app`, binaries `cleanmymac`/`cmm`; group `S8EX82NJP6.com.macpaw.CleanMyMac5.CLI`; host `cli.cleanmymac.com` |

- **Team ID `S8EX82NJP6`** ("MacPaw Way Ltd" in profiles and PermissionsKit copyright). **(added)** Security tools list the signing identity as `Developer ID Application: MacPaw Inc. (S8EX82NJP6)` (VERIFIED: `chainguard-dev/osquery-defense-kit` allow-lists). App Group `S8EX82NJP6.com.macpaw.CleanMyMac5`. VERIFIED-BIN (provisioning profiles; cask). TCC entries this session also show `S8EX82NJP6/com.macpaw.CleanMyMac-mas` (MAS edition) and `…CleanMyMac-setapp` (Setapp) and `…CleanMyMac4`, `…zh.CleanMyMac4`. VERIFIED (`blacktop/ipsw-diffs` tccd string diff, fetched).
- The 5.x **Agent launchd plist** (fetched from a residue backup, `MYunFeiYang/zbookpowerg7`) is minimal:
  ```xml
  <key>Label</key><string>com.macpaw.CleanMyMac5.Agent</string>
  <key>MachServices</key><dict><key>com.macpaw.CleanMyMac5.Agent</key><true/></dict>
  <key>Program</key><string>/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent</string>
  <key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent</string></array>
  ```
  VERIFIED-BIN. (No `RunAtLoad`, no `KeepAlive` → launchd starts it **on demand** when a client connects to the Mach service; it exits when idle, matching MacPaw's "inactive unless needed; exits when the app quits" description.)
- **Provisioning-profile entitlements** (decoded this session):
  - HealthMonitor: `com.apple.application-identifier = S8EX82NJP6.com.macpaw.CleanMyMac5.HealthMonitor`, `keychain-access-groups = [S8EX82NJP6.*]`, `com.apple.developer.team-identifier = S8EX82NJP6`. AppIDName "CleanMyMac 5 Site HealthMonitor".
  - Menu: same shape, `…CleanMyMac5.Menu`.
  - FinderSyncExtension: adds `com.apple.security.application-groups = [S8EX82NJP6.*]`.
  VERIFIED-BIN.
- **Per-user data / uninstall footprint** (from cask `zap` + Fleet/IntuneBrew uninstall scripts): `~/Library/Application Support/CleanMyMac_5`, `~/Library/Caches/com.macpaw.CleanMyMac5`, `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5`, `~/Library/Application Scripts/S8EX82NJP6.com.macpaw.CleanMyMac5`, `~/Library/HTTPStorages/com.macpaw.CleanMyMac5(.binarycookies)`, `~/Library/Logs/com.macpaw.CleanMyMac5`, `~/Library/Preferences/com.macpaw.CleanMyMac5.plist`, `~/Library/Saved Application State/com.macpaw.CleanMyMac5.savedState`, and shared `/Users/Shared/CleanMyMac_5`. VERIFIED (cask zap, fetched). **(corrected)** The per-process logs `CleanMyMac_5`, `CleanMyMac_5_Menu` and `CleanMyMac_5_HealthMonitor` live in the **App Group container**, at `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Logs/<name>`, not under `~/Library/Logs`. VERIFIED (a Mole cleaner operations log in `andreychev/dotfiles`, found by GitHub code search). Implication for us: put shared logs/state in the app-group container so all our processes can write there.
- **(added) Other editions' layouts:**
  - **Setapp:** `com.macpaw.CleanMyMac-setapp` has its own SMJobBless helper `Contents/Library/LaunchServices/com.macpaw.CleanMyMac-setapp.Agent`. Its Menu login item is `Contents/Library/LoginItems/CleanMyMac_5_Setapp_Menu.app` (`com.macpaw.CleanMyMac-setapp.Menu`). VERIFIED (InjectLib config).
  - **Mac App Store:** `/Applications/CleanMyMac_5_MAS.app` with **two "Modern Login Items"**, `Contents/Library/LoginItems/CleanMyMac_5_MAS_Menu.app` and `…/CleanMyMac_5_MAS_HealthMonitor.app`. No launch daemon is listed for it, consistent with the sandbox. VERIFIED (EtreCheck sample in `dmdgolf/etrecheck-analyzer`).
- **(added) launchd domains:** `com.macpaw.CleanMyMac5.{HealthMonitor,Menu,Updater}` are jobs in the per-user `gui/<uid>` domain. `com.macpaw.CleanMyMac5.Agent` is in the `system` domain. VERIFIED (`fpcMotif/nix-darwin` disables them with `launchctl disable` per domain). The cask's `uninstall launchctl:` list (HealthMonitor, Menu) confirms that both login items are launchd jobs labelled by bundle id.

### 2.2 The `dumpbtm` view (how login items register on macOS 13+)

From a real `sfltool dumpbtm` dump of CleanMyMac X (`jinrenjie/blog`, fetched):

- Menu: `Type: app (0x2)`, identifier `com.macpaw.CleanMyMac4.Menu`, URL `…/CleanMyMac X.app/Contents/Library/LoginItems/CleanMyMac X Menu.app/`.
- Health Monitor: `Type: login item (0x4)`, identifier `com.macpaw.CleanMyMac4.HealthMonitor`, with **`Parent Identifier`** = the Menu — i.e. the Health Monitor is a **nested login item whose parent is the Menu app**. `Disposition: [enabled, disallowed, visible, notified]`. VERIFIED.

- **(added) Caveat:** that dump comes from a **pirated, re-signed** copy ("Developer Name: TNT …"), so the `Disposition`/signing fields are not representative. Only the nesting structure is useful evidence. In CMM X the HealthMonitor URL is relative (`Contents/Library/LoginItems/CleanMyMac X HealthMonitor.app`) to its parent, the Menu app. In 5.x MAS the HealthMonitor sits directly in the **main** app's `Contents/Library/LoginItems` (EtreCheck, above). A provisioning-file guide (`eliekh05/provision-files` CONTRIBUTING) shows the same for the direct edition. So 5.x likely flattened the nesting. INFERRED.

INFERRED for us: a background agent nested inside the menu-bar login item is a common pattern; a flat layout is simpler. **(corrected)** `SMAppService.loginItem(identifier:)` resolves the identifier against the *calling* app's `Contents/Library/LoginItems`. So a nested agent must be registered by the bundle that contains it, or simply not nested. LaunchAgents/LaunchDaemons registered from inside the app bundle are **associated with the app in the Login Items panel automatically**. `AssociatedBundleIdentifiers` is only needed for *legacy* plists installed outside the bundle. VERIFIED-APPLE (`updating-helper-executables-from-earlier-versions-of-macos`, fetched JSON).

### 2.3 CleanMyMac X (4.x) and 3.x — what the bundle reveals

VERIFIED-BIN from `auspham/mac-essential`'s committed `CleanMyMac 3.app` (I downloaded the Mach-O binaries and plists and ran `strings`/plist parsing this session):

- **Main app Info.plist:** `CFBundleIdentifier = com.macpaw.CleanMyMac3`, `NSPrincipalClass = CMApp` (X: `CMApplication`), `LSApplicationCategoryType = public.app-category.utilities`, `CFBundleURLSchemes = [cleanmymac]` (X: `cleanmymacx`), `SUEnableAutomaticChecks`, `SUEnableSystemProfiling` (Sparkle keys). It registers **`NSServices`** (Finder/Services menu): "Scan for Large and Old Files" (`scanFolderForLargeOld`, `public.folder`), "Clean with CleanMyMac" (`cleanVolume`, `public.volume`), "Uninstall with CleanMyMac" (`uninstallApplication`, `com.apple.application-bundle`), "Erase/Securely Erase with CleanMyMac" (`eraseItem`/`securelyEraseItem`). VERIFIED-BIN.
- **Sub-apps:** `CleanMyMac 3 Menu.app` (`LSUIElement=true`; declares `SMPrivilegedExecutables`) and `CleanMyMac 3 Scheduler.app` (`LSUIElement=true`). X renamed/kept the Menu and introduced HealthMonitor.
- **XPC services in the bundle:** `com.macpaw.CleanMyMac.IconsService.xpc` and `com.macpaw.CleanMyMac.LipoService.xpc` (`XPCService.ServiceType = Application`). These are **non-privileged, in-bundle XPC services** used to offload work (icon rendering; `lipo`/thin universal binaries). VERIFIED-BIN.
- **Storage-management app extension:** `StorageManagement.appex`, `NSExtensionPointIdentifier = com.apple.storagemanagement`, principal class `CMStorageManagementExtension`, display name "System Junk" — i.e. CleanMyMac integrated into macOS's own "Storage Management" panel. VERIFIED-BIN.
- **DevMate** auto-update stack bundled: `DevMateKit.framework` with `Autoupdate.app`, `Problem Reporter(.app)`, `com.devmate.UpdateInstaller.xpc`, `DevMateIssuesReporter.framework`, `CrashReporter.framework`. (DevMate was MacPaw's Sparkle-based distribution/analytics SaaS.) VERIFIED-BIN.
- **(added) CMM X 4.0.0 main Info.plist** (`Zfinix/zos` JSON, fetched):
  - `CFBundleIdentifier = com.macpaw.CleanMyMac4`, `NSPrincipalClass = CMApplication`, `NSMainStoryboardFile = Main`;
  - `SUEnableAutomaticChecks = false` and `SUAllowsAutomaticUpdates = false`. Sparkle's own scheduler is switched off; the app/Updater drives checks itself;
  - TCC usage strings for **Contacts, Calendars, Photos** (the cache cleanup touches those apps' data);
  - a catch-all `CFBundleDocumentTypes` entry (`*`, role Viewer), so any file can be dropped on or opened with the app (Shredder/Uninstaller);
  - `CFBundleHelpBookName = com.macpaw.CleanMyMac.help` and `LSMinimumSystemVersion = 10.10`.

  VERIFIED.
- **(added) Frameworks in CMM3:** `@rpath/DevMateKit.framework` and `@rpath/MPPhotos.framework` (MacPaw's Photos-library helper). **No `libswift*`** references: CMM3 is pure Objective-C. Its analytics are in-house `CMAnalyticsTracker` subclasses (`CMNPSAnalyticsTracker`, `CMSystemCleanupAnalyticsTracker`, `CMRecommendationAnalyticsTracker`, …). VERIFIED-BIN (fact-check `strings`).
- **Source paths** leaked in the binary reveal module structure: `ScanningService/…/CMScanner.m`, `KnowledgeBase/…/FMDatabase*.m`, `PrivilegedAgentDaemon/…/CMPermissionsRepair.m`, `CMMTools/…/CMLaunchdManager.m`, `Activation/DevMate Activation/…`, `Analytics/…/Trackers/…`. VERIFIED-BIN.

### 2.4 (added) What runs when — CleanMyMac 5 direct edition

| When | Process | launchd domain / mechanism | Evidence |
|---|---|---|---|
| User login | **Menu** (`com.macpaw.CleanMyMac5.Menu`) | `gui/<uid>` job, login item, cask `login_item: "CleanMyMac 5 Menu"` | VERIFIED (cask; nix-darwin; process capture) |
| User login | **HealthMonitor** (`com.macpaw.CleanMyMac5.HealthMonitor`) | `gui/<uid>` job, login item in `Contents/Library/LoginItems` | VERIFIED (cask `launchctl`; process capture) |
| Login + every 6 h | **Updater** (`com.macpaw.CleanMyMac5.Updater`) | user LaunchAgent plist in `~/Library/LaunchAgents`, `StartInterval 21600` (Setapp twin also `RunAtLoad`) | VERIFIED (cask zap; audit; Setapp plist) |
| On demand (first root task, then on each XPC connect) | **Agent** (root) | `system` domain, SMJobBless-written plist, `MachServices` only | VERIFIED (plist) + INFERRED-HIGH (SMJobBless) |
| When Finder needs it | **FinderSync extension** (sandboxed appex) | PlugInKit, enabled in System Settings › Extensions | VERIFIED (process capture; container) |
| User opens app | **Main app** `CleanMyMac_5` | normal launch | VERIFIED |
| Unresolved | `com.macpaw.moonlock.engine` ES sysext | `/Library/SystemExtensions/<UUID>/…` | conflicting (see §2.1) |

Our clone mirrors this with fewer moving parts:
- a `MenuBarExtra` (or one login-item app) that hosts the monitor;
- no separate Updater, unless we add Sparkle;
- an optional `SMAppService.daemon` helper, registered only when the user first runs a root task.

INFERRED.

---

## 3. The privileged helper (root Agent) & its XPC protocol

This is the single most important internal subsystem to copy *safely*.

### 3.1 Install / registration

- **CMM3 / CMM X:** installed with **`SMJobBless`** (legacy). Evidence: the Menu app's Info.plist contains
  ```xml
  <key>SMPrivilegedExecutables</key>
  <dict><key>com.macpaw.CleanMyMac3.Agent</key>
    <string>identifier com.macpaw.CleanMyMac3.Agent and anchor apple generic and certificate leaf[subject.OU] = "S8EX82NJP6"</string>
  </dict>
  ```
  and the Agent Mach-O embeds, in its `__TEXT,__info_plist`, an **`SMAuthorizedClients`** array:
  ```xml
  <string>(identifier "com.macpaw.CleanMyMac3.Menu" or identifier "com.macpaw.CleanMyMac3")
          and anchor apple generic and certificate leaf[subject.OU] = "S8EX82NJP6"</string>
  ```
  VERIFIED-BIN (both parsed this session). The main binary imports `_SMJobBless`, `_SMJobCopyDictionary`, `_SMLoginItemSetEnabled`, `_AuthorizationCreate`, `_AuthorizationCopyRights`. VERIFIED-BIN (`strings` of `CleanMyMac 3`).
- **CMM X (4.x)** keeps the same `SMJobBless` + `SMAuthorizedClients`/`SMPrivilegedExecutables` design, requirement string `… certificate leaf[subject.OU] = "S8EX82NJP6"`, helper at `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac4.Agent`. The `SMPrivilegedExecutables` DR for X 4.0 is visible in a committed Info.plist (`Zfinix/zos`): `identifier com.macpaw.CleanMyMac4.Agent and anchor apple generic and certificate leaf[subject.OU] = "S8EX82NJP6"`. VERIFIED-BIN.
- **CMM 5 (2024+)** keeps the same on-disk layout (`/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent` + `/Library/LaunchDaemons/…Agent.plist`) and a `MachServices` entry. **(added) Fact-check: the evidence now points strongly to legacy `SMJobBless`:**
  1. **Plist shape.** Apple's `SMJobBless` reference says ServiceManagement extracts the helper's embedded launchd plist, writes it to disk, and sets `ProgramArguments` to a one-element array pointing at the standard location. The 5.x residue plist is exactly that: `Program` and `ProgramArguments[0]` both equal `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`, with no `BundleProgram` and no `AssociatedBundleIdentifiers`. VERIFIED-APPLE (`smjobbless(_:_:_:_:)` JSON) + VERIFIED-BIN (plist).
  2. **Helper location in the bundle.** InjectLib's config gives the 5.x helper as `/Contents/Library/LaunchServices/com.macpaw.CleanMyMac5.Agent` (`autoHandleHelper: true`). `Contents/Library/LaunchServices/<label>` is the location `SMJobBless` *requires*. An `SMAppService` daemon would be referenced from `Contents/Library/LaunchDaemons/*.plist` via `BundleProgram`. VERIFIED (InjectLib `config.json`) + VERIFIED-APPLE.
  3. **`SMPrivilegedExecutables` exists.** InjectLib's `main.py` handles such helpers by rewriting `SMPrivilegedExecutables:<helper>` in the app's `Info.plist` with PlistBuddy `Set`. That edit fails if the key is absent, and the key is meaningful only for SMJobBless. VERIFIED (source) → INFERRED that 5.x's Info.plist carries `SMPrivilegedExecutables`.
  4. **Not on the SMAppService path.** An `SMAppService.daemon` plist stays inside the bundle (`Contents/Library/LaunchDaemons`). It is never copied to `/Library/LaunchDaemons` or `/Library/PrivilegedHelperTools`. VERIFIED-APPLE (`daemon(plistName:)`; migration guide).

  **Conclusion: 5.x installs its Agent with `SMJobBless`.** INFERRED-HIGH. `SMJobBless` has been deprecated since macOS 13 ("Please use SMAppService instead") but still works. Apple's guide says a legacy daemon plist without `AssociatedBundleIdentifiers` is shown in System Settings › Login Items under the **organization name from its signing certificate**. VERIFIED-APPLE (migration guide). **Tension:** MacPaw's `cleanmymac-agent` KB, as summarized by tracks 01/13 and not re-fetchable here, reportedly says macOS does *not* list the Agent as a background item. Which is true on 14/15/26 is unverified; check with `sfltool dumpbtm` (§13). On-device confirmation commands are in §13.
- **Install trigger:** lazy. The helper is installed the first time an operation needs root (admin-password prompt), not at first launch. It is inactive unless needed. VERIFIED-KB (macpaw.com `cleanmymac-agent` KB as summarized by tracks 01/13; not re-fetchable in the fact-check: macpaw.com blocked). Consistent with the plist having no `RunAtLoad`/`KeepAlive`, and with the Agent not appearing in a 2026-09-20 process list where Menu/HealthMonitor/FinderSync were running. VERIFIED (OpenAgents capture).
- **launchd wiring (CMM3 Agent embedded plist):**
  ```xml
  <key>Label</key><string>com.macpaw.CleanMyMac3.Agent</string>
  <key>MachServices</key><dict><key>com.macpaw.CleanMyMac3.Agent</key><true/></dict>
  <key>Sockets</key><dict><key>MasterSocket</key><dict>
     <key>SockFamily</key><string>Unix</string>
     <key>SockPathName</key><string>/var/run/com.macpaw.CleanMyMac3.Agent.socket</string>
     <key>SockPathMode</key><integer>438</integer>  <!-- 0666 -->
     <key>SockType</key><string>Stream</string></dict></dict>
  ```
  VERIFIED-BIN. (CMM3 used both a Mach service and a `launchd`-created Unix socket at `/var/run/…`; mode 0666 is world-rw — a listening socket, not itself an auth boundary. 5.x's plist drops the socket and keeps only `MachServices`. INFERRED improvement over time.)

### 3.2 The XPC protocol (`CMPrivilegedOperation(s)`)

The helper vends an Objective-C protocol over `NSXPCConnection`. Method selectors extracted this session from the **CMM3 Agent binary** (`strings`), corroborated by the Talos advisory (X 4.04) and the 0day.today advisory (CMM3). These are the *capabilities a cleaner's root helper needs*; we list them so our clone's allow-list is complete and so we understand the attack surface. VERIFIED-BIN / VERIFIED (Talos/0day).

**File-system verbs**
`removeItemAtPath:withReply:`, `removeFileAtPath:error:`, `removeContentsOfDirectoryAtPath:`,
`moveItemAtPath:toPath:withReply:`, `moveItemAtPath:toPath:createDstIntermediatePath:removeDstPath:error:`,
`moveToTrashItemAtPath:withReply:`, `copyItemAtPath:toPath:error:`, `createDirectoryAtPath:withIntermediateDirectories:attributes:`,
`truncateFileAtPath:withReply:` / `truncateFileAtOffset:`, `securelyRemoveItemAtPath:withReply:` (+`com.macpaw.CleanMyMac.SecureRemoveErrorDomain`).

**Sizing / enumeration (read-only helpers)**
`sizeOfItemAtPath:reply:`, `itemSizeAtPath:`, `com_macpaw_FTSWalkAtPath:recursive:handler:` (an `fts_open`-based walker), `contentsOfDirectoryAtPath:error:`, `statCreationTimeAtPath:`/`statModificationTimeAtPath:`/`statAccessTimeAtPath:`, `fileExistsAtPath:`, `isFileDirectoryAtPath:`.

**launchd / login items**
`removeLaunchdAgentAtPath:withReply:`, `enableLaunchdAgentAtPath:withReply:`, `disableLaunchdAgentAtPath:withReply:`, `unloadAgentAtPath:shouldDisable:`, `jobLabelForLaunchdAgent:`, `removeSMLoginItem:withReply:`, `removeGlobalLoginItemForAppWithPath:withReply:`, `removePrivilegedToolWithLabel:`, `startStartupItem:withReply:` / `stopStartupItem:withReply:`.

**System maintenance**
`flushDNSWithReply:` (**(corrected)** two code paths in the strings: `/usr/sbin/discoveryutil mdnsflushcache` + `udnsflushcaches` for OS X 10.10.0–10.10.3, otherwise `/usr/sbin/dscacheutil -flushcache` + `/usr/bin/killall -HUP mDNSResponder`), `startSpotlightReindexWithReply:` (`/usr/bin/mdutil`), `runPeriodicScript:withReply:` (`/usr/sbin/periodic`), `removeASLWithReply:` (stop/start `com.apple.syslogd` and `com.apple.aslmanager`, clear `/var/log/asl`), `removeDiagnosticLogsWithReply:` (**(added)** `/usr/bin/log erase --all`; Talos also describes this verb building an `erase`/`all` command), `repairPermissionsWithReply:`/`repairPermissionsWithReportProgress:` (`/usr/libexec/repair_packages --repair`), `removePackageWithID:withReply:` (`/usr/sbin/pkgutil --forget`), `removeKextAtPath:withReply:` (`/sbin/kextunload`), `removeLibraryFromLauchdConf:withReply:` (**(added)** strips `DYLD_INSERT_LIBRARIES` lines from `/etc/launchd.conf`, an anti-adware fix), `startStartupItem:`/`stopStartupItem:` (`/sbin/SystemStarter start|stop "<name>"`). **(corrected)** The XPC verb is `slimBinaryWithPath:archs:withReply:`; `slimBinaryAtPath:archsToLeave:` is the internal worker. The Agent strings contain `/usr/bin/ditto` (which can thin with `--arch`) but **no `lipo`**; `lipo` work runs in the main bundle's `LipoService.xpc`. VERIFIED-BIN (fact-check `strings` of the Agent).

**(added) Safety behaviours visible in the CMM3 Agent:**
- It references **`com.apple.rootless`**, the SIP-protection attribute name. String VERIFIED-BIN; its use as a pre-delete SIP check is INFERRED.
- It tries to clear the **immutable flag** before removing: "Failed to unset immutable flag for %@ with error: %d". VERIFIED-BIN.
- It treats a **missing path** as an error rather than a no-op: "Missing path. Treat as an error." VERIFIED-BIN.

Copy the intent into our helper: skip SIP-protected items, handle `uchg` explicitly with user confirmation (never try to clear `schg`), and fail closed.

**(added) Obsolete verbs on our target OS (macOS 14+):** do not port these. INFERRED from general macOS history; only the `periodic` and `repair_packages` man-page facts were checked, in track 05.
- `/etc/launchd.conf` (ignored since 10.10);
- `/sbin/SystemStarter` and StartupItems (removed);
- `discoveryutil` (10.10 only);
- ASL `/var/log/asl` (replaced by unified logging);
- `repair_packages` (no man page on 11+; Apple dropped permission repair with SIP in 10.11);
- `kextunload` (superseded by `kmutil`).

`/usr/sbin/periodic` exists on 14 but is **gone on macOS 15+**: no binary, no man page, no `com.apple.periodic-*` jobs. VERIFIED by track 05 §4.4; not re-checked in this pass.

**Lifecycle**
`pleaseTerminate` (DoS-prone; see CVE-2018-4046), `setXpcConnection:`, `listener:shouldAcceptNewConnection:` (the `NSXPCListenerDelegate`).

The helper links Security transforms (`SecTransformExecute`, `SecEncodeTransformCreate`/`SecDecodeTransformCreate`, i.e. Base64/hex coding), `CC_MD5`, and `NSXPCInterface`/`NSXPCListener`. VERIFIED-BIN. **(corrected)** `CCCrypt` is imported by the *main app*, not by the Agent.

### 3.3 Security history — the Talos disclosure (our design driver)

VERIFIED (official CVE JSON from `CVEProject/cvelistV5`, re-fetched in the fact-check; Talos blog mirror, re-fetched). All share **CVSS 3.0 7.1 (AV:L/AC:L/PR:N/UI:N/S:C/C:N/I:H/A:N)**. **(corrected)** The 13 CVE-2018-* entries are "Improper Input Validation" in **"Clean My Mac X 4.04"**, published **2019-01-10**. CVE-2019-5011 is **CWE-459** in **4.20**, published **2019-03-21**. Discovered by Tyler Bohan (Cisco Talos). The method↔CVE mapping below matches the Talos post headings.

| CVE | Talos | Helper method | What it let a non-root local process do |
|---|---|---|---|
| 2018-4032 | 0705 | `moveItemAtPath:` | supply `nil` destination → file **deleted** as root |
| 2018-4033 | 0706 | `moveToTrashItemAtPath:` | delete root files via a nil argument |
| 2018-4034 | 0707 | `removeItemAtPath:` | delete any file as root |
| 2018-4035 | 0708 | `truncateFileAtPath:` | truncate/corrupt any file as root |
| 2018-4036 | 0709 | `removeKextAtPath:` | unload/remove kexts as root |
| 2018-4037 | 0710 | `removeDiagnosticsLogs` | delete system log data as root (builds an `erase` … `all` command, i.e. `log erase --all`) |
| 2018-4041 | 0715 | `enableLaunchdAgentAtPath:` | load a launchd agent as root |
| 2018-4042 | 0716 | `removeLaunchdAgentAtPath:` | remove a launchd agent as root |
| 2018-4043 | 0717 | `removeASL` | stop syslogd / ASL as root |
| 2018-4044 | 0718 | `removePackageWithID:` (`pkgutil --forget`) | delete package receipts as root |
| 2018-4045 | 0719 | `securelyRemoveItemAtPath:` | securely delete any file as root |
| 2018-4046 | 0720 | `pleaseTerminate` | **DoS**: kill the root daemon |
| 2018-4047 | 0721 | `disableLaunchdAgentAtPath:` (`launchctl`) | uninstall launchd scripts as root |
| **2019-5011** | 0759 | — (CWE-459 Incomplete Cleanup) | upgrading to 4.20 **left the old vulnerable helper on disk** |

- **Root cause (all of them):** the `NSXPCListener shouldAcceptNewConnection:` delegate **accepted every connection** and the methods took raw caller-supplied paths; there was **no verification of the client's code signature / identity**, despite the `SMAuthorizedClients` DR (which only governs *install*, not *per-call* trust). The 0day.today CMM3 advisory shows the same class of bug about six months earlier (dated 2018-07-27; corrected from "a year earlier") via `runPeriodicScript:` (hand `periodic` a directory of attacker scripts → arbitrary root code). VERIFIED (Talos; 0day).
- **Fix:** Talos tells users to update to **X 4.2.0** and links MacPaw's "cleanmymac-x-update-4.2.0" blog post (VERIFIED, Talos mirror). For 2019-5011 MacPaw also had to remove the stale helper left by upgrades (VERIFIED). The "(2018-12)" date is INFERRED from the disclosure timeline (corrected: not stated in the sources re-read).
- The 0day.today CMM3 advisory is dated **2018-07-27**, author **Chi Chou**. It names the protocol `CMPrivilegedOperation` and the Mach service `com.macpaw.CleanMyMac3.Agent`. VERIFIED (archive re-fetched).
- **This is exactly the trap our clone must avoid** (§12).

### 3.4 Objective-See / broader context

Patrick Wardle's tools weren't directly fetchable, but the pattern CleanMyMac's helper embodies (an `SMJobBless` root daemon exposing generic file verbs over XPC without per-client validation) is the canonical "insecure privileged helper" class Wardle and Jonathan Levin popularised, and the **OffensiveCon "Privileged Helper Tools"** survey (`blankwall/Offensive-Con`, fetched) lists `com.macpaw.CleanMyMac4.Agent` as **"patched."** `chainguard-dev/osquery-defense-kit` treats `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac4.Agent` signed by `Developer ID Application: MacPaw Inc. (S8EX82NJP6)` as a known-good root daemon. VERIFIED (fetched).

---

## 4. Full Disk Access — detection, request, behaviour

MacPaw open-sourced its FDA logic as **`PermissionsKit`** (`MacPaw/PermissionsKit`, fetched). This is almost certainly the same approach CleanMyMac uses. VERIFIED.

- **No public API to *request* FDA.** The only legal move is to deep-link to System Settings and **poll**:
  ```objc
  [workspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]];
  ```
  **(added)** On macOS 13+ (System Settings) the commonly used form is `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`. Many apps try it first and fall back to the legacy URL above, which still resolves. VERIFIED (GitHub code search: e.g. `lobehub/lobehub` `permissions.ts` tries both). Neither URL is documented by Apple, so treat them as best-effort and always show manual instructions too. INFERRED.
- **Detection** = attempt `open(path, O_RDONLY)` on a set of TCC-protected files; `fd != -1` → **Authorized**; `errno == EPERM || EACCES` → **Denied**; otherwise **NotDetermined**. Multiple files are tried because any one might be absent or blocked for unrelated reasons:
  - `~/Library/Safari/CloudTabs.db`
  - `~/Library/Safari/Bookmarks.plist`
  - `~/Library/Application Support/com.apple.TCC/TCC.db`
  - `/Library/Preferences/com.apple.TimeMachine.plist`
  VERIFIED (`MPFullDiskAccessAuthorizer.m`, re-fetched in the fact-check). The aggregation rule: the first readable file → Authorized (stop). Any file that gives `EPERM`/`EACCES` → Denied, unless a later file is readable. All files missing → NotDetermined. Before macOS 10.14 it returns Authorized unconditionally.
- **Sandbox nuance:** in a sandboxed (MAS) build the home dir is the container; PermissionsKit resolves the **real** home via `getpwuid(getuid())->pw_dir` when `APP_SANDBOX_CONTAINER_ID` is set, and the app must carry temporary-exception entitlements to read those files. VERIFIED.
- **No completion callback** when FDA is granted — you must **poll** (PermissionsKit says so explicitly) or re-check on `NSApplication` foreground. VERIFIED.
- **Vendor UX (prior tracks):** CleanMyMac tells users to run a scan first so the app's components register in the FDA list, then toggle it on; the Assistant shows an "Allow Access" shortcut. Without FDA, mail-attachment malware scanning is unavailable, Trash on some volumes can't be listed, and the Health Monitor lacks disk data. VERIFIED (macpaw.com FDA KB, via tracks 01/02).
- **TCC footprint:** macOS `tccd` ships a built-in allow/annotation list that names `S8EX82NJP6/com.macpaw.CleanMyMac{4,5,-mas,-setapp}` and `com.macpaw.zh.CleanMyMac4` (also competitor `S7F733N4B5/com.drbuho.BuhoCleaner`). VERIFIED (tccd string diff). **(corrected)** The `kTCCServiceBluetoothAlways` grant in `LunaParker/macos-permission-report` belongs to **`com.macpaw.CleanMyMac5`** (the app), not the Moonlock engine. VERIFIED (that repo's `generate_report.py`). Its likely purpose is the Menu's connected-device / Bluetooth battery widgets. INFERRED.

**For our clone (INFERRED):** reimplement PermissionsKit's probe (our own file list, e.g. `~/Library/Safari/Bookmarks.plist`, `~/Library/Mail`, `/Library/Application Support/com.apple.TCC/TCC.db`), deep-link to `Privacy_AllFiles`, poll every 1–2 s, auto-advance when a protected read succeeds. Run a first scan to force component registration so our app appears in the FDA list.

---

## 5. Sandboxing & editions

- **Direct edition** (MacPaw Store / Homebrew): **not sandboxed**, Developer-ID signed + notarized, Sparkle self-update, full feature set, ships the root Agent. VERIFIED (cask; prior tracks). (corrected: Setapp is listed separately below; it ships its own Agent, but its app updates come from Setapp.)
- **Mac App Store edition** (`id1339170533`, bundle suffix `-mas`): **sandboxed**; drops Updater, Shredder, some maintenance; can't delete MAS app binaries (reset only); no Leftovers; no App-Store/macOS update listing. VERIFIED (prior tracks; MAS missing-features KB).
- **Setapp edition** (`-setapp`): own Updater LaunchAgent `com.macpaw.CleanMyMac-setapp.Updater` pointing at `~/Library/Application Support/CleanMyMac Setapp/CleanMyMac X Updater.app`, with `RunAtLoad true`, `StartInterval 21600`, `EnableTransactions true`. VERIFIED (`droxey/dotfiles` plist, re-fetched). **(added)** Setapp itself updates the app binary, yet this edition still has an "Updater" agent. So the Updater's job likely includes **background data updates**: the Safety Database / malware signatures and update nags, not just app updates. INFERRED. For us: one scheduled agent can refresh rule data whether or not the app updates itself.

**For our clone (INFERRED):** build the **direct, non-sandboxed** edition only (full capability on a personal Mac mini). Sandboxing would block the helper, arbitrary-path scanning, and most maintenance.

---

## 6. The Safety Database / "knowledge base"

CleanMyMac's safety guarantee ("doesn't delete user files unless you choose to") is enforced by a **signed, encrypted rules file** consulted on every scan, updatable in the background. VERIFIED (prior tracks: safety-database KB). This session I confirmed its on-disk form in CMM3:

- Files shipped in `CleanMyMac 3.app/Contents/Resources`: **`info.cmmkb`** and **`KnowledgeBase.pem`**. VERIFIED-BIN.
  - `info.cmmkb`: 435,200 bytes, **entropy ≈ 8.0 bits/byte**, no plaintext, no bplist/SQLite/zip magic. **(added)** The size is exactly **425 × 1024-byte pages**; the first 16 bytes look random (a SQLCipher salt).
  - `KnowledgeBase.pem`: 654 bytes, `-----BEGIN PUBLIC KEY-----`. **(corrected)** `openssl asn1parse` shows OID `dsaEncryption`: a **1024-bit DSA** key, the Sparkle-1 signing scheme, *not* RSA.
- The main binary's knowledge-base layer uses **FMDB (SQLite)**: `KnowledgeBase/.../FMDatabase.m`, `FMDatabaseQueue.m`, `FMResultSet.m`. **(added)** It also has `FMEncryptedDatabase.m`, `FMResultSet+Mapping`, `FMDatabase+SQLiteMocking` and `CMKnowledgeBaseObfuscation.h`. Classes: `CMKnowledgeBase`, `CMKnowledgeBaseBundle`, `CMKnowledgeBaseInstaller`, `CMKnowledgeBaseInjector`, `CMKnowledgeBaseScanners`, `CMKnowledgeBaseItemInfos`, `CMKnowledgeBaseState`, `CMKBApplicationInfo`. Notifications: `CMKnowledgeBaseDidAdd/RemoveItemNotification`. VERIFIED-BIN.
- **(corrected) Encryption = SQLCipher.** The main binary statically links SQLCipher. Strings include `cipher_use_hmac`, `cipher_page_size`, `cipher_default_kdf_iter`, `cipher_migrate`, `hexrekey`, `SELECT sqlcipher_export('migrate');`, `PRAGMA kdf_iter = 4000;` and `PRAGMA cipher_use_hmac = OFF;`. Those PRAGMAs are the SQLCipher-1.x-compatibility settings: AES-256-CBC, PBKDF2 4000 iterations, no per-page HMAC, 1024-byte pages. They match the file size above. So **`info.cmmkb` is a SQLCipher-encrypted SQLite DB** queried through FMDB. VERIFIED-BIN. The key-derivation secret is obfuscated in code (`CMKnowledgeBaseObfuscation.h`); we did not and will not extract it.
- **(corrected) What the RSA/AES strings really are.** The strings "Failed to export AES256 key", "Cannot verify (decrypt) without the public key, which is currently nil", "Invalid signature.", `PEM_read_bio_RSA_PUBKEY` and `RSA_public_decrypt` sit in the **DevMate Kevlar licensing** block. Neighbouring strings: `com.devmate.kevlarValidator`, "License hash missmatch", "License expired", `activations.devmate.com`, and OpenSSL loaded at runtime from `/usr/lib/libcrypto.35.dylib`. They concern **license/activation verification, not the knowledge base.** VERIFIED-BIN. The earlier "RSA-verified, CCCrypt-decrypted KB" conclusion is withdrawn.
- **(added) Delivery/update channel.** The KB is updated by a **second Sparkle updater**. The binary holds two `DM_SUUpdater` properties, `_mainUpdater` and `_kbUpdater`, plus the delegate `feedURLStringForUpdater:`. The KB pseudo-bundle has id `com.macpaw.CleanMyMac3.KnowledgeBase` and name "CleanMyMac Safety DataBase". Its keys sit next to `SUPublicDSAKey`/`SUPublicDSAKeyFile` → `KnowledgeBase.pem`. Updates are `CMMKB-%@.zip` archives. A test feed is selected by the default `UseTestUpdatesForKnowledgeBase`. A per-user copy is migrated into a user KB folder (`_userKnowledgeBaseFolderForVersion:`, `userInfo.cmmkb`). An `isKnowledgeBaseDisabled` switch exists. VERIFIED-BIN. **Pattern worth copying:** ship the rules DB as its own signed, versioned update channel, separate from app updates.
- Delivery host for 5.x: `cmd-cdn.cleanmymac.com` is plausible but its role is INFERRED (corrected: the source rule sets are CDN *routing* lists, e.g. `SukkaW/Surge` `domainset/cdn.conf`, not statements of purpose). Prior tracks: "Enable background updates of … Safety Database."
- **(added) The rules are shared across MacPaw products.** The 5.x CLI wiki says its detection logic "is based on cleanup rules shared with CleanMyMac". The Safety Database is a standalone component reused by the GUI and the CLI. VERIFIED (cleanmymac-cli Safety-and-Privacy wiki, re-read). 5.x's on-disk KB format is still unconfirmed (GAP). The CMM3 design (SQLCipher DB + separately signed update channel) is the best-evidenced template.

**For our clone (INFERRED):** ship a versioned **signed knowledge base** (our own schema; design in track 06 §3.11). Concretely: a JSON or SQLite rules file + an **Ed25519** detached signature verified at load (modern; DSA-1024 as used by CMM3 is long obsolete). Encryption at rest is unnecessary for a personal build: the vendor's SQLCipher layer protected IP, not users. Prefer plain SQLite/JSON + signature. Rules cover protected locations (never walk `/System`, `/System/Library`, `~/Library/Keychains`, `~/Library/Mobile Documents`), app-specific cache exceptions (Spotify offline cache, Gradle), and per-app uninstall maps. Fetch updates over HTTPS from our own endpoint; verify signature before replacing the local copy; never execute anything from it.

---

## 7. Scanning engine — structure & performance

### 7.1 Module/scanner taxonomy (CMM3, VERIFIED-BIN)

The engine is a tree of **`CMScanner`** subclasses grouped by **`CMGroupScanner`**s, driven by `CMScannerSpecification`, `CMScannerDescriptionProvider`, measured by `CMScannerStatistician`. Extracted scanner classes (73): System/User/Caches/SystemCaches/UserCaches/System-User-Logs/Logs, Trashes/MountedTrashes/MailTrashes/ApertureTrashes/PhotosTrashes, Mail(Attachments/Group/Maintenance), iTunes(Caches/Downloads/Group), iOS(Apps/Backups/SoftwareUpdates), Photos(CachesCleanup/RAWCleanup/SyncCaches/Sierra), LargeOld (`CMLAOFScanner`/`CMLAOFGroupScanner`), Apps/AllApps/AppsGroup/LeftoversApps, extension scanners (Safari/Chrome/Firefox/Opera/Skype/WebKit/Growl/AudioPlugin/LaunchAgents/LoginItems/PrefPanes/ScreenSaver/Services/Widgets/Plugin), Privacy(Group)/RecentItems, Maintenance(Periodic/Spotlight/DNS/DiskRepair/StartupDiskRepair/PermissionsRepair/LSDBRebuild/Mail), Eraser/EraserGroup (Shredder), UniversalBinaries, AppLanguages/SystemLanguages, BrokenPrefs/BrokenStartupItems/BrokenApplicationsUpdates, DevJunk/XcodeJunk. VERIFIED-BIN.

INFERRED mapping to 5.x modules: these roll up into **Cleanup** (System/Photo/Mail/iTunes junk, Trash), **Performance/Maintenance**, **Applications** (Uninstaller/Leftovers/Updater), **Protection** (Privacy traces), **Clutter/Large&Old**, **Shredder**.

### 7.2 Performance techniques (VERIFIED-BIN + INFERRED)

- **FTS walk:** the helper exposes `com_macpaw_FTSWalkAtPath:recursive:handler:` and the binary imports `fts_open$INODE64` — size/enumeration uses the C `fts(3)` API, far faster than `NSFileManager` enumeration. VERIFIED-BIN.
- **Spotlight metadata** for Large & Old: imports `NSMetadataQuery`, `MDItemCreate`, `MDItemCopyAttribute`, `kMDItemLastUsedDate`, `kMDItemContentModificationDate`, `kMDItemPhysicalSize`, `NSMetadataQueryUserHomeScope` → it queries the Spotlight index rather than walking the disk. VERIFIED-BIN.
- **Concurrency:** imports `NSOperationQueue`; scanners run on operation queues (parallel per-scanner). VERIFIED-BIN. **(added)** Named queues in the binary include `sizeCalculationQueue`, `estimationQueue` and `operationQueue`. Sizing is a separate pipeline from discovery, so lists can appear before the sizes finish. VERIFIED-BIN. INFERRED: bounded `maxConcurrentOperationCount`.
- **(added) fts error sites:** `CMFTSFileManager error in fts_open`, `nibsJunkForApplicationAtPath error in fts_open`, `languagesForApplicationAtPath error in fts_open`. So the main app (not only the helper) walks bundles with `fts(3)` to find localization (`.lproj`) and NIB junk. VERIFIED-BIN. No `getattrlistbulk` reference was found; that remains our own optimization idea (INFERRED).
- **Offloaded work via in-bundle XPC:** `IconsService` (icon extraction) and `LipoService` (`lipo`) run out-of-process to keep the UI responsive and isolate crashes. VERIFIED-BIN.
- **Purgeable space (5.x):** the "Free Up Purgeable Space" maintenance task arrived in **5.0.5** (release notes, VERIFIED). With the CLI's `optimize purgeable`, it asks macOS to release purgeable bytes. The public way to *measure* purgeable space is the URL resource keys `volumeAvailableCapacityForImportantUsageKey` / `…ForOpportunisticUsageKey` (fetched Apple docs). **(corrected)** The unified-log lines `CleanMyMac_5_HealthMonitor … [com.apple.cache_delete:client] com.apple.logd.cachedelete` show the HealthMonitor acting as a **CacheDelete client** (querying). They do not show a purge. A third-party "System Monitor" app emits identical lines in the same log every few seconds, which is what periodic free-space/purgeable *queries* look like. VERIFIED (`pabloguia/XCodeVault` log, re-read). How 5.x actually *triggers* purging is unconfirmed: private CacheDelete SPI, or the classic fill-the-disk-with-a-temp-file trick. INFERRED; see track 05.

**For our clone (INFERRED performance budget, Apple-Silicon SSD):** enumerate only known locations (never a full-disk walk); use `getattrlistbulk`/`fts` for bulk stat; use `NSMetadataQuery` for Large&Old; parallelise per-category with a bounded queue; hash duplicates with a size-bucket → 4 KB head/tail → full SHA-256-on-collision ladder. Target: Cleanup ≤ 15 s, a Smart scan ≤ 60 s (see track 02/05).

---

## 8. Update mechanism

- **CMM 5 (direct):** Sparkle 2. The `cleanmymac` cask's `livecheck` reads the **appcast** `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml` (strategy `:sparkle`); binaries at `https://updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_<build>.zip`; `auto_updates true`. The InjectLib config lists `Sparkle.framework/Versions/B/Sparkle` as 5.x's inject target → **Sparkle is embedded**. A dedicated **Updater LaunchAgent** (`com.macpaw.CleanMyMac5.Updater`) wakes every **21600 s (6 h)** (audit evidence: `…Updater.plist:18`). VERIFIED (cask; `zixing131/…InjectLib`; `MichelKerkmeester/…` audit; fetched).
- **Build-number scheme:** `MMmmpp.0.YYMMDDHHMM` (e.g. `50701.0.2609301754` = v5.7.1 built 2026-09-30 17:54). Latest observed **5.7.1** (cask `version "5.7.1,50701.0.2609301754"`, re-fetched 2026-10-12). Min macOS 11: VERIFIED via the legacy appcast's `sparkle:minimumSystemVersion` 11.0 (5.0.x–5.3.1) and the CLI cask's `depends_on macos: :big_sur`. **(corrected)** The main `cleanmymac` cask says only `depends_on :macos` (no minimum), and "up to macOS 27" is not stated in any source re-read here (INFERRED / from track 01).
- **(added) Legacy 5.x appcast (DevMate infrastructure).** A Sparkle feed titled "CleanMyMac 5" is served from DevMate's S3 bucket: `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml`. It was fetched through the S3 path-style host; the `updateinfo.devmate.com` and `dl.devmate.com` hostnames are proxy-blocked here. It lists **23 items, 5.0.0 (50000.0.2410151250, 2024-10-15) → 5.3.1 (50301.0.2601271414, 2026-01-28)**. Key facts:
  - Enclosures are `https://dl.devmate.com/com.macpaw.CleanMyMac5/<build>/<unix-ts>/CleanMyMac5-<build>.zip` (5.3.1 ≈ 194 MB).
  - Some items carry `<sparkle:deltas>` (binary deltas from the previous 1–3 builds, 5–16 MB each).
  - Release notes: `updates.devmate.com/releasenotes/<build>/<lang>/com.macpaw.CleanMyMac5.html` in **13 locales**: de, en, es, fr, it, ja, ko, nl, pl, pt-BR, tr, uk, zh-Hans.
  - `minimumSystemVersion` is 11.0.
  - The feed has **no `sparkle:edSignature` or `dsaSignature` attributes**.

  Sparkle 2 still accepts updates to an app bundle when the old app has no (Ed)DSA public key, if the new bundle is validly code-signed by the same Developer ID team; it refuses an update that removes code signing. VERIFIED (Sparkle `SUUpdateValidator.m`, 2.x branch). So CMM5 updates were authenticated by **Apple code signing only**, at least on this feed. INFERRED for the current `updates.cleanmymac.com` feed, which could not be fetched (proxy 403). After 5.3.1 the cask points at `updates.cleanmymac.com/com.macpaw.cleanmymac5/releases/CleanMyMac5_<build>.zip` (underscore naming). MacPaw moved 5.x hosting off DevMate in early 2026 (INFERRED from the feed ending at 5.3.1).
- **(added) Sparkle 2 detail:** the `Versions/B` framework layout that InjectLib targets is Sparkle 2's: Sparkle changed `FRAMEWORK_VERSION` from A to B (VERIFIED: `sparkle-project/Sparkle` `Configurations/ConfigFramework.xcconfig`). Sparkle's built-in scheduler defaults to 86,400 s with a 1-hour floor (`SUScheduledCheckInterval`). CMM X set `SUEnableAutomaticChecks=false` and used its own Updater agent at 21,600 s instead (VERIFIED: Sparkle docs; CMM X Info.plist).
- **CMM X / 3 (direct):** **DevMate** (MacPaw's Sparkle fork + analytics). Bundle ships `DevMateKit.framework` with `Autoupdate.app`, `com.devmate.UpdateInstaller.xpc`, crash/issue reporters; appcasts under `updates.devmate.com`/`updateinfo.devmate.com`; downloads from `dl.devmate.com/com.macpaw.CleanMyMac4/CleanMyMacX.dmg`. The X Updater app is a separate `CleanMyMac X Updater.app` (v1.3.2) under `~/Library/Application Support/CleanMyMac X/`. VERIFIED-BIN / VERIFIED (fetched manifests, system_profiler).
- **MAS/Setapp:** no Sparkle — App Store / Setapp handle updates. VERIFIED.

**For our clone (INFERRED):** for a personal Mac mini, **skip auto-update entirely** (rebuild & reinstall), or add **Sparkle 2** with an Ed25519-signed appcast you host. If added, keep the updater inside the app (use Sparkle's `SPUStandardUpdaterController`); do **not** ship a world-writable helper for updates.

---

## 9. Telemetry / analytics

VERIFIED (host-block rulesets `SukkaW/Surge`, `Repcz/Tool`; firebog block-lists; binary URLs; bug-bounty host dumps):

- **Analytics endpoint:** `api-lytics.macpaw.com` (and `old-api-lytics.macpaw.com`, `analytics.macpaw.com`, `catalina.macpaw.com`). **(corrected)** It is in some privacy block lists (e.g. firebog `w3kbl`). The `SukkaW/Surge`/`Repcz/Tool` lists cited earlier are **CDN routing** sets, not block lists. VERIFIED (GitHub code search).
- **(added) CMM3 analytics implementation:** in-house tracker classes (`CMAnalyticsTracker`, `CMAnalyticsTrackerRequestBuilder`, `CMAnalyticsTrackerDebugEndpointKey`; subclasses for NPS, system cleanup, recommendations, active issues, license info). No Google Analytics strings were found in a re-run of `strings`. VERIFIED-BIN.
- **Knowledge-base/command CDN:** `cmd-cdn.cleanmymac.com`; general CDN `cdn.macpaw.com`, `cdn2.macpaw.com`.
- **Menu speed test:** `speedtest.macpaw.com` (routed DIRECT in proxy rulesets).
- **CMM3 extras (binary URLs):** `api-lytics.macpaw.com`, DevMate activation `activations.devmate.com/activation.php`, (corrected: Google-Analytics-for-OS-X is a MacPaw repo but is **not** referenced by the CMM3 binary), `software.macpaw.com/cleanmymac2/lookup`, subscription endpoints `macpaw.com/backend/cleanmymac_subscribe`. VERIFIED-BIN.
- **Moonlock engine** has its own `cdn-public-apis.moonlock.com`. VERIFIED (ruleset).
- CLI: analytics **can be disabled** via `cleanmymac config` (the settings include "the analytics toggle"); "no source code or personal files are uploaded." VERIFIED (cleanmymac-cli README, re-read). (corrected) "On by default" is not stated explicitly; INFERRED from opt-out wording.

**For our clone (INFERRED):** **ship zero telemetry.** No analytics host, no crash reporter calling home. Keep all history local (the "My Activity" equivalent) in the app-group container. This is both a privacy win and avoids any MacPaw-host contact.

---

## 10. Languages & frameworks

- **CleanMyMac X / 3:** Objective-C + AppKit (`CMApplication`/`CMApp` principal class; X 4.0 uses `NSMainStoryboardFile = Main`), CoreFoundation/CoreServices/Security, CommonCrypto, FMDB + **SQLCipher** (corrected/added), DevMateKit (Sparkle fork, `DM_SU*` classes), MPPhotos.framework. No Swift runtime in CMM3. VERIFIED-BIN.
- **(added) Localization:** the 5.x release notes ship in 13 locales (de, en, es, fr, it, ja, ko, nl, pl, pt-BR, tr, uk, zh-Hans). Apart from MacPaw's separate `zh` edition (`cleanmymac-zh` cask), that is a good proxy for the app's UI languages. VERIFIED (appcast `releaseNotesLink xml:lang` values) → INFERRED for the UI.
- **CleanMyMac 5:** a new codebase with "3D animated interface," redesigned Menu, Apple-Intelligence "Smart Insights" (Apple-Silicon + Tahoe). MacPaw's current public Swift work (CocoaSprings spring-physics animation package; SwiftUI) suggests the 5.x UI uses modern Swift/SwiftUI + custom animation (CocoaSprings is literally "interactive spring animations for macOS," matching the app's physics-y motion). INFERRED + VERIFIED (CocoaSprings README, fetched).
- MacPaw reusable pieces relevant to us (all MIT/public): **`PermissionsKit`** (FDA), **`CocoaSprings`** (animations), **`XADMaster`/`unar`** (archive handling — note CVE-2024-22405/CVE-2023-46270 quarantine-attribute bugs, a reminder to set `com.apple.quarantine` correctly if we ever unarchive), **`FMPFeedbackForm`** (feedback UI), **`Fixel`** (their font — do **not** use; pick our own). VERIFIED (repo list, fetched).

**For our clone:** **Swift 5.9+/6, SwiftUI** (NavigationSplitView sidebar), AppKit bridges where needed (NSWorkspace, menu-bar `NSStatusItem` or SwiftUI `MenuBarExtra`), Combine/async-await, `fts`/`getattrlistbulk` via a small C shim, SQLite (GRDB or raw) for history + knowledge base. INFERRED.

---

## 11. Recommended architecture for our clone (concrete)

### 11.1 Process map (our own reverse-DNS prefix, e.g. `com.<you>.<App>`)

| Our process | Role | Registration |
|---|---|---|
| `com.<you>.App` (main) | SwiftUI app, sidebar modules | — |
| `com.<you>.App.Menu` | menu-bar `LSUIElement` agent | `SMAppService.loginItem(identifier:)` or `MenuBarExtra` in main app |
| `com.<you>.App.HealthMonitor` | background metrics + optional realtime watch | `SMAppService.agent(plistName:)`, plist in `Contents/Library/LaunchAgents` |
| `com.<you>.App.Helper` | **root** file/maintenance helper | `SMAppService.daemon(plistName:)`, plist in `Contents/Library/LaunchDaemons` |
| (optional) `com.<you>.App.FinderSync` | right-click "Clean/Uninstall" | FinderSync `.appex` |
| App Group `group.com.<you>.App` | shared settings / ignore list / history / KB | entitlement on all targets |

### 11.2 Helper via SMAppService + hardened XPC (VERIFIED-APPLE, fetched Apple docs)

- **Install:** `let d = SMAppService.daemon(plistName: "com.<you>.App.Helper.plist"); try d.register()`. **(corrected wording)** `register()` *registers* the daemon, but "the system won't bootstrap the LaunchDaemon until an admin approves" it in System Settings › Login Items. Once approved, it is bootstrapped on every boot. Meanwhile `d.status == .requiresApproval`. The same status comes back if the user later revokes consent. In that case call `SMAppService.openSystemSettingsLoginItems()` and show guidance. `register()` throws `kSMErrorAlreadyRegistered` if already registered and `kSMErrorLaunchDeniedByUser` if the user denied it. VERIFIED-APPLE (`register()`, `Status.requiresApproval`, `openSystemSettingsLoginItems()` JSON, re-fetched).
- The daemon plist needs only `Label`, `BundleProgram` (path **relative to the bundle**, e.g. `Contents/MacOS/<Helper>` — replaces the legacy absolute `Program`), and `MachServices` = your Mach-service name. VERIFIED-APPLE (migration guide: "replace `Program` with `BundleProgram`").
- **Connect:**
  ```swift
  let c = NSXPCConnection(machServiceName: "com.<you>.App.Helper", options: .privileged)
  c.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
  c.setCodeSigningRequirement(
    "identifier \"com.<you>.App.Helper\" and anchor apple generic and certificate leaf[subject.OU] = \"<YOURTEAMID>\"")
  c.resume()
  ```
  `setCodeSigningRequirement(_:)` (macOS 13+) must be called **before `resume()`/`activate()`** (calling it twice is an XPC error). It enforces the *peer's* signature, and mismatched messages invalidate the connection. A malformed requirement string traps in Swift. VERIFIED-APPLE (re-fetched). **(added)** The `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"` form only works with an Apple-issued certificate (Developer ID or Apple Development). For a self-signed personal build use the `certificate leaf = H"…"` form in §11.6.
- **On the helper side** (corrected: two distinct APIs, both macOS 13+):
  - (a) the **listener-level** `NSXPCListener.setConnectionCodeSigningRequirement(_:)` ("sets the code signing requirement for connections to this listener"), called once on the `NSXPCListener(machServiceName:)` before `resume()`; or
  - (b) inside `listener(_:shouldAcceptNewConnection:)`, call **`newConnection.setCodeSigningRequirement(_:)`** before `newConnection.resume()`. That is the per-connection method; Apple's sample uses it this way.

  Either way, the requirement names *our main app*. Messages that don't match invalidate the connection (`NSXPCConnectionCodeSigningRequirementFailure`). Calling either more than once is an XPC error. VERIFIED-APPLE (both JSON pages re-fetched). This is the single control whose absence caused the 2018 CVEs.
- **Belt-and-suspenders (INFERRED; pre-13 or defence in depth):** validate the peer's **audit token**: token → `SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: tokenData], …)` → `SecCodeCheckValidity(code, [.strictValidate, .checkAllArchitectures], ourRequirement)`. `kSecGuestAttributeAudit` is public (VERIFIED-APPLE). **(corrected)** **`NSXPCConnection` has no public `auditToken` property.** Its public identity properties are `processIdentifier`, `effectiveUserIdentifier`, `effectiveGroupIdentifier` and `auditSessionIdentifier` (VERIFIED-APPLE: `NSXPCConnection` topic list). The audit token is reachable only through private SPI: KVC `valueForKey:@"auditToken"` or `xpc_connection_get_audit_token`. On our macOS 14+ target, use the public `setCodeSigningRequirement` APIs and skip the SPI. Never trust the PID alone (PIDs are reused, a TOCTOU race).

### 11.3 Safe helper API (do NOT repeat MacPaw's 2018 mistake)

- **No generic `removeItemAtPath:`.** Expose **intent-level verbs** whose paths the helper **re-derives and re-validates** against the signed knowledge base + a hard blocklist, e.g. `cleanSystemCaches(itemIDs:)`, `cleanSystemLogs(olderThan:)`, `flushDNS()`, `removeBrokenLoginItems(ids:)`, `thinUniversalBinaries(bundleIDs:)`. The client sends **IDs**, not paths.
- For each path: resolve symlinks, reject anything under `/System`, `/System/Library`, SIP-protected trees, `/`, the user's Keychains/CloudDocs; `lstat` and re-check **immediately before** `unlink` (close the TOCTOU window the way CleanMyMac did not); refuse to follow symlinks out of the allowed roots.
- Log every privileged action (our own log in `/Library/Logs/com.<you>.App/helper.log`).
- Version-pin: on every app update, re-`register()` and refuse connections from an app whose version ≠ the helper's expected version (prevents the CVE-2019-5011 "stale helper" class).

### 11.4 Simpler alternative for a personal Mac (INFERRED, recommended first)

For a single personal Mac mini you do **not** need a persistent root daemon. Two lighter options:

1. **No root at all.** Restrict cleanup to user-domain paths (`~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, Xcode DerivedData, dev caches, Downloads clutter, browser privacy traces). This covers the large majority of reclaimable space and needs only **Full Disk Access**, no admin. This is what the MacPaw **CLI** does for most commands (`optimize ram` explicitly "no sudo required"). VERIFIED (cleanmymac-cli).
2. **Occasional admin via AppleScript** for the few root tasks (system caches/logs, DNS flush): `NSAppleScript("do shell script \"…\" with administrator privileges")`. One Touch-ID/password prompt per batch, no installed daemon, nothing left on disk to attack. Downside: coarse (whole shell runs as root — so **build the command from constants, never interpolate user/scan-derived paths**), and the prompt recurs. Acceptable for personal use; **not** acceptable for a distributed product.

Default recommendation: ship **(1)** as the baseline, add the **§11.2 hardened SMAppService daemon** only for the system-domain tasks, and keep **(2)** as the no-daemon fallback.

### 11.5 Login item for the main app / menu agent

- Launch-at-login for the main app: `SMAppService.mainApp.register()` / `.unregister()`. VERIFIED-APPLE.
- Menu-bar agent: either SwiftUI `MenuBarExtra` inside the main app (simplest), or a separate `LSUIElement` login-item app via `SMAppService.loginItem(identifier:)`. The Health agent (if separate) via `SMAppService.agent(plistName:)`. Detect disabled state with `.status`; for legacy plists use `statusForLegacyPlist(at:)`. VERIFIED-APPLE.

### 11.6 SwiftPM layout & building an .app without Xcode GUI (INFERRED)

- A SwiftUI app can be built from SwiftPM via an executable target, but bundling `.app` + `Info.plist` + helper + entitlements is easiest with a **tiny `xcodebuild` project** or a **Makefile** that: compiles each target with `swiftc`/`xcrun`, assembles `Foo.app/Contents/{MacOS,Resources,Library/LaunchDaemons,Library/LoginItems}`, writes `Info.plist`s, then signs.
- **Ad-hoc signing for personal use:** `codesign -s - --force --options runtime --entitlements App.entitlements Foo.app` (and each nested helper/agent, inner-most first). Ad-hoc (`-s -`) means **no notarization**; Gatekeeper will require a right-click-Open once, and FDA/TCC will attach to the ad-hoc cdhash (resets if you rebuild with a different hash — keep a stable signing identity if you can, even a self-signed cert, so TCC grants persist). **(corrected)** Ad-hoc-signed code has no certificate chain, so it can **never satisfy `anchor apple generic`** or any `certificate leaf[...]` clause. A requirement for ad-hoc code can only pin a `cdhash H"…"`, which changes on every rebuild, or use `identifier "…"` alone, which any process can claim: insecure. Recommended for a personal build: create a **self-signed code-signing certificate** (Keychain Access › Certificate Assistant › Create a Certificate, type "Code Signing") and sign every target with it. XPC requirements can then be `identifier "com.<you>.App" and certificate leaf = H"<SHA-1 of your cert>"`, and TCC/FDA grants persist across rebuilds. INFERRED (code-signing requirement language semantics; not tested on-device here). Whether `SMAppService.daemon` accepts a daemon signed with a self-signed (non-Apple) identity is **unverified**. If it refuses, fall back to the §11.4 AppleScript route or a Developer ID certificate.
- CI: GitHub Actions `macos-14`/`macos-15` runner, `xcodebuild -scheme … -destination 'platform=macOS'` or `swift build`, then the packaging script. (Track for CI setup is separate.)

---

## 12. Safety rules distilled (for the whole team)

VERIFIED (Talos) + VERIFIED (cleanmymac-cli Safety & Privacy wiki, fetched) + INFERRED:

1. **Per-connection code-signing check on the helper** (the one thing MacPaw missed in 2018). Use the listener's `setConnectionCodeSigningRequirement` or each connection's `setCodeSigningRequirement` (macOS 13+, public). (corrected: the audit-token path needs private SPI; optional only.)
2. **Intent verbs, never arbitrary-path primitives.** IDs in, helper re-derives paths.
3. **Signed, read-only knowledge base**; never execute from it; verify signature before load.
4. **Hard blocklist** of never-touch trees; resolve symlinks; re-check at delete time.
5. **Default-safe selections:** preselect only clearly-removable items; leave recent/ambiguous unchecked (CLI preselects project artifacts **>7 days**, leaves newer unchecked — adopt this). VERIFIED.
6. **Review before delete, explicit confirm, ignore list** (CLI: `ignore add/list/remove`). VERIFIED.
7. **No telemetry; local-only history.**
8. **Clean uninstall of our own footprint** (mirror the cask `zap` list under our IDs) so we don't become the thing a cleaner flags.
9. **Set `com.apple.quarantine` correctly** if we ever unarchive (XADMaster CVEs).
10. **Replace the helper on every app version** and refuse version-mismatched clients (CVE-2019-5011).

---

## 13. Open gaps / to verify on-device

- ~~Whether CMM **5.x** installs the Agent via legacy `SMJobBless` or `SMAppService.daemon`.~~ **(updated by fact-check)** Now **INFERRED-HIGH: SMJobBless.** The evidence: the SMJobBless-shaped plist, the helper at `Contents/Library/LaunchServices/`, and third-party tooling that edits `SMPrivilegedExecutables` (§3.1). A byte-level confirmation still needs the 5.x bundle, which we did not download: its hosts are proxy-blocked.
- Exact 5.x XPC protocol method names. We have the **CMM3** set, which is the right shape. 5.x is a rewrite and may differ, but the capabilities are the same. **Still open**; no public 5.x Agent strings or advisories were found by GitHub code search.
- Exact 5.x knowledge-base format. **(corrected)** CMM3 is a **SQLCipher-encrypted SQLite DB via FMDB**, updated through a separate **DSA-signed Sparkle channel**; the earlier "RSA-verified" wording was wrong. 5.x is unconfirmed. The CLI shares "cleanup rules" with the app, which points to a standalone rules component.
- Precise Moonlock Endpoint-Security event subscriptions: **still open, and now it is also unresolved whether CMM5 ships the ES sysext at all** (§2.1). The ES event catalog (header-verified, with first macOS version) covers what a realtime monitor would subscribe to:
  - `NOTIFY_XP_MALWARE_DETECTED/REMEDIATED` (13.0);
  - `NOTIFY_BTM_LAUNCH_ITEM_ADD/REMOVE` (13.0);
  - `NOTIFY_GATEKEEPER_USER_OVERRIDE` (15.0);
  - `NOTIFY_TCC_MODIFY` (15.4).

  ES needs the `com.apple.developer.endpoint-security.client` entitlement, which requires an Apple-issued provisioning profile → **out of scope for a personal build**. Use a lighter FSEvents/`NSMetadataQuery`-based "new app installed / new launch item" watch instead.
- `macpaw.com` KB pages (`cleanmymac-agent`, `cleanmymac-helper-tool`) and the live `updates.cleanmymac.com` appcast: **still blocked** in the fact-check (WebFetch: DNS failure; curl: proxy 403), and the WebSearch budget was exhausted. A follow-up run with these hosts allowed should capture the exact current wording.
- **(added) On-device checks that settle the remaining gaps** (read-only, on a Mac with CleanMyMac 5 installed; replace the path if it was installed via Homebrew as `/Applications/CleanMyMac.app`):
  ```sh
  A="/Applications/CleanMyMac_5.app"
  plutil -p "$A/Contents/Info.plist" | grep -A3 SMPrivilegedExecutables   # present ⇒ SMJobBless
  ls "$A/Contents/Library/LaunchServices" "$A/Contents/Library/LaunchDaemons" "$A/Contents/Library/LoginItems" 2>&1
  sudo sfltool dumpbtm | grep -B3 -A14 -i macpaw    # Agent typed "legacy daemon" ⇒ SMJobBless; "daemon" ⇒ SMAppService
  launchctl print system/com.macpaw.CleanMyMac5.Agent | head -40
  systemextensionsctl list | grep -i macpaw          # is the Moonlock ES sysext installed by CMM5?
  codesign -d --entitlements - --xml "$A" | plutil -p -
  otool -L "$A/Contents/MacOS/CleanMyMac_5" | grep -iE 'swift|sparkle|sqlcipher'
  strings - /Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent | grep -E 'WithReply:|withReply:' | sort -u   # 5.x XPC verbs
  ls "$A/Contents/Resources" | grep -iE 'kb|knowledge|safety|\.db|\.sqlite|\.pem'   # 5.x KB files
  ```
  The `legacy daemon` vs `daemon` reading of `dumpbtm` is INFERRED from BTM type naming. The same `jinrenjie/blog` dump lists Microsoft AutoUpdate's plist in `/Library/LaunchAgents` as `Type: curated legacy agent (0x90008)`, which suggests a legacy flag of `0x10000` on top of agent `0x8` / daemon `0x10`.

---

## 14. Sources (this track)

Fetched this session (primary / near-primary):
- Homebrew casks: `raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb`, `.../cleanmymac-zh.rb`; `raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb`
- CVE JSON: `raw.githubusercontent.com/CVEProject/cvelistV5/main/cves/2018/4xxx/CVE-2018-4032…4047.json`, `.../2019/5xxx/CVE-2019-5011.json`
- Talos blog (archived): `raw.githubusercontent.com/EFI-Demo/Endpoint-Forecasting-and-Interpreting/.../Vulnerability Spotlight … CleanMyMac X.txt` (→ `talosintelligence.com/vulnerability_reports/TALOS-2018-0705…0721`, `TALOS-2019-0759`)
- 0day.today CMM3 LPE advisory (archived): `raw.githubusercontent.com/fullhunt/0day-today-archive/.../data/30785.txt`
- MacPaw CMM3 bundle (binaries & plists): `raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac 3.app/Contents/...` (main binary, `Library/LaunchServices/com.macpaw.CleanMyMac3.Agent`, `Resources/info.cmmkb`, `Resources/KnowledgeBase.pem`, Info.plists for app/Menu/Scheduler/LipoService/IconsService/StorageManagement.appex)
- CMM5 Agent launchd plist: `raw.githubusercontent.com/MYunFeiYang/zbookpowerg7/.../com.macpaw.CleanMyMac5.Agent.plist`
- Provisioning profiles (decoded): `raw.githubusercontent.com/eliekh05/provision-files/HEAD/profiles/CleanMyMac_5_{HealthMonitor,Menu,FinderSyncExtension}.provisionprofile`
- MacPaw `PermissionsKit` FDA source: `raw.githubusercontent.com/MacPaw/PermissionsKit/master/PermissionsKit/Private/FullDiskAccess/MPFullDiskAccessAuthorizer.m` + README
- MacPaw `cleanmymac-cli` README + wiki (Safety-and-Privacy, FAQ, Commands): `github.com/MacPaw/cleanmymac-cli`
- CMM X Info.plist (`SMPrivilegedExecutables`): `raw.githubusercontent.com/Zfinix/zos/.../apps/CleanMyMac X.app.json`
- `SMAuthorizedClients`/`SMPrivilegedExecutables` checker + patch note: `raw.githubusercontent.com/YuXilong/YuXilong.GitHub.io/.../2022-06-04-…LaunchServices…Patch.md`
- `sfltool dumpbtm` of CMM X: `raw.githubusercontent.com/jinrenjie/blog/.../content/technology/20230428.en.md`
- tccd string diff (built-in MacPaw allow entries): `raw.githubusercontent.com/blacktop/ipsw-diffs/.../tccd.md`
- Fleet uninstall script; IntuneBrew uninstall; `earthinversion/Mac-apps-self-manage` (component list)
- InjectLib configs (component/helper layout, Sparkle inject target): `zixing131/QiuChenly-InjectLib`, `kingzynj/InjectLib`
- nix-darwin launchd labels; `starlink-awaken/omostation` (Updater classed external); `MichelKerkmeester/…` audit (Updater 21600 s)
- Process/netstat capture incl. Moonlock system extension path: `TaliskerMan/Monitro`, `OpenAgentsInc/openagents`
- `system_profiler` app list (versions/signing): `satemorej/jts-photo`
- CacheDelete unified-log evidence: `pabloguia/XCodeVault`
- Apple developer docs JSON (fetched): `developer.apple.com/tutorials/data/documentation/servicemanagement/smappservice(+daemon/agent/loginitem/mainApp/register/status/statusForLegacyPlist/openSystemSettingsLoginItems).json`, `.../foundation/nsxpcconnection/setcodesigningrequirement(_:).json`, `.../nsxpclistener/setconnectioncodesigningrequirement(_:).json`, `.../smjobbless(_:_:_:_:).json`, `.../updating-helper-executables-from-earlier-versions-of-macos.json`, `.../smloginitemsetenabled(_:_:).json`
- MacPaw repo list / `CocoaSprings` README (Swift/animation stack): `github.com/MacPaw` (search, fetched)

Added by the fact-check pass (all fetched 2026-10-12):
- Legacy CMM5 Sparkle appcast (DevMate S3, path-style): `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml`
- CMM5 cumulative release notes (5.0.4→5.2.5, incl. 5.0.5 "Free Up Purgeable Space"): `https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html` (fetched by track 01; re-read here)
- Sparkle 2 source: `https://raw.githubusercontent.com/sparkle-project/Sparkle/2.x/Sparkle/SUUpdateValidator.m`; `Configurations/ConfigFramework.xcconfig` (`FRAMEWORK_VERSION = B`); docs `sparkle-project.github.io/documentation/index.md` and `/customization/index.md`
- InjectLib config + helper handling: `https://raw.githubusercontent.com/zixing131/QiuChenly-InjectLib/HEAD/config.json`, `https://raw.githubusercontent.com/kingzynj/InjectLib/HEAD/main.py`
- Apple doc JSON: `servicemanagement/smjobbless(_:_:_:_:)`, `servicemanagement/smappservice/daemon(plistname:)`, `servicemanagement/smappservice/register()`, `servicemanagement/smappservice/status-swift.enum/requiresapproval`, `foundation/nsxpcconnection` (topic list), `foundation/nsxpcconnection/setcodesigningrequirement(_:)`, `foundation/nsxpclistener/setconnectioncodesigningrequirement(_:)`, `security/ksecguestattributeaudit`, `servicemanagement/updating-helper-executables-from-earlier-versions-of-macos` (all under `developer.apple.com/tutorials/data/documentation/…json`)
- EndpointSecurity `ESTypes.h` (MacOSX26.5 SDK mirror `alexey-lysiuk/macos-sdk`, fetched by track 04; event-version comments re-read)
- Talos posts (archived): `EFI-Demo/Endpoint-Forecasting-and-Interpreting` `CTIs/talosintelligence/talosintelligence/2019/Vulnerability Spotlight Multiple privilege escalation vulnerabilities in CleanMyMac X.txt` and `… Privilege escalation bug in CleanMyMac X's helper service.txt`
- CMM X 4.0.0 Info.plist JSON: `https://raw.githubusercontent.com/Zfinix/zos/HEAD/apps/CleanMyMac%20X.app.json`
- Process captures: `TaliskerMan/Monitro` `backend/out.txt`; `OpenAgentsInc/openagents` `docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-before.txt`
- EtreCheck sample (MAS layout): `dmdgolf/etrecheck-analyzer` `data/sample_report.txt`
- Leftover scan (FinderSync container, helper size): `earthinversion/Mac-apps-self-manage` README
- Group-container log paths: `andreychev/dotfiles` `.config/mole/operations.log` (GitHub code search hit)
- launchd domains: `fpcMotif/nix-darwin` `modules/darwin/background-services.nix`
- Setapp Updater plist: `droxey/dotfiles` `.macprefs/StartupItems/LaunchAgents/User/com.macpaw.CleanMyMac-setapp.Updater.plist`
- Bluetooth TCC attribution: `LunaParker/macos-permission-report` `generate_report.py`
- FDA deep-link variants: `lobehub/lobehub` `apps/desktop/src/main/utils/permissions.ts`
- Signing identity strings: `chainguard-dev/osquery-defense-kit` `detection/persistence/2-unexpected-uid0-daemon-macos.sql`
- Moonlock standalone DMG location: `opengood-ai/env-setup` `packages/moonlock.sh`
- CLI cask: `https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb`

---

## Verification notes

Adversarial fact-check of this track, 2026-10-12. Constraints:
- The shared WebSearch budget was already exhausted, so no new web searches could run.
- `macpaw.com`, `updates.cleanmymac.com`, `dl.devmate.com`, `updates.devmate.com` and `updateinfo.devmate.com` were unreachable (WebFetch DNS failure / proxy 403).

Verification therefore used primary artifacts fetched directly:
- Homebrew and MacPaw casks, Apple developer-doc JSON, CVE JSON, archived Talos posts;
- the CMM3 binaries, re-analysed with `strings`, `openssl asn1parse` and byte statistics;
- PermissionsKit and Sparkle source, a legacy 5.x Sparkle appcast, and GitHub code search.

One disclosure: the legacy appcast was read through the allowed path-style S3 host (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/…`). Its vanity hostname is proxy-blocked. On the same reasoning, the fact-checker deliberately did **not** download the 194 MB 5.x app zip through S3, since that would route around the explicit `dl.devmate.com` block. Byte-level 5.x checks are left to the on-device commands in §13.

### Claims checked (most implementation-critical first)

| # | Claim | Result |
|---|---|---|
| 1 | 5.x bundle IDs, paths, zap list, helper path, Updater plist (cask) | **Confirmed** (cask re-fetched; version 5.7.1, build 50701.0.2609301754). Main-app naming nuance **corrected**: on disk `CleanMyMac_5.app`, Homebrew renames it to `CleanMyMac.app` |
| 2 | 5.x Agent plist contents (Label/MachServices/Program/ProgramArguments) | **Confirmed** (raw plist re-fetched) |
| 3 | 5.x helper install method | **Upgraded** from "likely" to **INFERRED-HIGH: SMJobBless** (Apple's SMJobBless plist semantics; InjectLib shows the helper in `Contents/Library/LaunchServices/`; InjectLib rewrites `SMPrivilegedExecutables`) |
| 4 | CMM3/X `SMJobBless` + `SMAuthorizedClients`/`SMPrivilegedExecutables` strings, Unix socket `/var/run/…socket` 0666 | **Confirmed** (Agent `strings`; X 4.0 Info.plist JSON) |
| 5 | XPC selector list | **Confirmed**, with fixes: DNS-flush string `udnsflushcaches` and the `discoveryutil` path; `slimBinaryWithPath:archs:withReply:` is the XPC verb; no `lipo` in the Agent. **Added**: `log erase --all`, `SystemStarter`, `DYLD_INSERT_LIBRARIES` launchd.conf scrubbing, `com.apple.rootless` check, immutable-flag clearing |
| 6 | "Helper links `CCCrypt`" | **Corrected**: the Agent imports `CC_MD5` and Sec transforms; `CCCrypt` is in the main app |
| 7 | CVE table, CVSS, dates | **Confirmed** mapping (Talos headings) and CVSS. **Corrected**: CVE-2019-5011 is CWE-459, affects 4.20, published 2019-03-21; the 0day.today advisory is 2018-07-27, about 6 months (not a year) earlier; the "2018-12" fix date is unsourced → INFERRED |
| 8 | PermissionsKit FDA probe file list + deep link | **Confirmed** from source. **Corrected** the exec-summary path: user `~/Library/Application Support/com.apple.TCC/TCC.db`, not `/Library/…`. **Added** the macOS 13+ `com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles` variant |
| 9 | KB = RSA-verified, CCCrypt AES-decrypted SQLite | **Corrected (major)**: `info.cmmkb` is **SQLCipher** (1.x-compatible settings: `kdf_iter 4000`, no HMAC, 1024-byte pages; the file is exactly 425 pages). `KnowledgeBase.pem` is **DSA-1024**, used as `SUPublicDSAKeyFile` for a **second Sparkle updater** (`_kbUpdater`, `CMMKB-<ver>.zip`). The RSA/AES strings belong to DevMate **Kevlar licensing** |
| 10 | 5.x uses Sparkle 2; appcast URL; 6-hour Updater | **Confirmed**: `Versions/B` = Sparkle 2 (Sparkle xcconfig); appcast URL per the cask; 21,600 s per audit + Setapp plist. **Added**: the legacy DevMate feed (5.0.0–5.3.1, deltas, 13 locales, min macOS 11, **no EdDSA signatures** → Apple-code-signing validation path, per Sparkle source) |
| 11 | "Min macOS 11, up to macOS 27" | min 11 **confirmed** via appcast + CLI cask. "Up to 27" and the cask minimum **not supported** (cask has bare `depends_on :macos`) → INFERRED |
| 12 | 5.x ships a Moonlock ES system extension | **Downgraded to INFERRED / unresolved**: present beside CMM5 in one capture, absent in another; may be the standalone Moonlock app |
| 13 | Moonlock uses `kTCCServiceBluetoothAlways` | **Corrected**: the source attributes it to `com.macpaw.CleanMyMac5` (the app) |
| 14 | HealthMonitor "drives CacheDelete" | **Corrected**: the log shows CacheDelete *client queries* identical to another monitoring app's; no purge evidenced |
| 15 | ES event names / versions | **Confirmed** against `ESTypes.h`: XP_MALWARE_* and BTM_* in 13.0, GATEKEEPER_USER_OVERRIDE in 15.0, TCC_MODIFY in 15.4 |
| 16 | `setCodeSigningRequirement` / `setConnectionCodeSigningRequirement` usage | **Confirmed** macOS 13+, before `resume()`, single call. **Corrected**: the listener method is listener-level; per-connection is `newConnection.setCodeSigningRequirement`. **`NSXPCConnection.auditToken` is not public API** |
| 17 | `SMAppService.daemon` approval semantics; `AssociatedBundleIdentifiers` | **Confirmed** approval/bootstrap behaviour. **Corrected**: in-bundle agents/daemons associate automatically; `AssociatedBundleIdentifiers` is for legacy plists |
| 18 | Ad-hoc signing with `anchor apple generic` | **Corrected**: ad-hoc code cannot satisfy it; recommend a self-signed code-signing cert. `SMAppService` acceptance of self-signed daemons is unverified |
| 19 | Telemetry hosts | `api-lytics.macpaw.com` **confirmed** in the CMM3 binary. `cmd-cdn` KB role → INFERRED. The Surge lists are CDN routing lists, not block lists. Google Analytics **not** in the CMM3 binary (corrected). CLI "on by default" → INFERRED |
| 20 | Logs location | **Corrected/added**: per-process logs live in the App Group container `…/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5/Library/Logs/` |

### Gaps the researcher reported: status after the fact-check

1. **SMJobBless vs SMAppService for 5.x:** largely answered (INFERRED-HIGH SMJobBless, three independent signals). Byte confirmation is pending the §13 on-device commands.
2. **5.x XPC method names:** still open. No public 5.x Agent strings or advisories turned up in GitHub code search. No 5.x CVE was found in the CVE corpus fetched (only 2018/2019 CleanMyMac entries; other MacPaw CVEs concern Encrypto and XADMaster/The Unarchiver).
3. **5.x Safety-Database format:** still open for 5.x. The CMM3 baseline is now **correctly** characterized (SQLCipher + DSA-signed Sparkle KB channel). The CLI confirms that rules are shared with the app.
4. **Moonlock ES subscriptions:** still open. Whether CMM5 installs the sysext at all is also open. A personal build cannot use ES anyway (restricted entitlement).
5. **Live KB pages / live 5.x appcast:** still blocked. Partly offset by the legacy DevMate appcast and the cumulative release notes.

### Added coverage (previously missing)

- Edition layouts: Setapp helper and Menu names; MAS modern login items, no daemon.
- launchd domains for each job, and a "what runs when" table (§2.4).
- The FinderSync extension is sandboxed.
- CMM X Info.plist keys: Sparkle auto-checks disabled, TCC usage strings, catch-all document type.
- Safety behaviours in the CMM3 Agent.
- The KB update channel design.
- Sparkle validation semantics without EdDSA.
- macOS-14+ obsolescence of several legacy maintenance verbs (cross-referenced with track 05).

### Remaining uncertainty (treat as INFERRED until checked on-device)

- The 5.x KB file format and its update channel.
- 5.x XPC verbs and how the 5.x helper validates clients.
- Whether CMM5's current `updates.cleanmymac.com` feed carries EdDSA signatures.
- Whether CMM5 installs the Moonlock ES sysext.
- Whether the SMJobBless Agent appears under "Allow in the Background" on macOS 14/15/26 (Apple's guide implies yes; MacPaw's KB reportedly says no).
- Whether `SMAppService.daemon` works with a self-signed (non-Apple) code-signing identity for our personal build.
