import Foundation

// MARK: - launchctl

public enum PerformanceLaunchctl {
    /// Parses the `services = { … }` block of `launchctl print gui/<uid>` or `launchctl print system`.
    /// Each line is `<pid> <last exit status> <label>`; a pid of `0` or `-` means not running.
    public static func services(fromPrint output: String) -> [String: PerformanceLaunchService] {
        var result: [String: PerformanceLaunchService] = [:]
        var inServices = false
        var depth = 0
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inServices {
                if line == "services = {" {
                    inServices = true
                    depth = 1
                }
                continue
            }
            if line.hasSuffix("{") { depth += 1; continue }
            if line == "}" {
                depth -= 1
                if depth == 0 { break }
                continue
            }
            guard depth == 1 else { continue }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 3 else { continue }
            let pidToken = tokens[0]
            let statusToken = tokens[1]
            guard pidToken == "-" || Int32(pidToken) != nil, statusToken == "-" || Int(statusToken) != nil else { continue }
            let label = tokens[2...].joined(separator: " ")
            let pid = Int32(pidToken).flatMap { $0 > 0 ? $0 : nil }
            result[label] = PerformanceLaunchService(label: label, pid: pid, lastExitStatus: statusToken == "-" ? nil : statusToken)
        }
        return result
    }

    /// Parses `launchctl list` (tab separated `PID Status Label`, header first).
    public static func services(fromList output: String) -> [String: PerformanceLaunchService] {
        var result: [String: PerformanceLaunchService] = [:]
        for rawLine in output.components(separatedBy: "\n") {
            let fields = rawLine.components(separatedBy: "\t")
            guard fields.count >= 3 else { continue }
            let pidToken = fields[0].trimmingCharacters(in: .whitespaces)
            let statusToken = fields[1].trimmingCharacters(in: .whitespaces)
            let label = fields[2...].joined(separator: "\t").trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, pidToken == "-" || Int32(pidToken) != nil else { continue }
            let pid = Int32(pidToken).flatMap { $0 > 0 ? $0 : nil }
            result[label] = PerformanceLaunchService(label: label, pid: pid, lastExitStatus: statusToken == "-" ? nil : statusToken)
        }
        return result
    }

    /// Parses the `disabled services` block of `launchctl print-disabled <domain>` into
    /// label → disabled. Accepts both `=> disabled|enabled` and the older `=> true|false`.
    public static func disabledOverrides(fromPrintDisabled output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        var inBlock = false
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if line.hasPrefix("disabled services = {") || line == "disabled services = {" { inBlock = true }
                continue
            }
            if line == "}" { break }
            guard let arrow = line.range(of: "=>") else { continue }
            var label = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            if label.hasPrefix("\"") && label.hasSuffix("\"") && label.count >= 2 {
                label = String(label.dropFirst().dropLast())
            }
            let value = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces).lowercased()
            switch value {
            case "disabled", "true": result[label] = true
            case "enabled", "false": result[label] = false
            default: continue
            }
        }
        return result
    }

    /// The service target for a label in a domain (`gui/501/com.example.agent`).
    public static func serviceTarget(domain: PerformanceLaunchDomain, uid: UInt32, label: String) -> String {
        "\(domainTarget(domain: domain, uid: uid))/\(label)"
    }

    /// `gui/<uid>` for agents (they run in the user's session), `system` for daemons.
    public static func domainTarget(domain: PerformanceLaunchDomain, uid: UInt32) -> String {
        switch domain {
        case .userAgent, .globalAgent: return "gui/\(uid)"
        case .systemDaemon: return "system"
        }
    }

    /// The commands that turn a launchd item off (`bootout` then `disable`, persists across
    /// restarts) or back on (`enable` then `bootstrap`). Each entry is argv for /bin/launchctl.
    public static func toggleCommands(enable: Bool, domain: PerformanceLaunchDomain, uid: UInt32, label: String,
                                      plistPath: String) -> [[String]] {
        let target = serviceTarget(domain: domain, uid: uid, label: label)
        if enable {
            return [["enable", target], ["bootstrap", domainTarget(domain: domain, uid: uid), plistPath]]
        }
        return [["bootout", target], ["disable", target]]
    }

    /// A launchd label is reverse-DNS-ish text with no spaces or control characters. Anything
    /// else is refused before it reaches a command line.
    public static func isSafeLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 255 else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "._-+@:".unicodeScalars.contains(scalar)
        }
    }
}

