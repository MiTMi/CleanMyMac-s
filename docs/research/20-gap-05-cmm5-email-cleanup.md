# 20-gap-05 — CleanMyMac 5.7 "Email Cleanup" (Gmail): vendor UX and how to build our version

Date: 2026-10-12. Scope: the Gmail cleanup tool MacPaw shipped in CleanMyMac **5.7.0** (2026-09-25), and a complete build spec for our own tool. It covers Google OAuth, the Gmail API, and List-Unsubscribe handling under RFC 2369 and RFC 8058. Our app is **Spruce** (see `Sources/Spruce*`). The tool's catalogue ID is `tools/email`, its SF Symbol is `envelope.badge`, and its Activity event is `emailAction` (all from `20-gap-04` §3/§4).

> **Read this first: limits of this session.**
> - `macpaw.com`, `developers.google.com` and `rfc-editor.org` would not resolve from this sandbox (WebFetch failed with `getaddrinfo ENOTFOUND`).
> - The shared WebSearch budget for this run was already used up.
> - The vendor facts below come from the sibling reports (`01-overview.md`, `13-helpcenter.md`, `20-gap-01`, `20-gap-04`). Their authors fetched `macpaw.com/how-to/organize-email-inbox` and `macpaw.com/cleanmymac/whats-new` earlier in this run.
> - Google API and RFC facts were checked by **GitHub code search** against copies of the primary texts:
>   - Google's machine-readable **Gmail v1 discovery document**, as vendored in `googleapis/google-api-nodejs-client` and `googleapis/google-api-python-client`;
>   - the **RFC 8058 and RFC 2369 texts**, mirrored in `jstedfast/MimeKit/rfc/`.
>
>   They were also checked against open-source Gmail cleaners that quote Google's docs.
> - Everything about the vendor's *screens* beyond the one-paragraph how-to summary is **INFERRED** and labelled that way.

**Labels used**

| Label | Meaning |
|---|---|
| **VERIFIED [vendor-via-01/13]** | MacPaw page fetched earlier in this run by a sibling report. URL cited. |
| **VERIFIED [discovery]** | Exact text in Google's Gmail v1 discovery document (`https://github.com/googleapis/google-api-nodejs-client/blob/main/discovery/gmail-v1.json`; canonical `https://gmail.googleapis.com/$discovery/rest?version=v1`). |
| **VERIFIED [RFC]** | Exact text in the RFC (`https://github.com/jstedfast/MimeKit/blob/master/rfc/rfc8058.txt`, `.../rfc2369.txt`; canonical `https://www.rfc-editor.org/rfc/rfc8058`, `/rfc2369`). |
| **VERIFIED-2ND** | A third-party repository quotes or relies on the Google doc. Repo cited. |
| **RECALLED** | Prior knowledge, not re-fetched this session. Re-check before relying on it. |
| **INFERRED** | Our reasoning or recommendation. |
| **GAP** | Unknown. Settle it on the Mac mini (see §9). |

---

## 0. TL;DR (the 15 facts that drive the build)

1. **Placement.** Sidebar **Tools** › **Email Cleanup**. It is **Gmail only** and new in **5.7.0** (2026-09-25). VERIFIED [vendor-via-01] https://macpaw.com/how-to/organize-email-inbox ; https://macpaw.com/cleanmymac/whats-new (01 §5.2, §6).
2. **What it finds.** Newsletters, promotions, spam, trash, old drafts, large attachments, plus a **top senders** view. VERIFIED [vendor-via-01/13] (same URLs). The *exact on-screen labels* are a **GAP**.
3. **Actions.** **Unsubscribe**, which can also **remove existing** mail from that sender; **Archive**; **Move to Trash**. Every action asks for confirmation. VERIFIED [vendor-via-01/13]. **Undo** and **sign-out** behaviour are a GAP.
4. **One scope does everything the vendor does.** `https://www.googleapis.com/auth/gmail.modify` covers search, metadata, archive, trash/untrash, draft delete, and sending a `mailto:` unsubscribe. Google describes it as "Read, compose, and send emails from your Gmail account". VERIFIED [discovery].
5. **Avoid `gmail.metadata`.** The `q` search parameter and `format=FULL/RAW` "cannot be used when accessing the api using the gmail.metadata scope". VERIFIED [discovery]. Real-world error: `403 Metadata scope does not support 'q' parameter`. VERIFIED-2ND (`Himalpok1/Personal-OS` ADR-053; `overfolder/overslash`).
6. **Never request `https://mail.google.com/`.** It is the only scope that allows permanent deletion: "Read, compose, send, and permanently delete all your email from Gmail". VERIFIED [discovery]. Our app moves mail to Trash only.
7. **All the read and modify scopes are Restricted.** `gmail.readonly`, `gmail.modify`, `gmail.metadata`, `gmail.compose`, `mail.google.com` and `gmail.settings.basic` are **Restricted**. A public app needs verification plus an annual **CASA** security assessment. VERIFIED-2ND (`postalsys/learn-emailengine-app` scopes doc; `nicksheaharty/synced-landing`). A personal build skips this through the **personal-use exemption (<100 users)**. VERIFIED-2ND (support.google.com/cloud/answer/13464323, quoted in `kenn-io/msgvault`, `busystack/busymax` and others).
8. **Testing mode lasts 7 days.** With External user type in **Testing**, refresh tokens expire **7 days** after consent. Switching to **In production** (unverified) removes that limit; the "Google hasn't verified this app" warning stays. VERIFIED-2ND (Google OAuth doc quoted verbatim in `samsorensen/tune-transfer`, `AndyForest/SoupNet`; `Mubder/kazma`).
9. **OAuth on macOS.** Use the system auth sheet `ASWebAuthenticationSession` with PKCE (S256). The redirect is the reversed client ID, `com.googleusercontent.apps.<id>:/oauthredirect`, on an **"iOS"-type** client, which needs no client secret. Fallback: a **Desktop**-type client with a loopback `http://127.0.0.1:<port>` redirect. That type *requires* its non-secret `client_secret` at the token endpoint even with PKCE. VERIFIED-2ND (`shimataro/keryx` docs; `polhem-dev/polhem-oauth2` ADR-006; `drusifer/happening` ARCH.md; `justlinuxnoob/hush` auth.rs).
10. **Metadata-only scanning.** Use `messages.list` (ID pages, `maxResults` ≤ **500**), then `messages.get?format=metadata&metadataHeaders=…`. The format returns "only email message ID, labels, and email headers"; `metadataHeaders` restricts it to the headers named. VERIFIED [discovery]. Message bodies are never downloaded.
11. **Bulk limits.** `messages.batchModify` takes up to **1000 IDs** per request. VERIFIED [discovery]: "There is a limit of 1000 ids per request." `messages.list` skips SPAM and TRASH unless `includeSpamTrash=true`. VERIFIED [discovery].
12. **Classic quota.** List 5 units, get 5, batchModify 50, send 100. Per-user ceiling: 250 units/s (= 15,000/min); per project: 1,200,000/min. VERIFIED-2ND (several repos). **But** a 2026 project reports Google's current page lists `messages.get` = **20** units and a per-user ceiling of **6,000/min**. VERIFIED-2ND (`justlinuxnoob/hush` NOTES.md). → Make costs configurable and use an **adaptive limiter** (§6.9).
13. **One-click unsubscribe (RFC 8058)** is an HTTPS **POST** of the body `List-Unsubscribe=One-Click` to the HTTPS URI in `List-Unsubscribe`. Rules:
    - The POST MUST NOT include cookies or HTTP authorization.
    - The sender MUST NOT redirect.
    - The message MUST carry a valid DKIM signature that covers both headers.
    - The body SHOULD be `multipart/form-data` and MAY be `application/x-www-form-urlencoded`.

    VERIFIED [RFC].
14. **RFC 2369 URI order.** List-Unsubscribe URIs are in "order of preference from left to right". Clients use the "left most protocol that it supports" and fall back only if it fails. VERIFIED [RFC].
15. **Undo path.** A trashed message can be recovered: `messages.untrash`, or remove the `TRASH` label. Gmail empties Trash after 30 days (RECALLED). `drafts.delete` "Immediately and permanently deletes the specified draft. Does not simply trash it." VERIFIED [discovery]. So we trash draft *messages* instead of calling `drafts.delete` (§6.7).

---

## 1. Vendor product facts (what MacPaw shipped)

### 1.1 Release, placement, availability

| Claim | Evidence | Status |
|---|---|---|
| Email Cleanup first shipped in **5.7.0**, 2026-09-25 (Homebrew cask date). 5.7.1 (2026-10-01) is a fix release. | 01 §6 table | VERIFIED [vendor-via-01] (Homebrew) |
| Entry point: "go to **Tools** in the sidebar, choose **Email Cleanup**". | https://macpaw.com/how-to/organize-email-inbox (01 §5.1, 13 §3.48) | VERIFIED [vendor-via-01/13] |
| It is one of the vendor's named example tools in the **My Tools** hub (with Uninstaller, Duplicate Finder, Space Lens, Login Items, Downloads, App Updater, Application Permissions). | https://macpaw.com/news/my-tools-cleanmymac via 01 §5.2 | VERIFIED [vendor-via-01] |
| The help center's "Concepts and usage" lists an **"Email cleanup"** section beside Cloud Cleanup and Space Lens. | https://macpaw.com/support/cleanmymac/knowledgebase/concepts-and-usage (01 §5.1) | VERIFIED [vendor-via-01] |
| The sidebar label may read **"Tools"** rather than "My Tools". | gap-01 §4.1 | VERIFIED row exists; label GAP |
| **Gmail only.** No Outlook, iCloud Mail or IMAP. | How-to and What's New describe Gmail sign-in only | VERIFIED [vendor-via-01] (absence of other providers: INFERRED) |
| Plan tier (Basic vs Plus) and presence in the Mac App Store edition. | Not found. Cloud Cleanup is Plus-only (01 §5.2), so Email Cleanup is plausibly Plus as well. | **GAP** / INFERRED |
| Multiple Gmail accounts at once. | Not found | **GAP** |
| Works on 5.7's supported macOS range (Sonoma 14 → Tahoe 26, and macOS 27 support in 5.7.1). | 01 §6 | VERIFIED range; the tool has no extra OS requirement (INFERRED: it only needs network) |
| Needs no Full Disk Access or other TCC permission. | It talks to Gmail over HTTPS | INFERRED |

