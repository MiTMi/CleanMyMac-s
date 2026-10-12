# 02 — Smart Care (CleanMyMac 5.x, 2024+) / Smart Scan (CleanMyMac X, 2018–2024): end-to-end flow

Track owner: research subagent, "Smart Care / Smart Scan" track
Date: 2026-10-12
Target: an original, functionally equivalent one-click "checkup" flow for our own macOS app (Apple Silicon Mac mini, macOS 14 Sonoma / 15 Sequoia / 26 Tahoe). Do not reuse MacPaw names, artwork or marketing copy. "Smart Care" and "Smart Scan" are MacPaw feature names. This document uses **"Checkup"** as the working name for our equivalent.

---

## 0. Method, source access and legend

**How this was researched.** About 65 web searches and 8 direct document fetches.

- Direct fetches of MacPaw pages (macpaw.com, cms-static/cms-rendered.macpaw.com), cleanmymac.com, review sites, apps.apple.com and setapp.com all failed in this sandbox (DNS failure or egress-proxy CONNECT 403).
- MacPaw knowledge-base (KB) and review content was therefore read through search-engine extraction of the cited URL. The tool returns paraphrased and quoted excerpts of the indexed page.
- GitHub raw content *was* reachable. MacPaw's own `cleanmymac-cli` README and wiki, and two open-source clones/cleaners (Mole, Mac Sai), were fetched in full.

**Legend.**

| Tag | Meaning |
|---|---|
| **VERIFIED** | The claim appears in the cited source. For macpaw.com and most review sites this was confirmed via search-engine excerpt of that exact URL (the page could not be opened directly). |
| **VERIFIED-direct** | Confirmed by downloading and reading the document itself (GitHub raw). |
| **INFERRED** | Our reasoning or recommendation for our implementation. It is not a documented MacPaw behavior. |
| **UNVERIFIED** | Searched for, but no source found. It is a gap, and the behavior must be designed by us. |

Paraphrased throughout. Short UI labels are quoted verbatim where a source gave them.

**Fact-check pass (2026-10-12, adversarial reviewer).** A second agent re-checked this report. Items it changed are marked **(corrected)**, and items it added are marked **(added in fact-check)**. In that pass, macpaw.com, review sites and web search were unavailable: DNS/proxy blocks, plus an exhausted search budget. Sources the reviewer *could* read directly:

- raw.githubusercontent.com: the MacPaw CLI README and wiki, the Homebrew `cleanmymac` cask, the CVE JSON records (CVEProject/cvelistV5), a mirror of the Talos spotlight text, Mole, Mac Sai, and macOS man pages mirrored per OS version (vitorgalvao/macos-man-pages);
- Apple's documentation JSON (developer.apple.com);
- MacPaw's legacy DevMate release-notes bucket on S3 (CleanMyMac X 4.0–4.6.x and CleanMyMac Classic 1.x).

Claims backed only by macpaw.com search excerpts could therefore not be re-confirmed *or* refuted in this pass; they keep their original tag. See "## Verification notes" at the end.

---

## 1. Executive summary (the 15 facts that matter most)

1. **Smart Care is the default landing screen and the entry point of CleanMyMac 5.** It runs five sub-routines "one by one": **Cleanup, Protection, Performance, Applications, My Clutter**. It "combines the functionality of all CleanMyMac modules but doesn't fully replace them." VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/smart-care. Reviewers also say the app opens directly on Smart Care, e.g. Forbes: https://www.forbes.com/sites/marksparrow/2024/10/16/the-new-cleanmymac-update-will-keep-your-mac-fit-and-health/.
2. **What each sub-routine does inside Smart Care** (VERIFIED, same KB URL):
   - *Cleanup* scans system junk (logs, caches, broken login items, etc.), mail attachments and Trash bins, and **auto-selects items for removal**.
   - *Protection* runs a **Quick Scan** for malware and **auto-selects found threats**.
   - *Performance* **suggests** periodic maintenance scripts and the **Flush DNS Cache** task.
   - *Applications* **recommends app updates, excluding system apps and macOS updates**.
   - *My Clutter* scans for **duplicate files in the Downloads folder only**.
3. **Flow = Scan → results as tiles → (optional) Review per tile → Run.** The KB steps: go to Smart Care, click **Scan**, review the results, click **Run**. A rescan is done via **Start Over** in the upper-left corner, after a confirmation. VERIFIED (Smart Care KB).
4. **The results screen shows one tile per module.** Contents: total data that can be safely removed, number of threats, number of maintenance tasks, available app updates, number of duplicate files. Each tile has a **Review** button to adjust selections. VERIFIED (Smart Care KB).
5. **Default selection: all Smart Care tasks are selected by default.** You skip one by clearing the checkmark on its tile. VERIFIED (Smart Care KB, via search excerpt).
6. **Excluding modules is persistent and lives in Settings.** The path is **Settings → Scanning tab → Smart Care** (left pane), then deselect a module, category or group. Deselecting a parent deselects its children. **Excluded modules still appear in results but their tiles are dimmed.** VERIFIED (Smart Care KB).
7. **Smart Care only runs the "basics" of each module.** One reviewer saw 6.1 GB in Smart Care's Cleanup versus 7.1 GB in the full Cleanup module. VERIFIED: https://www.softwarehow.com/cleanmymac-review/. This is deliberate safety scoping: Smart Care touches only low-risk categories.
8. **Safety guarantee wording.** CleanMyMac "doesn't delete any user files or app data unless you choose to." VERIFIED (Smart Care KB). Cleanup decisions are driven by a **Safety Database** of rules and exceptions, checked on every scan. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database.
9. **Smart-selection rules are documented per category** (VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk):
   - Document Versions: never the earliest or latest version; only versions less than 4 h apart.
   - iOS backups: the most recent backup is never auto-selected.
   - Safari downloads: only broken ones.
   - Slack downloads: broken, or at least 1 month old.
   - Mail attachments: only attachments that can be re-downloaded. User-modified ones are marked "changed by user" and left unselected. VERIFIED: https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments.
10. **Predecessor, Smart Scan (CleanMyMac X), had three scanners: Cleanup, Protection, Speed.** The summary showed the total removable data, the number of threats and the number of optimization tasks. There was **Review Details** under each scanner icon, per-item checkboxes, and a **Run** button. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/start-smart-scan.
11. **No scheduled auto-run is documented for the consumer app, only reminders.** These come from the CleanMyMac X Menu (weekly cleanup reminders), a frequency setting on the **Notifications** tab, and the Assistant. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/how-often-run-cleanup-scans and https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu. Real scheduled, forced runs existed only in CleanMyMac Business: every 7/14/30 days, with 0–2 reminders before a forced run. VERIFIED: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation.
12. **Scan duration is about 1–2 minutes on recent Macs.** Data points: 54 s on macOS Tahoe (allaboutcookies), ~1 min on a 2021 MacBook Air, "a couple of minutes" elsewhere. The KB warns it "may take a while, especially on older or heavily used Mac computers." VERIFIED (Smart Care KB plus reviews cited in §8).
13. **Permissions.** Full Disk Access (FDA) is needed for complete scans, and the first Smart Care/Smart Scan run registers the app's components with macOS. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access and https://macpaw.com/support/cleanmymac-x/knowledgebase/full-disk-access. Root operations go through a separately installed helper tool, the "Agent". VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/background-items.
    - **(corrected / refined)** In 5.x the Agent is a classic *blessed* privileged helper, the SMJobBless-style layout: binary at `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac5.Agent`, launchd plist at `/Library/LaunchDaemons/com.macpaw.CleanMyMac5.Agent.plist`. The plist has `Label`/`MachServices` = `com.macpaw.CleanMyMac5.Agent` and `Program` set to that binary.
    - That is not an `SMAppService.daemon` registration, whose plist would stay inside the app bundle.
    - Other 5.x background components: `com.macpaw.CleanMyMac5.HealthMonitor`, `com.macpaw.CleanMyMac5.Menu` (login item "CleanMyMac 5 Menu"), and a per-user `~/Library/LaunchAgents/com.macpaw.CleanMyMac5.Updater.plist`.
    - VERIFIED-direct: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb (uninstall/zap stanzas); public copy of the Agent plist at https://raw.githubusercontent.com/MYunFeiYang/zbookpowerg7/f4bce960e458399a4ebedb3cd29bf4d0f67af4ee/docs/backups/cleanmymac5-residue-2026-09-18/com.macpaw.CleanMyMac5.Agent.plist. `SMJobBless` is deprecated since macOS 13 ("use SMAppService instead"). VERIFIED-direct: Apple docs JSON for `SMJobBless(_:_:_:_:)`.
14. **macOS 15 Sequoia removed `periodic`.** The "periodic maintenance scripts" that Smart Care suggests cannot run the classic way on our target OS. VERIFIED: https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html. Our Performance tile must use other tasks on macOS 15+ (§10).
    - **Fact-check corroboration (added).** The macOS man-page mirror has `periodic.8` for macOS 13 and 14 but not for 15 or 26. VERIFIED-direct: https://github.com/vitorgalvao/macos-man-pages (raw `macOS/14/man8/periodic.8` → 200, `macOS/15/man8/periodic.8` → 404).
    - A forensic artifact note reports that a tested 15.6.1 host had no `/usr/sbin/periodic`, no `/etc/periodic` and no `com.apple.periodic-*` jobs. VERIFIED-direct: https://github.com/AppliedIR/sift-mcp (`packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml`).
15. **MacPaw's own CLI (2026, public beta) shows the same philosophy in text form.** Scan → Review → Confirm, grouped categories with checkboxes, age-based pre-selection (older than 7 days preselected, newer shown but unchecked), and a completion summary ("Cleanup complete!", per-category ✓ lines, "N items removed", total "cleaned"). VERIFIED-direct: https://github.com/MacPaw/cleanmymac-cli (README and wiki). This is the best available primary evidence for completion-screen semantics.
    - Re-fetched and re-confirmed in the fact-check.
    - The README's sample `clean` results screen shows **System Junk** and **Dev Tools** checked but **AI Junk** unchecked ("40 items selected (23.43 GB)"). So MacPaw's shared logic can leave a whole category unchecked while still listing it. VERIFIED-direct (README sample output).
    - The README's own sample completion screen then lists AI Junk as cleaned, so the sample is not fully consistent. INFERRED.

---

## 2. Version lineage relevant to this flow

