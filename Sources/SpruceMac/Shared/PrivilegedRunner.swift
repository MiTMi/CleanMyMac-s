import AppKit
import Foundation
import SpruceCore

/// Runs the few operations that need root, via a single macOS administrator prompt
/// (`do shell script … with administrator privileges`).
///
/// Design rules (learned from the 2018 CleanMyMac helper vulnerabilities):
/// * No persistent root daemon — nothing stays installed that another process could abuse.
/// * Only fixed commands from `PrivilegedCommand`, or allowlisted executables whose
///   arguments pass a per-tool validator; every argument is single-quote escaped.
/// * File operations are re-validated *inside* the root script: the user may take many
///   seconds to approve the prompt, so the script re-checks, by device and inode, that
///   it is in the very directory and acting on the very item that `PathGuard` approved,
///   and then only touches the item by its base name. A symlink swapped into a path
///   while the prompt is open cannot redirect root anywhere else.
/// * Root never changes the owner or permissions of existing files.
/// * One prompt per batch: commands are joined into one script.
public final class PrivilegedRunner: @unchecked Sendable {
    public static let shared = PrivilegedRunner()

    /// Fixed, audited administrator commands.
    public enum PrivilegedCommand: String, CaseIterable, Sendable {
        case flushDNS
        case purgeMemory
        case reindexSpotlight
        case runPeriodicScripts
        case thinTimeMachineSnapshots
        case clearFontCaches
        case repairHomePermissions

        /// The exact shell command executed as root.
        public var shell: String {
            switch self {
            case .flushDNS:
                return "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
            case .purgeMemory:
                return "/usr/sbin/purge"
            case .reindexSpotlight:
                return "/usr/bin/mdutil -E /"
            case .runPeriodicScripts:
                return "if [ -x /usr/sbin/periodic ]; then /usr/sbin/periodic daily weekly monthly; fi"
            case .thinTimeMachineSnapshots:
                // Ask the system to reclaim up to 1 TB of purgeable snapshot space, urgency 4 (highest).
                return "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
            case .clearFontCaches:
                return "/usr/bin/atsutil databases -remove"
            case .repairHomePermissions:
                return "/usr/sbin/diskutil resetUserPermissions / \(getuid())"
            }
        }
    }

    public init() {}

    /// Runs commands as root with one prompt. Returns combined output.
    @discardableResult
    public func run(_ commands: [PrivilegedCommand]) async throws -> String {
        guard !commands.isEmpty else { return "" }
        let script = commands.map { "(\($0.shell))" }.joined(separator: "; ")
        return try await runAsAdministrator(script)
    }

    /// Executables that may be run as root with caller-supplied arguments. Each one also
    /// has an argument validator (`refusal(for:)`) that only lets its harmless or
    /// intended verbs through.
    public static let allowedExecutables: Set<String> = [
        "/bin/launchctl", "/usr/bin/tmutil", "/usr/sbin/sfltool", "/usr/bin/profiles",
        "/usr/bin/mdutil", "/usr/bin/killall", "/bin/kill", "/usr/sbin/purge",
        "/usr/bin/dscacheutil", "/usr/bin/pkgutil", "/usr/bin/log", "/usr/bin/tccutil",
    ]

    /// One root command invocation.
    public struct Invocation: Sendable {
        public var executable: String
        public var arguments: [String]
        public init(_ executable: String, _ arguments: [String] = []) {
            self.executable = executable
            self.arguments = arguments
        }
    }

    /// Runs allowlisted executables as root, all in one administrator prompt.
    /// Each invocation's exit status is ignored individually (`; true`) so one failure
    /// does not prevent the rest; inspect state afterwards to confirm the effect.
    /// Throws without prompting when any invocation fails its validator.
    @discardableResult
    public func run(_ invocations: [Invocation]) async throws -> String {
        guard !invocations.isEmpty else { return "" }
        var parts: [String] = []
        for inv in invocations {
            if let reason = Self.refusal(for: inv) {
                throw SpruceError.unsupported(reason)
            }
            let command = ([inv.executable] + inv.arguments).map(Self.shellQuote).joined(separator: " ")
            parts.append("(\(command); true)")
        }
        return try await runAsAdministrator(parts.joined(separator: "; "))
    }

    // MARK: Files

