import Foundation

// MARK: - Task identity

/// Every maintenance task Spruce knows. Raw values are persisted (last-run dates), never rename.
public enum PerformanceTaskID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case freeRAM
    case purgeableSpace
    case flushDNS
    case maintenanceScripts
    case reindexSpotlight
    case repairHomePermissions
    case speedUpMail
    case rebuildLaunchServices
    case resetQuickLook
    case clearFontCaches

    public var id: String { rawValue }

    /// Identifier of the task's `ScanItem` in review lists.
    public var itemID: String { PerformanceTaskID.itemPrefix + rawValue }

    public static let itemPrefix = "performance.task."

    public init?(itemID: String) {
        guard itemID.hasPrefix(PerformanceTaskID.itemPrefix) else { return nil }
        self.init(rawValue: String(itemID.dropFirst(PerformanceTaskID.itemPrefix.count)))
    }
}

/// How noticeable a task is. Only `low` tasks are ever pre-selected.
public enum PerformanceTaskImpact: String, Codable, Sendable, Comparable {
    /// Quick, harmless, nothing visible changes.
    case low
    /// Has a visible side effect (apps must quit, snapshots are thinned…).
    case moderate
    /// Long-running or troubleshooting-only. Run when there's a symptom.
    case advanced

    private var rank: Int {
        switch self {
        case .low: return 0
        case .moderate: return 1
        case .advanced: return 2
        }
    }

    public static func < (lhs: PerformanceTaskImpact, rhs: PerformanceTaskImpact) -> Bool { lhs.rank < rhs.rank }

    public var label: String {
        switch self {
        case .low: return "Quick and safe"
        case .moderate: return "Noticeable"
        case .advanced: return "Troubleshooting"
        }
    }
}

/// When a task is worth running.
public enum PerformanceTaskCadence: Hashable, Sendable {
    /// Routine care: due again after this many days.
    case every(days: Int)
    /// Only when the Mac shows a related symptom (or a measured condition calls for it).
    case onSymptoms
}

/// Steps the engine implements itself (no single command covers them).
public enum PerformanceBuiltinStep: String, Codable, Sendable, Hashable {
    /// Quit-checked `PRAGMA integrity_check` + `VACUUM` on Mail's Envelope Index.
    case compactMailIndex
    /// `lsregister -dump` → `-u` for records of apps that no longer exist → `-gc`.
    case unregisterStaleLaunchServices
}

/// One unit of work inside a task.
public enum PerformanceTaskStep: Hashable, Sendable {
    /// A fixed administrator command: the raw value of `PrivilegedRunner.PrivilegedCommand`.
    case privileged(String)
    /// A command run as the current user (no shell involved).
    case user(executable: String, arguments: [String])
    /// Engine-implemented work.
    case builtin(PerformanceBuiltinStep)

    public var needsAdmin: Bool {
        if case .privileged = self { return true }
        return false
    }
}

// MARK: - Task definition

public struct PerformanceTaskDefinition: Identifiable, Hashable, Sendable {
    public var id: PerformanceTaskID
    public var title: String
    /// What it does, two or three sentences.
    public var summary: String
    /// Symptoms that call for it.
    public var whenToRun: [String]
    /// What the user may notice afterwards.
    public var sideEffects: String?
    public var symbol: String
    public var impact: PerformanceTaskImpact
    public var cadence: PerformanceTaskCadence
    public var steps: [PerformanceTaskStep]
    /// Executables that must exist for the task to be offered (hidden otherwise).
    public var requiredExecutables: [String]
    /// Apps that must be closed first (bundle id → display name).
    public var appsToQuit: [PerformanceAppToQuit]
    public var needsFullDiskAccess: Bool
    /// Position in a batch run (lower runs first).
    public var runOrder: Int

    public init(id: PerformanceTaskID, title: String, summary: String, whenToRun: [String], sideEffects: String?,
                symbol: String, impact: PerformanceTaskImpact, cadence: PerformanceTaskCadence,
                steps: [PerformanceTaskStep], requiredExecutables: [String], appsToQuit: [PerformanceAppToQuit] = [],
                needsFullDiskAccess: Bool = false, runOrder: Int) {
        self.id = id
        self.title = title
        self.summary = summary
        self.whenToRun = whenToRun
        self.sideEffects = sideEffects
        self.symbol = symbol
        self.impact = impact
        self.cadence = cadence
        self.steps = steps
        self.requiredExecutables = requiredExecutables
        self.appsToQuit = appsToQuit
        self.needsFullDiskAccess = needsFullDiskAccess
        self.runOrder = runOrder
    }

