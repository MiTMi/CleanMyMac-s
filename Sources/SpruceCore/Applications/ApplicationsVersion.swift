import Foundation

/// Version comparison compatible with Sparkle's `SUStandardVersionComparator`, plus the
/// clean-ups update checkers need (trailing ".0", cask "1.2,345" builds, decorations).
public enum ApplicationsVersion {

    enum PartType { case number, string, period, separator }

    static func type(of character: Character) -> PartType {
        if character == "." { return .period }
        if character.isASCII && character.isNumber { return .number }
        if character.isWhitespace || character.isPunctuation || character.isSymbol { return .separator }
        return .string
    }

    /// Splits "1.2b3" into ["1", ".", "2", "b", "3"]: runs of one character type; periods
    /// are always parts of their own.
    static func parts(_ version: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentType: PartType?
        for character in version {
            let t = type(of: character)
            if let ct = currentType, ct == t, t != .period {
                current.append(character)
            } else {
                if !current.isEmpty { result.append(current) }
                current = String(character)
                currentType = t
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Compares two version strings the way Sparkle does:
    /// numbers numerically, strings lexically, a string part is older than a number part
    /// (`1.2a < 1.2.1`), a longer numeric tail is newer, a trailing string tail is older
    /// (`1.0b1 < 1.0`), and trailing zeros are ignored.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = parts(a.trimmingCharacters(in: .whitespaces))
        let pb = parts(b.trimmingCharacters(in: .whitespaces))
        let n = min(pa.count, pb.count)
        for i in 0..<n {
            let ta = type(of: pa[i].first!)
            let tb = type(of: pb[i].first!)
            if ta == tb {
                switch ta {
                case .number:
                    let na = Decimal(string: pa[i]) ?? 0
                    let nb = Decimal(string: pb[i]) ?? 0
                    if na < nb { return .orderedAscending }
                    if na > nb { return .orderedDescending }
                case .string:
                    let r = pa[i].compare(pb[i])
                    if r != .orderedSame { return r }
                case .period, .separator:
                    continue
                }
            } else if ta != .string && tb == .string {
                return .orderedDescending
            } else if ta == .string && tb != .string {
                return .orderedAscending
            } else if ta == .number {
                // A number against a period/separator: the number is newer.
                return .orderedDescending
            } else if tb == .number {
                return .orderedAscending
            }
            // Period vs separator: treat as equal.
        }
        if pa.count == pb.count { return .orderedSame }
        let longerIsA = pa.count > pb.count
        let tail = longerIsA ? Array(pa[n...]) : Array(pb[n...])
        // The first meaningful extra part decides: a number makes the longer version newer
        // ("1.2.1" > "1.2"), a string marks a pre-release of the shorter one ("1.0b1" < "1.0",
        // "2.0 beta" < "2.0"). Extra zeros only ("1.2.0" vs "1.2") are equal.
        let meaningful = tail.filter { part in
            let t = type(of: part.first!)
            return t == .string || t == .number
        }
        if meaningful.allSatisfy({ type(of: $0.first!) == .number && $0.allSatisfy { $0 == "0" } }) {
            return .orderedSame
        }
        let longerIsNewer = type(of: meaningful.first!.first!) == .number
        if longerIsA {
            return longerIsNewer ? .orderedDescending : .orderedAscending
        }
        return longerIsNewer ? .orderedAscending : .orderedDescending
    }

    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    /// Splits a Homebrew cask version ("1.2.3,456" or "1.2.3,456:abc") into version and build.
    /// `latest` (unversioned casks) yields nil.
    public static func splitCaskVersion(_ raw: String) -> (version: String, build: String?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.lowercased() != "latest" else { return nil }
        let pieces = trimmed.split(separator: ",", maxSplits: 1).map(String.init)
        let version = pieces[0]
        var build = pieces.count > 1 ? pieces[1] : nil
        if let b = build, let colon = b.firstIndex(of: ":") { build = String(b[..<colon]) }
        return (version, build?.isEmpty == true ? nil : build)
    }

    /// Strips decorations that are not part of the version ("v1.2", "Version 1.2",
    /// "1.2 (Build 34)" → "1.2").
    public static func cleaned(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["version ", "ver. ", "ver ", "v"] where s.lowercased().hasPrefix(prefix) {
            let rest = s.dropFirst(prefix.count)
            if rest.first?.isNumber == true { s = String(rest) }
        }
        if let paren = s.firstIndex(of: "("), paren > s.startIndex {
            s = String(s[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Words that mark pre-releases in version names or channels.
    static let prereleaseMarkers = ["alpha", "beta", "rc", "dev", "nightly", "preview", "canary", "pre", "insider", "snapshot", "test"]

    /// True when a version string looks like a pre-release ("2.0b3", "3.1-rc1", "4.0 Beta").
    public static func isPrerelease(_ version: String) -> Bool {
        let lower = version.lowercased()
        for marker in prereleaseMarkers {
            if lower.range(of: marker) != nil { return true }
        }
        // "2.0b3" / "2.0a1": a single a/b letter followed by a digit.
        let scalars = Array(lower)
        for (i, ch) in scalars.enumerated() where (ch == "a" || ch == "b") && i > 0 && i + 1 < scalars.count {
            if scalars[i - 1].isNumber && scalars[i + 1].isNumber { return true }
        }
        return false
    }

    /// First numeric component ("12.4.1" → 12).
    public static func majorComponent(_ version: String) -> Int? {
        let digits = version.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// A major upgrade: the first numeric component increases (5.x → 6.0).
    public static func isMajorUpgrade(from installed: String, to available: String) -> Bool {
        guard let a = majorComponent(installed), let b = majorComponent(available) else { return false }
        return b > a
    }

    /// True when the running OS (e.g. "14.5") satisfies a minimum system version ("10.13").
    public static func osSatisfies(minimum: String?, current: String) -> Bool {
        guard let minimum, !minimum.isEmpty else { return true }
        return compare(current, minimum) != .orderedAscending
    }

    /// True when the running OS does not exceed a maximum system version.
    public static func osSatisfies(maximum: String?, current: String) -> Bool {
        guard let maximum, !maximum.isEmpty else { return true }
        return compare(current, maximum) != .orderedDescending
    }

    /// "14.5.0" from `ProcessInfo.operatingSystemVersion`.
    public static var currentOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Decides whether an available version is an update for the installed app.
    ///
    /// Sparkle semantics: the feed's build (`sparkle:version`) is compared with the installed
    /// `CFBundleVersion`. The display versions guard against mixed numbering schemes — an
    /// item whose display version is *older* than the installed one is never an update.
    public static func isUpdate(availableVersion: String, availableBuild: String?,
                                installedVersion: String, installedBuild: String) -> Bool {
        let shortAvailable = cleaned(availableVersion)
        let shortInstalled = cleaned(installedVersion)
        if !shortAvailable.isEmpty && !shortInstalled.isEmpty && compare(shortAvailable, shortInstalled) == .orderedAscending {
            return false
        }
        if let availableBuild, !availableBuild.isEmpty, !installedBuild.isEmpty {
            return compare(availableBuild, installedBuild) == .orderedDescending
        }
        guard !shortAvailable.isEmpty, !shortInstalled.isEmpty else { return false }
        return compare(shortAvailable, shortInstalled) == .orderedDescending
    }
}