    /// Permanently removes paths that need root. Every path must pass
    /// `PathGuard.checkPrivileged` with `.remove`; the root script then re-checks, by
    /// identity, the parent folder and the item before removing it by name.
    /// - Returns: the paths that were removed.
    @discardableResult
    public func removePaths(_ paths: [String], guardian: PathGuard = PathGuard(),
                            options: PathGuard.Options = []) async throws -> Set<String> {
        var pinned: [Pinned] = []
        for path in paths {
            let verdict = guardian.checkPrivileged(path, method: .remove, options: options)
            guard verdict.isAllowed else { throw SpruceError.blockedPath(path) }
            // Already gone: nothing to do.
            guard let pin = Self.pin(path, index: pinned.count) else { continue }
            pinned.append(pin)
        }
        guard !pinned.isEmpty else { return [] }
        let script = Self.removeScript(pinned)
        let output = try await runAsAdministrator(script)
        let ok = Self.markers("SPRUCE-OK", in: output)
        var removed = Set<String>()
        for pin in pinned where ok.contains(pin.index) && FileWalker.entry(at: pin.path) == nil {
            removed.insert(pin.path)
        }
        return removed
    }

    /// Moves root-owned items into the current user's Trash with one administrator
    /// prompt. The items keep their owner and permissions: they go into a new folder that
    /// root creates inside the Trash ("Spruce Admin Trash …"), so nothing the user can
    /// write to is ever handed to `chown`, and existing Trash entries are never touched.
    /// Emptying that folder needs the administrator again (Finder or Spruce asks).
    /// Every path must pass `PathGuard.checkPrivileged` with `.trash` and `options`, and be
    /// on the same disk as the Trash.
    /// - Returns: the Trash location of each moved path.
    @discardableResult
    public func trashPaths(_ paths: [String], guardian: PathGuard = PathGuard(),
                           options: PathGuard.Options = []) async throws -> [String: String] {
        let trashPath = (NSHomeDirectory() as NSString).appendingPathComponent(".Trash")
        if FileWalker.entry(at: trashPath) == nil {
            try? FileManager.default.createDirectory(atPath: trashPath, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
        }
        guard let trash = Self.resolvedDirectory(trashPath), let trashID = Self.identity(of: trash, followLink: true),
              trashID.isDirectory else {
            throw SpruceError.commandFailed("Your Trash folder couldn't be found.")
        }
        var pinned: [Pinned] = []
        var destinations: [Int: String] = [:]
        var taken = Set<String>()
        for path in paths {
            let verdict = guardian.checkPrivileged(path, method: .trash, options: options)
            guard verdict.isAllowed else { throw SpruceError.blockedPath(path) }
            guard let pin = Self.pin(path, index: pinned.count) else { continue }
            // A move to another disk would be a copy made by root; leave those alone.
            guard pin.device == trashID.device else { continue }
            pinned.append(pin)
            destinations[pin.index] = Self.uniqueName(pin.name, taken: &taken)
        }
        guard !pinned.isEmpty else { return [:] }
        let script = Self.trashScript(pinned, destinations: destinations, trash: trash, trashID: trashID.id)
        let output = try await runAsAdministrator(script)
        let lines = Self.lines(output)
        if lines.contains("SPRUCE-ERR trash") {
            throw SpruceError.commandFailed("Your Trash changed while waiting for approval, so nothing was moved.")
        }
        guard !lines.contains("SPRUCE-ERR stage"),
              let stage = lines.first(where: { $0.hasPrefix("SPRUCE-STAGE ") })?.dropFirst("SPRUCE-STAGE ".count),
              !stage.isEmpty else {
            throw SpruceError.commandFailed("Spruce couldn't prepare a folder in your Trash.")
        }
        let stageFolder = (trash as NSString).appendingPathComponent(String(stage))
        let ok = Self.markers("SPRUCE-OK", in: output)
        var moved: [String: String] = [:]
        for pin in pinned where ok.contains(pin.index) {
            guard let name = destinations[pin.index] else { continue }
            let destination = (stageFolder as NSString).appendingPathComponent(name)
            if FileWalker.entry(at: pin.path) == nil && FileWalker.entry(at: destination) != nil {
                moved[pin.path] = destination
            }
        }
        return moved
    }

    /// Single-quote shell escaping: 'it'\''s'.
    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Pinning

    /// What a root script expects to find, by identity ("<device>:<inode>", as printed by
    /// `/usr/bin/stat -f %d:%i`).
    struct Pinned {
        let index: Int
        /// The path as the caller gave it.
        let path: String
        /// Its parent folder with symlinks resolved.
        let parent: String
        let name: String
        let parentID: String
        let itemID: String
        let device: String
    }

    struct Identity {
        let id: String
        let device: String
        let isDirectory: Bool
    }

    static func identity(of path: String, followLink: Bool) -> Identity? {
        var st = stat()
        let rc: Int32
        if followLink {
            rc = stat(path, &st)
        } else {
            rc = lstat(path, &st)
        }
        guard rc == 0 else { return nil }
        let device = String(UInt64(truncatingIfNeeded: Int64(st.st_dev)))
        let isDirectory = UInt32(st.st_mode) & UInt32(S_IFMT) == UInt32(S_IFDIR)
        return Identity(id: "\(device):\(UInt64(st.st_ino))", device: device, isDirectory: isDirectory)
    }

    static func resolvedDirectory(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Identities of `path` and its parent, or nil when the item no longer exists.
    static func pin(_ path: String, index: Int) -> Pinned? {
        let standardized = (path as NSString).standardizingPath
        let name = (standardized as NSString).lastPathComponent
        guard !name.isEmpty, name != "/", name != ".", name != "..",
              let parent = resolvedDirectory((standardized as NSString).deletingLastPathComponent),
              let parentID = identity(of: parent, followLink: true), parentID.isDirectory else { return nil }
        let itemPath = (parent as NSString).appendingPathComponent(name)
        guard let itemID = identity(of: itemPath, followLink: false) else { return nil }
        return Pinned(index: index, path: path, parent: parent, name: name, parentID: parentID.id,
                      itemID: itemID.id, device: itemID.device)
    }

    /// `name`, or `name 2`, `name 3`… so items in one batch never collide (case-insensitive).
    static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        var candidate = name
        var counter = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while taken.contains(candidate.lowercased()) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        taken.insert(candidate.lowercased())
        return candidate
    }

    /// `cd` into the pinned parent and prove it is the same folder.
    private static func enterParent(_ pin: Pinned) -> String {
        "cd -P -- \(shellQuote(pin.parent)) && [ \"$(/usr/bin/stat -f %d:%i .)\" = \(shellQuote(pin.parentID)) ]"
    }

    /// Prove the item in the current folder is the one that was checked.
    private static func sameItem(_ pin: Pinned) -> String {
        "[ \"$(/usr/bin/stat -f %d:%i -- \(shellQuote("./" + pin.name)))\" = \(shellQuote(pin.itemID)) ]"
    }

    static func removeScript(_ pinned: [Pinned]) -> String {
        let parts = pinned.map { pin in
            "( \(enterParent(pin)) && \(sameItem(pin)) && /bin/rm -rf -- \(shellQuote("./" + pin.name)) " +
            "&& echo 'SPRUCE-OK \(pin.index)' ) 2>/dev/null || echo 'SPRUCE-SKIP \(pin.index)'"
        }
        return parts.joined(separator: "; ") + "; true"
    }

    /// 1. Pin the Trash, create a fresh root-owned folder in it and pin that too.
    /// 2. For each item: in its pinned parent, rename it to an unguessable name; then move
    ///    that name into the pinned staging folder (destination relative to it). If the
    ///    second step fails, rename it back.
    /// 3. Remove the staging folder again if nothing arrived.
    static func trashScript(_ pinned: [Pinned], destinations: [Int: String], trash: String, trashID: String) -> String {
        var s = "umask 022; "
        s += "cd -P -- \(shellQuote(trash)) 2>/dev/null && [ \"$(/usr/bin/stat -f %d:%i .)\" = \(shellQuote(trashID)) ] "
        s += "|| { echo 'SPRUCE-ERR trash'; exit 0; }; "
        s += "S=$(/usr/bin/mktemp -d './Spruce Admin Trash XXXXXX') || { echo 'SPRUCE-ERR stage'; exit 0; }; "
        s += "cd -P -- \"$S\" && [ \"$(/usr/bin/stat -f %u .)\" = '0' ] && [ \"$(/usr/bin/stat -f %d:%i ..)\" = \(shellQuote(trashID)) ] "
        s += "|| { echo 'SPRUCE-ERR stage'; exit 0; }; "
        s += "/bin/chmod 755 . ; echo \"SPRUCE-STAGE ${S#./}\"; "
        for pin in pinned {
            guard let destination = destinations[pin.index] else { continue }
            let hidden = ".spruce-" + UUID().uuidString
            let hide = "( \(enterParent(pin)) && \(sameItem(pin)) && /bin/mv -- \(shellQuote("./" + pin.name)) \(shellQuote("./" + hidden)) ) 2>/dev/null"
            let bring = "/bin/mv -- \(shellQuote((pin.parent as NSString).appendingPathComponent(hidden))) \(shellQuote("./" + destination)) 2>/dev/null"
            let restore = "( \(enterParent(pin)) && /bin/mv -- \(shellQuote("./" + hidden)) \(shellQuote("./" + pin.name)) ) 2>/dev/null"
            s += "if \(hide); then if \(bring); then echo 'SPRUCE-OK \(pin.index)'; else \(restore); echo 'SPRUCE-SKIP \(pin.index)'; fi; "
            s += "else echo 'SPRUCE-SKIP \(pin.index)'; fi; "
        }
        s += "cd -P .. 2>/dev/null && /bin/rmdir -- \"${S#./}\" 2>/dev/null; true"
        return s
    }

    static func lines(_ output: String) -> [String] {
        output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Indexes printed as "<prefix> <index>".
    static func markers(_ prefix: String, in output: String) -> Set<Int> {
        Set(lines(output).compactMap { line -> Int? in
            guard line.hasPrefix(prefix + " ") else { return nil }
            return Int(line.dropFirst(prefix.count + 1))
        })
    }

    // MARK: Argument validation

    /// Why `invocation` may not run as root, or nil when it may.
    public static func refusal(for invocation: Invocation) -> String? {
        let tool = invocation.executable
        guard allowedExecutables.contains(tool) else { return "\(tool) is not allowed to run as administrator" }
        let args = invocation.arguments
        if args.contains(where: { $0.isEmpty || $0.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) }) {
            return "Invalid argument for \(tool)"
        }
        let refused = "\((tool as NSString).lastPathComponent) \(args.joined(separator: " ")) is not allowed as administrator"
        let verb = args.first ?? ""
        switch tool {
        case "/bin/launchctl":
            return launchctlRefusal(args).map { "\(refused): \($0)" }
        case "/usr/bin/tmutil":
            return ["thinlocalsnapshots", "deletelocalsnapshots", "listlocalsnapshots", "listlocalsnapshotdates"]
                .contains(verb) ? nil : refused
        case "/usr/sbin/sfltool":
            return args == ["dumpbtm"] ? nil : refused
        case "/usr/bin/profiles":
            return ["list", "show", "status"].contains(verb) ? nil : refused
        case "/usr/bin/mdutil":
            return mdutilAllowed(args) ? nil : refused
        case "/usr/bin/killall":
            return killallAllowed(args) ? nil : refused
        case "/bin/kill":
            return killAllowed(args) ? nil : refused
        case "/usr/sbin/purge":
            return args.isEmpty ? nil : refused
        case "/usr/bin/dscacheutil":
            return args == ["-flushcache"] ? nil : refused
        case "/usr/bin/pkgutil":
            return pkgutilAllowed(args) ? nil : refused
        case "/usr/bin/log":
            return ["show", "stats"].contains(verb) ? nil : refused
        case "/usr/bin/tccutil":
            return tccutilAllowed(args) ? nil : refused
        default:
            return refused
        }
    }

    private static func isLabel(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 255 && s.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "._-+@:".unicodeScalars.contains($0)
        }
    }

