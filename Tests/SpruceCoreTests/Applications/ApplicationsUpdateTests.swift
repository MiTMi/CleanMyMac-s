import Foundation
import XCTest
@testable import SpruceCore

final class ApplicationsUpdateTests: XCTestCase {

    func testITunesLookupDecodingAndUpdate() {
        let json = """
        {"resultCount":1,"results":[{"bundleId":"com.example.notes","trackId":12345,"trackName":"Notes Pro",
        "version":"3.2","trackViewUrl":"https://apps.apple.com/us/app/notes-pro/id12345?mt=12&uo=4",
        "releaseNotes":"Bug fixes.","currentVersionReleaseDate":"2024-09-01T10:00:00Z","minimumOsVersion":"12.0",
        "sellerName":"Example Inc.","fileSizeBytes":"45678901"}]}
        """
        let results = ApplicationsITunes.decode(Data(json.utf8))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].fileSizeBytes, 45_678_901)
        XCTAssertEqual(results[0].storeURL?.absoluteString, "macappstore://apps.apple.com/us/app/notes-pro/id12345")
        XCTAssertNotNil(results[0].releaseDate)

        let app = ApplicationsAppInfo(path: "/Applications/Notes Pro.app", name: "Notes Pro", bundleID: "com.example.notes",
                                      version: "3.1", source: .appStore)
        let update = ApplicationsITunes.update(from: results[0], app: app, currentOS: "14.5")
        XCTAssertEqual(update?.availableVersion, "3.2")
        XCTAssertEqual(update?.source, .appStore)
        XCTAssertEqual(update?.releaseNotes, "Bug fixes.")

        var direct = app
        direct.source = .other
        XCTAssertNil(ApplicationsITunes.update(from: results[0], app: direct, currentOS: "14.5"), "no receipt, no App Store update")
        XCTAssertNil(ApplicationsITunes.update(from: results[0], app: app, currentOS: "11.0"), "needs a newer macOS")
        XCTAssertTrue(ApplicationsITunes.lookupURL(bundleID: "com.example.notes", country: "US")!.absoluteString
            .contains("bundleId=com.example.notes&country=us&entity=desktopSoftware"))
    }

    func testHomebrewParsingAndMatching() {
        let info = """
        {"formulae":[],"casks":[
          {"token":"firefox","name":["Mozilla Firefox"],"version":"121.0","installed":"120.0","auto_updates":true,
           "homepage":"https://www.mozilla.org/firefox/","artifacts":[{"app":["Firefox.app"]},{"zap":[{"trash":["~/x"]}]}]},
          {"token":"renamed","name":["Renamed"],"version":"2.0,200","installed":"1.0,100",
           "artifacts":[{"app":["Original.app",{"target":"Renamed App.app"}]}]},
          {"token":"selfupdated","name":["Self"],"version":"5.0","installed":"4.0","artifacts":[{"app":["Self.app"]}]}
        ]}
        """
        let casks = ApplicationsHomebrew.parseInfo(Data(info.utf8))
        XCTAssertEqual(casks.map(\.token), ["firefox", "renamed", "selfupdated"])
        XCTAssertEqual(casks[0].appArtifacts, ["Firefox.app"])
        XCTAssertEqual(casks[1].appArtifacts, ["Renamed App.app"])
        XCTAssertTrue(casks[0].autoUpdates)
        XCTAssertEqual(ApplicationsHomebrew.caskTokens(casks: casks)["renamed app.app"], "renamed")

        let outdatedJSON = """
        {"formulae":[],"casks":[
          {"name":"firefox","installed_versions":["120.0"],"current_version":"121.0","pinned":false,"pinned_version":null},
          {"name":"renamed","installed_versions":"1.0,100","current_version":"2.0,200"},
          {"name":"selfupdated","installed_versions":["4.0"],"current_version":"5.0"}
        ]}
        """
        let outdated = ApplicationsHomebrew.parseOutdated(Data(outdatedJSON.utf8))
        XCTAssertEqual(outdated.count, 3)
        XCTAssertEqual(outdated[1].installedVersions, ["1.0,100"])

        let apps = [
            ApplicationsAppInfo(path: "/Applications/Firefox.app", name: "Firefox", bundleID: "org.mozilla.firefox", version: "120.0", build: "12024.1"),
            ApplicationsAppInfo(path: "/Applications/Renamed App.app", name: "Renamed App", bundleID: "com.r.app", version: "1.0", build: "100"),
            // The app already updated itself to 5.0; Homebrew's record is stale.
            ApplicationsAppInfo(path: "/Applications/Self.app", name: "Self", bundleID: "com.self.app", version: "5.0", build: "500"),
        ]
        let updates = ApplicationsHomebrew.updates(outdated: outdated, casks: casks, apps: apps)
        XCTAssertEqual(updates.map(\.name), ["Firefox", "Renamed App"])
        XCTAssertEqual(updates[0].caskToken, "firefox")
        XCTAssertEqual(updates[1].availableVersion, "2.0")
        XCTAssertTrue(updates[1].isMajor)
        XCTAssertTrue(updates[0].isUnattended)
    }

    func testIgnoreAndSourcePrecedence() {
        let sparkle = ApplicationsUpdate(appPath: "/Applications/A.app", bundleID: "com.a.app", name: "A",
                                         installedVersion: "1", availableVersion: "2", source: .sparkle)
        let brew = ApplicationsUpdate(appPath: "/Applications/A.app", bundleID: "com.a.app", name: "A",
                                      installedVersion: "1", availableVersion: "2", source: .homebrew, caskToken: "a")
        let other = ApplicationsUpdate(appPath: "/Applications/B.app", bundleID: "com.b.app", name: "B",
                                       installedVersion: "1", availableVersion: "1.1", source: .sparkle)
        let filtered = ApplicationsUpdateIgnore.filtered([sparkle, brew, other], ignoredItemIDs: [])
        XCTAssertEqual(filtered.map(\.source), [.homebrew, .sparkle])
        XCTAssertEqual(filtered.map(\.name), ["A", "B"])

        let skipped = ApplicationsUpdateIgnore.filtered([sparkle, other], ignoredItemIDs: [other.skipVersionKey])
        XCTAssertEqual(skipped.map(\.name), ["A"])
        let ignoredApp = ApplicationsUpdateIgnore.filtered([sparkle, other], ignoredItemIDs: [sparkle.ignoreAppKey])
        XCTAssertEqual(ignoredApp.map(\.name), ["B"])
        let newer = ApplicationsUpdate(appPath: "/Applications/B.app", bundleID: "com.b.app", name: "B",
                                       installedVersion: "1", availableVersion: "1.2", source: .sparkle)
        XCTAssertEqual(ApplicationsUpdateIgnore.filtered([newer], ignoredItemIDs: [other.skipVersionKey]).count, 1,
                       "skipping a version does not hide later versions")
        XCTAssertTrue(ApplicationsUpdateIgnore.filtered([sparkle], ignoredItemIDs: [], ignoredBundleIDs: ["COM.A.APP"]).isEmpty)
    }

    func testHTMLToText() {
        let html = "<h1>What&#39;s new</h1><p>Better <b>sync</b>&nbsp;and more.</p><ul><li class=\"x\">One</li><li>Two &amp; three</li></ul><script>alert(1)</script>"
        XCTAssertEqual(ApplicationsHTMLText.plainText(html), "What's new\n\nBetter sync and more.\n\n• One\n• Two & three")
        XCTAssertEqual(ApplicationsHTMLText.plainText("Plain\n\n\n\ntext  "), "Plain\n\ntext")
    }
}