    public var needsAdmin: Bool { steps.contains(where: \.needsAdmin) }

    /// Raw values of the administrator commands this task runs, in order.
    public var privilegedCommands: [String] {
        steps.compactMap { step in
            if case .privileged(let raw) = step { return raw }
            return nil
        }
    }

    /// Steps that run as the current user, in order.
    public var userSteps: [PerformanceTaskStep] { steps.filter { !$0.needsAdmin } }

    /// Requirements shown in the detail pane ("Needs").
    public var requirements: [String] {
        var out: [String] = []
        if needsAdmin { out.append("Your administrator password") }
        for app in appsToQuit { out.append("\(app.name) to be closed") }
        if needsFullDiskAccess { out.append("Full Disk Access") }
        return out
    }

    public var isRoutine: Bool {
        if case .every = cadence { return true }
        return false
    }
}

public struct PerformanceAppToQuit: Hashable, Sendable, Codable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

// MARK: - Catalog

public enum PerformanceTaskCatalog {
    public static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static let mail = PerformanceAppToQuit(bundleID: "com.apple.mail", name: "Mail")

    /// The full catalog, in display order.
    public static let all: [PerformanceTaskDefinition] = [
        PerformanceTaskDefinition(
            id: .freeRAM,
            title: "Release Memory",
            summary: "Empties the file cache macOS keeps in memory, so the next app you open starts with more free memory. macOS fills the cache again on its own as you work.",
            whenToRun: ["Your Mac feels sluggish and memory pressure is high",
                        "Before opening a large project, game or video"],
            sideEffects: "Apps you reopen right afterwards may start a moment slower while their files are read again.",
            symbol: "memorychip", impact: .low, cadence: .every(days: 7),
            steps: [.privileged("purgeMemory")], requiredExecutables: ["/usr/sbin/purge"], runOrder: 90),
        PerformanceTaskDefinition(
            id: .purgeableSpace,
            title: "Reclaim Purgeable Space",
            summary: "Asks macOS to hand back disk space it is holding as purgeable, mostly the local Time Machine snapshots kept on the startup disk between backups.",
            whenToRun: ["Finder shows much less free space than you expect",
                        "An installer or download says the disk is full"],
            sideEffects: "Local Time Machine snapshots are thinned out. Backups on your backup disk are not touched.",
            symbol: "internaldrive", impact: .moderate, cadence: .every(days: 7),
            steps: [.privileged("thinTimeMachineSnapshots")], requiredExecutables: ["/usr/bin/tmutil"], runOrder: 70),
        PerformanceTaskDefinition(
            id: .flushDNS,
            title: "Refresh DNS Cache",
            summary: "Clears the website addresses your Mac remembers, so it looks them up fresh. That fixes sites that moved to a new server or stopped loading after a network change.",
            whenToRun: ["Some websites won't open while others work fine",
                        "After changing DNS servers, VPN or other network settings"],
            sideEffects: "VPN apps that are connected may reconnect.",
            symbol: "network", impact: .low, cadence: .every(days: 7),
            steps: [.privileged("flushDNS")], requiredExecutables: ["/usr/bin/dscacheutil", "/usr/bin/killall"],
            runOrder: 50),
        PerformanceTaskDefinition(
            id: .maintenanceScripts,
            title: "Run Housekeeping Scripts",
            summary: "Runs the daily, weekly and monthly scripts that ship with macOS. They rotate logs, delete old temporary files and refresh a few system databases.",
            whenToRun: ["Your Mac is usually asleep or off at night, when macOS would run them",
                        "Once a week as routine care"],
            sideEffects: nil,
            symbol: "clock.arrow.circlepath", impact: .low, cadence: .every(days: 7),
            steps: [.privileged("runPeriodicScripts")], requiredExecutables: ["/usr/sbin/periodic"], runOrder: 60),
        PerformanceTaskDefinition(
            id: .reindexSpotlight,
            title: "Rebuild Spotlight Index",
            summary: "Erases the Spotlight index of the startup disk and builds it again from scratch. It fixes searches that are slow or miss files you know are there.",
            whenToRun: ["Spotlight or Finder search can't find files that exist",
                        "Search results are slow or out of date"],
            sideEffects: "Rebuilding takes from several minutes to a couple of hours. Until it finishes, search results are incomplete and your Mac works harder.",
            symbol: "magnifyingglass", impact: .advanced, cadence: .onSymptoms,
            steps: [.privileged("reindexSpotlight")], requiredExecutables: ["/usr/bin/mdutil"], runOrder: 100),
        PerformanceTaskDefinition(
            id: .repairHomePermissions,
            title: "Repair Home Permissions",
            summary: "Resets the owner and access rights of the items in your home folder to their defaults. It fixes apps that can't save settings or open your files.",
            whenToRun: ["Apps keep asking for your password to save a file",
                        "Apps can't save preferences, or forget them after a restart"],
            sideEffects: "Custom sharing permissions you set on folders in your home are reset. It can take several minutes on a large home folder.",
            symbol: "lock.shield", impact: .advanced, cadence: .onSymptoms,
            steps: [.privileged("repairHomePermissions")], requiredExecutables: ["/usr/sbin/diskutil"], runOrder: 80),
        PerformanceTaskDefinition(
            id: .speedUpMail,
            title: "Compact Mail Database",
            summary: "Compacts the database Mail uses to list and search your messages, removing the empty space deleted mail leaves behind. Your messages themselves are not touched.",
            whenToRun: ["Mail is slow to open mailboxes or to search",
                        "You recently deleted a lot of mail"],
            sideEffects: "Mail has to be closed while it runs. A very large mailbox can take a few minutes.",
            symbol: "envelope", impact: .moderate, cadence: .onSymptoms,
            steps: [.builtin(.compactMailIndex)], requiredExecutables: ["/usr/bin/sqlite3"],
            appsToQuit: [mail], needsFullDiskAccess: true, runOrder: 10),
        PerformanceTaskDefinition(
            id: .rebuildLaunchServices,
            title: "Rebuild Launch Services",
            summary: "Tidies the database macOS uses to decide which app opens which file, and removes entries for apps that are no longer on your Mac.",
            whenToRun: ["The Open With menu lists apps twice, or apps you deleted",
                        "Files open in the wrong app or show the wrong icon"],
            sideEffects: "Finder may take a moment to redraw some file icons.",
            symbol: "arrow.up.forward.app", impact: .moderate, cadence: .onSymptoms,
            steps: [.builtin(.unregisterStaleLaunchServices)], requiredExecutables: [lsregisterPath], runOrder: 20),
        PerformanceTaskDefinition(
            id: .resetQuickLook,
            title: "Reset Quick Look Cache",
            summary: "Clears the thumbnails and previews that Finder and Quick Look have stored, and reloads the preview plug-ins.",
            whenToRun: ["Thumbnails show an old version of a file",
                        "Space-bar previews don't appear or look wrong"],
            sideEffects: "Finder draws thumbnails again the next time you open a folder.",
            symbol: "eye", impact: .low, cadence: .onSymptoms,
            steps: [.user(executable: "/usr/bin/qlmanage", arguments: ["-r", "cache"]),
                    .user(executable: "/usr/bin/qlmanage", arguments: ["-r"])],
            requiredExecutables: ["/usr/bin/qlmanage"], runOrder: 30),
        PerformanceTaskDefinition(
            id: .clearFontCaches,
            title: "Clear Font Caches",
            summary: "Deletes the caches macOS keeps for fonts, for your account and for the system, so they're rebuilt from the fonts you have installed.",
            whenToRun: ["Text appears in the wrong font or with garbled characters",
                        "A font you installed or removed doesn't show up correctly"],
            sideEffects: "Restart your Mac afterwards. Until then some apps may draw text more slowly.",
            symbol: "textformat", impact: .advanced, cadence: .onSymptoms,
            steps: [.user(executable: "/usr/bin/atsutil", arguments: ["databases", "-removeUser"]),
                    .privileged("clearFontCaches")],
            requiredExecutables: ["/usr/bin/atsutil"], runOrder: 40),
    ]