### 1.2 Sign-in flow

| Claim | Status |
|---|---|
| The user signs in to Gmail with Google OAuth. | VERIFIED [vendor-via-01] (01 §5.2: "Gmail sign-in (Google OAuth)") |
| The closest vendor precedent is Cloud Cleanup's Google Drive "connect", done through browser OAuth. | VERIFIED [vendor-via-01] (01 §5.2, Cloud Cleanup row) |
| Likely sequence: an intro screen with a "sign in / connect" button → Google's consent page in a browser or the system auth sheet → back in the app, the signed-in address appears → scan. | INFERRED |
| MacPaw ships a verified, CASA-assessed OAuth client. Users see a normal consent screen ("CleanMyMac wants to access your Google Account"), not the unverified-app warning. | INFERRED. Google requires this for any public app that uses Restricted Gmail scopes (§6.2). |
| Which scopes MacPaw requests. | **GAP**. Archive and trash need `gmail.modify` (or broader), so the vendor client most likely requests **`gmail.modify`** (INFERRED). Check on the device: the consent screen lists the scopes, and so does `myaccount.google.com/connections` afterwards. |

### 1.3 Scan and results

| Claim | Status |
|---|---|
| The scan groups mail into **newsletters, promotions, spam, trash, old drafts, large attachments**, plus **top senders**. | VERIFIED [vendor-via-01] (01 §5.2). 13 §3.48 lists "newsletters, promotions, spam, old drafts and large attachments"; the What's New line names "newsletters, promotions, spam, old drafts … top senders". |
| Exact category titles, order, icons, and which categories show counts versus sizes. | **GAP** |
| Per-sender rows with message counts (needed for "top senders" and per-sender unsubscribe). | INFERRED from "top senders" plus "Unsubscribe" |
| Whether categories are mutually exclusive. A promotional newsletter qualifies as both. | **GAP**. Our rule is in §3.3. |
| Scan scope: whole mailbox or a recent window; progress UI. | **GAP** |

### 1.4 Actions, confirmations, undo, sign-out

| Claim | Status |
|---|---|
| **Unsubscribe**, optionally **plus removing existing mail** from that sender. | VERIFIED [vendor-via-01] (01 §5.2: "Unsubscribe (optionally + remove existing)") |
| **Archive** and **Move to Trash**. | VERIFIED [vendor-via-01/13] |
| **Every action is confirmed.** | VERIFIED [vendor-via-01/13] (13 §3.48 "each confirmed"; 13 summary "every action is confirmed") |
| Undo inside the app. | **GAP**. Gmail's own Trash allows recovery for 30 days (RECALLED). Unsubscribing cannot be undone. |
| Sign-out / disconnect control and where it lives (tool header, Settings). | **GAP** |
| Whether the vendor ever deletes permanently. | **GAP**. The vendor's named actions stop at Trash, which suggests it does not request `https://mail.google.com/` (INFERRED). |

### 1.5 Privacy

| Question | Status |
|---|---|
| Is processing done on the device? | **GAP**. The app can call Gmail directly from the Mac, which would keep message metadata off MacPaw's servers (INFERRED, likely). The shipped privacy policy text was not reachable. |
| What is sent to MacPaw? | **GAP**. Expect at least product analytics events (feature opened, counts), as elsewhere in CleanMyMac (12 notes an analytics toggle exists; GUI location unknown). |
| Google "Limited Use" disclosure. | INFERRED. Any verified app that uses Restricted Gmail scopes must state that its use of Google user data follows the Google API Services User Data Policy, including the Limited Use requirements (RECALLED policy). Look for this sentence in MacPaw's privacy policy or on the tool's intro screen. |

### 1.6 Context: comparable products (for UX calibration)

- **Gmail's own "Manage subscriptions"** (2025). A left-nav view listing frequent bulk senders with message counts and an **Unsubscribe** button per row. It relies on the sender's List-Unsubscribe header. VERIFIED-2ND (`neilbhammar/mailmop` blog posts dated 2025-09-21 and 2026-09-02; TLDR Marketing 2025-07-17 headline). This is the baseline users will compare us against. Our extra value: categories, sizes, bulk Archive/Trash of existing mail, and the large-attachment and old-draft finders.
- **Hush** (open-source Tauri desktop app). One-click RFC 8058 only. It **blocks `mailto:`**, because sending as the user would widen its read-only permission, and it **blocks plain links**, because their effect cannot be known. It claims about **93%** of senders support one-click and about **6%** are mailto-only. It uses separate opt-in scopes: readonly by default, modify for trashing, settings.basic for blocking filters. VERIFIED-2ND (`justlinuxnoob/hush` README.md, auth.rs).
- **gclean.** Protects STARRED and IMPORTANT mail. Exact-matches the From address after a quoted `from:` search. Has a typed-confirmation flow and `undo`. VERIFIED-2ND (`jellydn/gclean` protector.go, sender_trash.go, docs/desktop.md).
- **inbox-zero.** Requests `gmail.modify` plus `gmail.settings.basic`. VERIFIED-2ND (`elie222/inbox-zero` apps/web/utils/gmail/scopes.ts).

---

## 2. Our UX spec — screens and states (all INFERRED unless cited)

Display name: **Email Cleanup**, a generic descriptive name used in `20-gap-04` row 26. If we want more distance from the vendor wording, the alternative is "Inbox Cleanup". All UI strings below are our own.

### 2.1 State machine

```
            ┌──────────────┐  no client ID configured
            │ notConfigured│──────────────► Setup guide (§7.4)
            └──────┬───────┘
                   │ client ID present
            ┌──────▼───────┐  "Connect Gmail…"   ┌────────────┐
            │  signedOut   │────────────────────►│ authorizing│──cancel──► signedOut
            └──────▲───────┘                     └─────┬──────┘
                   │ disconnect / invalid_grant        │ tokens + granted scopes
            ┌──────┴───────┐                     ┌─────▼──────┐
            │ needsReauth  │◄──refresh fails─────│   ready    │ (shows account, last scan)
            └──────────────┘                     └─────┬──────┘
                                                       │ "Scan"
                                                 ┌─────▼──────┐  cancel → ready (partial results kept)
                                                 │  scanning  │  phases: counts → ids → headers → grouping
                                                 └─────┬──────┘
                                                 ┌─────▼──────┐
                                                 │  results   │◄───────────┐
                                                 └─────┬──────┘            │ refresh counts
                                                       │ action confirmed  │
                                                 ┌─────▼──────┐            │
                                                 │   acting   │────────────┤ (progress per sender)
                                                 └─────┬──────┘            │
                                                 ┌─────▼──────┐            │
                                                 │ actionDone │──"Done"────┘  (summary + Undo)
                                                 └────────────┘
Overlay states: offline, rateLimited(retryAt), insufficientScope(missing), workspaceBlocked
```

### 2.2 Intro (signedOut)

- Header: the `envelope.badge` icon, the title **Email Cleanup**, and the subtitle "Find newsletters, promotions and big emails in Gmail, and clear them in bulk."
- Three bullet tiles: "Unsubscribe in one click" · "Archive or trash in bulk" · "Find large attachments and old drafts".
- Primary button **Connect Gmail…**. Secondary link "How your data is handled", which opens the §2.8 sheet.
- Footnote: "Spruce reads email headers only, never message bodies, and never sends your data anywhere." This must be literally true (§6.4).
- In `notConfigured`, the button reads **Set Up Google Access…** and opens the §7.4 guide.

### 2.3 Ready (connected, not yet scanned or stale)

- Account chip: avatar monogram, the address from `users.getProfile`, and a ⋯ menu with **Rescan**, **Disconnect…** and **Open Gmail**.
- Instant tiles from `labels.get` (1 unit each): Promotions · Spam · Trash · Drafts, showing `messagesTotal` and unread counts. (`messagesTotal` = "The total number of messages with the label." VERIFIED [discovery].)
- Scope selector: **Last 12 months** (default) · Last 3 years · Entire mailbox. Below it, a cost hint: "about N minutes for M emails" (§6.9).
- Primary button **Scan**.

### 2.4 Scanning

A progress ring and a phase label: "Counting emails…" → "Reading senders… 4,210 of 18,000" → "Grouping…".
- Use **real counts**. Count IDs first, then read metadata. Gmail's `resultSizeEstimate` is unreliable. VERIFIED-2ND (`justlinuxnoob/hush` model.rs: "has been seen reporting thousands for a handful of matches").
- **Stop** keeps the partial results and marks them "Partial scan".
- Categories fill in live as their queries finish, so the user can start reviewing early. This mirrors the vendor's background-scan pattern in Applications 5.5.5 (01 §6).

