import XCTest
@testable import SpruceCore

final class PerformanceLaunchctlTests: XCTestCase {
    let printOutput = """
    gui/501 = {
    \ttype = login
    \thandle = 501
    \tactive count = 412
    \tsecurity context = {
    \t\tuid unset
    \t\tasid = 100018
    \t}

    \tsubdomains = {
    \t\tpid/1234
    \t}

    \tservices = {
    \t\t       0      -       com.example.idle
    \t\t     603      -       com.example.running
    \t\t       0     78       com.example.crashed
    \t\t       -      -       com.example.dash
    \t}

    \tendpoints = {
    \t\t"com.example.endpoint" = {
    \t\t\tport = 0x1234
    \t\t}
    \t}

    \tdisabled services = {
    \t\t"com.example.off" => disabled
    \t}
    }
    """

    func testParsesServicesBlock() {
        let services = PerformanceLaunchctl.services(fromPrint: printOutput)
        XCTAssertEqual(Set(services.keys), ["com.example.idle", "com.example.running", "com.example.crashed", "com.example.dash"])
        XCTAssertNil(services["com.example.idle"]?.pid)
        XCTAssertEqual(services["com.example.running"]?.pid, 603)
        XCTAssertEqual(services["com.example.crashed"]?.lastExitStatus, "78")
        XCTAssertNil(services["com.example.dash"]?.pid)
        XCTAssertTrue(PerformanceLaunchctl.services(fromPrint: "garbage").isEmpty)
    }

    func testParsesLaunchctlList() {
        let list = "PID\tStatus\tLabel\n-\t0\tcom.example.a\n512\t0\tcom.example.b\n"
        let services = PerformanceLaunchctl.services(fromList: list)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services["com.example.b"]?.pid, 512)
        XCTAssertNil(services["com.example.a"]?.pid)
    }

    func testParsesPrintDisabledBothFormats() {
        let modern = """
        disabled services = {
        \t"com.example.off" => disabled
        \t"com.example.on" => enabled
        }

        login item associations = {
        \t"com.example.helper" => "com.example.App"
        }
        """
        let m = PerformanceLaunchctl.disabledOverrides(fromPrintDisabled: modern)
        XCTAssertEqual(m, ["com.example.off": true, "com.example.on": false])

        let legacy = "disabled services = {\n\t\"com.old.off\" => true\n\t\"com.old.on\" => false\n}\n"
        XCTAssertEqual(PerformanceLaunchctl.disabledOverrides(fromPrintDisabled: legacy), ["com.old.off": true, "com.old.on": false])
    }

    func testToggleCommandsAndTargets() {
        XCTAssertEqual(PerformanceLaunchctl.serviceTarget(domain: .userAgent, uid: 501, label: "com.x"), "gui/501/com.x")
        XCTAssertEqual(PerformanceLaunchctl.serviceTarget(domain: .globalAgent, uid: 501, label: "com.x"), "gui/501/com.x")
        XCTAssertEqual(PerformanceLaunchctl.serviceTarget(domain: .systemDaemon, uid: 501, label: "com.x"), "system/com.x")
        XCTAssertEqual(PerformanceLaunchctl.toggleCommands(enable: false, domain: .systemDaemon, uid: 501, label: "com.x",
                                                           plistPath: "/Library/LaunchDaemons/com.x.plist"),
                       [["bootout", "system/com.x"], ["disable", "system/com.x"]])
        XCTAssertEqual(PerformanceLaunchctl.toggleCommands(enable: true, domain: .userAgent, uid: 501, label: "com.x",
                                                           plistPath: "/Users/t/Library/LaunchAgents/com.x.plist"),
                       [["enable", "gui/501/com.x"], ["bootstrap", "gui/501", "/Users/t/Library/LaunchAgents/com.x.plist"]])
    }

    func testSafeLabels() {
        XCTAssertTrue(PerformanceLaunchctl.isSafeLabel("com.google.keystone.agent"))
        XCTAssertTrue(PerformanceLaunchctl.isSafeLabel("org.pqrs.karabiner_grabber-1"))
        XCTAssertFalse(PerformanceLaunchctl.isSafeLabel(""))
        XCTAssertFalse(PerformanceLaunchctl.isSafeLabel("com.x; rm -rf /"))
        XCTAssertFalse(PerformanceLaunchctl.isSafeLabel("com.x\nother"))
        XCTAssertFalse(PerformanceLaunchctl.isSafeLabel("../../etc"))
    }
}