    /// Jobs that macOS itself ships (their plists live on the sealed system volume).
    private static func isAppleSystemJob(_ label: String) -> Bool {
        let fm = FileManager.default
        return ["/System/Library/LaunchDaemons", "/System/Library/LaunchAgents"].contains {
            fm.fileExists(atPath: "\($0)/\(label).plist")
        }
    }

    /// launchctl: only job management verbs, never a job macOS ships, never a plist in /System.
    static func launchctlRefusal(_ args: [String]) -> String? {
        let verbs: Set<String> = ["bootout", "bootstrap", "enable", "disable", "load", "unload", "remove", "print", "list"]
        guard let verb = args.first, verbs.contains(verb) else { return "unsupported launchctl command" }
        for arg in args.dropFirst() {
            if arg.hasPrefix("-") {
                guard arg == "-w" || arg == "-F" else { return "unsupported option \(arg)" }
                continue
            }
            if arg.hasPrefix("/") {
                let key = PathGuard.key((arg as NSString).standardizingPath)
                guard !key.hasPrefix("/system/"), key.hasSuffix(".plist") else { return "not a third-party job file" }
                continue
            }
            let parts = arg.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var label: String?
            switch parts[0] {
            case "system":
                guard parts.count <= 2 else { return "bad target \(arg)" }
                label = parts.count == 2 ? parts[1] : nil
            case "gui", "user":
                guard parts.count >= 2, parts.count <= 3, UInt32(parts[1]) != nil else { return "bad target \(arg)" }
                label = parts.count == 3 ? parts[2] : nil
            default:
                guard parts.count == 1 else { return "bad target \(arg)" }
                label = arg
            }
            if let label {
                guard isLabel(label) else { return "bad label \(label)" }
                if isAppleSystemJob(label) { return "\(label) is part of macOS" }
            }
        }
        return nil
    }