### 2.5 Results

Two panes, following our module layout (09 / gap-02 patterns):

- **Left list (categories)**, each row showing count and size:
  1. **Newsletters** — "Mailing lists you're subscribed to"
  2. **Promotions** — "Deals and marketing (Gmail's Promotions tab)"
  3. **Top Senders** — "Who fills your inbox the most"
  4. **Large Attachments** — "Emails over 10 MB"
  5. **Old Drafts** — "Drafts untouched for 6+ months"
  6. **Spam** — "Already in Gmail's Spam folder"
  7. **Trash** — "Already in Trash (deleted by Gmail after 30 days)"
- **Right pane:**
  - Sender-grouped categories (1–3): a sortable table.
  - Message-grouped categories (4–6): a message table.
  - Trash (7): an information card.
- **Bottom bar:** the selection summary ("12 senders · 3,402 emails · 1.2 GB") and the action buttons for the current category (§2.6). Buttons are disabled when nothing is selected.

### 2.6 Rows and actions per category

| Category | Row content | Sort options | Actions (bottom bar) | Pre-selected |
|---|---|---|---|---|
| Newsletters | Monogram; display name; address (dim); **count**; **% unread** (unread/count); last received; method badge (**One-click** · **Email** · **Web page** · **None**) | Count ↓ (default), % unread, Last received, Name | **Unsubscribe…** (dialog offers "also archive/trash existing"), **Archive**, **Move to Trash** | **None** |
| Promotions | Same, grouped by sender | Count ↓ | **Archive**, **Move to Trash**, **Unsubscribe…** (when a method exists) | None |
| Top Senders | Same, top 100 by count across the scan scope, excluding the user's own address | Count ↓ | **Unsubscribe…**, **Archive**, **Move to Trash**, optional **Block…** (§6.8) | None |
| Large Attachments | Subject (in memory only), sender, date, **size** | Size ↓ | **Move to Trash**, **Open in Gmail** | None |
| Old Drafts | Subject, last edited (`internalDate`), recipient(s) | Oldest first | **Move to Trash** | None |
| Spam | Sender, subject, date | Date ↓ | **Move to Trash** (empties the folder sooner), **Not Spam** (moves back to Inbox) | None |
| Trash | Count and size; text: "Gmail permanently deletes items in Trash after 30 days." | — | **Open Trash in Gmail** (`https://mail.google.com/mail/u/0/#trash`). No permanent delete (§6.2). | — |

Why nothing is pre-selected (INFERRED): everything here is user data. The vendor never pre-selects personal-file tools: "Large & Old Files, Uninstaller and Extensions never pre-select anything" (13 §1, item 4). We follow the same policy.

The row ⋯ menu offers: "Show recent emails" (opens a popover with the 5 newest subjects, kept in memory only), "Open in Gmail" (search `from:<addr>`), "Copy address", and "Never show this sender" (a local ignore list).

### 2.7 Confirmation dialogs (our copy) and undo

Each is a sheet with a summary, the consequence, and an explicit destructive button. These are original strings.

- **Unsubscribe…**
  - Title: "Unsubscribe from 12 senders?"
  - Body: "9 support instant unsubscribe. 2 will receive an unsubscribe email sent from your address. 1 needs you to finish on its website. Senders may take up to 2 days to stop."
  - Options (radio): "Keep existing emails" · "Archive existing emails (3,402)" · "Move existing emails to Trash (3,402)".
  - Checkbox, default on: "Skip starred emails".
  - Buttons: **Cancel** / **Unsubscribe**.
  - The "2 days" figure matches the bulk-sender rule: honour unsubscribes within 2 days. VERIFIED-2ND (`peterbamuhigire/social-media-skills` deliverability table citing Gmail and Yahoo sender requirements).
- **Archive**: "Archive 3,402 emails from 8 senders? They leave your Inbox but stay in All Mail and search." → **Archive**.
- **Move to Trash**: "Move 3,402 emails (1.2 GB) to Trash? Gmail deletes Trash permanently after 30 days. You can undo this from Activity until then." → **Move to Trash** (destructive style).
- **Result sheet (actionDone)**:
  - Per-sender outcomes: ✓ Unsubscribed · ✉︎ Email sent · ↗ Finish on website (button) · ⚠ Failed (reason).
  - Totals, then **Undo** (archive/trash only) and **Done**.
  - Unsubscribing is shown as not undoable.
- **Undo** replays the journal (§6.10):
  - Trashed messages: `messages.untrash`, or `batchModify` removing `TRASH` and restoring `INBOX` where it was present before.
  - Archived messages: `batchModify` adding `INBOX` back.
  - Undo is available from the result sheet and from **Activity** for 30 days, after which Gmail purges Trash (RECALLED).

### 2.8 Privacy sheet ("How your data is handled")

Our statement. Each line must be true of the code.

1. "Spruce connects to Gmail directly from this Mac. There is no Spruce server."
2. "It reads message headers only: sender, subject, date, size, labels and unsubscribe headers. It never downloads message bodies or attachments."
3. "Results are kept on this Mac and deleted when you disconnect. Subjects are never written to disk."
4. "Unsubscribe requests go straight to each sender's published unsubscribe address. Spruce sends no cookies or account details with them."
5. "Your Google sign-in is stored in your Mac's Keychain. You can disconnect here, or remove access at any time in your Google Account › Security › Third-party connections."
6. "Spruce can't permanently delete email. Everything it removes goes to Gmail's Trash first."

### 2.9 Disconnect

The ⋯ menu offers **Disconnect…**. The confirm sheet reads: "Disconnect your Gmail account? Spruce will revoke its access and delete local scan results." On confirm:

1. `POST https://oauth2.googleapis.com/revoke` with `token=<refresh_token>`. RECALLED endpoint.
2. Delete the Keychain items.
3. Delete the cache DB and action journal, after asking whether to keep pending undo records. Default: delete.
4. Return to `signedOut`.

If the revoke call fails (offline), delete locally anyway and tell the user how to remove access in their Google Account.

### 2.10 Error overlays

| Condition | Detection | UI |
|---|---|---|
| Token expired or revoked | Refresh returns `invalid_grant` | "Your Gmail connection expired. Reconnect…" (expected weekly in Testing mode; §7.2) |
| Scope unticked at consent | The token response `scope` lacks `gmail.modify` | "Spruce needs permission to organize your email to archive or trash. Reconnect and keep 'Read, compose…' ticked." Scanning stays possible if readonly was granted. |
| Rate limited | 429, or 403 with reason `rateLimitExceeded`/`userRateLimitExceeded` | Inline "Gmail asked us to slow down — resuming in 20 s" |
| Workspace admin block | `admin_policy_enforced` at consent | "Your organization doesn't allow this app." |
| Offline | `NSURLErrorNotConnectedToInternet` | Banner. Cached results stay readable but actions are disabled. |

---

## 3. Category definitions (how each group is computed)

### 3.1 Gmail system labels we rely on

From Google's labels guide, as copied verbatim in `i-am-alice/4th-devs` docs/reference.md and `benhyh/flow` (VERIFIED-2ND):
- `INBOX` and `SPAM` can be applied by hand.
- `SENT` (no) is "Applied automatically to messages that are sent with drafts.send or messages.send…".
- `DRAFT` (no) is "Automatically applied to all draft messages created with the Gmail API or Gmail interface."
- `CATEGORY_PERSONAL`, `CATEGORY_SOCIAL`, `CATEGORY_PROMOTIONS`, `CATEGORY_UPDATES` and `CATEGORY_FORUMS` (yes) each "Corresponds to messages that are displayed in the [X] tab of the Gmail interface."
- The guide also lists `TRASH`, `UNREAD`, `STARRED` and `IMPORTANT` as manually applicable. RECALLED. The snippet seen stopped after SPAM.

### 3.2 Queries and rules (INFERRED design; operators RECALLED from Gmail search syntax)

`q` "Supports the same query format as the Gmail search box." VERIFIED [discovery].

Let `W` be the scope window: `newer_than:1y` for "Last 12 months", `newer_than:3y` for "Last 3 years", empty for the entire mailbox. Always append `-in:chats`.

| Category | ID enumeration (`messages.list`) | Per-message rule after metadata | Grouping |
|---|---|---|---|
| **Newsletters** | `q = W` (all mail in the window; needed because newsletters also land in Primary) | Score ≥ 3 under §3.4 | By sender |
| **Promotions** | `labelIds=CATEGORY_PROMOTIONS`, `q = W` | Label present | By sender |
| **Top Senders** | Same message set as Newsletters | Exclude `SENT`, `DRAFT`, and From = own address | By sender, top 100 by count |
| **Large Attachments** | `q = "has:attachment larger:10M " + W` (threshold 5/10/25 MB in Settings) | `sizeEstimate` ≥ threshold. (`sizeEstimate` = "Estimated size in bytes of the message." VERIFIED [discovery].) | Per message, size ↓ |
| **Old Drafts** | `labelIds=DRAFT`, `q = "older_than:6m"` (3/6/12 months in Settings) | `internalDate` older than the threshold | Per message |
| **Spam** | `labelIds=SPAM`, `includeSpamTrash=true` | — | Per message |
| **Trash** | `labelIds=TRASH`, `includeSpamTrash=true` (count via `labels.get TRASH` is enough) | — | Count and size only |