final class PerformanceSystemParserTests: XCTestCase {
    func testVPNDetection() {
        let connected = "Available network connection services in the current set (*=enabled):\n* (Connected)   1A2B PPP --> L2TP \"Work VPN\" [PPP:L2TP]\n"
        XCTAssertTrue(PerformanceSystemParsers.vpnConnected(scutilNCList: connected))
        let idle = "Available network connection services in the current set (*=enabled):\n* (Disconnected) 1A2B VPN \"Work\"\n"
        XCTAssertFalse(PerformanceSystemParsers.vpnConnected(scutilNCList: idle))
    }

    func testSpotlightStatus() {
        XCTAssertEqual(PerformanceSystemParsers.spotlightIndexingEnabled(mdutilStatus: "/:\n\tIndexing enabled. \n"), true)
        XCTAssertEqual(PerformanceSystemParsers.spotlightIndexingEnabled(mdutilStatus: "/:\n\tIndexing disabled.\n"), false)
        XCTAssertNil(PerformanceSystemParsers.spotlightIndexingEnabled(mdutilStatus: "Error: unknown"))
    }

    func testSQLiteReadouts() {
        let counts = PerformanceSystemParsers.sqlitePageCounts("51234\n4120\n")
        XCTAssertEqual(counts?.pageCount, 51234)
        XCTAssertEqual(counts?.freelistCount, 4120)
        XCTAssertNil(PerformanceSystemParsers.sqlitePageCounts("Error: unable to open database"))
        XCTAssertTrue(PerformanceSystemParsers.integrityOK("ok\n"))
        XCTAssertFalse(PerformanceSystemParsers.integrityOK("*** in database main ***\nPage 12 is never used"))
    }

    func testMailIndexLocation() {
        let home = "/Users/t"
        let dirs = ["/Users/t/Library/Mail": ["V2", "V10", "V9", "PersistenceInfo.plist", "Vx"]]
        let files: Set<String> = ["/Users/t/Library/Mail/V10/MailData/Envelope Index",
                                  "/Users/t/Library/Mail/V2/MailData/Envelope Index"]
        let path = PerformanceMailIndex.locate(home: home, fileExists: { files.contains($0) }, list: { dirs[$0] })
        XCTAssertEqual(path, "/Users/t/Library/Mail/V10/MailData/Envelope Index")
        XCTAssertNil(PerformanceMailIndex.locate(home: home, fileExists: { _ in false }, list: { dirs[$0] }))
        XCTAssertNil(PerformanceMailIndex.locate(home: home, fileExists: { _ in true }, list: { _ in nil }))
        XCTAssertEqual(PerformanceMailIndex.companionPaths(for: "/a/Envelope Index"),
                       ["/a/Envelope Index", "/a/Envelope Index-wal", "/a/Envelope Index-shm"])
    }

    func testLaunchServicesDump() {
        let dump = """
        bundle id:                  12345
        path:                       /Applications/Safari.app (0x1a2b)
        path:                       /Applications/Deleted.app (0x3c4d)
        path:                       /Applications/Deleted.app (0x3c4e)
        path: /Users/t/Downloads/Old Thing.app
        path:                       /Volumes/Offline/Tool.app (0x99)
        path:                       /System/Applications/Gone.app (0x77)
        path:                       /Applications/Foo.app/Contents/Resources/doc.pdf (0x1)
        name:                       Deleted
        """
        XCTAssertEqual(PerformanceLaunchServices.registeredAppPaths(fromDump: dump),
                       ["/Applications/Safari.app", "/Applications/Deleted.app", "/Users/t/Downloads/Old Thing.app",
                        "/Volumes/Offline/Tool.app", "/System/Applications/Gone.app"])
        let stale = PerformanceLaunchServices.stalePaths(fromDump: dump, fileExists: { $0 == "/Applications/Safari.app" })
        XCTAssertEqual(stale, ["/Applications/Deleted.app", "/Users/t/Downloads/Old Thing.app"])
        XCTAssertEqual(PerformanceLaunchServices.stalePaths(fromDump: dump, fileExists: { _ in false }, limit: 1).count, 1)
    }

