import Foundation

/// Decides which `launchctl` commands Spruce may run while removing a flagged launch job.
///
/// The label of a flagged property list is chosen by whoever wrote it, and heuristic
/// findings can be false positives, so the label is never trusted on its own:
/// `launchctl bootout` and `disable` act on *whatever* job carries that label. Malware that
/// copies the label of a real macOS service (`com.apple.mDNSResponder`) or of another
/// vendor's job must not make Spruce stop or permanently turn off that service.
///
/// The rules:
/// * labels with unusual characters are never passed to `launchctl`;
/// * a label that macOS itself defines (in `/System/Library/Launch*`) is never stopped or
///   turned off — the real service would be hit, not the copy;
/// * a job is only stopped when launchd confirms it was loaded from the flagged plist
///   (`launchctl print` shows that plist as its `path`);
/// * `com.apple.*` labels are never turned off, and neither is a label that differs from
///   the plist's file name unless the catalog matched the label itself.
public enum ProtectionLaunchControl {
    /// Folders where macOS defines its own launch jobs.
    public static let systemJobFolders = [
        "/System/Library/LaunchDaemons", "/System/Library/LaunchAgents",
        "/Library/Apple/System/Library/LaunchDaemons", "/Library/Apple/System/Library/LaunchAgents",
    ]

    /// `launchctl print` exits with this status when no job has the label.
    public static let serviceNotFoundStatus: Int32 = 113

    /// True for labels made of the characters launchd labels use in practice.
    public static func isSafeLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 255, !label.hasPrefix("-") else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-+@:".unicodeScalars.contains(scalar))
        }
    }

    /// True for labels in Apple's namespace.
    public static func isAppleLabel(_ label: String) -> Bool {
        label.lowercased().hasPrefix("com.apple.")
    }

    /// Lowercased labels (file names and `Label` keys) of the jobs defined in `folders`.
    public static func systemLabels(folders: [String] = systemJobFolders) -> Set<String> {
        var labels = Set<String>()
        let fm = FileManager.default
        for folder in folders {
            for name in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where name.lowercased().hasSuffix(".plist") {
                labels.insert((name as NSString).deletingPathExtension.lowercased())
                guard let data = fm.contents(atPath: folder + "/" + name),
                      let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dict = object as? [String: Any],
                      let label = dict["Label"] as? String, !label.isEmpty else { continue }
                labels.insert(label.lowercased())
            }
        }
        return labels
    }

    // MARK: Policy

    /// What Spruce may do with one job, before asking launchd anything.
    public struct Policy: Sendable, Equatable {
        public var label: String?
        /// Why the job is not stopped (nil: it may be stopped once launchd confirms it was
        /// loaded from the flagged plist).
        public var stopRefusal: String?
        /// Why the label is not turned off in launchd (nil: it may be).
        public var disableRefusal: String?

        public init(label: String?, stopRefusal: String?, disableRefusal: String?) {
            self.label = label
            self.stopRefusal = stopRefusal
            self.disableRefusal = disableRefusal
        }

        public var mayStop: Bool { stopRefusal == nil }
        public var mayDisable: Bool { disableRefusal == nil }
    }

    /// - Parameters:
    ///   - plistPath: the flagged property list.
    ///   - label: its `Label` key (nil when it has none).
    ///   - systemLabels: from `systemLabels(folders:)`.
    ///   - catalogMatchedLabel: the threat catalog matched this label itself.
    public static func policy(plistPath: String, label: String?, systemLabels: Set<String>,
                              catalogMatchedLabel: Bool) -> Policy {
        guard let label, !label.isEmpty else {
            let reason = "It has no job name, so launchd can't run it"
            return Policy(label: nil, stopRefusal: reason, disableRefusal: reason)
        }
        guard isSafeLabel(label) else {
            let reason = "Its job name contains unusual characters, so Spruce doesn't pass it to launchctl"
            return Policy(label: label, stopRefusal: reason, disableRefusal: reason)
        }
        if systemLabels.contains(label.lowercased()) {
            let reason = "It copies the name of a macOS service (\(label)), so Spruce leaves launchd alone to keep the real service running"
            return Policy(label: label, stopRefusal: reason, disableRefusal: reason)
        }
        if isAppleLabel(label) {
            return Policy(label: label, stopRefusal: nil,
                          disableRefusal: "It uses an Apple-style job name (\(label)), which Spruce never turns off in launchd")
        }
        let stem = ((plistPath as NSString).lastPathComponent as NSString).deletingPathExtension
        if stem.caseInsensitiveCompare(label) != .orderedSame && !catalogMatchedLabel {
            return Policy(label: label, stopRefusal: nil,
                          disableRefusal: "Its job name (\(label)) differs from its file name, so Spruce won't turn that name off in launchd")
        }
        return Policy(label: label, stopRefusal: nil, disableRefusal: nil)
    }

    // MARK: launchd state

    /// What `launchctl print <domain>/<label>` reported.
    public enum LoadState: Sendable, Equatable {
        case notLoaded
        /// Loaded; `plistPath` is the property list launchd loaded it from, when shown.
        case loaded(plistPath: String?)
        /// `launchctl` failed for another reason.
        case unknown
    }

    /// Interprets the exit status and output of `launchctl print <domain>/<label>`.
    public static func loadState(printStatus: Int32, output: String) -> LoadState {
        if printStatus == 0 { return .loaded(plistPath: loadedPlistPath(fromPrint: output)) }
        if printStatus == serviceNotFoundStatus || output.localizedCaseInsensitiveContains("could not find service") {
            return .notLoaded
        }
        return .unknown
    }

    /// The `path = …` line of `launchctl print` (the plist the job was loaded from).
    public static func loadedPlistPath(fromPrint output: String) -> String? {
        for raw in output.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("path = ") else { continue }
            let value = line.dropFirst("path = ".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// True when the job is loaded and came from `plistPath`, so stopping it stops this
    /// item and nothing else.
    public static func isLoaded(from plistPath: String, state: LoadState) -> Bool {
        guard case .loaded(let loadedPath?) = state else { return false }
        return samePath(loadedPath, plistPath)
    }

    /// Whether to run `launchctl bootout` for the job.
    public static func shouldStop(policy: Policy, plistPath: String, state: LoadState) -> Bool {
        guard policy.mayStop else { return false }
        switch state {
        case .notLoaded:
            return false
        case .loaded:
            return isLoaded(from: plistPath, state: state)
        case .unknown:
            // launchd couldn't be asked: only for labels that pass every check.
            return policy.mayDisable
        }
    }

    /// Parses the `disabled services` block of `launchctl print-disabled <domain>` into
    /// label → disabled. Accepts both `=> disabled|enabled` and the older `=> true|false`.
    public static func disabledOverrides(fromPrintDisabled output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        var inBlock = false
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if line.hasPrefix("disabled services = {") { inBlock = true }
                continue
            }
            if line == "}" { break }
            guard let arrow = line.range(of: "=>") else { continue }
            var label = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            if label.hasPrefix("\""), label.hasSuffix("\""), label.count >= 2 {
                label = String(label.dropFirst().dropLast())
            }
            switch line[arrow.upperBound...].trimmingCharacters(in: .whitespaces).lowercased() {
            case "disabled", "true": result[label] = true
            case "enabled", "false": result[label] = false
            default: continue
            }
        }
        return result
    }

    /// Case-insensitive comparison of standardized paths (APFS is case-insensitive).
    static func samePath(_ a: String, _ b: String) -> Bool {
        (a as NSString).standardizingPath.lowercased() == (b as NSString).standardizingPath.lowercased()
    }
}