Notes:
- **Messages, not conversations.** The API counts messages and Gmail's UI shows conversations, so our numbers will be higher than the counts Gmail shows. Label the columns "emails" and explain this in a tooltip. INFERRED.
- **Large Attachments: the whole message is the unit.** The Gmail API cannot strip an attachment from a stored message; only labels change after delivery. RECALLED. So the action is "Move to Trash" for the whole message.

### 3.3 Overlap rules

- **Newsletters** and **Promotions** may share senders. Each list shows its own view, and selection state is **per sender** across lists (selecting a sender in one list ticks it in the other).
- **Top Senders** is a superset view. It shows a small "Newsletter"/"Promo" tag on matching rows.
- Spam and Trash are excluded from every other category.
- Sizes in the bottom bar are de-duplicated by message ID.

### 3.4 "Newsletter" classifier (scoring; INFERRED weights; signals VERIFIED-2ND in `jellydn/gclean` classifier.go)

gclean's layered signals are: header signals (List-Unsubscribe, List-ID, Precedence: bulk|list|junk, Auto-Submitted), then Gmail categories.

| Signal | Points |
|---|---|
| `List-Unsubscribe` present | +3 |
| `List-Unsubscribe-Post: List-Unsubscribe=One-Click` | +1 |
| `List-Id` present | +2 |
| `Precedence: bulk` or `list` | +2 |
| `CATEGORY_PROMOTIONS` / `CATEGORY_UPDATES` / `CATEGORY_FORUMS` | +1 |
| Same sender sent ≥ 4 messages in the window | +1 |
| `Auto-Submitted: auto-generated` / `auto-replied`, *without* List-Unsubscribe (receipts, alerts, 2FA codes) | −2 |
| Sender in the user's ignore list | excluded |

Threshold ≥ 3. In effect, anything with List-Unsubscribe qualifies, and a bare List-Id list needs one more signal.

**Transactional guard.** Senders whose last 5 subjects match `/(receipt|order|invoice|verification|security alert|password|code)/i` get a "Transactional?" warning chip. Unsubscribing them is allowed but warned. INFERRED.

### 3.5 Sender identity and normalization

- Parse `From` with an RFC 5322 address parser. Decode RFC 2047 encoded-words (`=?UTF-8?B?…?=`) in display names. Lower-case the address.
- Group key = the full address. Group by `List-Id` instead when present and stable: one ESP address can serve many lists, and one list can rotate sending addresses. INFERRED.
- Never trust the display name alone. Show the address under it, because display-name spoofing is common.
- **Exact match before acting.** Gmail's `from:` search also matches display names and substrings. Before acting on "all mail from X", run a quoted `from:"x@y.com"` search, then exact-match the parsed From address of every result. VERIFIED-2ND (`jellydn/gclean` sender_trash.go: "Lists Gmail with a quoted from: query, then exact-matches the normalized From address").

---

## 4. Unsubscribe engine (RFC 2369 + RFC 8058)

### 4.1 Header facts

- **RFC 2369 §3.2 (List-Unsubscribe).**
  - A comma-separated list of angle-bracketed URIs, "order of preference from left to right".
  - The client "should use the left most protocol that it supports", and uses another URL "only if the first one used failed".
  - VERIFIED [RFC] (MimeKit mirror; tex2e/rfc-translater rfc2369.html).
- **RFC 8058 §3.1 (sender requirements).**
  - List-Unsubscribe "MUST contain one HTTPS URI. It MAY contain other non-HTTP/S URIs such as MAILTO:".
  - List-Unsubscribe-Post "MUST contain the single key/value pair 'List-Unsubscribe=One-Click'".
  - "the message MUST have a valid DomainKeys Identified Mail (DKIM) signature that covers at least the List-Unsubscribe and List-Unsubscribe-Post headers."
  - "The mail sender MUST NOT return an HTTPS redirect".
  - VERIFIED [RFC].
- **RFC 8058 §3.2 (receiver).**
  - The POST content "SHOULD be sent as 'multipart/form-data' [RFC7578] or MAY be sent as 'application/x-www-form-urlencoded'".
  - "The POST request MUST NOT include cookies, HTTP authorization, or any other context information."
  - VERIFIED [RFC].
  - The receiver must have the user's consent before POSTing. RFC 8058 §3.2 per VERIFIED-2ND (`ScaleDockHQ/scaledock-skills` receiver-behavior.md). In our app, the confirmation dialog is that consent.
- **Why never auto-GET.** RFC 8058's motivation is that "anti-spam software often fetches all resources in mail header fields automatically". VERIFIED-2ND (`diogoseca/bjjgraph` unsubscribe.js quoting the RFC). A GET may unsubscribe someone by accident, or confirm to the sender that the address is live. So we **never GET** an unsubscribe URL automatically.
- **Sender-side context.** Since Feb 2024, Gmail and Yahoo require bulk senders to support one-click unsubscribe and to honour requests within 2 days. VERIFIED-2ND (deliverability table cited in §2.7; `elie222/inbox-zero` send.tsx comment "From Feb 2024 Google requires this for bulk senders"). So one-click coverage is high in practice (hush measured about 93%, VERIFIED-2ND).

### 4.2 Method selection (per sender; INFERRED algorithm)

```
Take the newest message from the sender that has a List-Unsubscribe header (metadata already cached).
uris = parseListUnsubscribe(header)          // §4.3
post = normalize(List-Unsubscribe-Post)

if post == "List-Unsubscribe=One-Click"
   and let https = uris.first(where: scheme == "https")
   and dkimCoversUnsubscribe(message)        // §4.5
   and isPublicHost(https)                   // §4.6
   → .oneClick(https)
else if let mailto = uris.first(where: scheme == "mailto")
   → .mailto(parseMailto(mailto))            // RFC 6068: to, subject, body, cc
else if let web = uris.first(where: scheme == "https" || scheme == "http")
   → .webPage(web)                           // never fetched by us; opened in browser on click
else
   → .none                                   // offer Archive/Trash/Block instead
```

The left-to-right preference of RFC 2369 is honoured *within* a method class. One-click goes first because it is the only method that is safe to automate.

### 4.3 Header parsing rules (tests must cover these)

- Unfold folded header lines (CRLF + WSP → space).
- Split on commas *outside* angle brackets.
- Strip `<` and `>`.
- Tolerate missing brackets, which some senders emit: accept a bare `https://…` or `mailto:…` token.
- Ignore URIs with schemes other than https, http and mailto.
- Cap at 5 URIs and 2,048 characters each.
- Normalise List-Unsubscribe-Post by trimming whitespace, then compare `key=value` case-insensitively on the key, with the value exactly `One-Click`.
  - Hush accepts `"  List-Unsubscribe = One-Click  "` and a trailing CRLF. VERIFIED-2ND (`justlinuxnoob/hush` parse.rs tests).
  - Reject anything with extra pairs, because the RFC says "single key/value pair".

### 4.4 One-click POST (Swift sketch)

```swift
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ s: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection r: HTTPURLResponse,
                    newRequest: URLRequest) async -> URLRequest? { nil }   // 3xx = not success (RFC 8058)
}

func postOneClick(_ url: URL) async throws -> OneClickResult {
    precondition(url.scheme == "https")
    let cfg = URLSessionConfiguration.ephemeral          // no cookie jar, no cache, no credentials
    cfg.httpShouldSetCookies = false
    cfg.httpCookieAcceptPolicy = .never
    cfg.urlCredentialStorage = nil
    cfg.timeoutIntervalForRequest = 15
    let session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }

    let boundary = "spruce-\(UUID().uuidString)"
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data("""
    --\(boundary)\r\nContent-Disposition: form-data; name="List-Unsubscribe"\r\n\r\nOne-Click\r\n--\(boundary)--\r\n
    """.utf8)
    let (_, resp) = try await session.data(for: req)
    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
    switch code {
    case 200..<300: return .done
    case 300..<400: return .redirected            // show "Finish on website" with the URL
    case 400, 415:  return .retryURLEncoded       // retry once with application/x-www-form-urlencoded body "List-Unsubscribe=One-Click"
    default:        return .failed(code)
    }
}
```

- The multipart body follows the RFC's SHOULD. The urlencoded retry follows its MAY. INFERRED: send multipart first, fall back once.
- Success = 2xx only. Do not follow redirects; treat 3xx as failure or manual. VERIFIED-2ND (`remorses/zele` CHANGELOG: "no cookies, no auth, and no HTTP redirects (senders MUST NOT redirect — 3xx is treated as failure)"; `flectar/mail` and `NextOSP/comail` unsubscribe.rs: "Success is a 2xx only: no redirects are followed … and no cookies are sent").
- User-Agent: a generic `Spruce/1.0 (one-click unsubscribe)`. Never include the user's address. INFERRED.

### 4.5 DKIM gate (RFC 8058 MUST)

Gmail records its verdict in the `Authentication-Results` header. RECALLED format: `mx.google.com; dkim=pass header.i=@example.com header.s=… ; spf=…; dmarc=pass …`. Request `Authentication-Results` and `DKIM-Signature` through `metadataHeaders`, then allow one-click only when:

1. some `dkim=pass` result names domain *D* (`header.i`/`header.d`); and
2. a `DKIM-Signature` header with `d=D` lists **both** `list-unsubscribe` and `list-unsubscribe-post` in its `h=` tag.

The `h=` check follows VERIFIED-2ND (`productdevbook/yuva` dkim.go `CoversListUnsubscribe`; `requarks/wiki` mail.ts: "RFC 8058 requires both unsubscribe headers to be signed, and Gmail and Yahoo will not honour…"). `remorses/zele` offers a similar `--require-dkim` gate (VERIFIED-2ND).