// MARK: - Small system readouts

public enum PerformanceSystemParsers {
    /// `scutil --nc list`: any `(Connected)` service means a VPN is up.
    public static func vpnConnected(scutilNCList output: String) -> Bool {
        output.components(separatedBy: "\n").contains { $0.contains("(Connected)") }
    }

    /// `mdutil -s /`: true for "Indexing enabled.", false for "Indexing disabled.", nil otherwise.
    public static func spotlightIndexingEnabled(mdutilStatus output: String) -> Bool? {
        let lower = output.lowercased()
        if lower.contains("indexing enabled") { return true }
        if lower.contains("indexing disabled") || lower.contains("indexing and searching disabled") { return false }
        return nil
    }

    /// Output of `sqlite3 <db> "PRAGMA page_count; PRAGMA freelist_count;"` → (pages, free pages).
    public static func sqlitePageCounts(_ output: String) -> (pageCount: Int, freelistCount: Int)? {
        let numbers = output.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    /// `PRAGMA integrity_check` prints exactly "ok" for a healthy database.
    public static func integrityOK(_ output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok"
    }
}

// MARK: - Mail

public enum PerformanceMailIndex {
    /// `~/Library/Mail/V<n>/MailData/Envelope Index` for the highest `n` that has one.
    public static func locate(home: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                              list: (String) -> [String]? = { try? FileManager.default.contentsOfDirectory(atPath: $0) }) -> String? {
        let mailRoot = (home as NSString).appendingPathComponent("Library/Mail")
        guard let names = list(mailRoot) else { return nil }
        let versions = names.compactMap { name -> (Int, String)? in
            guard name.count >= 2, name.first == "V", let n = Int(name.dropFirst()) else { return nil }
            return (n, name)
        }.sorted { $0.0 > $1.0 }
        for (_, name) in versions {
            let path = (mailRoot as NSString).appendingPathComponent("\(name)/MailData/Envelope Index")
            if fileExists(path) { return path }
        }
        return nil
    }

    /// The database plus its `-wal` and `-shm` side files.
    public static func companionPaths(for path: String) -> [String] {
        [path, path + "-wal", path + "-shm"]
    }
}

// MARK: - Launch Services

public enum PerformanceLaunchServices {
    /// `.app` paths registered in `lsregister -dump` output. Lines look like
    /// `path:      /Applications/Foo.app (0x1a2b)`; the hex suffix is dropped.
    public static func registeredAppPaths(fromDump output: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("path:") else { continue }
            var value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let open = value.range(of: " (0x", options: .backwards), value.hasSuffix(")") {
                value = String(value[..<open.lowerBound])
            }
            guard value.hasPrefix("/"), value.lowercased().hasSuffix(".app") else { continue }
            if seen.insert(value).inserted { out.append(value) }
        }
        return out
    }

    /// Registered apps whose bundle no longer exists, skipping disks that aren't connected
    /// and anything inside the read-only system volume.
    public static func stalePaths(fromDump output: String, fileExists: (String) -> Bool, limit: Int = 400) -> [String] {
        var out: [String] = []
        for path in registeredAppPaths(fromDump: output) {
            if out.count >= limit { break }
            if path.hasPrefix("/System/") { continue }
            if fileExists(path) { continue }
            if PerformanceBrokenCheck.isOnDisconnectedVolume(path, fileExists: fileExists) { continue }
            out.append(path)
        }
        return out
    }
}

// MARK: - Home permissions

public enum PerformanceHomePermissions {
    /// Problems with the ownership or writability of the home folder's key locations
    /// (the conditions under which resetting home permissions is worth it).
    public static func problems(home: String, uid: UInt32, ownerOf: (String) -> UInt32?, isWritable: (String) -> Bool,
                                exists: (String) -> Bool) -> [String] {
        var out: [String] = []
        if let owner = ownerOf(home), owner != uid {
            out.append("Your home folder is owned by another account")
        }
        let checks = ["", "Library", "Library/Preferences", "Library/Application Support", "Library/Caches"]
        for relative in checks {
            let path = relative.isEmpty ? home : (home as NSString).appendingPathComponent(relative)
            guard exists(path) else { continue }
            if !isWritable(path) {
                out.append(relative.isEmpty ? "Your home folder isn't writable" : "~/\(relative) isn't writable")
            } else if !relative.isEmpty, let owner = ownerOf(path), owner != uid {
                out.append("~/\(relative) is owned by another account")
            }
        }
        return out
    }
}