    private static func mdutilAllowed(_ args: [String]) -> Bool {
        guard let flag = args.first, let volume = args.last, volume.hasPrefix("/") else { return false }
        switch flag {
        case "-s", "-E": return args.count == 2
        case "-i": return args.count == 3 && (args[1] == "on" || args[1] == "off")
        default: return false
        }
    }

    private static let signalFlags: Set<String> = ["-HUP", "-TERM", "-INT", "-KILL", "-1", "-2", "-9", "-15"]

    private static func killallAllowed(_ args: [String]) -> Bool {
        let restartable: Set<String> = ["mDNSResponder", "mDNSResponderHelper", "Dock", "Finder", "SystemUIServer",
                                        "cfprefsd", "coreaudiod", "iconservicesagent", "iconservicesd", "quicklookd",
                                        "QuickLookUIService", "lsd", "fontd"]
        var rest = args[...]
        if let first = rest.first, signalFlags.contains(first) { rest = rest.dropFirst() }
        return rest.count == 1 && restartable.contains(rest.first!)
    }

    private static func killAllowed(_ args: [String]) -> Bool {
        var rest = args[...]
        if let first = rest.first, signalFlags.contains(first) { rest = rest.dropFirst() }
        let own = Int32(ProcessInfo.processInfo.processIdentifier)
        return !rest.isEmpty && rest.allSatisfy { arg in
            guard let pid = Int32(arg) else { return false }
            return pid > 1 && pid != own
        }
    }

