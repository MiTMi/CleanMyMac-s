import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A parsed launchd property list (launch agent or daemon).
public struct ProtectionLaunchItem: Sendable, Hashable {
    public var plistPath: String
    public var label: String?
    /// `Program`, or the first element of `ProgramArguments`.
    public var program: String?
    /// Full `ProgramArguments` (empty when only `Program` is set).
    public var arguments: [String]
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var environment: [String: String]
    /// `Disabled` key set in the plist itself.
    public var isDisabled: Bool
    /// False when the file is not a readable property list (e.g. compiled code disguised as a plist).
    public var isValidPlist: Bool
    public var domain: ProtectionLaunchDomain
    public var kind: ProtectionItemKind

    public init(plistPath: String, label: String?, program: String?, arguments: [String], runAtLoad: Bool,
                keepAlive: Bool, environment: [String: String], isDisabled: Bool, isValidPlist: Bool,
                domain: ProtectionLaunchDomain, kind: ProtectionItemKind) {
        self.plistPath = plistPath
        self.label = label
        self.program = program
        self.arguments = arguments
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.environment = environment
        self.isDisabled = isDisabled
        self.isValidPlist = isValidPlist
        self.domain = domain
        self.kind = kind
    }

    /// Parses a launchd plist. Never throws: unreadable files come back with `isValidPlist == false`.
    public static func parse(path: String, domain: ProtectionLaunchDomain, kind: ProtectionItemKind, home: String) -> ProtectionLaunchItem {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any] else {
            return ProtectionLaunchItem(plistPath: path, label: nil, program: nil, arguments: [], runAtLoad: false,
                                        keepAlive: false, environment: [:], isDisabled: false, isValidPlist: false,
                                        domain: domain, kind: kind)
        }
        let arguments = (dict["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
        let rawProgram = (dict["Program"] as? String) ?? arguments.first
        let program = rawProgram.map { Self.expand($0, home: home) }
        let keepAlive: Bool
        if let flag = dict["KeepAlive"] as? Bool {
            keepAlive = flag
        } else {
            keepAlive = dict["KeepAlive"] is [String: Any]
        }
        var environment: [String: String] = [:]
        if let env = dict["EnvironmentVariables"] as? [String: Any] {
            for (key, value) in env {
                if let s = value as? String { environment[key] = s }
            }
        }
        return ProtectionLaunchItem(
            plistPath: path,
            label: dict["Label"] as? String,
            program: program,
            arguments: arguments.map { Self.expand($0, home: home) },
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: keepAlive,
            environment: environment,
            isDisabled: dict["Disabled"] as? Bool ?? false,
            isValidPlist: true,
            domain: domain,
            kind: kind
        )
    }

    /// The label, or the plist file name without extension.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        return ((plistPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Script interpreters whose *argument* is the real payload.
    public static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish", "osascript", "python", "python2", "python3",
        "perl", "ruby", "node", "php", "tclsh", "expect", "swift",
    ]

    /// Interpreter name when the job runs a script (`/bin/bash script.sh`, `/usr/bin/env python3 x.py`).
    public var interpreter: String? {
        let parts = commandLine
        guard let first = parts.first else { return nil }
        let name = (first as NSString).lastPathComponent
        if name == "env" {
            guard let next = parts.dropFirst().first(where: { !$0.hasPrefix("-") && !$0.contains("=") }) else { return nil }
            let nextName = (next as NSString).lastPathComponent
            return Self.interpreters.contains(nextName) ? nextName : nil
        }
        return Self.interpreters.contains(Self.versionStripped(name)) ? Self.versionStripped(name) : nil
    }

    /// Inline code passed with `-c` / `-e` to an interpreter.
    public var inlineCommand: String? {
        guard interpreter != nil else { return nil }
        let parts = commandLine
        for (index, arg) in parts.enumerated() where arg == "-c" || arg == "-e" || arg == "-lc" || arg == "-ic" {
            if index + 1 < parts.count { return parts[index + 1] }
        }
        return nil
    }

    /// The file that actually runs: the program itself, or the script handed to an interpreter.
    public var payloadPath: String? {
        let parts = commandLine
        guard let first = parts.first else { return nil }
        guard interpreter != nil else { return first.hasPrefix("/") ? first : nil }
        if inlineCommand != nil { return nil }
        var skipNext = false
        var sawInterpreter = (first as NSString).lastPathComponent != "env"
        for arg in parts.dropFirst() {
            if skipNext { skipNext = false; continue }
            if !sawInterpreter {
                if !arg.hasPrefix("-") && !arg.contains("=") { sawInterpreter = true }
                continue
            }
            if arg == "-l" || arg == "-i" || arg.hasPrefix("--") { continue }
            if arg.hasPrefix("-") { continue }
            if arg.hasPrefix("/") { return arg }
            return nil
        }
        return nil
    }

    /// Program + arguments as launchd would run them.
    public var commandLine: [String] {
        if !arguments.isEmpty {
            if let program, !arguments.isEmpty, arguments.first != program {
                // `Program` overrides argv[0].
                return [program] + arguments.dropFirst()
            }
            return arguments
        }
        return program.map { [$0] } ?? []
    }

    /// The whole command line as one string (for pattern checks).
    public var commandText: String { commandLine.joined(separator: " ") }

    static func expand(_ s: String, home: String) -> String {
        if s == "~" { return home }
        if s.hasPrefix("~/") { return home + s.dropFirst(1) }
        return s
    }