If the gate fails, downgrade to `.webPage` (manual) and show "Couldn't verify this sender — finish on its website". INFERRED.

### 4.6 SSRF and abuse guards for the POST target

The header is written by the sender, which may be an attacker. Before POSTing:

- Require https and port 443 (or no explicit port).
- Reject IP-literal hosts.
- Resolve DNS and reject loopback, private (RFC 1918), link-local, CGNAT `100.64/10`, ULA `fc00::/7`, multicast and unspecified addresses. Hush does the same: `is_loopback() || is_private()…`. VERIFIED-2ND (`justlinuxnoob/hush` unsub.rs).
- Reject hostnames ending in `.local` or `.internal`, or with no dot.
- Rate-limit to 4 concurrent POSTs.
- Never send more than one POST per sender per action.

INFERRED where not cited.

### 4.7 `mailto:` unsubscribe

- Parse with RFC 6068: `to` comes from the path; `subject`, `body` and `cc` come from the query.
- Build an RFC 5322 message: `From: <profile.emailAddress>`, `To`, `Subject` (default "unsubscribe"), and a short body (default "unsubscribe").
- Base64url-encode it and call `POST /gmail/v1/users/me/messages/send` with body `{"raw": "…"}`.
  - Cost 100 units. RECALLED; also VERIFIED-2ND (`difficultnerd/MailTinder` T-404 table: send = 100).
  - Scope: `gmail.send`, `gmail.compose` or **`gmail.modify`**. `gmail.modify` covers it: "Read, compose, and send emails…" VERIFIED [discovery]. Its listing as an accepted scope of `messages.send` is RECALLED.
- The confirmation must say an email will be sent from the user's address, and to which recipient. Hush refuses mailto for exactly this reason (VERIFIED-2ND). We allow it, with that disclosure.
- The sent message appears in **Sent**. Leave it there for transparency. INFERRED.
- Guard: refuse if `to` contains more than 1 address, or if `body` exceeds 1 KB. Never include anything not in the mailto URI. INFERRED.

### 4.8 Web-page-only senders

Show **Finish on website ↗**. It opens the URL with `NSWorkspace.shared.open(url)` only on an explicit click. Log the outcome as "manual". We never fetch these URLs. INFERRED.

### 4.9 Follow-up check (INFERRED, our extra)

Store `(sender, unsubscribedAt, method)`. On the next scan more than 3 days later, flag senders that still sent mail after `unsubscribedAt + 2 days` with the chip "Still sending". Offer **Block…** (§6.8) or Trash.

---

## 5. Gmail API reference for this tool

Base URL: `https://gmail.googleapis.com/gmail/v1/users/me/…`. VERIFIED-2ND (e.g. `danielmiessler/LifeOS` gmail.ts).

| Purpose | Method / endpoint | Key params | Min. scope (ours) | Quota units (classic; see §6.9) | Notes |
|---|---|---|---|---|---|
| Identity and totals | `GET /profile` | — | any Gmail scope | 1 | Returns `emailAddress`, `messagesTotal`, `historyId`. No openid/email scope needed. VERIFIED-2ND (ADR-053, `Himalpok1/Personal-OS`). |
| Category tiles | `GET /labels/{id}` (SPAM, TRASH, DRAFT, CATEGORY_*) | — | readonly ⊂ modify | 1 | `messagesTotal`, `messagesUnread`, `threadsTotal`. VERIFIED [discovery] for messagesTotal. |
| Enumerate IDs | `GET /messages` | `q`, `labelIds`, `maxResults≤500`, `pageToken`, `includeSpamTrash` | readonly (`q` not allowed with metadata) | 5 per page | "maximum allowed value for this field is 500". VERIFIED [discovery]. |
| Header metadata | `GET /messages/{id}` | `format=metadata`, `metadataHeaders=From&…`, `fields=id,threadId,labelIds,internalDate,sizeEstimate,payload/headers` | readonly | 5 (2026 report: 20) | `fields` partial responses also drop `snippet`. RECALLED system parameter. Privacy win. |
| Batch the above | `POST https://gmail.googleapis.com/batch/gmail/v1` (multipart/mixed) | ≤ 100 sub-requests | as each | sum of parts | VERIFIED-2ND (`pimalaya/io-gmail` `GMAIL_BATCH_MAX_REQUESTS = 100`). Google suggests ≤ 50 per batch to avoid rate errors (RECALLED). |
| Archive | `POST /messages/batchModify` | `{"ids":[…≤1000], "removeLabelIds":["INBOX"]}` | modify | 50 | 1000 cap VERIFIED [discovery]. |
| Trash (bulk) | `POST /messages/batchModify` | `{"ids":[…], "addLabelIds":["TRASH"]}` | modify | 50 | Widely used (VERIFIED-2ND `DaTrollMon/gmail_purge`: "adding the TRASH label … via batchModify"). Hush calls it "disputed" and uses per-message trash (VERIFIED-2ND). We use batchModify **plus a verification pass** (§6.6). |
| Trash (single) | `POST /messages/{id}/trash` | no body | modify | 5 | "Moves the specified message to the trash." VERIFIED [discovery]. Send `Content-Length: 0`: a bodyless POST without the header is rejected. VERIFIED-2ND (`justlinuxnoob/hush` NOTES.md). |
| Untrash | `POST /messages/{id}/untrash`, or batchModify remove `TRASH` | — | modify | 5 / 50 | Undo. |
| Not spam | batchModify remove `SPAM`, add `INBOX` | — | modify | 50 | |
| Delete draft | `DELETE /drafts/{id}` | — | modify (RECALLED) | 10 (RECALLED) | **Permanent**: "Does not simply trash it". VERIFIED [discovery]. Use only as a fallback (§6.7). |
| Send mailto unsubscribe | `POST /messages/send` | `{"raw": base64url}` | modify (or send) | 100 | §4.7 |
| Block future mail (optional) | `POST /settings/filters` | criteria `from`, action `addLabelIds:["TRASH"]` or `removeLabelIds:["INBOX"]` | **gmail.settings.basic** | 5 (RECALLED) | Our extra. VERIFIED-2ND (`justlinuxnoob/hush`: the filter is "the only way to *guarantee* a sender stops reaching the inbox"). |
| Incremental rescan | `GET /history` | `startHistoryId`, `historyTypes` | readonly | 2 | Returns 404 once the cursor ages out ("at least one week and often longer"). Then do a full rescan. VERIFIED-2ND (ADR-053). |
| **Never used** | `messages.delete`, `messages.batchDelete` | — | `https://mail.google.com/` | — | batchDelete: "Deletes many messages by message ID. Provides no guarantees…" VERIFIED [discovery]. Needs the full-access scope (RECALLED). Out of scope. |

`format` enum, verbatim (VERIFIED [discovery]):

| Format | Description |
|---|---|
| `minimal` | "Returns only email message ID and labels; does not return the email headers, body, or payload." |
| `full` | Body parsed into `payload`. "Format cannot be used when accessing the api using the gmail.metadata scope." |
| `raw` | Same restriction. |
| `metadata` | "Returns only email message ID, labels, and email headers." |

**Headers we request.** `From`, `Subject`, `Date`, `List-Unsubscribe`, `List-Unsubscribe-Post`, `List-Id`, `Precedence`, `Auto-Submitted`, `Authentication-Results`, `DKIM-Signature`. Open-source cleaners use the same core set. VERIFIED-2ND (`sievins/spring-clean-gmail` gmail.ts: `metadataHeaders: ["From","Subject","Date","List-Unsubscribe","List-Unsubscribe-Post"]`).

---

## 6. Implementation design

### 6.1 Module layout (fits the existing targets)

```
Sources/SpruceCore/Email/            (pure, unit-tested, no networking)
  EmailModels.swift                  MessageMeta, SenderSummary, EmailCategory, UnsubscribeMethod
  RFC5322From.swift                  address + RFC 2047 display-name decoding
  ListUnsubscribeParser.swift        RFC 2369 list + RFC 8058 post-value check
  MailtoParser.swift                 RFC 6068
  DKIMGate.swift                     Authentication-Results + DKIM-Signature h= check
  NewsletterClassifier.swift         §3.4 scoring
  SenderAggregator.swift             grouping, top-N, de-dup sizes
  GmailQuery.swift                   query builders for §3.2
Sources/SpruceMac/Email/             (networking, Keychain, AuthenticationServices)
  GoogleOAuth.swift                  PKCE, ASWebAuthenticationSession, loopback fallback, refresh, revoke
  TokenStore.swift                   Keychain (kSecClassGenericPassword)
  GmailClient.swift                  REST + batch, typed errors, retry
  AdaptiveRateLimiter.swift          §6.9
  OneClickUnsubscriber.swift         §4.4 + §4.6
  EmailCleanupEngine.swift           scan + actions orchestration, progress AsyncStream
  EmailActionJournal.swift           undo records (§6.10)
Sources/Spruce/Modules/Toolbox/Email/
  EmailCleanupView.swift, EmailIntroView.swift, EmailResultsView.swift,
  SenderTable.swift, EmailConfirmSheets.swift, GoogleSetupGuideView.swift
```

### 6.2 Scope policy

| Mode | Scopes requested | Unlocks |
|---|---|---|
| **Default** | `https://www.googleapis.com/auth/gmail.modify` | Everything in §2 except Block |
| Optional toggle "Also allow blocking senders" | + `https://www.googleapis.com/auth/gmail.settings.basic` | **Block…** (Gmail filter) |
| Optional "Scan only (read-only)" | `https://www.googleapis.com/auth/gmail.readonly` | Scan, plus one-click unsubscribe (an HTTP POST needs no Gmail scope). No archive, trash or mailto. |
| Never | `https://mail.google.com/`, `gmail.metadata` (it overrides `q`) | — |