    private static func pkgutilAllowed(_ args: [String]) -> Bool {
        guard let verb = args.first else { return false }
        if verb == "--forget" {
            return args.count == 2 && isLabel(args[1]) && !args[1].lowercased().hasPrefix("com.apple.")
        }
        return ["--pkgs", "--pkg-info", "--pkg-info-plist", "--files", "--export-plist"].contains(verb)
    }

    /// Only `tccutil reset <Service> <bundle id>` for one third-party app; never a blanket reset.
    private static func tccutilAllowed(_ args: [String]) -> Bool {
        guard args.count == 3, args[0] == "reset" else { return false }
        let service = args[1]
        let bundleID = args[2]
        return !service.isEmpty && service.lowercased() != "all"
            && service.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            && isLabel(bundleID) && !bundleID.lowercased().hasPrefix("com.apple.")
    }

    // MARK: Running

    @discardableResult
    private func runAsAdministrator(_ shellScript: String) async throws -> String {
        // Stop pressed before the prompt appeared: don't ask at all.
        if Task.isCancelled { throw SpruceError.cancelled }
        let escaped = shellScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        switch await AppleScriptExecutor.shared.run(source) {
        case .success(let output):
            return output
        case .failure(let code, let message):
            if code == -128 { throw SpruceError.cancelled }
            throw SpruceError.commandFailed(message.isEmpty ? "Administrator command failed." : message)
        }
    }
}

/// Runs a non-privileged command-line tool and captures its output.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
    }

    /// Executes `executable` with `arguments` (no shell involved, so no injection).
    public static func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 60) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(status: -1, stdout: "", stderr: error.localizedDescription))
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                // Drain stderr concurrently so a chatty tool cannot fill the pipe and deadlock.
                let errBox = DataBox()
                let errGroup = DispatchGroup()
                errGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    errGroup.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                errGroup.wait()
                let errData = errBox.data
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData, as: UTF8.self)
                ))
            }
        }
    }
}

/// Holds data written by one thread and read by another after a `DispatchGroup.wait()`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