    public static func definition(_ id: PerformanceTaskID) -> PerformanceTaskDefinition {
        // `all` covers every case; the fallback only exists to keep this total.
        all.first { $0.id == id } ?? all[0]
    }

    /// Tasks this Mac can run: every required executable must exist. Tasks whose tools
    /// are gone (e.g. `periodic` on macOS 15+) are hidden rather than shown disabled.
    public static func available(isExecutable: (String) -> Bool) -> [PerformanceTaskDefinition] {
        all.filter { $0.requiredExecutables.allSatisfy(isExecutable) }
    }

    /// Sorts task ids into batch run order and removes duplicates.
    public static func ordered(_ ids: [PerformanceTaskID]) -> [PerformanceTaskID] {
        var seen = Set<PerformanceTaskID>()
        let unique = ids.filter { seen.insert($0).inserted }
        return unique.sorted { definition($0).runOrder < definition($1).runOrder }
    }

    /// Administrator commands for a batch, in run order, without duplicates.
    public static func privilegedBatch(for ids: [PerformanceTaskID]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for id in ordered(ids) {
            for raw in definition(id).privilegedCommands where seen.insert(raw).inserted {
                out.append(raw)
            }
        }
        return out
    }
}

// MARK: - Conditions

/// What Spruce knows about Mail's Envelope Index.
public enum PerformanceMailIndexState: Sendable, Equatable {
    /// Mail has never been set up on this Mac.
    case notFound
    /// The database exists but can't be read (Full Disk Access missing).
    case unreadable
    case measured(PerformanceMailIndexInfo)
}