// MARK: - Processes & heavy consumers

public struct PerformanceProcessSample: Sendable, Hashable {
    public var pid: Int32
    public var ppid: Int32
    public var uid: UInt32
    /// `ps` %CPU (can exceed 100 on multi-core Macs).
    public var cpu: Double
    public var residentBytes: Int64
    /// Executable path (or bare name for kernel tasks).
    public var path: String

    public init(pid: Int32, ppid: Int32, uid: UInt32, cpu: Double, residentBytes: Int64, path: String) {
        self.pid = pid
        self.ppid = ppid
        self.uid = uid
        self.cpu = cpu
        self.residentBytes = residentBytes
        self.path = path
    }

    public var name: String {
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? path : base
    }
}

public enum PerformanceProcessParser {
    /// argv for `/bin/ps` matching `parse`.
    public static let psArguments = ["-axo", "pid=,ppid=,uid=,pcpu=,rss=,comm="]

    /// Parses `ps -axo pid=,ppid=,uid=,pcpu=,rss=,comm=`. The command is the rest of the
    /// line, so paths with spaces survive. RSS is in KiB.
    public static func parse(_ output: String) -> [PerformanceProcessSample] {
        var out: [PerformanceProcessSample] = []
        for rawLine in output.components(separatedBy: "\n") {
            var rest = Substring(rawLine)
            var fields: [String] = []
            for _ in 0..<5 {
                rest = rest.drop(while: { $0 == " " || $0 == "\t" })
                guard let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { break }
                fields.append(String(rest[..<end]))
                rest = rest[end...]
            }
            guard fields.count == 5 else { continue }
            let command = rest.trimmingCharacters(in: .whitespaces)
            guard let pid = Int32(fields[0]), let ppid = Int32(fields[1]), let uid = UInt32(fields[2]),
                  let cpu = Double(fields[3].replacingOccurrences(of: ",", with: ".")), let rss = Int64(fields[4]),
                  !command.isEmpty else { continue }
            out.append(PerformanceProcessSample(pid: pid, ppid: ppid, uid: uid, cpu: cpu, residentBytes: rss * 1024, path: command))
        }
        return out
    }
}

/// One row of the heavy-consumers list: an app (with all its helper processes) or a lone process.
public struct PerformanceConsumer: Identifiable, Sendable, Hashable {
    /// App bundle path, or `pid:<n>` for a lone process.
    public var id: String
    public var name: String
    public var appPath: String?
    public var pids: [Int32]
    /// The process to quit (the app's main executable when known).
    public var primaryPID: Int32
    public var cpu: Double
    public var memoryBytes: Int64
    public var ownedByUser: Bool
    /// Why it can't be quit from Spruce (nil = quittable).
    public var protectedReason: String?

    public init(id: String, name: String, appPath: String?, pids: [Int32], primaryPID: Int32, cpu: Double,
                memoryBytes: Int64, ownedByUser: Bool, protectedReason: String?) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.pids = pids
        self.primaryPID = primaryPID
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.ownedByUser = ownedByUser
        self.protectedReason = protectedReason
    }

    public var processCount: Int { pids.count }
    public var isApp: Bool { appPath != nil }
    public var canQuit: Bool { protectedReason == nil }
}

public enum PerformanceConsumerSort: String, CaseIterable, Sendable, Identifiable {
    case cpu
    case memory

    public var id: String { rawValue }
    public var title: String { self == .cpu ? "CPU" : "Memory" }
}