Notes:
- **Incremental consent.** Use `include_granted_scopes=true` when upgrading from read-only to modify. RECALLED parameter.
- **Never combine `gmail.metadata` with other scopes.** One README warns that tokens carrying it fail `q` searches even alongside broader scopes ("Do not combine it with other scopes"). VERIFIED-2ND, weak (`aarushk09/Daemo-Bounty---Gmail-API`). The rule costs nothing.
- **Granular consent.** The consent page shows each scope as a checkbox the user can untick. Read the token response's `scope` field and enable features from it. VERIFIED-2ND (`justlinuxnoob/hush` README: "Google presents these as separate tick-boxes… Hush trusts what Google actually granted"; commands.rs: `can_delete = granted.contains("gmail.modify")`).

### 6.3 Google OAuth for a single-user macOS app

**Option A (recommended): "iOS"-type client + ASWebAuthenticationSession + PKCE, no secret.**
- Google treats an "iOS" application type as covering a native macOS app. Its token endpoint accepts secret-less exchange and refresh. "Desktop app" clients reject that with `invalid_request: client_secret is missing`, even with PKCE. VERIFIED-2ND (`shimataro/keryx` docs/sync-architecture.md).
- Redirect: `com.googleusercontent.apps.<client-id-prefix>:/oauthredirect`. The iOS client type accepts this, or a custom scheme equal to the bundle ID. VERIFIED-2ND (`polhem-dev/polhem-oauth2` ADR-006 table; `stalkiq/portalsos` GmailEngine.swift).
- `ASWebAuthenticationSession` matches the callback on the **scheme only**. VERIFIED-2ND (`readest/readest` memory notes).
- One empirical report says Desktop-type clients also accept the reverse-client-ID scheme. VERIFIED-2ND, weak (`drusifer/happening` ARCH.md). Treat it as a fallback, not the plan.
- Optionally register the scheme in `Info.plist` `CFBundleURLTypes`, so that a system-browser fallback can return through `kAEGetURL`. INFERRED.

```swift
import AuthenticationServices, CryptoKit

struct PKCE {
    let verifier: String = {
        var b = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, 32, &b)
        return Data(b).base64URL                     // 43 chars, RFC 7636
    }()
    var challenge: String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
}

@MainActor
final class GoogleAuthorizer: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for s: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? ASPresentationAnchor() }

    func authorize(clientID: String, scopes: [String], loginHint: String?) async throws -> TokenSet {
        let scheme = clientID.split(separator: ".").reversed().joined(separator: ".")  // com.googleusercontent.apps.XXXX
        let redirect = "\(scheme):/oauthredirect"
        let pkce = PKCE(); let state = UUID().uuidString
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "include_granted_scopes", value: "true"),
        ] + (loginHint.map { [.init(name: "login_hint", value: $0)] } ?? [])

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: c.url!, callbackURLScheme: scheme) { url, err in
                if let url { cont.resume(returning: url) } else { cont.resume(throwing: err ?? OAuthError.cancelled) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false   // reuse the user's Google session; set true for "use a different account"
            s.start()
        }
        let q = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard q.first(where: { $0.name == "state" })?.value == state else { throw OAuthError.stateMismatch }
        if let e = q.first(where: { $0.name == "error" })?.value { throw OAuthError.denied(e) }
        guard let code = q.first(where: { $0.name == "code" })?.value else { throw OAuthError.noCode }
        return try await exchange(code: code, verifier: pkce.verifier, clientID: clientID, redirect: redirect)
    }
}
```

- On macOS 14.4+ we may use `ASWebAuthenticationSession(url:callback: .customScheme(scheme), completionHandler:)`, the newer callback API. RECALLED.
- **Token exchange.** `POST https://oauth2.googleapis.com/token`, form-encoded: `grant_type=authorization_code`, `code`, `code_verifier`, `client_id`, `redirect_uri`. Add `client_secret` for Desktop clients only.
- **Refresh.** `grant_type=refresh_token`, `refresh_token`, `client_id` (and the secret, if Desktop).
- Endpoints: RECALLED; also seen in `justlinuxnoob/hush` auth.rs parameter set.

**Option B (fallback): Desktop client + loopback + PKCE + the default browser.**
1. Bind `127.0.0.1` on an ephemeral port with `NWListener`.
2. Open the auth URL with `NSWorkspace.shared.open`.
3. Accept a single `GET /?code=…&state=…`.
4. Reply with a tiny "You can close this tab" page.
5. Close the listener. Timeout: 300 s.

Sources and notes:
- Hush uses this design (`CONSENT_TIMEOUT = 300 s`; parameters include `code_challenge`, `S256` and offline access). VERIFIED-2ND.
- It is the RFC 8252 §7.3 desktop pattern. VERIFIED-2ND (`drusifer/happening`).
- Our app is **not sandboxed** (`Support/Spruce.entitlements`), so no entitlement is needed. A sandboxed build needs `com.apple.security.network.server`. VERIFIED-2ND (`drusifer/happening`: "The Mac App Store sandbox ships without the com.apple.security.network.server entitlement a loopback server needs").
- The Desktop "client secret" is embedded and "obviously not treated as a secret". VERIFIED-2ND (Google doc quoted in `simonw/til` and `google-gemini/gemini-cli` oauth2.ts). Store it in the Keychain anyway, so it is not left in plain `UserDefaults`.
- The out-of-band (`urn:ietf:wg:oauth:2.0:oob`) flow is retired. RECALLED (Google blocked it in 2022–23). Don't use it.

**Token storage.**
- Keychain generic password: service `com.<ourbundle>.google`, account = the email address. Value: JSON `{refresh_token, access_token, expiry, scopes}`.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; never synced.
- Keep the access token in memory. Refresh 60 s before expiry; on a 401, refresh once and retry once.
- The guideline "Tokens live in the Keychain only" comes from gap-04 §3.

### 6.4 Privacy-by-construction rules (enforced in code review and tests)

1. Only `format=metadata` (or `minimal`) is ever requested. A unit test asserts that `GmailClient` cannot build `format=full|raw`.
2. Always send `fields=` without `snippet`.
3. Persist only: sender key, display name, counts, sizes, dates, label flags, the unsubscribe method plus target URL, and message IDs (needed for actions and undo). **Subjects are held in memory only** (for row popovers).
4. Cache location: `~/Library/Application Support/<bundle>/Email/<sha256(email)>/scan.sqlite`, file mode `0600`. Wiped on Disconnect.
5. No analytics event contains addresses, domains or subjects. Activity `emailAction` events log counts and bytes only (gap-04 §4.5 schema).

### 6.5 Scan pipeline

```
P0  getProfile                         → account, messagesTotal, historyId           (1 unit)
P1  labels.get × 7                     → instant tiles                                 (7 units)
P2  messages.list per category query   → ID sets (pages of 500)                        (5/page)
    union of IDs; skip IDs already cached with the same historyId
P3  messages.get(format=metadata) via batch (≤50 per batch), limiter-paced             (5 or 20 each)
    → MessageMeta { id, threadId, labelIds, internalDate, sizeEstimate, headers }
P4  classify + aggregate (SpruceCore)  → SenderSummary[], per-category views
P5  persist summary + historyId; emit Activity "scan" event (items = messages read)
Rescan: history.list(startHistoryId) → apply added/removed/label changes; on 404 → full P2–P4.
```

**Cost model.** With the classic numbers, a 12-month window of 18,000 messages costs about 90,000 units for P3. At 250 units/s that is about 6 minutes. At the 2026 figure (20 units per get, 6,000/min) the same window takes about 60 minutes. Hush says its quota "caps a large mailbox at forty minutes" (VERIFIED-2ND, lib.rs comment).

So (INFERRED):
- Default to **Last 12 months**.
- Show the estimate before scanning.
- Make the scan resumable: persist the ID cursor and the cached metadata.
- Let categories render progressively.
- Order P3 so that Promotions, Updates and Forums go first. They hold most bulk mail, so the Newsletters and Top Senders lists fill quickly.

### 6.6 Bulk actions (engine semantics)

| Action | Calls | Notes |
|---|---|---|
| **Archive** (senders S) | For each sender: list IDs with `q=from:"addr" in:inbox` → exact-match From → `batchModify removeLabelIds:[INBOX]` in chunks of 1000 | Skip `STARRED` if the option is on. Journal the IDs. |
| **Move to Trash** | Same enumeration without `in:inbox` → `batchModify addLabelIds:[TRASH]` (chunks of 1000) → **verify**: re-list `from:"addr"`, which excludes Trash by default (VERIFIED [discovery] `includeSpamTrash` default false). Any ID still returned gets a per-message `messages.trash` fallback. | The verify step follows hush's `verify_binned`: "anything we binned that still comes back under a from: search … did not move". VERIFIED-2ND. |
| **Unsubscribe** | §4 per sender, then the chosen follow-up (keep / archive / trash existing) | Outcomes are recorded per sender. |
| **Not spam** | `batchModify removeLabelIds:[SPAM] addLabelIds:[INBOX]` | |
| **Block** (optional scope) | `settings.filters.create {criteria:{from:addr}, action:{removeLabelIds:["INBOX"], addLabelIds:["TRASH"]}}` | The filter is visible and removable in Gmail Settings › Filters (VERIFIED-2ND hush NOTES). |

