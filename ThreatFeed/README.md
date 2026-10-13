# Spruce threat list

This folder is Spruce's downloadable threat list. The app fetches two files from the
`main` branch of this repository:

| File | Address |
|---|---|
| `feed.json` | `https://raw.githubusercontent.com/MiTMi/CleanMyMac-s/main/ThreatFeed/feed.json` |
| `rules.yara` | `https://raw.githubusercontent.com/MiTMi/CleanMyMac-s/main/ThreatFeed/rules.yara` |

How the app uses them:

* It checks at most once a day, when a Protection scan starts or when the user presses
  **Check Now** in Settings. Users can turn the download off in Settings.
* It downloads over HTTPS only. `feed.json` may be up to 5 MB and `rules.yara` up to 2 MB;
  bigger files are refused.
* A copy that passes the checks below is cached on disk. If a download fails or is refused,
  the app quietly keeps its cached copy, or the catalog built into the app.
* The list can only **add** detections. Built-in families win when an id is used twice,
  indicators the built-in catalog already has are skipped, downloaded indicators and rules
  are ignored for Apple-signed files, and downloaded rules don't run on programs with a
  valid developer signature (Developer ID or App Store). Something only this list flags is
  shown to the user but never selected for removal on its own. Spruce never removes
  anything without the user confirming, and removed items go to the Trash.

The code that reads and checks these files is
`Sources/SpruceCore/Protection/ProtectionThreatFeed.swift` (feed) and
`ProtectionRuleSource.swift` (rules). `ThreatFeedRepositoryTests` checks that the files in
this folder pass.

## feed.json

```json
{
  "format": 1,
  "version": 2,
  "updated": "2026-10-13",
  "families": [
    {
      "id": "examplestealer",
      "name": "Example Stealer",
      "category": "stealer",
      "severity": "critical",
      "summary": "Steals browser passwords and sends them to its server."
    }
  ],
  "indicators": [
    { "kind": "path", "pattern": "~/Library/LaunchAgents/com.examplestealer.agent.plist", "family": "examplestealer" },
    { "kind": "launchLabel", "pattern": "com.examplestealer.agent", "family": "examplestealer" },
    { "kind": "sha256", "pattern": "<64 hex characters>", "family": "examplestealer" },
    { "kind": "path", "pattern": "~/Library/Application Support/.exst/helper", "family": "examplestealer", "executableOnly": true }
  ]
}
```

### Top level

| Key | Rule |
|---|---|
| `format` | Required. Must be `1`. A higher number tells older versions of Spruce to ignore the file. |
| `version` | Required, at least 1. **Raise it with every change.** The app never replaces its cached copy with a lower version. |
| `updated` | Optional. `YYYY-MM-DD` or a full ISO 8601 date and time. |
| `families` | Optional. At most 2,000 entries. |
| `indicators` | Optional. At most 20,000 entries. |

Other keys are ignored. If the file isn't a JSON object, has the wrong format, a missing
version, a top-level key of the wrong type or too many entries, the whole file is refused.
Otherwise each bad entry is left out on its own, with a reason the app keeps for
diagnostics.

### Families

| Key | Rule |
|---|---|
| `id` | Lowercase letters, digits, `.`, `-` and `_`; starts with a letter or digit; at most 64 characters. An id the built-in catalog already uses is ignored (the built-in family is kept). Each id may appear once. |
| `name` | 1 to 80 characters, shown to the user. |
| `category` | One of `adware`, `browserHijacker`, `pua`, `stealer`, `backdoor`, `spyware`, `trojan`, `dropper`, `miner`, `ransomware`, `malware`, `suspicious`. |
| `severity` | `low`, `medium`, `high` or `critical`. |
| `summary` | Optional, at most 300 characters. A plain, original one-line description. |

Indicators may also point at the built-in families, by id: `adload`, `pirrit`, `genieo`,
`bundlore`, `shlayer`, `chromeloader`, `amos`, `banshee` and the others listed in
`ProtectionCatalogData.families`.

Findings that only this list (its indicators or rules) detects are never pre-selected for
removal: the user decides. When the built-in catalog or Apple's XProtect rules also detect
an item, pre-selection follows its family's category: known threats are pre-selected for
removal except `pua` and `suspicious`, which wait for the user's decision.

### Indicators

Every indicator has a `kind`, a `pattern` and a `family` (an id from this file or the
built-in catalog). `executableOnly` (default `false`) limits path indicators to programs:
Mach-O files, scripts with a shebang, or files with an execute bit.

| Kind | Pattern | Checks |
|---|---|---|
| `path` | A path glob. `~` is the home folder. `*` and `?` stay within one name. | See "Path patterns". |
| `pathRegex` | A regular expression over the same paths, case-insensitive. | See "Path patterns". |
| `launchLabel` | Glob of a startup job's label. | At least two dot-separated parts before any wildcard (`com.example.*` is fine, `com.*` isn't); no spaces or `/`; must not match common jobs such as `com.google.keystone.agent` or `com.apple.…`. |
| `bundleID` | Glob of an app's bundle identifier. | Same as `launchLabel`; must not match identifiers such as `com.apple.Safari` or `com.google.Chrome`. |
| `bundleName` | Glob of a bundle's file name, e.g. `Example Cleaner.app`. | At least four characters before any wildcard; no `/`; must not match common names such as `Installer.app` or `Example Helper.app` (so `*.app` and `Install*` are refused). |
| `teamID` | Apple Developer Team ID of a revoked malware signing identity. | 10 letters and digits (stored uppercase). The teams of a few widely used developers (Adobe, Google, Microsoft, Mozilla) are refused. |
| `sha256` | SHA-256 of a malicious file. | 64 hexadecimal characters (stored lowercase). The hash of an empty file is refused. |