| Version / date | Change relevant to the one-click flow | Status |
|---|---|---|
| CleanMyMac Classic 1.x (c. 2010–2012) | Not part of the one-click flow. Its release notes are where the Uninstaller's "Quit Application" dialog gained **Skip**, and where the rule "empty `Caches` folders are kept for sandboxed apps" first appears (see §4.1, §5 Screen 6). **(added in fact-check)** | VERIFIED-direct: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html |
| CleanMyMac X 4.0 (Sept 2018) | **Smart Scan** introduced: Cleanup + Protection + Speed; vendor claimed it was 3× faster than its predecessor. The 4.0.0 release notes say the "X" covers "three main fundamentals – Cleanup, Protection, and Speed", plus Updater, Assistant, Uninstaller and Menu. | VERIFIED: https://macrumors.com/2018/09/05/macpaw-launches-cleanmymac-x; the three fundamentals are VERIFIED-direct: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.0.0/releasenotes.html (the "3×" figure was not re-checked) |
| X 4.2.0 | Fixed the Talos-reported root-helper vulnerabilities (§9). **(added in fact-check)** | VERIFIED-direct: Talos spotlight text mirror (see §9) |
| X 4.4.1 | "Smart Scan VoiceOver improvements and fixes"; purgeable space can be freed in the **Maintenance** module; App Store cache now cleaned as part of User Cache. **(added in fact-check)** | VERIFIED-direct: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.4.6/releasenotes.html (cumulative notes) |
| X 4.4.3 | "Clearer scan details for Smart Scan"; Downloads cleanup added to System Junk. **(added in fact-check)** | VERIFIED-direct: same |
| X 4.6.2 | Free up RAM **directly from the low-memory notification** (an actionable notification); Assistant suggestions now come from an ML model. **(added in fact-check)** | VERIFIED-direct: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.6.9/releasenotes.html (cumulative) |
| X 4.6.9 | Option to **exclude Speed tasks** from Smart Scan; "Scan All" option added to the Action menu. The same release fixed "Cache files cleanup broke Ableton Preferences" (a safety-DB exception). | VERIFIED: https://tidbits.com/watchlist/cleanmymac-4-6-9/; re-confirmed **VERIFIED-direct**: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.6.9/releasenotes.html |
| X 4.14.0 | Security component rebranded **Moonlock Engine**. | VERIFIED: https://macpaw.com/cleanmymac-x/whats-new |
| X 4.15.0 | **Configurable protection scan settings** (affects what the Protection step scans). | VERIFIED: same |
| X 4.15.8 (1 Oct 2024) | Last 4.x stability release. | VERIFIED: same |
| **CleanMyMac 5.0.0 (16 Oct 2024)** | "X" dropped. Redesigned 3D-animated UI. Sidebar cut to **6 modules: Smart Care, Cleanup, Protection, Performance, Applications, My Clutter**. Smart Scan replaced by **Smart Care** (5 routines). Assistant plus Mac Health. Menu-bar grid of tiles. | VERIFIED: https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/, https://9to5mac.com/2024/10/16/macpaw-releases-major-update-to-cleanmymac-with-fresh-design-and-new-features/, https://www.prnewswire.com/news-releases/macpaw-launches-new-cleanmymac-the-smart-effortless-app-for-mac-care-302275058.html |
| 5.0.7 (May 2025) | Accessibility improvements; "Screen Cleaning Mode" (one search excerpt attributes this mode to 5.7.1 instead, so the date conflicts). | VERIFIED-conflicting: https://apps.apple.com/us/app/cleanmymac/id1339170533, https://macpaw.com/cleanmymac/whats-new |
| 5.2.1 | Cloud Cleanup (Plus tier). Not part of Smart Care. | VERIFIED: https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html |
| 5.2.9 (31 Oct 2025) | Listed stable release on Wikipedia at that time. | VERIFIED: https://en.wikipedia.org/wiki/CleanMyMac |
| 5.6.0 (17 Aug 2026; the App Store says 21 Aug) | **Notification Center**: a bell icon that keeps product news, offers and messages in one place. | VERIFIED: https://macpaw.com/cleanmymac/whats-new |
| 5.6.1 (2 Sep 2026) | Fixes only. | VERIFIED: same |
| 5.7.0 (25 Sep 2026) | **Email Cleanup** (Gmail). Not part of Smart Care. | VERIFIED: same |
| 5.7.1 (1 Oct 2026) | Maintenance release (minor issues and crashes). The Homebrew cask pins `version "5.7.1,50701.0.2609301754"`, i.e. build 50701.0, a build stamp of 2026-09-30 17:54. That matches a 1 Oct release. Bundle ID `com.macpaw.CleanMyMac5`; the app ships as `CleanMyMac_5.app`; updates come via Sparkle from `updates.cleanmymac.com/com.macpaw.cleanmymac5/updates.xml`. **(added in fact-check)** | VERIFIED: same; build and bundle details VERIFIED-direct: Homebrew cask (see §1 item 13) |
| CleanMyMac CLI 1.0 beta (2026) | Terminal app: `clean`, `purge`, `analyze`, `optimize`, `ignore`, `config`. The README says "cleanup logic shared with CleanMyMac", and the wiki says detection uses "cleanup rules shared with CleanMyMac". Shipped as `CleanMyMac_5_CLI.app` (cask name "CleanMyMac 5 CLI"); needs macOS 11+. | VERIFIED-direct: https://github.com/MacPaw/cleanmymac-cli; https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb |

No 5.1–5.7 release note mentions a Smart Care behavior change. The Smart Care KB is the current reference. UNVERIFIED that nothing changed.

---

## 3. What the one-click flow aggregates

### 3.1 Smart Care (CleanMyMac 5.x): module-by-module spec

| Tile | What it scans (vendor) | Default state | Result metric on tile | What "Run" does | Notes / sources |
|---|---|---|---|---|---|
| **Cleanup** | System junk (log files, cache files, broken login items, "and other"), **Mail attachments**, **Trash bins** | Items **auto-selected** | "total data that can be safely removed" (size) | Deletes the selected junk | VERIFIED (Smart Care KB). The Trash Bins module has 5 categories: Mail, Photos, Gemini Duplicates, Startup drive (incl. items removed from iCloud), External drives (one trash per drive). VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/trash-bins. Smart Care only uses the module "basics" (6.1 vs 7.1 GB). VERIFIED: softwarehow |
| **Protection** | **Quick Scan** for malware (Moonlock engine). Optional extra locations from Settings → Protection; the **disk-images (DMG)** option explicitly also applies to Smart Care | Found threats **auto-selected** | number of threats found | Removes the selected threats | VERIFIED: Smart Care KB; https://macpaw.com/support/cleanmymac/knowledgebase/protection-scan-options. Smart Care does *not* run Deep Scan. Deep Scan is recommended monthly from the Protection module. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/how-often-run-cleanup-scans |
| **Performance** | "Suggests running periodic maintenance scripts and the Flush DNS Cache task" | Tile selected (all tasks selected by default) | number of maintenance tasks | Runs the suggested tasks (needs root, via the helper) | VERIFIED (Smart Care KB). The Performance module itself offers a "weekly maintenance" bundle with **Review** and **Run Tasks**, plus **View All Tasks → Maintenance Tasks**. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks. Not in the App Store edition. VERIFIED: same |
| **Applications** | Available **app updates**, "excluding system apps and macOS updates" | Tile selected | number of app updates available | Updates the selected apps | VERIFIED (Smart Care KB). Update sources in the Updater module: App Store, Custom, macOS, Sparkle. The App Store edition lists neither App Store nor macOS updates. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/updater |
| **My Clutter** | **Duplicate files in ~/Downloads only** | Tile selected | number of duplicate files | Removes the selected duplicates | VERIFIED (Smart Care KB). The full Duplicates module has an "Apply smart selection" option. Which copy it keeps is not documented. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files |

**Deep links and module identifiers (added in fact-check).**

- A third-party skill reports that CleanMyMac 5 registers a `cleanmymac5://` URL scheme. `open "cleanmymac5:///modules/<name>"` opens a module screen, with these names: `smartCare`, `cleanup`, `protection`, `performance`, `applications`, `myClutter`, `spaceLens`.
- A link only *opens* the screen. It does not start a scan.
- Source (third-party, apparently hands-on, not vendor documentation): https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md. The same source says the App Store build (`CleanMyMac_5_MAS`) is sandboxed and asks for home-folder and Applications access before scanning. Status: INFERRED (single third-party source).
- **Implications for us (INFERRED).**
  - Space Lens appears to still exist in 5.x as its own screen, alongside the six modules that §2 lists from press coverage.
  - Our URL scheme (§5 Screen 0) should follow the same pattern: `ourapp://checkup` opens the screen and `?autostart=1` scans.

What Smart Care deliberately **does not** do. INFERRED from the module list versus the full app.

- No Privacy cleanup (browser history, cookies), no Large & Old files, no Similar Images, no Uninstaller, no Space Lens.
- No Deep malware scan, no RAM/purgeable tasks listed, and no macOS updates.

These are the riskier or more personal categories. They stay in their own modules, where the user always reviews.

### 3.2 Smart Scan (CleanMyMac X 4.x): module spec

VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/start-smart-scan. The three-pillar structure (Cleanup, Protection, Speed) is also VERIFIED-direct from the 4.0.0 release notes (§2).

| Scanner | Underlying modules |
|---|---|
| **Cleanup** | System Junk, Photo Junk (not in App Store edition), Mail Attachments, iTunes Junk, Trash Bins |
| **Protection** | Malware Removal |
| **Speed** | **Maintenance**: Free Up RAM, Run Maintenance Scripts, Flush DNS Cache, Hung Applications. The App Store edition used **Large & Old Files** instead of Speed. |

Behaviors (VERIFIED, same URL unless noted):

- After analysis the user sees three things: the total amount of data that can be removed safely, the number of found threats, and the number of optimization tasks.
- **Review Details** sits under the Cleanup and Protection scanner icons. Deselecting an item or task removes it from *this* Smart Scan run only.
- Persistent exclusion: **Preferences → Scanning**, then deselect a module or submodule. Speed tasks can be disabled too, since 4.6.9. Excluding System Junk or iTunes Junk *submodules* also affects their standalone module scans.
- **Run** completes the cleanup and starts the maintenance tasks.
- During the first Smart Scan, CleanMyMac X registers its components in System Settings, so the app appears in the FDA list. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/full-disk-access
- In the CleanMyMac X **Menu**, the disk monitor's **Free Up** button instantly starts Smart Scan. This is an extra entry point. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/ram-monitoring (search excerpt)
- **(added in fact-check)** X 4.6.9 also added a **Scan All** option to the app's **Action** menu. VERIFIED-direct: DevMate 4.6.9 release notes. The note does not explain it. Presumably it runs every module's own scan rather than the curated Smart Scan subset (INFERRED). Implication (INFERRED): keep two levels. "Checkup" is the safe subset that can pre-select. A separate "Scan everything" command fills each module's results for review but never pre-selects beyond each module's own defaults.

### 3.3 Edition differences that change the flow

VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans and https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features

- **App Store edition.**
  - No Maintenance tasks.
  - No Updater/Agent background components.
  - System Junk in Smart Care lacks **Broken Login Items** and **Deleted Users**. Broken Preferences and Document Versions remain.
  - No Photos or Gemini trash categories.
  - X's Smart Scan swapped Speed for Large & Old Files.
- **Implication for us (INFERRED).** We ship outside the App Store (Developer ID, or a local build for one Mac mini). We can implement the full set, including root tasks through our own helper.
  - **(added in fact-check)** Staying unsandboxed is a hard requirement for the "quit apps" flow too. Apple documents that `NSRunningApplication.terminate()` returns `false` when called from a sandboxed app. VERIFIED-direct: Apple docs JSON for `NSRunningApplication.terminate()`.

---

## 4. Safety logic: what is pre-selected vs. what needs review, and why

### 4.1 Documented rules