Concurrency: one sender at a time per action type. Progress is reported per sender. The action can be cancelled between chunks; the journal records whatever completed.

### 6.7 Old drafts

1. Enumerate with `labelIds=DRAFT` and `q=older_than:6m`.
2. **Move to Trash** calls `messages.trash` on the draft's *message* ID, which keeps it recoverable. RECALLED that Gmail accepts trashing draft messages. Verify on the device.
3. If the API rejects it, offer a second, explicit confirmation: "Delete permanently? Drafts can't be recovered" → `drafts.delete`, which is permanent (VERIFIED [discovery]).
4. Never auto-escalate from step 2 to step 3. INFERRED.

### 6.8 Edge cases

- **Own address and aliases.** Exclude From = `profile.emailAddress`. Optionally exclude "send-as" aliases too (`settings.sendAs.list` needs settings scopes, so skip it and let the user add aliases to the ignore list). INFERRED.
- **Google Workspace accounts.** An admin may block third-party apps (`admin_policy_enforced`). VERIFIED-2ND (Google doc text quoted in `samsorensen/tune-transfer`). Gmail may also be disabled for the account (400 `failedPrecondition`). RECALLED.
- **Refresh-token limit.** "100 refresh tokens per Google Account per OAuth 2.0 client ID". Creating a new one silently invalidates the oldest. VERIFIED-2ND (Google doc quoted in `samsorensen/tune-transfer`, `AndyForest/SoupNet`). Reuse the stored refresh token. Re-consent only on `invalid_grant`.
- **Password change.** Refresh tokens carrying Gmail scopes can be revoked when the user changes password. RECALLED. Handle it as `needsReauth`.
- **Huge senders** (50k+ messages, e.g. notification bots). Page IDs and act in 1000-ID chunks, with a progress bar per sender.
- **Threads with mixed senders.** We act per *message*, so other people's replies in the same thread stay put. Tell the user this in a tooltip. INFERRED.
- **Gmail "Important" label.** It is auto-assigned. Don't protect it by default (it would hide most promos), but offer a toggle "Skip emails Gmail marked Important". gclean protects both STARRED and IMPORTANT behind config flags. VERIFIED-2ND (`jellydn/gclean` protector.go).
- **Labels on archived mail.** Archiving only removes `INBOX`; user labels stay.
- **Time.** `internalDate` is epoch milliseconds as a string (RECALLED). Use it, not the sender-controlled `Date` header, for age rules.

### 6.9 Rate limiting and errors

| Item | Value | Status |
|---|---|---|
| Per-user ceiling (classic) | 250 units/s moving average, about 15,000/min | VERIFIED-2ND (`Auxx-Ai/auxx-ai` provider-configs.ts; `Jayrr-Dev/AgenitiX` apiUsage.ts `per_user_per_minute_units: 15000`) |
| Per-project ceiling | 1,200,000 units/min | VERIFIED-2ND (`Jayrr-Dev/AgenitiX`) |
| 2026 reading of Google's page | `messages.get` = **20** units; per-user = **6,000/min** | VERIFIED-2ND (`justlinuxnoob/hush` NOTES.md, "Gmail's quota numbers disagree between sources") |
| Classic unit costs | list 5, get 5, batchModify 50, trash 5, untrash 5, send 100, getProfile 1, labels.get 1, history.list 2, drafts.delete 10 | VERIFIED-2ND for list/get (`Fireside-Cloud-Solutions/...` gmail-api-optimizations.md; `Auxx-Ai/auxx-ai` GMAIL_QUOTA_COSTS) and send (MailTinder); others RECALLED |
| Retryable errors | HTTP 429; 403 with `rateLimitExceeded`, `userRateLimitExceeded` or `quotaExceeded`; 5xx / `backendError` | VERIFIED-2ND (`elie222/inbox-zero` retry.ts; `justlinuxnoob/hush` gmail.rs) |
| `Retry-After` | Honour it when present | VERIFIED-2ND (ADR-053: "Gmail and Graph both send" it) |

