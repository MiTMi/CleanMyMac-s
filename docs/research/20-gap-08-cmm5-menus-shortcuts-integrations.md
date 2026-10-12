# 20-gap-08 — CleanMyMac 5.x commands and system integration points

Covers: the main menu bar and keyboard shortcuts; the Dock menu; result-list context menus; Finder integration (Finder Sync extension, Services); the URL scheme; Shortcuts, widgets and Control Center; the trash-monitor "uninstall completely" prompt; drag-and-drop targets; in-app Help and the About window.

> **Our app:** code name *Spruce* (placeholder until the final name is cleared, 12 §5.1), design system *Prism*. The module names follow `docs/ARCHITECTURE.md`: Checkup, Cleanup, Protection, Performance, Applications, Clutter, Space Map, Cloud Storage, Toolbox, Activity, plus the Monitor (menu bar). The URL scheme is written `spruce://` throughout; rename it with the product. Vendor labels are quoted only to show structure. Nothing here is to be shipped verbatim.

Date: 2026-10-12. Author: gap-fill pass 08.

---

## 0. Method, reachability and labels

### 0.1 What could be reached in this pass

| Channel | Result |
|---|---|
| WebSearch | **Budget exhausted** before this pass began (shared 200-search limit). No searches were possible. |
| WebFetch / curl to macpaw.com, apps.apple.com, setapp.com | **Failed** (`getaddrinfo ENOTFOUND`). `updates.cleanmymac.com` (the 5.4+ Sparkle feed) → proxy 403. |
| GitHub code search (MCP) and `raw.githubusercontent.com` | **Reachable.** This was the main source: the committed CleanMyMac 3.9 bundle (nibs, strings, Info.plists, binaries), the CleanMyMac X 4.0.0 Info.plist, process captures, an EtreCheck report, Alfred workflows, dotfiles. |
| DevMate S3 release notes (`s3-us-west-2.amazonaws.com/updateinfo.devmate.com/...`) | **Reachable.** All 32 X per-version pages (4.0.0–4.6.10), the X cumulative page to 4.15.14 and the 5.x cumulative page to 5.3.1 were fetched and grepped. |
| `developer.apple.com/tutorials/data/documentation/*.json` | **Reachable.** Finder Sync, App Intents, ControlWidget, NSApplicationDelegate and NSHelpManager pages were fetched. |
| YouTube walkthroughs, review sites, MacPaw KB | Not reachable. KB facts below come from earlier reports that fetched them (cited by section). |

**Bottom line.** No reachable source documents the 5.x menu bar, its shortcuts, or what the 5.x Finder Sync extension adds. The best exact evidence is the **CleanMyMac 3.9 bundle**: its compiled `MainMenu.nib` was parsed this pass, giving every menu item, key equivalent and selector. CleanMyMac X adds a few dated deltas (Services, Help-menu feedback form, drag-and-drop fixes). 5.x adds verified anchors (Activate menu, Settings ⌘,, Start Over, Control-click → Add to Ignore List, the Finder Sync bundle, the Health-Monitor trash prompt, the `cleanmymac5://` module links). Section 12 lists the commands that settle the rest in ten minutes on a Mac with CleanMyMac 5 installed.

### 0.2 Labels

| Label | Meaning |
|---|---|
| **VERIFIED-BIN** | Read this pass from a shipped vendor bundle file: a compiled nib parsed with `plistlib`, a `.strings` file, an `Info.plist`, or `strings` output of a shipped Mach-O. URL given. |
| **VERIFIED-PLIST** | A shipped `Info.plist` published as JSON by a third party (CleanMyMac X 4.0.0). |
| **VERIFIED-DM** | MacPaw's own release notes on DevMate S3, fetched this pass. |
| **VERIFIED-KB (via NN §x)** | MacPaw KB text recorded by an earlier report (NN), not re-fetchable here. |
| **VERIFIED-OSS** | A public third-party file that records shipped behaviour (process capture, EtreCheck report, dotfile, workflow). |
| **VERIFIED-APPLE** | Apple developer documentation JSON fetched this pass. |
| **INFERRED** | Our reasoning or our design. Never ship as "the vendor does X". |

---

## 1. Executive summary

1. **CleanMyMac 3.9's menu bar is now known exactly** (VERIFIED-BIN, §2.1). Six standard menus (app, File, Edit, View, Window, Help) plus three app-specific ones: **Go** (Back ⌘[, Dashboard ⌘D, modules ⌘1–⌘6), **Action** (Scan ↩, Rescan ⌘R, Authenticate…) and **Activate** (licensing, tag 666). The **File** menu doubles as the result-row menu: Select (Space), Launch (⌘↓), Quick Look (⌘Y), Reveal in Finder (⇧⌘R), Add to / Remove From Ignore List, Add Folder… (⌘O). **View** has Show File Paths. **Window** has Ignore List. **Help** has CleanMyMac Help (⌘?), Support Center…, What's New, More MacPaw Products…, Provide Feedback….
2. **5.x menu bar: only anchors are verified.** "CleanMyMac › Settings…" (⌘,) and "CleanMyMac › Activate" are KB-documented (via 01 §4.2, §10). Everything else is reconstruction (§2.3). The lineage (CMM3 had ⌘1–⌘6 for modules, ⇧⌘R reveal, ⌘Y Quick Look, ↩ Scan) is the best available prior.
3. **Context menus.** Control-click → **Add to Ignore List** is verified for CMM3, X and 5.x. CMM3 also offered Quick Look, Reveal in Finder, Launch, Reveal in Photos, and hover icons (magnifier = reveal, eye = Quick Look). 5.x **Smart Insights** is a per-item button (macOS 26 + Apple Intelligence), not a documented context-menu item (§4).
4. **Services menu history (VERIFIED).**
   - CMM3: six `NSServices`: "Scan for Large and Old Files" (folders), "Clean with CleanMyMac" (volumes), "Erase with CleanMyMac" and "Securely Erase with CleanMyMac" (any item), "Uninstall with CleanMyMac" (app bundles), "Clean iPhoto Library with CleanMyMac". The app itself toggled them in `pbs.plist`.
   - X 4.0.0 shipped **no** `NSServices`. **4.0.2 added a "Services menu for Updater and Uninstaller modules"** (VERIFIED-DM).
   - 5.x: no evidence of Services either way.
5. **5.x Finder Sync extension: the bundle is verified; what it adds is not.**
   - VERIFIED: it exists in the direct edition (`Contents/PlugIns/CleanMyMac_5_FinderSyncExtension.appex`, `com.macpaw.CleanMyMac5.FinderSyncExtension`, sandboxed, App Group). It was **running** in a 2026-09-20 process capture, so it is enabled and Finder loads it.
   - VERIFIED (absence): the **Mac App Store edition (installed 2026-04-04) registers no CleanMyMac Finder Sync, widget, Intents or Share extension** (EtreCheck report).
   - What the extension contributes (context-menu items, toolbar button, badges) is **unknown**. Best inference: Finder context-menu entries that open the app on a target (uninstall an app; analyse or scan a folder), the successor of X's Services (§5.3).
6. **URL schemes (VERIFIED for 3 and X; third-party for 5).**
   - CMM3: `cleanmymac://` with routes `/activate`, `/retrieve_license`, `/blocked_license`, `/reset_activations`, `/upgrade_license`, `/buy_license`, `/subscribe`, `/about`, `/tell_friend`, `/support_center`, plus launch arguments `-cleanTrash`, `-uninstall`, `-scheduledScan`, `-freeSpace`, `-fullScan`, `-openMonitoringSettings`… (VERIFIED-BIN).
   - X: `cleanmymacx://`, described in its plist as a "multipurpose URL: activation etc." (VERIFIED-PLIST).
   - 5.x: `cleanmymac5:///modules/<smartCare|cleanup|protection|performance|applications|myClutter|spaceLens>` opens a module without scanning (single third-party source; INFERRED).
7. **No Shortcuts actions, widgets or Control Center controls are evidenced for 5.x.** The X widget (`…CleanMyMac4.CleanMyMacWidget`) is gone from the 5.x cask. The MAS 5.x EtreCheck report lists none. No release note through 5.3.1, and no What's New entry through 5.7.1, mentions them (§6.5).
8. **The trash-monitor prompt is known exactly for CMM3** (VERIFIED-BIN, §7.1).
   - A custom alert from the Menu app titled "Uninstall applications correctly.", subtitle "Remove trashed applications along with all related leftovers."
   - One row per trashed app: icon, name, related-files count, size.
   - Buttons: **Uninstall Completely** (↩), **View in CleanMyMac**, **Dismiss** (Esc). Dismiss is wired to `ignoreForever:`.
   - It has its own **Progress → Done / Failure** tabs, so the uninstall runs *inside the alert*.
   - In 5.x the **Health Monitor** raises the "uninstall completely?" offer (VERIFIED-KB via 13 §3.23). Its 5.x presentation (macOS notification vs. Menu popover) is unknown.
9. **Drag and drop.**
   - CMM3 and X declare `CFBundleDocumentTypes` "AnyFile" (`*`, role Viewer), so **any file or app can be dropped on the Dock icon** or opened with `open -a` (VERIFIED-BIN/PLIST). Alfred workflows uninstall apps with `open -a "CleanMyMac X" <app>` (VERIFIED-OSS).
   - X fixed "conflicting drag and drop cases during uninstallation" (4.0.2) and a "drag and drop UI issue within Uninstaller" (4.5.3), so the Uninstaller is a drop target (VERIFIED-DM).
   - The CMM3 Shredder accepted drops (VERIFIED-BIN help).
10. **Help and About.**
    - CMM3: a bundled Apple Help Book plus online Support Center. Custom About window: name, version, auto-scrolling credits, an Acknowledgements popover, a "Made in Ukraine" link, a "Try our products:" cross-promo strip.
    - The Menu app uses the standard About panel.
    - X 4.6.9 put a feedback form in the Help menu (VERIFIED-DM).
    - 5.x carries a "Crafted by MacPaw" signature asset for the About/footer (VERIFIED-OSS via 09 §4.2) and ⓘ info popovers on rows (via 20-gap-02).
