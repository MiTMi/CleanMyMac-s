import Foundation

/// The Cleanup rule catalog ("safety database").
///
/// CONTRACT: `categories` is used by Settings › Scanning to let the user exclude
/// categories (`SpruceSettings.excludedCleanupCategories`).
///
/// Ordering matters: a rule never touches paths claimed by a rule listed *before* it,
/// so specific rules come first and the broad ones (`~/Library/Caches/*`,
/// `~/Library/Logs/*`, `/Library/Caches/*`) come last.
public enum CleanupCatalog {

    /// Every category, in display order (System Junk first, then Mail and Trash).
    public static var categories: [CategoryDescriptor] {
        CleanupCategory.allCases.map(\.descriptor)
    }

    /// Categories of System Junk that can contain removable items, in display order.
    public static var systemJunkCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { $0.section == .systemJunk && !$0.isInformational }
    }

    public static func rule(id: String) -> CleanupRule? {
        rulesByID[id]
    }

    private static let rulesByID: [String: CleanupRule] = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: Built-in exceptions (never listed, never removed)

    /// Paths (tilde globs, case-insensitive) that are never offered, nor anything below them.
    public static let protectedPaths: [String] = [
        // Real user content kept inside "cache" folders.
        "~/Library/Caches/com.spotify.client",
        "~/Library/Application Support/Spotify/PersistentCache/Storage",
        "~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts",
        // System-critical caches: deleting them breaks search, fonts, icons, iCloud,
        // pending App Store updates, in-flight background downloads, audio, Settings panes.
        "~/Library/Caches/CloudKit*",
        "~/Library/Caches/com.apple.FontRegistry*",
        "~/Library/Caches/com.apple.Spotlight*",
        "~/Library/Caches/Spotlight*",
        "~/Library/Caches/Metadata",
        "~/Library/Caches/com.apple.iconservices*",
        "~/Library/Caches/com.apple.dock*",
        "~/Library/Caches/com.apple.finder",
        "~/Library/Caches/com.apple.appstoreagent",
        "~/Library/Caches/com.apple.nsurlsessiond",
        "~/Library/Caches/com.apple.bird*",
        "~/Library/Caches/com.apple.CloudDocs*",
        "~/Library/Caches/com.apple.cloudd",
        "~/Library/Caches/com.apple.LaunchServices*",
        "~/Library/Caches/com.apple.siriactionsd*",
        "~/Library/Caches/com.apple.coreaudio*",
        "~/Library/Caches/com.apple.audio*",
        "~/Library/Caches/com.apple.systempreferences*",
        "~/Library/Caches/com.apple.Settings*",
        "~/Library/Caches/com.apple.controlcenter*",
        "~/Library/Containers/com.apple.systempreferences*",
        "~/Library/Containers/com.apple.Settings*",
        "~/Library/Containers/com.apple.controlcenter*",
        "~/Library/Containers/com.apple.finder*",
        "~/Library/Containers/com.apple.dock*",
        "~/Library/Containers/com.apple.wallpaper*",
        "~/Library/Containers/com.apple.CloudDocs*",
        "~/Library/Containers/com.docker.docker/Data/vms",
        "~/Library/Application Support/CloudDocs",
        // Dependency stores, runtimes and model stores.
        "~/Library/Caches/JetBrains*",
        "~/Library/Caches/ms-playwright*",
        "~/.cache/ms-playwright*",
        "~/Library/Caches/pypoetry/virtualenvs",
        "~/Library/Caches/org.R-project.R/R/renv",
        "~/.cache/huggingface",
        "~/.cache/lm-studio",
        "~/.ollama",
        "~/.lmstudio",
        "~/.cargo/bin",
        "~/.rustup",
        "~/.orbstack",
        // System locations.
        "/Library/Caches/Desktop Pictures",
        "/Library/Caches/ColorSync",
        "/Library/Caches/*Aerial*",
        "/Library/Caches/com.apple.iconservices*",
        "/Library/Caches/com.apple.cache_delete*",
        "/private/var/log/install.log*",
        "/private/var/db",
        // Our own files.
        "~/Library/Logs/Spruce",
        "~/Library/Caches/Spruce*",
        "~/Library/Application Support/Spruce",
    ]

    /// Path-component globs (case-insensitive) that are protected anywhere: security
    /// agents (deleting their caches trips tamper alarms), VPNs, license managers and
    /// telemetry queues apps depend on.
    public static let protectedNames: [String] = [
        "com.crowdstrike*", "com.sentinelone*", "com.eset*", "com.jamf*", "com.jamfsoftware*",
        "com.paloaltonetworks*", "com.cisco.anyconnect*", "com.cisco.secureclient*", "com.cisco.amp*",
        "com.microsoft.wdav*", "com.sophos*", "com.trendmicro*", "com.bitdefender*", "com.kaspersky*",
        "com.symantec*", "com.mcafee*", "com.carbonblack*", "com.vmware.carbonblack*", "co.elastic.*",
        "com.elastic.endpoint*", "com.tanium*", "io.kandji*", "com.kandji*", "com.addigy*", "com.mosyle*",
        "com.paceap*", "com.native-instruments*", "com.avid*",
        "com.wireguard*", "net.tunnelblick*", "com.nordvpn*", "com.expressvpn*", "ch.protonvpn*",
        "com.privateinternetaccess*", "com.tailscale*", "io.tailscale*", "net.mullvad*", "com.mullvad*",
        "com.cloudflare.1dot1dot1dot1*",
        "*cctclearcutlogger*", "*shortcutssandboxcache*",
    ]

    // MARK: Rules

    private static let day: TimeInterval = 86_400
    private static let hour: TimeInterval = 3_600

    static let xcodeRules: [CleanupRule] = [
        CleanupRule(id: "xcode.moduleCache", category: .xcodeJunk, title: "Module Cache",
                    paths: ["~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex"], target: .each,
                    safety: .review, gate: .xcode,
                    note: "Clang and Swift module cache. Xcode rebuilds it, but the next build of every project takes longer."),
        CleanupRule(id: "xcode.derivedData", category: .xcodeJunk, title: "Derived Data",
                    paths: ["~/Library/Developer/Xcode/DerivedData/*"], target: .each, minAge: hour, gate: .xcode,
                    analyzer: .derivedData,
                    note: "Intermediate build files and the code index of a project. Xcode recreates them on the next build."),
        CleanupRule(id: "xcode.archives", category: .xcodeJunk, title: "Archives",
                    paths: ["~/Library/Developer/Xcode/Archives/*/*.xcarchive"], target: .each, safety: .review,
                    deletion: .trash,
                    note: "An archived build with its debug symbols. Keep it if you may need to read crash reports of this version. Goes to the Trash."),
        CleanupRule(id: "xcode.deviceSupport", category: .xcodeJunk, title: "Device Support",
                    paths: ["~/Library/Developer/Xcode/iOS DeviceSupport/*",
                            "~/Library/Developer/Xcode/watchOS DeviceSupport/*",
                            "~/Library/Developer/Xcode/tvOS DeviceSupport/*",
                            "~/Library/Developer/Xcode/visionOS DeviceSupport/*",
                            "~/Library/Developer/Xcode/macOS DeviceSupport/*"],
                    target: .each, gate: .xcode, analyzer: .newestKept,
                    note: "Debug symbols copied from a device running this OS version. Xcode copies them again when such a device is connected."),
        CleanupRule(id: "xcode.documentationCache", category: .xcodeJunk, title: "Documentation Cache",
                    paths: ["~/Library/Developer/Xcode/DocumentationCache/*"], target: .each, gate: .xcode,
                    addsPermanentZone: true, analyzer: .newestKept,
                    note: "Documentation index of an Xcode version. The newest one is kept."),
        CleanupRule(id: "xcode.ibSupport", category: .xcodeJunk, title: "Interface Builder Cache",
                    paths: ["~/Library/Developer/Xcode/UserData/IB Support"], gate: .xcode, addsPermanentZone: true,
                    note: "Interface Builder rendering cache, rebuilt when you open a storyboard."),
        CleanupRule(id: "xcode.previews", category: .xcodeJunk, title: "SwiftUI Previews",
                    paths: ["~/Library/Developer/Xcode/UserData/Previews"], gate: .xcode,
                    note: "Simulators and builds used by SwiftUI previews. Recreated when a preview runs."),
        CleanupRule(id: "xcode.products", category: .xcodeJunk, title: "Build Products",
                    paths: ["~/Library/Developer/Xcode/Products"], gate: .xcode,
                    note: "Products Xcode built outside your project folders."),
        CleanupRule(id: "xcode.simulatorCaches", category: .xcodeJunk, title: "Simulator Caches",
                    paths: ["~/Library/Developer/CoreSimulator/Caches"], gate: .simulator,
                    note: "Simulator system caches, rebuilt when a simulator boots."),
        CleanupRule(id: "xcode.testDevices", category: .xcodeJunk, title: "Test Device Clones",
                    paths: ["~/Library/Developer/XCTestDevices"], gate: .xcode,
                    note: "Simulator clones made for running tests in parallel."),
        CleanupRule(id: "xcode.simulatorLogs", category: .xcodeJunk, title: "Simulator Logs",
                    paths: ["~/Library/Logs/CoreSimulator"], target: .files, minAge: 7 * day, gate: .simulator,
                    note: "Logs of simulated devices, older than a week."),
        CleanupRule(id: "xcode.appCache", category: .xcodeJunk, title: "Xcode Cache",
                    paths: ["~/Library/Caches/com.apple.dt.Xcode"], minAge: hour, gate: .xcode,
                    note: "Xcode's own app cache."),
        CleanupRule(id: "xcode.swiftpm", category: .xcodeJunk, title: "Swift Package Cache",
                    paths: ["~/Library/Caches/org.swift.swiftpm", "~/.cache/swift-package-manager"],
                    minAge: hour, gate: .xcode,
                    note: "Swift Package Manager download and checkout cache. Packages download again on the next build."),
    ]

    static let devRules: [CleanupRule] = [
        CleanupRule(id: "dev.homebrew", category: .devJunk, title: "Homebrew Downloads",
                    paths: ["~/Library/Caches/Homebrew/downloads"], minAge: day,
                    note: "Bottles and casks Homebrew already installed. They download again if needed."),
        CleanupRule(id: "dev.npm", category: .devJunk, title: "npm Cache",
                    paths: ["~/.npm/_cacache"], minAge: hour,
                    note: "npm's package download cache."),
        CleanupRule(id: "dev.npmLogs", category: .devJunk, title: "npm Logs",
                    paths: ["~/.npm/_logs"], target: .files, minAge: day,
                    note: "Debug logs npm wrote after failed commands."),
        CleanupRule(id: "dev.yarn", category: .devJunk, title: "Yarn Cache",
                    paths: ["~/Library/Caches/Yarn", "~/.yarn/berry/cache"], minAge: hour, addsPermanentZone: true,
                    note: "Yarn's package cache."),
        CleanupRule(id: "dev.pnpm", category: .devJunk, title: "pnpm Store",
                    paths: ["~/Library/pnpm/store"], safety: .review, addsPermanentZone: true,
                    note: "pnpm's content store. Projects link to it, so removing it frees less than shown and every project must reinstall."),
        CleanupRule(id: "dev.pip", category: .devJunk, title: "pip Cache",
                    paths: ["~/Library/Caches/pip"], minAge: hour,
                    note: "pip's download and wheel cache."),
        CleanupRule(id: "dev.poetry", category: .devJunk, title: "Poetry Cache",
                    paths: ["~/Library/Caches/pypoetry/cache", "~/Library/Caches/pypoetry/artifacts"], minAge: hour,
                    note: "Poetry's package cache. Virtual environments are never touched."),
        CleanupRule(id: "dev.uv", category: .devJunk, title: "uv Cache",
                    paths: ["~/.cache/uv"], minAge: hour,
                    note: "uv's package cache."),
        CleanupRule(id: "dev.cargo", category: .devJunk, title: "Cargo Registry",
                    paths: ["~/.cargo/registry/cache", "~/.cargo/registry/src"], minAge: hour, addsPermanentZone: true,
                    note: "Downloaded crate archives and their unpacked sources."),
        CleanupRule(id: "dev.goBuild", category: .devJunk, title: "Go Build Cache",
                    paths: ["~/Library/Caches/go-build"], minAge: hour,
                    note: "Go's build cache."),
        CleanupRule(id: "dev.cocoapods", category: .devJunk, title: "CocoaPods Cache",
                    paths: ["~/Library/Caches/CocoaPods"], minAge: hour,
                    note: "CocoaPods download cache."),
        CleanupRule(id: "dev.gradleCaches", category: .devJunk, title: "Gradle Caches",
                    paths: ["~/.gradle/caches"], safety: .review,
                    note: "Gradle's dependency and build caches. Removing them forces long re-downloads, so they're never pre-selected."),
        CleanupRule(id: "dev.gradleDaemon", category: .devJunk, title: "Gradle Daemon Logs",
                    paths: ["~/.gradle/daemon"], target: .files, minAge: 7 * day, namePatterns: ["*.log"],
                    addsPermanentZone: true,
                    note: "Logs of Gradle build daemons, older than a week."),
        CleanupRule(id: "dev.gradleWrapper", category: .devJunk, title: "Gradle Distributions",
                    paths: ["~/.gradle/wrapper/dists"], safety: .review,
                    note: "Gradle versions downloaded by project wrappers. Projects download them again."),
        CleanupRule(id: "dev.maven", category: .devJunk, title: "Maven Repository",
                    paths: ["~/.m2/repository"], safety: .review,
                    note: "Maven's local repository. Builds download every dependency again."),
        CleanupRule(id: "dev.bun", category: .devJunk, title: "Bun Cache",
                    paths: ["~/.bun/install/cache"], minAge: hour,
                    note: "Bun's package cache."),
        CleanupRule(id: "dev.android", category: .devJunk, title: "Android Caches",
                    paths: ["~/.android/cache", "~/.android/build-cache"], minAge: hour, addsPermanentZone: true,
                    note: "Android SDK and build caches."),
        CleanupRule(id: "dev.androidStudio", category: .devJunk, title: "Android Studio Caches",
                    paths: ["~/Library/Caches/Google/AndroidStudio*"], minAge: hour,
                    gate: .bundleIDs(["com.google.android.studio"]),
                    note: "Android Studio system caches."),
        CleanupRule(id: "dev.vscode", category: .devJunk, title: "VS Code Caches",
                    paths: ["~/Library/Application Support/Code/Cache",
                            "~/Library/Application Support/Code/Code Cache",
                            "~/Library/Application Support/Code/GPUCache",
                            "~/Library/Application Support/Code/CachedData",
                            "~/Library/Application Support/Code/CachedExtensionVSIXs",
                            "~/Library/Application Support/Code/logs"],
                    minAge: hour, gate: .bundleIDs(["com.microsoft.VSCode"]), addsPermanentZone: true,
                    note: "Visual Studio Code's web caches, downloaded extension packages and old logs."),
        CleanupRule(id: "dev.toolCaches", category: .devJunk, title: "Developer Tool Caches",
                    paths: ["~/.cache/pre-commit", "~/.cache/ruff", "~/.cache/mypy", "~/.cache/eslint",
                            "~/.cache/prettier", "~/.cache/typescript", "~/.cache/vite", "~/.cache/webpack",
                            "~/.cache/node-gyp", "~/.cache/bazel", "~/.cache/terraform", "~/.cache/prisma",
                            "~/.cache/zig", "~/.cache/deno", "~/.cache/golangci-lint", "~/.cache/black",
                            "~/.cache/pylint", "~/.cache/jedi", "~/.cache/electron", "~/.cache/electron-builder",
                            "~/.cache/turbo", "~/.cache/yarn", "~/.cache/pnpm", "~/.cache/pip"],
                    minAge: hour,
                    note: "Caches of linters, bundlers and build tools. They fill up again as you work."),
        CleanupRule(id: "dev.composer", category: .devJunk, title: "Composer Cache",
                    paths: ["~/Library/Caches/composer", "~/.composer/cache"], minAge: hour,
                    note: "Composer's package cache."),
        CleanupRule(id: "dev.deno", category: .devJunk, title: "Deno Cache",
                    paths: ["~/Library/Caches/deno"], minAge: hour,
                    note: "Deno's module cache."),
        CleanupRule(id: "dev.nuget", category: .devJunk, title: "NuGet Packages",
                    paths: ["~/.nuget/packages"], safety: .review,
                    note: "NuGet's global package folder. Builds restore everything again."),
        CleanupRule(id: "dev.puppeteer", category: .devJunk, title: "Puppeteer Browsers",
                    paths: ["~/.cache/puppeteer"], safety: .review,
                    note: "Browsers downloaded by Puppeteer for automated tests."),
    ]

    static let updateRules: [CleanupRule] = [
        CleanupRule(id: "updates.sparkle", category: .oldUpdates, title: "App Update Downloads",
                    paths: ["~/Library/Caches/*/org.sparkle-project.Sparkle/PersistentDownloads/*",
                            "~/Library/Caches/*/org.sparkle-project.Sparkle/Installation/*"],
                    target: .each, minAge: 10 * day, gate: .ownerAtWildcard,
                    note: "An app update downloaded more than 10 days ago. It has been installed or abandoned."),
        CleanupRule(id: "updates.sparkleSandboxed", category: .oldUpdates, title: "App Update Downloads",
                    paths: ["~/Library/Containers/*/Data/Library/Caches/*/org.sparkle-project.Sparkle/PersistentDownloads/*",
                            "~/Library/Containers/*/Data/Library/Caches/*/org.sparkle-project.Sparkle/Installation/*"],
                    target: .each, needsFullDiskAccess: true, minAge: 10 * day, gate: .ownerAtWildcard,
                    addsPermanentZone: true,
                    note: "An app update downloaded more than 10 days ago. It has been installed or abandoned."),
        CleanupRule(id: "updates.microsoftAutoUpdate", category: .oldUpdates, title: "Microsoft AutoUpdate Cache",
                    paths: ["~/Library/Caches/com.microsoft.autoupdate2"], minAge: day,
                    gate: .bundleIDs(["com.microsoft.autoupdate2"]),
                    note: "Microsoft AutoUpdate's download cache."),
        CleanupRule(id: "updates.spotify", category: .oldUpdates, title: "Spotify Updates",
                    paths: ["~/Library/Application Support/Spotify/PersistentCache/Update/*"], target: .each,
                    minAge: day, gate: .bundleIDs(["com.spotify.client"]), namePatterns: ["*.tbz"],
                    addsPermanentZone: true,
                    note: "An old Spotify updater archive."),
        CleanupRule(id: "updates.microsoftClones", category: .oldUpdates, title: "Pending Microsoft Updates",
                    paths: ["/Library/Caches/com.microsoft.autoupdate.helper/Clones.noindex/*"], target: .each,
                    safety: .review, needsAdmin: true, gate: .bundleIDs(["com.microsoft.autoupdate2"]),
                    note: "A copy of a Microsoft app prepared for a pending update. Removing it cancels that update and may free little (it shares data with the app)."),
        CleanupRule(id: "updates.installers", category: .oldUpdates, title: "macOS Installers",
                    paths: ["/Applications/Install macOS*.app"], target: .each, safety: .review,
                    analyzer: .installerApps,
                    note: "A complete macOS installer. Remove it from Applications if you no longer need it."),
    ]

    static let iosRules: [CleanupRule] = [
        CleanupRule(id: "ios.softwareUpdates", category: .iosSoftwareUpdates, title: "Firmware Files",
                    paths: ["~/Library/iTunes/iPhone Software Updates/*",
                            "~/Library/iTunes/iPad Software Updates/*",
                            "~/Library/iTunes/iPod Software Updates/*"],
                    target: .each, minAge: day, namePatterns: ["*.ipsw"], addsPermanentZone: true,
                    note: "iPhone or iPad firmware. It downloads again when you update or restore a device with this Mac."),
        CleanupRule(id: "ios.configuratorFirmware", category: .iosSoftwareUpdates, title: "Configurator Firmware",
                    paths: ["~/Library/Group Containers/*.group.com.apple.configurator"], target: .findFiles,
                    needsFullDiskAccess: true, minAge: day, namePatterns: ["*.ipsw"], addsPermanentZone: true,
                    maxDepth: 6,
                    note: "Firmware downloaded by Apple Configurator. It downloads again when needed."),
        CleanupRule(id: "ios.photoCache", category: .iosSoftwareUpdates, title: "iOS Photo Cache",
                    paths: ["~/Pictures/iPod Photo Cache"], target: .each, deletion: .trash, needsFullDiskAccess: true,
                    note: "Photos prepared for syncing to a device. They're prepared again on the next sync. Goes to the Trash."),
        CleanupRule(id: "ios.backups", category: .iosBackups, title: "Device Backups",
                    paths: ["~/Library/Application Support/MobileSync/Backup/*"], target: .each, safety: .review,
                    deletion: .trash, needsFullDiskAccess: true, measureBudget: 90, analyzer: .iosBackup,
                    note: "A backup of an iPhone or iPad. Keep at least one recent backup of every device you use. Goes to the Trash."),
    ]

    static let brokenRules: [CleanupRule] = [
        CleanupRule(id: "broken.preferences", category: .brokenPreferences, title: "Preferences",
                    paths: ["~/Library/Preferences/*", "~/Library/Preferences/ByHost/*"], target: .each,
                    deletion: .trash, gate: .ownerFromFileName, analyzer: .brokenPreference,
                    note: "A damaged settings file."),
        CleanupRule(id: "broken.containerPreferences", category: .brokenPreferences, title: "App Preferences",
                    paths: ["~/Library/Containers/*/Data/Library/Preferences/*"], target: .each, deletion: .trash,
                    needsFullDiskAccess: true, gate: .ownerAtWildcard, analyzer: .brokenPreference,
                    note: "A damaged settings file of a sandboxed app."),
        CleanupRule(id: "broken.launchAgents", category: .brokenLoginItems, title: "Launch Agents",
                    paths: ["~/Library/LaunchAgents/*.plist"], target: .each, deletion: .trash,
                    analyzer: .launchAgent,
                    note: "Starts a program that no longer exists. Goes to the Trash."),
        CleanupRule(id: "broken.systemLaunchItems", category: .brokenLoginItems, title: "System Launch Items",
                    paths: ["/Library/LaunchAgents/*.plist", "/Library/LaunchDaemons/*.plist"], target: .each,
                    safety: .review, analyzer: .systemLaunchItems,
                    note: "A system-wide launch item that points to a missing program."),
        CleanupRule(id: "downloads.incomplete", category: .incompleteDownloads, title: "Incomplete Downloads",
                    paths: ["~/Downloads"], target: .findFiles, deletion: .trash, needsFullDiskAccess: true,
                    minAge: day, namePatterns: ["*.download", "*.crdownload", "*.part", "*.partial", "*.opdownload"],
                    maxDepth: 3,
                    note: "A download that never finished. Start it again if you still need it. Goes to the Trash."),
    ]

    static let tempRules: [CleanupRule] = [
        CleanupRule(id: "temp.user", category: .tempFiles, title: "Your Temporary Files",
                    paths: ["$TMPDIR"], target: .files, minAge: 3 * day, ageBasis: .modificationAndAccess,
                    gate: .ownerBelowRow,
                    excludedNames: ["*.lock", "*.lck", "*.pid", "*.sock", ".X*-lock", "*.socket"],
                    ownFilesOnly: true, maxDepth: 6,
                    note: "Temporary files of yours nobody has opened for at least 3 days."),
    ]

    static let insightRules: [CleanupRule] = [
        CleanupRule(id: "info.documentVersions", category: .documentVersions, title: "Document Versions",
                    paths: [], target: .each, safety: .review, analyzer: .documentVersions,
                    note: "Earlier versions of documents, kept by macOS."),
        CleanupRule(id: "info.deletedUsers", category: .deletedUsers, title: "Deleted Users",
                    paths: [], target: .each, safety: .review, analyzer: .deletedUsers,
                    note: "Archived home folders of deleted accounts."),
    ]

    static let mailRules: [CleanupRule] = [
        CleanupRule(id: "mail.downloads", category: .mailAttachments, title: "Opened Attachments",
                    paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*",
                            "~/Library/Mail Downloads/*"],
                    target: .each, needsFullDiskAccess: true, gate: .bundleIDs(["com.apple.mail"]),
                    analyzer: .mailDownload,
                    note: "A copy Mail saved when you opened an attachment. Opening the message gets it again."),
        CleanupRule(id: "mail.stored", category: .mailAttachments, title: "Downloaded Attachments",
                    paths: ["~/Library/Mail"], target: .each, deletion: .trash, needsFullDiskAccess: true,
                    gate: .bundleIDs(["com.apple.mail"]), analyzer: .mailStored,
                    note: "An attachment Mail downloaded with a message."),
    ]

    static let trashRules: [CleanupRule] = [
        CleanupRule(id: "trash.startup", category: .trashBins, title: "Trash",
                    paths: ["~/.Trash/*"], target: .each, excludedNames: [".DS_Store", ".localized"],
                    includeHidden: true, measureBudget: 60,
                    note: "In the Trash of your startup disk."),
        CleanupRule(id: "trash.external", category: .trashBins, title: "Trash on Connected Drives",
                    paths: [], target: .each, excludedNames: [".DS_Store", ".localized"], includeHidden: true,
                    measureBudget: 60, analyzer: .externalTrash,
                    note: "In the Trash of a connected drive."),
        CleanupRule(id: "trash.mail", category: .trashBins, title: "Mail Trash",
                    paths: ["~/Library/Mail"], target: .each, safety: .review, needsFullDiskAccess: true,
                    analyzer: .mailTrash,
                    note: "Deleted messages kept by Mail."),
    ]

    static let logRules: [CleanupRule] = [
        CleanupRule(id: "logs.diagnosticReports", category: .userLogs, title: "Crash Reports",
                    paths: ["~/Library/Logs/DiagnosticReports", "~/Library/DiagnosticReports"], target: .files,
                    minAge: 7 * day, addsPermanentZone: true,
                    note: "Crash, hang and energy reports older than a week."),
        CleanupRule(id: "logs.crashReporter", category: .userLogs, title: "Crash Reporter Data",
                    paths: ["~/Library/Application Support/CrashReporter"], target: .files, minAge: 7 * day,
                    note: "Crash reporter data older than a week."),
        CleanupRule(id: "logs.containers", category: .userLogs, title: "App Logs",
                    paths: ["~/Library/Containers/*/Data/Library/Logs"], target: .files, needsFullDiskAccess: true,
                    minAge: 7 * day, gate: .ownerAtWildcard, addsPermanentZone: true,
                    note: "Logs written by a sandboxed app, older than a week."),
        CleanupRule(id: "logs.user", category: .userLogs, title: "Logs",
                    paths: ["~/Library/Logs/*"], target: .files, minAge: 7 * day, gate: .ownerAtWildcard,
                    note: "Log files older than a week."),
        CleanupRule(id: "logs.systemDiagnosticReports", category: .systemLogs, title: "System Crash Reports",
                    paths: ["/Library/Logs/DiagnosticReports"], target: .files, needsAdmin: true, minAge: 7 * day,
                    note: "Crash and hang reports of system services, older than a week."),
        CleanupRule(id: "logs.system", category: .systemLogs, title: "System Logs",
                    paths: ["/Library/Logs/*"], target: .files, needsAdmin: true, minAge: 7 * day,
                    note: "Log files of system components, older than a week."),
        CleanupRule(id: "logs.var", category: .systemLogs, title: "macOS Service Logs",
                    paths: ["/private/var/log"], target: .files, needsAdmin: true, minAge: 7 * day,
                    note: "Logs of macOS services, older than a week."),
    ]

    static let cacheRules: [CleanupRule] = [
        CleanupRule(id: "caches.gpuShaders", category: .systemCaches, title: "GPU Shader Caches",
                    paths: ["$DARWIN_CACHE/*/com.apple.metal", "$DARWIN_CACHE/*/com.apple.metalfe",
                            "$DARWIN_CACHE/*/com.apple.gpuarchiver"],
                    minAge: day, gate: .ownerAtWildcard,
                    note: "Compiled GPU shaders. Apps compile them again on first use."),
        CleanupRule(id: "caches.system", category: .systemCaches, title: "System Caches",
                    paths: ["/Library/Caches/*"], needsAdmin: true, minAge: 7 * day, gate: .ownerAtWildcard,
                    note: "A cache shared by system services, untouched for a week."),
        CleanupRule(id: "caches.containers", category: .userCaches, title: "App Caches",
                    paths: ["~/Library/Containers/*/Data/Library/Caches"], needsFullDiskAccess: true, minAge: hour,
                    gate: .ownerAtWildcard,
                    reviewNames: ["com.apple.Photos", "com.apple.photolibraryd", "com.apple.mediaanalysisd",
                                  "com.apple.photoanalysisd"],
                    addsPermanentZone: true,
                    note: "Cache of a sandboxed app, rebuilt as needed."),
        CleanupRule(id: "caches.groupContainers", category: .userCaches, title: "Shared App Caches",
                    paths: ["~/Library/Group Containers/*/Library/Caches"], needsFullDiskAccess: true, minAge: hour,
                    gate: .ownerAtWildcard, reviewNames: ["*.com.apple.*", "group.com.apple.*", "com.apple.*"],
                    addsPermanentZone: true,
                    note: "Cache shared by a family of apps, rebuilt as needed."),
        CleanupRule(id: "caches.user", category: .userCaches, title: "App Caches",
                    paths: ["~/Library/Caches/*"], minAge: hour, gate: .ownerAtWildcard,
                    reviewNames: ["com.apple.akd", "com.apple.photoanalysisd", "com.apple.mediaanalysisd"],
                    note: "Data this app keeps to load faster. It's rebuilt as needed."),
    ]

    /// All rules, specific before generic (see the type documentation).
    public static let rules: [CleanupRule] =
        xcodeRules + devRules + updateRules + iosRules + brokenRules + tempRules + insightRules
        + mailRules + trashRules + logRules + cacheRules

    // MARK: Permanent zones

    /// Whether `zone` is a legitimate permanent-removal folder for `rule`: it must be
    /// matched by one of the rule's own patterns (contents/files rows) or be the parent
    /// of something they match (each/findFiles rows).
    public static func isDeclaredZone(_ zone: String, rule: CleanupRule, context: CleanupContext) -> Bool {
        guard rule.addsPermanentZone || rule.analyzer == .externalTrash else { return false }
        let zoneComps = CleanupPaths.components(zone.lowercased())
        guard zoneComps.count >= 3 else { return false }
        if rule.analyzer == .externalTrash {
            return context.externalVolumes.contains { volume in
                CleanupPaths.components((volume.path + "/.Trashes/\(context.uid)").lowercased()) == zoneComps
            }
        }
        for raw in rule.paths {
            guard let absolute = CleanupScanner.resolveToken(raw, context: context) else { continue }
            let pattern = CleanupPattern(absolute: absolute)
            switch rule.target {
            case .contents, .files:
                if pattern.lowered.count == zoneComps.count && pattern.covers(zoneComps) { return true }
            case .each:
                let parentPattern = CleanupPattern(absolute: CleanupPaths.join(Array(pattern.components.dropLast())))
                if parentPattern.lowered.count == zoneComps.count && parentPattern.covers(zoneComps) { return true }
            case .findFiles:
                if pattern.covers(zoneComps) { return true }
            }
        }
        return false
    }
}
