# 09 — Visual & Interaction Design System

> **Track:** look & feel of MacPaw's CleanMyMac X (2018–2024) and the redesigned "CleanMyMac" (5.x, Oct 2024 → 5.7.x in 2026), followed by an **original** design-system spec for our own app (Apple-silicon Mac mini, macOS 14 Sonoma → macOS 26 Tahoe).
> **Date:** 2026-10-12.
> **Rule:** we reproduce the *qualities* (one living colour field per module, one hero, one big action, calm glossy depth, honest review lists). We do **not** reuse MacPaw names, illustrations, icons, the pink iMac + squeegee mark, sounds, copy, or exact palettes. Part B gives original tokens.

---

## 0. Method, evidence labels and session constraints

### 0.1 Labels used in this file

| Label | Meaning |
|---|---|
| **VERIFIED** | I read a primary source this session: MacPaw's DevMate release-note HTML on S3, or Apple developer documentation JSON. URL given. |
| **VERIFIED-K** | Verified by a teammate report in this repo (`docs/research/0x-*.md`), which cites the original URL. I could not re-fetch it because the domain is blocked from this session (see 0.2). |
| **VERIFIED-OSS** | Read this session in a third-party GitHub repo whose author inspected the **shipped** app. Two kinds: (a) a reverse-engineering note on the CleanMyMac 5.5.4 bundle (asset catalogs, frameworks, colours read from decoded renditions); (b) "pixel-led" replica code of CleanMyMac X whose comments say the values were sampled from the installed app. This is strong evidence, but secondhand. |
| **VERIFIED-PX** | My own pixel measurements this session, taken from CleanMyMac X screenshots (`reference-*.png`, 1090×672) committed to a third-party repo. |
| **CLONE-OBS** | A design decision in a third-party clone whose docs say it mirrors CleanMyMac 5 reference screenshots. This is weaker evidence. Use it to form hypotheses only. |
| **INFERRED** | My reasoning or recommendation. |

### 0.2 Constraints (read before trusting coverage)

- **Web search was unavailable.** The per-run WebSearch budget, which all agents share, was used up before this track started. Every search attempt returned "budget used up".
- **Most domains were blocked.** The egress proxy refused CONNECT to: macpaw.com, cleanmymac.com, behance.net, dribbble.com, red-dot.org, 9to5mac.com, macstories.net, macworld.com, tidbits.com, apps.apple.com, setapp.com, youtube.com, theverge.com, appleinsider.com, tomsguide.com, sixcolors.com, figma.com, web.archive.org and images.macpaw.com.
- **What was reachable:**
  - GitHub (raw files, the HTML file tree, code search);
  - MacPaw's DevMate release-note bucket on S3;
  - developer.apple.com.
- **How I compensated:**
  1. I re-used design facts that teammates had already verified against MacPaw and press pages (VERIFIED-K).
  2. I mined GitHub for people who reverse-engineered or pixel-replicated the real app.
  3. I measured real screenshots myself.
- **Follow-up fetch list.** Section 8 lists the primary design pages a future session should fetch to close the gaps: Behance case study, Red Dot / iF pages, the MacPaw "introducing new CleanMyMac" post, and the MacStories / 9to5Mac screenshots.
- **Fact-check pass (same day).** An adversarial fact-check re-tested the key claims of this file. It had the same limits: WebSearch budget used up, and the same domains blocked for both `curl` and WebFetch. It used what was reachable: the DevMate S3 appcasts (`…/com.macpaw.CleanMyMac5/updates.xml` and `…/CleanMyMac4/updates.xml`, with dated versions), Apple's documentation JSON, raw GitHub, and the GitHub code-search API. Items it changed are marked **(corrected)**. Items it added are marked **(added)**. The summary is in "## Verification notes" at the end.

### 0.3 Key sources actually read this session

- DevMate release notes (VERIFIED):
  - CMM5 5.0.0–5.2.5: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html
  - CMM5 5.0.0: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50000.0.2410151250/releasenotes.html
  - CMM X 4.10–4.12: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- **CleanMyMac 5.5.4 bundle teardown** (VERIFIED-OSS), from inspecting `/Applications/CleanMyMac_5_MAS.app` build 50504.0.2605130801 with `assetutil` and a CoreUI exporter: https://raw.githubusercontent.com/jayvicsanantonio/VaderCleaner/main/docs/cleanmymac-3d-assets.md
- **CleanMyMac X pixel-led replica** (VERIFIED-OSS), in ddlmanus/MacOptimizer `AppUninstaller/`:
  - `CleanMyMacWindowMetrics.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/CleanMyMacWindowMetrics.swift
  - `Styles.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/Styles.swift
  - `CleanMyMacSidebar.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/CleanMyMacSidebar.swift
  - `SmartCleanerReplicaView.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/SmartCleanerReplicaView.swift
  - `SystemJunkReplicaView.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/SystemJunkReplicaView.swift
  - `CleanMyMacDetailsOverlay.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/CleanMyMacDetailsOverlay.swift
  - `ContentView.swift` — https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/AppUninstaller/ContentView.swift
- **CleanMyMac X screenshots** (VERIFIED-PX), all at https://raw.githubusercontent.com/ddlmanus/MacOptimizer/main/:
  - `reference-optimization-intro.png`
  - `-optimization-details.png`
  - `-optimization-selected.png`
  - `-optimization-sidebar-hover.png`
  - `-maintenance-intro.png`
  - `-maintenance-details.png`
  - `-extensions-intro.png`
  - `-uninstaller-list.png`
  - `-updater-details.png`

  They are Chinese-localised, so labels are translated below.
- **CMM5-inspired clone** (CLONE-OBS): https://github.com/jayvicsanantonio/VaderCleaner. Files read:
  - `SectionTheme.swift`, `VaderTheme.swift`, `BloomField.swift`, `FloatingScanButton.swift`, `ScanDiscWindowController.swift`, `NavigationRailView.swift`, `ScanProgressIndicator.swift`, `SectionIntroView.swift`, `MenuBarContent.swift`, `ContentView.swift`, `VaderCleanerApp.swift`;
  - `docs/history/spec.md` and `plan.md`.
- **CMM5-style UI spec** in another project (CLONE-OBS), written from CMM5 screenshots supplied by its owner: https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/main/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md
- **Apple docs** (VERIFIED, availability read from `developer.apple.com/tutorials/data/documentation/swiftui/*.json`):
  - MeshGradient, `glassEffect(_:in:)`, GlassEffectContainer, `backgroundExtensionEffect()`, `PrimitiveButtonStyle.glass`, MenuBarExtra;
  - MenuBarExtraStyle.window, `containerBackground(_:for:)`, ContainerBackgroundPlacement.window, `layerEffect`, ShaderLibrary;
  - `keyframeAnimator`, `phaseAnimator`, `sensoryFeedback`, `symbolEffect`, `visualEffect`, `contentTransition`, `numericText`;
  - `scrollTransition`, `toolbarBackgroundVisibility`, Material, `WindowStyle.hiddenTitleBar`, `accessibilityReduceTransparency`.
- **Teammate reports used:** 01-overview.md, 02-smart-care.md, 07-clutter.md, 08-menu-app.md (all in `docs/research/`).

---

## 1. TL;DR — what makes CleanMyMac *feel* premium (and what we keep)

1. **One continuous, module-tinted colour field fills the whole window.** There are no grey panes and no system sidebar material. Switching modules re-tints the entire window.
   - X: soft, desaturated vertical gradients. Each module has its own top hue, and all of them sink into the same deep indigo at the bottom. VERIFIED-PX / VERIFIED-OSS.
   - 5.x: a dark canvas with a **Metal-rendered live animated colour field** (`CleanMyLiveBackground.framework`). VERIFIED-OSS.
2. **One hero object per module.** It is glossy, top-lit and reads as 3D, but it is a **pre-rendered bitmap, not runtime 3D**. 5.x hero renditions are 600×400 pt (@1x) and category icons are 200×200 pt. VERIFIED-OSS.
3. **One persistent, circular primary action**, internally called the **"Ubiquitous Button"**. It keeps the same geometry in every module and changes only its label (Scan → Stop → Run/Clean), palette and progress ring.
   - It **breaks the window edge**. Evidence:
     - the designer described the big scan button as asymmetric and extending beyond the app window (VERIFIED-K, Behance);
     - screenshots show it overhanging the bottom edge (VERIFIED-PX).
   - In 5.x the button bundle ships a Metal library for its glassy effect. VERIFIED-OSS.
4. **Floating chrome.** In X the sidebar is a separate translucent rounded panel that **overhangs the window's left edge** (VERIFIED-PX). Window-only captures lack both the sidebar and the action button, which strongly suggests they are child windows (INFERRED).
5. **Information hierarchy:**
   - X: "intro → scan → summary → Review (two-pane list) → Run".
   - 5.x: "intro → scan → **tiles** with *Review* → Run". VERIFIED-K.
6. **Typography carries the mood.** Big numbers are set in very thin weights (X uses ~37–39 pt ultralight for found sizes) beside short bold headings and quiet 10–12 pt body text. VERIFIED-OSS.
7. **Accent discipline.** X uses a single cool cyan for every interactive affordance on any module colour: checkbox fill, "Review/View" pills, result numbers. VERIFIED-PX / VERIFIED-OSS.
8. **Depth comes from light, not shape.** The ingredients are:
   - glow under the primary action;
   - blooms in the background;
   - frosted panels with hairline rims;
   - specular highlights baked into the art.
9. **Delight layer.** Award juries and MacPaw cite parallax, micro-animations, hover effects, "atmospheric sounds" and glass-like icons (VERIFIED-K). 5.x adds the following (VERIFIED-OSS):
   - a squeegee "wipe" sprite sequence;
   - seasonal snowflake particle assets;
   - a Rive animation for tips;
   - an intro video for onboarding.
10. **Accessibility arrived late but is real.** VoiceOver and Reduce Motion support came in 5.0.7 (released 26 Mar 2025 per the DevMate appcast; **(corrected)**, it was not Dec 2024), and Reduce Motion "simplifies visual effects" (VERIFIED). High-contrast variants of the sidebar icons exist (VERIFIED-OSS).

---

## 2. Design lineage, awards and stated principles