11. **Spruce build order (INFERRED; §11).**
    - **P0:** menu bar and shortcuts; `spruce://` scheme; Dock menu and Dock drop; `NSServices`. Info.plist and app delegate only.
    - **P1:** trash monitor in the Monitor agent.
    - **P2:** Finder Sync `.appex`.
    - **P3:** App Intents, widget and Control Center control. App Intents metadata needs an Xcode build, not plain `swift build`.

---

## 2. Main menu bar

### 2.1 CleanMyMac 3.9: the exact menu bar (VERIFIED-BIN)

Source: `Base.lproj/MainMenu.nib` (compiled keyed archive, parsed with Python `plistlib`) and `en.lproj/MainMenu.strings`. URLs:
- https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/Base.lproj/MainMenu.nib
- https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/en.lproj/MainMenu.strings

Selectors are the nib's `NSNibControlConnector` labels. The principal class is `CMApp` with delegate `CMApplicationDelegate`. "—" = separator.

| Menu | Item | Key | Selector / notes |
|---|---|---|---|
| **CleanMyMac** | About CleanMyMac | — | `showAboutWindow:` (custom window, §9.2) |
| | Tell a Friend… | — | `tellFriend:` |
| | — | | |
| | Preferences… | ⌘, | `showPreferences:` |
| | — | | |
| | Activate… | ⌘B | `activateApp:` (tag 9999) |
| | License Agreement… | — | `showLicenseAgreement:` |
| | — | | |
| | Check for Updates | — | `checkForUpdates:` (delegate) |
| | What’s New | — | release notes window |
| | — | | |
| | Services ▸ | | standard |
| | — | | |
| | Hide CleanMyMac / Hide Others / Show All | ⌘H / ⌥⌘H / — | standard |
| | — | | |
| | Quit CleanMyMac | ⌘Q | `terminate:` |
| **File** | Add Folder… | ⌘O | `chooseOtherScanLocation:` (adds a scan location) |
| | — | | |
| | Select | Space (no modifier) | `check:` (toggles the focused row's checkbox; tag 3) |
| | Launch | ⌘↓ | `launchAppAction:` (tag 10; apps) |
| | — | | |
| | Quick Look | ⌘Y | `quickLookSelectedItems:` (tag 2) |
| | Reveal in Finder | ⇧⌘R | `revealInFinder:` (tag 1) |
| | Add to Ignore List | — | `addToIgnoreList:` (tag 4) |
| | Remove From Ignore List | — | `removeFromIgnoreList:` (tag 4; shown in place of Add when the item is ignored) |
| | — | | |
| | Close | ⌘W | `performClose:` |
| **Edit** | Undo, Redo, Cut, Copy, Paste, Paste and Match Style, Delete, Select All; Find ▸ (Find… ⌘F → `findAction:`, Find Next ⌘G, Find Previous ⇧⌘G, Use Selection for Find ⌘E, Jump to Selection ⌘J); Spelling and Grammar ▸; Substitutions ▸; Transformations ▸; Speech ▸ | standard | Find… is routed to `CMApp` (`findAction:`), i.e. it focuses the module's search field |
| **View** | Show File Paths | — | `toggleShowFilePaths:` (shows full paths under item names in result lists) |
| | — | | |
| | Enter Full Screen | ⌃⌘F | `toggleFullScreen:` |
| **Go** | Back | ⌘[ | `backAction:` |
| | Dashboard | ⌘D | `toggleDashboard:` |
| | — | | |
| | Smart Cleanup | ⌘1 | `activateModuleBySenderTag:` (tag 1001) |
| | System Junk / iPhoto Junk / Mail Attachments / iTunes Junk / Trash Bins / Large & Old Files | — | tags 1002–1007 (Smart Cleanup's sub-modules, no keys) |
| | — | | |
| | Uninstaller | ⌘2 | tag 1008 |
| | Maintenance | ⌘3 | tag 1009 |
| | Privacy | ⌘4 | tag 1010 |
| | Extensions | ⌘5 | tag 1011 |
| | Shredder | ⌘6 | tag 1012 |
| **Action** | Scan | ↩ (Return, no modifier) | `performMainAction:` (the big round button's action: Scan, then Clean/Remove/Uninstall depending on state) |
| | Rescan | ⌘R | `performRescanAction:` |
| | — | | |
| | Authenticate… | — | `authorizeAction:`. Code-built titles `MenuItemTitle_Authenticate` / `MenuItemTitle_Deauthenticate` suggest it toggles. |
| **Activate** (tag 666; licensing) | Enter Activation Number…, Buy a License, Retrieve License | — | `enterActivationNumberAction:`, `buyLicenseAction:`, `retrieveLicenseAction:` |
| **Window** | Minimize | ⌘M | standard |
| | Zoom | — | standard |
| | — | | |
| | Ignore List | — | `manageIgnoredItems:` (opens Preferences › Ignore List) |
| | — | | |
| | Bring All to Front | — | standard |
| **Help** | CleanMyMac Help | ⌘? | `showHelpAction:` (bundled Help Book) |
| | — | | |
| | Support Center… | — | `visitSupportCenter:` (web) |
| | — | | |
| | What's New in CleanMyMac 3 | — | `showWhatsNewWindow:` |
| | More MacPaw Products... | — | `showMoreAppsAction:` (cross-promo) |
| | Online Manual… | — | **hidden** in the nib |
| | — | | |
| | Provide Feedback… | — | `showFeedbackAction:` |

Code-only menu strings in the main binary (VERIFIED-BIN, `strings` of https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203):
- "Reset CleanMyMac preferences" with "Do you want to reset defaults?" / "To reset CleanMyMac preferences You need to restart the application." / "Restart";
- "Turn Extended Logging On" / "Turn Extended Logging Off";
- "Show Help", "Open Preferences", "Activation from Menu", "Open Activation Menu", "Upgrade at 50% OFF".

INFERRED: the reset and logging items are hidden support items, probably revealed by a modifier key or added only in diagnostics builds.

Design observations (INFERRED):
- **Return is Scan.** The primary round button is the window's default button; Return fires the current primary action.
- **The File menu is the item menu.** The same commands appear in the row context menu (§4.1), so every row action has a menu-bar twin and a shortcut. That is the accessibility pattern to copy.
- **Module switching uses ⌘1…⌘6** for the top-level modules only, never for sub-categories.
- ⇧⌘R for reveal avoids ⌘R (Rescan); ⌘Y (Quick Look) avoids Space, which toggles selection.

### 2.2 CleanMyMac X (2018–2024): verified deltas

| Change | Version | Status |
|---|---|---|
| Main UI moved to a storyboard (`NSMainStoryboardFile = Main`); principal class `CMApplication`. | 4.0.0 | VERIFIED-PLIST (https://raw.githubusercontent.com/Zfinix/zos/HEAD/apps/CleanMyMac%20X.app.json) |
| `CFBundleHelpBookName = com.macpaw.CleanMyMac.help` kept, but **no `CFBundleHelpBookFolder`**. | 4.0.0 | VERIFIED-PLIST. INFERRED: no bundled Help Book; help went online. |
| No `NSServices` key in the plist. | 4.0.0 | VERIFIED-PLIST |
| "Services menu for Updater and Uninstaller modules" added. | 4.0.2 | VERIFIED-DM https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.0.2/releasenotes.html |
| "Context menu items description within the Maintenance module". | 4.4.4–4.5.1 | VERIFIED-DM (…/4.4.4/releasenotes.html) |
| "Quick Look preview by double click within Space Lens". | 4.4.6 | VERIFIED-DM (…/4.4.6/releasenotes.html) |
| "New feedback form in the Help menu". | 4.6.9 | VERIFIED-DM (…/4.6.9/releasenotes.html) |
| "App didn't unfold from the Dock" fixed. | 4.10.x | VERIFIED-DM (cumulative 41514 page) |

X's exact menu titles and shortcuts were **not found** in any reachable source. INFERRED: X kept the CMM3 skeleton, replacing "Smart Cleanup" with "Smart Scan" and the module list with X's (System Junk, Mail Attachments, Trash Bins, Malware Removal, Privacy, Optimization, Maintenance, Uninstaller, Updater, Extensions, Space Lens, Large & Old Files, Shredder).

### 2.3 CleanMyMac 5.x: verified anchors and best reconstruction

**Verified anchors:**

| Fact | Status |
|---|---|
| App menu **CleanMyMac › Activate** opens the activation dialog (trial / Buy / "I already have a license" → MacPaw Account). "Unlock Full Version" at the window's top right does the same. | VERIFIED-KB (via 01 §4.2, §9.1; https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation) |
| Settings open via **CleanMyMac › Settings…** (⌘,). Tabs include General, Scanning, Ignore List, Protection, Menu. | VERIFIED-KB for the tabs (via 01 §10; 20-gap-06 §2). The ⌘, key is the macOS standard and the CMM3 binding. |
| **Start Over** sits at the top left of results screens and asks for confirmation. | VERIFIED-KB (Smart Care KB, via 02 §3, 20-gap-01 §3) |
| **Control-click → Add to Ignore List** on result rows. | VERIFIED-KB (cleanmymac-safety KB, via 20-gap-02 §3, 13 §3.5) |
| The 5.x window has VoiceOver support (5.0.7), so menu items and controls carry accessibility labels. | VERIFIED-DM (5.x cumulative notes) |
| A third-party agent guide reports that the 5.x window "doesn't show up to AppleScript UI scripting". | VERIFIED-OSS (https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md). INFERRED: this concerns the custom-drawn window content. The **menu bar** is still exposed to System Events. |

**Best reconstruction (INFERRED, weak):**
- **CleanMyMac:** About CleanMyMac · Settings… ⌘, · Activate… (only when unlicensed) · Check for Updates… · Services · Hide/Hide Others/Show All · Quit ⌘Q.
- **Edit:** standard (the search fields need Cut/Copy/Paste).
- **View:** Enter Full Screen ⌃⌘F.
- **Window:** standard.
- **Help:** CleanMyMac Help (opens the online KB), a feedback or contact item (X 4.6.9 precedent).
- A Go-style module menu with **⌘1…⌘7** is plausible from the CMM3 precedent, but **unverified**.
- Not supported by any evidence: the "Start Over", "Scan" and "module switching" shortcut keys.

### 2.4 Spruce menu bar spec (INFERRED; original wording)

Implement with SwiftUI `Commands`:
- `CommandGroup(replacing: .appInfo)` for About;
- `CommandGroup(after: .appSettings)` for Check for Updates;
- `CommandMenu("Scan")` and `CommandMenu("Go")`;
- `CommandGroup(replacing: .help)` for Help.

Use `@FocusedValue` / `focusedSceneValue` for the selected rows, so item commands enable and disable correctly. Use `@FocusedValue` for the current module and flow state too.

| Menu | Item | Key | Enabled when / behaviour |
|---|---|---|---|
| **Spruce** | About Spruce | — | custom About window (§9.3) |
| | Settings… | ⌘, | `Settings` scene |
| | Check for Updates… | — | only if update checks are on (personal build: may be hidden) |
| | Services ▸ / Hide / Hide Others / Show All / Quit | standard | — |
| **File** | Add Folder to Scan… | ⌘O | Space Map, Clutter (Large & Old, Duplicates), Shredder; `NSOpenPanel` folders |
| | Open | ⌘↓ | an app row is focused: launch it; a file row: open it with the default app |
| | Quick Look | ⌘Y | one or more file rows selected; in Space Map also Space and double-click (§10) |
| | Reveal in Finder | ⇧⌘R | file or app rows selected (`NSWorkspace.activateFileViewerSelecting`) |
| | Copy Path | ⌥⌘C | file rows selected (Finder's "Copy as Pathname" binding) |
| | Ignore ▸ | — | **Ignore This Item**, **Ignore This Folder**, **Ignore All in Group**. Becomes **Stop Ignoring** for ignored items (Settings view) |
| | Close Window | ⌘W | standard |
| **Edit** | Standard + Find… ⌘F (focus the module search field), Select All ⌘A, **Deselect All ⌥⌘A**, **Select Recommended** ⌥⌘R | | Select/Deselect act on the visible list only |
| **View** | Show Sidebar / Hide Sidebar | ⌃⌘S | SwiftUI `SidebarCommands` |
| | Show File Paths | ⌥⌘P | persists (`ui.showPaths`) |
| | Sort By ▸ Size / Name / Date Modified / Last Opened | — | per list; check-marked |
| | Show Inspector | ⌥⌘I | design 09 §B |
| | Enter Full Screen | ⌃⌘F | standard |
| **Scan** | Scan | ↩ | primary orb is the default button; never fires while a text field has focus |
| | Scan Again | ⌘R | results showing; confirms "Discard these results?" if the user changed the selection |
| | Stop | ⌘. / Esc | while scanning or running; already-finished parts are kept (02 §5) |
| | Run Selected… | ⌘↩ | results with a selection; opens the confirmation sheet, never deletes directly |
| | Back / Start Over | ⌘[ | review → results; on results = Start Over (with confirmation) |
| **Go** | Checkup ⌘1 · Cleanup ⌘2 · Protection ⌘3 · Performance ⌘4 · Applications ⌘5 · Clutter ⌘6 · Space Map ⌘7 · Cloud Storage ⌘8 · Toolbox ⌘9 | ⌘1–⌘9 | sidebar order (09 §B); `AppModel.open(_:)` |
| | Activity | ⇧⌘A | — |
| | Notifications | ⇧⌘N | toggles the bell popover (20-gap-04 §6) |
| | — | | |
| | Tools ▸ (submenu listing every Toolbox tool) | — | `AppModel.open(module, tool:)` with the tool ids from ARCHITECTURE |
| **Window** | Minimize ⌘M · Zoom · Ignore List… · Operation History… · Bring All to Front | | Ignore List opens Settings › Ignore List |
| **Help** | Spruce Help | ⌘? | local Help window (§9.3) |
| | Help for This Screen | — | the current module's anchor (also the header "?" button) |
| | Keyboard Shortcuts | ⌘/ | a sheet listing this table |
| | What's New in Spruce | — | local release notes |
| | Permissions Guide… | — | FDA, Notifications, Login Items, App Management (13 §5) |
| | Open Logs Folder · Export Diagnostics… · Reset All Warnings | (⌥ held) | revealed only with ⌥ (alternate items); CMM3 had hidden support items |

Rules (INFERRED):
- Every destructive command goes through the same confirmation sheet as the orb. No shortcut skips confirmation; ⌘↩ only opens the sheet.
- Never bind ⌘⌫ or ⇧⌘⌫. In Finder they mean Move to Trash and Empty Trash, and users would expect an immediate action.
- Leave out licensing, cross-promotion and "Tell a Friend" items: Spruce is a personal build.

---

## 3. Dock icon menu and Dock drop

### 3.1 Evidence

- **No `AppleDockMenu` key** in the CMM3 3.9 or X 4.0.0 Info.plist. No dock-menu nib in the CMM3 resource list (`_CodeSignature/CodeResources`, fetched). VERIFIED-BIN / VERIFIED-PLIST.
- The CMM3 binary contains `applicationDockMenu:` among `NSApplicationDelegate` selector names. Inconclusive: protocol metadata lists all optional methods.
- INFERRED: CMM3, and probably X and 5.x, show **only the standard Dock menu**: window list, Options ▸ (Keep in Dock, Open at Login, Show in Finder), Show All Windows, Hide, Quit. No 5.x evidence either way.
- **Dock drop is supported.** Both bundles declare one document type, `CFBundleTypeName = AnyFile`, `CFBundleTypeExtensions = ["*"]`, `CFBundleTypeRole = Viewer` (VERIFIED-BIN https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Info.plist; VERIFIED-PLIST X 4.0.0). So the Dock icon accepts any dropped file, and `open -a` hands files to the app.
  - The CMM3 binary implements `application:openFile:`, `application:openFiles:`, `application:openURLs:` and `application:openFileWithoutUI:` (VERIFIED-BIN strings).
  - Users relied on this. The "Uninstall with CleanMyMac X" Alfred workflow runs `open -a CleanMyMac\ X.app {query}` on app bundles, widgets and plug-ins, keyword `uninstall` (VERIFIED-OSS https://raw.githubusercontent.com/WShiBin/conf-for-mac/master/Alfred/Alfred.alfredpreferences/workflows/user.workflow.8491B49E-46CC-446B-A61B-C0086EA24736/info.plist). INFERRED: an opened `.app` lands in the Uninstaller with that app selected.

### 3.2 Spruce Dock menu spec (INFERRED)

`NSApplicationDelegate.applicationDockMenu(_:)` (VERIFIED-APPLE https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)) through `@NSApplicationDelegateAdaptor`. Return a fresh `NSMenu` each time so the sizes are current:

```
Run Checkup
Empty Trash (7.4 GB)…       ← disabled at 0 B or without FDA; always confirms
Free Up Memory              ← only when memory pressure is warn/critical (20-gap-01 §6)
—
Open ▸  Cleanup · Protection · Performance · Applications · Clutter · Space Map · Cloud Storage · Toolbox
—
Pause Alerts for 1 Hour / Resume Alerts
```

### 3.3 Spruce open/drop routing (INFERRED)

Declare `CFBundleDocumentTypes` with `LSItemContentTypes`: `com.apple.application-bundle`, `com.apple.installer-package-archive`, `public.folder`, `public.item`. Role `Viewer`, `LSHandlerRank = None`, so Spruce never becomes a default opener. Handle the files in `application(_:open:)` (VERIFIED-APPLE: AppKit calls it for URL and document opens and then skips `openFile(s):`).

| Dropped / opened item | Destination | Notes |
|---|---|---|
| `.app` | Applications › Uninstaller, that app selected, leftovers computed | Refuse system apps and Spruce itself with an inline note |
| `.pkg` / `.mpkg` | Applications › Installers, with the package's receipt lookup (`pkgutil --pkgs`, 06 §3) | read-only until confirmed |
| folder | Space Map rooted at that folder | ask "Map this folder" vs "Find duplicates here" only if the drop is on the Dock icon. Drops on a module go to that module (§8) |
| any other file(s) | Toolbox › Shredder staging list (unchecked until confirmed) | never auto-shred |
| many mixed items | a small sheet: "What would you like to do with these 5 items?" | grouped by type |

---

## 4. Result-list context menus and row affordances

### 4.1 Vendor evidence

| Context | Items / affordances | Status |
|---|---|---|
| CMM3, every result list | **Hover icons:** magnifier = reveal in Finder, eye = Quick Look. Control-click → **Add to Ignore List** (a one-time explainer with "Do not show this message again"). "Sort by" pop-up; search field. | VERIFIED-BIN help topics 2–8 (e.g. https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-2.html); 13 §4.15 |
| CMM3, same items as File menu | Select (Space) · Launch (⌘↓) · Quick Look (⌘Y) · Reveal in Finder (⇧⌘R) · Add to / Remove From Ignore List | VERIFIED-BIN (§2.1). INFERRED that the row context menu reuses these items, since they share tags 1–4 and 10. |
| CMM3 Photo Junk | Control-click → **Reveal in Photos**; **Quick Look** shows RAW and JPEG side by side | VERIFIED-BIN topic-3 |
| CMM3 Uninstaller | Per app: Keep · Launch · Reveal in Finder · Add to Ignore List. **Action › Refresh** reloads the list (selection lost). | VERIFIED via 06 §2 ([CMM3-Strings]); topic-8 |
| X Maintenance | Context-menu items gained descriptions (4.4.4) | VERIFIED-DM |
| X Space Lens | Double-click = Quick Look (4.4.6) | VERIFIED-DM |
| 5.x, all modules with results | Control-click → **Add to Ignore List** | VERIFIED-KB (via 20-gap-02 §3) |
| 5.x, unfamiliar items in Cleanup, Protection, Performance, Applications | **Smart Insights** button (Apple Intelligence, macOS 26, Apple Silicon) explains what an item is and whether it is needed | VERIFIED-KB/news (via 01 §5.2, 08 §8.3). A per-item **button**. Not documented as a context-menu entry. Placement: 20-gap-04 §7. |
| 5.x Privacy / Maintenance rows | ⓘ info buttons (informational rows have ⓘ in place of a checkbox) | REPLICA / X screenshots (via 20-gap-02 §2) |

### 4.2 Spruce row context menus (INFERRED)

One `RowContextMenu` builder, used by `ItemRow`. Items appear only when they apply:

| Item | Key | Applies to | Notes |
|---|---|---|---|
| Check / Uncheck | Space | any selectable row | mirrors the checkbox. `risky` rows ask for confirmation before checking (ARCHITECTURE rule 3) |
| Open | ⌘↓ | apps, files | apps: launch; files: default app |
| Quick Look | ⌘Y | files, folders, images | `QLPreviewPanel`. Skip dataless cloud files unless the user confirms (07 §9) |
| Reveal in Finder | ⇧⌘R | anything with a path | — |
| Reveal in Photos | — | Photos-library items | `photos://` cannot target an asset. Open Photos and show the Smart Album the scan created, or just reveal the library. |
| Copy Path | ⌥⌘C | anything with a path | — |
| Explain This Item | — | items with a rule entry; on-device model when available | shows our rule's rationale; the Foundation Models answer is optional (macOS 26). Same panel as the ⓘ button. |
| Ignore ▸ This Item / This Folder / All Items from This App | — | anything ignorable (not Trash Bins or Privacy, matching vendor scopes, 20-gap-06 §3.6) | first use shows the explainer with "Don't show again" |
| Show in Space Map | — | folders | jumps to Space Map rooted there |
| Uninstall… / Reset… | — | app rows | opens the Uninstaller flow, never immediate |

---

## 5. Finder integration

### 5.1 CleanMyMac 3: Services (VERIFIED-BIN)

From `Info.plist` (`NSServices`, port name `CleanMyMac 3 Service`, empty `NSRequiredContext`, so they also appear in Finder's context menu). Source: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Info.plist

| Menu title | `NSMessage` | `NSSendFileTypes` |
|---|---|---|
| Scan for Large and Old Files | `scanFolderForLargeOld` | `public.folder` |
| Clean with CleanMyMac | `cleanVolume` | `public.volume` |
| Erase with CleanMyMac | `eraseItem` | `public.item` |
| Securely Erase with CleanMyMac | `securelyEraseItem` | `public.item` |
| Uninstall with CleanMyMac | `uninstallApplication` | `com.apple.application-bundle` |
| Clean iPhoto Library with CleanMyMac | `cleanPhotoLibrary` | `com.apple.photo.library` |

- The provider methods exist in the binary as `scanFolderForLargeOld:userData:error:` … `cleanPhotoLibrary:userData:error:`, registered with `setServicesProvider:` (VERIFIED-BIN strings).
- **The app manages its own Services' visibility.** It reads `~/Library/Preferences/pbs.plist` › `NSServicesStatus`, builds keys in the format `"%@ - %@ - %@"` (bundle ID - menu title - message) and writes `enabled_context_menu` / `enabled_services_menu`. It logs "Exception occured while updating services: %@" (VERIFIED-BIN strings). A user dotfile that disables exactly these six keys confirms the format, e.g. `"com.macpaw.CleanMyMac3 - Uninstall with CleanMyMac - uninstallApplication"` (VERIFIED-OSS https://github.com/diimdeep/dotfiles/blob/1893a156f9e694de5ae7d7081de2f2c2f4bb9e76/osx/configure/services.sh). The same file shows the sister app's "Scan for Duplicates with MacPaw Gemini".
- CMM3 also shipped a `StorageManagement.appex` ("System Junk") for macOS's own Storage Management window (VERIFIED via 10 §2.3).

### 5.2 CleanMyMac X: Services return in 4.0.2

- 4.0.0 shipped no `NSServices` (VERIFIED-PLIST).
- **4.0.2: "Services menu for Updater and Uninstaller modules"** (VERIFIED-DM).
- The exact titles were not found. INFERRED: "Uninstall with CleanMyMac X" on app bundles, plus an Updater counterpart.
- No Finder Sync extension is known for X. The X cask's zap list has a widget but no Finder Sync container (VERIFIED via 01 §3.2, 13 §3.22).

### 5.3 CleanMyMac 5.x: the Finder Sync extension

**Verified facts:**

| Fact | Source |
|---|---|
| Path `CleanMyMac_5.app/Contents/PlugIns/CleanMyMac_5_FinderSyncExtension.appex`; executable `CleanMyMac_5_FinderSyncExtension` | VERIFIED-OSS process capture, 2026-09-20 (https://github.com/OpenAgentsInc/openagents/blob/49d65052fbf0dfa2a3f01e4359061416d3773e74/docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-after.txt) |
| Bundle ID `com.macpaw.CleanMyMac5.FinderSyncExtension`; provisioning entitlement `com.apple.security.application-groups = [S8EX82NJP6.*]` | VERIFIED via 10 §2.1 (decoded provisioning profile) |
| Sandboxed: leaves `~/Library/Containers/com.macpaw.CleanMyMac5.FinderSyncExtension` (4 KB) and `~/Library/Application Scripts/com.macpaw.CleanMyMac5.FinderSyncExtension` on a 5.6.0 install | VERIFIED-OSS https://github.com/earthinversion/Mac-apps-self-manage/blob/7b6087f0f82fc11aa1a04c42d9225d1300c77119/README.md |
| It was **running** alongside the Menu and Health Monitor, so it was enabled and loaded by Finder | VERIFIED-OSS (same capture) |
| Not in the Homebrew cask's `zap` list | VERIFIED (https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb, fetched this pass) |
| **The Mac App Store edition registers no Finder Sync extension.** An EtreCheck report of a Mac mini (2024) with `CleanMyMac_5_MAS.app` installed 2026-04-04 lists four Finder Sync extensions (Beyond Compare, Google Drive, OneDrive, Synology), none from CleanMyMac. It also lists no CleanMyMac widget, Intents plug-in or Share extension. | VERIFIED-OSS https://raw.githubusercontent.com/dmdgolf/etrecheck-analyzer/HEAD/data/sample_report.txt |

**What it adds: unknown.** No release note (5.0.0–5.3.1 fetched), KB excerpt in earlier reports, or third-party file names its menu items, toolbar button or badges. 5.4–5.7.1 notes are behind the unreachable `updates.cleanmymac.com`.

What the API allows (VERIFIED-APPLE):
- **Context menus:** `menu(for:)` with `FIMenuKind` = `contextualMenuForItems`, `contextualMenuForContainer`, `contextualMenuForSidebar`, `toolbarItemMenu`. "If `kind` is `FIMenuKindToolbarItemMenu`, the system always calls this method even if the target and selection are not related to the extension." https://developer.apple.com/documentation/findersync/fifindersyncprotocol/menu(for:)
- **Toolbar button:** `toolbarItemName` / `toolbarItemImage` / `toolbarItemToolTip`. The user adds it via Finder › View › Customize Toolbar.
- **Badges:** `setBadgeImage(_:label:forBadgeIdentifier:)` / `setBadgeIdentifier(_:for:)`.
- **Scope:** only items inside `directoryURLs`. "Always set `directoryURLs` when the extension starts." https://developer.apple.com/documentation/findersync/fifindersynccontroller/directoryurls
- **Host app:** `FIFinderSyncController.isExtensionEnabled` and `showExtensionManagementInterface()` (macOS 10.14+).

INFERRED ranking of what MacPaw uses it for:
1. **Context-menu entries that hand a target to the main app.** Likely: uninstall a selected `.app`; analyse a selected folder (Space Lens / Large Files); possibly a malware scan of a file or folder. It continues X 4.0.2's Services for Uninstaller and Updater. A sandboxed extension cannot uninstall anything itself, so it must open the app (URL scheme or App Group / XPC message).
2. **A toolbar button menu.** Possible: it is the only Finder Sync surface shown regardless of folder.
3. **Badges.** Unlikely: a cleaner has no sync state to show, and badging the whole disk is costly.

Note that the extension process runs even when unused. Finder launches every enabled Finder Sync extension. Its presence does not tell us its `directoryURLs`.

**Services in 5.x:** no evidence either way. INFERRED: the Finder Sync menu replaced them in the direct edition. The MAS edition has neither surface as far as the EtreCheck data shows. That report does not list Services.

### 5.4 Where users enable Finder Sync extensions (for our onboarding)

| macOS | Location | Status |
|---|---|---|
| 14 Sonoma | System Settings › Privacy & Security › Extensions › **Added Extensions** | VERIFIED-OSS (CloudWire README: https://github.com/DonMikone/CloudWire/blob/793395648d4a6098f2b5260c2216783b775c4361/README.md) |
| 15.0–15.1 | The management UI was missing or buggy | VERIFIED-OSS (https://github.com/mariusgm/newfile/blob/05819878e41f2a63b62ba83141c061552d2a630d/README.md; https://github.com/PrakashSewani/dormant-macos/blob/1593e5547d85ce02edab884f117ae2ff67adcfbd/docs/decisions.md) |
| 15.2+ and 26 Tahoe | System Settings › General › Login Items & Extensions › **File Providers**. The "Finder" category there lists **Quick Actions**, not Finder Sync. | VERIFIED-OSS (https://github.com/thenervelab/hippius-desktop/blob/275e07e4cb3843498641f77e32bef21f4d73410f/.claude/rules/macos-packaging.md; https://github.com/AlexToumayan/quietdesk/blob/85ca85ee7fd1589144ea1fe0df89f8b086a41b38/docs/evidence/research.md, citing Apple forum thread 756711) |
| any | `pluginkit -e use -i <bundle-id>` turns it on; `pluginkit -mvv -p com.apple.FinderSync` lists them | VERIFIED-OSS (FileCut README; dormant-macos). The documented API path is `FIFinderSyncController.showExtensionManagementInterface()`. |
| deep link | `x-apple.systempreferences:com.apple.LoginItems-Settings.extension` | VERIFIED-OSS (https://github.com/sorty-organizer/Sorty/blob/527aaf8bc152a9b69a1bf0c954df8a5298f16fdc/Sources/SortyCore/FinderExtension/ExtensionCommunication.swift) |

Practical notes (VERIFIED-OSS, same sources):
- The extension registers only after the host app has been launched once from a PlugInKit-accepted location such as `/Applications`.
- Re-signing changes the extension's identity and can silently drop the user's enablement.

### 5.5 Spruce Finder integration spec (INFERRED)

**Layer 1: `NSServices` (P0).** Info.plist only, no extension, works on 14/15/26. Register a services provider at launch (`NSApp.servicesProvider = ServicesProvider()`, then `NSUpdateDynamicServices()`).

| Title (ours) | Message | Send file types | Action |
|---|---|---|---|
| Uninstall with Spruce | `uninstallApp` | `com.apple.application-bundle` | open Uninstaller with the app selected |
| Map Folder with Spruce | `mapFolder` | `public.folder`, `public.volume` | Space Map rooted there |
| Find Duplicates with Spruce | `findDuplicates` | `public.folder` | Clutter › Duplicates with that location |
| Scan for Threats with Spruce | `scanThreats` | `public.item` | Protection › custom-path scan |
| Shred with Spruce | `shredItems` | `public.item` | Toolbox › Shredder staging (unchecked) |

Each handler reads file URLs from the pasteboard (`NSPasteboard.readObjects(forClasses: [NSURL.self])`), validates them with `PathGuard`, activates the app and routes as in §3.3. Services never act destructively without the in-app confirmation.

**Layer 2: Finder Sync `.appex` (P2), "Spruce Finder Actions".**
- `directoryURLs = [URL(fileURLWithPath: "/")]`. Context menu `contextualMenuForItems` only, with no badges.
- Show items by selection type: one or more `.app` → "Uninstall with Spruce…"; folder → "Map in Spruce" and "Find Duplicates Here"; anything → "Scan for Threats".
- The extension is sandboxed. It only builds a `spruce://` URL with the item paths and opens it with `NSWorkspace.shared.open(_:)`. Paths are percent-encoded; several items are passed as repeated `path=` parameters.
- Alternatively, write a request to the App Group container and post a Darwin notification. No security-scoped bookmarks are needed, because the host app has its own (FDA) access.
- Optional toolbar button with a menu (Run Checkup, Open Space Map for Current Folder).
- Onboarding: if `!FIFinderSyncController.isExtensionEnabled`, show a card with "Turn On Finder Actions" → `showExtensionManagementInterface()`. Explain the 15.2+ "File Providers" location.
- SwiftPM caveat: an `.appex` needs its own bundle, Info.plist (`NSExtensionPointIdentifier = com.apple.FinderSync`, `NSExtensionPrincipalClass`) and sandbox entitlement. Build it in `scripts/build-app.sh` with `swiftc` into `Contents/PlugIns/`, or move to an Xcode project.

---

## 6. URL scheme, Shortcuts, widgets, Control Center

### 6.1 CleanMyMac 3: `cleanmymac://` (VERIFIED-BIN)

- `CFBundleURLTypes`: name "CleanMyMac multipurpose URL: activation etc.", scheme `cleanmymac` (Info.plist).
- Route strings in the main binary, next to `_setupURLScheme` and an Apple-event handler (`setEventHandler:andSelector:forEventClass:andEventID:`): `/activate`, `/retrieve_license`, `/blocked_license`, `/reset_activations`, `/upgrade_license`, `/buy_license`, `/subscribe`, `/about`, `/tell_friend`, `/support_center`.
- INFERRED: the scheme served licensing and marketing links from MacPaw's site and emails, not automation.
- **Launch arguments** (the Menu, Scheduler and helper hand-off into the main app; VERIFIED-BIN strings): `-cleanTrash`, `-uninstall`, `-scheduled`, `-scheduledScan`, `-openMonitoringSettings`, `-launchFromHelper`, `-launchFromHelper_scan`, `-freeSpace`, `-fullScan`, `-activate <key>` ("Please provide activation key"), `-deactivate`. The binary also has `receivedUninstallApplicationsNotification:`, the hand-off from the trash alert (§7.1).

### 6.2 CleanMyMac X: `cleanmymacx://` (VERIFIED-PLIST)

`CFBundleURLName` "CleanMyMacX multipurpose URL: activation etc.", scheme `cleanmymacx` (4.0.0). Routes not recovered. INFERRED: the same licensing routes as CMM3.

### 6.3 CleanMyMac 5.x: `cleanmymac5://`

- Reported routes: `cleanmymac5:///modules/<name>`, where `<name>` ∈ `smartCare`, `cleanup`, `protection`, `performance`, `applications`, `myClutter`, `spaceLens`. "Opening it only shows the screen; it doesn't scan or clean." Older versions use other schemes; check `CFBundleURLTypes`. Source: a hands-on third-party agent guide (VERIFIED-OSS as a report; the routes themselves are INFERRED from one source): https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md
- The empty host (`///`) means the path carries the route.
- No other routes were found (GitHub code search for `cleanmymac5://`: one hit, this file).
- INFERRED:
  - licensing routes probably persist, by lineage;
  - the Finder Sync extension probably uses this scheme or the App Group to hand off targets;
  - newer modules (Cloud Cleanup, My Tools, Email Cleanup) may have their own route names; unknown.
- **Setapp / MAS schemes:** unknown. Bundle IDs are `com.macpaw.CleanMyMac-setapp` and `com.macpaw.CleanMyMac-mas` (10 §2.1).

### 6.4 Spruce URL scheme spec (INFERRED)

Register `CFBundleURLTypes` → `spruce` (rename with the product). Handle it in SwiftUI `.onOpenURL` on the main `WindowGroup`, with `handlesExternalEvents(matching: ["*"])` so no second window opens. AppKit apps can use `application(_:open:)`. Test with `open "spruce://…"`.

| Route | Parameters | Effect | Destructive? |
|---|---|---|---|
| `spruce://module/<id>` | `id` ∈ `checkup, cleanup, protection, performance, applications, clutter, spaceMap, cloudStorage, toolbox, activity` | `AppModel.open(module)` | no |
| `spruce://tool/<toolId>` | tool ids from ARCHITECTURE (`cleanup.trash`, `applications.uninstaller`, …) | `AppModel.open(module, tool:)` | no |
| `spruce://scan/<id>` | `id` as above; `?autostart=1` is implicit | open the module and start a scan | no (scans are read-only) |
| `spruce://uninstall` | `path=` (repeatable, absolute, percent-encoded) | Uninstaller with these apps selected and leftovers computed | **no**: the user still presses Uninstall |
| `spruce://map` | `path=` | Space Map rooted at the path | no |
| `spruce://duplicates` | `path=` (repeatable) | Duplicates with these locations | no |
| `spruce://threats` | `path=` (repeatable) | Protection custom scan | no |
| `spruce://leftovers` | `bundleId=` and `name=` | Applications › Leftovers filtered to a trashed app (used by the trash monitor) | no |
| `spruce://settings/<tab>` | `general, checkup, notifications, monitor, protection, ignoreList, permissions` | open Settings on a tab | no |
| `spruce://help/<anchor>` | module id or topic | Help window at the anchor | no |

Security rules:
- **No route deletes, empties, quits, kills or changes settings.** A URL can only navigate, pre-fill or start a read-only scan. Any web page or app can open a URL.
- Validate `path` values: they must be absolute, must exist, and pass through `PathGuard`. Cap them at 200.
- Coalesce repeated opens within 1 s and ignore unknown routes, logged at debug level.
- While a Run is in progress, queue the navigation and show it as a banner ("Spruce will open Space Map when cleanup finishes").

### 6.5 Shortcuts / App Intents, widgets, Control Center in 5.x

| Surface | Evidence | Conclusion |
|---|---|---|
| Widgets | X shipped `com.macpaw.CleanMyMac4.CleanMyMacWidget` (cask zap list). The 5.x cask has no widget container. The MAS 5.x EtreCheck "Widgets" list has no CleanMyMac entry. | **No widget in 5.x** (VERIFIED absence for MAS; strong INFERRED for direct). Via 01 §3.2, 08 §2; EtreCheck. |
| Shortcuts / App Intents | No Intents plug-in in the MAS EtreCheck list. No release note 5.0.0–5.3.1 or What's New entry to 5.7.1 (01 §6) mentions Shortcuts or Siri. In-process App Intents would not show in EtreCheck. | **No evidence**; INFERRED absent. Check `Contents/Resources/Metadata.appintents` on a real bundle (§12). |
| Control Center controls | Controls need macOS 26 (`ControlWidget`, `ControlWidgetButton`: VERIFIED-APPLE https://developer.apple.com/documentation/swiftui/controlwidget, https://developer.apple.com/documentation/widgetkit/controlwidgetbutton). There is no widget extension in which to host one. | **Absent** (INFERRED). |
| The CLI as the automation surface | MacPaw shipped `cleanmymac` / `cmm` (CLI 1.0, July 2026). "CLI integration" is listed as coming next. | VERIFIED via 01 §6, 03 §2. The vendor's automation answer is the CLI, not Shortcuts. |

### 6.6 Spruce Shortcuts / widget / Control spec (INFERRED, P3)

App Intents in the main app target (macOS 13+; `AppShortcutsProvider`, `AppShortcut(intent:phrases:shortTitle:systemImageName:)`: VERIFIED-APPLE https://developer.apple.com/documentation/appintents/appshortcutsprovider):

| Intent | Parameters | Result | Notes |
|---|---|---|---|
| Run Checkup | `openInApp: Bool` (default true) | opens Checkup and scans; returns a summary string when run in the background | read-only. Never runs the clean step. |
| Open Spruce Module | `module: ModuleEntity` (`AppEnum`) | opens it | `OpenIntent`-style (VERIFIED-APPLE https://developer.apple.com/documentation/appintents/openintent) |
| Get Free Disk Space | — | `Measurement<UnitInformationStorage>` | `volumeAvailableCapacityForImportantUsage` |
| Get Mac Health | — | the health level and its top reasons | from the Monitor snapshot |
| Empty Trash | — | freed bytes | `requestConfirmation` is **required**. Never bound to a Siri phrase without confirmation. |
| Free Up Memory | — | before/after pressure | only offered if we ship the RAM tool |

Notes:
- `openAppWhenRun` is deprecated in favour of `supportedModes` (VERIFIED-APPLE https://developer.apple.com/documentation/appintents/appintent/openappwhenrun). Use `supportedModes` on the macOS 26 SDK, guarded.
- **Build caveat:** App Intents metadata (`Metadata.appintents`) is produced by Xcode's build step. A pure `swift build` app bundle will not expose intents to Shortcuts.
- **Widget** (WidgetKit extension, small/medium): free space, health level, last Checkup time. Tap → `spruce://module/checkup`.
- **Control** (macOS 26): `ControlWidgetButton` "Run Checkup" (fire-and-forget, opens the app), optionally "Empty Trash" with app-side confirmation.

---

## 7. The trash monitor: "uninstall completely?" when an app goes to the Trash

### 7.1 CleanMyMac 3: exact alert (VERIFIED-BIN)

Sources (Menu app, `CleanMyMac 3 Menu.app`, `LSUIElement = true`):
- `Base.lproj/TrashedAppAlert.nib` (parsed) and `en.lproj/TrashedAppAlert.strings`: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/Resources/Base.lproj/TrashedAppAlert.nib
- `Base.lproj/Localizable.strings` (same folder).
- Help topic 94: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html

**Where it appears.** A custom alert view controller (`CMTrashedAppsAlertViewController`) hosted by the Menu app.
- INFERRED from the sibling alerts and 08 §6.1: it drops down from the menu-bar icon as a HUD panel, not as a Notification Center banner.
- Help topic 94: suggestions on correct uninstallation of trashed applications are displayed "when you try moving an application to the Trash folder".
- Controlled by the Menu preference "Offer to correctly uninstall applications" (VERIFIED, 08 §7.1, 20-gap-06 §3).

**Structure.** One `NSTabView` bound to `tabIdentifier`, with four tabs:

| Tab | Content |
|---|---|
| **List** | Title "**Uninstall applications correctly.**"; description "**Remove trashed applications along with all related leftovers.**" Another variant in Localizable: "CleanMyMac will help you remove trashed applications along with all related leftovers." A table (`NSArrayController` bound to `issues`, one `CMTrashedAppIssue` per app). Each row binds `appNode.icon`, `appNode.name`, `appNode.relatedFilesString` (e.g. "N related files", format INFERRED), `appNode.size` (an `NSByteCountFormatter`), and a hidden "Simulated" label for test mode (`CMAppTrashMonitorTestMode`). Buttons: **Uninstall Completely** (`uninstallAction:`, key ↩), **View in CleanMyMac** (`launchCleanMyMacAction:`), **Dismiss** (`ignoreForever:`, key Esc). |
| **Progress** | "**Uninstalling Applications**" with an animated progress indicator bound to `wantsAttention` |
| **Done** | "**Done**" |
| **Failure** | "**Uninstallation Failed**" / "**Some of the related items could not be removed.**" Buttons: **View in CleanMyMac** (↩) and **Dismiss** (`dismissFailure:`, Esc). |

Behaviour read from the wiring (INFERRED from the selector names and bindings):
- The uninstall runs **inside the alert**, without opening the main app. The table showing names and sizes is the confirmation.
- **Dismiss means "never offer for these apps again"** (`ignoreForever:`), not "later".
- "View in CleanMyMac" hands the apps to the main app's Uninstaller: launch argument `-uninstall`, `receivedUninstallApplicationsNotification:` (§6.1).
- Several apps trashed together form **one alert with several rows**.

**Monitored locations** (strings in the Menu binary; VERIFIED-BIN): `~/.Trash`, `.Trashes` (per volume), `Documents/.Trash/`.
- INFERRED: the last is the iCloud Drive Trash under `~/Library/Mobile Documents/`.
- Classes: `CMTrashedAppsMonitor`, `CMTrashedAppsMonitorState`, `CMTrashedAppsReport`, `CMTrashedAppsMonitorMeasurements`.
- CMM3 used kqueue vnode sources for Trash (08 §3.1.1).

**Related rule:** putting the startup-drive Trash on the Ignore List **disables the Trash Monitor** (with a confirmation); removing it re-enables it (VERIFIED, 13 §4.15).

### 7.2 CleanMyMac X

- The Notifications preferences include a "full-uninstall prompt" (VERIFIED-KB via 13 §3.42).
- "Minor Trash Monitor … issues fixed" in 4.13.6 (VERIFIED-DM, cumulative 41514 page).
- Presentation not recovered. INFERRED: still a Menu-app alert.

### 7.3 CleanMyMac 5.x

- The **Health Monitor** background item raises "uninstall completely?" when an app is dragged to the Trash, alongside low-disk, high-memory and hung-app alerts (VERIFIED-KB, cleanmymac-processes, via 13 §3.23).
- 5.x alerts are posted even when the main app is closed (VERIFIED-KB via 08 §6.1).
- The toggle key was not found among the 5.x preference keys (20-gap-06 §3, row "App moved to Trash").
- **Presentation unknown.** Most likely (INFERRED):
  - a macOS notification from the Health Monitor or Menu process;
  - title along the lines of "Uninstall <App> completely?", body naming the leftovers' size;
  - one primary action (uninstall or remove leftovers) plus dismissal;
  - or the redesigned Menu popover with a CMM3-style card.
- 20-gap-07 §6 (alert catalogue, `app.trashed`) holds the Monitor-side spec. This section adds the prompt content and the edge cases.

### 7.4 Spruce trash-monitor spec (INFERRED)

**Engine (Monitor agent, `SpruceMac/Monitor`):**
- An `FSEventStream` on `~/.Trash` and on each mounted volume's `.Trashes/<uid>`, re-armed on `NSWorkspace.didMountNotification`.
- Optionally `~/Library/Mobile Documents/com~apple~CloudDocs/.Trash`.
- Flags `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`, latency 1.0 s. Pearcleaner's Sentinel does this (06 §3.10).
- `~/.Trash` is TCC-protected: the agent needs **Full Disk Access**. Without it, show the "Trash monitoring needs Full Disk Access" card and never claim "nothing found".

**Detection rules:**
1. Consider only top-level `*.app` bundles that appeared in a Trash folder. Read `CFBundleIdentifier`, the name, the version and the icon **from the trashed bundle**.
2. **Debounce 2 s and batch**, so dragging five apps gives one prompt.
3. **Suppress** when:
   - Spruce's own Uninstaller trashed it (an in-process token set, cleared after 10 s; Pearcleaner pauses its watcher the same way, 06 §3.4);
   - the bundle ID is still installed elsewhere (`LSCopyApplicationURLsForBundleIdentifier` / `NSWorkspace.urlsForApplications(withBundleIdentifier:)` outside the Trash). Its leftovers are shared data, so never offer;
   - it is an Apple/system app, Spruce itself, or on the Ignore List;
   - "Don't ask for this app" was chosen;
   - its leftovers total less than 1 MB and fewer than 3 items (nothing worth asking about);
   - the user disabled the alert, or ignored the startup Trash (vendor rule).
4. Compute leftovers with the Applications engine (06 §3), read-only, with the default selection rules.
5. If the app is **put back** before the user acts (the bundle leaves the Trash), withdraw the prompt.

**Presentation** (original copy):
- **Primary:** a `UNUserNotification` from the Monitor.
  - Title "Finish removing “<App>”?"; for several apps, "Finish removing 3 apps?".
  - Body "<App> left 14 items (312 MB) in your Library."
  - Category actions: **Remove Leftovers…** (foreground, opens the panel below) and **Don't Ask for This App**. Dismissing does nothing.
  - Unlike CMM3, plain dismissal is **not** "ignore forever": silent opt-outs are hard to discover.
- **Panel:** a small HUD `NSPanel` under the status item, or the Monitor popover's alert card if it is open.
  - App icon(s), name, "14 items · 312 MB" per row, a disclosure for the item list, checkboxes per app.
  - Buttons **Move Leftovers to Trash** (default, ↩), **Review in Spruce** (opens `spruce://leftovers?bundleId=…`), **Not Now** (Esc). A "Don't ask again for these apps" checkbox.
- **Progress / Done / Failure** in place, as in CMM3:
  - "Removing leftovers…" then "Done: 312 MB moved to the Trash";
  - or "Some items couldn't be removed" with **Review in Spruce**, which lists failures with reasons (permission, in use, SIP).
- Deletion goes through `FileRemover.dispose` with `DeletionMethod.trash` (ARCHITECTURE rule 1–2). Root-owned leftovers (LaunchDaemons, PrivilegedHelperTools) are listed but need **Review in Spruce**, which uses the admin prompt via `PrivilegedRunner`.

**Settings:** Notifications › "Offer to remove leftovers when an app is moved to the Trash" (default on), plus a "Don't ask" list with Remove buttons. This is the same `app.trashed` alert ID as 20-gap-07.

**Tests:** move a disposable app to the Trash and expect a prompt within 3 s. Put it back and expect the prompt withdrawn. Trash 3 apps at once and expect one prompt with 3 rows. Uninstall via Spruce and expect no prompt. Trash a second copy of an installed app and expect no prompt. Turn off FDA and expect the access card.

---

## 8. Drag-and-drop targets in the main window

### 8.1 Vendor evidence

| Target | Evidence | Status |
|---|---|---|
| CMM3 Shredder | "drag-and-drop files directly to the module". The completion text invites more drops: "Add or simply drag and drop more files for shredding." | VERIFIED-BIN topic-92, Localizable (`CleanupCompleteReviewMore_EraserGroupScanner`) |
| CMM3 drag machinery | `registerForDraggedTypes:`, `draggingEntered:`, `customDraggingEntered:`, `performDragOperation:`, `NSFilenamesPboardType` in the main binary | VERIFIED-BIN strings |
| X Uninstaller | 4.0.2 fixed "Conflicting drag and drop cases during uninstallation". 4.5.3 fixed "Drag and drop UI issue within Uninstaller". So apps can be dropped onto the Uninstaller. | VERIFIED-DM (…/4.0.2/, …/4.5.3/releasenotes.html) |
| CleanMyMac 1.7.2 | "Package Deinstaller": drag installer packages in to remove what they installed | VERIFIED via 06 §2 |
| Dock icon (all versions with "AnyFile") | any file or app can be dropped | VERIFIED-BIN/PLIST (§3.1) |
| 5.x | No source. Shredder is not among the 5.x tools named so far (06 §2; 20-gap-04 §3). | Unknown. INFERRED: the Uninstaller still accepts dropped apps. |

### 8.2 Spruce drop targets (INFERRED)

Use SwiftUI `.dropDestination(for: URL.self)` (or `onDrop(of: [.fileURL])`). Load item providers inside the closure: "the drop receiver can access the dropped payload only before this closure returns" (VERIFIED-APPLE https://developer.apple.com/documentation/swiftui/view/ondrop(of:istargeted:perform:)-f15m).

| Drop on | Accepts | Result | Highlight copy (ours) |
|---|---|---|---|
| Applications (idle or list) | `.app`, `.pkg` | select the dropped apps and compute leftovers. `.pkg` → Installers with receipts. | "Drop apps to uninstall" |
| Space Map | one folder or volume | re-root the map | "Drop a folder to map it" |
| Clutter › Large & Old / Duplicates | folders | add as scan locations (chips) | "Drop folders to include" |
| Protection (custom scan) | files, folders | scan these only | "Drop items to scan" |
| Toolbox › Shredder | files, folders | staging list, unchecked | "Drop items to shred" |
| Settings › Ignore List | files, folders, apps | add rules (path prefix or bundle ID) | — |
| **Sidebar row** | as for that module | switches to the module and applies the drop (spring-loaded after 0.6 s of hover) | — |
| Anywhere else | — | reject (`.forbidden` cursor) | — |

Common rules:
- Reject paths inside SIP-protected areas or our own bundle, with an inline reason.
- Dedupe items.
- Accept at most 500 items per drop.
- Never start a destructive step because of a drop.

---

## 9. In-app Help ("?" links) and the About window

### 9.1 Help: vendor evidence

| Version | Help surface | Status |
|---|---|---|
| CMM3 | A bundled **Apple Help Book** (`CFBundleHelpBookFolder = CleanMyMac3Help.help`, `CFBundleHelpBookName = com.macpaw.CleanMyMac.help`) with one topic per module (`topic-1…9`, `topic-90…94`) and a search index. Opened by Help › CleanMyMac Help (⌘?, `showHelpAction:`). Help › Support Center… opens the web support centre. Online Manual… is hidden. | VERIFIED-BIN (Info.plist, CodeResources, MainMenu.nib) |
| X 4.0.0 | `CFBundleHelpBookName` is kept but no `CFBundleHelpBookFolder` | VERIFIED-PLIST. INFERRED: online help. |
| X 4.6.9 | Feedback form in the Help menu | VERIFIED-DM |
| 5.x | The MacPaw Help Center has a per-module KB tree (13 §2). In-app ⓘ info popovers on rows (Privacy, Maintenance, Protection scan mode) and Smart Insights explainers. | VERIFIED-KB tree (13); ⓘ: REPLICA/X screenshots (20-gap-02); Smart Insights VERIFIED (01). A per-module "?" button that links to the KB is **not verified**; 13 §2.3 proposes it as our design. |

### 9.2 About: vendor evidence

- **CMM3 main app** (`AboutWindow.nib` + strings; VERIFIED-BIN https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/Base.lproj/AboutWindow.nib):
  - a custom vibrancy window (`NSVisualEffectView`) with the app name (bound to `currentAppName`) and "Version %@" (bound to `currentAppVersion`);
  - an auto-scrolling credits text view (`CMAutoScrollView`);
  - an **Acknowledgements** button opening a popover with a web view;
  - a site link (`visitSite:`) and a "Made in Ukraine" link (`visitMadeInUkraine:`);
  - a "**Try our products:**" strip with four product tiles (Gemini Classic, Encrypto, Hider 2, CleanMyDrive 2), some hidden by a binding (`encryptoHidden`).
- **CMM3 Menu app:** the gear menu has About (`orderFrontStandardAboutPanel:`, the standard panel), Preferences, Reset All Warnings (`resetAllIgnores:`), Provide Feedback, Quit (VERIFIED-BIN Menu `MainMenu.nib`).
- **5.x:** `MainAppUI.framework` holds a wordmark and a "Crafted by MacPaw" signature, used in About or a footer (VERIFIED-OSS via 09 §4.2, VaderCleaner teardown of 5.5.4). Layout unknown.

### 9.3 Spruce Help and About spec (INFERRED)

**Help.**
- Ship local help as Markdown or HTML in `Resources/Help/<anchor>.md`, rendered in a SwiftUI **Help window**: sidebar of topics, search, back/forward.
- Prefer this to an Apple Help Book. Help Books need `hiutil` indexing and `CFBundleHelpBookFolder`, and Help Viewer is slow. `NSHelpManager.openHelpAnchor(_:inBook:)` (VERIFIED-APPLE https://developer.apple.com/documentation/appkit/nshelpmanager) stays an option if we want macOS Help-menu search integration.
- **"?" button** in every `ScreenHeader` → `spruce://help/<moduleId>`. Each **ⓘ** on a row → a popover with the rule's rationale ("What is it · Is it safe · What happens if removed"), plus "Learn more" → Help anchor.
- Topics:
  - one per module and tool;
  - Permissions (FDA, Notifications, Login Items & background items, App Management, Finder Actions);
  - Ignore List; Safety rules ("What Spruce never deletes");
  - Keyboard shortcuts (this file's §10);
  - Uninstalling Spruce (components to remove: Monitor login item, Finder extension, App Group container);
  - Troubleshooting.
- Help menu items as in §2.4. The macOS Help menu's search field indexes menu items automatically.

**About window** (a small custom SwiftUI window, or `NSApp.orderFrontStandardAboutPanel(options:)` with a credits `NSAttributedString`):
- Spruce icon, name, "Version 1.2 (45)", copyright line;
- rules-database version and date (e.g. "Cleanup rules 2026.10.12");
- "Built for macOS 14–26; running on <model, macOS version>";
- buttons: **Acknowledgements** (open-source references studied, even with no dependencies), **Release Notes**, **Copy System Info** (for bug reports).
- No cross-promotion and no vendor-style signature line.

---

## 10. Spruce keyboard shortcut master table (INFERRED)

Columns: precedent from CMM3 (VERIFIED-BIN) or macOS convention, and conflict notes.

| Key | Command | Precedent | Notes |
|---|---|---|---|
| ⌘, | Settings… | CMM3, macOS | — |
| ⌘1…⌘9 | Checkup … Toolbox | CMM3 ⌘1–⌘6 for top-level modules | sidebar order |
| ⇧⌘A | Activity | — | Finder uses ⇧⌘A for "Go to Applications", but only in Finder |
| ⇧⌘N | Notifications popover | — | Finder's "New Folder" binding, Finder only |
| ↩ | Primary action (Scan / Review / Run sheet) | CMM3 Action › Scan = ↩ | inactive while a text field has focus |
| ⌘R | Scan Again | CMM3 Rescan ⌘R | confirms if the selection was edited |
| ⌘↩ | Run selected… (opens confirmation) | — | never deletes by itself |
| ⌘. / Esc | Stop | macOS cancel | — |
| ⌘[ | Back / Start Over | CMM3 Go › Back ⌘[ | Start Over confirms |
| Space | Check / uncheck focused row | CMM3 File › Select = Space | exception: Space Map is a browser-style view, so Space = Quick Look there and ⌫ toggles selection (07 §8.2) |
| ⌘Y | Quick Look | CMM3 ⌘Y | also double-click in Space Map (X 4.4.6) |
| ⇧⌘R | Reveal in Finder | CMM3 ⇧⌘R | — |
| ⌘↓ | Open / Launch | CMM3 Launch ⌘↓; Finder Open | — |
| ⌥⌘C | Copy Path | Finder "Copy as Pathname" | — |
| ⌘O | Add Folder to Scan… | CMM3 Add Folder… ⌘O | — |
| ⌘F | Find (focus search) | CMM3, macOS | Toolbox type-to-search too (20-gap-04 §3) |
| ⌘A / ⌥⌘A | Select All / Deselect All | macOS / Finder | visible rows only |
| ⌥⌘R | Select Recommended | — | restores the default smart selection |
| ⌃⌘S | Show/Hide Sidebar | SwiftUI `SidebarCommands` | 09 §B suggested ⌘0. Prefer the system binding; ⌘0 stays unassigned. |
| ⌥⌘I | Inspector | 09 §B | — |
| ⌥⌘P | Show File Paths | CMM3 View › Show File Paths (no key) | Finder's Path Bar binding, Finder only |
| ⌃⌘F | Full screen | macOS | — |
| ⌘? | Spruce Help | CMM3 | — |
| ⌘/ | Keyboard Shortcuts sheet | — | — |
| ⌃⌥⌘M | Global: toggle Monitor popover | 20-gap-07 §2 | registered by the Monitor agent; user-changeable |
| ⌘W / ⌘M / ⌘Q / ⌘H / ⌥⌘H | standard | macOS | — |

Never assigned: ⌘⌫, ⇧⌘⌫, ⌥⇧⌘⌫ (Finder trash semantics) and any unmodified letter key in lists (accidental triggers).

**Reconciliation with earlier reports (INFERRED).**
- 07 §8.2 and 20-gap-03 §4.5 gave Space Map **⌘R = reveal**. That collides with app-wide ⌘R = Scan Again (the CMM3 binding, and 02 §5's choice, which already moved reveal to ⇧⌘R). Use **⇧⌘R** for reveal everywhere, as CMM3 did.
- 09 §B's **⌘0** sidebar toggle is replaced by the system **⌃⌘S**.
- 02 §5's ⌘R = Scan is kept; ↩ also fires the primary orb.

---

## 11. Implementation notes and priorities (INFERRED)

| Priority | Item | Where | Notes |
|---|---|---|---|
| P0 | Menu bar (§2.4) and shortcuts (§10) | `Sources/Spruce/App/SpruceCommands.swift` (integrator-owned) | `@FocusedValue(\.selectedItems)` from `ItemRow` lists; `@FocusedValue(\.flowState)` from `ScanFlowModel` |
| P0 | `spruce://` scheme (§6.4) | Info.plist + `.onOpenURL` in `SpruceApp` | `URLRouter` in SpruceCore: pure parsing, Linux-testable, with route tests |
| P0 | Dock menu and open/drop routing (§3) | `AppDelegate` via `@NSApplicationDelegateAdaptor` | `application(_:open:)` → `URLRouter` |
| P0 | `NSServices` (§5.5 Layer 1) | Info.plist + `ServicesProvider` (`@objc` methods `uninstallApp(_:userData:error:)` etc.) | after install run `/System/Library/CoreServices/pbs -update` for testing |
| P1 | Trash monitor (§7.4) | `SpruceMac/Monitor/TrashedAppWatcher.swift` + Monitor UI | FDA gate; suppression token shared with the Uninstaller via App Group defaults |
| P1 | Context menus (§4.2), drop targets (§8.2) | design system `ItemRow`, module views | — |
| P1 | Help window, "?" and ⓘ (§9.3) | `Sources/Spruce/Help` (new, integrator to assign) | Markdown rendered with `AttributedString(markdown:)` |
| P2 | Finder Sync `.appex` (§5.5 Layer 2) | new target, built by `scripts/build-app.sh` | sandbox and App Group entitlements; ad-hoc signing works locally, but enablement resets on re-sign |
| P3 | App Intents, widget, Control (§6.6) | needs an Xcode project or `xcodebuild` | App Intents metadata extraction is an Xcode build phase |

---

## 12. Gaps and how to close them on a Mac with CleanMyMac 5 (≈10 minutes)

Assumes CleanMyMac 5 installed at `/Applications/CleanMyMac.app` (Homebrew) or `/Applications/CleanMyMac_5.app` (direct). All commands are read-only.

```sh
APP=/Applications/CleanMyMac.app; [ -d "$APP" ] || APP=/Applications/CleanMyMac_5.app

# URL schemes, Services, document types, help book, dock menu
plutil -p "$APP/Contents/Info.plist" | grep -A12 -E 'CFBundleURLTypes|NSServices|CFBundleDocumentTypes|CFBundleHelpBook|AppleDockMenu|NSUserActivityTypes'

# Every bundled extension (Finder Sync, widgets, intents, share…)
ls "$APP/Contents/PlugIns" "$APP/Contents/Extensions" 2>/dev/null
pluginkit -mAvv 2>/dev/null | grep -i -A3 macpaw
find "$APP" -name Metadata.appintents -maxdepth 4

# The Finder Sync extension: plist + candidate menu titles
FS="$APP/Contents/PlugIns/CleanMyMac_5_FinderSyncExtension.appex"
plutil -p "$FS/Contents/Info.plist"
strings -a "$FS/Contents/MacOS/CleanMyMac_5_FinderSyncExtension" | grep -iE 'uninstall|scan|lens|space|shred|malware|cleanmymac5:|menu|toolbar|badge' | sort -u | head -80
find "$FS" -name '*.strings' -exec plutil -p {} \; 2>/dev/null | head -80

# URL routes the main app knows (compiled strings and binary)
strings -a "$APP/Contents/MacOS/"* | grep -E '^/?modules/|cleanmymac5:|smartCare|myClutter|spaceLens' | sort -u | head -80

# Menu bar items with shortcuts (System Events can read the menu bar even if the window is opaque)
osascript <<'EOF'
tell application "System Events" to tell process "CleanMyMac"
  set out to ""
  repeat with m in menu bar items of menu bar 1
    set out to out & "## " & name of m & linefeed
    try
      repeat with i in menu items of menu 1 of m
        set k to ""
        try
          set k to value of attribute "AXMenuItemCmdChar" of i
          set k to k & " mods=" & (value of attribute "AXMenuItemCmdModifiers" of i)
        end try
        set out to out & "  " & (name of i as text) & "  " & k & linefeed
      end repeat
    end try
  end repeat
  return out
end tell
EOF
# AXMenuItemCmdModifiers: 0 = ⌘, 1 = ⇧⌘, 2 = ⌥⌘, 3 = ⌥⇧⌘, 4 = ⌃⌘, 8 = no ⌘ (bit 3 = "no command")

# Trash prompt: drag a disposable app to the Trash, then
log show --last 2m --predicate 'process CONTAINS "CleanMyMac"' | grep -iE 'trash|uninstall' | tail -40
# and screenshot whatever appears (notification vs. popover)
```

| # | Open question | Closed by |
|---|---|---|
| 1 | 5.x menu titles and shortcuts | the `osascript` dump |
| 2 | What the Finder Sync extension adds; whether a toolbar button exists | appex `strings` / `.strings`; right-click an app and a folder in Finder; Finder › View › Customize Toolbar |
| 3 | Whether 5.x still declares `NSServices` | `plutil` on Info.plist; Finder right-click › Services |
| 4 | Full `cleanmymac5://` route list | binary `strings`; then `open "cleanmymac5:///modules/…"` trials |
| 5 | App Intents present? | `Metadata.appintents`; Shortcuts app › Apps |
| 6 | 5.x trash prompt presentation and copy | the drag test + screenshot |
| 7 | Dock menu items | right-click the Dock icon |
| 8 | About window layout | CleanMyMac › About CleanMyMac |
| 9 | Drop targets in the 5.x window | drag an app onto Applications and a folder onto Space Lens |

---

## 13. Sources

**Vendor bundles and plists (fetched or parsed this pass)**
- CleanMyMac 3.9 main menu nib/strings: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/Base.lproj/MainMenu.nib ; https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/en.lproj/MainMenu.strings
- CleanMyMac 3.9 Info.plist (URL type, document types, `NSServices`, help book): https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Info.plist
- CleanMyMac 3.9 resource manifest: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/_CodeSignature/CodeResources
- CleanMyMac 3.9 About window: …/Contents/Resources/Base.lproj/AboutWindow.nib and …/en.lproj/AboutWindow.strings
- CleanMyMac 3.9 main binary strings (URL routes, launch args, services, drag, dock): https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203
- CleanMyMac 3 Menu: TrashedAppAlert nib/strings, MainMenu nib/strings, Localizable.strings, Info.plist, binary: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/MacOS/CleanMyMac%203%20Menu.app/Contents/Resources/Base.lproj/TrashedAppAlert.nib (and siblings)
- CleanMyMac 3 Help Book topics 2, 3, 8, 92, 94: https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/Resources/CleanMyMac3Help.help/Contents/Resources/English.lproj/topic-94.html (and siblings)
- CleanMyMac X 4.0.0 Info.plist (JSON): https://raw.githubusercontent.com/Zfinix/zos/HEAD/apps/CleanMyMac%20X.app.json
- Homebrew cask (5.7.1): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb

**MacPaw release notes (DevMate S3)**
- X per-version pages 4.0.0–4.6.10, e.g. https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.0.2/releasenotes.html , …/4.4.4/…, …/4.4.6/…, …/4.5.3/…, …/4.6.9/…
- X cumulative to 4.15.14: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41514.0.2512021236/releasenotes.html
- 5.x cumulative 5.0.0–5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html

**Third-party evidence of shipped behaviour**
- 5.x process capture (Finder Sync running): https://github.com/OpenAgentsInc/openagents/blob/49d65052fbf0dfa2a3f01e4359061416d3773e74/docs/gym/measurements/2026-09-20-kev-4b-metal-pass/processes-after.txt
- 5.6.0 leftover scan (Finder Sync containers): https://github.com/earthinversion/Mac-apps-self-manage/blob/7b6087f0f82fc11aa1a04c42d9225d1300c77119/README.md
- EtreCheck report with CleanMyMac 5 MAS (no CleanMyMac extensions): https://raw.githubusercontent.com/dmdgolf/etrecheck-analyzer/HEAD/data/sample_report.txt
- `cleanmymac5://` module links: https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md
- Alfred "Uninstall with CleanMyMac X" (`open -a`): https://raw.githubusercontent.com/WShiBin/conf-for-mac/master/Alfred/Alfred.alfredpreferences/workflows/user.workflow.8491B49E-46CC-446B-A61B-C0086EA24736/info.plist ; listings: https://github.com/msoedov/Alfred-collection (Readme)
- CMM3 services disabled via `pbs`: https://github.com/diimdeep/dotfiles/blob/1893a156f9e694de5ae7d7081de2f2c2f4bb9e76/osx/configure/services.sh

**Finder Sync enablement on 14/15/26 (developer notes)**
- https://github.com/thenervelab/hippius-desktop/blob/275e07e4cb3843498641f77e32bef21f4d73410f/.claude/rules/macos-packaging.md
- https://github.com/AlexToumayan/quietdesk/blob/85ca85ee7fd1589144ea1fe0df89f8b086a41b38/docs/evidence/research.md (cites developer.apple.com/forums/thread/756711)
- https://github.com/mariusgm/newfile/blob/05819878e41f2a63b62ba83141c061552d2a630d/README.md
- https://github.com/DonMikone/CloudWire/blob/793395648d4a6098f2b5260c2216783b775c4361/README.md
- https://github.com/sorty-organizer/Sorty/blob/527aaf8bc152a9b69a1bf0c954df8a5298f16fdc/Sources/SortyCore/FinderExtension/ExtensionCommunication.swift
- https://github.com/PrakashSewani/dormant-macos/blob/1593e5547d85ce02edab884f117ae2ff67adcfbd/docs/decisions.md
- https://github.com/CitroenGames/FileCut (README, SETUP.md)

**Apple documentation (JSON fetched)**
- FinderSync: https://developer.apple.com/documentation/findersync/fifindersynccontroller , …/fifindersyncprotocol , …/fifindersyncprotocol/menu(for:) , …/fifindersyncprotocol/toolbaritemname , …/fifindersynccontroller/directoryurls , …/fimenukind , …/fifindersynccontroller/isextensionenabled , …/fifindersynccontroller/showextensionmanagementinterface()
- AppKit: https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:) , …/nsapplicationdelegate/application(_:open:) , …/nshelpmanager , …/nsworkspace/recycle(_:completionhandler:)
- SwiftUI: https://developer.apple.com/documentation/swiftui/commandgroupplacement , …/view/ondrop(of:istargeted:perform:)-f15m , …/controlwidget
- WidgetKit: https://developer.apple.com/documentation/widgetkit/controlwidgetbutton
- App Intents: https://developer.apple.com/documentation/appintents/appshortcutsprovider , …/appshortcut , …/openintent , …/appintent/openappwhenrun

**Earlier reports relied on** (KB facts not re-fetchable here): 01 §3.2, §4.2, §6, §9.1, §10; 02 §3; 06 §2, §3.4, §3.10; 08 §3.1.1, §6, §7.1, §8.3; 09 §4.2; 10 §2; 13 §2, §3.22–3.24, §3.42, §4.15; 20-gap-01 §3; 20-gap-02 §2–3; 20-gap-04 §3, §6–7; 20-gap-06 §2–3; 20-gap-07 §2, §6.