public enum PerformanceConsumerAggregator {
    /// Processes Spruce never offers to quit: macOS would misbehave or relaunch them.
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "Dock", "SystemUIServer", "Finder",
        "ControlCenter", "NotificationCenter", "mds", "mds_stores", "mdworker", "mdworker_shared", "backupd",
        "softwareupdated", "coreaudiod", "cfprefsd", "logd", "opendirectoryd", "securityd", "trustd",
        "fseventsd", "configd", "powerd", "hidd", "bluetoothd", "airportd", "syspolicyd", "tccd", "UserEventAgent",
        "distnoted", "coreservicesd", "lsd", "runningboardd", "sharingd", "Spotlight", "WallpaperAgent",
    ]

    /// Folders whose executables belong to macOS itself.
    static let systemPrefixes = ["/System/Library/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/usr/lib/", "/sbin/", "/bin/",
                                 "/Library/Apple/", "/System/Cryptexes/OS/"]

    /// Groups samples into consumers and sorts them. Helper processes roll up into the
    /// outermost app bundle; everything else is listed per process.
    public static func aggregate(_ samples: [PerformanceProcessSample], userUID: UInt32, ownPID: Int32,
                                 sort: PerformanceConsumerSort, limit: Int = 25) -> [PerformanceConsumer] {
        var apps: [String: [PerformanceProcessSample]] = [:]
        var lone: [PerformanceProcessSample] = []
        for sample in samples where sample.pid > 0 || sample.name == "kernel_task" {
            if let bundle = PerformanceVendor.outermostAppBundle(in: sample.path) {
                apps[bundle, default: []].append(sample)
            } else {
                lone.append(sample)
            }
        }
        var consumers: [PerformanceConsumer] = []
        for (bundle, members) in apps {
            consumers.append(appConsumer(bundle: bundle, members: members, userUID: userUID, ownPID: ownPID))
        }
        for sample in lone {
            consumers.append(PerformanceConsumer(
                id: "pid:\(sample.pid)", name: sample.name, appPath: nil, pids: [sample.pid], primaryPID: sample.pid,
                cpu: sample.cpu, memoryBytes: sample.residentBytes, ownedByUser: sample.uid == userUID,
                protectedReason: protectionReason(name: sample.name, path: sample.path, uid: sample.uid,
                                                  userUID: userUID, pids: [sample.pid], ownPID: ownPID)))
        }
        let sorted = consumers.sorted { lhs, rhs in
            switch sort {
            case .cpu:
                if lhs.cpu != rhs.cpu { return lhs.cpu > rhs.cpu }
                return lhs.memoryBytes > rhs.memoryBytes
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.cpu > rhs.cpu
            }
        }
        return Array(sorted.prefix(limit))
    }

    private static func appConsumer(bundle: String, members: [PerformanceProcessSample], userUID: UInt32,
                                    ownPID: Int32) -> PerformanceConsumer {
        let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
        let mainPrefix = bundle + "/Contents/MacOS/"
        let main = members.first { sample in
            sample.path.hasPrefix(mainPrefix) && !sample.path.dropFirst(mainPrefix.count).contains("/")
        } ?? members.min { $0.pid < $1.pid }!
        let pids = members.map(\.pid).sorted()
        let ownedByUser = members.allSatisfy { $0.uid == userUID }
        var reason = protectionReason(name: name, path: main.path, uid: main.uid, userUID: userUID, pids: pids, ownPID: ownPID)
        if reason == nil && bundle.hasPrefix("/System/Library/") {
            reason = "Part of macOS"
        }
        return PerformanceConsumer(id: bundle, name: name, appPath: bundle, pids: pids, primaryPID: main.pid,
                                   cpu: members.reduce(0) { $0 + $1.cpu },
                                   memoryBytes: members.reduce(0) { $0 + $1.residentBytes },
                                   ownedByUser: ownedByUser, protectedReason: reason)
    }

    static func protectionReason(name: String, path: String, uid: UInt32, userUID: UInt32, pids: [Int32],
                                 ownPID: Int32) -> String? {
        if pids.contains(ownPID) { return "This is Spruce" }
        if protectedNames.contains(name) || name.hasPrefix("mdworker") { return "macOS needs it running" }
        if uid != userUID { return uid == 0 ? "Runs as a system process" : "Belongs to another account" }
        if PerformanceVendor.outermostAppBundle(in: path) == nil,
           systemPrefixes.contains(where: { path.hasPrefix($0) }) {
            return "Part of macOS"
        }
        return nil
    }

    /// Whether a consumer deserves a "heavy" badge.
    public static func isHeavy(_ consumer: PerformanceConsumer, totalMemory: Int64) -> (cpu: Bool, memory: Bool) {
        let cpuHeavy = consumer.cpu >= 50
        let memoryHeavy = consumer.memoryBytes >= 1_500_000_000
            || (totalMemory > 0 && Double(consumer.memoryBytes) / Double(totalMemory) >= 0.10)
        return (cpuHeavy, memoryHeavy)
    }
}
