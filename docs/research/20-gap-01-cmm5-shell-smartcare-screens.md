# 20 · Gap-fill 01 — CleanMyMac 5.x main window and the Smart Care journey, screen by screen

> **Track:** gap-fill for 01-overview §14 (gaps 1, 5), 02-smart-care §15 (gaps 1–3, 6, 9) and 09-design §7 (gaps 1, 3, 5, 6, 8).
> **Target build:** CleanMyMac 5.6–5.7.1 (Aug–Oct 2026), on macOS 14 / 15 / 26.
> **Date of this pass:** 2026-10-12.
> **Our app:** code name *Spruce*, design system *Prism*. Smart Care is called **Checkup** in our app (09-design §B). Nothing in this file is to be shipped verbatim. Vendor labels are quoted only so that we can understand the structure.

---

## 0. Method, access limits and evidence labels

### 0.1 What this session could and could not reach

This needs saying first, because it bounds every conclusion below.

| Attempt | Result |
|---|---|
| `WebSearch` (any query) | **Refused.** The turn-wide budget of 200 searches, shared by all agents, was already used up when this task started. No web search ran in this pass. |
| `WebFetch` on `macpaw.com/support/cleanmymac/knowledgebase/smart-care`, `itunes.apple.com/lookup?id=1339170533&entity=macSoftware`, `www.macstories.net/...`, `9to5mac.com/...`, `en.wikipedia.org/...` | **DNS failure** (`getaddrinfo ENOTFOUND`) for every host. |
| `curl` through the session proxy to `macpaw.com`, `apps.apple.com`, `is1-ssl.mzstatic.com`, `setapp.com`, `www.reddit.com`, `www.youtube.com`, `i.ytimg.com`, `www.macworld.com`, `www.tomsguide.com`, `www.techradar.com`, `sixcolors.com`, `allaboutcookies.org`, `www.softwarehow.com`, `formulae.brew.sh`, `cleanmymac-5.devmate.com`, `i.imgur.com`, `i.redd.it` | **Blocked** (HTTP 000; `CONNECT tunnel failed, response 403` for itunes). |
| `raw.githubusercontent.com` and GitHub code search (MCP `search_code`) | **Reachable.** About 25 code searches and about 30 raw-file fetches were made. |
| `api.github.com` for repos other than this project | Refused by the session's repository binding. |

**Result: in this pass, as in every earlier pass, no researcher has seen a primary 5.x screenshot, App Store screenshot URL, App Store release note, video transcript or vendor KB page.** I did not work around the search limit with archive or reader services.

What *is* new comes from GitHub:
1. a third clone that encodes the 5.x Smart Care choreography in more detail than any source we had (erluxman/learn);
2. a third-party **hands-on audit of CleanMyMac 5.5.7** with real Smart Care result numbers;
3. a secondhand description of the actual product screenshot on macpaw.com;
4. further VaderCleaner files that describe the 5.x "Manager" review surface and the "Customize Smart Care" settings tree;
5. a pixel-led **X** replica, which lets us tell X-era copy apart from 5.x copy;
6. **real vendor screenshots of the complete CleanMyMac X Smart Scan journey** (landing → scanning → results → quit-apps prompt → running → completion) from the public `kafkaGen/dora-ai` dataset, route 1, steps 1–6. 05-performance had used only step 5, and the sibling gap-fill 20-gap-02 pointed to the dataset. These are the newest real pixels of the predecessor flow (late X 4.15.x: Moonlock branding, Claude desktop app visible). They anchor the shell and journey conventions that 5.x inherited, and they correct some X copy taken from the replica (§5.10).

§9 is a **hands-on verification kit**. With it, the owner of the Mac mini can close every remaining gap in under an hour, using the vendor's 7-day trial, Accessibility Inspector and `plutil`.

### 0.2 Labels used in this file

The task asks for two labels, VERIFIED and INFERRED. To keep the strength of evidence visible, each is qualified:

| Label | Meaning |
|---|---|
| **VERIFIED [vendor]** | MacPaw's own text (KB, release notes, appcast). Most were fetched by earlier passes; the URL is given and the earlier report section is named. |
| **VERIFIED [3P-bundle]** | A third party inspected the **shipped** 5.x app bundle (asset catalogs, frameworks, plists) and published what they found. Strong but secondhand. |
| **VERIFIED [3P-hands-on]** | A third party ran a 5.x build and wrote down what the UI showed (numbers, behaviour). Strong but secondhand, and translated where noted. |
| **VERIFIED [X-screenshot]** | Read by me directly off a **real CleanMyMac X** screenshot (dora-ai route 1). Primary pixels, but of the **predecessor**. It proves a convention existed in late X, not that 5.x kept it. |
| **INFERRED [clone-obs]** | Behaviour or layout encoded in a third-party clone whose code comments say it follows the original ("like the original", "per screenshots", "the reference uses …"). Moderate. It becomes stronger when independent clones agree. |
| **INFERRED** | Our reasoning or recommendation. |

---

## 1. Executive summary

**What we can now say with reasonable confidence (5.x):**

1. **One continuous coloured surface.** The whole window, sidebar included, sits on one module-tinted canvas. The sidebar has no material and no divider. The traffic lights float over the canvas, and there is no visible toolbar on landing screens. INFERRED [clone-obs ×3]. The Metal live background is VERIFIED [3P-bundle].
2. **The Smart Care landing** has the giant glossy display-and-squeegee hero, a large light headline, one subtitle line and a round **Scan** button that straddles the window's bottom edge, with a glow.
   - The hero is VERIFIED [3P-bundle].
   - The layout is INFERRED [clone-obs ×3].
   - The returning-user headline in the most faithful clone is "Welcome back!", with the subtitle "Start with a quick and extensive scan of your Mac." INFERRED [clone-obs, single source]. The late-X landing used different wording ("Welcome to CleanMyMac X" / "…a nice and thorough scan…", VERIFIED [X-screenshot]), so the 5.x copy is still unconfirmed.
3. **The sidebar at 5.0** had six module rows plus an **Assistant** row pinned bottom-left. VERIFIED [vendor/press] (via 01 §5.1). A clone screenshot reproduces it (§3.2).
   - **Space Lens**, **Cloud Cleanup** and **Tools** are sidebar items in later builds. VERIFIED [vendor] (KB/how-to wording, via 01 §5.1).
   - Whether **My Activity** is its own row, and whether **Assistant** still sits at the bottom in 5.7, is **not verified**.
4. **Scanning.** The Smart Care scan replaces the landing with a **card stage**: three cards on top (Cleanup, Protection, Performance) and two below (Applications, My Clutter).
   - The card being scanned widens, lights up in its module colour and shows a "Looking for …" headline, an animating icon and a one-line file ticker. Waiting cards are dark glass. Finished cards show their metric.
   - Applications and My Clutter share the last stage.
   - The round button becomes **Stop** with a progress ring.
   - INFERRED [clone-obs, erluxman; partly corroborated by GuilhermeVozniak and by X behaviour].
5. **The sidebar collapses to an icon rail** once Smart Care leaves its landing. **Three independent clones** do this (erluxman, VaderCleaner, GuilhermeVozniak), which upgrades the earlier "plausible" to "likely". It is still INFERRED [clone-obs ×3].
6. **Results.** The same 3 + 2 grid at equal sizes. Each tile has a checkbox and the module name top-left, the module's 3D icon bleeding off the top-right corner, a big metric, a status line and a **Review** button. **Start Over** sits in the title strip at top-left, and the round button reads **Run**.
   - Structure, dimming, Review, Run and Start Over are VERIFIED [vendor] (Smart Care KB via 02 §1).
   - Geometry and placement are INFERRED [clone-obs].
7. **Real result numbers from a 5.5.7 run:** "23.1 GB", "1 threat", "2 maintenance tasks", "1 important update". VERIFIED [3P-hands-on, translated from the Chinese UI]. This confirms that the **Performance tile still counts maintenance tasks** in mid-2026 builds, and that the Applications tile talks about "important" updates.
8. **Review surfaces ("Managers")** look like a **white card** with a magenta accent: a header with search and "Sort by", a left nav, a middle facet column, a right item list and a footer action. They zoom up from the button that opened them. INFERRED [clone-obs, VaderCleaner "the reference Manager uses a magenta accent on a white surface"]. This matters for the light/dark question: the canvas is always dark, but the review cards are light.
9. **Performance tile on macOS 15/26:** `periodic` is gone. The tile most likely holds **two tasks: Flush DNS Cache + Free Up RAM**, with Free Up Purgeable Space as the alternative second task, and Run Maintenance Scripts hidden. Evidence:
   - the late-X Smart Scan on a 2025-era macOS ran exactly "Flush DNS Cache" and "Free Up RAM" as its two Speed tasks (VERIFIED [X-screenshot] 1_3, 1_5, 1_6);
   - a 5.5.7 run showed "2 maintenance tasks" (VERIFIED [3P-hands-on]);
   - the vendor filters tasks per OS (05 §1 item 3);
   - the CLI offers `optimize ram|purgeable`, and one clone lists DNS + purgeable (§6).
   The conclusion itself is INFERRED.
9a. **The real X Smart Scan journey** (dora-ai route 1) fixes several shell conventions that 5.x most likely kept. All are VERIFIED [X-screenshot]; carrying them over to 5.x is INFERRED:
   - centred module title in the title strip during scan, results and run, hidden on the landing and the completion screen;
   - "‹ Start Over" top-left on results **and** completion;
   - a **progress pie on the Smart Scan sidebar row** during scan and run, which turns into a white dot when results are ready;
   - a **live running total next to the Stop button**;
   - a green "OK" / "No threats found" for an empty pillar;
   - a **quit-apps prompt during Run**;
   - a running list with per-task status (size + ✓, ⚠ partial, "Running…" spinner, "•••" waiting);
   - a completion screen with three ✓ result rows, **Share Results**, and a yellow **⚠ View Log** when something was only partly cleaned. The round button is gone on that screen.