    func testHomePermissionProblems() {
        let home = "/Users/t"
        let fine = PerformanceHomePermissions.problems(home: home, uid: 501, ownerOf: { _ in 501 }, isWritable: { _ in true },
                                                       exists: { _ in true })
        XCTAssertTrue(fine.isEmpty)
        let bad = PerformanceHomePermissions.problems(home: home, uid: 501,
                                                      ownerOf: { $0 == "/Users/t/Library/Caches" ? 0 : 501 },
                                                      isWritable: { $0 != "/Users/t/Library/Preferences" },
                                                      exists: { _ in true })
        XCTAssertEqual(bad, ["~/Library/Preferences isn't writable", "~/Library/Caches is owned by another account"])
        let foreignHome = PerformanceHomePermissions.problems(home: home, uid: 501, ownerOf: { _ in 0 }, isWritable: { _ in true },
                                                              exists: { $0 == home })
        XCTAssertEqual(foreignHome, ["Your home folder is owned by another account"])
    }

    func testHomePermissionsOnRealTempFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let uid = (try FileManager.default.attributesOfItem(atPath: dir.path)[.ownerAccountID] as? NSNumber)?.uint32Value ?? 0
        let problems = PerformanceHomePermissions.problems(
            home: dir.path, uid: uid,
            ownerOf: { path in (try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountID] as? NSNumber)?.uint32Value },
            isWritable: { FileManager.default.isWritableFile(atPath: $0) },
            exists: { FileManager.default.fileExists(atPath: $0) })
        XCTAssertTrue(problems.isEmpty, "\(problems)")
    }
}

final class PerformanceConsumerTests: XCTestCase {
    let ps = """
        0     0     0   9.5  12345 kernel_task
        1     0     0   0.1   8000 /sbin/launchd
      410     1   501  45.0 900000 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      415   410   501  30.5 600000 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
      500     1   501   2.0  50000 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
      600     1   501  70.0 300000 /usr/local/bin/node
      700     1     0  12.0 100000 /usr/libexec/syspolicyd
      800     1   501   0,5  20000 /usr/bin/some tool with spaces
      900     1   501   1.0  10000 /Applications/Spruce.app/Contents/MacOS/Spruce
    bad line here
    """

    func testParsesPsOutput() {
        let samples = PerformanceProcessParser.parse(ps)
        XCTAssertEqual(samples.count, 9)
        XCTAssertEqual(samples[0].name, "kernel_task")
        XCTAssertEqual(samples[2].pid, 410)
        XCTAssertEqual(samples[2].residentBytes, 900_000 * 1024)
        XCTAssertEqual(samples[3].ppid, 410)
        XCTAssertEqual(samples[7].path, "/usr/bin/some tool with spaces")
        XCTAssertEqual(samples[7].cpu, 0.5, accuracy: 0.001)
    }

    func testAggregatesAppsAndProtectsSystem() {
        let samples = PerformanceProcessParser.parse(ps)
        let byCPU = PerformanceConsumerAggregator.aggregate(samples, userUID: 501, ownPID: 900, sort: .cpu)
        let chrome = byCPU.first!
        XCTAssertEqual(chrome.name, "Google Chrome")
        XCTAssertEqual(chrome.pids, [410, 415])
        XCTAssertEqual(chrome.primaryPID, 410)
        XCTAssertEqual(chrome.cpu, 75.5, accuracy: 0.001)
        XCTAssertTrue(chrome.canQuit)
        XCTAssertTrue(chrome.isApp)

        let node = byCPU.first { $0.name == "node" }!
        XCTAssertTrue(node.canQuit)
        XCTAssertFalse(node.isApp)
        XCTAssertFalse(byCPU.first { $0.name == "Finder" }!.canQuit)
        XCTAssertFalse(byCPU.first { $0.name == "kernel_task" }!.canQuit)
        XCTAssertEqual(byCPU.first { $0.name == "syspolicyd" }?.protectedReason, "macOS needs it running")
        XCTAssertEqual(byCPU.first { $0.name == "launchd" }?.protectedReason, "macOS needs it running")
        XCTAssertEqual(byCPU.first { $0.name == "Spruce" }?.protectedReason, "This is Spruce")
        XCTAssertEqual(byCPU.first { $0.name == "some tool with spaces" }?.protectedReason, "Part of macOS")

        let byMemory = PerformanceConsumerAggregator.aggregate(samples, userUID: 501, ownPID: 900, sort: .memory, limit: 2)
        XCTAssertEqual(byMemory.count, 2)
        XCTAssertEqual(byMemory[0].name, "Google Chrome")
        XCTAssertEqual(byMemory[1].name, "node")
    }

