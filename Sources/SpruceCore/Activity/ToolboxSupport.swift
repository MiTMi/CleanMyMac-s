import Foundation

// MARK: - Screen Cleaning timing

/// Hold-to-exit gesture used by Screen Cleaning: a key (Esc) or button held down
/// continuously for `duration` seconds. Key auto-repeat keeps the original start.
public struct ToolboxHoldTracker: Sendable, Equatable {
    public var duration: TimeInterval
    public private(set) var pressedAt: Date?

    public init(duration: TimeInterval = 2) {
        self.duration = max(0.1, duration)
    }

    public var isPressed: Bool { pressedAt != nil }

    /// Starts the hold (ignored while already held, so auto-repeat doesn't restart it).
    public mutating func press(at date: Date) {
        if pressedAt == nil { pressedAt = date }
    }

    /// Letting go before the duration resets the gesture.
    public mutating func release() {
        pressedAt = nil
    }

    /// 0...1 while held, 0 when not held.
    public func progress(at date: Date) -> Double {
        guard let pressedAt else { return 0 }
        return min(1, max(0, date.timeIntervalSince(pressedAt) / duration))
    }

    public func isComplete(at date: Date) -> Bool {
        progress(at: date) >= 1
    }
}

/// Timing of one Screen Cleaning session: a hard time limit (input is never locked for
/// long, even if the exit gesture fails) and the fade of the on-screen instructions.
public struct ToolboxCleaningClock: Sendable, Equatable {
    public var startedAt: Date
    /// The session ends by itself after this long.
    public var limit: TimeInterval
    /// Instructions stay fully visible this long, then dim so they don't hide smudges.
    public var instructionsVisibleFor: TimeInterval

    public init(startedAt: Date, limit: TimeInterval = 600, instructionsVisibleFor: TimeInterval = 5) {
        self.startedAt = startedAt
        self.limit = max(10, limit)
        self.instructionsVisibleFor = instructionsVisibleFor
    }

    public func elapsed(at date: Date) -> TimeInterval { max(0, date.timeIntervalSince(startedAt)) }

    public func remaining(at date: Date) -> TimeInterval { max(0, limit - elapsed(at: date)) }

    public func isExpired(at date: Date) -> Bool { remaining(at: date) <= 0 }

    /// 1 for the first seconds, then a one-second fade down to 0.15.
    public func instructionOpacity(at date: Date) -> Double {
        let t = elapsed(at: date) - instructionsVisibleFor
        if t <= 0 { return 1 }
        return max(0.15, 1 - t * 0.85)
    }

    /// "9:41" style countdown.
    public static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let s = total % 60
        return "\(total / 60):" + (s < 10 ? "0\(s)" : "\(s)")
    }
}

// MARK: - Shredder planning

/// A regular file the Shredder will overwrite.
public struct ToolboxShredFile: Equatable, Sendable {
    public var path: String
    public var inode: UInt64
    /// Logical size (bytes written when overwriting).
    public var size: Int64

    public init(path: String, inode: UInt64, size: Int64) {
        self.path = path
        self.inode = inode
        self.size = size
    }
}

/// What shredding one chosen item involves, and whether it is allowed.
///
/// Refused when: the item is a symlink, a protected location or app bundle (PathGuard),
/// contains anything PathGuard protects (an app, a keychain…), has a file with other
/// hard links (overwriting would destroy the other copy too), or has files or a parent
/// folder you can't write to.
public struct ToolboxShredPlan: Identifiable, Equatable, Sendable {
    public var root: String
    public var id: String { root }
    public var isDirectory: Bool
    /// Regular files to overwrite.
    public var files: [ToolboxShredFile]
    /// Files, folders and links inside (1 for a single file).
    public var itemCount: Int
    public var logicalBytes: Int64
    /// Space given back once removed.
    public var allocatedBytes: Int64
    /// Why the item can't be shredded (nil when it can).
    public var problem: String?

    public init(root: String, isDirectory: Bool = false, files: [ToolboxShredFile] = [], itemCount: Int = 0,
                logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0, problem: String? = nil) {
        self.root = root
        self.isDirectory = isDirectory
        self.files = files
        self.itemCount = itemCount
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.problem = problem
    }

    public var name: String { (root as NSString).lastPathComponent }
    public var canShred: Bool { problem == nil }