10. **The Smart Care duplicates step** only scans `~/Downloads` (VERIFIED [vendor]). So it can only find duplicates **within** Downloads, never "a Downloads file that duplicates something elsewhere" (INFERRED, follows from the scope). Which copy it keeps is still undocumented (§7).
11. **Onboarding** is built around an **`IntroVideo.mp4`** (VERIFIED [3P-bundle]). The permission steps, their copy and their order remain a **gap**. We know the vendor tells users to grant FDA after a first Smart Care scan, and that the Assistant shows an **Allow Access** recommendation. VERIFIED [vendor] via 01 §9.1.
12. **Liquid Glass on macOS 26:** still unverified for the window. All 5.x builds declare macOS 11.0 as their minimum (VERIFIED [vendor appcast]), so any Liquid Glass must sit behind availability checks. The kit in §9 includes a 10-second `otool` check that settles whether the app is linked against the macOS 26 SDK.

**What is still unknown** (closable with §9): default and minimum window size; exact intro-chip labels; exact empty-state and completion copy; where the bell and "Unlock Full Version" sit; whether a summary sits next to Run; the scan-finish sound; the onboarding step list; and Liquid Glass adoption.

---

## 2. Evidence ledger (new in this pass)

| # | Source (what it is) | Label | What it contributes | URL |
|---|---|---|---|---|
| E1 | **erluxman/learn** `Cleaner.swift` + `CleanerIcons.swift`: a SwiftUI recreation "laid out like CleanMyMac". The comments repeatedly say "like the original" / "as the original does". | INFERRED [clone-obs] | Smart Care choreography (3 + 2 stage, active card widens, "Applications and My Clutter share the last stage"), rail collapse with a progress pie, "‹ Start Over" beside the traffic lights, module title centred in the title strip, blur-fade between modules, window draggable from any empty spot, round button hanging off the bottom edge, per-module headlines and scan lines, results headline, tile anatomy, Performance tasks | https://raw.githubusercontent.com/erluxman/learn/main/Sources/Learn/Cleaner.swift ; https://raw.githubusercontent.com/erluxman/learn/main/Sources/Learn/CleanerIcons.swift |
| E2 | erluxman/learn README screenshot of that clone's Smart Care landing | INFERRED [clone-obs] (visual) | Six-row sidebar with 3D mini icons (selected = colour, others frosted), **Assistant** row at bottom-left with a two-dot glyph, hero, "Welcome back!" + subtitle, glowing round **Scan** half outside the window | https://raw.githubusercontent.com/erluxman/learn/main/docs/screenshot-cleaner.png |
| E3 | **yangyihang96/StorageCleanerMac** competitive audit, dated 2026-08-25, run against **CleanMyMac 5.5.7** installed on the auditor's Mac (read-only; nothing cleaned) | VERIFIED [3P-hands-on] (Chinese, translated here) | Smart Care result counts (23.1 GB; 1 threat; 2 maintenance tasks; 1 important update); the Cleanup page pre-selected 1,839 items / 22.6 GB; Smart Care chains the protection, performance and applications modules; an earlier read showed 20.4 GB system junk, 263 MB mail attachments, 34 MB Trash and 5.6 GB "Extra Binaries" | https://raw.githubusercontent.com/yangyihang96/StorageCleanerMac-OpenSource/main/docs/COMPETITIVE_AUDIT_1.9.12.md |
| E4 | **medlars/verdictui** design doc (2026-09). The author inspected "the actual product screenshot" on macpaw.com/cleanmymac. | VERIFIED [3P-hands-on] (secondhand description of a vendor image) | "translucent violet sidebar, large dimensional Smart Care object, generous open space, and a single primary action"; the reference has a "dark purple canvas" | https://raw.githubusercontent.com/medlars/verdictui/main/docs/workbench-design.md |
| E5 | **VaderCleaner** `ApplicationsManagerView.swift`, `ProtectionDashboardView.swift`, `SettingsScanningTab.swift`, `VaderCleanerTests/RailCollapseTests.swift` | INFERRED [clone-obs] | Manager = white card + magenta accent + search + "Sort by" + left nav + footer action, zooming from the opening button; Protection results grid with a Start Over bar; "Customize Smart Care" settings = left list (Smart Care / Modules) + right tree with glossy badges and tri-state checkboxes; rail collapse latching | https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/ApplicationsManagerView.swift ; …/VaderCleaner/ProtectionDashboardView.swift ; …/VaderCleaner/SettingsScanningTab.swift ; …/VaderCleanerTests/RailCollapseTests.swift |
| E6 | VaderCleaner `docs/cleanmymac-3d-assets.md`: teardown of **CleanMyMac 5.5.4 (MAS, build 50504.0.2605130801)** | VERIFIED [3P-bundle] | Hero `ModuleIcon`, `intro-category-quick-scan / -security-check / -system-tuneup` chips, sidebar glyph variants, `MainAppUI` back-button chrome, `IntroVideo.mp4`, `WiperFrame_1…6`, `CMM5UbiquitousButton` bundle with `default.metallib`, `AssistantUI` health states | https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md |
| E7 | **GuilhermeVozniak/app-cleaner** UI revamp spec (2026-10-02), from "reference screenshots supplied by the owner" | INFERRED [clone-obs] | Dark module-tinted canvas, thin icon rail with Smart Care alone on top and hairline-separated groups, "Start Over" at top-left of the title strip, module name centred, a round CTA that becomes Stop, no light scheme | https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/main/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md ; …/apps/desktop/frontend/src/style.css |
| E8 | **ddlmanus/MacOptimizer** `SmartCleanerReplicaView.swift`: a pixel-led replica of **CleanMyMac X** Smart Scan (bilingual strings) | VERIFIED [3P-bundle-like] for **X only** | Lets us tell X flow apart from 5.x (§5.10). Superseded by E10 for exact X copy | https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/SmartCleanerReplicaView.swift |
| E9 | hollow/dotfiles `macos/defaults.sh` (5.x Setapp keys, already used in 09 §4.8) | VERIFIED [3P-bundle-like] | `SmartCareReminderEnabled`, `ShowAssistantRecommendations`, `MenuAppEnabled` | https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh |
| E10 | **kafkaGen/dora-ai** dataset, route 1, steps 1–6: **real screenshots of CleanMyMac X Smart Scan** (2180 × 1288 px window captures), plus per-step `node_desc.json` | VERIFIED [X-screenshot] | Exact late-X copy and layout for every journey state, the title strip, the sidebar progress pie, the live total by Stop, the empty-pillar state, the quit prompt, the running list and the completion screen (§5.11) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/1/image.png … /1/6/image.png ; …/routes/1/<n>/node_desc.json |

**Caveat on E8.** Its strings are **paraphrases**, not the real X copy. For example, the replica's results headline "Okay, here's what I found." is "Alright, here's what I've found." in the real X screenshot (E10). Where E8 and E10 differ, E10 wins.

Clones that I checked and **rejected** as evidence, because they are invented rather than observed: MYLEKHATECH/Ccmacui (a generic Figma guide with a 220 pt sidebar, a blue/green palette and invented screens), alex-foster-personal/cleanmymacfree (wireframes), apo-bozdag/clean-my-mac (Svelte; reuses the X subtitle only), yunweneric/tidy, momenbasel/PureMac (own design) and themoretheless/ppduster (feature summary only).

---

## 3. (a) Window chrome

### 3.1 Window size

| Question | Evidence | Status |
|---|---|---|
| Default size | None for 5.x. The X window-only captures were 1090 × 672 px, aspect ≈ 1.62 (09 §7 item 10). The dora-ai X captures (E10) are 2180 × 1288 px, i.e. about **1090 × 644 pt** at 2× (aspect 1.69). They are cropped at the left edge, where X's sidebar panel overhangs the main window. Clone choices: erluxman 1040 × 720 ("same as Learn Settings", i.e. not measured); Ccmacui's 1280 × 800 is invented. | **GAP** for 5.x. §9.2 measures it. |
| Minimum size | None. The vendor's minimum *display* is 1280 × 800 (01 §3, VERIFIED [vendor]), so the window must fit in about 1280 × 715 visible points with the menu bar and Dock. | **GAP.** INFERRED: the minimum is ≤ 1100 × 680. |
| Resizable? | X was resizable with a fixed sidebar. No 5.x evidence. | INFERRED: yes. |
| Full-screen | No evidence. | INFERRED: supported (standard AppKit). |

**Ours.** Keep 09 §B.13.2: `defaultSize(1180 × 740)`, `minWidth 1040, minHeight 680`, `.windowResizability(.contentMinSize)`. Nothing in this pass argues against it. The 1.59 aspect of 1180 × 740 is close to X's 1.62.

### 3.2 Title-bar strip (reconstruction)

```
 ●●●   ‹ Start Over                 Smart Care                    [🔔] [Unlock Full Version]
 └ traffic lights over the canvas   └ centred module name         └ right cluster (position INFERRED)
```