public struct PerformanceMailIndexInfo: Sendable, Equatable {
    public var path: String
    public var bytes: Int64
    public var pageCount: Int
    public var freelistCount: Int

    public init(path: String, bytes: Int64, pageCount: Int, freelistCount: Int) {
        self.path = path
        self.bytes = bytes
        self.pageCount = pageCount
        self.freelistCount = freelistCount
    }

    /// Share of the database that is empty pages (0...1).
    public var freelistRatio: Double {
        pageCount > 0 ? Double(freelistCount) / Double(pageCount) : 0
    }

    /// Bytes a VACUUM would roughly give back.
    public var reclaimableBytes: Int64 {
        Int64(Double(bytes) * freelistRatio)
    }
}

/// Measured state of the Mac that drives recommendations. `nil` means "unknown".
public struct PerformanceConditions: Sendable, Equatable {
    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    public var memoryPressureLevel: Int?
    public var swapUsedBytes: Int64?
    public var purgeableBytes: Int64?
    /// Free share of the startup disk (0...1).
    public var volumeFreeFraction: Double?
    public var vpnConnected: Bool
    public var spotlightIndexingEnabled: Bool?
    public var mailIndex: PerformanceMailIndexState?
    /// Human-readable home-permission problems; empty when everything looks right.
    public var homePermissionProblems: [String]
    /// When macOS itself last ran the daily script (mtime of /var/log/daily.out).
    public var systemScriptsLastRun: Date?

    public init(memoryPressureLevel: Int? = nil, swapUsedBytes: Int64? = nil, purgeableBytes: Int64? = nil,
                volumeFreeFraction: Double? = nil, vpnConnected: Bool = false, spotlightIndexingEnabled: Bool? = nil,
                mailIndex: PerformanceMailIndexState? = nil, homePermissionProblems: [String] = [],
                systemScriptsLastRun: Date? = nil) {
        self.memoryPressureLevel = memoryPressureLevel
        self.swapUsedBytes = swapUsedBytes
        self.purgeableBytes = purgeableBytes
        self.volumeFreeFraction = volumeFreeFraction
        self.vpnConnected = vpnConnected
        self.spotlightIndexingEnabled = spotlightIndexingEnabled
        self.mailIndex = mailIndex
        self.homePermissionProblems = homePermissionProblems
        self.systemScriptsLastRun = systemScriptsLastRun
    }
}

// MARK: - Assessment

public struct PerformanceTaskAssessment: Sendable, Equatable {
    public var isAvailable: Bool
    public var isRecommended: Bool
    /// Pre-selected in lists: recommended *and* low impact.
    public var preselect: Bool
    /// Why it is (or isn't) recommended, or why it can't run.
    public var reason: String

    public init(isAvailable: Bool = true, isRecommended: Bool, preselect: Bool, reason: String) {
        self.isAvailable = isAvailable
        self.isRecommended = isRecommended && isAvailable
        self.preselect = preselect && isRecommended && isAvailable
        self.reason = reason
    }
}