final class ApplicationsExtensionTests: XCTestCase {

    let output = """
    +    com.foo.ShareExt(1.2)
                Path = /Applications/Foo.app/Contents/PlugIns/ShareExt.appex
                UUID = 1234
                 SDK = com.apple.share-services
       Parent Bundle = /Applications/Foo.app
        Display Name = Foo Share
         Parent Name = Foo

    -    com.bar.Finder(3.0)
                Path = /Applications/Bar.app/Contents/PlugIns/FinderExt.appex
                 SDK = com.apple.FinderSync
       Parent Bundle = /Applications/Bar.app

         com.apple.share.Mail.compose(16.0)
                Path = /System/Applications/Mail.app/Contents/PlugIns/MailShareExtension.appex
                 SDK = com.apple.share-services

         com.foo.ShareExt(1.1)
                Path = /Users/x/Old/Foo.app/Contents/PlugIns/ShareExt.appex
                 SDK = com.apple.share-services
    """

    func testParsesPluginKitOutput() {
        let entries = ApplicationsPluginKit.parse(output)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].identifier, "com.foo.ShareExt")
        XCTAssertEqual(entries[0].version, "1.2")
        XCTAssertEqual(entries[0].election, "+")
        XCTAssertEqual(entries[0].displayName, "Foo Share")
        XCTAssertEqual(entries[1].election, "-")
        XCTAssertFalse(entries[1].isEnabled)
        XCTAssertNil(entries[2].election)
        XCTAssertTrue(entries[2].isEnabled)

        let extensions = ApplicationsPluginKit.extensions(from: entries)
        XCTAssertEqual(extensions.map(\.identifier), ["com.foo.ShareExt", "com.bar.Finder"], "no Apple items, one per identifier")
        XCTAssertEqual(extensions[0].category, "Share Menu")
        XCTAssertEqual(extensions[1].category, "Finder")
        XCTAssertEqual(extensions[1].hostAppName, "Bar")
        XCTAssertEqual(extensions[1].name, "FinderExt")
        XCTAssertTrue(extensions[0].canToggle)
        XCTAssertFalse(extensions[0].canRemove)
    }

    func testPluginFilesCatalog() {
        let tree = ApplicationsTempTree()
        let home = tree.path("home")
        tree.plist("home/Library/QuickLook/Markdown.qlgenerator/Contents/Info.plist",
                   ["CFBundleName": "QLMarkdown", "CFBundleIdentifier": "com.ql.markdown", "CFBundleShortVersionString": "1.0"])
        tree.dir("home/Library/Screen Savers/Aerial.saver")
        tree.file("home/Library/Services/Resize.workflow/Contents/document.wflow")
        tree.file("home/Library/PreferencePanes/readme.txt")
        let locations = ApplicationsExtensionCatalog.locations(home: home).filter(\.isUserDomain)
        let files = ApplicationsExtensionCatalog.files(locations: locations, info: ApplicationsExtensionCatalog.bundleInfo(atPath:))
        let byKind = Dictionary(grouping: files, by: \.kind)
        XCTAssertEqual(byKind[.quickLook]?.first?.name, "QLMarkdown")
        XCTAssertEqual(byKind[.quickLook]?.first?.identifier, "com.ql.markdown")
        XCTAssertEqual(byKind[.screenSaver]?.first?.name, "Aerial")
        XCTAssertEqual(byKind[.service]?.first?.name, "Resize")
        XCTAssertNil(byKind[.preferencePane])
        XCTAssertTrue(files.allSatisfy { $0.canRemove && !$0.canToggle })
    }
}