| Element | When visible | Vendor evidence | Status |
|---|---|---|---|
| Traffic lights | Always. They float directly on the module canvas, with no toolbar band. | Clone screenshot E2; erluxman's sidebar "sits on" the surface. Full-size content view with a hidden title bar. | INFERRED [clone-obs ×2] |
| **"Start Over"** with a leading chevron | Smart Care **results** (and module results). Top-left, just right of the traffic lights. | KB: "Start Over in the upper-left corner, after a confirmation". VERIFIED [vendor] (02 §1 item 3). Chevron + label beside the traffic lights: E1 ("‹ Start Over" beside the window buttons, leading padding about 90 pt), E7. A custom back-button asset exists in `MainAppUI`. VERIFIED [3P-bundle] (E6). | VERIFIED (position) + INFERRED (glyph) |
| "‹ Back" | Inside a Review/Manager surface | VaderCleaner managers have Back that zooms back into the dashboard (E5) | INFERRED [clone-obs] |
| Centred module name | During scan, results and run. Not on the landing, where the big headline already names the screen, and not on the completion screen. | **X:** "Smart Scan" is centred in the title strip on scanning (1_2), results (1_3), quit prompt (1_4) and running (1_5), and absent on the landing (1_1) and completion (1_6). VERIFIED [X-screenshot]. **5.x:** E1 draws "Smart Care" centred (13 pt semibold, white at 85 %) once Smart Care is running; E7 says "module name centred". | VERIFIED for X; INFERRED [clone-obs ×2] for 5.x |
| Start Over visibility | Results **and** completion. Not during scan or run (Stop is the exit there). | **X:** "‹ Start Over" appears on 1_3 and 1_6 only. VERIFIED [X-screenshot] | VERIFIED for X; INFERRED for 5.x |
| **Bell** → Notification Center | From 5.6.0 | Feature VERIFIED [vendor] (01 §5.1, https://macpaw.com/cleanmymac/whats-new). Position not documented. | INFERRED: top-right of the title strip |
| **"Unlock Full Version"** | Unlicensed or trial only | VERIFIED [vendor]: "top-right" (01 §9.1, https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation) | VERIFIED |
| Health/Assistant widget | — | **X:** an "Assistant" **pill at the top-right of the window** (dark translucent capsule, a two-dot glyph, cyan label), present on every journey screen and dimmed during scan and run. VERIFIED [X-screenshot] E10. **5.0:** moved to an **Assistant** row at the **bottom of the sidebar** (01 §5.1; E2 shows it). `AssistantUI.framework` with `HealthStatus*` states still ships in 5.5.4 (E6). | VERIFIED for X and 5.0; **GAP** for 5.7 |
| Window dragging | From any empty part of the canvas | E1: "any empty spot moves the window, as in the original" (`isMovableByWindowBackground`) | INFERRED [clone-obs] |

### 3.3 Liquid Glass on macOS 26

- **Verified facts:**
  - All 5.x builds in the appcast declare `sparkle:minimumSystemVersion` 11.0. VERIFIED [vendor] (09 §4.2).
  - The 5.5.4 icon is stored as layered `AppIcon_Assets` with P3 swatches and in-catalog gradients, consistent with an Icon Composer icon. VERIFIED [3P-bundle], interpretation INFERRED (09 §4.8 D).
- **No source** shows a glass sidebar, glass buttons or glass tiles in 5.6–5.7.
- **INFERRED.** The window is mostly custom-drawn: Metal canvas, custom back button, custom Metal-shaded round button. So what changes on Tahoe is probably limited to system chrome: traffic lights, sheets, alerts, menus, popovers and the Settings window, *if* the binary links the macOS 26 SDK. The round button already has its own glass shader (`CMM5UbiquitousButton` + `default.metallib`), so "glassiness" predates Tahoe.
- **Closable in 10 seconds:** `otool -l` → `LC_BUILD_VERSION sdk` (§9.4).
- **Ours** stays as in 09 §B.6 / §B.8.2: `.glassEffect` only for the rail selection pill and the circular title-bar buttons on 26+, with material fallbacks on 14/15.

---

## 4. (b) Sidebar

### 4.1 Rows and order

| Build | Rows, top → bottom | Evidence | Status |
|---|---|---|---|
| 5.0 (Oct 2024) | Smart Care · Cleanup · Protection · Performance · Applications · My Clutter … *(gap)* … **Assistant** (pinned bottom-left) | MacStories / 9to5Mac / MacObserver via 01 §5.1; clone screenshot E2 | VERIFIED [vendor/press] + visual INFERRED |
| 5.1+ | + **Space Lens** as its own row | KB: Space Lens is "a sidebar item"; deep link `cleanmymac5:///modules/spaceLens` (02 §3.1, third-party) | VERIFIED [vendor] for "sidebar item" |
| 5.2.1+ | + **Cloud Cleanup** | How-to: Cloud Cleanup is chosen from the sidebar (01 §5.1) | VERIFIED [vendor] |
| 5.4+ | + **My Activity** | Feature VERIFIED (01 §5.2). **No source says it is a sidebar row.** | INFERRED: a row, placed low |
| 5.5+ | + **My Tools** | How-to: "go to Tools in the sidebar" (01 §5.1). The label in the sidebar may be **"Tools"** rather than "My Tools". | VERIFIED [vendor] (row exists); label **GAP** |
| 5.7 | Same, plus Email Cleanup *inside* Tools (not a row) | 01 §5.2 | VERIFIED [vendor] |

**Best reconstruction for 5.7** (order from the vendor's feature table, 01 §5.1; grouping INFERRED):

```
 Smart Care
 ─────────────            ← hairline (INFERRED [clone-obs E7])
 Cleanup
 Protection
 Performance
 Applications
 My Clutter
 ─────────────
 Space Lens
 Cloud Cleanup
 ─────────────
 Tools / My Tools
 My Activity
           …
 Assistant / Health        ← bottom-pinned status row (5.0 VERIFIED; 5.7 GAP)
```

- **Section headers** (text such as "MODULES"): **no evidence** that 5.x uses them. Two clones draw **no divider at all** ("no divider: the sidebar lies flat on the surface"; VaderCleaner: "no sidebar material, no divider"). One clone (E7) separates groups with hairlines. INFERRED: hairlines at most, no text headers. Our 09 §B.8.2 text headers are our own choice and may stay.

### 4.2 Icon style and selection

- **Glyphs.** Bespoke per-module glyphs at **24 × 24 pt** (48 px @2x), with `Active` / `Inactive` and High-Contrast variants (`Module=Smart Care, Active=On, HCM=Off`). VERIFIED [3P-bundle] (E6).
- **Look in the clones.**
  - E2 renders each row's icon as a **tiny 3D "glass" version of the module silhouette** (monitor, disc, octagon hand, chevron bolt, hexagon, blob/folder).
  - The selected row is in full colour. Unselected rows are frosted white and take on the background hue.
  - **Smart Care's icon is always in colour.** E1 code: `mono: !selected && module != .smartCare`.
  - Row height is about 54 pt, the icon about 30 pt and the label 15.5 pt (medium, semibold when selected).
  - INFERRED [clone-obs].
- **Selection pill.** A frosted rounded rectangle with radius 14–18 (white about 13 % fill, gradient hairline rim from white 28 % to 8 %, soft shadow) that **slides** between rows on a spring (response 0.45, damping 0.78). INFERRED [clone-obs, E1 + VaderCleaner]. VaderCleaner tints the rim in the module accent; E1 keeps it white.
- **Assistant row.** A circular glass token holding two dots (one large, one small) plus the label "Assistant". INFERRED [clone-obs, E1/E2]. VERIFIED [vendor] that an Assistant entry sat at the bottom-left in 5.0.

### 4.3 Does the rail collapse during scans and results?

| Clone | Rule | Notes |
|---|---|---|
| erluxman (E1) | Sidebar → **78 pt icon rail** when `module == .smartCare && phase != .home`. The Smart Care rail icon gets a **13 pt progress pie** badge (top-right) that fills during the scan and is full at results. Labels are hidden. The Assistant row also collapses. | Only Smart Care collapses the rail. Module scans keep the full sidebar. |
| VaderCleaner (E5) | Collapses when **any** section leaves its intro, and stays collapsed **for the rest of the session** ("latched"). Hovering a row floats a name tooltip. | Explicitly its own rule (tests pin it). |
| GuilhermeVozniak (E7) | Always a 64 pt icon rail with tooltips. | Listed among its goals. Probably reflects reference screenshots taken in results states. |

**Verdict:** **likely** (three independent clones), but still **INFERRED**. The erluxman variant (collapse only for Smart Care's scan, run and results, with the progress pie) is the most specific and best matches a "give the stage room" rationale.

**X precedent for the pie (VERIFIED [X-screenshot], E10).** X did **not** collapse its sidebar during Smart Scan: the full labelled sidebar stays on 1_2–1_6. But the Smart Scan row showed a **small progress pie at its right edge** during scanning (1_2) and running (1_5), and a **solid white dot** once results were ready (1_3). So erluxman's pie badge is a faithful carry-over of a real vendor convention. The collapse is the part that remains unproven.

**Ours (INFERRED):** collapse to icons on entering Checkup scanning, results or running, and re-expand on Start Over or completion → Done. Show a progress ring badge on the Checkup rail icon. Do **not** latch for the session (latching hides labels from new users). Keep 09 §B.8.2's collapsed spec (44 pt pill, tooltip, 6 pt badge dots).

---

## 5. (c) The Smart Care journey, screen by screen

Screen IDs match 02 §5 (Screens 0–9) where possible.

### 5.0 State machine (vendor reconstruction)

```
            ┌───────────── Start Over (confirm) ──────────────┐
            ▼                                                  │
  [SC-1 Landing] ──Scan──▶ [SC-3 Scanning] ──done──▶ [SC-4 Results] ──Run──▶ [SC-7 Running] ──▶ [SC-8 Completion]
        ▲                        │ Stop                    │  ▲ Review/Back                          │ (button / Start Over)
        └────────────────────────┘                         ▼  │                                      │
                                                   [SC-5 Manager/Review]                             │
        ▲────────────────────────────────────────────────────────────────────────────────────────────┘
```

- Stop during scanning returns to the landing and discards partial results. INFERRED [clone-obs E1: `Stop` → `state.stop()` → `.home`]. X's Stop did the same (VERIFIED for X, 02 §5 Screen 3).
- In E1, only the results screen shows Start Over. During the scan, the round **Stop** is the only exit.

### 5.1 SC-1 Landing

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ●●●                                                                           │
│ ╭──────────────╮                                                              │
│ │▣ Smart Care  │                ╭─────────────────────╮                       │
│ ╰──────────────╯                │  glossy magenta     │   ← ModuleIcon hero   │
│  ◌ Cleanup                      │  display + squeegee │     600×400 pt asset  │
│  ◌ Protection                   ╰──────────┬──────────╯                       │
│  ◌ Performance                         ▁▁▁▁┴▁▁▁▁  pedestal                     │
│  ◌ Applications                                                              │
│  ◌ My Clutter                       Welcome back!          ← ~36 pt, light/regular │
│                       Start with a quick and extensive scan of your Mac.     │
│                                                                              │
│  ◉ Assistant                              ( Scan )   ← round ~80 pt, half below the edge │
└───────────────────────────────────────────╲______╱───────────────────────────┘
```

| Element | Content | Status |
|---|---|---|
| Hero | A free-standing glossy **magenta computer display** in ¾ view on a pale-lavender pedestal (#BDBCEF), with a lavender-silver **squeegee** lying diagonally across the screen. Gradient #FF91D7 → #B70193. Asset 600 × 400 pt (1200 × 800 @2x). | VERIFIED [3P-bundle] (E6) |
| Hero position | Upper-middle of the content area (centre at ≈ 36 % of the height in E1); scales to about 0.9 while scanning in module screens | INFERRED [clone-obs] |
| Headline | Returning user: **"Welcome back!"** E1 and E2 both show it. A first-run variant ("Welcome to CleanMyMac") is plausible by analogy with X but unseen for 5.x. | INFERRED [clone-obs, single source] |
| Subtitle | E1 uses "Start with a quick and extensive scan of your Mac." The Svelte clone carries the same line, and the X replica paraphrases it. **But the late-X landing (E10, 1_1) reads "Welcome to CleanMyMac X" / "Start with a nice and thorough scan of your Mac."** So the "quick and extensive" wording is either older X copy or genuine 5.x copy. | INFERRED (unresolved; §9.3 settles it) |
| Seasonal decoration | Late X framed the hero with pixel-style **snowflake** ornaments in winter (E10, 1_1 and 1_6). 5.x ships `Snowflakes1…3` + `EmitterMask` (E6). | VERIFIED [X-screenshot] + VERIFIED [3P-bundle]; INFERRED: 5.x shows a seasonal particle layer, switchable via `CustomThemes` |
| **Three intro rows/chips** | The bundle has `intro-category-quick-scan`, `intro-category-security-check` and `intro-category-system-tuneup` (32 × 32 pt) in `SmartCareModule`. VERIFIED [3P-bundle]. **Their labels and placement are unknown.** E1/E2 show **no** rows on the returning-user landing, so they probably appear on the **first-run** landing or a "what Smart Care does" panel. Likely meanings: quick scan · security check · system tune-up. | Assets VERIFIED; labels and placement **GAP** (§9.3 resolves with `plutil`) |
| Primary button | Round, about 80 pt, labelled **"Scan"**, centred on the content area, straddling the bottom edge, with a breathing halo. Its own bundle `CMM5UbiquitousButton` has a `default.metallib` glass shader. | Bundle VERIFIED [3P-bundle]; placement INFERRED [clone-obs ×2, VaderCleaner "per screenshots", E2]; X rationale ("goes beyond the application") VERIFIED for X (02 §5 Screen 1) |
| Background | Smart Care violet field: deep violet top-left (#4A129E → #1E0752 in E1) with a magenta glow behind the hero (#C02CC0). The real thing is a Metal shader (`CleanMyLiveBackground.framework`). | Shader VERIFIED [3P-bundle]; colours INFERRED [clone-obs] |
| Vendor product shot | "translucent violet sidebar, large dimensional Smart Care object, generous open space, and a single primary action" | VERIFIED [3P-hands-on] (E4) |

### 5.2 SC-2 Pre-flight (permissions)

There is no dedicated Smart Care pre-flight screen in any source. VERIFIED [vendor] (01 §9.1): without FDA the scan still runs but is incomplete; the vendor even advises running Smart Care *first* so that its components register with TCC, and only then granting FDA. The **Assistant** shows an FDA recommendation with **Allow Access**. INFERRED: a banner or recommendation, not a blocking screen.

### 5.3 SC-3 Scanning

```
┌ rail ┐  ‹                         Smart Care                                         ┐
│ ◔ SC │  ╭────────────────────────────────────╮ ╭──────────╮ ╭──────────╮            │
│ ◌    │  │       Looking for junk...          │ │Protection│ │Performance│           │
│ ◌    │  │                                    │ │          │ │          │            │
│ ◌    │  │      (Cleanup icon, animating)     │ │   ◇ icon │ │  ◇ icon  │ ← waiting:  │
│ ◌    │  │                                    │ │  peeking │ │  peeking │   dark glass│
│ ◌    │  │   ~/Library/Caches/com.foo.bar     │ ╰──────────╯ ╰──────────╯            │
│      │  ╰────────────────────────────────────╯   ← active card ≈2.3× wider, lit      │
│      │  ╭───────────────────╮ ╭───────────────────╮   in the module colour (bottom-   │
│      │  │ Applications      │ │ My Clutter        │    bright gradient)               │
│ ◉    │  ╰───────────────────╯ ╰───────────────────╯                                   │
└──────┘                      ( Stop )  ← ring fills with overall progress              ┘
```

| Aspect | Reconstruction | Status |
|---|---|---|
| Order | Cleanup → Protection → Performance → (Applications + My Clutter together). X ran its three pillars left to right in the same way (1_2: Cleanup done, Protection running, Speed waiting). | "One by one" VERIFIED [vendor]; X order VERIFIED [X-screenshot]; the 4-stage grouping INFERRED [clone-obs E1: "Applications and My Clutter share the last stage, like the original"] |
| Stage layout | Top row: Cleanup, Protection, Performance. Bottom row: Applications, My Clutter. While the top row is active it takes about 62 % of the height. When the last stage runs, the bottom row grows to about 64 %. The active card's width weight is 2.3 (top row) or 3.2 (bottom row) against 1 for the others. The cards **animate** between these sizes on a spring. | INFERRED [clone-obs E1] |
| Active card | Lit by a gradient from white 10 % at the top to the module colour at 95 % at the bottom; 26 pt semibold headline; the module's 3D icon animating (Smart Care's squeegee wipes, Cleanup's disc rocks, the others move gently); a one-line ticker of the current file name (middle-truncated, 12.5 pt, about 14 updates/s). | INFERRED [clone-obs E1]. Squeegee wipe frames `WiperFrame_1…6` exist: VERIFIED [3P-bundle] |
| Per-module headlines | Cleanup "Looking for junk..." · Protection "Looking for threats..." · Performance "Examining your system..." · Applications "Checking your apps..." · My Clutter "Analyzing your storage..." · whole-flow line "Scanning your Mac..." | INFERRED [clone-obs, single source]. These differ from X's pillar lines ("Finding unwanted files...", "Determining potential threats...", "Defining suitable tasks..." — E8), which hints they were taken from 5.x |
| Performance stage text | Instead of a file ticker: "Preparing tasks for performance optimization." | INFERRED [clone-obs E1] |
| Waiting cards | Dark glass (white about 7 % fill, 10 % hairline), module name top-left at 12.5 pt semibold, icon **peeking up from the bottom edge** | INFERRED [clone-obs E1] |
| Finished cards | The icon moves to the **top-right corner** and the metric appears at the bottom-left (e.g. "4.1 GB of junk / to clean") | INFERRED [clone-obs E1] |
| Live counters | **X:** a **running total sits to the right of the Stop button** ("3,13 GB" in 1_2), and each finished pillar shows its metric plus **Review Details…** while the others are still scanning. VERIFIED [X-screenshot]. **5.x:** no source; each card fills in its metric as its stage finishes (E1). | VERIFIED for X; INFERRED for 5.x: keep a running total next to Stop |
| Headline while scanning | **X:** "Looking at it..." + a playful wait line ("Give me a moment. We all wish it was easy as pie."). Pillar lines "Removes unneeded junk" (done, with ✓), "Determining potential threats..." with a path ticker under it, "Defining suitable tasks..." / "Waiting...". VERIFIED [X-screenshot] 1_2. **5.x:** per-card headlines (row above). | X VERIFIED |
| **Stop** | The round button becomes **"Stop"** with a white progress ring (3 pt, round caps) tracing overall progress. | INFERRED [clone-obs E1, E7 "busy it spins a ring and can become Stop"]; X had Stop (VERIFIED for X) |
| Rail | Collapsed to icons; Smart Care icon with a progress pie (§4.3) | INFERRED [clone-obs] |
| Background | The canvas stays Smart Care violet. Only the active card carries the module colour. | INFERRED [clone-obs E1] |
| Duration | About 1 minute (54 s on Tahoe in one review) | VERIFIED [vendor/press] via 02 §8 |

### 5.4 SC-4 Results

```
┌ rail ┐  ‹ Start Over                Smart Care                                       ┐
│ ● SC │           Your tasks are ready to run. Look what we found:   ← ~22 pt medium  │
│ ◌    │  ╭─────────────────╮ ╭─────────────────╮ ╭─────────────────╮                  │
│ ◌    │  │☑ Cleanup     ◆  │ │☑ Protection  ◆  │ │☑ Performance ◆  │ ← icon bleeds off │
│ ◌    │  │                 │ │                 │ │                 │   the top-right   │
│ ◌    │  │ 23.1 GB of junk │ │ 1 threat        │ │ 2 tasks         │ ← metric 21 pt sb │
│ ◌    │  │ to clean [Review]│ │ to remove[Review]│ │ to run  [Review]│ ← sub 12.5 pt 60%│
│      │  ╰─────────────────╯ ╰─────────────────╯ ╰─────────────────╯                  │
│      │  ╭─────────────────────────╮ ╭─────────────────────────╮                      │
│      │  │☑ Applications        ◆  │ │☑ My Clutter          ◆  │                      │
│      │  │ 1 important update      │ │ 12 duplicates           │                      │
│ ◉    │  ╰─────────────────────────╯ ╰─────────────────────────╯                      │
└──────┘                         ( Run )                                                ┘
```

| Aspect | Content | Status |
|---|---|---|
| Tiles | One per routine: Cleanup, Protection, Performance, Applications, My Clutter | VERIFIED [vendor] (Smart Care KB via 02 §1 item 4) |
| Default selection | All selected; clear a tile's checkmark to skip it | VERIFIED [vendor] (02 §1 item 5) |
| Tile metrics | Cleanup = size that can be safely removed; Protection = number of threats; Performance = number of maintenance tasks; Applications = available updates; My Clutter = number of duplicates | VERIFIED [vendor] |
| Real values seen | 23.1 GB · 1 threat · 2 maintenance tasks · 1 important update (CleanMyMac 5.5.7, Chinese UI, translated) | VERIFIED [3P-hands-on] (E3) |
| Grid | 3 + 2, equal sizes at results; the top row is about 50 % of the height; 10 pt gaps; radius 16 | INFERRED [clone-obs E1] |
| Tile anatomy | Checkbox (22 pt, radius 6) + module name at top-left; module 3D icon at about 70 % size, positioned top-right and partly clipped by the tile ("bleeding off the corner", also E7); big metric (≈21 pt semibold) and a muted second line ("to clean", "to run"); **Review** capsule bottom-right (12.5 pt semibold, white 16 % fill, 28 % hairline, radius 8) | INFERRED [clone-obs E1 + E7]; Review on each tile VERIFIED [vendor] |
| Headline | "Your tasks are ready to run. Look what we found:" | INFERRED [clone-obs, single source]. X used "Okay, here's what I found." (E8), so this differs from X |
| **Nothing found** | **No 5.x evidence.** **X (real):** the empty Protection pillar shows a large green **"OK"** in place of a number, the caption "No threats found", **no ✓ selection mark** (Cleanup and Speed have one) and no Review Details button. VERIFIED [X-screenshot] 1_3. | **GAP** for 5.x → INFERRED: the tile keeps its place, shows a success word in the metric slot in the success colour, hides the checkbox and Review |
| X results header (for contrast) | "Alright, here's what I've found." + "All of the tasks to keep your Mac clean, safe, and optimized are waiting. Run them all at once!"; pillar captions "Removes unneeded junk" / "Neutralizes potential threats" / "Increases system performance"; metric styles "3,13 GB" (cyan, light), "OK" (green), "2" + "tasks to run" | VERIFIED [X-screenshot] 1_3 |
| **Excluded in Settings** | Tile shown **dimmed**; Settings path: Settings → Scanning → Smart Care, deselect a module/category/group (parents cascade) | VERIFIED [vendor] (02 §1 item 6). Exact opacity and badge: GAP |
| Run button | The round button changes label to **"Run"** (same position and size) | "Run" VERIFIED [vendor]; round placement INFERRED [clone-obs E1] |
| Summary next to Run | **No evidence** of a "Selected: …" caption. E7's generic pattern has a "selection caption + Clean orb". | **GAP** → INFERRED: none, or a short caption above the orb |
| Start Over | Title strip, top-left; asks for confirmation | VERIFIED [vendor] (position + confirmation); copy **GAP** |
| Sound at scan end | E1 plays a short sound when results appear. `SoundsEnabled` exists in 5.x prefs. | Key VERIFIED [3P-bundle-like] (09 §4.8 A); event INFERRED |

**Side finding for 03-cleanup.** The 5.5.7 audit lists "Extra Binaries" (5.6 GB) next to system junk, mail attachments and Trash in the Cleanup results. In its second round it calls the same group "Universal Binaries" inside the Cleanup manager. 5.x may have renamed *Universal Binaries* to **Extra Binaries** (13-helpcenter also quotes "extra binaries" from a KB description). VERIFIED [3P-hands-on] that the term appears; exact label GAP.

### 5.5 SC-5 Review ("Manager")

| Aspect | Reconstruction | Status |
|---|---|---|
| Entry | **Review** on a tile, or a module dashboard's "Manage …"/"Review All …" buttons (e.g. "Manage My Applications", "Review All Files"; 01 §5.2) | VERIFIED [vendor] (button names) |
| Transition | The Manager **zooms up from the button that opened it** over the receding dashboard, and zooms back into it on Back | INFERRED [clone-obs E5] |
| Surface | A **white card** (light surface) over the dark canvas, with a **magenta accent** for checkboxes and the primary action, whatever the module's hue | INFERRED [clone-obs E5: "The reference Manager uses a magenta accent on a white surface"] |
| Layout | Header (**Back**, centred "<Module> Manager" title, **search**, **"Sort by:"**) · left pane (sub-areas) · middle pane (groups with tri-state checkboxes and sizes or counts) · right pane (group heading + description, a "Select:" menu, item rows) · footer ("N Items Selected" + the destructive primary button) | INFERRED [clone-obs E5]; the full anatomy is consolidated in sibling 20-gap-02 §2 item 4 (REPLICA-5). Facet names per module in 03/06/07 |
| Back | "‹ Back" in the title strip | INFERRED [clone-obs] |

**Ours.** 09 §B.8.7 already specifies a two-pane review list. Recommendation: render it as a **light, card-like "sheet surface"** (white at about 92 % with material, ink #14151F) laid over the dark canvas, with our **own** accent per module. Do not use a single magenta accent, which is the vendor's tell. Zoom-from-source with `matchedGeometryEffect`, falling back to a crossfade under Reduce Motion.

### 5.6 SC-6 Pre-run conflicts

**New, VERIFIED [X-screenshot] 1_4:** the one-click flow **does** prompt to quit apps, which closes 02 §15 gap 4 for X.
- **When:** *after* Run is pressed, while the running screen is up (Stop still visible behind the dimmed canvas), not as a pre-run confirmation.
- **Look:** a centred light modal card.
- **Content:** title "Some applications should be quit."; one explanatory line (quit them so all their related items can be cleaned); one row per app with its icon, name and a **Quit** button. In the capture the apps were Claude, Code and Safari.
- **Footer:** **Ignore** (left) and **Quit All** (right, blue, default).

The same component appears in Performance (05 §3, 8_2) and Cleanup (20-gap-02 §3.9). INFERRED: 5.x Smart Care uses the same component; Ignore = skip those apps' items.

Admin prompt via the Agent: see 02 §5 Screen 6.

### 5.7 SC-7 Running

| Aspect | Evidence | Status |
|---|---|---|
| What runs | "Run completes the Smart Care tasks": cleanup, threat removal, maintenance tasks, app updates, duplicate removal | VERIFIED [vendor] |
| Visuals | 5.x ships a **6-frame squeegee "wipe" sprite** (`WiperFrame_1…6`) in the root catalog, "used during cleaning" | VERIFIED [3P-bundle] (E6); where and when it plays: INFERRED (on the hero/display during Run) |
| X running screen (real) | The finished pillar's art drifts up and fades; the active pillar's art sits left of centre. On the right: the headline "Optimizing Your System..." over a task list. Each row has an icon, a name and a trailing status: a size + **✓** when done ("Trash Bins 342,3 MB ✓"), a size + **yellow ⚠** when only partly done ("System Junk 876,5 MB ⚠"), "Running..." + spinner, or "•••" when waiting. The round button reads **Stop** with a green progress ring. | VERIFIED [X-screenshot] 1_5 |
| Per-area progress lines | X headlines per phase (cleaning / protecting / optimizing); 1_5 shows "Optimizing Your System...". 5.x unknown. | X VERIFIED; 5.x **GAP** |
| Stop during Run | **X: yes**, the round button reads Stop during Run (1_4, 1_5). VERIFIED [X-screenshot]. No 5.x evidence. | INFERRED for 5.x: Stop exists, effective between items |
| Order | **X:** the running list went System Junk → Trash Bins → Flush DNS Cache → Free Up RAM (1_5), i.e. cleanup before speed tasks. The Protection pillar had nothing to do (OK). 5.x: no evidence. | X VERIFIED [X-screenshot]; INFERRED: ours runs Protection first, then cleanup, then tasks, with updates last (02 §5 Screen 7) |

### 5.8 SC-8 Completion

| Aspect | Evidence | Status |
|---|---|---|
| 5.x wording and layout | None found | **GAP** |
| X pattern (real) | Layout: the hero display, cropped by the left edge, on the left; text on the right. Headline **"Well done!"**, subtitle "Your Mac is in great shape.", then three rows, each with a pillar icon, a green ✓ ring, a big value and a caption: "1,22 GB" / "Unneeded junk removed"; "Protected" / "No potential threats found"; "2 Tasks" / "Mac's performance topped out". A **Share Results** capsule follows. **"‹ Start Over"** sits top-left, and a yellow **"⚠ View Log"** sits bottom-left (shown because System Junk was only partly cleaned). No round button and no centred title. | VERIFIED [X-screenshot] 1_6 (the E8 replica's "Nice work!" is a paraphrase) |
| CLI pattern | "Cleanup complete!", ✓ rows with sizes, "<size> cleaned!", "<n> items removed" | VERIFIED [vendor] (02 §1 item 15) |
| Sound | `SoundsEnabled` exists; CMM3 had "clean finished" sounds | INFERRED: a completion sound plays |
| After | Mac Health / Assistant update; `SmartCareReminderEnabled` drives later reminders | VERIFIED [vendor] / [3P] |

### 5.9 Start Over confirmation

VERIFIED [vendor]: Start Over asks for confirmation (02 §1 item 3). The alert copy and buttons are **GAP**.

INFERRED shape: a standard `NSAlert` sheet with a question title (discard results and scan again?), a primary "Start Over" button and "Cancel".

**Ours** (original copy): title "Scan again?", body "Your current results and selections will be cleared.", buttons **Scan Again** (default) / **Cancel**. Skip the alert when the user has not changed any selection (INFERRED kindness; the vendor always asks).

### 5.10 X → 5.x copy and flow differences (to avoid mixing generations)

| Moment | Late X (VERIFIED [X-screenshot], E10 route 1) | 5.x (best evidence) |
|---|---|---|
| Idle title | "Welcome to CleanMyMac X" | "Welcome back!" for returning users (INFERRED [clone-obs]); first-run unknown |
| Idle subtitle | "Start with a nice and thorough scan of your Mac." | "Start with a quick and extensive scan of your Mac." (INFERRED [clone-obs]; possibly older X copy) |
| Scanning headline | "Looking at it..." + a wait line | "Scanning your Mac..." + per-card lines (INFERRED [clone-obs]) |
| Pillar/card lines | "Removes unneeded junk" · "Determining potential threats..." · "Defining suitable tasks..." · "Waiting..." | "Looking for junk..." · "Looking for threats..." · "Examining your system..." · "Checking your apps..." · "Analyzing your storage..." (INFERRED [clone-obs]) |
| Live total | Size next to Stop | Unknown |
| Results headline | "Alright, here's what I've found." + "…Run them all at once!" | "Your tasks are ready to run. Look what we found:" (INFERRED [clone-obs]) |
| Empty pillar | Green "OK" + "No threats found" | Unknown |
| Layout | 3 columns (Cleanup / Protection by Moonlock / Speed) with ✓ marks and "Review Details…" | 5 tiles (3 + 2) with checkbox and Review (VERIFIED structure) |
| Quit prompt | During Run: "Some applications should be quit." · Quit / Ignore / Quit All | Unknown (INFERRED same component) |
| Running | "Optimizing Your System..." + task list with ✓ / ⚠ / Running… / ••• | Unknown (squeegee wipe sprite exists) |
| Completion | "Well done!" + "Your Mac is in great shape." + three ✓ rows + Share Results + ⚠ View Log + Start Over | Unknown |

### 5.11 What to take from the real X journey for our build (INFERRED)

These conventions are **functional** (state visibility, recoverability), not brand. Carrying them into Checkup is safe and makes it feel complete:
1. **Title-strip rules:** a centred module name only while busy or showing results; Start Over on results and completion only.
2. **A progress indicator on the sidebar or rail row** of the running flow (a pie or ring), so that the user can browse other modules while Checkup runs and still see it.
3. **A live total next to the Stop orb** during scanning (the bytes found so far).
4. **An empty state that replaces the metric with a success word in the success colour, and drops the checkbox.**
5. **The quit-apps prompt after Run**, listing the apps with per-app Quit plus Ignore and Quit All. 02 §5 Screen 6 already specifies ours: "Quit & Continue / Skip These Items / Cancel".
6. **A running list with four row states** (done ✓ + size, partial ⚠ + size, running spinner, waiting •••).
7. **Completion:** three or five result rows with ✓, a share or copy-summary action (ours: "Copy Summary"), and a **View Log** link that turns into a warning style when anything was skipped or partial. No orb on this screen.

All copy must be ours (09 §B.12). For example: "All set." / "Here's what changed."; "Partially cleaned (in use)".

---

## 6. (d) The Performance tile on macOS 15 / 26

**Vendor facts:**
- The KB says the Smart Care Performance step "suggests running periodic maintenance scripts and the Flush DNS Cache task". VERIFIED [vendor] (02 §3.1).
- `periodic` (`/usr/sbin/periodic`, `/etc/periodic`) is **absent** on macOS 15 and 26. VERIFIED (02 §1 item 14).
- The vendor already **filters maintenance tasks per macOS version**: a recent X build listed only 7 tasks, with "Run Maintenance Scripts" missing on that OS. VERIFIED [3P-hands-on] (05 §1 item 3).
- **A 5.5.7 run in Aug 2026 showed "2 maintenance tasks"** on the results screen. VERIFIED [3P-hands-on] (E3); the macOS version is not stated, but the date and audit context suggest 26.x.
- 5.0.5 added **Free Up Purgeable Space**. VERIFIED [vendor].
- The CLI's `optimize` offers exactly `ram | purgeable`. VERIFIED [vendor] (02 §2).
- The erluxman clone hard-codes the Smart Care task list as **"Flush DNS Cache"** and **"Free Up Purgeable Space"** (two tasks; tile "2 tasks / to run"). INFERRED [clone-obs].
- **The late-X Smart Scan** (Claude desktop app visible, so 2025 or later; exact macOS not visible) showed "2 tasks to run". In Run those were exactly **"Flush DNS Cache"** and **"Free Up RAM"**, after System Junk and Trash Bins. Completion: "2 Tasks". VERIFIED [X-screenshot] 1_3, 1_5, 1_6 (05 §2 already noted 1_5). No "Run Maintenance Scripts" row, which fits a macOS without `periodic` (or one where the scripts had run recently).

**Conclusion (INFERRED, moderately strong).** On macOS 15/26 the Performance tile shows **2 tasks**, most likely **Flush DNS Cache + Free Up RAM**, the direct X precedent. Free Up Purgeable Space (added in 5.0.5) is the plausible alternative or third. Run Maintenance Scripts is hidden because `periodic` is missing. The KB sentence is legacy wording from macOS ≤ 14.

**Ours.** The Checkup Performance tile = "due" tasks computed at scan time:
- `dnsFlush` is always due (cheap, root via helper; skip under an active VPN, per Mole, 05).
- `purgeable` is due when the CacheDelete purgeable estimate is ≥ 1 GB (05 §4.2).
- `periodicScripts` is due only if `FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic")` **and** the last `/var/log/daily.out` is older than 7 days (01 §5.2 fact-check).
- `ram` matches the vendor precedent, but it is offered **only when it can help**: memory pressure is at warn or critical (`DispatchSource.makeMemoryPressureSource` / `kern.memorystatus_vm_pressure_level`), or swap used is over 1 GB. Otherwise it is omitted, given the efficacy criticism in 05 §5. It always remains available in Performance and the Monitor.

Metric copy: "2 tasks" / "ready to run". Empty: "Nothing due".

---

## 7. (e) Smart Care's duplicates step

- **Scope.** "Scans for duplicate files in the Downloads folder only". VERIFIED [vendor] (02 §1 item 2; 07 §1 and §3; 13 §1 item 2).
- **Within vs across.** Because only `~/Downloads` is enumerated, a duplicate pair can only be formed from two files that are **both inside Downloads**, including its subfolders (INFERRED; a Downloads file that duplicates something in `~/Documents` cannot be detected without scanning `~/Documents`). Nothing in any source suggests a cross-folder comparison. VaderCleaner reads the vendor the same way: "Smart Care, which surfaces duplicate files in Downloads", and it walks only that folder. INFERRED [clone-obs].
- **Which copy is kept.** **Undocumented** (02 §15 gap 5; 07 §5 and its gaps list; 13 §3 duplicate-files digest). Known context:
  - In My Clutter, "Apply smart selection" keeps one per group, and marketing says it "pre-picks the user-side copies and avoids system files". VERIFIED [vendor] (07).
  - MacPaw's Gemini 2 had keeper filters (Automatically / Newest / Oldest / Any). VERIFIED [3P] (07 §5).
  - The Trash Bins KB lists a separate "Gemini Duplicates" trash category, which points to recoverable removal. VERIFIED [vendor] (02 §15).
- **Ours (INFERRED, unchanged from 02 §4.3, made precise):**
  1. Group by size, then SHA-256 of the full content (exact matches only). Ignore 0-byte files and bundles (`.app`, `.pkg` directories). Treat hard links and APFS clones (same `fileResourceIdentifierKey`) as **one** file, not duplicates.
  2. Keeper ranking: (a) the name without a browser re-download suffix (` (1)`, ` 2`, `-1`, ` copy`); (b) the oldest `creationDate` (the first download); (c) the shallowest path; (d) lexical order.
  3. Default selection = every non-keeper. Removal → `FileManager.trashItem` (recoverable), with an Undo toast and the "Undo duplicates" completion action.
  4. Metric: "12 duplicates", subtitle "in Downloads · 180 MB".

---

## 8. (f) First-launch onboarding and light mode

### 8.1 What we know about the 5.x first launch

| Step | Evidence | Status |
|---|---|---|
| Intro video | `Features_IntroFlow.bundle/…/IntroVideo.mp4`: a feature module dedicated to an "intro flow", with one video | VERIFIED [3P-bundle] (E6). Duration and copy: GAP |
| Licence | "Unlock Full Version" (top-right) → trial / buy / activate → MacPaw Account | VERIFIED [vendor] (01 §9.1) |
| Background items | macOS posts "Background Items Added" when the Menu and Health Monitor register; the app watches for them being disallowed | VERIFIED [vendor] (01 §8, §9.1) |
| Full Disk Access | KB: run Smart Care, then System Settings → Privacy & Security → Full Disk Access → toggle. The Assistant shows a recommendation with **Allow Access**. The Health score counts "FDA granted". | VERIFIED [vendor] (01 §9.1). **A dedicated FDA onboarding screen is not evidenced.** |
| Notifications | No evidence of a pre-prompt. The system prompt appears when the app first requests authorisation. | **GAP** |
| Privileged helper | Installed lazily on the first root operation (admin prompt) | VERIFIED [vendor] (01 §9.1) |
| Landing | Smart Care | VERIFIED [vendor/press] (02 §1 item 1) |

**Best reconstruction (INFERRED):** IntroVideo welcome (skippable) → (optional licence/trial choice) → Smart Care landing. Permissions are handled **contextually**: FDA through the Assistant recommendation after the first scan, the helper on first root task, notifications on first use. The `intro-category-*` chips (§5.1) may belong to this flow's last card or to the first-run Smart Care landing.

**Ours.** Keep 01 §9.2 / 09 §B.8.12 (4–5 live SwiftUI steps, no video). Add one detail from this pass: since the vendor never blocks on FDA, our FDA step must offer **Later**. The Checkup tiles then carry the "Limited" chip (09 §B.8.6), mirroring the vendor's "scan still runs but incomplete".

### 8.2 Does the canvas change in light mode?

| Evidence | Points to |
|---|---|
| Three clones built from 5.x references are **dark-only** ("No light scheme — the canvas gradient IS the brand", E7; E1; VaderCleaner) | Canvas ignores system appearance |
| E4 calls the reference a "dark purple canvas" | Dark |
| The in-app release-notes page forces `color-scheme: only light` (09 §4.3) | Some embedded surfaces are light whatever the appearance |
| Review **Managers** are **white cards** (E5) | The app mixes a dark canvas with light cards; this is not a dark/light theme switch |
| `CustomThemes` preference key (09 §4.5) | Seasonal/national theme layer; semantics unconfirmed |

**Conclusion (INFERRED, moderate):** the 5.x canvas **does not change** between light and dark mode. Light surfaces (Managers, release notes) are light in both modes. §9.5 verifies this in one minute.

**Ours:** 09 §B.3.4 already defaults to an always-dark canvas, with an optional "Daylight" theme. Keep it.

---

## 9. Hands-on verification kit (for the owner's Mac mini)

Every remaining gap can be closed locally with the vendor's free 7-day trial. This is research on software the user has installed. **Do not copy any string, image or sound into our app;** record structure and measurements only. Install it from the vendor's site, run the checks, then uninstall (Homebrew cask `cleanmymac` has a complete `zap` stanza, 02 §1 item 13).

### 9.1 Paths

```bash
APP="/Applications/CleanMyMac_5.app"          # direct edition (MAS: CleanMyMac_5_MAS.app)
BIN="$APP/Contents/MacOS/$(defaults read "$APP/Contents/Info" CFBundleExecutable)"
PROC="$(defaults read "$APP/Contents/Info" CFBundleName)"   # process name for System Events
```

### 9.2 Window size (default and minimum)

```bash
# Fresh default: quit the app, remove saved frames, relaunch
defaults read com.macpaw.CleanMyMac5 2>/dev/null | grep -i "NSWindow Frame"   # note the existing value first
osascript -e "tell application \"System Events\" to tell process \"$PROC\" to get {position, size} of window 1"
# Minimum: drag the window to its smallest size, then rerun the line above.
```

### 9.3 Every UI string (resolves the headline, chips, empty-state, completion and Start Over copy)

```bash
mkdir -p ~/cmm5-strings && cd ~/cmm5-strings
find "$APP" -path '*en.lproj/*.strings' -print0 | while IFS= read -r -d '' f; do
  out="$(echo "$f" | sed "s|$APP/||; s|/|_|g").json"
  plutil -convert json -o "$out" "$f" 2>/dev/null
done
grep -l -i "start over"     *.json   # find the module that owns the confirmation
grep -h -o -i '"[^"]*smart care[^"]*"' *.json | sort -u | head -50
grep -h -i -E 'welcome|look what|tasks are ready|nothing|all clear|up to date' *.json | head -80
# Intro chips: the strings file next to SmartCareModule.framework
ls "$APP/Contents/Frameworks/" | grep -i -E 'smartcare|intro'
```
(Also check `*.stringsdict` for plural forms, e.g. "%d threats". If the app uses `.xcstrings`, they compile to `.strings`, so the loop above still finds them.)

### 9.4 Liquid Glass and SDK

```bash
otool -l "$BIN" | grep -A4 LC_BUILD_VERSION      # 'sdk 26.x' ⇒ system chrome adopts Liquid Glass automatically
plutil -p "$APP/Contents/Info.plist" | grep -i -E 'compatib|LSMinimumSystemVersion'
```
Then take screenshots on macOS 26 of the window, a sheet (Start Over), the Settings window and a popover. Compare the traffic-light/toolbar region with a system app.

### 9.5 Light vs dark canvas

```bash
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'
screencapture -o -w ~/cmm5-light.png     # click the CleanMyMac window
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
screencapture -o -w ~/cmm5-dark.png
```
(Terminal needs Screen Recording permission on macOS 15/26.)

### 9.6 Exact on-screen labels per state (Accessibility tree)

The app supports VoiceOver since 5.0.7 (VERIFIED [vendor]), so its elements carry AX labels. In each state (landing, scanning, results, review, running, done), run:

```bash
cat > /tmp/axdump.js <<'JS'
ObjC.import('Foundation');
function run(argv) {
  const name = argv[0] || 'CleanMyMac';
  const se = Application('System Events');
  const w = se.processes.byName(name).windows[0];
  const lines = [];
  w.entireContents().forEach(e => {
    try {
      const pos = e.position(), size = e.size();
      lines.push([e.role(), e.name() || '', e.description() || '', String(e.value() || ''),
                  pos.join(','), size.join('x')].join(' | '));
    } catch (_) {}
  });
  return lines.join('\n');
}
JS
osascript -l JavaScript /tmp/axdump.js "$PROC" > ~/cmm5-ax-$(date +%H%M%S).txt
```
(The terminal app needs Accessibility permission. Accessibility Inspector, in Xcode → Open Developer Tool, shows the same tree with frames. The position and size columns give the sidebar width, row height and tile sizes.)

### 9.7 Assets, sounds and the intro video

```bash
find "$APP" \( -name '*.caf' -o -name '*.aif*' -o -name '*.wav' -o -name '*.m4a' -o -name '*.mp3' \) | sed "s|$APP/||"
find "$APP" -name 'IntroVideo.mp4' -exec mdls -name kMDItemDurationSeconds {} \;
find "$APP" -name Assets.car | grep -i -E 'SmartCare|MainAppUI|IntroFlow' | while IFS= read -r car; do
  echo "== $car"; xcrun assetutil --info "$car" | grep -E '"Name"' | sort -u; done
```

### 9.8 Capture checklist (fill in and append to this file)

| # | Item | Value |
|---|---|---|
| 1 | Default window size (pt) | |
| 2 | Minimum window size (pt) | |
| 3 | Sidebar width expanded / collapsed; row height | |
| 4 | Sidebar rows in order (5.7.1) and any dividers | |
| 5 | Is "Assistant" (or Health) still a bottom row? | |
| 6 | Does the rail collapse during scan / results / module scans? | |
| 7 | Landing headline (first run vs returning), subtitle, chips | |
| 8 | Scanning: order, per-module lines, Stop present? | |
| 9 | Results headline; each tile's metric line and sub-line | |
| 10 | Nothing-found tile; excluded (dimmed) tile | |
| 11 | Text next to Run? | |
| 12 | Running visuals; Stop during Run? | |
| 13 | Completion headline, metrics, sound | |
| 14 | Start Over alert title and buttons | |
| 15 | Performance tile tasks on macOS 26 | |
| 16 | Duplicates: which copy is unchecked by default | |
| 17 | Onboarding screens (count, order, permission screens) | |
| 18 | Light-mode canvas changes? | |
| 19 | `LC_BUILD_VERSION` sdk; Liquid Glass visible where? | |
| 20 | Position of the bell and "Unlock Full Version" | |

---

## 10. Delta to our blueprints (09 §B, 02 §5) from this pass

All INFERRED and original. None of these copies vendor copy or art.

1. **Checkup scanning stage.** Offer the **"stage cards"** layout as the primary scanning view instead of (or above) the checklist under the hero in 09 §B.8.5. Five glass cards (3 + 2); the active card expands on a spring (`.spring(response: 0.5, dampingFraction: 0.86)`), takes the module tint, shows our own line ("Sweeping caches…", "Checking for threats…", "Lining up maintenance…", "Looking for updates…", "Comparing downloads…") and a middle-truncated path ticker capped at 10 Hz. Finished cards keep their metric. This matches the vendor's *pattern* (a functional equivalent), while text, icons and colours stay ours.
2. **Rail collapse.** Collapse for Checkup scan, run and results, with a progress-ring badge on the Checkup icon. Re-expand on Start Over or Done. No session latch.
3. **Title strip.** The left slot holds "‹ Start Over" (results) or "‹ Back" (review). The centre holds the module name (hidden on landings). The right side holds the bell, plus "Unlock" only if we ever add licensing (we will not: personal build). This matches 09 §B.8.1; no change.
4. **Results grid.** 09 §B.8.6 uses a 3 × 2 grid with a Summary tile. Keep it: the sixth tile is our original addition and fills the vendor's empty slot in a 3 + 2. Add the **nothing-found** state ("All good" + ✓, checkbox hidden) and the **excluded** state (35 % opacity + "Skipped" chip), already specified there.
5. **Review surface.** Render 09 §B.8.7 as a light sheet-card over the dark canvas, zooming from the Review button. Use our per-module accent (not one global magenta).
6. **Performance tile logic.** As in §6 above: DNS always; RAM only under memory pressure; purgeable when large; periodic only if the binary exists and the scripts are stale.
6a. **Journey conventions from the real X flow** (§5.11): rail-row progress ring; live total by the Stop orb; success-word empty state; quit prompt after Run; four-state running list; completion with ✓ rows, Copy Summary and a warning-styled View Log. No orb on completion.
7. **Duplicates keeper.** The ranking in §7 above, with Trash + Undo.
8. **Onboarding.** FDA step has **Later**; the Checkup still runs, in "Limited" mode.
9. **Window drag.** Set `window.isMovableByWindowBackground = true` (canvas only; controls opt out via `mouseDownCanMoveWindow`).
10. **Module transitions.** Blur-fade (blur 0 ↔ 22, opacity, scale 0.97) between modules, 0.42 s ease-in-out, and a plain crossfade under Reduce Motion. INFERRED [clone-obs E1: "as the original does between modules"].

---

## 11. Image URLs

**5.x vendor screenshots found: none.** All candidate hosts (macpaw.com, apps.apple.com / mzstatic.com, setapp.com, review sites, YouTube) were unreachable in this session, and the App Store lookup JSON (`screenshotUrls`, `releaseNotes`) could not be fetched. No GitHub-hosted copy of the lookup JSON for id 1339170533 exists (code search: 0 hits for `"trackId": 1339170533`).

**Secondary images that were found and viewed:**

| Image | What it shows | Label |
|---|---|---|
| https://raw.githubusercontent.com/erluxman/learn/main/docs/screenshot-cleaner.png (1600 × 979) | The erluxman clone's Smart Care landing: violet canvas, six-row sidebar + Assistant, magenta display hero with squeegee, "Welcome back!", round Scan straddling the bottom edge | INFERRED [clone-obs] |

**Real vendor screenshots of CleanMyMac X (predecessor) Smart Scan, viewed this pass** (dora-ai route 1; 2180 × 1288 px each):

| Step | State | URL |
|---|---|---|
| 1_1 | Landing ("Welcome to CleanMyMac X", Scan) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/1/image.png |
| 1_2 | Scanning ("Looking at it...", Stop + live total) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/2/image.png |
| 1_3 | Results ("Alright, here's what I've found.", Run) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/3/image.png |
| 1_4 | Quit-apps prompt during Run | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/4/image.png |
| 1_5 | Running ("Optimizing Your System...", task list) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/5/image.png |
| 1_6 | Completion ("Well done!", Share Results, View Log, Start Over) | https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/6/image.png |

The same dataset holds other X modules: routes 2–8 are covered in 05 and 20-gap-02; route 9 Uninstaller, 10 Updater, 11 Extensions, 12 Space Lens, 13 Large & Old Files and 14 Shredder exist (`node_desc.json` read; images not reviewed here).

**Pages to fetch next session** (in priority order), for the image URLs:
1. `https://itunes.apple.com/lookup?id=1339170533&entity=macSoftware` → `screenshotUrls[]`, `releaseNotes`, `version`, `currentVersionReleaseDate`.
2. `https://macpaw.com/cleanmymac` (hero product shot) and `https://macpaw.com/support/cleanmymac/knowledgebase/smart-care` (KB inline images).
3. `https://setapp.com/apps/cleanmymac` (Setapp gallery).
4. MacStories / 9to5Mac 2024 launch articles (01 §15) and the allaboutcookies Tahoe review cited in 02 §8.

---

## 12. Remaining gaps (after this pass)

| # | Gap | Best current answer | Close with |
|---|---|---|---|
| 1 | Default / minimum window size | Unknown; ours 1180 × 740 / 1040 × 680 | §9.2 |
| 2 | 5.7 sidebar rows (My Activity row? "Tools" vs "My Tools"? Assistant at the bottom?) | Reconstruction in §4.1 | §9.6 |
| 3 | Rail collapse | Likely (three clones) | §9.8 item 6 |
| 4 | Intro chip labels and placement | Assets exist; labels unknown | §9.3 |
| 5 | Landing headline (first run) | "Welcome back!" for returning users (clone) | §9.3 |
| 6 | Scanning copy, Stop | Clone strings; Stop likely | §9.3, §9.6 |
| 7 | Results headline, empty and dimmed tiles, caption by Run | Clone headline; others unknown | §9.3, §9.6 |
| 8 | Running visuals, Stop during Run | X: task list + Stop (VERIFIED); 5.x squeegee wipe likely | Screen recording |
| 9 | Completion copy, metrics, sound | X: "Well done!" + ✓ rows + Share Results + View Log (VERIFIED); 5.x unknown | §9.3, §9.7 |
| 9a | Quit prompt in Smart Care | X: yes, during Run (VERIFIED); 5.x INFERRED same | Run Smart Care with Safari open |
| 10 | Start Over alert copy | Unknown | §9.3 |
| 11 | Performance tile on 15/26 | 2 tasks: DNS + RAM (X precedent), purgeable as the alternative (INFERRED) | §9.8 item 15 |
| 12 | Duplicate keeper rule | Unknown | Test with 3 copies in Downloads |
| 13 | Onboarding sequence | IntroVideo + contextual permissions (INFERRED) | Fresh install on a new user account |
| 14 | Light mode | Canvas stays dark (INFERRED) | §9.5 |
| 15 | Liquid Glass | Unknown | §9.4 |
| 16 | Bell / Unlock positions | Top-right (INFERRED / VERIFIED for Unlock) | Screenshot |

---

## 13. Sources

**Vendor (via earlier reports, which fetched them):**
- Smart Care KB — https://macpaw.com/support/cleanmymac/knowledgebase/smart-care (02 §1, §3.1)
- Full Disk Access KB — https://macpaw.com/support/cleanmymac/knowledgebase/full-disk-access (01 §9.1)
- Installation and activation KB ("Unlock Full Version") — https://macpaw.com/support/cleanmymac/knowledgebase/installation-activation (01 §9.1)
- Missing features / feature table — https://macpaw.com/support/cleanmymac/knowledgebase/missing-features (01 §5.1)
- Space Lens KB — https://macpaw.com/support/cleanmymac/knowledgebase/space-lens (01 §5.1)
- What's New (5.6.0 Notification Center, 5.7.0 Email Cleanup) — https://macpaw.com/cleanmymac/whats-new (01 §6)
- DevMate cumulative notes 5.0.0–5.3.1 — https://updates.devmate.com/releasenotes/50301.0.2601271414/com.macpaw.CleanMyMac5.html (local copy re-read this pass: 5.0.5 purgeable, 5.0.7 VoiceOver / Reduce Motion, 5.1.0 Space Lens, 5.2.1 Cloud Cleanup, 5.2.6 Smart Insights, 5.3.0 Dropbox)
- DevMate appcast (minimumSystemVersion 11.0) — https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/ (09 §4.2)

**Third-party, read this pass (raw GitHub):**
- E1 https://raw.githubusercontent.com/erluxman/learn/main/Sources/Learn/Cleaner.swift
- E1 https://raw.githubusercontent.com/erluxman/learn/main/Sources/Learn/CleanerIcons.swift
- E2 https://raw.githubusercontent.com/erluxman/learn/main/docs/screenshot-cleaner.png and README https://raw.githubusercontent.com/erluxman/learn/main/README.md
- E3 https://raw.githubusercontent.com/yangyihang96/StorageCleanerMac-OpenSource/main/docs/COMPETITIVE_AUDIT_1.9.12.md
- E4 https://raw.githubusercontent.com/medlars/verdictui/main/docs/workbench-design.md
- E5 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/ApplicationsManagerView.swift
- E5 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/ProtectionDashboardView.swift
- E5 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleaner/SettingsScanningTab.swift
- E5 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/master/VaderCleanerUITests/SmartScanUITests.swift and https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleanerTests/RailCollapseTests.swift
- E5 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/VaderCleanerCore/Sources/VaderCleanerCore/DuplicateScanner.swift (keeper = shortest path, then lexical; their choice)
- E6 https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md
- E7 https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/main/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md and …/apps/desktop/frontend/src/style.css
- E8 https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/SmartCleanerReplicaView.swift
- E9 https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh
- E10 https://raw.githubusercontent.com/kafkaGen/dora-ai/HEAD/datasets/routes/1/{1..6}/image.png and …/node_desc.json (real CleanMyMac X screenshots; dataset index https://github.com/kafkaGen/dora-ai/tree/main/datasets/routes)
- Sibling gap-fill: `20-gap-02-cmm5-cleanup-protection-performance-screens.md` (Manager anatomy: Back · centred "<Module> Manager" · Search · "Sort by:", three panes, footer "N Items Selected"; X completion with Share Results / View Log / Start Over)

**Checked and rejected (invented, not observed):** MYLEKHATECH/Ccmacui `src/imports/cleanmymac-design-guide.md`; alex-foster-personal/cleanmymacfree; apo-bozdag/clean-my-mac; gaowujian/obsidian-vault feature summary (derivative of the KB); themoretheless/ppduster `research/commercial.json`.

---

## Verification notes

- **This pass made no web searches** (the budget was exhausted) and **no non-GitHub fetches** (DNS and proxy blocks), as logged in §0.1. Everything labelled VERIFIED [vendor] relies on earlier reports' fetches, cited by section.
- Every file in §2 / §13 was actually downloaded and read in this pass. Quoted labels (for example "Welcome back!", "Looking for junk...", "Your tasks are ready to run. Look what we found:", "Start Over", "Run", "Review", "Stop") are copied from those files. Where a label comes from a clone, it is marked INFERRED [clone-obs] and must not be treated as vendor copy.
- The E3 numbers are my translation of the Chinese audit text ("23.1 GB；另报 1 个威胁、2 个维护任务、1 个重要更新"). "Important update" reflects the auditor's Chinese UI ("重要更新"); the English label may differ.
- The clone screenshot (E2) was viewed directly. It is the clone's rendering, not the vendor's.
- The six X screenshots (E10) were viewed directly. Strings quoted from them ("Welcome to CleanMyMac X", "Start with a nice and thorough scan of your Mac.", "Looking at it...", "Alright, here's what I've found.", "Some applications should be quit.", "Optimizing Your System...", "Well done!", "Your Mac is in great shape.", "Share Results", "View Log", "Start Over") are **X** copy, quoted only to identify states. The numbers use a comma decimal separator ("3,13 GB") because the capture's locale used one.