/// A task with everything the UI needs to show it.
public struct PerformanceTaskState: Identifiable, Sendable, Equatable {
    public var definition: PerformanceTaskDefinition
    public var assessment: PerformanceTaskAssessment
    public var lastRun: Date?

    public var id: PerformanceTaskID { definition.id }

    public init(definition: PerformanceTaskDefinition, assessment: PerformanceTaskAssessment, lastRun: Date?) {
        self.definition = definition
        self.assessment = assessment
        self.lastRun = lastRun
    }
}

public enum PerformanceRecommender {
    public static let routineMemorySwapThreshold: Int64 = 2_000_000_000
    public static let purgeableThreshold: Int64 = 5_000_000_000
    public static let lowDiskFraction = 0.15
    public static let mailFreelistThreshold = 0.05
    public static let mailLargeIndex: Int64 = 1_000_000_000

    /// The date to show and judge by. For the housekeeping scripts macOS's own runs count too.
    public static func effectiveLastRun(_ id: PerformanceTaskID, recorded: Date?, conditions: PerformanceConditions) -> Date? {
        guard id == .maintenanceScripts, let system = conditions.systemScriptsLastRun else { return recorded }
        guard let recorded else { return system }
        return max(recorded, system)
    }

    public static func assess(_ definition: PerformanceTaskDefinition, lastRun: Date?,
                              conditions: PerformanceConditions, now: Date = Date()) -> PerformanceTaskAssessment {
        let low = definition.impact == .low
        let overdue = isOverdue(definition, lastRun: lastRun, now: now)

        switch definition.id {
        case .freeRAM:
            if let level = conditions.memoryPressureLevel, level >= 2 {
                return .init(isRecommended: true, preselect: low,
                             reason: level >= 4 ? "Memory pressure is critical right now" : "Memory pressure is elevated right now")
            }
            if let swap = conditions.swapUsedBytes, swap > routineMemorySwapThreshold {
                return .init(isRecommended: true, preselect: low, reason: "Your Mac is using \(ByteFormat.string(swap)) of swap")
            }
            return routine(definition, lastRun: lastRun, overdue: overdue, now: now)

        case .flushDNS:
            if conditions.vpnConnected {
                return .init(isRecommended: false, preselect: false,
                             reason: "A VPN is connected, and refreshing DNS may make it reconnect")
            }
            return routine(definition, lastRun: lastRun, overdue: overdue, now: now)

        case .maintenanceScripts:
            return routine(definition, lastRun: lastRun, overdue: overdue, now: now)

        case .purgeableSpace:
            let recentlyRun = lastRun.map { now.timeIntervalSince($0) < 86_400 } ?? false
            if let free = conditions.volumeFreeFraction, free < lowDiskFraction, !recentlyRun {
                return .init(isRecommended: true, preselect: low, reason: "The startup disk is nearly full")
            }
            if let purgeable = conditions.purgeableBytes {
                if purgeable >= purgeableThreshold && !recentlyRun {
                    return .init(isRecommended: true, preselect: low,
                                 reason: "About \(ByteFormat.string(purgeable)) is held as purgeable space")
                }
                return .init(isRecommended: false, preselect: false,
                             reason: purgeable < 1_000_000_000 ? "Hardly any purgeable space right now"
                                 : "\(ByteFormat.string(purgeable)) purgeable, which macOS frees on its own when needed")
            }
            return .init(isRecommended: false, preselect: false, reason: lastRunText(lastRun, now: now))

        case .reindexSpotlight:
            if conditions.spotlightIndexingEnabled == false {
                return .init(isAvailable: false, isRecommended: false, preselect: false,
                             reason: "Spotlight indexing is turned off for the startup disk")
            }
            return symptomDriven(lastRun: lastRun, now: now)

        case .repairHomePermissions:
            if let problem = conditions.homePermissionProblems.first {
                return .init(isRecommended: true, preselect: false, reason: problem)
            }
            return .init(isRecommended: false, preselect: false, reason: "No permission problems found in your home folder")

        case .speedUpMail:
            switch conditions.mailIndex {
            case .notFound?:
                return .init(isAvailable: false, isRecommended: false, preselect: false,
                             reason: "Mail has no local mailboxes on this Mac")
            case .unreadable?:
                return .init(isRecommended: false, preselect: false,
                             reason: "Grant Full Disk Access so Spruce can check Mail's database")
            case .measured(let info)?:
                let recentlyRun = lastRun.map { now.timeIntervalSince($0) < 7 * 86_400 } ?? false
                if !recentlyRun && info.freelistRatio >= mailFreelistThreshold {
                    let percent = Int((info.freelistRatio * 100).rounded())
                    return .init(isRecommended: true, preselect: low,
                                 reason: "\(percent)% of Mail's database is empty space")
                }
                if !recentlyRun && info.bytes >= mailLargeIndex {
                    return .init(isRecommended: true, preselect: low,
                                 reason: "Mail's database has grown to \(ByteFormat.string(info.bytes))")
                }
                return .init(isRecommended: false, preselect: false,
                             reason: "Mail's database is in good shape (\(ByteFormat.string(info.bytes)))")
            case nil:
                return symptomDriven(lastRun: lastRun, now: now)
            }

        case .rebuildLaunchServices, .resetQuickLook, .clearFontCaches:
            return symptomDriven(lastRun: lastRun, now: now)
        }
    }