    func testHeavyThresholds() {
        let heavy = PerformanceConsumer(id: "a", name: "a", appPath: nil, pids: [1], primaryPID: 1, cpu: 80,
                                        memoryBytes: 2_000_000_000, ownedByUser: true, protectedReason: nil)
        let h = PerformanceConsumerAggregator.isHeavy(heavy, totalMemory: 16_000_000_000)
        XCTAssertTrue(h.cpu)
        XCTAssertTrue(h.memory)
        let light = PerformanceConsumer(id: "b", name: "b", appPath: nil, pids: [2], primaryPID: 2, cpu: 3,
                                        memoryBytes: 200_000_000, ownedByUser: true, protectedReason: nil)
        let l = PerformanceConsumerAggregator.isHeavy(light, totalMemory: 16_000_000_000)
        XCTAssertFalse(l.cpu)
        XCTAssertFalse(l.memory)
    }
}

final class PerformanceLaunchServicesDumpReaderTests: XCTestCase {
    private let dump = """
    bundle id:                  12345
    \tpath:                       /Applications/Safari.app (0x1a2b)\r
    path:                       /Applications/Deleted.app (0x3c4d)
    path:                       /Applications/Deleted.app (0x3c4e)
    name:                       path: /Applications/NotAPathLine.app
    path: /Users/t/Downloads/Old Thing.app
    path:                       /Applications/Foo.app/Contents/Resources/doc.pdf (0x1)
    path:                       /Applications/Ünïcode.app (0x5)
    path:                       /Applications/Last.app
    """
    private let expected = ["/Applications/Safari.app", "/Applications/Deleted.app", "/Users/t/Downloads/Old Thing.app",
                            "/Applications/Ünïcode.app", "/Applications/Last.app"]

    func testSameResultWhateverTheChunkSize() {
        let data = Data(dump.utf8)
        XCTAssertEqual(PerformanceLaunchServices.registeredAppPaths(fromDump: dump), expected)
        for size in [1, 2, 3, 7, 16, 64, data.count] {
            var reader = PerformanceLaunchServicesDumpReader()
            var offset = 0
            while offset < data.count {
                let end = min(offset + size, data.count)
                reader.consume(data.subdata(in: offset..<end))
                offset = end
            }
            reader.finish()
            XCTAssertEqual(reader.paths, expected, "chunk size \(size)")
            XCTAssertEqual(reader.byteCount, data.count)
        }
    }

    func testOverlongLinesAreSkippedNotBuffered() {
        let long = "path: /" + String(repeating: "x", count: PerformanceLaunchServicesDumpReader.maxLineLength) + ".app\n"
        let text = long + "path: /Applications/After.app\n" + String(long.dropLast())
        let data = Data(text.utf8)
        for size in [5, 1000, data.count] {
            var reader = PerformanceLaunchServicesDumpReader()
            var offset = 0
            while offset < data.count {
                let end = min(offset + size, data.count)
                reader.consume(data.subdata(in: offset..<end))
                offset = end
            }
            reader.finish()
            XCTAssertEqual(reader.paths, ["/Applications/After.app"], "chunk size \(size)")
        }
    }

    func testStalePathsFromCollectedList() {
        let stale = PerformanceLaunchServices.stalePaths(from: expected, fileExists: { $0 == "/Applications/Safari.app" })
        XCTAssertEqual(stale, ["/Applications/Deleted.app", "/Users/t/Downloads/Old Thing.app", "/Applications/Ünïcode.app",
                               "/Applications/Last.app"])
    }
}