Patterns may not be empty, start or end with spaces, or contain control characters. An
indicator the built-in catalog (or this file) already has is skipped silently. Only add
indicators from public research you can link to, and never guess hashes.

### Path patterns

A path indicator flags the item it matches **and everything inside it**, so the checks
are strict:

* A `path` starts with `/` or `~/`, has no empty names, `.` or `..`, and is at most 512
  characters.
* It needs **at least two concrete names before any wildcard**; `~` doesn't count.
  `~/Library/LaunchAgents/com.example.*.plist` is fine; `/`, `~`, `~/*`, `~/.helper`,
  `/tmp/*` and `/tmp/php*` are refused, `/tmp/runner` is fine. (A single name right in the
  home folder, like `~/.helper`, can only be built into the app.)
* Every name with a wildcard needs at least three other characters (`~/Library/LaunchAgents/*`
  is refused).
* A `pathRegex` starts with `^/` or `^~/`, compiles, uses `|` only inside parentheses and
  has no back-references. So that it is quick to check against every path, it has no
  repeated group (`(a|b)*`, `(x+)+`, `(ab){2}`), at most two repeats (`*`, `+`, `?`, `{n,}`,
  `{n,m}`; `{n}` is fine) and at most four `|`. Its literal start must hold at least two
  complete names: `^~/Library/Application Support/\.[0-9]{19,}(/|$)` is fine,
  `^/(private/)?tmp/php` isn't (write two entries, `^/private/tmp/…` and so on, with two
  names each).
* No pattern may point into the user's own files: `~/Documents`, `~/Desktop`,
  `~/Downloads`, `~/Pictures`, `~/Movies`, `~/Music`, `~/Public`, `~/Sites`, iCloud Drive
  and cloud storage (`~/Library/Mobile Documents`, `~/Library/CloudStorage`), Mail,
  Messages, Photos, Safari, Calendars, Keychains, Apple's app containers
  (`~/Library/Containers/com.apple.…`, `~/Library/Group Containers/group.com.apple.…`),
  Photos and Music libraries anywhere, `/Users` and `/Volumes`.
* No pattern may match one of Spruce's ordinary sample locations: the home folder and its
  standard folders, `~/Library/LaunchAgents/com.example.agent.plist`,
  `/Library/LaunchDaemons/com.example.helper.plist`, `/Applications/Example.app`,
  `/tmp/example`, `/usr/local/bin/example` and so on (`canaryPaths` in
  `ProtectionThreatFeedValidator`).

## rules.yara

Extra YARA rules, run by Spruce's built-in engine next to Apple's XProtect rules over the
programs and scripts a malware scan examines: loose programs and scripts, apps' main
programs, the programs startup jobs run, helper tools and files in known threat locations.
Files bigger than 100 MB are skipped and the rules see at most the first 16 MB of a file.

Each rule's meta section may say what it detects:

| Meta key | Meaning |
|---|---|
| `description` | What the user sees: "Matches the Spruce threat list rule for *description*". Falls back to the rule name. |
| `family` | A family id from `feed.json` or the built-in catalog; the finding then takes that family's name and category. |
| `category` | One of the categories above (overrides the family's). |
| `severity` | `low`, `medium`, `high` or `critical`. Default: the family's severity, at least `high`. |

Without `family`, Spruce looks for a known family name in the description and the rule name
(`adload`, `pirrit`, `shlayer`…); otherwise the finding is named after the description and
counts as `malware`.

Supported: text strings (`ascii`, `wide`, `nocase`, `fullword`, `private`, `xor`), hex
strings (`??`, nibble wildcards, jumps, alternatives), the usual conditions (`all of them`,
`2 of ($a*)`, `#a > 3`, `$a at 0`, `$a in (0..100)`, `for … of`, `uint32(0) == 0xfeedfacf`,
`filesize < 1MB`, `hash.sha256(0, filesize) == "…"`, references to other rules, private and
global rules). Rules that use regular expressions, base64 strings or modules other than
`hash` (`pe`, `macho`, `math`…) are skipped, each on its own, along with the rules that
refer to them; `include` lines are ignored.

Keep rules specific. When the app loads the file it runs the rules over a few harmless
samples (an empty file, bare program headers, the start of a 1 MB program, a tiny shell
script, a property list, zeros and random bytes); any rule that matches one is switched
off. The rules don't run on programs with a valid developer signature (Developer ID or App
Store); scripts and unsigned, ad-hoc or badly signed programs are checked. Test a new rule against the
malware sample it targets and against ordinary apps before publishing it.