**Limiter (INFERRED, modelled on hush's adaptive design).**
- A token bucket in *units*, with costs from a table in `UserDefaults`, so they can be edited if Google changes them.
- Start at 80 units/s with at most 10 requests in flight. MailDesk uses 10 in flight (VERIFIED-2ND `kedardk005/MailDesk` .env.example).
- On 50 consecutive successes, raise the rate by 10% up to 240 units/s.
- On a rate error, halve it and wait for `Retry-After`, or for an exponential backoff with full jitter (1 s, 2 s, 4 s … capped at 64 s).
- Make it deterministic for tests: inject `now`, `sleep` and `random`, as ADR-053 recommends (VERIFIED-2ND).

### 6.10 Action journal (undo)

```swift
struct EmailActionRecord: Codable {
    let id: UUID, date: Date, account: String
    let kind: Kind                      // archive, trash, notSpam, unsubscribe, block
    let senderKeys: [String]
    let messageIDs: [String]            // capped at 50k per record; larger actions split into multiple records
    let priorInbox: [String]            // subset of messageIDs that had INBOX before (to restore on undo)
    let outcomes: [String: Outcome]?    // per sender for unsubscribe
    var undone: Bool
}
```

Undo window: 30 days, matching Gmail's Trash retention (RECALLED). After that, the record shows "Can't undo — Gmail has emptied Trash".

Activity integration (gap-04 §4.4): log `emailAction` with `items` = messages affected and `bytes` = sum of `sizeEstimate`. Time saved: **20 s per sender** (the gap-04 constant).

### 6.11 Tests (SpruceCore, no network)

- **ListUnsubscribeParser.** Single and multiple URIs, folded lines, missing brackets, mailto with a `subject` query, uppercase schemes, `http` vs `https`, more than 5 URIs, the post-value variants from §4.3, and post headers with extra pairs (rejected).
- **RFC5322From.** `"Name" <a@b>`, `a@b`, encoded words (`=?UTF-8?Q?…?=`), commas in quoted names, and IDN domains (store punycode, display Unicode).
- **DKIMGate.** `pass` with `h=` covering both headers → allowed. `pass` with `h=` missing `list-unsubscribe-post` → denied. `fail` → denied. Multiple signatures → the domain must match.
- **NewsletterClassifier.** The §3.4 table cases, plus the transactional guard.
- **SenderAggregator.** De-duplicated sizes, top-N, own-address exclusion, and List-Id grouping.
- **OneClick SSRF guard.** Private, loopback and CGNAT IPs, IP literals, port ≠ 443, `.local`.
- **GmailClient against `URLProtocol` stubs.**
  - Batch building, chunking at 1000.
  - The `Content-Length: 0` trash POST.
  - Retry on 429 and 403-rate errors.
  - `invalid_grant` → `needsReauth`.
  - No `format=full` anywhere.

---

## 7. Google Cloud setup for a personal build

### 7.1 Why the user brings their own client

MacPaw's client is verified and CASA-assessed (INFERRED). Ours cannot reuse it. Shipping our own *public* client would need Restricted-scope verification plus an annual CASA assessment (VERIFIED-2ND, §0 item 7). For a single-user Mac mini, the user creates a personal client and pastes its ID into Settings. Alternatively, the developer builds it in at compile time, as Sioul does with build-time env vars (VERIFIED-2ND `aurelienpierre/sioul` docs/google.md).

### 7.2 Testing vs In production

| | Testing | In production (unverified, personal use) |
|---|---|---|
| Who can sign in | Listed test users only (max 100) | Anyone, up to a 100-user cap while unverified |
| Refresh token lifetime | **Expires 7 days after consent**. Automatic refresh does not extend it. | No 7-day timer |
| Consent screen | Unverified warning | Same warning ("Google hasn't verified this app" → Advanced → continue) |
| Policy basis | Google OAuth doc, quoted in `samsorensen/tune-transfer` | Personal-use exemption support.google.com/cloud/answer/13464323, quoted in `kenn-io/msgvault`, `nyybatboy/gmail-max-mcp` |

All of the above: VERIFIED-2ND (`Mubder/kazma` email-integration.md table; `kenn-io/msgvault` oauth-setup.md).

**Recommendation (INFERRED).** Publish to **In production** and do **not** submit for verification. The Testing mode's weekly re-auth is a poor experience. If the user stays in Testing, the UI must treat the weekly `invalid_grant` as a normal state: a one-click **Reconnect** that pre-fills `login_hint`.

### 7.3 Console steps (names per the 2026 "Google Auth Platform" console)

The menu names (Branding, Audience, Data Access, Clients) come from VERIFIED-2ND (`busystack/busymax` docs/google_setup.md).

1. console.cloud.google.com → **New project** (e.g. "Spruce Personal").
2. **APIs & Services › Library** → **Gmail API** → **Enable**.
3. **Google Auth Platform › Branding** → app name and support email. **Audience** → **External**, then add your Gmail address as a **Test user**, or **Publish app** (§7.2).
4. **Data Access** → **Add or remove scopes** → add `…/auth/gmail.modify`, and optionally `…/auth/gmail.settings.basic`.
5. **Clients › Create client**:
   - **Application type: iOS**, Bundle ID = Spruce's bundle identifier → copy the **Client ID**. No secret. (Option A)
   - Or **Desktop app** → copy the Client ID **and** client secret. (Option B)
6. In Spruce, open **Settings › Accounts › Google**, paste the Client ID (and the secret for Desktop), then click **Connect Gmail…**.

### 7.4 In-app setup guide (`notConfigured` state)

A 6-step sheet mirroring §7.3. Each step gets a "Copy" button for the scope strings and the bundle ID, and an "Open Google Cloud Console" button. The Client ID field is validated against the regex `^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$`. The guide ends with a "Test connection" button that runs `getProfile`.

---

## 8. Vendor-parity checklist

| Vendor capability | Status | Ours |
|---|---|---|
| Tools › Email Cleanup entry | VERIFIED | Toolbox row 26 `tools/email` (gap-04) ✓ |
| Gmail sign-in (OAuth) | VERIFIED | §6.3 ✓ (our own client, §7) |
| Newsletters / promotions / spam / trash / old drafts / large attachments | VERIFIED (names; exact labels GAP) | §3.2 ✓ |
| Top senders | VERIFIED | §2.6 ✓ |
| Unsubscribe (+ remove existing) | VERIFIED | §4, §2.7 ✓ |
| Archive, Move to Trash | VERIFIED | §6.6 ✓ |
| Every action confirmed | VERIFIED | §2.7 ✓ |
| Undo | GAP | Journal-based undo, 30 days ✓ (our extra) |
| Disconnect | GAP | §2.9 ✓ |
| On-device processing | GAP | Guaranteed on-device, §6.4 ✓ |
| Block future mail (filter) | Not reported for vendor | Optional extra §6.6 |
| "Still sending" follow-up | Not reported for vendor | Optional extra §4.9 |

---

## 9. Open gaps and how to close them on the Mac mini (INFERRED procedure)

1. **Exact UI labels, layout and states.** Install the 5.7.1 trial, open Tools › Email Cleanup, and record the intro, scan, results and confirmation screens. For *structure only*, dump the string keys: `plutil -p`, or open `…/Contents/Resources/*.lproj/*.strings`/`.loctable` files whose names mention email or gmail (gap-01 §9 kit). Do not copy the wording.
2. **Scopes MacPaw requests.** Read them off Google's consent page. Afterwards check myaccount.google.com › Security › "Your connections to third-party apps & services" → CleanMyMac → access list.
3. **Redirect mechanism.** During sign-in, see whether a browser tab opens (loopback) or a system sheet appears (`ASWebAuthenticationSession`). Run `lsof -iTCP -sTCP:LISTEN -P | grep -i cleanmymac` during consent to detect a loopback listener.
4. **On-device processing vs a MacPaw proxy.** Run Little Snitch or `nettop -p <pid>` during a scan. Traffic should go only to `gmail.googleapis.com` and `oauth2.googleapis.com`; any MacPaw host during the scan would suggest server-side processing.
5. **Undo behaviour** after Trash and Archive. **Sign-out** location (tool header vs Settings).
6. **Plan tier** (Basic vs Plus) and **App Store edition** availability.
7. **Quota cost table.** When `developers.google.com` is reachable, re-read https://developers.google.com/workspace/gmail/api/reference/quota and update the limiter defaults (§6.9 conflict).
8. **Restricted-scope list.** Re-read https://developers.google.com/workspace/gmail/api/auth/scopes to confirm the gmail.send (Sensitive) and gmail.labels (Non-sensitive) classifications. Third-party sources disagree on gmail.send and gmail.readonly.
9. **`messages.trash` on draft messages.** Test it with a throwaway draft (§6.7).

---

## 10. Sources

**Vendor (via sibling reports, fetched earlier this run)**
- https://macpaw.com/how-to/organize-email-inbox — entry point, categories, actions, confirmations (01 §5.1/§5.2; 13 §3.48)
- https://macpaw.com/cleanmymac/whats-new — 5.7.0 Email Cleanup line (01 §6)
- https://macpaw.com/news/my-tools-cleanmymac — Email Cleanup among the example tools (01 §5.2)
- https://macpaw.com/support/cleanmymac/knowledgebase/concepts-and-usage — "Email cleanup" section (01 §5.1)
- Homebrew cask history for the 5.7.0 and 5.7.1 dates (01 §6)

**Google, primary text (discovery document mirrors)**
- https://github.com/googleapis/google-api-nodejs-client/blob/main/discovery/gmail-v1.json — scope descriptions; `format` enum incl. the gmail.metadata restriction; `maxResults` ≤ 500; `includeSpamTrash`; `metadataHeaders`; batchModify "limit of 1000 ids"; `messages.trash`; `messages.batchDelete`; `drafts.delete` "permanently deletes … Does not simply trash it"; `Label.messagesTotal`; `Message.sizeEstimate`
- https://github.com/googleapis/google-api-python-client/blob/main/googleapiclient/discovery_cache/documents/gmail.v1.json — same text
- https://github.com/ballerina-platform/module-ballerinax-googleapis.gmail (types.bal) — `q` "cannot be used when accessing the api using the gmail.metadata scope"

**RFC text**
- https://github.com/jstedfast/MimeKit/blob/master/rfc/rfc8058.txt (canonical https://www.rfc-editor.org/rfc/rfc8058) — HTTPS URI, single key/value pair, DKIM coverage, no redirects, multipart/urlencoded, no cookies or auth
- https://github.com/jstedfast/MimeKit/blob/master/rfc/rfc2369.txt (canonical https://www.rfc-editor.org/rfc/rfc2369) — left-to-right preference
- https://github.com/tex2e/rfc-translater (html/rfc8058.html, html/rfc2369.html) — same text

**Google OAuth and policy (quoted by third parties)**
- https://github.com/samsorensen/tune-transfer/blob/main/notes/oauth2.0.txt — Testing 7-day expiry; 100 refresh tokens per account per client; `admin_policy_enforced`
- https://github.com/AndyForest/SoupNet (docs/planning/org-accounts-research/offboarding-deprovisioning.md) — same quotes
- https://github.com/kenn-io/msgvault/blob/main/docs/guides/oauth-setup.md — personal-use exemption, In production removes the 7-day expiry
- https://github.com/Mubder/kazma (docs/docs/guide/email-integration.md) — Testing vs Production table
- https://github.com/nyybatboy/gmail-max-mcp/blob/main/SETUP.md — publish without verification; support.google.com/cloud/answer/13464323
- https://github.com/busystack/busymax/blob/main/docs/google_setup.md — 2026 console menu names
- https://github.com/postalsys/learn-emailengine-app (docs/accounts/gmail/gmail-api-scopes.md) — Restricted vs Sensitive Gmail scopes
- https://github.com/nicksheaharty/synced-landing (content/guides/batch-b/gmail-oauth-scopes-explained.ts) — scope classification table
- https://github.com/simonw/til/blob/main/googlecloud/google-oauth-cli-application.md — "client secret is obviously not treated as a secret"
- https://github.com/shimataro/keryx/blob/main/docs/sync-architecture.md — iOS-type client for macOS, secret-less; Desktop clients need the secret
- https://github.com/polhem-dev/polhem-oauth2/blob/main/docs/adr/adr-006-app-sign-in.md — Google client types and accepted redirects
- https://github.com/drusifer/happening/blob/main/docs/ARCH.md — ASWebAuthenticationSession on macOS; loopback needs `network.server` in the sandbox
- https://github.com/readest/readest (apps/readest-app/.claude/memory/gdrive-provider-multipr-status.md) — ASWebAuthenticationSession matches on scheme

**Open-source Gmail cleaners (implementation evidence)**
- https://github.com/justlinuxnoob/hush — README, NOTES.md, src-tauri/src/{auth,unsub,parse,scan,ratelimit,gmail,model}.rs (scopes, loopback+PKCE, SSRF guard, quota conflict, trash verification, Content-Length gotcha)
- https://github.com/jellydn/gclean — classifier.go, protector.go, sender_trash.go, docs/desktop.md
- https://github.com/elie222/inbox-zero — apps/web/utils/gmail/{scopes,retry}.ts
- https://github.com/sievins/spring-clean-gmail — src/lib/gmail.ts (`metadataHeaders`)
- https://github.com/DaTrollMon/gmail_purge — internal/gmailapi/gmailapi.go (trash via batchModify)
- https://github.com/remorses/zele — CHANGELOG.md (one-click, mailto, `--require-dkim`)
- https://github.com/flectar/mail, https://github.com/NextOSP/comail — unsubscribe.rs (2xx-only, no redirects, no cookies)
- https://github.com/Himalpok1/Personal-OS — docs/decisions/ADR-053.md (metadata-scope limits, `history.list` 404, `Retry-After`)
- https://github.com/pimalaya/io-gmail — src/v1/batch.rs (100-request batch cap)
- https://github.com/Jayrr-Dev/AgenitiX (convex/apiUsage.ts), https://github.com/Auxx-Ai/auxx-ai (provider-configs.ts), https://github.com/kedardk005/MailDesk (.env.example) — quota figures
- https://github.com/neilbhammar/mailmop — blog posts on Gmail "Manage subscriptions" (2025)
- https://github.com/ScaleDockHQ/scaledock-skills (skills/list-unsubscribe/references/*.md), https://github.com/peterbamuhigire/social-media-skills (deliverability table) — receiver consent; 2-day processing rule
- https://github.com/productdevbook/yuva (api/internal/email/dkim.go), https://github.com/requarks/wiki (backend/models/mail.ts) — DKIM `h=` coverage of the unsubscribe headers

**Sibling reports**: `01-overview.md` §5.1, §5.2, §6; `12-competitors.md` §5.7; `13-helpcenter.md` §1, §3.48; `20-gap-01` §4.1, §9; `20-gap-04` §3, §4.4, §4.5.