| Rule | Source | Status |
|---|---|---|
| By default only **automatically generated system/app data** is offered for removal. User files are never touched unless the user chooses. | Smart Care KB; https://macpaw.com/how-to/is-cleanmymac-safe | VERIFIED |
| **Safety Database**: list of items, rules and exceptions consulted on every scan. Includes protected locations (e.g. it won't go into `/Library` or `/System/Library` wholesale; the Shredder refuses critical folders). Also app-specific exceptions where "cache" holds real data (example: **Spotify offline music** lives in caches). | https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database | VERIFIED |
| **Document Versions**: never the earliest or latest version. Auto-select only versions created less than 4 h apart, keeping the latest in each range. | https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk | VERIFIED |
| **iOS device backups**: the most recent backup is never auto-selected. | same | VERIFIED |
| **Downloads (System Junk)**: Safari, only broken downloads auto-selected. Slack, broken downloads plus files at least 1 month old. | same | VERIFIED |
| **Mail attachments**: smart selection only flags attachments recoverable by reopening the mail (Mail/Spark) or Outlook "Repair Folders". Edited attachments are labelled "changed by user" and not selected. | https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments | VERIFIED (German KB) |
| **Protection**: all found threats auto-selected ("Remove" works without review; "Review" lets you inspect first). | https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal | VERIFIED |
| **Ignore List**: items never shown in results. Categories: Cleanup (System Junk, Mail Attachments), Protection (Malware Removal), Applications (Uninstaller, Updater), My Clutter (Duplicates, Similar Images, Downloads). Add via Control-click → **Add to Ignore List** (documented for X); manage on the **Ignore List** tab. | https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety, https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-safety | VERIFIED |
| **Browser data needs the browser closed.** The Privacy module prompts the user to quit a running browser. Privacy is *not* part of Smart Care. | https://macpaw.com/support/cleanmymac/knowledgebase/privacy | VERIFIED |
| **CLI parity**: protected system locations are excluded. Age-based pre-selection: artifacts older than 7 days are preselected, newer ones visible but unchecked. Explicit confirmation required; `--force` skips it. | https://github.com/MacPaw/cleanmymac-cli (README and wiki "Safety-and-Privacy") | VERIFIED-direct |
| Older CleanMyMac 3 pre-selected **Language Files** and **Universal Binaries** in System Junk (not documented as part of Smart Care). | https://tidbits.com/2015/08/28/save-space-and-uninstall-apps-with-cleanmymac-3/ | VERIFIED (old version) |
| **(added in fact-check)** **Keep the cache folder, delete its contents**: "Empty 'Caches' folders are kept for correct functioning of Sandboxed Apps". | https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html (CleanMyMac Classic 1.10.9) | VERIFIED-direct (old version; still sound practice) |
| **(added in fact-check)** App-specific exceptions grow from bug reports. Examples: cache cleanup "broke Ableton Preferences" (fixed in X 4.6.9); cleanup forced VLC to rebuild its font cache (fixed in Classic 1.10.6); the Safety Database was updated "to support the latest version of Photos" (X 4.4.2). | DevMate release notes for 4.6.9, 4.4.6 (cumulative) and Classic 1.11 (URLs in §2) | VERIFIED-direct |

### 4.2 Why Smart Care can be "select all by default"

INFERRED. Smart Care can pre-select everything only because its scope was trimmed to categories where wrong deletions are cheap:

- caches and logs regenerate;
- Trash is already user-discarded;
- mail attachments can be re-downloaded;
- duplicates leave one copy;
- malware is malware;
- app updates are reversible-ish;
- DNS flush is harmless.

Everything personal or irreversible lives in separate modules that require explicit review. **We should copy this architectural principle, not the UI.**

### 4.3 Our selection policy

INFERRED / recommended. Four tiers, encoded in data, not UI.

| Tier | Meaning | In Checkup? | Default | Examples |
|---|---|---|---|---|
| T0 `protected` | Never offered. Blocklisted paths, SIP areas, ignore-list items, running-app live caches. | Never shown | n/a | `/System`, `/usr`, `/bin`, `/sbin`, `/Library` root, `~/Library/Mobile Documents`, Keychains, Mail store, Photos library, `~/Library/Application Support/<app>` databases |
| T1 `autoSafe` | Regenerable or already discarded | Yes | **Checked** | `~/Library/Caches/*` (minus exceptions), `~/Library/Logs/*`, `/Library/Logs/*` (root), broken login items, broken prefs (unparseable plists), Trash contents, Mail Downloads not modified, `/private/var/folders/.../C/` stale temp |
| T2 `recommended` | Low risk but user-visible effect | Yes | **Checked**, with an explanation row | exact duplicates in ~/Downloads (keep one), app updates, maintenance tasks, malware threats |
| T3 `reviewOnly` | Personal / irreversible / ambiguous | **No**; only in the dedicated module | Unchecked | language files, universal-binary thinning, iOS backups, document versions outside the 4 h rule, large & old files, similar images, browser history/cookies, Xcode archives, Deleted Users |

Rules (INFERRED):

- **Age gate.** A cache/log item modified within the last *N* minutes (default 60) is downgraded to unchecked "in use / recent". This mirrors the CLI's 7-day artifact rule at smaller scale.
- **Open-file gate.** Skip any item held open by a process (`lsof`/`proc_pidfdinfo`). Skip `~/Library/Caches/<bundle-id>` while its owner app is running.
  - Mole documents why: deleting a live SQLite cache can make the owning helper write to unlinked files until the disk fills. VERIFIED-direct: https://raw.githubusercontent.com/tw93/Mole/main/SECURITY_AUDIT.md
  - Re-confirmed in the fact-check. Mole adds three details:
    - The example was Autodesk Fusion's background helpers.
    - The probe is tri-state: "could not tell" counts as running.
    - The SQLite base file plus its `-wal`/`-shm` companions are checked together with one `lsof` call. The check runs again at the deletion sink, so a helper that launches after sizing still blocks deletion.
- **Keep containers, delete contents (added in fact-check).** For `~/Library/Caches/<id>` and similar folders, remove the *children* and keep the (now empty) folder. Sandboxed apps expect it to exist. This mirrors MacPaw's long-standing rule (§4.1).
- **Cleanability pre-filter (added in fact-check).** Drop at scan time anything the deleting process cannot actually remove, so it never inflates the tile's number. Examples: root-owned children of system caches when the helper is unavailable, and SIP/data-vault-protected `~/Library/Caches/com.apple.*` directories. Mac Sai documents exactly this filter. VERIFIED-direct: https://raw.githubusercontent.com/iliyami/MacSai/main/README.md.
- **Exceptions DB.** A JSON rules file (our "safety DB") with protected subpaths, e.g.:
  - Spotify `PersistentCache/Storage`;
  - browser profile `Service Worker/CacheStorage` (may hold offline web-app data);
  - Adobe/Steam large caches kept unchecked.
- **Duplicates.** Only full-content (SHA-256) matches are eligible. Keep the oldest creation date, or the name without a ` (1)` / ` copy` suffix. Never auto-select when *all* copies are in the same folder with different names and identical dates; leave that to review.
- **User files go to Trash (`FileManager.trashItem`), junk is deleted.** Caches, logs and temp files are unlinked permanently, as cleaners do. Duplicates, and anything under `~/Downloads`, `~/Documents` or `~/Desktop`, go to the Trash so they can be undone. Malware is quarantined (moved to an app-owned quarantine folder with metadata), then deleted after 30 days.

---

## 5. The exact user journey, screen by screen

**Journey at a glance (added in fact-check).** Each step is tagged with how well it is supported; the detail follows in Screens 0–9.

1. **Open.** The app (or a deep link / menu-bar button) lands on the one-click screen. VERIFIED for 5.x (opens on Smart Care). The `cleanmymac5:///modules/smartCare` deep link is INFERRED (third-party).
2. **Pre-flight.** FDA and helper status are checked. Without FDA the scan is incomplete; the Agent is installed with an admin prompt. VERIFIED (KB).
3. **Scan.** Press the single **Scan** button. Modules run "one by one". In X, the button turned into **Stop**. VERIFIED for X; INFERRED for 5.x.
4. **Results.** One tile per area, each with a metric. All tiles are selected by default; clearing a tile's checkmark skips it. Tiles excluded in Settings appear dimmed. Each tile has **Review**. **Start Over** sits top-left (with confirmation). VERIFIED (Smart Care KB).
5. **Review (optional).** Drill into a tile to adjust items. Smart-selection rules decide what is checked. Changes in X's Smart Scan applied to that run only; permanent exclusions live in Settings → Scanning, and per-item exclusions in the Ignore List. VERIFIED (KBs).
6. **Run.** One primary button executes everything selected. VERIFIED.
   - Quit prompts are UNVERIFIED for Smart Care.
   - Admin authentication goes through the already-installed Agent. VERIFIED.
7. **Completion.** A summary of what was cleaned or fixed. The 5.x layout is UNVERIFIED; the CLI analogue is "<size> cleaned!" plus "<n> items removed". VERIFIED-direct.
8. **Afterwards.**
   - Mac Health and Assistant update. VERIFIED (KB).
   - Reminders return on the configured cadence: weekly or bi-weekly is recommended. VERIFIED (X KB).
   - There is no unattended auto-run in the consumer app. INFERRED (§6.1).

Below, "Vendor" describes what CleanMyMac does (with status). "Ours" is our recommended equivalent.

### Screen 0: entry points

- **Vendor.**
  - App launch opens Smart Care by default. VERIFIED: Forbes; MacStories.
  - Other routes in: the Assistant's reminders. VERIFIED: PR Newswire.
  - Menu-bar app notifications and reminders. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu
  - In X, the Menu's disk monitor **Free Up** started Smart Scan. VERIFIED: ram-monitoring KB excerpt.
  - Health Monitor warnings (low disk, high memory, unresponsive apps). VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes
- **Ours (INFERRED).**
  - (a) Main window opens on Checkup.
  - (b) Menu-bar extra with a "Run Checkup" button and a last-checkup age.
  - (c) Reminder notification with a "Scan Now" action.
  - (d) URL scheme `ourapp://checkup?autostart=1` and an App Intent "Run Checkup" for Shortcuts/Siri.
  - (e) Keyboard shortcut ⌘R on the Checkup screen (Mac Sai uses ⌘R for scan and ⌘K for clean; VERIFIED-direct: https://raw.githubusercontent.com/iliyami/MacSai/main/README.md).

### Screen 1: Checkup home (idle)

- **Vendor.**
  - Large hero area with an illustration and one primary **Scan** button.
  - X design notes: the "big scan button is not symmetrical and goes beyond the application" window, and superellipse shapes are everywhere. VERIFIED: https://www.behance.net/gallery/141590791/CleanMyMac-X-Product-Design
  - A warm pink/blue colour spectrum during scanning and cleaning. VERIFIED: https://www.red-dot.org/project/cleanmymac-x-55187
  - Parallax animation, hover effects, atmospheric sounds, glass-like icons. VERIFIED: https://macpaw.com/news/cleanmymac-if-design-award
  - 5.x is "3D-animated" with a tile layout. VERIFIED: 9to5Mac, PR Newswire.
  - In X, VoiceOver users found the first-launch buttons hard to reach. VERIFIED: https://afb.org/aw/21/6/17076
- **Ours (INFERRED).** Use an original visual identity; do not imitate MacPaw's gradient, button shape, illustrations or sounds. Content:
  - title ("Checkup") and a one-line subtitle listing the five areas;
  - one prominent **Scan** button (default button, Return key);
  - footer chips showing *last checkup: 6 days ago · freed 3.2 GB*;
  - small "Customize…" link to Settings → Checkup;
  - a banner if FDA or the helper is missing (see Screen 2).
  - Every control gets an accessibility label and is reachable by keyboard.

### Screen 2: pre-flight / permission gating (first run or when lost)

- **Vendor.**
  - FDA is needed for full scans. Without it, CleanMyMac "cannot scan all areas".
  - The KB tells users to open Smart Care and click Scan, then grant FDA in System Settings → Privacy & Security → Full Disk Access (Touch ID/password).
  - The helper "Agent" is installed via its own admin-password prompt (macOS treats it as a helper tool, not a background item).
  - The Menu and Health Monitor are background items under General → Login Items & Extensions → Allow in the Background.
  - The app monitors these and notifies if they get disabled.
  - VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access, https://macpaw.com/support/cleanmymac/knowledgebase/background-items, https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items
- **Ours (INFERRED).**
  1. Detect FDA by attempting a read of a TCC-protected path, e.g. `~/Library/Safari/Bookmarks.plist`, or a `stat` on `~/Library/Mail`. If missing, show a sheet with a deep link. **(corrected)** On macOS 13+ (System Settings), open `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles` first. Fall back to the legacy `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, which many apps still use as a second candidate.
     - VERIFIED-direct (common practice in open-source code, not Apple-documented): e.g. https://github.com/viticci/remctl/blob/main/remctl-permissions.swift, https://github.com/lobehub/lobehub (`apps/desktop/src/main/utils/permissions.ts`).
     - Apple does not document these URLs, so always fall back to opening System Settings plainly. INFERRED.
  2. **Do not block the scan without FDA.** Run in "limited" mode and mark affected tiles with a "Limited — grant Full Disk Access for complete results" badge.
  3. Register the privileged helper with `SMAppService.daemon(plistName:)` (macOS 13+). If it is not approved, root-only items (system logs, `/Library/Caches`, DNS flush) appear as "Requires helper" and are unchecked.
     - **(added in fact-check)** Apple requires the plist to live in the app's own `Contents/Library/LaunchDaemons/`. A launch agent goes in `Contents/Library/LaunchAgents/`. A login-item helper app goes in `Contents/Library/LoginItems/`, registered with `SMAppService.loginItem(identifier:)`. All are macOS 13+. VERIFIED-direct: Apple docs JSON for `SMAppService.daemon(plistName:)`, `.agent(plistName:)`, `.loginItem(identifier:)`.
     - MacPaw itself still uses the older blessed-helper layout (§1 item 13). We should not copy that: `SMJobBless` is deprecated since macOS 13.
  4. Re-check permissions on every app activation (`NSApplication.didBecomeActiveNotification`).

### Screen 3: scanning (progress)

- **Vendor.**
  - The modules run "one by one". VERIFIED (Smart Care KB).
  - X scanned in three stages: Cleanup, then Protection, then Speed. VERIFIED: https://macpaw.com/cleanmymac-x/smart-cleanup
  - During the scan the Scan button becomes a **Stop** button (VoiceOver announced "Pressed, Stop" in X). VERIFIED: https://afb.org/aw/21/6/17076
  - Typical duration is about 1 minute; it may take longer on older or heavily used Macs (§8).
  - No source describes 5.x progress copy or whether partial results display. UNVERIFIED.
  - **Fact-check update (weak evidence, INFERRED).** A third-party clone's design spec was written from CleanMyMac 5 reference screenshots: https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/e71f840ac5bb50f43199030b4e4308563ebad0de/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md. It describes the 5.x idiom this way:
    - one large circular primary action per screen, which spins a ring while busy and "can become Stop";
    - a **Cleanup** scanning screen with a progress headline and a list of categories that gain check marks as each finishes, plus a **Stop** control;
    - **Start Over** placed in the title strip at top-left.
  - That suggests 5.x shows per-category completion live (checkmarks) rather than a live file count. It also suggests a Stop control exists during module scans.
  - This is a clone's reading of screenshots, not vendor documentation, and it covers the Cleanup module rather than Smart Care. Treat it as a hint only. X's Smart Scan Stop button remains the only documented case.
- **Ours (INFERRED).**
  - A five-step horizontal (or vertical) stepper: Cleanup · Protection · Performance · Applications · Clutter. Each step shows idle, spinning, done (with metric), skipped (dimmed) or limited (badge).
  - A live line underneath ("Scanning ~/Library/Caches…", throttled to about 10 updates/s) and a running "found so far: 2.4 GB".
  - **Stop** button in place of Scan; Esc and ⌘. also stop. Stop cancels the `Task` tree. Modules already finished keep their results, and the user lands on a results screen with unfinished modules marked "Not scanned — Scan again".
  - Internally, run the IO-bound modules concurrently with bounded concurrency (Cleanup, Clutter hashing, Applications network checks) while the UI animates sequentially. Users get a "one by one" narrative with less wall-clock time.
  - Prevent sleep during scan and run: `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason:)`.
    - Fact-check: both options and `beginActivity(options:reason:)` exist (macOS 10.9+). Call `endActivity(_:)` with the returned token when done. VERIFIED-direct: Apple docs JSON.
    - In Foundation's headers, `.userInitiated` already includes `.idleSystemSleepDisabled`, so the second flag is redundant but harmless. INFERRED.

### Screen 4: results (the decision screen)

- **Vendor.**
  - Tiles, one per module, each with its metric:
    - Cleanup: size;
    - Protection: threat count;
    - Performance: task count;
    - Applications: update count;
    - My Clutter: duplicate count.
  - Each tile has a **Review** button.
  - All tasks are selected by default; clearing a tile's checkmark skips it.
  - Excluded modules show **dimmed** tiles.
  - **Start Over** in the upper-left (with a confirmation) discards the results and returns to Scan.
  - Primary button **Run**.
  - VERIFIED: Smart Care KB.
  - Reviewers describe a single screen you can approve wholesale or review item by item. VERIFIED: https://thehightechsociety.com/cleanmymac-review/ (search excerpt)
  - Exact empty-state strings (e.g. no threats) are UNVERIFIED.
- **Ours (INFERRED).** Layout:
  - Header: "Checkup found 4.8 GB to clean, 0 threats, 2 tasks, 3 updates, 12 duplicates". Show only the parts that are non-zero.
  - 5 cards in a grid. Each card has:
    - a checkbox (top-right, bound to "include in Run");
    - the area name;
    - a big metric;
    - a one-line explanation;
    - a **Review** button;
    - badges (Limited, Requires helper, Skipped in Settings).
  - Card states:

    | State | Visual | Checkbox | Copy (original) |
    |---|---|---|---|
    | Has findings | Normal | On | "4.1 GB of caches, logs and Trash" |
    | Nothing found | Normal, success glyph | Off and disabled | "Nothing to clean" / "No threats found" / "All apps up to date" / "No duplicates in Downloads" / "No tasks due" |
    | Excluded in Settings | Dimmed | Disabled | "Skipped — turned off in Settings" plus an "Enable" link |
    | Not scanned (stopped/failed) | Dimmed with warning | Disabled | "Not scanned" plus "Scan" |
    | Limited | Normal plus badge | On | "Partial results — grant Full Disk Access" |
    | Threats found | Accent warning | On (locked on unless reviewed) | "2 threats — will be removed" |

  - Footer bar:
    - left: **Start Over** (confirmation alert: "Discard these results and scan again?" with Scan Again / Cancel);
    - centre: "Selected: 4.1 GB · 2 tasks · 3 updates";
    - right: primary **Run** (disabled when nothing is selected).
  - Freshness: if results are older than 15 minutes when the user clicks Run, auto-rescan the selected modules first (files change). Show "Refreshing results…".

### Screen 5: review drill-down (per tile)

- **Vendor.**
  - "Review" opens the module's detail with categories and items, checkboxes and sizes. Users deselect or select items.
  - Smart selection for duplicates is available in that module.
  - Items can be added to the Ignore List by Control-click (X).
  - X: "Review Details" opened a list of the items found by the Cleanup/Protection scanners. VERIFIED (Smart Scan KB).
  - System Junk review groups items by type and sorts them; some items are smart-selected. VERIFIED (system-junk KB).
- **Ours (INFERRED).** A pushed (NavigationStack) or sheet view.
  - **Two-pane.** The left pane lists categories with tri-state checkboxes and sizes (e.g. User Caches, System Logs, User Logs, Broken Login Items, Broken Preferences, Mail Downloads, Trash: Startup Disk, Trash: External "Backup"). The right pane lists items with checkbox, icon, name, path (truncated middle), size and last modified, plus a reason tag for unchecked items ("in use", "modified recently", "changed by user", "most recent backup").
  - **Toolbar:** search field, sort menu (Size/Name/Date), "Select: All / None / Recommended" menu, "Reveal in Finder" (⇧⌘R, so it doesn't collide with ⌘R = Scan), Quick Look (Space).
  - **Context menu:** Reveal in Finder, Quick Look, **Ignore** (adds to the Ignore List and removes the item from the results), Copy Path.
  - **Footer:** "Back to results" (keeps edits) and the selected-total live counter. There is no separate "Clean" button here: Run stays on the results screen to keep one decision point. (In the standalone module views, a Clean button is appropriate.)
  - **Protection review:** a threat list with name, type (adware, PUA, trojan…), path(s) and launch-item linkage. Default all checked. Unchecking requires a confirmation ("Keep this item? It was flagged as …").
  - **Applications review:** app icon, current → new version, source (Sparkle / Homebrew cask / App Store / vendor), release notes disclosure, and a "Running" badge.
  - **Performance review:** task rows with description, last-run date (X showed last run dates; VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance) and a "Requires admin" badge.

### Screen 6: pre-run confirmation and conflicts

- **Vendor.**
  - **Apps that must be quit.** For Smart Care specifically there is no documentation. UNVERIFIED.
  - Related documented behaviors:
    - the Privacy module prompts to close running browsers before cleaning (VERIFIED: privacy KB);
    - the Uninstaller's "Quit Application" dialog gained a **Skip** option (VERIFIED: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html). **(corrected)** The fact-check fetched this page. It covers **CleanMyMac Classic 1.x** (c. 2010–2012, "Restricted maximum supported OS to 10.8.x"), not CleanMyMac X or 5. It shows that MacPaw has long used a quit dialog with a Skip choice, but says nothing about current Smart Care;
    - Mole's `optimize` prints a "Close these apps before database optimization: Safari" step, which shows a quit-before-task pattern in a modern cleaner. VERIFIED-direct: https://raw.githubusercontent.com/tw93/Mole/main/README.md (third-party; added in fact-check);
    - third-party guides note CleanMyMac may ask to quit apps and advise saving work first (VERIFIED: https://setapp.com/how-to/delete-app-from-mac-that-wont-delete).
  - **Admin password.** The helper install prompts for the macOS admin password, typically the first time root cleanup is needed. VERIFIED: https://www.justanswer.com/mac-computers/l99f0-app-needs-install-helper-won-t-accept-admin.html (third-party Q&A). Re-authentication is available from the Action menu → Authenticate (X). VERIFIED: https://talk.macpowerusers.com/t/cleanmymac-x-permission-issue/17372 (forum)
- **Ours (INFERRED).** Before executing:
  1. **Build a conflict list** from the selection:
     - app updates whose app is running;
     - cache folders whose owner bundle ID is running (if not already auto-excluded);
     - Mail attachments while Mail is running (safe, but notify).
  2. If the list is non-empty, show a **"Some apps are open"** sheet:
     - list of app icons and names, each with a per-app toggle;
     - copy: "Quit these apps to finish the selected tasks. Unsaved changes may be lost.";
     - buttons: **Quit & Continue** (default), **Skip These Items**, **Cancel**.
     - Quit uses `NSRunningApplication.terminate()` (polite; apps can show save dialogs). Wait up to 20 s per app via KVO on `isTerminated`. If an app refuses, mark its items "Skipped — app still open". **Never `forceTerminate()`** without a second explicit confirmation.
     - Fact-check: `terminate()`, `forceTerminate()` and `isTerminated` all exist (macOS 10.6+). Apple documents three caveats: `terminate()` may return before the app exits, so you must observe `isTerminated`; it returns `false` if the app is already gone; and it returns `false` from a sandboxed caller. VERIFIED-direct: Apple docs JSON.
  3. If the selection includes root items and the helper isn't approved, show a one-time "Approve the helper" explanation. If declined, skip root items.
  4. Optional power-user setting "Confirm before Run" (off by default, since the results screen *is* the confirmation, matching the vendor's one-click model).

### Screen 7: running (execution)

- **Vendor.** Run "completes the cleanup and starts maintenance tasks" (X). In 5.x it "completes the Smart Care tasks". No documentation of progress UI or cancellation during Run. VERIFIED/UNVERIFIED as stated.
- **Ours (INFERRED).**
  - Same five-step stepper, now in "executing" mode, each with a progress ring and a running "Freed 1.2 GB".
  - Order: **Protection first** (remove threats before anything else touches their files), then Cleanup, Clutter, Performance, and Applications last. Updates are the slowest and network-bound, and app relaunches shouldn't disturb cleanup.
  - **Stop.** Allowed between items. Mac Sai's model is chunked deletion (5k-item chunks) with a cancellation check between chunks. **(corrected)** The "returns to idle within about a second" figure in Mac Sai's README refers to **scans** being cancelled, not to deletion. VERIFIED-direct: Mac Sai README. Already-deleted items stay deleted. The summary reports partial completion.
  - Never interrupt mid-file. App updates in progress finish or roll back atomically: download to a temp dir, verify the signature, then swap the bundle.

### Screen 8: completion summary

- **Vendor.**
  - No source documents the 5.x completion screen's wording or layout. UNVERIFIED.
  - MacPaw's CLI shows: "Cleanup complete!", then per-category ✓ lines with sizes, a big "<size> cleaned!" figure, "<n> items removed", and tips (how to protect a path, how to skip confirmation). VERIFIED-direct: https://github.com/MacPaw/cleanmymac-cli
  - Partial failures appear in a cleanup log; users have reported "This item was cleaned partially." VERIFIED: https://talk.macpowerusers.com/t/cleanmymacx-error-while-cleaning-up-system-junk/13096 (forum)
- **Ours (INFERRED).**
  - Hero metric "Freed 4.1 GB" (sum of actually-removed bytes, measured by the pre-delete allocated size of items that succeeded). Also show the free-space delta from `volumeAvailableCapacityForImportantUsageKey` before and after, as Mole does ("Free space: … (+4.5GB)"; VERIFIED-direct: Mole README, re-confirmed in the fact-check).
    - Fact-check: `volumeAvailableCapacityForImportantUsageKey` (macOS 10.13+; Apple: available capacity "for storing important resources") and `volumeAvailableCapacityKey` (10.6+; raw available capacity) both exist. VERIFIED-direct: Apple docs JSON.
    - Apple flags both as fingerprinting-sensitive "required reason" APIs, which need a privacy-manifest declaration if we ever ship through the App Store. VERIFIED-direct: same.
    - In practice the "important usage" figure is larger because it counts purgeable space. Use one key consistently for before and after. INFERRED.
  - Per-area result rows: "Cleanup — 3.9 GB removed (1,204 items)", "Protection — 2 threats removed", "Performance — 2 tasks done", "Applications — 3 apps updated", "Clutter — 12 duplicates moved to Trash (180 MB)".
  - Skipped/failed rows are collapsible: "8 items skipped (in use)", "1 update failed — Retry". "View Log" opens the activity log (per-item path and error; prune after 30 days, as Mac Sai does).
  - Buttons: **Done** (returns to the home screen, updating "last checkup" and the health status), and **Undo duplicates** (restores from Trash, available only until the Trash is emptied).
  - Persist a `CheckupReport` (date, durations, bytes per module, counts, failures) for history, the menu bar and the reminder logic.

### Screen 9: after the run

- **Vendor.** The Mac Health score (5 steps, Excellent → Critical; factors include malware, disk health, battery health, low disk space) and the Assistant recommendations update. A reviewer felt the score mostly reflected scan recency. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/mac-health; https://www.softwarehow.com/cleanmymac-review/
- **Ours (INFERRED).** Update the health status in the sidebar and menu bar. Clear the "checkup due" badge. Reschedule the next reminder.

---

## 6. Scheduling, reminders and notifications

### 6.1 Vendor facts

- **Recommended frequency.** Smart Scan weekly for heavy daily use, about every 2 weeks for lighter use. Deep malware scan at least monthly. The malware database updates every 7–10 days. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/how-often-run-cleanup-scans
- **Reminder frequency is adjustable** on the **Notifications** tab of Preferences. Older versions had a "Scheduler" tab with options from weekly to annually. Reminders can be turned off. VERIFIED: same, plus https://macpaw.com/support/cleanmymac-3/knowledgebase/notifications
- **Menu-bar reminders.**
  - Weekly cleanup reminders, tips about unused features, and a prompt to fully uninstall apps dragged to the Trash.
  - Alerts for an overfilled Trash and cluttered drives, including external drives.
  - Low-RAM warnings.
  - Configurable from the Menu or Preferences → Notifications.
  - VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu
- **Health Monitor (background item).** Notifies about low disk space, high memory usage and unresponsive apps. Powers real-time malware monitoring. VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes
- **Assistant.** Personalized suggestions and reminders of "scheduled maintenance". In X it could be silenced via Preferences → Assistant, and its yellow buttons marked the most relevant tasks. VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-assistant; PR Newswire.
- **Notification Center (5.6.0)**, opened from a bell icon, keeps messages. VERIFIED: https://macpaw.com/cleanmymac/whats-new
- **Business-only automation** (discontinued; sunset 14 Jul 2026). VERIFIED: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation
  - Smart Scan task with a start date/time.
  - Repeat every 7, 14 or 30 days.
  - Forced-execution day/time if the user skips.
  - 0, 1 or 2 reminders before forced execution.
  - Selectable junk types: System log files, Broken login items, User cache files, Language files, Broken preferences, Xcode junk, Mail attachments, Trash bins.
  - Start date and interval cannot be edited after creation.
- **Consumer auto-run.** No documented automatic Smart Care execution in the consumer app. UNVERIFIED that none exists; one Setapp review mentions a user setting reminders every 3 days. VERIFIED: https://setapp.com/how-to/best-mac-cleaner-software
- **Process-level evidence (added in fact-check).**
  - The Homebrew cask's uninstall stanza lists every background job CleanMyMac 5 installs: `com.macpaw.CleanMyMac5.HealthMonitor` and `com.macpaw.CleanMyMac5.Menu` (launchctl), a per-user `com.macpaw.CleanMyMac5.Updater` LaunchAgent, and the root `com.macpaw.CleanMyMac5.Agent` daemon. There is **no Scheduler job**.
  - By contrast, the CleanMyMac X (Chinese edition) cask lists a `com.macpaw.zh.CleanMyMac4.Scheduler` launchd job, plus a `…scheduler.sfl*` recent-documents file.
  - VERIFIED-direct: https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb and https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb.
  - INFERRED from this: 5.x has no separate scheduler process. Reminders and alerts are most likely posted by HealthMonitor or Menu, which is consistent with "reminders only, no unattended Smart Care runs".
- **Actionable notifications (added in fact-check).** X 4.6.2 added "Freeing up RAM right from the notification when your Mac's running out of memory". So MacPaw's notifications carry action buttons that run a task directly. VERIFIED-direct: DevMate release notes 4.6.9 (cumulative). Whether 5.x reminders have a "Scan" action is UNVERIFIED.

### 6.2 Our design

INFERRED.

- **Settings → Checkup → Schedule.**
  - Reminder: Off / Every 3 days / Weekly (default) / Every 2 weeks / Monthly.
  - Preferred time (default 10:00).
  - Option "Scan automatically in the background and notify me with results". **Never auto-run cleanup by default.**
  - Opt-in "Auto-clean Tier-1 items only" for power users, clearly labelled.
- **Mechanism.**
  - In-app: `NSBackgroundActivityScheduler` (identifier `com.ourapp.checkup.reminder`, `interval` = chosen period, `tolerance` = 1 h, `qualityOfService = .utility`, `repeats = true`). It fires only while the app or agent process runs.
    - Fact-check: these properties exist (macOS 10.10+). Apple's defaults are `repeats = false`, `tolerance` = half the `interval`, and `qualityOfService = .background`. The identifier must be a non-empty reverse-DNS string that stays constant across launches. Setting the values explicitly, as above, is therefore required. VERIFIED-direct: Apple docs JSON.
  - To fire while the main app is closed, ship a lightweight **login agent** (menu-bar helper). The agent owns the scheduler and posts notifications. **(corrected)** Register it with one of:
    - `SMAppService.loginItem(identifier:)` for a helper *app* in `Contents/Library/LoginItems/`;
    - `SMAppService.agent(plistName:)` for a launchd agent in `Contents/Library/LaunchAgents/`.
    - `SMAppService.mainApp` registers the *main app itself* as a login item. Use it only if the main app is the menu-bar extra.
    - VERIFIED-direct: Apple docs JSON.
  - Persist `lastCheckupDate` and `nextReminderDate` in shared `UserDefaults(suiteName:)` (App Group) so the main app and agent agree.
- **Notification** (`UNUserNotificationCenter`).
  - Category `CHECKUP_DUE`, actions **Scan Now** (foreground, opens the app with autostart), **Remind Me Tomorrow** and **Turn Off Reminders**.
  - For background-scan results: category `CHECKUP_RESULTS`, body "4.2 GB can be cleaned · 0 threats", actions **Review** and **Later**.
  - Respect Focus (use `.timeSensitive` only for threats found).
    - Fact-check: `UNNotificationInterruptionLevel.timeSensitive` is macOS 12+ and can break through Focus and Notification Summary. VERIFIED-direct: Apple docs JSON.
    - It also needs the Time Sensitive Notifications capability (`com.apple.developer.usernotifications.time-sensitive` entitlement), and users can turn it off per app. INFERRED from Apple platform practice. Without the entitlement, fall back to `.active`.
  - Throttle health alerts (low disk below 10% / 10 GB, sustained memory pressure) to at most one per type per 24 h (Mac Sai does throttled opt-in health alerts; VERIFIED-direct).
- **Skip logic.** If a Checkup was run manually within the reminder interval, push the reminder back. Never remind while on battery below 20% (not relevant for a Mac mini, but keep it generic) or during a full-screen app or presentation (`CGSessionCopyCurrentDictionary` / Focus status).

---

## 7. Settings that drive the flow

| Vendor setting | Location | Status | Our equivalent (INFERRED) |
|---|---|---|---|
| Smart Care module/category/group inclusion tree | Settings → **Scanning** → Smart Care | VERIFIED (Smart Care KB) | Settings → Checkup → "Include in Checkup" tree with tri-state checkboxes. Persist as a set of disabled node IDs. Excluded nodes render as dimmed tiles/rows. |
| X: Preferences → Scanning (Smart Scan modules; Speed tasks) | Preferences | VERIFIED (Smart Scan KB) | same tree |
| Ignore list per module | Settings → **Ignore List** | VERIFIED (safety KB) | Settings → Ignored Items, grouped by area; add from any review context menu. Stored as canonical paths and bundle IDs. Applies before results are computed. |
| Protection scan locations (DMG affects Smart Care; email attachments need FDA) and scan mode Quick/Balanced/Deep | Settings → **Protection** | VERIFIED: protection-scan-options KB; malware-removal KB | Settings → Protection. Checkup always uses Quick plus the chosen extra locations. |
| Notifications / reminder frequency | Preferences → **Notifications** | VERIFIED (X) | Settings → Notifications plus Checkup → Schedule |
| Menu on/off | Preferences → **Menu** tab | VERIFIED (X Menu KB) | Settings → Menu Bar |
| Assistant on/off | Preferences → **Assistant** (X) | VERIFIED | Settings → Suggestions |

---

## 8. Scan duration: evidence and our budget

| Source | Machine / OS | Measurement | Status |
|---|---|---|---|
| allaboutcookies.org review | macOS Tahoe test Mac | Smart Care **54 s** (Protection scan 44 s) | VERIFIED (search excerpt): https://allaboutcookies.org/cleanmymac-x-review |
| Review (2021 MacBook Air) | M1 | Smart Scan ≈ **1 min**, found >7 GB junk, no threats | VERIFIED (search excerpt) |
| Several reviews | various | "about 2 minutes" / "a couple of minutes" | VERIFIED (search excerpts) |
| Older review | Intel, HDD era | ~10 min | VERIFIED (search excerpt, old) |
| MacPaw KB | any | "may take a while, especially on older or heavily used Mac computers" | VERIFIED |
| Vendor claim | M-series | malware scan 89% faster than the previous algorithm (49% on Intel) | VERIFIED (secondhand) |

**Our target (INFERRED).** On an Apple Silicon Mac mini with an internal SSD:

- Cleanup ≤ 15 s (enumerate known locations only; never walk the whole disk).
- Protection Quick ≤ 30 s (launch agents/daemons, login items, browser extensions, `/Applications` signatures, Downloads, DMGs).
- Performance ≤ 1 s (rule evaluation).
- Applications ≤ 10 s (parallel appcast fetches with 5 s timeouts; cached 6 h, like the vendor's Updater cadence of every 6 hours; VERIFIED: https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes).
- Clutter ≤ 10 s for Downloads (size bucketing, then 4 KB head/tail hash, then full SHA-256 only on collisions).
- Total ≤ 60 s.

Show an indeterminate-then-determinate progress estimate based on the last run's durations stored in `CheckupReport`.

---

## 9. Permissions, privileged helper and security lessons

- **FDA.** Required for complete results (Mail data, Trash on some volumes, Safari, etc.). VERIFIED: https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access
- **Helper ("Agent").** Performs root operations such as deleting system junk. Installed via its own prompt. VERIFIED: background-items KB.
  - The legacy (X) helper launchd plist was `/Library/LaunchDaemons/com.macpaw.CleanMyMac4.Agent.plist`, with the binary at `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac4.Agent`. The bundled copy sat in `CleanMyMac X.app/Contents/Library/LaunchServices/` (the SMJobBless layout).
  - **(corrected)** The original citation (TALOS-2018-0716) could not be confirmed to contain this path: the Talos spotlight text and CVE records name only functions. The path is instead VERIFIED-direct from independent public sources:
    - the osquery allow-list in https://github.com/chainguard-dev/osquery-defense-kit (`detection/persistence/2-unexpected-uid0-daemon-macos.sql`);
    - the X Chinese-edition Homebrew cask, which uses the same `…CleanMyMac4.Agent` pattern.
  - 5.x uses the same layout with `CleanMyMac5` (§1 item 13).
- **Security history (lessons for our helper).** VERIFIED: https://blog.talosintelligence.com/vulnerability-spotlight-cleanmymac-x/; https://www.talosintelligence.com/vulnerability_reports/TALOS-2019-0759
  - Cisco Talos (Tyler Bohan; reports numbered TALOS-2018-0705…0721; fixed in **X 4.2.0**; tested on 4.04) found that CleanMyMac X's root helper exposed generic primitives with **no validation of the calling application**. Any local process could escalate.
    - The mapping below was re-checked in the fact-check against a text mirror of the Talos spotlight (https://github.com/EFI-Demo/Endpoint-Forecasting-and-Interpreting, `CTIs/talosintelligence/talosintelligence/2019/`) and the CVE JSON records in https://github.com/CVEProject/cvelistV5. **VERIFIED-direct**:
      - `moveItemAtPath` → CVE-2018-4032. A `nil` destination deletes the file.
      - `moveToTrashItemAtPath` → CVE-2018-4033.
      - `removeItemAtPath` → CVE-2018-4034.
      - `truncateFileAtPath` → CVE-2018-4035.
      - `removeLaunchdAgentAtPath` → CVE-2018-4042.
    - **(added in fact-check)** The full list also includes:
      - `removeKextAtPath` (CVE-2018-4036);
      - `removeDiagnosticsLogs` (CVE-2018-4037), which builds a `log erase --all`-style command;
      - `enableLaunchdAgentAtPath` (CVE-2018-4041);
      - `removeASL` (CVE-2018-4043), which stops syslogd/ASL;
      - `removePackageWithID` (CVE-2018-4044), a `pkgutil --forget` wrapper;
      - `securelyRemoveItemAtPath` (CVE-2018-4045);
      - `pleaseTerminate` (CVE-2018-4046, a DoS);
      - `disableLaunchdAgentAtPath` (CVE-2018-4047).
    - These names show what MacPaw's helper actually does as root: move/trash/remove/truncate paths, erase unified logs and ASL, remove kexts and launchd items, and forget package receipts. It is a useful checklist of the root verbs our helper will need, each to be wrapped as an intent-level, validated call. INFERRED.
  - CVE-2019-5011 (X 4.20): an upgrade left the vulnerable helper components in place. VERIFIED-direct: CVE JSON record.
  - **Our rules (INFERRED).**
    - (1) The helper accepts XPC only from our signed app: `NSXPCListener.setConnectionCodeSigningRequirement(_:)` on macOS 13+ (Mac Sai does this; VERIFIED-direct).
      - Fact-check: the API name and macOS 13.0 availability are VERIFIED-direct in Apple docs JSON. The client side can also pin the helper with `NSXPCConnection.setCodeSigningRequirement(_:)` (macOS 13+).
      - Mac Sai's README calls the listener method `setCodeSigningRequirement`, which is imprecise. Apple's listener method is `setConnectionCodeSigningRequirement(_:)`.
    - (2) Never expose "delete arbitrary path". Expose intent-level verbs instead: `cleanSystemLogs(olderThan:)`, `cleanSystemCaches(items: [ScanItemID])`, where IDs map to paths the helper itself re-derives and re-validates against the blocklist.
    - (3) Resolve symlinks and re-check immediately before unlinking (TOCTOU).
    - (4) Version-check and replace the helper on every app update (`SMAppService` re-register).
    - (5) Log every root action.
- **Background items.** Expect the macOS 13+ "Background Items Added" notification for the agent. Detect disabled state with `SMAppService.status` and show a fix-it banner, as the vendor does. VERIFIED: allow-background-items KB.

---

## 10. Performance tile on macOS 14/15/26: what "maintenance" can mean

- **The vendor's Smart Care suggests "periodic maintenance scripts" plus "Flush DNS Cache".** VERIFIED (Smart Care KB).
- **macOS 15 Sequoia removed `periodic`** (its jobs moved to launchd/logd). VERIFIED: heise link above; https://discussions.apple.com/thread/255818101. Also corroborated in the fact-check (man-page mirror and forensic note; §1 item 14).
  - **(corrected)** The earlier text said "cron is present but disabled". The forensic note reports that `cron` is **present and functional** on Sequoia and Tahoe: `com.vix.cron` starts on demand when a crontab exists. It is `at` whose launchd job is disabled by default. VERIFIED-direct: https://github.com/AppliedIR/sift-mcp (`packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml`).
  - In any case we schedule with launchd/`NSBackgroundActivityScheduler`, never cron.
  - Mole's code comment says `periodic` was "removed in macOS 26+". That conflicts with the evidence above and is probably imprecise. Mole guards the task with `command -v periodic`, which is what we should do too. VERIFIED-direct: https://raw.githubusercontent.com/tw93/Mole/main/lib/optimize/tasks.sh
- **Behavior on 15+ is unclear.** It is UNVERIFIED what CleanMyMac's Performance tile shows on Sequoia/Tahoe. CleanMyMac's own 2026 blog marks the Terminal maintenance-script method "pre-Sequoia only". VERIFIED: https://cleanmymac.com/blog/how-to-run-maintenance-mac
  - **Fact-check best estimate (INFERRED).** On 15/26 the tile most likely counts only the tasks that still apply, which leaves **Flush DNS Cache** at minimum. MacPaw's 2026 CLI, built on "cleanup rules shared with CleanMyMac", offers only RAM and purgeable-space tasks in `optimize`, and no maintenance scripts. So the modern vendor set is probably DNS flush plus possibly RAM/purgeable.
  - Our implementation should compute the tile's count from tasks whose `isAvailable(on:)` and `recommendIf` are both true. If that count is 0, show the tile's "nothing due" state rather than an empty number. No vendor screenshot or KB text for 15/26 was found.
- **Our task catalogue (INFERRED).** Each task has `isAvailable(on: OperatingSystemVersion)`, `requiresRoot`, a `recommendIf` rule and a `lastRun` date.

| Task | Command / API | Root | Recommend in Checkup when |
|---|---|---|---|
| Flush DNS cache | `dscacheutil -flushcache; killall -HUP mDNSResponder` (VERIFIED as standard for Sonoma–Tahoe: https://www.namecheap.com/support/knowledgebase/article.aspx/397/2194/how-to-clear-the-local-dns-cache). Fact-check: `-flushcache` is documented in the macOS 26 `dscacheutil(1)` man page ("should only be used in extreme cases"). `mDNSResponder(8)` documents only USR1/USR2/INFO signals, so the HUP flush is long-standing practice rather than man-page documented. Mole uses exactly this pair under sudo. VERIFIED-direct: man-page mirror; Mole `lib/optimize/tasks.sh`. **(added)** Mole skips the flush while a VPN `utun*` interface is the default route, because WireGuard-style clients treat the HUP as a network change and reconnect. | yes (helper) | not run in ≥ 7 days **and no active VPN** (else show "Skipped — VPN active") |
| Maintenance scripts (macOS 14 only) | `periodic daily weekly monthly` | yes | macOS < 15 **and `periodic` exists**, and not run in ≥ 7 days; hidden on 15+ |
| Free up purgeable space | ask the system to release purgeable space by creating and deleting a temporary large file, or `tmutil thinlocalsnapshots / <bytes> 4` for local snapshots. Fact-check: the syntax `tmutil thinlocalsnapshots mount_point [purge_amount] [urgency]`, with bytes and urgency 1–4, is VERIFIED-direct from the macOS 26 `tmutil(8)` man page (mirror). The vendor had a purgeable-space task in X's Maintenance module from 4.4.1 (VERIFIED-direct, §2). | snapshots: yes | `volumeAvailableCapacityForImportantUsage − volumeAvailableCapacity` ≥ 5 GB; review-only otherwise |
| Free up RAM | `/usr/sbin/purge` (needs root) via the helper, or a non-root approach. MacPaw's CLI says its `optimize ram` needs no sudo, so MacPaw uses some non-`purge` mechanism; which one is UNVERIFIED. Alternatively, just recommend quitting the top memory apps. **(corrected)** `purge(8)` (still shipped in macOS 26) only "force[s] disk cache to be purged" and "does not affect anonymous memory" (malloc/vm_allocate). So it empties the file cache; it does not reclaim app memory. Label it honestly ("Clear file cache"). VERIFIED-direct: macOS 26 man-page mirror. Root is required on modern macOS. INFERRED/common knowledge; the man page does not say. | yes for `purge` | memory pressure "warn/critical" sustained; review-only (benefit is debatable) |
| Reindex Spotlight | `mdutil -E /` (fact-check: `-E` "will cause each local store … to be erased. The stores will be rebuilt if appropriate", VERIFIED-direct from `mdutil(1)`, macOS 26 mirror) | yes | never auto; review-only (resource-intensive; vendor KB notes it is resource-intensive) |
| Rebuild Launch Services | — | — | **do not**. **(corrected)** Mole's audit gives two separate reasons. (a) A domain-wide rebuild made a running Network Extension VPN read as reinstalled, so Mole's optimize stopped doing it. (b) Per-record `lsregister -u` returns `-10814` on macOS 15+ for apps that are already gone. The earlier wording, "breakage on macOS 15+", conflated the two. VERIFIED-direct: Mole SECURITY_AUDIT.md |

MacPaw's CLI `optimize` does only RAM ("releases inactive memory", no sudo) and purgeable ("asks macOS to release disk space already marked as purgeable"). VERIFIED-direct: cleanmymac-cli README. That suggests MacPaw's own minimal modern set is RAM plus purgeable.

---

## 11. Handling apps that must be quit: implementation detail

INFERRED, building on the documented vendor patterns in §5, Screen 6.

1. **Mapping items to owners.** Each scan item carries `ownerBundleID?`, derived from:
   - its path (`~/Library/Caches/<bundle-id>`, `~/Library/Containers/<bundle-id>`, `~/Library/HTTPStorages/<bundle-id>`, `~/Library/Saved Application State/<bundle-id>.savedState`); or
   - the rule that produced it (e.g. the Mail Downloads rule → `com.apple.mail`).
2. **Running check.** `NSWorkspace.shared.runningApplications` (GUI apps) plus `proc_listallpids`/`proc_pidpath` for helpers. Also observe `didLaunchApplicationNotification` during review: an item whose owner launches after the scan flips to "in use" in the UI.
3. **Open-file check at delete time.** Use `proc_pidfdinfo` / `lsof -F n +D <dir>` with a timeout. If the check fails or times out, treat the item as in use (fail-closed, as in Mole).
4. **Policy by item type.**
   - Caches of running apps: auto-skip silently, reason "in use". No quit prompt for junk, since asking users to quit apps to save a few MB is hostile.
   - App updates: require a quit (prompt).
   - Malware: kill the malicious process (helper), then unload its launch item (`launchctl bootout`), then remove. No prompt beyond the Run.
   - Browser data: never in Checkup.
5. **Quit dialog semantics.**
   - "Quit & Continue" calls `terminate()`, then waits.
   - If the user has unsaved docs, the app shows its own save sheet and we keep waiting until the timeout. On timeout: "Couldn't quit Pages — its update was skipped."
   - Relaunch apps that we quit for updates, if they were running before (remember `NSRunningApplication.bundleURL`).

---

## 12. Proposed data model and state machine

INFERRED. Swift 6, async/await.

```swift
enum CheckupArea: String, CaseIterable, Codable { case cleanup, protection, performance, applications, clutter }

enum SelectionTier: Codable { case protected, autoSafe, recommended, reviewOnly }

struct ScanItem: Identifiable, Codable {
    let id: UUID
    let area: CheckupArea
    let categoryID: String          // e.g. "cleanup.userCaches"
    let url: URL?                   // nil for tasks / updates
    let allocatedBytes: Int64
    let modified: Date?
    let ownerBundleID: String?
    let tier: SelectionTier
    var isSelected: Bool            // initial = tier == .autoSafe || tier == .recommended, minus gates
    var skipReason: SkipReason?     // .inUse, .recent, .changedByUser, .mostRecentBackup, .requiresHelper, .limitedAccess
}

struct AreaResult: Codable {
    let area: CheckupArea
    var state: AreaState            // .found, .nothingFound, .excluded, .notScanned, .failed(Error)
    var items: [ScanItem]
    var isIncluded: Bool            // tile checkbox; default true when .found
    var limited: Bool               // missing FDA/helper
    var duration: Duration
}

enum CheckupPhase {
    case idle(lastReport: CheckupReport?)
    case preflight
    case scanning(current: CheckupArea, progress: [CheckupArea: Double], partial: [CheckupArea: AreaResult])
    case results([CheckupArea: AreaResult], scannedAt: Date)
    case resolvingConflicts([RunningAppConflict])
    case running(current: CheckupArea, progress: [CheckupArea: Double], freedSoFar: Int64)
    case completed(CheckupReport)
}

protocol CheckupModule: Sendable {
    var area: CheckupArea { get }
    func scan(context: ScanContext, progress: @Sendable (Double, String) -> Void) async throws -> AreaResult
    func execute(_ selection: [ScanItem], context: RunContext,
                 progress: @Sendable (Double, Int64) -> Void) async throws -> AreaOutcome
}
```

- **Coordinator.** A `@MainActor @Observable final class CheckupController` holds `phase`. It owns a `Task` for the scan or run, so cancellation means `task.cancel()`. Modules call `try Task.checkCancellation()` between directories or chunks (≤ 5,000 items per chunk, as in Mac Sai).
- **Transitions.**
  - `idle → preflight → scanning → results`
  - `results → (review edits) → resolvingConflicts? → running → completed → idle`
  - `results → Start Over → scanning`
  - `scanning → Stop → results(partial)`
  - `running → Stop → completed(partial)`
- **Persistence.** `CheckupReport` is appended to a small SQLite/JSON history (last 50). Store `lastCheckupDate` and per-task `lastRun` in App Group defaults.

---

## 13. Edge cases checklist

INFERRED unless marked.

- External volumes:
  - per-volume `.Trashes/<uid>` appears as separate Trash categories (VERIFIED: trash-bins KB);
  - skip read-only and network volumes;
  - handle a volume ejected mid-scan (results row becomes "Volume unavailable").
- iCloud-evicted files in Downloads (dataless): `URLResourceKey.ubiquitousItemDownloadingStatusKey`. Never hash dataless files (that would trigger downloads); exclude them from duplicates.
- Hard links and clones: APFS clones share blocks, so "freed" bytes can be over-estimated. Use `totalFileAllocatedSizeKey` and present the sizes as "up to".
- Firmlinks and symlinks: canonicalize with `URL.resolvingSymlinksInPath()` plus a realpath check against the blocklist (Mole and Mac Sai both do this).
- Time Machine local snapshots: freed space may not appear immediately. Re-read capacity after 2 s, and explain "space may take a moment to appear" if the delta is less than expected.
- App Translocation or apps running from DMGs: exclude from updates.
- MDM-managed Macs: updates of managed apps are disabled; mark them "Managed".
- Low disk (< 1 GB free): Checkup must still work. Avoid temp-file-heavy operations and don't download updates.
- The scan finds 0 everywhere: show a celebratory but plain "Everything looks good" state, update `lastCheckupDate`, no Run button.
- Results go stale between scan and Run: re-validate each item's existence, size and owner state at delete time. Missing items count as "already gone", not failures.
- The user edits selection in review, then Start Over: the edits are lost. Warn in the Start Over confirmation if there are custom edits.
- Ignore-list paths that are parents of findings: filter by prefix on canonical paths.
- Protection finds a threat inside a selected duplicate: the Protection outcome wins, and the item is removed from Clutter.
- Multiple user accounts: only the current user's home plus system areas (with helper). "Deleted Users" stays review-only.
- **(added in fact-check)** Active VPN: skip the DNS flush and show the reason. A HUP to mDNSResponder makes WireGuard-style clients reconnect (Mole; §10).
- **(added in fact-check)** Protected Apple caches: some `~/Library/Caches/com.apple.*` folders are data-vault/SIP protected and cannot be removed even with FDA. Filter them out at scan time instead of reporting failures after Run (Mac Sai; §4.3).
- **(added in fact-check)** Sandboxed apps' cache folders: delete the contents, keep the folder (MacPaw rule since Classic 1.10.9; §4.1).
- **(added in fact-check)** `periodic` absent: guard with an existence check (`command -v periodic` / `FileManager.isExecutableFile(atPath: "/usr/sbin/periodic")`) rather than an OS-version check alone (§10).

---

## 14. Copy and branding guardrails

INFERRED.

- Do not use: "Smart Care", "Smart Scan", "My Clutter", "Moonlock", "Space Lens", "Assistant" (generic but strongly associated), MacPaw's illustrations, 3D module icons, the pink/blue gradient spectrum, the off-canvas superellipse scan button, sounds, or marketing taglines.
- Our labels (proposal):
  - Checkup (feature);
  - areas: **Cleanup**, **Security**, **Speed**, **Apps**, **Clutter** ("Cleanup" is generic);
  - buttons: **Scan**, **Stop**, **Review**, **Run**, **Start Over**, **Done**. These are generic macOS verbs; acceptable.

---

## 15. Open questions / gaps (need hands-on verification or our own decision)

Each item below carries a **Fact-check update**. In that pass, macpaw.com and web search were unreachable (see §0), so most answers are evidence-based inferences, not vendor confirmations.

1. The exact 5.x **scanning-screen** visuals and copy, and whether partial results show live. UNVERIFIED.
   - *Fact-check update:* weak third-party evidence (a clone spec written from 5.x screenshots) points to a large circular action that spins while busy. It also points to a Cleanup scanning view with a progress headline and a category list that ticks off categories as they finish (§5 Screen 3).
   - Still UNVERIFIED for Smart Care itself. Our design (stepper with per-area completion) is consistent with that hint.
2. Whether **Stop/cancel** exists during 5.x Smart Care scan and Run (X had Stop during the scan). UNVERIFIED for 5.x.
   - *Fact-check update:* the same clone spec says the busy orb "can become Stop" and shows a Stop control during the Cleanup scan. That makes Stop during a 5.x scan *likely* (INFERRED, weak).
   - No evidence either way for Stop during **Run**.
   - Keep our design: Stop during scan; Stop between items during Run.
3. The **completion screen** wording and layout in 5.x. Only the CLI equivalent is known. UNVERIFIED.
   - *Fact-check update:* no new vendor evidence.
   - The CLI completion screen was re-confirmed: heading, per-category ✓ rows with sizes, a big "<size> cleaned!" figure, "<n> items removed", and two tips. It remains the best proxy.
4. Whether Smart Care **prompts to quit apps** (e.g. for app updates) and what its options are. UNVERIFIED.
   - *Fact-check update:* the only vendor evidence of a quit dialog with **Skip** is from **CleanMyMac Classic 1.x** (corrected in §5 Screen 6).
   - INFERRED: updating a running app requires quitting it, so Smart Care's Applications step must either prompt or skip running apps. Our "Quit & Continue / Skip These Items / Cancel" sheet covers both.
5. Which copy **My Clutter's duplicate smart selection** keeps, and whether removed duplicates go to the Trash. UNVERIFIED.
   - *Fact-check update (INFERRED):* My Clutter's duplicate finder descends from MacPaw's Gemini.
   - The Trash Bins KB (cited in §3.1) lists a separate **"Gemini Duplicates"** trash category. That points to *non-permanent* removal: duplicates go to a recoverable holding place, not straight to deletion.
     - For the Photos library, Gemini reportedly gathers duplicates in an album of that name for the user to delete in Photos (from memory; not re-checked).
     - For plain files, the Trash.
   - Which copy is kept is still undocumented. Keep our rule: oldest, or the copy whose name has no " (1)"/" copy" suffix; Trash, not unlink; offer Undo.
6. What the Performance tile shows on **macOS 15/26**, now that `periodic` is gone. UNVERIFIED.
   - *Fact-check update:* `periodic` is confirmed absent on 15/26 (man-page mirror plus forensic note).
   - Best estimate (INFERRED): Flush DNS Cache, plus possibly RAM/purgeable tasks, which is what MacPaw's 2026 CLI offers (§10).
7. Whether Smart Care **empties the Trash automatically** when the Cleanup tile is checked, or only selects some trash categories (e.g. the external-drive trash unchecked). UNVERIFIED.
   - *Fact-check update:* the MacPaw CLI's `clean trash` "Empties the system trash and mounted-volume trash bins", and `clean` runs it as part of "all clean categories". VERIFIED-direct.
   - The CLI shares rules with the app, so mounted-volume trashes are probably in scope by default. INFERRED.
   - The CLI sample also shows one whole category (AI Junk) unchecked by default, so per-category defaults exist. INFERRED.
   - Our choice: startup-disk Trash checked; external-volume Trash listed but **unchecked** (external drives may be backup disks); Photos/Mail trashes checked only if older than 7 days.
8. Any consumer-app **scheduled auto-run** of Smart Care in 2025–2026 builds. Not found; probably reminders only.
   - *Fact-check update:* the 5.x launchd inventory (Homebrew cask) has **no Scheduler job**, while the X (Chinese edition) cask had one (§6.1). This supports "reminders only" (INFERRED).
   - The Business product's forced runs remain the only documented auto-run.
9. Exact **empty-state strings** per tile. UNVERIFIED (we write our own anyway).
   - *Fact-check update:* nothing found.
   - The 5.x **Settings** tabs confirmed by KB excerpts so far are **Scanning** (with a Smart Care tree), **Ignore List** and **Protection**.
   - X additionally had **Notifications**, **Menu** and **Assistant** tabs. The rest of the 5.x tab list is UNVERIFIED.

---

## 16. Sources

Primary and vendor (KB pages were read via search-engine excerpts because direct fetches were blocked):

- Smart Care KB: https://macpaw.com/support/cleanmymac/knowledgebase/smart-care
- Smart Scan KB (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/start-smart-scan
- Smart Scan marketing (X): https://macpaw.com/cleanmymac-x/smart-cleanup
- Safety (5.x): https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-safety
- Safety Database (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/safety-database
- System Junk (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/system-junk
- Mail attachments (DE, X): https://macpaw.com/de/support/cleanmymac-x/knowledgebase/mail-attachments
- Trash Bins: https://macpaw.com/support/cleanmymac/knowledgebase/trash-bins
- Duplicates: https://macpaw.com/support/cleanmymac/knowledgebase/duplicate-files
- Malware removal: https://macpaw.com/support/cleanmymac/knowledgebase/malware-removal
- Protection scan options: https://macpaw.com/support/cleanmymac/knowledgebase/protection-scan-options
- Maintenance tasks: https://macpaw.com/support/cleanmymac/knowledgebase/maintenance-tasks
- Maintenance (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/maintenance
- Updater (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/updater
- How often to scan (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/how-often-run-cleanup-scans
- CleanMyMac 3 notifications: https://macpaw.com/support/cleanmymac-3/knowledgebase/notifications
- CleanMyMac X Menu: https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-x-menu
- CleanMyMac Menu (5.x): https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-menu
- Health Monitor: https://macpaw.com/support/cleanmymac/knowledgebase/cleanmymac-processes
- Background processes (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-processes
- Background items: https://macpaw.com/support/cleanmymac/knowledgebase/background-items
- Allow background items: https://macpaw.com/support/cleanmymac/knowledgebase/allow-background-items
- Mac Health: https://macpaw.com/support/cleanmymac/knowledgebase/mac-health
- Assistant (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/cleanmymac-assistant
- Full Disk Access (5.x): https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access
- Full Disk Access (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/full-disk-access
- Feature plans / editions: https://macpaw.com/support/cleanmymac/knowledgebase/feature-plans
- Missing features (X): https://macpaw.com/support/cleanmymac-x/knowledgebase/missing-features
- Privacy: https://macpaw.com/support/cleanmymac/knowledgebase/privacy
- Business Smart Scan automation: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan-automation
- Business Smart Scan: https://macpaw.com/support/cleanmymac-business/knowledgebase/smart-scan
- What's New (5.x): https://macpaw.com/cleanmymac/whats-new
- What's New (X): https://macpaw.com/cleanmymac-x/whats-new
- Launch announcement: https://macpaw.com/news/introducing-new-cleanmymac
- PR Newswire release: https://www.prnewswire.com/news-releases/macpaw-launches-new-cleanmymac-the-smart-effortless-app-for-mac-care-302275058.html
- Old CleanMyMac release notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac/1.11/releasenotes.html
- CleanMyMac blog, maintenance: https://cleanmymac.com/blog/how-to-run-maintenance-mac
- **MacPaw CleanMyMac CLI (fetched directly):** https://github.com/MacPaw/cleanmymac-cli (README); wiki pages Safety-and-Privacy, Commands, FAQ, Getting-Started (raw.githubusercontent.com/wiki/MacPaw/cleanmymac-cli/…)

Press and reviews:

- MacStories: https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/
- 9to5Mac: https://9to5mac.com/2024/10/16/macpaw-releases-major-update-to-cleanmymac-with-fresh-design-and-new-features/
- MacRumors (2024): https://www.macrumors.com/2024/10/16/macpaw-releases-redesigned-cleanmymac/
- MacRumors (2018): https://macrumors.com/2018/09/05/macpaw-launches-cleanmymac-x
- Forbes: https://www.forbes.com/sites/marksparrow/2024/10/16/the-new-cleanmymac-update-will-keep-your-mac-fit-and-health/
- Macworld: https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html
- SoftwareHow: https://www.softwarehow.com/cleanmymac-review/
- allaboutcookies: https://allaboutcookies.org/cleanmymac-x-review
- thehightechsociety: https://thehightechsociety.com/cleanmymac-review/
- TechRadar: https://www.techradar.com/reviews/cleanmymac-x-for-mac-review
- AFB AccessWorld (VoiceOver): https://afb.org/aw/21/6/17076
- TidBITS (CleanMyMac 3): https://tidbits.com/2015/08/28/save-space-and-uninstall-apps-with-cleanmymac-3/
- TidBITS (4.6.9): https://tidbits.com/watchlist/cleanmymac-4-6-9/
- Setapp: https://setapp.com/how-to/best-mac-cleaner-software
- Setapp: https://setapp.com/how-to/delete-app-from-mac-that-wont-delete
- Wikipedia: https://en.wikipedia.org/wiki/CleanMyMac

Design:

- Behance (Dimitry Novikov): https://www.behance.net/gallery/141590791/CleanMyMac-X-Product-Design
- Red Dot: https://www.red-dot.org/project/cleanmymac-x-55187
- iF Design Award: https://macpaw.com/news/cleanmymac-if-design-award
- Dribbble: https://dribbble.com/MacPaw/projects/623137-CleanMyMac
- And Action: https://www.and-action.net/projects/cleanmymac

Security:

- Talos spotlight: https://blog.talosintelligence.com/vulnerability-spotlight-cleanmymac-x/
- TALOS-2018-0716: https://talosintelligence.com/vulnerability_reports/TALOS-2018-0716
- TALOS-2019-0759: https://www.talosintelligence.com/vulnerability_reports/TALOS-2019-0759

macOS platform:

- heise (Sequoia removes `periodic`): https://www.heise.de/en/news/Cleanup-scripts-macOS-15-removes-periodic-but-no-longer-needs-it-10007870.html
- Apple Community (`periodic` on Sequoia): https://discussions.apple.com/thread/255818101
- Namecheap (DNS flush): https://www.namecheap.com/support/knowledgebase/article.aspx/397/2194/how-to-clear-the-local-dns-cache

Forums:

- MPU Talk (cleanup errors): https://talk.macpowerusers.com/t/cleanmymacx-error-while-cleaning-up-system-junk/13096
- MPU Talk (permission issue): https://talk.macpowerusers.com/t/cleanmymac-x-permission-issue/17372

Open-source implementation references (fetched directly; third-party, not MacPaw):

- Mole README: https://raw.githubusercontent.com/tw93/Mole/main/README.md
- Mole security audit: https://raw.githubusercontent.com/tw93/Mole/main/SECURITY_AUDIT.md
- Mac Sai README: https://raw.githubusercontent.com/iliyami/MacSai/main/README.md

Added in the fact-check (all fetched directly):

- Homebrew cask `cleanmymac` (5.7.1 build, launchd jobs, helper paths): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac.rb
- Homebrew cask `cleanmymac-zh` (X Chinese edition; has a `.Scheduler` job): https://raw.githubusercontent.com/Homebrew/homebrew-cask/master/Casks/c/cleanmymac-zh.rb
- MacPaw tap, `cleanmymac-cli` cask: https://raw.githubusercontent.com/MacPaw/homebrew-taps/main/Casks/cleanmymac-cli.rb
- Public copy of the 5.x Agent launchd plist: https://raw.githubusercontent.com/MYunFeiYang/zbookpowerg7/f4bce960e458399a4ebedb3cd29bf4d0f67af4ee/docs/backups/cleanmymac5-residue-2026-09-18/com.macpaw.CleanMyMac5.Agent.plist
- osquery allow-list naming `/Library/PrivilegedHelperTools/com.macpaw.CleanMyMac4.Agent`: https://github.com/chainguard-dev/osquery-defense-kit (`detection/persistence/2-unexpected-uid0-daemon-macos.sql`)
- DevMate release notes, CleanMyMac X: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/4.0.0/releasenotes.html, …/4.4.6/releasenotes.html, …/4.6.9/releasenotes.html
- CVE records: https://github.com/CVEProject/cvelistV5 (`cves/2018/4xxx/CVE-2018-4032…4047.json`, `cves/2019/5xxx/CVE-2019-5011.json`)
- Talos spotlight text mirror: https://github.com/EFI-Demo/Endpoint-Forecasting-and-Interpreting (`CTIs/talosintelligence/talosintelligence/2019/Vulnerability Spotlight Multiple privilege escalation vulnerabilities in CleanMyMac X.txt`)
- macOS man pages by OS version (periodic, tmutil, purge, mdutil, dscacheutil, mDNSResponder): https://github.com/vitorgalvao/macos-man-pages
- Forensic note on periodic, cron and at on Sequoia/Tahoe: https://github.com/AppliedIR/sift-mcp (`packages/forensic-knowledge/data/artifacts/macos/cron_at.yaml`)
- Mole optimize tasks (DNS flush with VPN guard, periodic guard): https://raw.githubusercontent.com/tw93/Mole/main/lib/optimize/tasks.sh
- Apple Developer documentation (JSON endpoints under developer.apple.com/tutorials/data/documentation/…): `SMAppService` (`daemon`, `agent`, `loginItem`, `mainApp`, `status`), `SMJobBless` (deprecated 13.0), `NSXPCListener.setConnectionCodeSigningRequirement(_:)`, `NSXPCConnection.setCodeSigningRequirement(_:)`, `NSBackgroundActivityScheduler` (`interval`, `tolerance`, `repeats`, `qualityOfService`), `ProcessInfo.beginActivity(options:reason:)`, `ActivityOptions.userInitiated` / `.idleSystemSleepDisabled`, `NSRunningApplication.terminate()` / `forceTerminate()` / `isTerminated`, `FileManager.trashItem(at:resultingItemURL:)`, `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` / `volumeAvailableCapacityKey` / `totalFileAllocatedSizeKey` / `ubiquitousItemDownloadingStatusKey`, `UNNotificationInterruptionLevel.timeSensitive`
- FDA deep-link usage in open-source apps: https://github.com/viticci/remctl (`remctl-permissions.swift`), https://github.com/lobehub/lobehub (`apps/desktop/src/main/utils/permissions.ts`)
- Third-party, weak evidence (not vendor): CleanMyMac 5 URL-scheme notes, https://raw.githubusercontent.com/taylorarndt/taylors-skill-collection/8069fd1523d68bfde5b3e500d875fba361fbf361/skills/mac-storage-cleanup/SKILL.md; clone UI spec from 5.x screenshots, https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/e71f840ac5bb50f43199030b4e4308563ebad0de/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md

---

## Verification notes

Adversarial fact-check pass, 2026-10-12.

### Access constraints during this pass

- **Unreachable:** macpaw.com, cleanmymac.com, `updates.cleanmymac.com` (the Sparkle appcast), review sites, Wikipedia, NVD, heise, Apple Community, and talosintelligence.com (DNS failure or proxy CONNECT 403). Web search was also unavailable because the shared search budget was exhausted.
- **Reachable:**
  - raw.githubusercontent.com and GitHub code search;
  - Apple's documentation JSON;
  - MacPaw's legacy DevMate S3 release-notes bucket: Classic 1.x and X 4.0.0–4.6.x. Builds 4.6.10 and later returned 403 or were absent.
- **Consequence:** claims backed only by search-engine excerpts of macpaw.com KB pages could be neither re-confirmed nor refuted. They keep their original VERIFIED (search-excerpt) tag and remain the main residual risk. They should be re-checked hands-on or with live page access before the UI is finalized. Examples: Smart Care's five routines, defaults, the Settings → Scanning path, dimmed tiles, Start Over, and My Clutter = Downloads duplicates only.

### Claims checked and their outcome

| # | Claim (section) | Outcome |
|---|---|---|
| 1 | MacPaw CLI facts: Scan → Review → Confirm; 7-day pre-selection; "Cleanup complete!" summary; `optimize ram` with no sudo; `--force`; ignore list (§1 item 15, §4.1, §10) | **Re-confirmed** VERIFIED-direct (README and wiki re-fetched). Minor wording refined: "cleanup logic/rules shared with CleanMyMac". Added: the sample shows a whole category (AI Junk) unchecked by default. |
| 2 | Talos CVE → helper-function mapping (§9) | **Re-confirmed** VERIFIED-direct (Talos text mirror plus CVE JSON). Added the full list of 13 functions, fixed version 4.2.0 and tested version 4.04. |
| 3 | X helper plist `/Library/LaunchDaemons/com.macpaw.CleanMyMac4.Agent.plist` (§9) | Path **confirmed**; **citation corrected**. TALOS-2018-0716 could not be shown to contain it, so the path is now sourced from an osquery allow-list and the cask pattern. |
| 4 | 5.x "Agent" helper (§1 item 13, §5 Screen 2) | **Refined/corrected.** 5.x uses an SMJobBless-style blessed helper in `/Library/PrivilegedHelperTools` plus `/Library/LaunchDaemons` (cask plus actual plist). Also documented HealthMonitor, Menu and Updater jobs. `SMJobBless` is deprecated since macOS 13. |
| 5 | macOS 15 removed `periodic` (§1 item 14, §10) | **Corroborated** (man-page mirror; forensic note on a tested 15.6.1 host). **Corrected** the side claim "cron is present but disabled": cron is present and functional, and `at` is the one disabled. Noted Mole's conflicting "macOS 26+" comment. |
| 6 | DNS flush command (§10) | **Confirmed** as standard practice (`dscacheutil(1)` documents `-flushcache`; HUP to mDNSResponder is practice, not in its man page). **Added** the VPN-reconnect caveat. |
| 7 | `tmutil thinlocalsnapshots / <bytes> 4` (§10) | **Confirmed** VERIFIED-direct (`tmutil(8)`, urgency 1–4). |
| 8 | `/usr/sbin/purge` as "Free up RAM" (§10) | **Corrected.** `purge(8)` flushes the disk cache and "does not affect anonymous memory". Relabel it. |
| 9 | `mdutil -E /` (§10) | **Confirmed** (`mdutil(1)`). |
| 10 | "Rebuild Launch Services: Mole documents breakage on macOS 15+" (§10) | **Corrected.** Two distinct issues: the VPN Network Extension side effect of a rebuild, and `lsregister -u` returning −10814 on macOS 15+ for apps that are already gone. |
| 11 | Mac Sai "cancellation returns to idle in ~1 s" applied to deletion (§5 Screen 7) | **Corrected.** That figure is for scans. Chunk size of 5k was confirmed. |
| 12 | FDA deep link (§5 Screen 2) | **Corrected/refined.** Primary on macOS 13+: `…com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles`; the legacy URL is a fallback. Undocumented by Apple. |
| 13 | Apple APIs used in the design (§5, §6.2, §9, §12) | **All exist** with the availability shown in Apple docs: SMAppService daemon/agent/loginItem/mainApp/status 13.0; `NSXPCListener.setConnectionCodeSigningRequirement` 13.0; `NSBackgroundActivityScheduler` 10.10; `.timeSensitive` 12.0; `terminate`/`forceTerminate`/`isTerminated` 10.6; `trashItem` 10.8; `volumeAvailableCapacityForImportantUsageKey` 10.13; `totalFileAllocatedSizeKey` 10.7; `ubiquitousItemDownloadingStatusKey` 10.9. **Corrected** `SMAppService.mainApp` usage (use `loginItem(identifier:)` for a helper app). Added: Apple's scheduler defaults; `terminate()` fails when sandboxed; the time-sensitive entitlement. |
| 14 | "Uninstaller Quit Application dialog gained Skip" (§5 Screen 6) | **Corrected context.** The source is **CleanMyMac Classic 1.x** (c. 2010–2012), not X or 5. |
| 15 | X 4.6.9 "exclude Speed tasks" and "Scan All" (§2) | **Re-confirmed** VERIFIED-direct (DevMate release notes). X 4.0 "Cleanup, Protection, Speed" also VERIFIED-direct. |
| 16 | 5.7.1 release (§2) | **Corroborated**: cask build 50701.0.2609301754 (stamp 2026-09-30). |

### Additions (not in the original report)

- 5.x background-process inventory, with no Scheduler job. Evidence for "reminders only".
- `cleanmymac5://` module deep links (third-party).
- X release-note facts:
  - actionable low-memory notification (4.6.2);
  - "Clearer scan details for Smart Scan" (4.4.3);
  - Smart Scan VoiceOver fixes (4.4.1);
  - purgeable-space task (4.4.1).
- Safety rules: keep empty `Caches` folders; exceptions database grown from bug reports (Ableton, VLC, Photos); cleanability pre-filter for protected Apple caches.
- Edge cases: active VPN versus DNS flush; detect `periodic` by existence rather than OS version.
- A step-by-step "Journey at a glance" at the top of §5.
- Gap answers recorded in §15, mostly INFERRED.

### Still uncertain

- **The 5.x screens:** scanning visuals and copy, whether Stop exists during Run, the completion-screen wording, empty-state strings, and the full Settings tab list. Only weak third-party hints exist.
- **Smart Care behaviors:** the quit-apps prompt for app updates; which duplicate copy is kept; the default selection of external-drive Trash; the Performance tile's contents on macOS 15/26.
- **MacPaw's non-sudo "free RAM" mechanism** in the CLI.
- **All macpaw.com KB-excerpt claims.** Not re-verifiable in this pass; see "Access constraints" above.