    /// Most entries examined inside one folder.
    public static let entryLimit = 250_000

    /// Builds the plan for one chosen path.
    public static func make(root rawRoot: String, guardian: PathGuard = PathGuard(),
                            fileManager: FileManager = .default) -> ToolboxShredPlan {
        // Not `standardizingPath`: on some platforms it resolves symlinks, and a chosen
        // link must be recognised as a link (never followed).
        var root = rawRoot
        while root.count > 1 && root.hasSuffix("/") { root.removeLast() }
        var plan = ToolboxShredPlan(root: root)
        guard let entry = FileWalker.entry(at: root) else {
            plan.problem = "It no longer exists."
            return plan
        }
        plan.isDirectory = entry.isDirectory
        if entry.isSymlink {
            plan.problem = "This is a link to another item. Shred the original instead."
            return plan
        }
        let verdict = guardian.check(root, method: .trash)
        if let reason = verdict.reason {
            plan.problem = reason
            return plan
        }
        let parent = (root as NSString).deletingLastPathComponent
        guard fileManager.isWritableFile(atPath: parent) else {
            plan.problem = "You don't have permission to change the folder it's in."
            return plan
        }

        if entry.isRegularFile {
            if let problem = fileProblem(entry, fileManager: fileManager) {
                plan.problem = problem
                return plan
            }
            plan.files = [ToolboxShredFile(path: root, inode: entry.inode, size: entry.logicalSize)]
            plan.itemCount = 1
            plan.logicalBytes = entry.logicalSize
            plan.allocatedBytes = entry.allocatedSize
            return plan
        }
        guard entry.isDirectory else {
            plan.problem = "Only files and folders can be shredded."
            return plan
        }

        var files: [ToolboxShredFile] = []
        var problem: String?
        var count = 0
        var logical: Int64 = 0
        var allocated: Int64 = 0
        FileWalker.walk(root, options: FileWalker.Options(includeHidden: true, crossDevices: false,
                                                          descendIntoPackages: true)) { item in
            if item.depth == 0 { return .continue }
            count += 1
            if count > entryLimit {
                problem = "It holds too many files to shred in one go (more than \(CountFormat.grouped(entryLimit)))."
                return .stop
            }
            // Links are moved with the folder but never followed or overwritten.
            if item.isSymlink { return .continue }
            let verdict = guardian.check(item.path, method: .trash)
            if let reason = verdict.reason {
                problem = "It contains a protected item: \(reason)"
                return .stop
            }
            if item.isDirectory && !fileManager.isWritableFile(atPath: item.path) {
                problem = "You don't have permission to change \u{201C}\(item.name)\u{201D} inside it."
                return .stop
            }
            allocated += item.allocatedSize
            if item.isRegularFile {
                if let issue = fileProblem(item, fileManager: fileManager) {
                    problem = issue
                    return .stop
                }
                logical += item.logicalSize
                files.append(ToolboxShredFile(path: item.path, inode: item.inode, size: item.logicalSize))
            }
            return .continue
        }
        if let problem {
            plan.problem = problem
            return plan
        }
        plan.files = files
        plan.itemCount = count
        plan.logicalBytes = logical
        plan.allocatedBytes = allocated + entry.allocatedSize
        return plan
    }

    private static func fileProblem(_ entry: FileEntry, fileManager: FileManager) -> String? {
        if entry.linkCount > 1 {
            return "\u{201C}\(entry.name)\u{201D} shares its data with another file (a hard link), so overwriting it would destroy the other copy too."
        }
        if !fileManager.isWritableFile(atPath: entry.path) {
            return "You don't have permission to overwrite \u{201C}\(entry.name)\u{201D}."
        }
        return nil
    }

    /// "3 items · 1.2 GB · 240 files".
    public static func summary(_ plans: [ToolboxShredPlan]) -> String {
        let usable = plans.filter(\.canShred)
        guard !usable.isEmpty else { return "Nothing to shred" }
        let bytes = usable.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let files = usable.reduce(0) { $0 + $1.files.count }
        var parts = [CountFormat.items(usable.count), ByteFormat.string(bytes)]
        if usable.contains(where: \.isDirectory) { parts.append(CountFormat.items(files, singular: "file")) }
        return parts.joined(separator: " · ")
    }
}