    static func versionStripped(_ name: String) -> String {
        // python3.11 → python3, ruby2.6 → ruby
        if let dot = name.firstIndex(of: "."), name[name.index(after: dot)...].allSatisfy({ $0.isNumber || $0 == "." }) {
            return String(name[..<dot])
        }
        return name
    }
}

/// Reads the first bytes of a file to tell programs and scripts from data.
public enum ProtectionFileSniffer {
    public enum FileType: Sendable, Equatable {
        case machO
        case script(interpreter: String)
        case appleScript
        case diskImage
        case installerPackage
        case archive
        case other
    }

    /// Classifies a regular file by magic number (and extension for containers).
    public static func type(of path: String) -> FileType {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg": return .diskImage
        case "pkg", "mpkg": return .installerPackage
        case "zip", "tar", "tgz", "gz", "xz", "bz2", "7z", "rar": return .archive
        default: break
        }
        guard let data = readPrefix(of: path, limit: 256), data.count >= 4 else { return .other }
        let b = [UInt8](data.prefix(4))
        let magic = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        let machO: Set<UInt32> = [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA]
        if machO.contains(magic) {
            // 0xCAFEBABE is also a Java class file; universal binaries have a small arch count.
            if magic == 0xCAFEBABE, data.count >= 8 {
                let count = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
                if count == 0 || count > 20 { return .other }
            }
            return .machO
        }
        if b[0] == 0x23, b[1] == 0x21 { // "#!"
            let line = String(decoding: data.prefix { $0 != 0x0A }, as: UTF8.self)
            let interpreterPath = line.dropFirst(2).trimmingCharacters(in: .whitespaces).split(separator: " ")
            var name = interpreterPath.first.map { (String($0) as NSString).lastPathComponent } ?? "sh"
            if name == "env", interpreterPath.count > 1 { name = String(interpreterPath[1]) }
            return .script(interpreter: name)
        }
        if data.starts(with: Array("FasdUAS".utf8)) { return .appleScript }
        return .other
    }

    /// True for Mach-O binaries, shebang scripts and compiled AppleScripts.
    public static func isCode(_ type: FileType) -> Bool {
        switch type {
        case .machO, .script, .appleScript: return true
        default: return false
        }
    }

    /// True for code, or any file with an execute bit.
    public static func isExecutable(path: String, type: FileType) -> Bool {
        isCode(type) || FileManager.default.isExecutableFile(atPath: path)
    }

    /// Reads up to `limit` bytes of a small text file (scripts, crontabs, plists).
    public static func text(of path: String, limit: Int = 256 * 1024) -> String? {
        guard let data = readPrefix(of: path, limit: limit) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Up to `limit` bytes from the start of a file; nil when it can't be opened or read.
    ///
    /// Uses the throwing `FileHandle.read(upToCount:)`: the legacy `readData(ofLength:)`
    /// raises an Objective-C exception on a read error (a disk I/O error, or a cloud file
    /// that can't be downloaded), which would take the whole app down mid-scan.
    public static func readPrefix(of path: String, limit: Int) -> Data? {
        guard limit > 0, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            return try handle.read(upToCount: limit) ?? Data()
        } catch {
            return nil
        }
    }

    // MARK: Cloud placeholders

    /// `SF_DATALESS` (`<sys/stat.h>`): the item's contents live only in the cloud (iCloud
    /// Drive with Optimise Mac Storage, File Provider apps).
    public static let datalessFlag: UInt32 = 0x4000_0000

    /// True for an online-only file or folder. Opening, hashing or signature-checking one
    /// would download it, so the malware scanner never reads such items. Only partially
    /// allocated files can be placeholders, so most files cost no extra system call.
    public static func isCloudPlaceholder(_ entry: FileEntry) -> Bool {
        if entry.isRegularFile {
            guard entry.logicalSize > 0, entry.allocatedSize < entry.logicalSize else { return false }
        } else if !entry.isDirectory {
            return false
        }
        guard let flags = statusFlags(of: entry.path) else { return false }
        return flags & datalessFlag != 0
    }

    /// `st_flags` of `path` (without following symlinks); nil where the platform has none.
    static func statusFlags(of path: String) -> UInt32? {
        #if canImport(Darwin)
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return UInt32(st.st_flags)
        #else
        return nil
        #endif
    }
}

/// Reads an application bundle's identity from its Info.plist.
public struct ProtectionBundleInfo: Sendable, Hashable {
    public var path: String
    public var bundleID: String?
    public var name: String
    public var executablePath: String?

    public init(path: String, bundleID: String?, name: String, executablePath: String?) {
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.executablePath = executablePath
    }

    public static func read(bundlePath: String) -> ProtectionBundleInfo {
        let name = (bundlePath as NSString).lastPathComponent
        let candidates = [bundlePath + "/Contents/Info.plist", bundlePath + "/Info.plist"]
        for plist in candidates {
            guard let data = FileManager.default.contents(atPath: plist),
                  let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dict = object as? [String: Any] else { continue }
            let bundleID = dict["CFBundleIdentifier"] as? String
            var executable: String?
            if let exe = dict["CFBundleExecutable"] as? String, !exe.isEmpty {
                let macOS = plist.hasSuffix("/Contents/Info.plist") ? bundlePath + "/Contents/MacOS/" + exe : bundlePath + "/" + exe
                executable = macOS
            }
            return ProtectionBundleInfo(path: bundlePath, bundleID: bundleID, name: name, executablePath: executable)
        }
        return ProtectionBundleInfo(path: bundlePath, bundleID: nil, name: name, executablePath: nil)
    }
}