| When | Fact | Status |
|---|---|---|
| CMM3 (2015–18) | **(corrected)** Shipped **five** UI sounds, not two: `ScanDidFinish.aiff`, `CleanDidFinish.aiff`, `CleanupFailed.aiff`, `DragEntered.aiff` and `Purchase.aiff` (the Menu helper app also bundles `CleanDidFinish.aiff`). General preferences had a "Play sounds for main … actions" checkbox and an "Animations: Disable for better performance" option. Also shipped: a seasonal "winter holidays" variant of the welcome-screen app icon, an onboarding **`Intro.mp4`** (the precedent for 5.x's `IntroVideo.mp4`), and the earliest **"Ubiquitous"** asset names (`HelperUbiquitousButtonNormal`, `HelperUbiquitousWindowNormal/Dark`). All of this comes from the `_CodeSignature/CodeResources` file lists and `.strings` files of an unofficial mirror of the CMM3 bundle on GitHub. We use no files from it. | VERIFIED-OSS (file names and strings only): https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/_CodeSignature/CodeResources ; preference strings via 13-helpcenter §5.1 |
| 2018 | CleanMyMac X launches with a full visual redesign (sidebar of grouped modules, per-module gradients, Smart Scan hero). | VERIFIED-K (01-overview §3; MacRumors 2018) |
| 2021 | **Red Dot** (Brands & Communication Design) for CleanMyMac X. The jury text highlights a **warm pink/blue colour spectrum during scanning and cleaning**. | VERIFIED-K (02-smart-care §Screen 1 → https://www.red-dot.org/project/cleanmymac-x-55187 ; https://www.iphoneincanada.ca/2021/08/17/cleanmymac-red-dot-award-2021/) |
| 2021 | **UX Design Awards**. **iF Design Award** notes call out parallax animation, hover effects, atmospheric sounds and glass-like icons. The year of the iF award was not re-checked. Treat "2021" as applying to the UX Design Awards only. | VERIFIED-K (01-overview §3; 02-smart-care → https://macpaw.com/news/cleanmymac-received-ux-design-awards ; https://macpaw.com/news/cleanmymac-if-design-award) |
| — | **Behance case study** "CleanMyMac X Product Design" (credited to Dimitry Novikov). It says **superellipse shapes are used everywhere**, and the big scan button is **not symmetrical and goes beyond the application window**. | VERIFIED-K (02-smart-care → https://www.behance.net/gallery/141590791/CleanMyMac-X-Product-Design) |
| Dec 2021 (4.10.0) → Mar 2022 (4.10.4) | **(corrected)** 4.10.0 shipped on **21 Dec 2021**, not Mar 2022. 4.10.4 shipped on 30 Mar 2022. Both dates come from the DevMate appcast. 4.10.0 added a new **Assistant** "in the app's upper-right corner". The 4.10.4 fix note mentions "the animation of the Assistant when switching to the full view", i.e. it expands from a pill into a panel. **(corrected)** 4.10.4 did not introduce the **Ukrainian theme**: it *updated* an existing one and added a switch to turn it off in Preferences. | VERIFIED (DevMate CMM4 notes + https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml) |
| Jun 2022 (4.11.0) | Redesigned Menu (menu-bar app) with CPU / Memory / Storage / Battery / Protection panels. | VERIFIED (DevMate CMM4 notes); visuals → 08-menu-app.md |
| Oct 2024 (5.0.0) | New "CleanMyMac" with a **"3D animated interface"**, a **tile-based** results layout, six modules plus an Assistant entry at the bottom-left of the sidebar, and a redesigned Menu as a **grid of tiles**. | VERIFIED-K (01-overview §3, §5.1; 02-smart-care §2; 08-menu-app) |
| Mar 2025 (5.0.7) | **(corrected)** Released **26 Mar 2025**, not Dec 2024 (5.0.4 was the Dec 2024 build, on 18 Dec). Added **VoiceOver + Reduce Motion** support. With Reduce Motion on, the app minimises unnecessary animations and simplifies visual effects. | VERIFIED (DevMate CMM5 notes + appcast https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml) |
| Jun 2025 (5.1.0, 12 Jun) | Space Lens returns, "reimagined": a storage map of folders as **bubbles** arranged largest → smallest, with zoom-in. | VERIFIED (DevMate CMM5 notes + appcast) |
| Jul 2025 (5.2.1, 28 Jul) | Cloud Cleanup (iCloud Drive, Google Drive, OneDrive); Dropbox followed in 5.3.0 (17 Dec 2025). | VERIFIED (DevMate 5.3.1 notes: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html) **(added)** |
| Oct 2025 (5.2.6, 17 Oct) | **Smart Insights**, "powered by Apple Intelligence", explains what system files are. | VERIFIED (same DevMate notes; upgraded from VERIFIED-K) **(added)** |
| 2026 | Notification Center bell (5.6), My Tools hub (5.5). The DevMate appcast stops at 5.3.1 (28 Jan 2026). Later builds (5.5.4 MAS build `50504.0.2605130801`; 5.6.0, seen at `/Applications/CleanMyMac_5.app` in a GitHub README) ship through another channel. | VERIFIED-K (01-overview §5.1); appcast VERIFIED |
| Tahoe (macOS 26) | Whether 5.x adopted **Liquid Glass** window chrome is still **unknown**. See §4.8 for indirect evidence: 5.x supports macOS 11+, its app icon is built from layers, and it draws its own chrome. | GAP (§7) |

**Stated principles (paraphrased from the award and press material that teammates verified):**
- immersive colour;
- motion that conveys progress;
- tactile hover feedback;
- sound as ambience;
- "glass" iconography;
- superellipse geometry.

---

## 3. CleanMyMac X (4.x, 2018–2024) — detailed anatomy

### 3.1 Window and chrome

- **One continuous surface.** The module gradient runs edge to edge, under a transparent title bar. The traffic lights sit directly on the gradient. The content starts below a ~23 pt title-bar band. VERIFIED-OSS (`CleanMyMacWindowMetrics.titlebarContentInset = 23`; the `ContentView.swift` comment says "CleanMyMac's window is one continuous gradient surface… there is no second inset content card").
- **Proportions (corrected).** The **window-only** captures (`reference-optimization-intro.png`, `reference-uninstaller-list.png`) show the whole window, with all four rounded corners, at exactly **1090×672 px**: an aspect ratio of **1.62:1**, near the golden ratio. VERIFIED-PX (re-measured in the fact-check pass).
  - The "≈1025×632 px" figure from `reference-optimization-details.png` is the **same window scaled by ≈0.94**. That capture is a screen region that also had to fit the overhanging sidebar and orb. It is not a different window size.
  - The replica's **1090×644** is most likely the same window minus a ≈28 px title band (INFERRED).
  - The capture scale is unknown (1× or downsampled 2×), so absolute points are unverified. Only the ≈1.62 aspect ratio is firm.
- **Floating sidebar panel.** It is a rounded, translucent panel ≈217×571 px. It starts ~32 px below the top, **overhangs the window's left edge by ~29 px** and stops ~28 px above the bottom. VERIFIED-PX.
  - In captures of the window alone (`reference-*-intro.png`, `-sidebar-hover.png`) both the sidebar and the bottom action button are **missing**, yet the content is still laid out as if the sidebar were there. VERIFIED-PX.
  - ⇒ The sidebar and the button are **separate child windows** layered over the main window. INFERRED.
  - This is the only way AppKit lets content cross a window's bounds. A clone uses the same technique for its disc (CLONE-OBS, `ScanDiscWindowController.swift`: "A child panel is the only way to render the disc outside the main window's bounds").
- **Bottom action button** ("UbiquitousButton"). It is centred on the content area (not the full window). Its centre sits ~70 pt above the content's bottom (VERIFIED-OSS `bottomActionCenterInset = 70`). The visible ring hangs ~13 px below the window's bottom edge (VERIFIED-PX).
- **Top bar of the content area.** Three zones on one row (VERIFIED-PX; `SystemJunkReplicaView.moduleHeader`):
  - **left:** a chevron-left link, "Start Over" on result screens, "Back" in review lists, or "Intro" in the Updater detail, at 12 pt medium, ~60 % white;
  - **centre:** the module name, small, at 12 pt medium, ~58 % white;
  - **right:** a **search field**, ≈181×27 pt, black 16 % fill, radius 7, with a magnifier glyph. It only appears in review lists.
- **Assistant pill.** It sits at the far top-right as a dark translucent capsule containing a small cyan/blue status dot and the word "Assistant" (VERIFIED-PX; position VERIFIED in DevMate 4.10.0). It expands into a full panel with an animation (VERIFIED, 4.10.4 fix note).

### 3.2 Sidebar

- **Structure.** Smart Scan sits alone at the top, followed by sections with small headers. VERIFIED-PX (screenshot, translated) and VERIFIED-K (AFB AccessWorld via 01-overview §7).

```
Smart Scan
CLEANUP      System Junk · Mail Attachments · Trash Bins
PROTECTION   Malware Removal · Privacy
SPEED        Optimization · Maintenance
APPLICATIONS Uninstaller · Updater · Extensions
FILES        Space Lens · Large & Old Files · Shredder
```

- **Row anatomy.** VERIFIED-OSS (replica sizes) / VERIFIED-PX (look).
  - A line glyph (~13 pt, white at 62 % inactive, 90 % selected), then a 12 pt label (medium, semibold when selected, 82–94 % white), then right-aligned live metrics. Examples of metrics:
    - "4.39 GB" next to System Junk after a scan;
    - "119.81 GB" next to Space Lens;
    - a mini spinner plus a running size while a module scans.
  - **(added)** Metric text is **9.5 pt medium at 72 % white** (62 % while busy). The busy spinner is a 12×12 pt mini `ProgressView`. The row has 7 pt of inner horizontal padding and is inset 17 pt from the panel edge. VERIFIED-OSS (`CleanMyMacSidebar.swift`).
  - Row height ≈27 pt.
  - Section headers are ~10–11 pt, medium, ~48 % white, with ~9 pt of space above them.
- **Glyph style.** Thin outline pictograms. Translated observations:
  - Smart Scan: a monitor;
  - System Junk: a disc/globe-like glyph;
  - Mail Attachments: an envelope;
  - Trash Bins: a bin;
  - Malware Removal: a **biohazard** mark;
  - Privacy: a raised **hand**;
  - Optimization: **vertical sliders**;
  - Maintenance: a **wrench**;
  - Uninstaller: a node/branch glyph;
  - Updater: a circular-arrow glyph;
  - Extensions: a plug/puzzle;
  - Space Lens: a lens circle;
  - Large & Old Files: a folder;
  - Shredder: a shredder.

  VERIFIED-PX.
- **Selection and hover.** VERIFIED-PX / VERIFIED-OSS.
  - **Selected:** an inset rounded rectangle (radius ≈7) that is **darker** than the panel (≈ black 24 % over it; sampled #6B5E8C on a #8F84B1 panel).
  - **Hover:** a faint white wash (≈5–6 %).
  - **Pressed:** opacity drops to ~72 %.
- **Panel material.** VERIFIED-OSS / VERIFIED-PX.
  - A lighter, frosted overlay on the same gradient: a white 17 % → black 12 % vertical wash, a 0.8 pt white 7.5 % hairline rim, radius ≈12 (continuous) and a soft drop shadow (black 24 %, radius 16, y 8).
  - Sampled from the Optimization screen: #AB87CF at the top, #605C8C near the bottom.

### 3.3 Per-module colour system (X)

**Common rule.** VERIFIED-PX.
- Each module has its own **top hue**.
- Every module converges to the same deep **indigo ≈ #3A4072** at the bottom.
- The gradient is mostly vertical with a slight top-left → bottom-right drift: at the same height, the left edge is ~4–8 % lighter.
- Colours are **muted, desaturated, "dusty" pastels**, never neon.
- Together the modules span a **warm pink ↔ cool blue/teal** spectrum, matching the Red Dot description (VERIFIED-K).

| Section › Module | Top stop | Mid stop(s) | Bottom | Hue description | Evidence |
|---|---|---|---|---|---|
| Smart Scan | **#9076A6** | #6F6091 | #474979 | dusty violet / heather | VERIFIED-OSS (replica sampled from a 1090×644 window) |
| Cleanup › System Junk | **#BA6E91** | #80578C | #3D457A | dusty rose / mauve-pink | VERIFIED-OSS |
| Cleanup › Mail Attachments | **#698EC3** | #6282B9 · #50669B | #353B6F | periwinkle blue | VERIFIED-OSS (sampled) |
| Cleanup › Trash Bins | **#56B6B0** | #4995A0 · #40678E | #3D4276 | soft teal / sea-glass | VERIFIED-OSS (sampled) |
| Protection › Malware Removal | **#CB7874** | #9F6078 · #6D5476 | #3D4372 | coral / salmon → plum | VERIFIED-OSS |
| Protection › Privacy | **#B76786** | #9E5D85 · #745180 | #3E4576 | rose-pink | VERIFIED-OSS |
| Speed › Optimization | **#9976C8** (PX) / #9A75CB (OSS) | #876DB7 · #705FA2 · #58508C | #414278 → #3A4072 | lavender-violet | VERIFIED-PX + OSS |
| Speed › Maintenance | **#B06F91** | #9A648B · #7D5983 · #5F4E7B | #434274 | rose-mauve | VERIFIED-PX |
| Applications › Uninstaller | **#6193B8** (PX) / #70A0C4 (OSS) | #5B82AB · #516E9A · #475987 | #3E4576 | steel / sky blue | VERIFIED-PX + OSS |
| Applications › Updater | **#3DAC9A** (PX) / #4BBAA7 (OSS) | #3D9891 · #3D7B88 · #3C617E | #3B4875 | teal-green → slate | VERIFIED-PX + OSS |
| Applications › Extensions | **#9577B5** | #846CA8 · #6D5E97 · #575086 | #414477 | lavender | VERIFIED-PX |
| Files › Space Lens | **#49AA93** | #3F8D82 | #315672 | sea-green | VERIFIED-OSS ("matches design image") |
| Files › Large & Old Files | **#C97B79** | #966271 | #414878 | coral-rose | VERIFIED-OSS ("matches design image") |
| Files › Shredder | **#67ABC0** | #527F9D | #424A7B | steel-cyan | VERIFIED-OSS ("matches design image") |

**Accent colours (X).**

| Role | Value | Notes | Evidence |
|---|---|---|---|
| Interactive cyan: checkbox fill, result numbers | **#5CE0F7** / #59D6F5 | One accent on every module colour | VERIFIED-OSS |
| Checkmark inside the cyan checkbox | **#335C87** | Dark navy, not white | VERIFIED-OSS |
| "View N items…" pill (intro screens) | **#7BD5FC** fill, dark text | Light-cyan capsule, radius ≈6, ~28 pt tall | VERIFIED-PX |
| "Review Details…" pill (results) | black 24–27 % fill, **cyan text** (#6BE0FA) | Small dark chip | VERIFIED-OSS |
| Smart Scan column accents | Cleanup **#4CD1F0** (cyan) · Protection **#45D68A** (green) · Speed **#E86BB2** (pink) | Colour of each column's big result number and status | VERIFIED-OSS |
| Scan orb | #8278A6 → #5E6B9E fill, violet glow #A85AD6 | Calm, low-contrast state | VERIFIED-OSS |
| Stop orb | #A34F94 → #704A85 fill | Warmer, magenta | VERIFIED-OSS |
| Run/Clean orb | violet fill with a **cyan ring** #47DBFA and cyan glow | The "go" state turns cyan | VERIFIED-OSS |

### 3.4 Module intro screen anatomy (X)

VERIFIED-PX (Optimization, Maintenance, Extensions intros) and VERIFIED-OSS (System Junk intro layout).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●                                                                        │
│        [sidebar overhangs]         MODULE TITLE (≈21–24pt bold)              │
│                                    one-line subtitle (≈11–13pt, ~67% white)  │
│                                                                ╭──────────╮  │
│                                    ◯  Benefit title (12pt sb)  │  glossy  │  │
│                                       2-line description 10pt  │  hero    │  │
│                                    ◯  Benefit title            │  ~270–   │  │
│                                       description              │  300pt   │  │
│                                    [ View 7 tasks… ] (cyan pill)╰──────────╯  │
│                                  ( Scan )  ← ubiquitous orb, for scan modules│
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Text column.** About 300 pt wide, left of a large illustration. There are ~68 pt between them.
- **Benefit rows.** Each row has:
  - a ~28 pt **ultralight outline icon** at ~37 % white inside a 40 pt box (gauge, warning triangle, magnifier, sliders, etc.);
  - a **12 pt semibold** title;
  - a **10 pt** description at ~47 % white.

  The rows are spaced ~28–35 pt apart.
- **Modules without a scan** (Optimization, Maintenance, Extensions) show a cyan pill such as "View N items/tasks…" instead of the orb. VERIFIED-PX.
- **Hero illustrations** (VERIFIED-PX):
  - Optimization: a large **pink→violet glossy sphere** carrying three white sliders with pearly knobs. **(added)** Sampled in the fact-check pass:
    - sphere top ≈ #C96EA7 (rose-pink);
    - sides ≈ #8F5CAB;
    - bottom ≈ #5F4BA0 (violet);
    - a thin lighter rim;
    - diameter ≈ 295 px in the 1090 px window-only capture.

    VERIFIED-PX.
  - Extensions: the same sphere with a white puzzle piece.
  - Maintenance: a **tilted glossy violet-pink clipboard card** with white check boxes and a white wrench overlapping it.

  The shared style:
  - soft studio lighting from the top-left;
  - pink-to-violet body gradients;
  - **white glossy foreground objects**;
  - a subtle rim light;
  - a slight perspective tilt;
  - no hard outlines.

### 3.5 Smart Scan flow (X)

VERIFIED-OSS (`SmartCleanerReplicaView.swift`, a pixel-led reconstruction). Copy is paraphrased.

| State | Layout | Typography / colour |
|---|---|---|
| **Idle / welcome** | The brand illustration is centred, ≈565×310 pt: the app-icon motif, a pink display with a squeegee. Below it, a welcome title and a one-line invitation to run a thorough scan. The orb reads **Scan**. | Title **35 pt regular**, 96 % white. Subtitle 14 pt, 66 % white. |
| **Scanning** | A short headline plus a playful one-line reassurance. **Three columns** (Cleanup · Protection · Speed), ~185 pt wide with 95 pt between them. Each column has a big glossy icon (178–270 pt), a bold 15 pt title (Protection also shows the Moonlock wordmark), and a 12 pt status line. The active column shows the **current path** at 10 pt, 34 % white, truncated in the middle; inactive columns show a "waiting" state. The orb reads **Stop**, with the running total to its right (17 pt light). | Headline 25 pt bold. Status lines 12 pt at 46 % white. Active icons "breathe": scale 1.025 over 0.65 s, auto-reversing, and the Speed icon also rocks ±2.5°. |
| **Results** | A casual first-person headline that amounts to "here's what I found", and a subtitle inviting the user to run everything. Each column shrinks its icon (~142–172 pt) and shows its result: a **big thin number** (size, threat count, task count) or a "Good / no threats" verdict, plus a small dark **"View Details…"** chip. The orb reads **Run**, cyan-ringed. | Numbers **37 pt ultraLight**, coloured with the column accent. Units 12 pt medium. Captions 11 pt at 38 % white. |
| **Cleaning** | Same three columns, each with an active or done status. The orb reads **Stop**. | — |
| **Finished** | A short congratulatory headline ("Nice work!"-style) and a "your Mac is in great shape" line. Each column shows a past-tense summary. **No orb** in this state. | — |
| **Details overlay** | An in-window panel (≈778×489, radius 7) over a black 58 % scrim. It has a "Back to Summary" chip, a 342 pt left category list, a hairline divider and the item list on the right. Transition: opacity plus a 0.995 → 1 scale over 0.16 s ease-out. | Same list styles as §3.7. |

### 3.6 The "Ubiquitous Button" (X)

VERIFIED-OSS (`CleanMyMacActionOrb`, whose comment reads "The original UbiquitousButton keeps identical geometry in every module; only its palette and state change"). The name "UbiquitousButton" also survives in the 5.x bundle as `CMM5UbiquitousButton_CMM5UbiquitousButton.bundle` (VERIFIED-OSS).

| Part | Value |
|---|---|
| Frame | 108 × 96 pt |
| Glow | 108 pt circle, blurred 17 pt, at 30 % (hover 42 %, disabled 10 %) |
| Outer ring | 82 pt diameter, white stroke 3 pt at 20 % |
| Main disc | 72 pt, module/state gradient (top → bottom), 2.3 pt state-colour ring at 94 %, shadow in the glow colour at 38 %, radius 9 |
| Inner ring / progress | 64 pt. Idle: hairline white 18 %. Busy: a white 76 % **progress arc**, 2 pt, round caps, starting at 12 o'clock (rotated −90°), trimmed from 0.02 to progress |
| Label | 13 pt medium, white 76 % (disabled 38 %) |
| Hover | Scale 1.025 and lift 3 pt, 0.14 s ease-out |
| Press | (Selection buttons) scale 0.94 with +8 % brightness, 0.08 s |
| States | **Scan** (violet) → **Stop** (magenta, with progress) → **Run / Clean / Remove / Uninstall / Update** (cyan ring and glow) → hidden when finished. **Disabled** when nothing is selected (VERIFIED-PX: the dim "Run" orb in Optimization details). |
| Accessory | The size or count of the selection sits ~108 pt to the right of the orb's centre (17 pt light, or 12 pt medium). It never moves the orb. |

### 3.7 Results summary and Review lists (X)

**Module results summary** (System Junk). VERIFIED-OSS.
- The illustration sits on the left (~290 pt).
- The text column on the right (285 pt) contains:
  - "Scan Complete" (20 pt bold);
  - the **selected size** in **39 pt ultralight cyan** with a small "Smart Selection" caption beside it;
  - "Includes" followed by up to 5 bulleted category names (11 pt);
  - a "Review Details" dark chip with cyan text;
  - "Found N in total" (10 pt, 38 % white).
- The orb reads **Clean**, with the selected size as its accessory.

**Review (two-pane) layout.** VERIFIED-OSS / VERIFIED-PX.

```
┌ ‹ Back            System Junk                 [🔍 Search        ]  (Assistant) ┐
│ [Select All]            Sort by Size ▾ │  User Cache Files (20pt bold)        │
│ ◉ (●) User Cache Files        2.1 GB   │  2–3 line explanation (11pt, 67%)    │
│ ◯ (●) System Log Files      312 MB     │                    Sort by Size ▾    │
│ ◯ (●) Language Files        1.4 GB     │  ◉ [icon] com.apple.Safari   88 MB   │
│    (●) Broken Login Items  (dimmed)    │  ◉ [icon] Google/Chrome     402 MB   │
│  … 54pt rows, 32pt round gradient icons│  … 41pt rows                         │
│                                        │                                      │
└──────────────── category pane ≈410pt ──┴── item pane ─── (orb straddles edge) ┘
```

- **Checkbox.** A 14 pt **circle**, filled cyan with a dark navy check, or a dash when partial. Unchecked it is a hairline white 42 % ring. The hit target is a full-height 44 pt column, with a 30 pt hover halo at white 7.5 %. Partial state = tri-state. VERIFIED-OSS.
- **Category icons.** Small **circular gradient badges** with a white glyph. Each category has its own two-stop gradient: orange→rose for user caches, cyan→blue for system caches, slate-blue for logs, peach→blue for universal binaries. VERIFIED-OSS. In Optimization they are glossy rounded-square app-icon-style renders (chart, rocket, hourglass). VERIFIED-PX.
- **Empty categories.** Shown **dimmed, without a checkbox** (Hung Applications). VERIFIED-PX.
- **Selected category row.** Black 22 % rounded rectangle, radius 7. VERIFIED-OSS. On hover it becomes lighter: #AD9EC7 over the violet. VERIFIED-PX.
- **Item row.** Checkbox, a 25 pt Finder icon, the name (11 pt medium, middle-truncated) and the size (11 pt medium, 61 pt right-aligned column). A context menu offers: Reveal, Quick Look, Ignore. VERIFIED-OSS.
- **Uninstaller list.** VERIFIED-PX.
  - The **left filter column** looks like a second sidebar: "All Applications 14 / Leftovers 8 / Suspicious / Selected", then the header "Stores" with "App Store 2 / Other 12", then the header "Vendors" with "Google 1 / MacPaw 1 / JetBrains 1 / Other 11". Counts are right-aligned.
  - The **right pane** has a 22 pt bold title and a subtitle, "Sort by Name ▾", and ~45 pt rows: radio circle · 32 pt app icon · name 13 pt · chevron › · size (e.g. "17.1 GB").
- **Updater detail.** VERIFIED-PX.
  - The left list has a "Select All" chip, "Sort by Last Opened ▾", and rows with an ⓘ button, app icon, name and "Version x".
  - The right pane has the app name (~22 pt bold), a version line "4.1.5 ✈ 4.1.11 | date | 454.5 MB", a horizontally scrolling **screenshot carousel** (rounded ~8 pt cards) and "Recent updates" notes.

### 3.8 Iconography and illustration style (X)

- The illustrations are **soft-3D glossy renders**:
  - pink→purple gradient bodies;
  - pearlescent white foreground objects;
  - top-left key light;
  - gentle perspective tilt;
  - no outlines;
  - the illustration "floats" without a ground plane.

  The juries called the icons "glass-like" (VERIFIED-K).
- The **parallax** effect (cursor-reactive depth) and **micro-animations** (breathing hero icons, rocking speed icon) are cited by the award and press material (VERIFIED-K). The breathing is replicated in OSS (VERIFIED-OSS).
- **Sidebar glyphs** are monochrome **outline** pictograms (VERIFIED-PX).
- **Benefit-row icons** are large **ultralight** outline icons at low opacity (VERIFIED-OSS/PX).

### 3.9 Typography (X)

- System font (SF Pro). The DevMate release-notes view embedded in the app also uses SF Pro Text at 13 px body and 18 px titles. VERIFIED.
- Observed scale (VERIFIED-OSS):

| Use | Size / weight |
|---|---|
| Welcome title | 35 regular |
| Flow headlines | 25 bold |
| Module titles | 20–22 bold |
| Big numbers | 37–39 **ultraLight** |
| Column titles | 15 bold |
| Body | 11–14 regular |
| Captions / paths | 10–11 at 34–47 % white |
| Sidebar | 12.2 medium / semibold |
| Section headers | 10 medium |

- The signature contrast is **ultra-thin giant numerals next to small bold labels**.

### 3.10 Motion, sound and theming (X)

- **Hover** on the orb: scale 1.025 and lift 3 pt (0.14 s). **Press** feedback on selection controls (0.08 s). VERIFIED-OSS.
- **Hero icons breathe** during the active phase (0.65 s ease-in-out, repeating, ±2.5% scale). VERIFIED-OSS.
- **Progress** is a thin ring inside the Stop orb. VERIFIED-OSS.
- **Overlay transitions:** fade plus a tiny scale (0.16 s). VERIFIED-OSS.
- **"Atmospheric sounds"** were part of the award-winning experience (VERIFIED-K). **(corrected)** CMM3 shipped five event sounds: scan finished, clean finished, cleanup failed, drag entered, and purchase. It also had a user toggle for them. VERIFIED-OSS (file names and strings only; §2).
- **Themes:** the Ukrainian theme, which 4.10.4 *updated* and made switchable **(corrected)**, and seasonal icon art (CMM3). VERIFIED.
- **Appearance:** the module canvases do **not** follow system Light/Dark; the colour field *is* the brand. INFERRED from screenshots that show identical canvases. Teammate 01 found no 5.x appearance setting. **(added)** 5.x does have a `CustomThemes` boolean preference (§4.8). What it controls is unconfirmed.

---

## 4. CleanMyMac (5.x, 2024 → 2026) — what changed

### 4.1 Overall direction

- **The canvas went dark and alive.**
  - Each module now sits on a dark, saturated field in its own hue. A **Metal-rendered live background** (`CleanMyLiveBackground.framework`, shaders compiled into the binary) supplies a moving colour field, the "aurora". VERIFIED-OSS.
  - CMM5-style specs built from real screenshots describe "a dark canvas that repaints in each module's colour", "big light display titles", "frosted cards" and "one glowing circular call to action per screen". CLONE-OBS.
- **"3D" is baked raster art.**
  - The 5.5.4 bundle contains **zero** `.usdz`/USD/SceneKit/Reality/glTF files.
  - The 3D look comes from pre-rendered PNGs in per-module `Assets.car` files (≈128 frameworks, one catalog each), a Metal background, **one Rive animation** (`TipsServiceUI…/main.riv`) and **one intro video** (`Features_IntroFlow…/IntroVideo.mp4`). VERIFIED-OSS.
- **Rendition sizes** (VERIFIED-OSS):
  - hero `ModuleIcon` 600×400 pt (1200×800 @2x);
  - category badges 200×200 pt;
  - sidebar module icons 24×24 pt;
  - Smart Care intro-category chips 32×32 pt.

  Everything ships as sRGB ARGB PNG at @1x and @2x.
- **Tiles replaced the three-column summary.** Smart Care shows one tile per module (Cleanup, Protection, Performance, Applications, My Clutter). Each tile has its metric and a **Review** button; **all tasks are selected by default**; excluded modules show **dimmed** tiles; then the user presses **Run**. A **Start Over** button sits at the top-left. VERIFIED-K (02-smart-care §2–3, MacPaw Smart Care KB).
- **The button stayed.** The circular primary action (the "Ubiquitous Button") survives as its own bundle, with a `default.metallib` for its glassy shader. VERIFIED-OSS. Two independent clones place it **straddling the window's bottom edge**, "per screenshots": half on the window, half over the desktop. CLONE-OBS (VaderCleaner plan, step 8; `ScanDiscWindowController.swift`).

### 4.2 Shell, sidebar and chrome (5.x)

- **Sidebar order** (VERIFIED-K, 01-overview §5.1; on-screen order INFERRED to match):
  - Smart Care · Cleanup · Protection · Performance · Applications · My Clutter · Space Lens · Cloud Cleanup · My Tools · My Activity.
  - At launch (5.0) an **Assistant** entry sat at the bottom-left.
  - Global chrome includes a **bell** that opens the Notification Center (5.6) and an "Unlock Full Version" control top-right when unlicensed.
- **Sidebar glyphs** (VERIFIED-OSS):
  - Bespoke per-module **24×24 monochrome line glyphs**, in Active and Inactive variants.
  - Each also has a **High-Contrast-Mode (HCM)** variant (file naming like "Module=Smart Care, Active=On, HCM=Off").
  - ⇒ They respond to *Increase Contrast*.
- **Selection treatment** (CLONE-OBS, VaderCleaner `NavigationRailView`, built to the reference):
  - a soft, inset, **translucent "glass" pill** (radius ≈18) with generous spacing, a faint horizontal sheen and a **hairline rim lit in the section accent**;
  - the rail and the detail area share **one continuous gradient**, with no sidebar material and no divider.
- **Rail collapse** (CLONE-OBS): the rail shows icons plus labels on landing screens and collapses to **icons only** once a scan starts, so results get more room. The second CMM5-style spec independently chose "a thin icon-only rail". **Treat as plausible, not verified.**
  - **Fact-check note (added).** Neither clone states that the *vendor* collapses its rail.
    - VaderCleaner implements collapse as its own feature (`RailCollapseTests.swift`; a collapsed row shows a floating name tooltip).
    - The GuilhermeVozniak spec lists "a thin icon-only rail" among its *goals*, next to fixing "tiny rail labels". That reads like a design choice, not an observation.
    - No primary 5.x screenshot was reachable, so this stays unverified.
- **Branding assets** in `MainAppUI` (VERIFIED-OSS): a wordmark, a "Crafted by MacPaw" signature (About/footer) and custom **back-button chrome**. MacPaw draws its own back button rather than using the system toolbar button.
- **Minimum display:** 1280×800 (a 1200×800 figure also appears). VERIFIED-K (01-overview §3). The default window size is unknown (GAP).
- **Minimum OS (added):** every 5.x item in the DevMate appcast declares `sparkle:minimumSystemVersion` **11.0** (Big Sur). Any macOS 26 Liquid Glass styling in 5.x must therefore sit behind runtime checks. VERIFIED (appcast).

### 4.3 Colour identity per module (5.x)

**The rule.** VERIFIED-OSS, from decoded renditions in the 5.5.4 teardown:
- Every module/category badge follows the same recipe: **a domain silhouette + a two-stop vertical gradient + a frosted, top-lit inner glyph + a soft drop shadow**.
- Colour codes the domain: **green = junk/trash, pink/magenta = privacy & security, orange = performance/maintenance, blue = applications**.

| Domain | Silhouette | Gradient (top → bottom) | Glyph / accent | Evidence |
|---|---|---|---|---|
| Brand / Smart Care hero (`ModuleIcon`) | Free-standing glossy magenta **display** in ¾ perspective on a pale-lavender pedestal; a silver-lavender **squeegee** lies diagonally across the screen | **#FF91D7 → #B70193** (→ #BE01C7) | Stand #BDBCEF; squeegee accent #E305AB | VERIFIED-OSS |
| App icon | Same motif on an off-white squircle | Swatches #F686BF light pink · #FF6395 hot pink · #BE01C7 magenta-violet; tile #F7F5FC | — | VERIFIED-OSS |
| Cleanup › System Junk | **Circle** | **#5CD746 → #155B29** (lime → forest) | Frosted mint basket/bin with lid, debossed ×, ~#7EB580 | VERIFIED-OSS |
| Cleanup › Trash Bins | **Circle** | same green | Pale-mint open tub ~#BBD8A5 | VERIFIED-OSS |
| Protection › Privacy | Rounded **octagon** | **#FD66ED → #B31C6E** | Lilac shield #F8BBFE with a cut-in check mark | VERIFIED-OSS |
| Performance › Maintenance | **Banner / bookmark** with a V-notch | **#FCA106 → #D34A25** | Butter-yellow wrench #FFE76F crossed with a screwdriver | VERIFIED-OSS |
| Applications › Uninstaller | **Hexagon** | **#47B6F9 → #055EC4** | Light-blue sweep/broom "X" with a round badge carrying a dark-blue × (#0550B3) | VERIFIED-OSS |
| Protection "all clear" | Pink glossy shield over a pale document, with sparkles | #FC85D6, document #FFF0FD | — | VERIFIED-OSS |
| My Clutter | Teal **folder** | (teal) | — | CLONE-OBS (comment: "teal My Clutter folder asset") |
| Space Lens | Indigo-violet object | (indigo-violet) | — | CLONE-OBS |
| Performance (module hero) | Orange **bolt** | (orange) | — | CLONE-OBS |

**Approximate dark canvases** used by a CMM5-faithful clone (CLONE-OBS, VaderCleaner `SectionTheme.swift`). They are useful as a *feel* reference only. The real background is a Metal shader, so its exact colours are unknown.

| Module | Accent | Canvas top → bottom |
|---|---|---|
| Smart Care | #C740FA (magenta-violet) | #331766 → #612EA8 |
| Cleanup | #21E636 | #081F0A → #0F4A14 |
| My Clutter | #1AE6DB | #081F1F → #0F4A47 |
| Space Lens | #8570FF | #0D0A26 → #1A1457 |
| Protection | #E62EC2 | #1F081A → #4A0F40 |
| Performance | #E65429 | #1F0D08 → #4A1C0F |
| Applications | #4C75FF | #0A0F2B → #17215E |

Note the inversion from X: in 5.x the **bottom is brighter and more saturated** than the near-black top, and an accent bloom rises from behind the floating button. CLONE-OBS (BloomField comments). This fits the "glow under the CTA" look.

**Conflicting clone evidence (added).** The other screenshot-based spec (GuilhermeVozniak) paints "a full-bleed gradient with a **bright radial glow top-right** and shade bottom-left", using three stops plus a glow colour per module.
- So the two clones disagree on where the light pools. The likeliest reconciliation is a *moving* field (Metal aurora) whose bright region drifts. INFERRED.
- Do not treat "bottom brighter" as a vendor fact.

**5.x brand spectrum (added, VERIFIED).** The 5.x release-notes page (DevMate HTML, shown in-app on update) renders the version heading as gradient text: `linear-gradient(90deg, #9E00CE, #AC097B, #178486, #397333, #0078CE)`, `background-size: 200%`, animated `background-position` 0 % → 100 % over **3 s ease, infinite**.
- The five stops are violet → magenta → teal → green → blue. They line up with the 5.x domain hues: Smart Care violet/magenta, My Clutter teal, Cleanup green, Applications blue.
- The same page forces `color-scheme: only light` and uses `"SF Pro Text", -apple-system`.
- The X (4.x) notes page has no such gradient.
- Source: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html (CSS `.rn-version`).

### 4.4 Screens (5.x)

- **Smart Care landing.**
  - The giant `ModuleIcon` hero (the brand display) and a title.
  - Three small **intro-category chips/rows**, named in the bundle as quick-scan, security-check and system-tuneup (32 pt icons). VERIFIED-OSS.
  - The circular **Scan** button.
- **Scanning.** The modules are checked off as their routines run. A CMM5-style clone shows a checklist with live check marks and a section-tinted animated indicator (sonar pulses and counter-rotating arcs). CLONE-OBS. The real 5.x scanning visuals are a GAP: likely the hero animates, the background intensifies and the ring fills. INFERRED.
- **Results.** One tile per module. Each tile has:
  - the module badge (in a clone spec, "bleeding off the top-right corner", CLONE-OBS);
  - a big stat (GB to remove, threats, tasks, updates, duplicates);
  - a status line;
  - a **Review** button.

  Excluded modules appear dimmed; the button reads **Run**; **Start Over** sits top-left. VERIFIED-K for structure and dimming. Tile styling seen in a clone that matched reference screenshots (CLONE-OBS, `VaderTheme.swift`):
  - translucent glass tiles with a **large corner radius (~24 pt)**;
  - tint-free translucent **Review** capsules with white semibold labels;
  - the direct action (Clean/Remove) as a **solid white capsule with a black label**, the brightest element on a tile;
  - header pills such as "Review All / View All / Manage".
- **Module screens.** VERIFIED-K for flows (01-overview §5.2; 06-applications):
  - Cleanup / Protection / Performance / Applications / My Clutter each follow *intro → scan → tiles → detail list*.
  - Entry buttons include "Manage My Applications" (Applications) and "Review All Files" (My Clutter).
- **Space Lens (5.1+).**
  - A **bubble** map, largest → smallest, with zoom-in (VERIFIED).
  - The asset catalog holds state overlays for map tiles: Default / Default_Hover / Selected / Selected_Hover / "Smaller Items" (+Focused/Hover) / Clouds_Default (+Hover), plus an Other-Items icon and back/forward navigation chrome. Fills are **tinted per node at runtime**. VERIFIED-OSS.
- **Protection results.** A full set of **malware-family glyphs** is shipped, one per family: adware, backdoor, botnet, dropper, exploit, installer, keylogger, miner, PUA, ransomware, riskware, rootkit, spyware, stealer, trojan, virus, worm, other. VERIFIED-OSS.
- **Health / Assistant.** Gauge states HealthStatusExcellent / Good / Fair / Poor / Critical / Unknown. VERIFIED-OSS. The KB labels are Excellent · Good · Fair · Requires Attention · Critical. VERIFIED-K.

### 4.5 Motion, sound and delight (5.x)

| Element | Fact | Evidence |
|---|---|---|
| Live background | Metal shader colour field. No assets ship for it, so it is fully procedural. | VERIFIED-OSS |
| Cleaning "wipe" | **`WiperFrame_1…6`** sprite sequence: the squeegee wipes across the display during cleaning. | VERIFIED-OSS |
| Seasonal effect | `Snowflakes1…3` + `EmitterMask`: a particle emitter for winter holidays. | VERIFIED-OSS |
| Tips | One **Rive** vector animation. | VERIFIED-OSS |
| Onboarding | **IntroVideo.mp4**. | VERIFIED-OSS |
| Button | Glass-like shader on the Ubiquitous Button (`default.metallib`). | VERIFIED-OSS |
| Reduce Motion | Since 5.0.7 the app adapts to the Mac's accessibility setting by minimising non-essential animation and simplifying visual effects. | VERIFIED |
| Sounds in 5.x | **(corrected, was "not documented")** 5.x has sound effects that the user can switch off. The 5.x preferences plist (Setapp edition, group container `S8EX82NJP6.com.macpaw.CleanMyMac-setapp`) contains a **`SoundsEnabled`** boolean, which a user's dotfiles set to `false` under the comment "Silence sound effects". Which events play a sound, and what they sound like, is still unknown. Precedent: CMM3 played sounds on scan finish, clean finish, cleanup failure, drag-enter and purchase (§2), and X had "atmospheric sounds". | VERIFIED-OSS (dotfiles: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh); X: VERIFIED-K |
| Seasonal / custom themes | **(added)** The same plist has a **`CustomThemes`** boolean. The dotfile author reads it as "Disable custom themes (use system appearance)". It plausibly gates the seasonal (snowflake) and national (Ukrainian) theme layers rather than a full light/dark theme. Semantics unconfirmed. | VERIFIED-OSS (key exists); meaning INFERRED |

### 4.6 Menu bar app ("The Menu", 5.x) — visual summary

- **Layout:** a **grid of tiles**: Health, Protection, Storage, Memory, Battery, CPU, Network, Connected Devices. VERIFIED-K (08-menu-app §1, 01-overview §5.2).
- **Status item:** a monochrome template icon (CMM3 precedent). VERIFIED-K (08).
- **X 4.11:** vertical panels that open detail views. VERIFIED (DevMate).
- Full functional and visual spec for ours → **08-menu-app.md §4**. Visual tokens for it → Part B §B.9.

### 4.7 Microcopy tone (both generations)

**Voice** (VERIFIED-OSS, from strings in the X replica; paraphrased):
- first-person "assistant";
- casual and upbeat;
- reassuring;
- short.

**Patterns:**
- headlines that read like a friend reporting back ("here's what I found");
- playful wait lines during scans;
- three-word imperative column descriptors (remove junk / remove threats / speed up);
- past-tense confirmations at the end;
- "Good" as a verdict when nothing is found.

**Ours:** keep the warmth, write our own lines (§B.12), never alarm.

### 4.8 Additional findings from the fact-check pass (added)

**A. 5.x user-facing preference keys (design-relevant).** VERIFIED-OSS, from two users' dotfiles that write keys their installed CleanMyMac (Setapp edition, 5.x, since "Smart Care" appears) actually reads. Sources: https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh and `hosmelq/.config` `dotfiles/macos/app-settings.json`.

| Domain | Key | Type | What it implies for the UI |
|---|---|---|---|
| `com.macpaw.CleanMyMac-setapp` | `MenuAppEnabled` | bool | A switch for the menu-bar app |
| same | `ShowAssistantRecommendations` | bool | Assistant recommendation cards can be hidden |
| group-container plist `S8EX82NJP6.com.macpaw.CleanMyMac-setapp` | `SoundsEnabled` | bool | **Sound effects exist, with a toggle** |
| same | `CustomThemes` | bool | A theme layer exists that can be switched off (seasonal / national themes; see §4.5) |
| same | `SmartCareReminderEnabled` | bool | Reminder notifications to run Smart Care |
| same | `TrashSizeAlertsEnabled` | bool | Trash-size alerts |
| same | `MalwareScanMode` | string `protected` / `manual` | Real-time vs manual malware scanning |

- The direct edition uses bundle ID `com.macpaw.CleanMyMac5`, the group container `~/Library/Group Containers/S8EX82NJP6.com.macpaw.CleanMyMac5`, and the app path `/Applications/CleanMyMac_5.app`. It runs these launchd jobs: `.Menu`, `.HealthMonitor`, `.Updater` and the privileged `.Agent`. VERIFIED-OSS (fleetdm uninstall script; several process listings on GitHub).
- **Ours (INFERRED):** Settings › General has **Play sounds** (on by default) and **Seasonal effects** (off by default). The canvas keeps a single appearance, so we offer no full theme switch beyond §B.3.4.

**B. MacPaw's own motion library: CocoaSprings.** VERIFIED (README: https://raw.githubusercontent.com/MacPaw/CocoaSprings/main/README.md, MIT).
- It provides damped-spring motion for `CALayer`, `NSView` and **`NSWindow`**.
- `SpringConfiguration` defaults: `angularFrequency` **7.5** and `dampingRatio` **0.5** (0–1).
- `SpringMotionWindow.pinToWindow(_:offsetFromCenter:)` makes a window *follow another window with spring lag*.
- This fits the X evidence that the overhanging sidebar and the action button are **separate windows** that track the main window (§3.1). INFERRED: we have no proof CleanMyMac uses this package.
- **Ours:** if we ever build the optional floating orb (§B.13.7), keep it rigidly attached (child window). Spring lag on a primary button reads as wobbly.

**C. MacPaw's typeface: Fixel.** VERIFIED (README: https://raw.githubusercontent.com/MacPaw/Fixel/main/README.md).
- A free MacPaw typeface in Text and Display widths, with 9 weights from Thin to Black, extended Latin and Cyrillic, and a geometric/humanist grotesque style.
- There is **no evidence** that the CleanMyMac app UI uses it. The 5.5.4 teardown lists no font assets, and both clones assume SF Pro. INFERRED.
- **Ours:** stay on SF Pro / SF Pro Rounded (§B.4). Do not adopt Fixel: it is MacPaw's brand face.

**D. Indirect evidence on Liquid Glass (macOS 26).**
- The 5.5.4 root catalog holds `AppIcon_Assets/*` layer images, named Display-P3 colour swatches (`Color-2…8`) and in-catalog gradients (`Gradient-1/2/3`) next to `AppIcon.icns`. VERIFIED-OSS (teardown §2).
- That structure matches an app icon authored as a **layered (Icon Composer–style) icon**, the format macOS 26 uses for Liquid Glass icons. INFERRED: so the *icon* is likely Tahoe-native.
- For the *window*, 5.x draws its own canvas, back button and primary button and supports macOS 11+. Any system Liquid Glass would mostly show in standard chrome (traffic lights, toolbar, sheets, menus) once built with the macOS 26 SDK. INFERRED.
- Still **unverified** whether the sidebar, buttons or tiles use `glassEffect`. Our plan (§B.6) is to use Liquid Glass only for navigation and controls on 26+.

**E. Timeline (VERIFIED, DevMate appcasts).**

| Version | Date | Version | Date |
|---|---|---|---|
| X 4.10.0 | 21 Dec 2021 | 5.0.7 | 26 Mar 2025 |
| X 4.10.4 | 30 Mar 2022 | 5.1.0 | 12 Jun 2025 |
| X 4.11.0 | 29 Jun 2022 | 5.2.1 | 28 Jul 2025 |
| X 4.15.0 | 5 Feb 2024 | 5.2.6 | 17 Oct 2025 |
| X 4.15.14 (latest X) | 2 Dec 2025 | 5.3.0 | 17 Dec 2025 |
| 5.0.0 | 15 Oct 2024 | 5.3.1 (latest on DevMate) | 28 Jan 2026 |

**F. Secondary corroboration of the Behance notes.** A third-party research note (PureMac `docs/IMPROVEMENT-RESEARCH.md`, citing the Behance case study by Novikov) repeats two design rationales: superellipse shapes are used because "sterile, perfect objects repel people", and the palette is deliberately muted and timeless, "not neon acid tones". This is secondhand, so read it as VERIFIED-K-level corroboration only: https://raw.githubusercontent.com/momenbasel/PureMac/main/docs/IMPROVEMENT-RESEARCH.md

---

## 5. Cross-generation comparison (quick reference)

| Aspect | CleanMyMac X | CleanMyMac (5.x) |
|---|---|---|
| Canvas | Dusty pastel module hue → shared indigo; static gradient | Dark, saturated module hue with a **live Metal aurora**; brighter toward the bottom (CLONE-OBS) |
| Sidebar | Floating frosted **panel overhanging the window's left edge**; outline glyphs; sections with headers; live sizes | Module list with bespoke 24 pt glyphs (Active/Inactive/HCM); glass selection pill (CLONE-OBS); possible icon-only collapse (CLONE-OBS) |
| Hero art | Pink→violet glossy spheres / cards with white objects | Per-domain **silhouettes** (circle, octagon, banner, hexagon, folder, bolt) with two-stop gradients and frosted glyphs; giant magenta brand display for Smart Care |
| Primary action | Ubiquitous orb, 72/82 pt disc + glow, straddling the bottom edge, progress ring | Ubiquitous Button with a Metal glass shader, straddling the bottom edge (CLONE-OBS) |
| Results | Three-column summary → two-pane review lists | Tiles with Review → detail lists; dimmed excluded tiles |
| Accent | Single cyan (#5CE0F7) for interaction everywhere | Module accent per screen; white capsules for direct actions (CLONE-OBS) |
| Type | SF Pro; ultralight giant numerals; small bold labels | SF Pro; "big light display titles" (CLONE-OBS) |
| Motion | Parallax, breathing icons, hover lift, overlay fades | 3D-animated feel, live background, wipe sprite, Rive tips, intro video, Reduce Motion support |
| Sound | Atmospheric sounds (award material) | Sound effects exist, with an on/off preference (`SoundsEnabled`, VERIFIED-OSS) **(corrected)**; the events and their character are unknown |
| Accessibility | Weak: VoiceOver users struggled on first launch (VERIFIED-K, AFB) | VoiceOver + Reduce Motion (5.0.7), HCM icon variants |

---

> **Part B (original design system for our app) follows below.**

## 6. PART B — Original design system for our app (codename **"Prism"**)

Everything in Part B is **INFERRED / original**. It is a recommendation to implement, not a description of MacPaw's product.

Module names follow 01-overview §13:

| Our module | MacPaw equivalent |
|---|---|
| **Checkup** | Smart Care |
| Cleanup | Cleanup |
| Protection | Protection |
| Performance | Performance |
| Applications | Applications |
| **Clutter** | My Clutter |
| **Space Map** | Space Lens |
| **Cloud Storage** | Cloud Cleanup |
| **Toolbox** | My Tools |
| **Activity** | My Activity |
| **Monitor** | the menu-bar app |

### B.0 Guardrails (what we must *not* copy)

**Never reuse:**
- the display-with-squeegee motif or any computer-with-wiper illustration;
- the magenta/pink brand ramp (#FF91D7→#B70193) as our brand colour;
- MacPaw's per-domain badge silhouettes (green circle bin, pink octagon shield, orange banner wrench, blue hexagon broom);
- MacPaw sidebar glyphs;
- the "Ubiquitous Button" name;
- their sounds, intro video or copy strings ("here's what I found"-style lines, "Nice work", etc.);
- the X palette values in §3.3.

**Generic ideas are fine to use:**
- module-tinted backgrounds;
- a circular primary action;
- glassy depth;
- tiles;
- two-pane review lists;
- thin numerals;
- an ambient animated canvas.

What makes ours distinct:
- **Hero language:** "glass lenses" (§B.10), built procedurally in SwiftUI, never bitmaps traced from theirs.
- **Palette:** a cooler indigo-and-cyan brand with mint/coral/amber modules (§B.3).
- **Checkboxes:** rounded-square, not circles.
- **Orb:** the selection total sits inside the orb, and the orb stays **inside** the window by default (§B.8.4).

### B.1 Principles

1. **One surface, one hue, one action.** Each screen has:
   - a module-tinted living canvas;
   - one hero;
   - one primary action.
   Everything else is quiet.
2. **Light is the material.** Depth comes from glow, blooms, frost and specular highlights, not from heavy shadows or skeuomorphic chrome.
3. **Show before you act.** Every destructive action has:
   - a reviewable list;
   - honest totals (selected vs found);
   - a reversible default ("Move to Trash").
   Safety rules are in 02/03.
4. **Calm motion with purpose.**
   - Ambient motion is slow (≥ 8 s cycles).
   - Feedback motion is fast (≤ 250 ms).
   - Progress motion is truthful: the ring tracks real progress, and indeterminate work is shown as a spin.
5. **Accessible by construction.**
   - Text contrast is at least 4.5:1.
   - Every control is keyboard-reachable.
   - Reduce Motion, Reduce Transparency and Increase Contrast each have an explicit design (§B.14).
6. **Cheap when idle.**
   - The canvas animates on the render server or at ≤ 30 fps.
   - It pauses when the window is occluded or not key.
   - The menu-bar popover is static (§B.15).

### B.2 Fidelity matrix — vendor quality → our implementation

| Vendor quality (Part A) | Keep? | Our version |
|---|---|---|
| Edge-to-edge module colour field | **Keep** | `LivingCanvas`: dark vertical base + 3×3 **MeshGradient** (macOS 15+), or 3 radial blooms (macOS 14), + 3 % grain |
| Module re-tint on navigation | **Keep** | 700 ms cross-fade of two canvas layers; sidebar pill slides (matched geometry) |
| Floating sidebar panel overhanging the window (X) | **Change** | In-window **frosted rail**, inset 10 pt from the edges, radius 18. No overhang, so no child window is needed. |
| Ubiquitous circular action straddling the bottom edge | **Adapt** | `ActionOrb` (96 pt disc) **inside** the window, centred on content, 28 pt above the bottom. Optional "Floating orb" setting (off by default) uses a child `NSPanel` (§B.13.7). |
| Pre-rendered 3D icons | **Change** | Procedural "glass lens" heroes in SwiftUI (vector, crisp at any size, themable). Optional Blender renders later, in our own shape language. |
| Thin giant numerals | **Keep (re-styled)** | SF Pro **Rounded** Thin/Light with monospaced digits and numeric content transitions |
| Single cyan interactive accent (X) | **Change** | Per-module `accentText` for interactive text and checkmarks; neutral white capsules for primary in-tile actions |
| Tiles with Review (5.x) | **Keep** | Checkup results grid 3×2 (5 modules + summary tile); every tile has a checkbox, a metric, a status and a **Review** button |
| Two-pane review lists (X) | **Keep** | Category pane 340 pt + item pane + inspector on demand |
| Parallax hero | **Keep (subtle)** | `onContinuousHover` → `rotation3DEffect` ≤ 6°, off under Reduce Motion |
| Atmospheric sounds | **Keep (original)** | 5 original sounds, "Play sounds" toggle (§B.11) |
| Seasonal effects | **Optional** | Off by default. Winter "frost sparkle" particle preset (Settings › General › Seasonal effects) |
| Intro video onboarding | **Change** | Live SwiftUI onboarding with the Checkup lens animation, no video (§B.8.12) |

### B.3 Colour tokens

#### B.3.1 Neutrals and semantic tokens

These apply to the dark canvas, which is the default for every module.

| Token | Value | Use |
|---|---|---|
| `ink.primary` | #FFFFFF @ 100 % | Titles, numbers |
| `ink.secondary` | #FFFFFF @ 72 % | Body text, subtitles (≥ 6:1 on every canvas bottom; checked) |
| `ink.tertiary` | #FFFFFF @ **66 %** **(corrected, was 52 %)** | Captions, metadata, paths. At 52 % it measured only 3.98–4.85:1 on the canvas bottoms, failing 4.5:1 on Cleanup, Performance, Clutter, Cloud Storage and Activity, and ~3.5:1 on cards. At 66 % it is ≥ 5.3:1 on every canvas bottom and ≥ 4.6:1 on `surface.card` (computed with the WCAG 2.x formula in the fact-check pass) |
| `ink.disabled` | #FFFFFF @ 32 % | Disabled labels |
| `ink.onBright` | #0B0B14 | Labels on white or bright fills (≥ 6:1 on every accent) |
| `line.hairline` | #FFFFFF @ 10 % | Row dividers, card rims |
| `line.highlight` | #FFFFFF @ 18 % | 1 pt top inner highlight on raised surfaces |
| `fill.subtle` | #FFFFFF @ 6 % | Hover wash, inputs |
| `fill.control` | #FFFFFF @ 10 % | Secondary buttons, chips |
| `fill.selected` | #FFFFFF @ 14 % | Selected rows / sidebar pill base |
| `surface.card` | material + #FFFFFF @ 7 % | Tiles, list containers |
| `surface.raised` | material + #FFFFFF @ 11 % | Popovers, sheets |
| `scrim` | #05050A @ 55 % | Behind sheets |
| `status.success` | **#34D399** | Done, safe, healthy |
| `status.warning` | **#FBBF24** | Attention, review |
| `status.danger` | **#FF5A5F** | Threats, critical, destructive |
| `status.info` | **#60A5FA** | Neutral information |
| `focus.ring` | `accentText` 2 pt + outer glow 4 pt @ 35 % | Keyboard focus |

#### B.3.2 Per-module palettes

All values below are original. Contrast ratios, re-computed in the fact-check pass (WCAG 2.x relative luminance):
- white on `canvasBottom` is **≥ 9.9:1** for every module. **(corrected)** It was stated as ≥ 10:1, but Activity measures 9.98:1.
- `accentText` on `canvasBottom` is ≥ 5.3:1 (minimum 5.31, Applications).
- `ink.onBright` on `accent` is **≥ 5.9:1**. **(corrected)** It was stated as ≥ 6:1, but Checkup measures 5.96:1 and Applications 5.99:1.
- white on `orbFill` is ≥ 4.6:1 (minimum 4.61: Performance and Activity).
- `ink.secondary` (72 %) on `canvasBottom` is ≥ 6.0:1.
- `ink.tertiary` needs 66 % to pass (§B.3.1).

| Module | Hue idea | `canvasTop` | `canvasBottom` | `accent` | `accentText` | `accent2` | `glow` | `orbFill` | SF Symbol (rail) |
|---|---|---|---|---|---|---|---|---|---|
| **Checkup** | indigo nebula + cyan spark | #0E0B26 | #2A1F66 | #8C7BFF | #A99CFF | #45D9F5 | #6F5CFF | #6556C2 | `sparkles` |
| **Cleanup** | lagoon mint | #051A17 | #0C4A3B | #3BE8A9 | #3BE8A9 | #C2F261 | #1FCB8A | #1D8464 | `bubbles.and.sparkles` |
| **Protection** | coral ember | #1E0710 | #5A1428 | #FF6177 | #FF8193 | #FFB08A | #F23D5C | #BD4257 | `shield.lefthalf.filled` |
| **Performance** | solar amber | #1F1003 | #5C2E06 | #FFAC33 | #FFAC33 | #FFE066 | #FF8A00 | #A5671A | `bolt.fill` |
| **Applications** | cobalt | #070F2B | #15306E | #5C88FF | #86A6FF | #7FE6FF | #3D6BFF | #4065C5 | `square.grid.2x2.fill` |
| **Clutter** | glacier aqua | #03191F | #0A4552 | #2ED6EE | #2ED6EE | #7CF5D4 | #00B8D9 | #187F90 | `square.stack.3d.up.fill` |
| **Space Map** | orchid | #130A26 | #3B1F6E | #B98CFF | #C9A6FF | #FF8AD8 | #9B5CFF | #8760C5 | `circle.hexagongrid.fill` |
| **Cloud Storage** | high sky | #06142A | #173E70 | #66BFFF | #66BFFF | #E4F3FF | #3FA6FF | #3B78B0 | `icloud.fill` |
| **Toolbox** | slate lilac | #10121F | #2C3152 | #A4ADE6 | #A4ADE6 | #E1E5FF | #7F8BD6 | #6A719F | `wrench.and.screwdriver.fill` |
| **Activity** | chartreuse | #0D1A08 | #2E4A12 | #BEEB6B | #BEEB6B | #7EE0B0 | #9BD63A | #5E7F2F | `chart.line.uptrend.xyaxis` |
| **Monitor** (popover) | graphite + status | #121318 | #1E2130 | status colour | — | — | status @ 30 % | — | `waveform.path.ecg` |

**(corrected)** Symbol availability was checked against the SFSafeSymbols per-release lists (https://github.com/SFSafeSymbols/SFSafeSymbols, `Sources/SFSafeSymbols/Symbols/SFSymbol+X.Y.swift`). VERIFIED-OSS. Every rail and hero symbol in this table exists on macOS 14:
- `bubbles.and.sparkles` is SF Symbols 4 (macOS 13).
- `chart.line.uptrend.xyaxis` is SF Symbols **3** (macOS 12), not 4.
- `shield.lefthalf.filled` and `circle.hexagongrid.fill` are SF Symbols 3.
- `wrench.and.screwdriver.fill` is SF Symbols 2.
- `sparkles`, `bolt.fill`, `square.grid.2x2.fill`, `square.stack.3d.up.fill`, `icloud.fill` and `waveform.path.ecg` are SF Symbols 1.

Still glance at them in the SF Symbols app for visual fit.

**How tokens are used:**
- `canvasTop`/`canvasBottom`: the base linear gradient, top → bottom. In our design the **bottom is the brighter, more saturated stop**, so the light pools behind the hero and the orb.
- `accent`: hero glow core, progress-ring head, tile checkbox fill, selected-rail rim, chart strokes.
- `accentText`: interactive text (links, "Review" labels on dark), selected-row checkmark, big metric colour.
- `accent2`: secondary mesh point and the progress-ring tail (angular gradient accent → accent2), sparkle particles.
- `glow`: bloom colour behind the hero and orb, and the orb's shadow.
- `orbFill`: the orb disc colour, chosen as the brightest accent/bottom mix that still carries a white label at ≥ 4.6:1.

#### B.3.3 Mesh gradient recipe (macOS 15+)

The mesh is a 3×3 grid. Colours are derived from the tokens, so no extra hex values are needed (`mix` = `Color.mix(with:by:)`, macOS 15):

```
row 0:  canvasTop            canvasTop                    accent2 @ 14 % over canvasTop
row 1:  mix(top,bottom,.45)  accent @ 30 %·k over mid     mix(top,bottom,.55)
row 2:  canvasBottom         glow @ 55 %·k over bottom    canvasBottom
k = 1.0 idle · 1.35 scanning · 0.8 results · 1.6 for 1.2 s on completion
```

**Point motion.**
- Edge points stay fixed.
- The centre point drifts ±0.08 on a 24 s sine.
- The middle points of the left and right edges move ±0.06 vertically (phase offsets 0 and 3.4 rad).
- The bottom-middle point drifts ±0.10 horizontally.
- Result: a slow "breathing aurora" with no visible loop.

**Overlay.** 3–3.5 % monochrome **grain** to kill gradient banding on large displays.

#### B.3.4 Light appearance policy

- **Default.** The canvas is **always dark-tinted, whatever the system appearance**. The module colour field is the identity, and both CleanMyMac generations behave this way (§3.10).
- Settings › General › Appearance offers **Dark (default) · Match System · Light**.
- **Light ("Daylight") tokens:**
  - `canvasTop` = accent @ 6 % over #FAFAFF;
  - `canvasBottom` = accent @ 18 % over #EEF0F7;
  - `ink.primary` #14151F;
  - `ink.secondary` #14151F @ 70 %;
  - surfaces are white @ 70 % + material.
  - Checked: ink on the Checkup daylight canvas is ≥ 12:1.
- System chrome (menus, alerts, Settings window) always follows the system appearance.

### B.4 Typography

The system font is **SF Pro**. SwiftUI switches between Text and Display optical sizes automatically. **SF Pro Rounded** is used for metrics, and **SF Mono** for paths.

| Token | Spec (`Font.system`) | Use |
|---|---|---|
| `display` | 40, `.light`, tracking −0.4 | Module title on intro / hero screens ("Cleanup") |
| `headline` | 26, `.semibold` | Flow headlines ("6.2 GB ready to clean") |
| `title` | 20, `.semibold` | Pane titles, sheet titles |
| `metricXL` | 56, `.thin`, `.rounded`, `monospacedDigit()` | The result number on module result screens |
| `metricL` | 34, `.light`, `.rounded`, `monospacedDigit()` | Tile metrics |
| `metricS` | 22, `.regular`, `.rounded`, `monospacedDigit()` | Inline stats, Monitor tiles |
| `unit` | 13, `.medium` | Unit next to a metric ("GB") at `ink.secondary` |
| `bodyStrong` | 13, `.semibold` | Row titles, tile titles |
| `body` | 13, `.regular` | Body text |
| `callout` | 12, `.regular` | Descriptions under titles |
| `caption` | 11, `.regular` | Metadata, sizes in rows (`monospacedDigit`) |
| `overline` | 10, `.semibold`, uppercase, tracking +0.8 | Sidebar section headers, tile eyebrow labels |
| `button` | 13, `.semibold` | Capsule buttons |
| `orbLabel` | 15, `.semibold` | Orb main label |
| `orbDetail` | 11, `.medium`, `monospacedDigit()` | Selection total inside the orb |
| `mono` | 11, `.regular`, `.monospaced` | Paths, bundle IDs |

**Rules:**
- No more than two weights per component.
- Numbers always use monospaced digits.
- Change numbers with `.contentTransition(.numericText())`.
- Truncate long paths in the middle.

### B.5 Spacing, layout and sizes

- **Spacing scale** (4 pt grid): `2 · 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 80`.
- **Radii** (all `.continuous`):

| Radius | Use |
|---|---|
| `xs` 6 | badges, chips |
| `s` 8 | inputs, small buttons |
| `m` 12 | rows, list containers, Monitor tiles |
| `l` 18 | tiles, cards, rail pill, rail panel |
| `xl` 26 | sheets, onboarding cards |
| capsule | buttons |
| circle | orb, checkbox halo |

- **Window:**
  - default **1180 × 740** (≈1.6:1);
  - minimum **1040 × 680** (fits a 1280×800 display with Dock and menu bar);
  - full-size content, hidden title bar, traffic lights over the canvas;
  - content starts 28 pt below the top.
- **Rail:**
  - expanded **232 pt**, collapsed **76 pt**;
  - inset 10 pt from the window's left, top (below the traffic lights, y = 44) and bottom;
  - radius 18;
  - rows 34 pt high, icon 18 pt, label 13 pt;
  - section headers use `overline`.
  - **Collapse:** the rail auto-collapses when a module enters results or review, and re-expands on hover after 400 ms or on ⌘0. INFERRED. The clone evidence (§4.2) suggests the vendor does something similar.
- **Content area:**
  - horizontal padding 40 pt;
  - maximum readable width 1000 pt, centred;
  - top bar 52 pt.
- **Hero art:** 300 pt (intro) → 220 pt (scanning) → 150 pt (results header).
- **Orb:**
  - disc 96;
  - progress track 112;
  - glow canvas 200;
  - centre 76 pt above the bottom of the window (so it sits 28 pt clear).
- **Tiles:**
  - minimum 280 × 176;
  - 16 pt gap;
  - 3 columns ≥ 1100 pt content width, otherwise 2.
- **Lists:** category rows 52 pt, item rows 44 pt, inspector 300 pt.
- **Hit targets:** at least 28 × 28 pt; checkboxes get a 36 pt hit area.

### B.6 Elevation, glow and materials

| Token | Spec |
|---|---|
| `elev.card` | shadow black 28 %, radius 18, y 8; plus a 1 pt `line.highlight` inner top edge and a `line.hairline` rim |
| `elev.raised` | shadow black 40 %, radius 40, y 20 |
| `glow.hero` | circle of `glow` @ 35 % · k, diameter 0.9 × hero, blur 48 |
| `glow.orb` | circle of `glow` @ 40–60 % breathing, diameter 1.5 × disc, blur 28. Breathing is a Core Animation opacity animation (render server), not a SwiftUI repeat loop. |
| `glow.focus` | `accentText` @ 35 %, blur 4, outside a 2 pt ring |

**Materials:**

| macOS | Layer | Treatment |
|---|---|---|
| 14–15 | Tiles / cards | `.ultraThinMaterial` (dark scheme forced) + white 7 % + hairline |
| 14–15 | Rail | `.ultraThinMaterial` + white 5 % |
| 14–15 | Popover / sheet | `.regularMaterial` |
| 26 (Tahoe) | Navigation / controls only | **Liquid Glass** on the rail selection pill, top-bar buttons, segmented controls, Monitor header and capsule buttons: `.glassEffect(.regular.tint(theme.accent.opacity(0.10)).interactive(), in: .capsule)`. Group neighbours in `GlassEffectContainer` so they morph. **Content stays on our frosted surfaces**: lists and tiles are content (Apple's Liquid Glass guidance), and glass over our saturated canvas reads muddy. |
| any | Reduce Transparency | All materials → opaque `canvasBottom` mixed 20 % with white (dark) or solid white (light). Canvas animation stays; blur is removed. |

### B.7 Motion system

**Durations and curves.**

| Token | Value | Curve | Use |
|---|---|---|---|
| `instant` | 0.08 s | `.easeOut` | Press-down scale |
| `quick` | 0.15 s | `.easeOut` | Hover washes, checkbox tick, chip toggles |
| `standard` | 0.25 s | `.snappy(duration: 0.25)` | Content fades/slides, rows appearing |
| `emphasized` | 0.45 s | `.spring(duration: 0.45, bounce: 0.18)` | Hero transform, orb state morph, tile reveal |
| `scene` | 0.70 s | `.smooth(duration: 0.7)` | Canvas re-tint between modules |
| `celebrate` | 1.2 s | keyframes | Completion burst + count-up |
| `ambient` | 8–30 s | linear / sine | Canvas drift (24 s), breathe (8 s), orb glow (1.8 s half-cycle), scanning orbit (6 s/rev) |

**Choreography.**

| Moment | Spec |
|---|---|
| Rail selection | The pill slides with `matchedGeometryEffect` (`emphasized`). The canvas cross-fades (`scene`). The old content fades and moves 8 pt opposite to travel; the new content fades in and moves 8 pt with travel (`standard`, 40 ms later). |
| Hover: row / tile / button | Wash to `fill.subtle` (`quick`). Tile: lift 2 pt, shadow +4 radius. Button: brightness +4 %. |
| Press | Scale 0.97 (orb 0.96), `instant`, release with a spring (`standard`). |
| Scan start | Hero shrinks 300→220 pt and moves up 24 pt (`emphasized`). The orb morphs from label "Scan" to the progress ring + "Stop" (cross-fade). Canvas k 1 → 1.35 over 1 s. Inward-drifting "dust" particles start (§B.13.5). |
| Scanning | The ring interpolates linearly to each new progress value over 0.3 s, and never goes backwards. Indeterminate phases show a 90° arc spinning at 1 rev/1.2 s. The status line ("Scanning ~/Library/Caches…") updates at ≤ 10 Hz with a 150 ms cross-fade. The running total counts up with `numericText`. |
| Results reveal | The headline fades in. Tiles stagger in 60 ms apart, each `emphasized` from y + 16, opacity 0, scale 0.98. Metric count-up 900 ms ease-out. |
| Checkbox | Fill and checkmark draw (trim 0 → 1, `quick`). Partial state = dash. The parent tile metric re-counts (`standard`). |
| Run / Clean | The orb shows a determinate ring. Rows being processed fade out and collapse (`standard`, 20 ms stagger, capped at the first 30 rows). |
| Completion | Ring completes → the disc fills with `status.success` mixed 30 % → a check glyph draws (0.4 s) → a particle burst (28–40 particles, 0.9 s) → sound → the headline swaps to the summary. The orb then turns into "Done" and fades away. **(corrected)** The step `sensoryFeedback(.success)` was removed. Apple documents that `.success` "only plays feedback on iOS and watchOS", so it does nothing on a Mac. See §B.13.9. |
| Sheet | Scrim fade 0.2 s; card scale 0.96 → 1 plus fade (`standard`). |
| Space Map zoom | The tapped bubble scales to fill (`emphasized`), siblings fade, and the breadcrumb pushes. |
| Monitor popover | Fade + scale 0.98 → 1 (0.2 s). The health ring sweeps from 0 → score (0.9 s) on open only. |

**Reduce Motion mapping** (vendor precedent: 5.0.7):
- The canvas is static: no drift, no breathe.
- No parallax and no particles.
- All transforms become 0.2 s cross-fades.
- Count-ups are replaced by a final value with a cross-fade.
- The progress ring still animates, because it carries information, but with no glow pulse.
- The completion is a check glyph plus the sound, with no burst.

### B.8 Components

#### B.8.1 Window shell

```
┌─ traffic lights ───────────────────────────────────────────────────────────────┐
│ ╭─ rail (frosted, r18) ─╮   ‹ Start Over        Cleanup          [⌕ Search] 🔔 │ ← top bar 52pt
│ │  ✦ Checkup        ●   │                                                       │
│ │ MODULES               │              (hero lens 300pt, glow)                   │
│ │  ◌ Cleanup    6.2 GB  │                                                       │
│ │  ◌ Protection   ✓     │              Cleanup   (display 40 light)              │
│ │  ◌ Performance  3     │       Clear caches, logs and leftovers safely.         │
│ │  ◌ Applications 4↑    │     • feature row   • feature row   • feature row      │
│ │  ◌ Clutter            │                                                       │
│ │ STORAGE               │                                                       │
│ │  ◌ Space Map          │                     ╭──────────╮                      │
│ │  ◌ Cloud Storage      │                     │   Scan   │  ← ActionOrb 96pt     │
│ │ TOOLS                 │                     ╰──────────╯                      │
│ │  ◌ Toolbox  ◌ Activity│                                                       │
│ │ [♥ Health: Good]  ⚙   │                                                       │
│ ╰───────────────────────╯                                                       │
└─────────────────────────────── living canvas fills everything ──────────────────┘
```

- **Window configuration:** `.windowStyle(.hiddenTitleBar)`; toolbar background hidden; the canvas extends under the title bar.
- **Top bar, left:** "Start Over" (results) or "‹ Back" (review/detail) as a plain text button with `chevron.left`, 13 pt medium, `ink.secondary` → `ink.primary` on hover.
- **Top bar, centre:** the module name in `callout` at `ink.tertiary`. It is hidden on intro screens, where the display title already names the module.
- **Top bar, right:** a search field (review lists only; 200 × 28, radius 8, `fill.control`), the **bell** (notifications), and on macOS 26 Liquid-Glass circular buttons.
- **Rail footer:** a Health pill (dot in a status colour + "Good") and a Settings gear.

#### B.8.2 Rail (sidebar)

- **Row:**
  - an 18 pt SF Symbol (hierarchical), `ink.tertiary` inactive / `accentText` active, then the label in `body` (`ink.secondary` / `ink.primary` semibold when active);
  - right-aligned **live badge**: a size (caption, monospaced), a count, a ✓ (`status.success`), a mini 12 pt spinner while scanning, or a warning dot.
- **Selected pill:** `fill.selected`, radius 12 inside the rail. A 1 pt rim with a linear gradient: `accent` @ 70 % on the leading edge → clear on the trailing edge. A faint inner top highlight.
  - On macOS 26 the pill is `.glassEffect(.regular.tint(accent.opacity(0.12)), in: .rect(cornerRadius: 12))`.
- **Hover:** `fill.subtle`, with no rim.
- **Sections:**
  - Checkup alone at the top;
  - MODULES (Cleanup, Protection, Performance, Applications, Clutter);
  - STORAGE (Space Map, Cloud Storage);
  - TOOLS (Toolbox, Activity).
- **Collapsed:** icons only, centred in a 44 pt pill, with the label in a tooltip. Badges become 6 pt dots at the icon's top-right.
- **Keyboard:** ⌘1…⌘9 jump to modules; ↑/↓ move between rows when the rail has focus; Return opens the module.

#### B.8.3 Hero ("glass lens") — see §B.10 for construction

- **States:**
  - `intro`: 300 pt, glow k = 1, parallax on;
  - `scanning`: 220 pt, orbit ring + particles;
  - `results`: 150 pt, docked top-left of the results header;
  - `clean`: calm, glow k = 0.6, with a small ✓ badge;
  - `limited`: desaturated 40 %, with a lock badge (missing Full Disk Access or helper).
- **Parallax:** pointer position within the window maps to `rotation3DEffect` of up to ±6° on x and y, with a 0.3 s smoothing spring. It returns to 0 when the pointer leaves.

#### B.8.4 ActionOrb (primary action)

| State | Disc | Ring (track 112 pt) | Label (inside) | Detail (inside, under the label) | Glow |
|---|---|---|---|---|---|
| `idle` | `orbFill` + specular | track white 14 % | **Scan** | — | breathe 40 → 60 % (1.8 s) |
| `hover` | +6 % brightness, scale 1.03 | track white 22 % | — | — | 70 % |
| `pressed` | scale 0.96 | — | — | — | 50 % |
| `scanning` | `orbFill` @ 85 % | determinate arc `accent→accent2`, 3 pt, round caps (or a spinning 90° arc if indeterminate) | **Stop** | % or running size | steady 55 % |
| `stopping` | dim 70 % | arc frozen | Stopping… | — | 30 % |
| `ready` | `orbFill`, ring in `accentText` 2 pt | full track in accent @ 40 % | **Clean / Run / Remove / Uninstall / Update** | selected total ("6.2 GB", "4 apps") | 65 % |
| `running` | as `scanning` | determinate | **Stop** | items left | 55 % |
| `done` | morphs to `status.success` mix 30 % | full success ring | ✓ glyph (draw) | freed total | burst, then fade out after 1.6 s |
| `disabled` | `orbFill` @ 35 % | track 8 % | label @ 40 % | "Nothing selected" | 0 |

- **Placement:** horizontally centred on the content area (not the window), with its centre 76 pt above the window's bottom edge.
- **Keyboard:** Return triggers it (default action). Esc maps to Stop while busy.
- **VoiceOver:** "Scan Cleanup, button", "Stop scan, 42 percent", "Clean 6.2 gigabytes, button".

#### B.8.5 Progress indicators

| Indicator | Spec |
|---|---|
| Orb ring | Primary progress indicator for module scans and cleans |
| Checkup checklist | During a Checkup scan, five rows (module glyph + name + status) sit under the hero. Status cycles waiting → spinner → ✓ with a result ("2.4 GB", "No threats"). |
| Linear bar | Inline only (Monitor, Updater). 4 pt high, radius 2, track white 10 %, fill `accent`. No shimmer under Reduce Motion. |

#### B.8.6 Tile (Checkup results, module dashboards)

```
╭───────────────────────────────────────╮  r18, surface.card, elev.card
│ [lens 28] CLEANUP              [☑]    │  overline + 16pt checkbox (36pt hit area)
│                                       │
│ 6.2 GB                                │  metricL 34 light rounded + unit 13
│ Caches, logs and 3 leftovers          │  callout, ink.secondary, 2 lines max
│                                       │
│ ( Review )        ( Clean now ▸ )     │  glass capsule + optional white capsule
╰───────────────────────────────────────╯
```

**States:**

| State | Look |
|---|---|
| default | as drawn |
| hover | lift 2 pt + surface +3 % |
| unchecked | metric and badge at 45 % opacity, checkbox empty; still clickable to re-include |
| excluded (by Settings) | 35 % opacity, a "Skipped" chip, no checkbox; hover shows a "Change in Settings" link |
| clean | metric replaced by an "All good" headline + ✓ in `status.success`; no Review button |
| limited | a "Limited — grant Full Disk Access" chip in `status.warning`, with the button "Grant…" |
| scanning | metric shows a 12 pt spinner + "Checking…" |
| error | "Couldn't finish" + Retry |

**Checkup grid:**
- five module tiles plus one **Summary** tile (total selected size, threats, tasks, time saved estimate);
- 3 × 2 at ≥ 1100 pt content width;
- the Summary tile spans 2 rows at wide widths.

#### B.8.7 Review lists (two-pane)

- **Category pane (340 pt):**
  - header: "Select All / Deselect All" chip + "Sort: Size ▾" menu;
  - rows (52 pt): 16 pt checkbox · 32 pt category badge (rounded-square r 9, two-stop gradient from module `accent` → `glow`, white SF Symbol 15 pt) · name `bodyStrong` · size `caption` monospaced (right) · chevron;
  - empty categories are shown at 40 % with "Nothing found" and no checkbox;
  - selected row: `fill.selected` r 12 + accent rim.
- **Item pane:**
  - title `title` + description `callout` (2–3 lines, plain-language: what it is, why it's safe);
  - a **Safety note** chip where relevant (e.g. "Rebuilt automatically by macOS");
  - rows (44 pt): checkbox · 20 pt Finder icon (`NSWorkspace.icon(forFile:)`) · name (middle-truncated) · secondary path in `mono` · size · hover actions (Reveal `magnifyingglass`, Quick Look `eye`, Ignore `eye.slash`, Explain `sparkles` if on-device AI is available).
- **Footer bar:**
  - "214 items selected · 6.2 GB of 7.9 GB" (left, `caption`);
  - the orb is centred.
- **Inspector (300 pt, toggle ⌥⌘I):** icon, name, full path (mono, selectable), size on disk, modified/accessed dates, owner app, safety rationale, actions.

#### B.8.8 Checkbox, badges, chips, buttons

- **Checkbox:** 16 pt rounded square (r 5).
  - Off: 1.5 pt stroke white 40 %.
  - On: fill `accent`, check glyph in `ink.onBright` (11 pt bold).
  - Mixed: a dash.
  - Animation: tick trim `quick`.
  - Hit area: 36 pt.
- **Size badge:** capsule, `caption` semibold monospaced, `fill.control` + `ink.primary`. Sizes ≥ 1 GB use `accentText`.
- **Status chip:** capsule, 11 semibold, status colour @ 16 % fill + status-colour text + 1 pt rim @ 30 %.
- **Buttons:**

| Kind | Look |
|---|---|
| Primary on canvas | the Orb |
| Primary in tiles/sheets | **white capsule** with `ink.onBright` label (or `status.danger` fill + white for irreversible delete) |
| Secondary | glass/frost capsule with a white label |
| Tertiary | text button in `accentText` |

Capsule height is 28 (regular) / 34 (large); horizontal padding 14 / 20.

#### B.8.9 Sheets and confirmations

- A centred card, 460 pt wide, r 26, `surface.raised`, `elev.raised`, over the scrim.
- Content:
  - a title (`title`);
  - a summary line with totals;
  - a scrollable list (max 6 rows visible) grouped by category with sizes;
  - the removal method ("Move to Trash", reversible — default; or "Delete immediately", danger).
- Buttons: Cancel (secondary, Esc) and the primary (Return).
- **Irreversible actions:** the primary is `status.danger`, and the user must type or hold for 0.6 s if there are more than 10 GB or more than 500 items. INFERRED safety pattern.
- **Running-apps warning:** the app icons in a row + "Quit & Continue" / "Skip their files".

#### B.8.10 Empty, clean and permission states

| State | Hero | Headline | Body | Action |
|---|---|---|---|---|
| Nothing found | calm lens, ✓ badge | "Spotless." | "No junk worth removing right now. We'll keep an eye on it." | Scan again |
| No threats | calm lens with a shield | "No threats found." | "Real-time monitoring is on." (or off → link) | Scan again |
| No updates | calm | "Everything's up to date." | Last checked time | Check again |
| Limited (no Full Disk Access) | desaturated lens + lock | "Some places are off-limits." | "Grant Full Disk Access so we can check caches, Mail and Trash." | Grant Access… (deep link) |
| Helper needed | lens + key | "This needs an admin OK." | Short reason | Continue (system auth prompt) |
| Error | lens with a warning dot | "Couldn't finish this scan." | Error summary + "Details" disclosure | Retry |

#### B.8.11 Toasts and undo

- A bottom-left glass capsule (above the rail footer), 32 pt high, auto-dismissing after 5 s.
- Example: "Moved 214 items to Trash · **Undo**". Undo restores via `NSFileManager` from the Trash records we keep (see 03-cleanup).

#### B.8.12 Onboarding (4–5 steps, aligned with 01-overview §9.2)

- **Layout:**
  - full-window Checkup canvas;
  - no rail;
  - a centred card stack (max 560 pt wide);
  - step dots;
  - primary white capsule + text "Skip".
- **Step 1: Welcome.** The lens assembles: three orbit rings fade in and lock, with a sparkle. 1.6 s; static under Reduce Motion.
- **Step 2: What it does.** Three cards: Clean · Protect · Speed up.
- **Step 3: Full Disk Access.**
  - An animated diagram of the System Settings toggle (drawn with SF Symbols, not a screenshot).
  - A draggable app-icon tile.
  - Live status: a "Waiting for access…" spinner → ✓.
- **Step 4: Notifications, then Menu bar Monitor.**
- **Finish:** land on Checkup with the orb pulsing once.

### B.9 Monitor (menu bar) visuals

The functional spec is in 08-menu-app.md §4. This section covers visual tokens only.

- **Status item:**
  - template SF Symbol `waveform.path.ecg` (or a custom 16 pt glyph), monochrome;
  - tinted `status.warning` / `status.danger` only while a problem is active.
- **Popover:**
  - `MenuBarExtra(...).menuBarExtraStyle(.window)`, **360 pt wide**;
  - Monitor canvas: graphite gradient #121318 → #1E2130, plus **one static radial bloom** in the current health colour @ 25 % at the top-centre. No mesh animation, to keep the CPU budget.
- **Header:**
  - a 64 pt health ring: 6 pt track white 10 %, arc in the status colour, round caps;
  - the headline ("Your Mac is in good shape", `bodyStrong` 15);
  - a device line (`caption`).
- **Tiles:** 2-column grid, r 12, `surface.card`, padding 12. Each tile has:
  - an `overline` label;
  - a `metricS` value + unit;
  - a 2 pt sparkline (60 samples) or a mini ring;
  - one capsule action ("Free Up", "Empty Trash").
- **Footer:** "Open <App>" text button · Settings gear · last-scan age.
- **Motion:**
  - ring sweep on open (0.9 s);
  - values update every 2 s with `numericText`;
  - sparklines shift without animation, so nothing redraws needlessly.

### B.10 Iconography and hero art

#### B.10.1 SF Symbols map

Use hierarchical rendering: primary = white or `accentText`, secondary = `accent2`.

| Area | Symbols |
|---|---|
| Rail | see §B.3.2 table |
| Top bar | `chevron.left`, `magnifyingglass`, `bell`, `bell.badge`, `gearshape`, `info.circle` |
| Row actions | `magnifyingglass.circle` (reveal), `eye` (Quick Look), `eye.slash` (ignore), `sparkles` (explain), `arrow.uturn.backward` (undo) |
| Cleanup categories | user caches `internaldrive` · system caches `gearshape.2` · logs `doc.text` · language files `character.bubble` · Xcode `hammer` · iOS backups `iphone` · broken prefs `slider.horizontal.3` · broken login items `person.crop.circle.badge.xmark` · document versions `doc.on.doc` · mail attachments `paperclip` · trash `trash` · deleted users `person.slash` |
| Protection | threats `exclamationmark.shield` · adware `megaphone` · keylogger `keyboard` · PUA `questionmark.app` · privacy `hand.raised` · cookies `circle.grid.3x3` · history `clock.arrow.circlepath` · permissions `lock.shield` |
| Performance | maintenance `wrench.adjustable` · RAM `memorychip` · DNS `network` · Spotlight `magnifyingglass` · login items `power` · background items `gearshape.arrow.triangle.2.circlepath` · Time Machine snapshots `clock.badge.checkmark` |
| Applications | uninstall `trash.square` · updates `arrow.down.circle` · leftovers `shippingbox` · installers `archivebox` · unused `moon.zzz` · extensions `puzzlepiece.extension` |
| Clutter | large files `doc.richtext` · old files `calendar.badge.clock` · duplicates `doc.on.doc` · similar photos `photo.on.rectangle` · downloads `arrow.down.to.line` |
| Monitor | `cpu`, `memorychip`, `internaldrive`, `battery.100percent` **(corrected: `battery.100` is deprecated on macOS 14 and renamed `battery.100percent`, SF Symbols 5)**, `wifi`, `antenna.radiowaves.left.and.right`, `cable.connector` |

All other names in this table were found in the SFSafeSymbols lists. VERIFIED-OSS. Notable minimums: `person.slash` needs SF Symbols 5 (macOS 14); `wrench.adjustable` and `gearshape.arrow.triangle.2.circlepath` need SF Symbols 4 (macOS 13). The rest are SF Symbols 1–3.

Use symbol effects on macOS 14+ (`symbolEffect`, VERIFIED macOS 14):
- `.bounce` on value change (e.g. a ✓ arriving);
- `.pulse` while waiting;
- `.variableColor` for Wi-Fi/scanning hints.

`.breathe`, `.rotate` and `.wiggle` exist only on macOS 15+. VERIFIED **(upgraded from INFERRED)**: Apple docs list `BreatheSymbolEffect`, `RotateSymbolEffect` and `WiggleSymbolEffect` as macOS 15.0, and `BounceSymbolEffect` as macOS 14.0. Use the macOS 15 effects behind `if #available(macOS 15, *)`.

#### B.10.2 Hero "glass lens" construction (original)

The heroes are vector, procedural and themable, drawn as a 7-layer SwiftUI stack:

| # | Layer | Spec |
|---|---|---|
| 1 | Bloom | `Circle` filled with `glow` @ 35 %·k, size 0.9×, blur 48 |
| 2 | Lens body | `Circle` with `RadialGradient(accent2 @ 90 % → accent → canvasBottom @ 95 %)`, centre (0.35, 0.30), end radius 0.75× |
| 3 | Frost core | `Circle` at 0.70× with `.ultraThinMaterial` + white 8 % (opaque mix under Reduce Transparency) |
| 4 | Glyph | module hero SF Symbol at 0.36× size, `.symbolRenderingMode(.hierarchical)`, white → `accent2`, shadow `glow` @ 50 % r 10 |
| 5 | Specular | top-left elliptical arc: white 0 → 45 % → 0 linear gradient, 0.55× wide, blur 2, rotated −20° |
| 6 | Rim | `Circle().strokeBorder(AngularGradient(white 55 %, clear, accent @ 60 %, clear, white 55 %), lineWidth: 1.5)` |
| 7 | Orbit (scanning only) | `Ellipse` 1.25× × 0.45×, rotated −18°, stroke white 18 %; a 6 pt dot in `accent2` travelling along it (6 s/rev). Checkup has **three** orbit rings at 0°, 60° and 120°, one per pillar (Clean, Protect, Speed). |

**Per-module hero glyphs:**

| Module | Hero glyph |
|---|---|
| Checkup | `sparkles` + 3 orbits |
| Cleanup | `bubbles.and.sparkles` |
| Protection | `shield.lefthalf.filled` |
| Performance | `bolt.fill` |
| Applications | `square.grid.2x2.fill` |
| Clutter | `square.stack.3d.up.fill` |
| Space Map | `circle.hexagongrid.fill` |
| Cloud Storage | `icloud.fill` |
| Toolbox | `wrench.and.screwdriver.fill` |
| Activity | `chart.line.uptrend.xyaxis` |

**Optional raster upgrade (later).** Render the same lens concept in Blender:
- top-left key light at 45°, rim light from bottom-right in `accent`;
- glass BSDF with roughness 0.15;
- export 600 × 600 @2x PNG into an asset catalog.

Keep one shape (the lens) for every module, so the system is clearly our own rather than a per-domain silhouette set.

### B.11 Sound design (original assets)

| Event | Character | Length | Notes |
|---|---|---|---|
| `scan.start` | soft airy rising "shimmer" | 220 ms | Only when the user presses Scan |
| `scan.complete` | two-note glassy chime, rising major third | 480 ms | Skip if the scan took < 1.5 s |
| `clean.complete` | gentle whoosh → sparkle tail | 900 ms | Synced to the completion burst |
| `attention` | low rounded "bloop" | 300 ms | Threats found, or action needed |
| `error` | muted double tap | 250 ms | Failures only |

- **Mastering:** about −18 LUFS integrated, peaks ≤ −3 dBFS, 48 kHz, delivered as `.caf`/AAC; total size under 200 KB.
- **Playback:**
  - use `AVAudioPlayer` (preloaded, `prepareToPlay`) or `NSSound`;
  - volume 0.6 × user setting;
  - never overlap: a new sound cancels the old one;
  - no sounds while the app is in the background, except for a user-initiated Monitor action.
- **Settings:** General › **Play sounds** (default **on**). The vendor treats sound as part of the experience, and 5.x has a matching `SoundsEnabled` switch (§4.8 A).
- **System preference:** also honour the system "Play user interface sound effects" setting.
  - The key is `com.apple.sound.uiaudio.enabled` (int/bool), usually in `NSGlobalDomain`. Some setups write it to the `com.apple.systemsound` domain. VERIFIED-OSS: many dotfiles map that checkbox to this key, e.g. wincent/wincent `aspects/defaults/index.ts`, keith/dotfiles `osx/defaults.sh`.
  - Read it as `UserDefaults.standard.object(forKey:)`, treating a missing key as "on". Fall back to `UserDefaults(suiteName: "com.apple.systemsound")`.
  - INFERRED: re-check on macOS 26.
- **Production:** synthesise in-house (e.g. with a small AudioKit or SoX script) or license royalty-free. Do not sample MacPaw's sounds.

### B.12 Microcopy voice

**Voice:**
- a calm, competent friend;
- second person ("your Mac"), occasional "we";
- plain words, no fear, no hype;
- numbers first.

**Patterns:**
- Lead with the result.
- Explain safety in one clause.
- Offer the next step.
- Never say "junk" about the user's own files: call them "files to review".

All lines below are original examples for our app.

| Moment | Examples |
|---|---|
| Checkup idle | "Let's give your Mac a once-over." · Sub: "Cleanup, protection, speed, apps and clutter: one scan, about a minute." |
| Scanning (rotate every 3 s) | "Peeking into caches…" · "Checking login items…" · "Looking for leftovers…" · "Asking apps about updates…" |
| Checkup results | "Here's the rundown." · Sub: "6.2 GB to clean, 4 updates, no threats. Everything below is pre-selected and safe to run." |
| Module results | "6.2 GB ready to clean" · Sub: "Only files macOS and your apps can rebuild." |
| Completion | "Done. You freed 6.2 GB." · "All tidy. Next check-in: Monday." |
| Clean state | "Spotless." · "Nothing needs attention." |
| Threat found | "We found 2 items that shouldn't be here." · CTA "Remove Threats" |
| Permission | "To check everywhere, we need Full Disk Access. You can change this any time." |
| Destructive confirm | "Move 214 items (6.2 GB) to the Trash?" · "You can put them back from the Trash." |
| Error | "That didn't work. Some files are in use. Quit Safari and try again." |

### B.13 SwiftUI implementation notes (macOS 14 baseline, enhanced on 15 and 26)

**API availability checked this session** (VERIFIED, Apple docs JSON):

| macOS | APIs |
|---|---|
| **10.15** | `EnvironmentValues.controlActiveState` (macOS only), `accessibilityReduceMotion`, `colorSchemeContrast` **(added)** |
| **11** | `WindowStyle.hiddenTitleBar` |
| **12** | `Material` |
| **13** | `MenuBarExtra`, `MenuBarExtraStyle.window`, `contentTransition`, `numericText(countsDown:)`; **(added)** `windowResizability(_:)`, `defaultSize(width:height:)`, `MenuBarExtra.init(isInserted:content:label:)`, `toolbarBackground(_: Visibility, for:)` (Apple marks it deprecated at 27.2 in favour of `toolbarBackgroundVisibility`) |
| **14** | `containerBackground(_:for:)`, `layerEffect`, **`colorEffect(_:isEnabled:)`** **(added)**, `ShaderLibrary`, `keyframeAnimator`, `phaseAnimator`, `sensoryFeedback`, `symbolEffect` + `BounceSymbolEffect`, `visualEffect`, `scrollTransition`, `TextRenderer` (Apple lists macOS 14.0), `onContinuousHover(coordinateSpace:perform:)`, `contentTransition(.numericText(value:))` |
| **15** | `MeshGradient`, `ContainerBackgroundPlacement.window`, `toolbarBackgroundVisibility(_:for:)`, **`Color.mix(with:by:in:)`**, **`pointerStyle(_:)` + `PointerStyle.link`**, **`BreatheSymbolEffect`, `RotateSymbolEffect`, `WiggleSymbolEffect`** **(added)** |
| **26** | `glassEffect(_:in:)`, `Glass.tint(_:)`, `Glass.interactive(_:)`, `GlassEffectContainer`, `glassEffectTransition`, `PrimitiveButtonStyle.glass`, `backgroundExtensionEffect()` |

- Build with the macOS 26 SDK (Xcode 26) so the Liquid Glass symbols compile. Guard them with `if #available(macOS 26, *)`.
- **(corrected: now VERIFIED, was INFERRED)** `colorEffect(_:isEnabled:)` is macOS 14.0, the same as `layerEffect`.
- **(corrected: now VERIFIED, was INFERRED)** `Color.mix(with:by:in:)` is macOS 15.0. The real signature has a third parameter `in:` (a `Gradient.ColorSpace`, default `.perceptual`), so the `mix(with:by:)` calls below compile and mix in perceptual space.
- **(added) Haptics on the Mac.** `sensoryFeedback` *compiles* on macOS 14, but Apple's per-case docs say:
  - `.success`, `.warning`, `.error`, `.selection` and `.impact` only play on iOS and watchOS;
  - `.alignment` plays on iOS and macOS;
  - `.levelChange` plays only on macOS.

  So the only Mac haptics are alignment and level-change ticks on a Force Touch trackpad. AppKit's `NSHapticFeedbackManager` adds that the trackpad gives nothing when the user is not touching it, and that haptics should answer user-initiated actions. VERIFIED (Apple docs JSON for `SensoryFeedback/*` and `NSHapticFeedbackPerformer.perform(_:performanceTime:)`).

#### B.13.1 Tokens

```swift
import SwiftUI

enum DS {
    enum Space { static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12,
                 l: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24, x3: CGFloat = 32,
                 x4: CGFloat = 40, x5: CGFloat = 48, x6: CGFloat = 64 }
    enum Radius { static let xs: CGFloat = 6, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 18, xl: CGFloat = 26 }
    enum Dur { static let instant = 0.08, quick = 0.15, standard = 0.25, emphasized = 0.45,
               scene = 0.70, celebrate = 1.2 }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static let inkOnBright = Color(hex: 0x0B0B14)
}

extension Font {
    static let dsDisplay   = Font.system(size: 40, weight: .light)
    static let dsHeadline  = Font.system(size: 26, weight: .semibold)
    static let dsTitle     = Font.system(size: 20, weight: .semibold)
    static let dsMetricXL  = Font.system(size: 56, weight: .thin, design: .rounded).monospacedDigit()
    static let dsMetricL   = Font.system(size: 34, weight: .light, design: .rounded).monospacedDigit()
    static let dsMetricS   = Font.system(size: 22, weight: .regular, design: .rounded).monospacedDigit()
    static let dsBodyStrong = Font.system(size: 13, weight: .semibold)
    static let dsBody      = Font.system(size: 13)
    static let dsCallout   = Font.system(size: 12)
    static let dsCaption   = Font.system(size: 11).monospacedDigit()
    static let dsOverline  = Font.system(size: 10, weight: .semibold)   // + .textCase(.uppercase) + .tracking(0.8)
    static let dsMono      = Font.system(size: 11, design: .monospaced)
}

struct ModuleTheme: Equatable {
    let canvasTop, canvasBottom, accent, accentText, accent2, glow, orbFill: Color
}

enum Module: String, CaseIterable, Identifiable {
    case checkup, cleanup, protection, performance, applications, clutter, spaceMap, cloud, toolbox, activity
    var id: String { rawValue }

    var theme: ModuleTheme {
        switch self {
        case .checkup:      .init(canvasTop: .init(hex: 0x0E0B26), canvasBottom: .init(hex: 0x2A1F66), accent: .init(hex: 0x8C7BFF),
                                  accentText: .init(hex: 0xA99CFF), accent2: .init(hex: 0x45D9F5), glow: .init(hex: 0x6F5CFF), orbFill: .init(hex: 0x6556C2))
        case .cleanup:      .init(canvasTop: .init(hex: 0x051A17), canvasBottom: .init(hex: 0x0C4A3B), accent: .init(hex: 0x3BE8A9),
                                  accentText: .init(hex: 0x3BE8A9), accent2: .init(hex: 0xC2F261), glow: .init(hex: 0x1FCB8A), orbFill: .init(hex: 0x1D8464))
        case .protection:   .init(canvasTop: .init(hex: 0x1E0710), canvasBottom: .init(hex: 0x5A1428), accent: .init(hex: 0xFF6177),
                                  accentText: .init(hex: 0xFF8193), accent2: .init(hex: 0xFFB08A), glow: .init(hex: 0xF23D5C), orbFill: .init(hex: 0xBD4257))
        case .performance:  .init(canvasTop: .init(hex: 0x1F1003), canvasBottom: .init(hex: 0x5C2E06), accent: .init(hex: 0xFFAC33),
                                  accentText: .init(hex: 0xFFAC33), accent2: .init(hex: 0xFFE066), glow: .init(hex: 0xFF8A00), orbFill: .init(hex: 0xA5671A))
        case .applications: .init(canvasTop: .init(hex: 0x070F2B), canvasBottom: .init(hex: 0x15306E), accent: .init(hex: 0x5C88FF),
                                  accentText: .init(hex: 0x86A6FF), accent2: .init(hex: 0x7FE6FF), glow: .init(hex: 0x3D6BFF), orbFill: .init(hex: 0x4065C5))
        case .clutter:      .init(canvasTop: .init(hex: 0x03191F), canvasBottom: .init(hex: 0x0A4552), accent: .init(hex: 0x2ED6EE),
                                  accentText: .init(hex: 0x2ED6EE), accent2: .init(hex: 0x7CF5D4), glow: .init(hex: 0x00B8D9), orbFill: .init(hex: 0x187F90))
        case .spaceMap:     .init(canvasTop: .init(hex: 0x130A26), canvasBottom: .init(hex: 0x3B1F6E), accent: .init(hex: 0xB98CFF),
                                  accentText: .init(hex: 0xC9A6FF), accent2: .init(hex: 0xFF8AD8), glow: .init(hex: 0x9B5CFF), orbFill: .init(hex: 0x8760C5))
        case .cloud:        .init(canvasTop: .init(hex: 0x06142A), canvasBottom: .init(hex: 0x173E70), accent: .init(hex: 0x66BFFF),
                                  accentText: .init(hex: 0x66BFFF), accent2: .init(hex: 0xE4F3FF), glow: .init(hex: 0x3FA6FF), orbFill: .init(hex: 0x3B78B0))
        case .toolbox:      .init(canvasTop: .init(hex: 0x10121F), canvasBottom: .init(hex: 0x2C3152), accent: .init(hex: 0xA4ADE6),
                                  accentText: .init(hex: 0xA4ADE6), accent2: .init(hex: 0xE1E5FF), glow: .init(hex: 0x7F8BD6), orbFill: .init(hex: 0x6A719F))
        case .activity:     .init(canvasTop: .init(hex: 0x0D1A08), canvasBottom: .init(hex: 0x2E4A12), accent: .init(hex: 0xBEEB6B),
                                  accentText: .init(hex: 0xBEEB6B), accent2: .init(hex: 0x7EE0B0), glow: .init(hex: 0x9BD63A), orbFill: .init(hex: 0x5E7F2F))
        }
    }

    var railSymbol: String {
        switch self {
        case .checkup:      "sparkles"
        case .cleanup:      "bubbles.and.sparkles"
        case .protection:   "shield.lefthalf.filled"
        case .performance:  "bolt.fill"
        case .applications: "square.grid.2x2.fill"
        case .clutter:      "square.stack.3d.up.fill"
        case .spaceMap:     "circle.hexagongrid.fill"
        case .cloud:        "icloud.fill"
        case .toolbox:      "wrench.and.screwdriver.fill"
        case .activity:     "chart.line.uptrend.xyaxis"
        }
    }
}
```

#### B.13.2 Scene and window

```swift
@main
struct PrismApp: App {
    @State private var model = AppModel()          // @Observable (macOS 14)

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(model.appearance.colorScheme)   // .dark by default
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 740)

        MenuBarExtra(isInserted: $model.showsMonitor) {
            MonitorPanel().environment(model).frame(width: 360)
        } label: {
            Image(systemName: "waveform.path.ecg")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(model) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            CanvasStack(module: model.selected, intensity: model.canvasIntensity)
            HStack(spacing: 0) {
                Rail().frame(width: model.railCollapsed ? 76 : 232).padding(10)
                ModuleHost(module: model.selected)          // top bar + hero/tiles/lists + orb overlay
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

/// Cross-fades whole canvases between modules: reliable on every OS version,
/// no reliance on gradient-colour interpolation.
struct CanvasStack: View {
    let module: Module
    let intensity: Double
    var body: some View {
        ZStack {
            LivingCanvas(theme: module.theme, intensity: intensity)
                .id(module)
                .transition(.opacity)
        }
        .animation(.smooth(duration: DS.Dur.scene), value: module)
        .ignoresSafeArea()
    }
}
```

On macOS 15+ the canvas can instead be installed with `.containerBackground(for: .window) { CanvasStack(...) }` (placement `.window` is VERIFIED macOS 15). This makes the window itself own the background, and the system chrome composites over it.

#### B.13.3 Living canvas (MeshGradient on 15+, blooms on 14)

```swift
struct LivingCanvas: View {
    let theme: ModuleTheme
    var intensity: Double = 1                       // 1 idle · 1.35 scanning · 0.8 results
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState   // .key / .active / .inactive

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.canvasTop, theme.canvasBottom], startPoint: .top, endPoint: .bottom)
            if #available(macOS 15, *) {
                let paused = reduceMotion || activeState == .inactive
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: paused)) { tl in
                    let t = paused ? 0 : tl.date.timeIntervalSinceReferenceDate
                    MeshGradient(width: 3, height: 3,
                                 points: Self.points(t),
                                 colors: Self.colors(theme, k: intensity))
                }
            } else {
                BloomField(accent: theme.glow, animated: !reduceMotion)   // CA radial layers, render-server animated
            }
        }
        .colorEffect(ShaderLibrary.grain(.float(0.035)))   // banding killer; see B.13.4
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ phase: Double, _ amp: Double, period: Double = 24) -> Float {
            Float(sin(t / period * 2 * .pi + phase) * amp)
        }
        return [
            [0, 0],                     [0.5, 0],                                  [1, 0],
            [0, 0.5 + w(0, 0.06)],      [0.5 + w(1.3, 0.08), 0.55 + w(2.1, 0.07)], [1, 0.5 + w(3.4, 0.06)],
            [0, 1],                     [0.5 + w(4.2, 0.10, period: 30), 1],       [1, 1],
        ]
    }

    @available(macOS 15, *)
    static func colors(_ th: ModuleTheme, k: Double) -> [Color] {
        let mid  = th.canvasTop.mix(with: th.canvasBottom, by: 0.45)
        let mid2 = th.canvasTop.mix(with: th.canvasBottom, by: 0.55)
        return [
            th.canvasTop,    th.canvasTop,                                        th.canvasTop.mix(with: th.accent2, by: 0.14),
            mid,             mid.mix(with: th.accent, by: min(1, 0.30 * k)),      mid2,
            th.canvasBottom, th.canvasBottom.mix(with: th.glow, by: min(1, 0.55 * k)), th.canvasBottom,
        ]
    }
}
```

**macOS 14 fallback (`BloomField`).** Use three `CAGradientLayer(type: .radial)` blooms:
- each placed on an oversized square layer and spun about an off-centre anchor point, so the glow travels in a circle;
- driven by a `CABasicAnimation("transform.rotation.z")` with periods of about 20 s, 34 s and 14 s;
- plus a container opacity "breathe" between 1.0 and 0.86 over 8 s.

All of this runs on the render server, so the main thread does nothing per frame. The pattern is proven in an OSS clone (VERIFIED-OSS: VaderCleaner `BloomField.swift`, anchors at (0.5, 0.9), (−0.08, 0.3) and (1.08, 0.08); accent opacities 0.45, 0.26 and 0.20). Choose **our own** anchors and periods; the technique is generic.

#### B.13.4 Grain shader (Metal, macOS 14+)

```metal
// Grain.metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 grain(float2 position, half4 color, float strength) {
    float n = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    half g = half((n - 0.5) * strength);
    return half4(color.rgb + g * color.a, color.a);
}
```

- Apply it once, to the canvas only. Never apply it to text.
- Disable it when `accessibilityReduceTransparency` or Increase Contrast is on.

#### B.13.5 Particles (Canvas + TimelineView)

```swift
struct ScanDust: View {             // inward-drifting "collected dust" while scanning
    let color: Color
    var active: Bool
    @State private var seeds = (0..<48).map { _ in Mote.random() }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for m in seeds {
                    let life = (t * m.speed + m.phase).truncatingRemainder(dividingBy: 1)   // 0 → 1
                    let r = m.r0 + (m.r1 - m.r0) * life
                    let a = m.angle + life * m.swirl
                    let s = m.size * (1 - life * 0.6)
                    let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    ctx.opacity = sin(life * .pi) * m.alpha
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                             with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Mote {
    var angle, swirl, r0, r1, size, speed, phase, alpha: Double
    static func random() -> Mote {
        .init(angle: .random(in: 0..<(2 * .pi)), swirl: .random(in: 0.4...1.2),
              r0: .random(in: 150...230), r1: .random(in: 40...70), size: .random(in: 1.5...3.5),
              speed: .random(in: 0.12...0.30), phase: .random(in: 0...1), alpha: .random(in: 0.35...0.8))
    }
}
```

- **Completion burst:** the same structure, but one-shot. Store the start date, then for 0.9 s move 28–40 motes **outward** from the orb centre with gravity (y += 120·t²) and fade them out. Colour them `accent2` and white.
- **Seasonal "frost sparkle":** the same, with slow downward drift, at 12 fps. Off by default.

#### B.13.6 ActionOrb (sketch)

```swift
enum OrbState: Equatable {
    case idle(String)
    case busy(String, progress: Double?, detail: String?)
    case ready(String, detail: String?)
    case done(detail: String?)
    case disabled(String, detail: String?)
}

struct ActionOrb: View {
    let state: OrbState
    let theme: ModuleTheme
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let disc: CGFloat = 96

    var body: some View {
        Button(action: action) {
            ZStack {
                GlowDisc(color: theme.glow, diameter: disc * 1.5, breathing: isIdle && !reduceMotion)
                Circle().stroke(.white.opacity(hovering ? 0.22 : 0.14), lineWidth: 2)
                    .frame(width: disc + 16, height: disc + 16)
                ring
                Circle()
                    .fill(theme.orbFill)
                    .overlay(Circle().fill(Color(hex: 0x34D399).opacity(isDone ? 0.30 : 0)))
                    .overlay(alignment: .top) {                         // specular cap
                        Ellipse()
                            .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: disc * 0.70, height: disc * 0.42)
                            .offset(y: disc * 0.06)
                    }
                    .overlay(Circle().strokeBorder(isReady ? theme.accentText : .white.opacity(0.25),
                                                   lineWidth: isReady ? 2 : 1))
                    .frame(width: disc, height: disc)
                    .shadow(color: theme.glow.opacity(0.5), radius: 14, y: 6)
                    .opacity(isEnabled ? 1 : 0.35)
                labels
            }
            .frame(width: 200, height: 200)
            .contentShape(Circle().inset(by: 44))
        }
        .buttonStyle(OrbPressStyle(reduceMotion: reduceMotion))
        .scaleEffect(hovering && isEnabled && !reduceMotion ? 1.03 : 1)
        .animation(.easeOut(duration: DS.Dur.quick), value: hovering)
        .animation(.spring(duration: DS.Dur.emphasized, bounce: 0.18), value: state)
        .onHover { hovering = $0 }
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var ring: some View {
        switch state {
        case .busy(_, let p?, _):
            Circle().trim(from: 0, to: max(0.02, min(1, p)))
                .stroke(AngularGradient(colors: [theme.accent, theme.accent2], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: disc + 16, height: disc + 16)
                .animation(.linear(duration: 0.3), value: p)
        case .busy(_, nil, _):
            Circle().trim(from: 0, to: 0.25)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: disc + 16, height: disc + 16)
                .keyframeAnimator(initialValue: 0.0, repeating: true) { v, angle in
                    v.rotationEffect(.degrees(angle))           // restarts at 0° each loop: seamless (0° ≡ 360°)
                } keyframes: { _ in
                    KeyframeTrack { LinearKeyframe(360.0, duration: 1.2) }
                }
        case .ready:
            Circle().stroke(theme.accent.opacity(0.4), lineWidth: 2).frame(width: disc + 16, height: disc + 16)
        default:
            EmptyView()
        }
    }

    private var labels: some View {
        VStack(spacing: 2) {
            if isDone {
                Image(systemName: "checkmark").font(.system(size: 26, weight: .semibold))
                    .symbolEffect(.bounce, value: isDone)
            } else {
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            if let detail {
                Text(detail).font(.system(size: 11, weight: .medium).monospacedDigit())
                    .opacity(0.8).contentTransition(.numericText())
            }
        }
        .foregroundStyle(.white)
    }

    // helpers
    private var isIdle: Bool { if case .idle = state { true } else { false } }
    private var isDone: Bool { if case .done = state { true } else { false } }
    private var isReady: Bool { if case .ready = state { true } else { false } }
    private var isEnabled: Bool { if case .disabled = state { false } else { true } }
    private var title: String {
        switch state {
        case .idle(let s), .busy(let s, _, _), .ready(let s, _), .disabled(let s, _): s
        case .done: "Done"
        }
    }
    private var detail: String? {
        switch state {
        case .busy(_, _, let d), .ready(_, let d), .done(let d), .disabled(_, let d): d
        case .idle: nil
        }
    }
    private var accessibilityText: String { [title, detail].compactMap { $0 }.joined(separator: ", ") }
}

struct GlowDisc: View {
    let color: Color; let diameter: CGFloat; let breathing: Bool
    var body: some View {
        let base = Circle().fill(color).frame(width: diameter, height: diameter).blur(radius: 28)
        if breathing {
            base.phaseAnimator([0.40, 0.60]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 1.8) }
        } else {
            base.opacity(0.5)
        }
    }
}

struct OrbPressStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: DS.Dur.instant), value: configuration.isPressed)
    }
}
```

**Performance notes:**
- Animating the opacity of a blurred view reuses the cached blur. Animating `blur(radius:)` or `shadow(radius:)` re-rasterises every frame, so avoid that (VERIFIED-OSS: the VaderCleaner glow notes say the same).
- If Instruments shows the SwiftUI phase loop costing CPU while idle, move the breathe to a Core Animation opacity animation on a layer-backed host.

#### B.13.7 Optional "floating orb" (straddles the window's bottom edge)

A window clips its own content, so an overhanging orb needs a **borderless child `NSPanel`**. This is the same technique the evidence suggests for the vendor's overhanging chrome (§3.1; VERIFIED-OSS VaderCleaner `ScanDiscWindowController.swift`).

```swift
final class FloatingOrbPanel {
    private var panel: NSPanel?
    private var tokens: [NSObjectProtocol] = []

    func attach<V: View>(to window: NSWindow, railWidth: CGFloat, @ViewBuilder content: () -> V) {
        let p = NSPanel(contentRect: .init(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // (corrected) keep the parent's level: a floating panel would hover above other apps' windows
        // when ours is behind them (Apple: panels should float only if they also hide on deactivate).
        p.isFloatingPanel = false; p.level = window.level
        p.becomesKeyOnlyIfNeeded = true; p.hidesOnDeactivate = false
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.appearance = NSAppearance(named: .darkAqua)          // hosting view doesn't inherit appearance
        p.collectionBehavior = [.fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: content())
        window.addChildWindow(p, ordered: .above)
        panel = p
        let reposition = { [weak self, weak window] in
            guard let self, let window, let p = self.panel else { return }
            let f = window.frame
            let cx = f.minX + railWidth + (f.width - railWidth) / 2
            let inFullScreen = window.styleMask.contains(.fullScreen)
            let cy = inFullScreen ? f.minY + 76 : f.minY             // straddle the edge, or tuck inside in full screen
            p.setFrameOrigin(NSPoint(x: cx - 100, y: cy - 100))
        }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in reposition() })
        }
        reposition()
    }
}
```

Hide the panel during onboarding and sheets, because it sits above the main window. Clamp it to `screen.visibleFrame` so it never goes below the Dock.

**(corrected)** The first draft copied VaderCleaner's `isFloatingPanel = true` together with `hidesOnDeactivate = false`. Apple's `NSPanel.isFloatingPanel` docs say panels do not float by default, and that floating fits only small, mouse-oriented panels that **hide when the app deactivates**. A child window added with `addChildWindow(_:ordered: .above)` already stays directly in front of its parent and moves with it. So keep the parent's level and let the child relationship handle ordering. Verify on macOS 14 and 26 that the orb does not show over other apps when our window is behind them (INFERRED test).

#### B.13.8 Surfaces, glass, checkbox and parallax

```swift
extension View {
    /// Frosted content surface (tiles, list containers). Same look on 14/15/26.
    @ViewBuilder func prismSurface(radius: CGFloat = DS.Radius.l, reduceTransparency: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            self.background(shape.fill(Color(white: 0.16)))
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(shape.fill(.white.opacity(0.07)))
                .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        }
    }

    /// Navigation/control layer: Liquid Glass on Tahoe, frost before.
    @ViewBuilder func prismGlassControl(tint: Color) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

struct PrismCheckboxStyle: ToggleStyle {           // rounded square, tri-state via `mixed`
    var accent: Color
    var mixed = false
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn || mixed ? accent : .clear)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(configuration.isOn || mixed ? 0 : 0.4), lineWidth: 1.5)
                    if mixed {
                        Capsule().fill(Color.inkOnBright).frame(width: 8, height: 2)
                    } else if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.inkOnBright)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 36, height: 36)                  // hit area
                .contentShape(Rectangle())
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: DS.Dur.quick), value: configuration.isOn)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

struct ParallaxTilt: ViewModifier {                 // hero tilt ≤ 6°, window-relative
    @State private var tilt = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .rotation3DEffect(.degrees(-tilt.height * 6), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(tilt.width * 6), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard !reduceMotion else { return }
                    switch phase {
                    case .active(let p):
                        withAnimation(.spring(duration: 0.3)) {
                            tilt = CGSize(width: p.x / geo.size.width - 0.5, height: p.y / geo.size.height - 0.5)
                        }
                    case .ended:
                        withAnimation(.spring(duration: 0.5)) { tilt = .zero }
                    }
                }
        }
    }
}
```

Attach `ParallaxTilt` to the **hero container**, which fills the content area, not to the 300 pt lens. That way the tilt reacts anywhere over the content.

#### B.13.9 Numbers, haptics, sound

- **Sizes:** `Text(Int64(bytes), format: .byteCount(style: .file))` + `.contentTransition(.numericText())`. Change the value inside `withAnimation(.snappy)`.
- **Count-up:** drive a `@State var shown: Double` with a `keyframeAnimator` (macOS 14) or `withAnimation(.easeOut(duration: 0.9))`, and format each frame.
- **Haptics (corrected).** The first draft used `.sensoryFeedback(.success / .selection / .warning, …)`. Those cases **do not play on macOS** (Apple docs: "Only plays feedback on iOS and watchOS"). A Mac mini has no built-in trackpad, and a Magic Trackpad only gives feedback while it is being touched. So:
  - Drop completion, selection and warning haptics. Signal those with sound and visuals.
  - Optionally use `.sensoryFeedback(.alignment, trigger: snappedItem)` when a dragged item snaps into place. This plays on macOS.
  - Optionally use `.levelChange`, which plays only on macOS, for stepping through discrete levels, e.g. a size-threshold slider in Clutter.
  - AppKit equivalent: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)`. Use it only in response to the user's own action.
- **Sound** is played from the same trigger points (§B.11):

```swift
import AVFoundation
@MainActor final class SoundPlayer {
    static let shared = SoundPlayer()
    var enabled = true
    private var players: [String: AVAudioPlayer] = [:]
    func preload(_ names: [String]) {
        for n in names {
            if let url = Bundle.main.url(forResource: n, withExtension: "caf"),
               let p = try? AVAudioPlayer(contentsOf: url) { p.prepareToPlay(); players[n] = p }
        }
    }
    func play(_ name: String, volume: Float = 0.6) {
        guard enabled, NSApp.isActive, let p = players[name] else { return }
        players.values.forEach { $0.stop() }
        p.currentTime = 0; p.volume = volume; p.play()
    }
}
```

#### B.13.10 Transitions between module phases

- Key the phase view: `.id(phase)` inside a `ZStack`, with `.transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))` and `.animation(.snappy(duration: 0.25), value: phase)`.
- Use `matchedGeometryEffect(id: "hero", in: ns)` to move the lens between its intro, scanning and results positions.
- Tile stagger: `ForEach(Array(tiles.enumerated()), id: \.element.id) { i, tile in TileView(tile).transition(.opacity.combined(with: .offset(y: 16))).animation(.spring(duration: 0.45, bounce: 0.18).delay(Double(i) * 0.06), value: showTiles) }`.

### B.14 Accessibility spec

**Reduce Motion:**
- Static canvas, no parallax and no particles.
- Cross-fades replace slides and scales.
- Count-ups are replaced by the final value.
- The orb glow does not breathe.
- The progress ring still updates.

This mirrors the vendor's 5.0.7 behaviour (VERIFIED).

**Reduce Transparency:**
- Materials become opaque surfaces.
- No grain and no blurs.
- Glass becomes solid.
- Canvas gradients remain, because they are opaque.

**Increase Contrast** (`@Environment(\.colorSchemeContrast) == .increased`):
- Hairlines go to 30 %.
- `ink.secondary` goes to 88 %.
- Selected rows gain a 2 pt solid `accentText` border.
- Glows are disabled.

The vendor ships HCM variants of its sidebar icons (VERIFIED-OSS); we get the same effect from SF Symbols weight and contrast.

**VoiceOver:**
- Every tile is one accessibility element: "Cleanup, 6.2 gigabytes, caches, logs and 3 leftovers, selected, button Review".
- The orb announces its state and progress.
- The canvas, particles and lens art are `accessibilityHidden(true)`, except for one label per hero ("Cleanup illustration").
- Live progress uses `.accessibilityValue` and an `AccessibilityNotification.Announcement` when a scan completes.

**Keyboard:**
- Full Tab order: rail → top bar → content → orb.
- ⌘1–⌘9 select modules.
- Return activates the orb; Esc stops a scan or closes a sheet.
- ⌘F focuses search; Space toggles the focused checkbox; ⌘A selects all in a list.
- ⌥⌘I toggles the inspector; ⌘0 toggles the rail.

**Contrast:** every text token meets 4.5:1 on its intended background (computed in §B.3.2). **(corrected)** This holds only after raising `ink.tertiary` from 52 % to 66 %. Disabled text (`ink.disabled`, 32 %) is exempt under WCAG. Do not put text directly over the brightest mesh point; keep text above the hero or inside surfaces.

**Pointer:** custom controls use `.pointerStyle(.link)` (VERIFIED macOS 15.0; `PointerStyle.link` is macOS-only) or `.onHover { NSCursor.pointingHand.push()/pop() }` on macOS 14, only on link-like text buttons.

### B.15 Performance budget for the visual layer

| Item | Target on an Apple-silicon Mac mini |
|---|---|
| Idle main window, key, canvas animating | CPU < 3 % of one core for our process. The canvas runs at 24 fps via `TimelineView`, or on the render server (CA). |
| Main window not key / occluded | The canvas pauses (`controlActiveState`; observe `NSWindow.didChangeOcclusionStateNotification`) → ~0 % CPU |
| Scanning (visual layer only) | ≤ 30 fps particles (48 motes); status text ≤ 10 Hz; ring updates ≤ 10 Hz with interpolation |
| Monitor popover | No ambient animation. Values every 2 s. CPU < 1 % while open. |
| Memory | Procedural heroes, no large bitmaps: main app UI < 150 MB RSS |
| Measurement | Instruments: SwiftUI, Animation Hitches, Core Animation FPS. Frame budget 16.6 ms. |

### B.16 Screen blueprints (ours)

**Checkup: scanning**

```
‹ (no back)                    Checkup                                    🔔
                         ╭────────────╮
                         │  lens 220  │  ← three orbit rings spin, dust drifts inward
                         ╰────────────╯
              Peeking into caches…            (headline 26 semibold)
              ~/Library/Caches/com.apple.Safari   (mono 11, tertiary, ≤10 Hz)

     ✓ Cleanup        2.4 GB     │  ◌ Protection   checking…   │  ○ Performance  waiting
     ○ Applications   waiting    │  ○ Clutter      waiting
                                  ( Stop · 42% )   ← orb with determinate ring
```

**Checkup: results**

```
Start Over ‹                   Checkup                                    🔔
 [lens 150]  Here's the rundown.                                  (headline)
             6.2 GB to clean · 4 updates · no threats   (callout, secondary)
 ╭ CLEANUP ☑ ─────────╮ ╭ PROTECTION ☑ ──────╮ ╭ SUMMARY ─────────────╮
 │ 6.2 GB             │ │ All good ✓         │ │ 7.1 GB selected      │
 │ caches, logs, …    │ │ Monitoring is on   │ │ ~14 min saved        │
 │ (Review)           │ │                    │ │ Health: Good         │
 ╰────────────────────╯ ╰────────────────────╯ │                      │
 ╭ PERFORMANCE ☑ ─────╮ ╭ APPLICATIONS ☑ ────╮ │                      │
 │ 3 tasks            │ │ 4 updates          │ │                      │
 │ (Review)           │ │ (Review)           │ ╰──────────────────────╯
 ╰────────────────────╯ ╰────────────────────╯ ╭ CLUTTER ☐ ───────────╮
                                               │ 12 duplicates (dim)  │
                                               ╰──────────────────────╯
                               ( Run · 7.1 GB )
```

**Checkup: done.** The orb shows ✓ and the burst plays. The headline reads "Done. You freed 6.2 GB." Below it are four small stat chips (Cleaned · Threats · Tasks · Updated) and two links, "See what changed" and "Back to Checkup".

**Module intro → results → review** (Cleanup):
- **Intro:** the lens on the left (300), the display title + subtitle + 3 feature rows on the right (an original layout variant: centred on wide windows), and the orb "Scan".
- **Results:** a header with lens 150 + "6.2 GB ready to clean" (metricXL) + "of 7.9 GB found"; a grid of category cards (2–3 columns, each with checkbox, badge, size, one-line description); a collapsed "Needs review" card for risky groups; the orb "Clean · 6.2 GB".
- **Review:** the two-pane list (§B.8.7).

**Space Map:**
- a breadcrumb bar at the top (Macintosh HD › Users › me › Library);
- a circle-packing bubble map filling the content, with bubbles tinted from `accent` → `accent2` by depth and a hover card (name · size · items · modified);
- a left synchronized list (300) with checkboxes;
- a bottom bar with "3 selected · 14.2 GB" and the orb "Remove".

Interaction details are in 07-clutter.

### B.17 Design QA checklist (before each release)

1. Every module screen shows exactly **one** primary action (the orb, or one white capsule in sheets).
2. Canvas switches cross-fade in about 0.7 s with no flash of grey. The rail pill slides.
3. Text contrast is ≥ 4.5:1 everywhere; spot-check with the macOS Accessibility Inspector. No text sits on the brightest mesh area.
4. Reduce Motion, Reduce Transparency and Increase Contrast are each verified on every screen.
5. All numbers use monospaced digits, and none jitter while counting.
6. Hover states on rows, tiles, buttons and rail items are visible but subtle; press states are present.
7. Empty, clean, limited and error states exist for every module (§B.8.10).
8. The orb never overlaps content at the minimum window size (1040 × 680). The floating-orb option stays inside `visibleFrame`.
9. Idle CPU is within budget (§B.15) with the window key, and zero when occluded.
10. No MacPaw asset, glyph, string or sound is present. Run a text search for "Smart Care", "My Clutter", "Space Lens", "Moonlock" and "CleanMyMac" in the repo before shipping.

---

## 7. Gaps and uncertainties

Status after the fact-check pass is given in **bold** at the end of each item.

1. **5.x exact layout metrics are unknown:** sidebar width, row height, font sizes, tile radius, default window size. The 5.x evidence here comes from asset teardown (VERIFIED-OSS) and clones (CLONE-OBS). Primary screenshots (MacPaw product page, MacStories/9to5Mac reviews) could not be fetched. **Still open.** The only firm 5.x numbers are rendition sizes (600×400 hero, 200×200 badges, 24×24 sidebar glyphs, 32×32 intro chips) and minimum macOS 11.
2. **Live background colours (5.x):** the Metal shader colours, the motion parameters, and whether intensity reacts to scan state. **Still open.** New hints:
   - The 5.x brand spectrum (violet #9E00CE → magenta #AC097B → teal #178486 → green #397333 → blue #0078CE) is verified from the release-notes CSS (§4.3).
   - The two clones disagree on where the bright region sits (bottom vs top-right), which suggests a moving field.
3. **Liquid Glass on Tahoe:** whether CleanMyMac 5.6–5.7 adopted Liquid Glass chrome (sidebar, toolbar, buttons) on macOS 26. **Partly answered (INFERRED).** The app icon appears to be a layered, Icon-Composer-style icon (§4.8 D). The window chrome is still unverified.
4. **5.x sounds:** whether they exist, and whether there is a toggle. **Answered.** Yes: there is a `SoundsEnabled` preference (VERIFIED-OSS, §4.8 A). Which events play, and how they sound, is still unknown.
5. **5.x onboarding:** the screens around `IntroVideo.mp4` (number of steps, copy). 01-overview §9 has the same gap. **Still open.** Precedent: CMM3 also opened with `Intro.mp4` (VERIFIED-OSS file name), so a video-led welcome is a long-running MacPaw pattern.
6. **Rail collapse in 5.x:** whether the sidebar collapses to icons during results. **Still unverified.** Re-reading the clones shows both treat it as their own design choice (§4.2).
7. **5.x appearance:** whether light mode changes the canvas. **Partly answered.** A `CustomThemes` preference exists, but what it controls is unconfirmed. The in-app release-notes view forces light (`color-scheme: only light`). The main canvas is still believed to be always dark (CLONE-OBS + INFERRED).
8. **Completion celebration:** the exact 5.x choreography is unknown beyond the squeegee wipe sprite (VERIFIED-OSS). In X, the finished state hid the orb and showed past-tense summaries (VERIFIED-OSS). **Still open.** CMM3 played distinct "scan finished" and "clean finished" sounds, and 5.x has a sound switch, so an audio cue at completion is likely (INFERRED).
9. **Behance / Dribbble / Red Dot / iF pages:** read only through teammate summaries (VERIFIED-K). Colour names, process notes and credits beyond those summaries are unverified. **Still blocked.** A secondary summary (PureMac) corroborates the superellipse rationale and the "muted, not neon" palette (§4.8 F).
10. **X window size:** **Resolved (corrected).** Window-only captures are 1090×672 px, so the aspect ratio is 1.62. The ≈1025×632 figure was the same window downscaled in a composite capture (§3.1). Absolute points are still unknown.
11. **SF Symbols and APIs:** **Resolved.**
    - Every symbol name was checked against the SFSafeSymbols lists; `battery.100` was replaced by `battery.100percent`.
    - `.breathe`/`.rotate`/`.wiggle` = macOS 15, `colorEffect` = macOS 14, `Color.mix(with:by:in:)` = macOS 15 and `pointerStyle`/`.link` = macOS 15, all VERIFIED in Apple docs.
    - New finding: `sensoryFeedback(.success/.selection/.warning)` does not play on macOS (§B.13).

## 8. Follow-up fetch list (for a session with web access)

- https://www.behance.net/gallery/141590791/CleanMyMac-X-Product-Design — principles, grid, colour and motion notes
- https://www.red-dot.org/project/cleanmymac-x-55187 — jury statement
- https://macpaw.com/news/cleanmymac-if-design-award and https://macpaw.com/news/cleanmymac-received-ux-design-awards
- https://dribbble.com/MacPaw/projects/623137-CleanMyMac — shots of the X and 5 illustrations and motion
- https://macpaw.com/news/introducing-new-cleanmymac and https://macpaw.com/cleanmymac — 5.x screenshots (sidebar, tiles, button)
- https://www.macstories.net/reviews/macpaw-updates-cleanmymac-with-a-fresh-design-and-new-tools/ and https://9to5mac.com/2024/10/16/macpaw-releases-major-update-to-cleanmymac-with-fresh-design-and-new-features/ — screenshot descriptions
- https://9to5mac.com/2022/06/30/cleanmymac-x-new-menu-bar-app/ — X Menu visuals
- https://afb.org/aw/21/6/17076 — X accessibility walkthrough (UI labels)
- YouTube "CleanMyMac 5 review" videos — motion reference for the scan animation, completion and Tahoe chrome

## 9. Source index

**Primary (VERIFIED, read this session):**
- DevMate CMM5 notes (5.0.0–5.2.5): https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50205.0.2509241440/releasenotes.html
- DevMate CMM5 5.0.0: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50000.0.2410151250/releasenotes.html
- DevMate CMM X 4.10–4.12.2: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/41202.0.2212161413/releasenotes.html
- Apple SwiftUI docs, at `https://developer.apple.com/documentation/swiftui/<symbol>`:
  - `meshgradient`, `view/glasseffect(_:in:)`, `glasseffectcontainer`;
  - `view/backgroundextensioneffect()`, `primitivebuttonstyle/glass`;
  - `menubarextra`, `menubarextrastyle/window`;
  - `view/containerbackground(_:for:)`, `containerbackgroundplacement/window`;
  - `view/layereffect(_:maxsampleoffset:isenabled:)`, `shaderlibrary`;
  - `view/keyframeanimator(initialvalue:repeating:content:keyframes:)`, `view/phaseanimator(_:trigger:content:animation:)`;
  - `view/sensoryfeedback(_:trigger:)`, `view/symboleffect(_:options:value:)`, `view/visualeffect(_:)`;
  - `view/contenttransition(_:)`, `contenttransition/numerictext(countsdown:)`;
  - `view/scrolltransition(_:axis:transition:)`, `view/toolbarbackgroundvisibility(_:for:)`;
  - `material`, `windowstyle/hiddentitlebar`, `environmentvalues/accessibilityreducetransparency`, `textrenderer`.

**Third-party, inspected the shipped app (VERIFIED-OSS):**
- CleanMyMac 5.5.4 asset teardown: https://github.com/jayvicsanantonio/VaderCleaner/blob/main/docs/cleanmymac-3d-assets.md
- CleanMyMac X pixel-led replica: https://github.com/ddlmanus/MacOptimizer/tree/main/AppUninstaller. Files:
  - `CleanMyMacWindowMetrics.swift`, `Styles.swift`, `CleanMyMacSidebar.swift`;
  - `SmartCleanerReplicaView.swift`, `SystemJunkReplicaView.swift`, `CleanMyMacDetailsOverlay.swift`;
  - `ContentView.swift`, `CircularActionButton.swift`.
- CleanMyMac X screenshots (VERIFIED-PX measurements): https://github.com/ddlmanus/MacOptimizer (root `reference-*.png`)
- CMM3 bundle file listing (sound/asset names only): unofficial mirror at https://github.com/auspham/mac-essential/tree/master/CleanMyMac%203.app/Contents/Resources

**Clones / specs (CLONE-OBS):**
- https://github.com/jayvicsanantonio/VaderCleaner:
  - `VaderCleaner/SectionTheme.swift` (in `VaderCleanerCore`), `VaderTheme.swift`, `BloomField.swift`;
  - `FloatingScanButton.swift`, `ScanDiscWindowController.swift`, `NavigationRailView.swift`;
  - `ScanProgressIndicator.swift`, `SectionIntroView.swift`, `MenuBarContent.swift`;
  - `ContentView.swift`, `VaderCleanerApp.swift`, `docs/history/spec.md`, `docs/history/plan.md`.
- https://github.com/GuilhermeVozniak/app-cleaner/blob/main/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md
- Not relied on: https://github.com/MYLEKHATECH/Ccmacui/blob/main/src/imports/cleanmymac-design-guide.md is a generic Figma guide. Its palette is not CleanMyMac's.

**Teammate reports (VERIFIED-K citations inside):** `docs/research/01-overview.md`, `02-smart-care.md`, `07-clutter.md`, `08-menu-app.md`, `13-helpcenter.md`.

**Added in the fact-check pass:**
- DevMate appcasts (dated versions; `minimumSystemVersion`):
  - https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/updates.xml
  - https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac4/updates.xml
- DevMate CMM5 notes 5.2.6–5.3.1: https://s3-us-west-2.amazonaws.com/updateinfo.devmate.com/com.macpaw.CleanMyMac5/50301.0.2601271414/releasenotes.html
- CMM5 release-notes CSS (gradient version title, `color-scheme: only light`): the 50205 notes URL above.
- CMM3 bundle file list (sounds, `Intro.mp4`, "Ubiquitous" assets): https://raw.githubusercontent.com/auspham/mac-essential/master/CleanMyMac%203.app/Contents/_CodeSignature/CodeResources and the Menu helper's `CodeResources`.
- 5.x preference keys (`SoundsEnabled`, `CustomThemes`, etc.):
  - https://raw.githubusercontent.com/hollow/dotfiles/2a58069f82213680193d40d7609a406b167591c4/macos/defaults.sh
  - https://github.com/hosmelq/.config (`dotfiles/macos/app-settings.json`)
- MacPaw OSS:
  - https://raw.githubusercontent.com/MacPaw/CocoaSprings/main/README.md
  - https://raw.githubusercontent.com/MacPaw/Fixel/main/README.md
- Apple docs JSON (availability and "only plays feedback on …" notes), at `https://developer.apple.com/tutorials/data/documentation/<path>.json` for:
  - `swiftui/sensoryfeedback/{success,selection,warning,impact,alignment,levelchange}`;
  - `swiftui/view/coloreffect(_:isenabled:)`, `swiftui/color/mix(with:by:in:)`;
  - `swiftui/view/pointerstyle(_:)`, `swiftui/pointerstyle/link`;
  - `symbols/{breathe,rotate,wiggle,bounce}symboleffect`;
  - `swiftui/environmentvalues/controlactivestate`, `swiftui/view/toolbarbackground(_:for:)-7lv0f`;
  - `appkit/nspanel/isfloatingpanel`, `appkit/nswindow/addchildwindow(_:ordered:)`;
  - `appkit/nswindow/didchangeocclusionstatenotification`, `appkit/nshapticfeedbackperformer/perform(_:performancetime:)`.
- SF Symbols availability lists: https://github.com/SFSafeSymbols/SFSafeSymbols (`Sources/SFSafeSymbols/Symbols/SFSymbol+{1.0…7.0}.swift`).
- UI-sound defaults key: e.g. https://github.com/wincent/wincent (`aspects/defaults/index.ts`), https://github.com/keith/dotfiles (`osx/defaults.sh`).
- Secondary Behance summary: https://raw.githubusercontent.com/momenbasel/PureMac/main/docs/IMPROVEMENT-RESEARCH.md
- CMM-style spec, re-read for the canvas-glow conflict: https://raw.githubusercontent.com/GuilhermeVozniak/app-cleaner/main/docs/superpowers/specs/2026-10-02-cmm-style-ui-revamp-design.md

---

## Verification notes

**Scope and method.** This adversarial pass re-tested about 20 implementation-critical claims. WebSearch was exhausted for the whole run (shared budget). macpaw.com, cleanmymac.com, behance.net, red-dot.org, 9to5mac.com, macstories.net and every press or review site tried were refused by the egress proxy, both from `curl` and from WebFetch (DNS failure). Reachable sources: DevMate S3 (release notes **and appcasts**), Apple's documentation JSON, raw GitHub, and the GitHub code-search API. No archive or reader proxies were used.

**Confirmed (no change needed):**
1. 5.0.7 added VoiceOver and Reduce Motion; Reduce Motion "simplifies visual effects". Re-read in the DevMate notes.
2. 5.1.0 Space Lens: folders shown as bubbles from largest to smallest, with zoom (DevMate).
3. 4.11.0 Menu redesign with CPU / Memory / Storage / Battery / Protection, and 4.10.0 Assistant "in the app's upper-right corner" (DevMate).
4. The 5.5.4 teardown, re-read in full:
   - no USD/SceneKit content;
   - `CleanMyLiveBackground.framework` (Metal);
   - `CMM5UbiquitousButton_CMM5UbiquitousButton.bundle/default.metallib`;
   - `WiperFrame_1…6`, `Snowflakes1…3`, `EmitterMask`, `main.riv`, `IntroVideo.mp4`;
   - rendition sizes 600×400, 200×200, 24×24 and 32×32;
   - badge hexes (#5CD746→#155B29, #FD66ED→#B31C6E, #FCA106→#D34A25, #47B6F9→#055EC4) and brand ramp #FF91D7→#B70193;
   - HCM sidebar variants and health states.
5. X replica constants (MacOptimizer source re-downloaded):
   - `titlebarContentInset 23`, `bottomActionCenterInset 70`;
   - orb 108×96 / glow 108 blurred 17 / rings 82, 72 and 64 / 2.3 pt ring / shadow radius 9;
   - hover 1.025 + lift 3 pt over 0.14 s; press 0.94 + brightness 0.08 over 0.08 s;
   - sidebar rows 27 pt, 12.2 pt labels, 10 pt headers at 48 %, selected black 24 % r7, hover white 5.5 %, pressed opacity 0.72;
   - panel white 17 % → black 12 %, rim 0.8 pt at 7.5 %, r12;
   - breathing 1.025 over 0.65 s with ±2.5° rock;
   - details overlay 778×489, scrim 58 %, 0.995 scale over 0.16 s;
   - type sizes 35 / 25 / 37 ultraLight / 39 ultraLight;
   - Of the 22 X hexes spot-checked, 21 were found in the replica source (±2 RGB per channel), among them #9076A6, #BA6E91, #CB7874, #5CE0F7, #335C87, #49AA93, #C97B79 and #67ABC0. The 22nd, #3A4072, is a pixel measurement and was confirmed by re-sampling the screenshot.
6. X pixel colours re-sampled: Optimization top ≈#9C79CB→#9976C8, bottom-right #3A4072, left edge lighter, "View items" pill ≈#7BD5FC.
7. Apple API availability: MeshGradient 15, `glassEffect` 26, `ContainerBackgroundPlacement.window` 15, `toolbarBackgroundVisibility` 15, `layerEffect`/`ShaderLibrary` 14, `TextRenderer` 14 (as Apple lists it), `hiddenTitleBar` 11, `numericText(countsDown:)` 13.
8. Clone claims re-read: the VaderCleaner disc straddles the bottom edge "per screenshots" (plan, step 8); its rail pill radius is 18.

**Corrected in place (marked "(corrected)"):**
1. 5.0.7 date: **26 Mar 2025**, not Dec 2024.
2. 4.10.0 date: **21 Dec 2021**, not Mar 2022. 4.10.4 *updated* the Ukrainian theme and made it switchable rather than introducing it.
3. CMM3 shipped **five** sounds, not two, plus a sound toggle, `Intro.mp4` and "Ubiquitous" assets.
4. X window: window-only captures are **1090×672 px** (aspect 1.62). The ≈1025×632 figure was a scaled composite.
5. **Haptics:** `sensoryFeedback(.success/.selection/.warning)` does not play on macOS. The completion choreography and §B.13.9 now use sound and visuals, with an optional `.alignment`/`.levelChange` only.
6. **Floating orb panel:** `isFloatingPanel = true` with `hidesOnDeactivate = false` goes against Apple's guidance. Changed to the parent's level.
7. **Contrast:** `ink.tertiary` at 52 % failed 4.5:1 on 5 of 10 canvases and on cards. Raised to 66 %. The stated minimums were also corrected: white/bottom ≥ 9.9:1, onBright/accent ≥ 5.9:1.
8. **SF Symbols:** `battery.100` is deprecated on macOS 14, use `battery.100percent`. `chart.line.uptrend.xyaxis` is SF Symbols 3, not 4.
9. **5.x sounds:** changed from "undocumented" to "exist, with a `SoundsEnabled` toggle" (VERIFIED-OSS).
10. The "bottom-brighter canvas" is downgraded to a disputed clone observation, because the other clone reports a top-right glow.

**Upgraded from INFERRED to VERIFIED:** `colorEffect` (14), `Color.mix(with:by:in:)` (15), `pointerStyle`/`.link` (15), `.breathe`/`.rotate`/`.wiggle` (15), the Smart Insights version (5.2.6), and the UI-sound defaults key (VERIFIED-OSS).

**Added:**
- the 5.x brand spectrum from the release-notes CSS;
- 5.x preference keys;
- minimum macOS 11;
- the appcast timeline;
- MacPaw's CocoaSprings (window-follow springs; defaults ω 7.5, ζ 0.5);
- the Fixel typeface caveat;
- the layered-icon hint for Tahoe;
- X sidebar metric typography.

**Still uncertain (not re-verifiable from this sandbox):**
- Everything sourced only from macpaw.com, Behance, Red Dot, iF, MacStories and 9to5Mac (labelled VERIFIED-K, unchanged);
- 5.x layout metrics and default window size;
- 5.x canvas colours and motion, and whether it reacts to scan state;
- Liquid Glass usage in 5.6–5.7 window chrome;
- the onboarding steps and copy;
- whether the rail collapses;
- the completion choreography;
- what `CustomThemes` actually toggles;
- the iF award year;
- absolute X window points.

The best next step is unchanged: install the 5.7.x trial on the Mac mini, record the screens, and read `defaults read com.macpaw.CleanMyMac5` plus the group-container plist to settle the settings questions. Use these for structure only, never for copying assets or strings.