    /// Assesses every available task.
    public static func states(for definitions: [PerformanceTaskDefinition], recorded: [PerformanceTaskID: Date],
                              conditions: PerformanceConditions, now: Date = Date()) -> [PerformanceTaskState] {
        definitions.map { def in
            let last = effectiveLastRun(def.id, recorded: recorded[def.id], conditions: conditions)
            return PerformanceTaskState(definition: def, assessment: assess(def, lastRun: last, conditions: conditions, now: now),
                                        lastRun: last)
        }
    }

    public static func isOverdue(_ definition: PerformanceTaskDefinition, lastRun: Date?, now: Date) -> Bool {
        guard case .every(let days) = definition.cadence else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= Double(days) * 86_400
    }

    public static func lastRunText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not run by Spruce yet" }
        return "Last run \(DurationFormat.relative(date, now: now))"
    }

    private static func routine(_ definition: PerformanceTaskDefinition, lastRun: Date?, overdue: Bool,
                                now: Date) -> PerformanceTaskAssessment {
        let low = definition.impact == .low
        guard overdue else {
            return .init(isRecommended: false, preselect: false, reason: lastRunText(lastRun, now: now) + ", not due yet")
        }
        if let lastRun {
            return .init(isRecommended: true, preselect: low,
                         reason: "Last run \(DurationFormat.relative(lastRun, now: now)), due \(cadenceText(definition.cadence))")
        }
        return .init(isRecommended: true, preselect: low, reason: "Not run by Spruce yet, due \(cadenceText(definition.cadence))")
    }

    private static func symptomDriven(lastRun: Date?, now: Date) -> PerformanceTaskAssessment {
        let base = "Run it when you notice the problems it fixes"
        guard let lastRun else { return .init(isRecommended: false, preselect: false, reason: base) }
        return .init(isRecommended: false, preselect: false,
                     reason: "\(base). Last run \(DurationFormat.relative(lastRun, now: now))")
    }

    private static func cadenceText(_ cadence: PerformanceTaskCadence) -> String {
        switch cadence {
        case .every(let days) where days == 1: return "daily"
        case .every(let days) where days == 7: return "weekly"
        case .every(let days) where days == 30: return "monthly"
        case .every(let days): return "every \(days) days"
        case .onSymptoms: return "when needed"
        }
    }
}

// MARK: - Review items

public enum PerformanceMetaKey {
    public static let kind = "performance.kind"
    public static let taskID = "performance.taskID"
    public static let recommended = "performance.recommended"
    public static let needsAdmin = "performance.needsAdmin"
    public static let kindTask = "task"
}

public enum PerformanceTaskItems {
    public static let maintenanceGroupID = "performance.maintenance"

    /// The task as a reviewable item (`deletion: .custom`; never touches files).
    public static func item(for state: PerformanceTaskState) -> ScanItem {
        let def = state.definition
        var note = def.summary
        if let side = def.sideEffects { note += "\n\n" + side }
        return ScanItem(
            id: def.id.itemID,
            title: def.title,
            subtitle: state.assessment.reason,
            size: 0,
            itemCount: 1,
            safety: def.impact == .low ? .safe : .review,
            isSelected: state.assessment.preselect,
            deletion: .custom,
            lastUsed: state.lastRun,
            symbol: def.symbol,
            note: note,
            metadata: [
                PerformanceMetaKey.kind: PerformanceMetaKey.kindTask,
                PerformanceMetaKey.taskID: def.id.rawValue,
                PerformanceMetaKey.recommended: state.assessment.isRecommended ? "1" : "0",
                PerformanceMetaKey.needsAdmin: def.needsAdmin ? "1" : "0",
            ]
        )
    }

    /// Task ids referenced by review items (non-task items are ignored).
    public static func taskIDs(in items: [ScanItem]) -> [PerformanceTaskID] {
        items.compactMap { item in
            if let raw = item.metadata[PerformanceMetaKey.taskID], let id = PerformanceTaskID(rawValue: raw) { return id }
            return PerformanceTaskID(itemID: item.id)
        }
    }

    /// The maintenance list as one review group. `onlyRecommended` keeps Checkup concise.
    public static func group(for states: [PerformanceTaskState], onlyRecommended: Bool) -> ScanGroup {
        let visible = states.filter { $0.assessment.isAvailable && (!onlyRecommended || $0.assessment.isRecommended) }
        return ScanGroup(
            id: maintenanceGroupID,
            title: "Maintenance Tasks",
            detail: "Routine care for macOS. Quick, harmless tasks that are due are selected for you; the others are worth running when you notice the problems they fix.",
            symbol: "wrench.and.screwdriver",
            safety: .safe,
            items: visible.map(item(for:))
        )
    }

    /// The Checkup tile for the given assessed tasks.
    public static func checkupTile(for states: [PerformanceTaskState]) -> CheckupTile {
        let recommended = states.filter { $0.assessment.isRecommended }
        let preselected = recommended.filter { $0.assessment.preselect }
        if recommended.isEmpty {
            return CheckupTile(module: .performance, headline: "Up to date", detail: "No maintenance is due right now",
                               status: .clear, actionCount: 0)
        }
        if preselected.isEmpty {
            return CheckupTile(module: .performance, headline: CountFormat.items(recommended.count, singular: "suggestion"),
                               detail: "worth a look in Performance", status: .info, isSelected: false,
                               actionCount: recommended.count)
        }
        return CheckupTile(module: .performance, headline: CountFormat.items(preselected.count, singular: "task"),
                           detail: "of routine maintenance to run", status: .attention, actionCount: preselected.count)
    }
}

// MARK: - Run results

public enum PerformanceTaskRunStatus: String, Codable, Sendable {
    case done
    case skipped
    case failed
}

public struct PerformanceTaskRunResult: Identifiable, Codable, Sendable, Hashable {
    public var id: PerformanceTaskID
    public var status: PerformanceTaskRunStatus
    public var detail: String
    /// Disk space given back (Mail compaction, purgeable space).
    public var freedBytes: Int64
    public var date: Date

    public init(id: PerformanceTaskID, status: PerformanceTaskRunStatus, detail: String, freedBytes: Int64 = 0, date: Date = Date()) {
        self.id = id
        self.status = status
        self.detail = detail
        self.freedBytes = freedBytes
        self.date = date
    }
}

public enum PerformanceRunSummary {
    public static func summary(_ results: [PerformanceTaskRunResult]) -> String {
        let done = results.filter { $0.status == .done }.count
        if results.isEmpty { return "No tasks were run" }
        if done == results.count {
            return done == 1 ? "1 task completed" : "All \(done) tasks completed"
        }
        if done == 0 { return "No tasks could be completed" }
        return "\(done) of \(results.count) tasks completed"
    }

    /// Converts task results into the shared outcome type. Completed tasks are reported in
    /// `removedItemIDs` (they were acted on); skipped and failed ones become failures.
    public static func outcome(_ results: [PerformanceTaskRunResult], date: Date = Date()) -> RunOutcome {
        let done = results.filter { $0.status == .done }
        let failures = results.filter { $0.status != .done }.map { result in
            ItemFailure(itemID: result.id.itemID, title: PerformanceTaskCatalog.definition(result.id).title, reason: result.detail)
        }
        return RunOutcome(module: .performance, date: date, freedBytes: results.reduce(0) { $0 + $1.freedBytes },
                          processedCount: done.count, removedItemIDs: done.map(\.id.itemID), failures: failures,
                          summary: summary(results))
    }
}
