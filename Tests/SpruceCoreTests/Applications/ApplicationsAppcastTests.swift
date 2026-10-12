import Foundation
import XCTest
@testable import SpruceCore

final class ApplicationsAppcastTests: XCTestCase {

    let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Foo Changelog</title>
        <item>
          <title>Version 2.1</title>
          <pubDate>Tue, 10 Sep 2024 14:03:00 +0000</pubDate>
          <sparkle:version>210</sparkle:version>
          <sparkle:shortVersionString>2.1</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
          <description><![CDATA[<h2>New</h2><ul><li>Faster sync</li><li>Fixed &amp; improved</li></ul>]]></description>
          <enclosure url="https://example.com/Foo-2.1.zip" length="12345678" type="application/octet-stream" sparkle:edSignature="abc"/>
        </item>
        <item>
          <title>Version 2.2 beta</title>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/Foo-2.2b1.zip" sparkle:version="220" sparkle:shortVersionString="2.2b1" length="1"/>
        </item>
        <item>
          <title>Version 3.0</title>
          <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/Foo-3.0.zip" sparkle:version="300" sparkle:shortVersionString="3.0" length="1"/>
        </item>
        <item>
          <title>Version 2.0</title>
          <sparkle:releaseNotesLink>https://example.com/notes/2.0.html</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/Foo-2.0.zip" sparkle:version="200" sparkle:shortVersionString="2.0" length="1"/>
        </item>
      </channel>
    </rss>
    """

    func testParsesItemsElementsAndEnclosureAttributes() {
        let items = ApplicationsAppcast.parse(Data(feed.utf8))
        XCTAssertEqual(items.count, 4)
        let first = items[0]
        XCTAssertEqual(first.version, "210")
        XCTAssertEqual(first.shortVersion, "2.1")
        XCTAssertEqual(first.minimumSystemVersion, "12.0")
        XCTAssertEqual(first.enclosureURL, "https://example.com/Foo-2.1.zip")
        XCTAssertEqual(first.enclosureLength, 12_345_678)
        XCTAssertNotNil(first.pubDate)
        XCTAssertTrue(first.descriptionText?.contains("Faster sync") == true)
        XCTAssertNil(first.channel, "the RSS <channel> element must not be read as a Sparkle channel")
        XCTAssertEqual(items[1].channel, "beta")
        XCTAssertEqual(items[1].version, "220")
        XCTAssertEqual(items[1].shortVersion, "2.2b1")
        XCTAssertEqual(items[3].releaseNotesLink, "https://example.com/notes/2.0.html")
    }

    func testBestItemSkipsBetasAndUnsupportedOS() {
        let items = ApplicationsAppcast.parse(Data(feed.utf8))
        let best = ApplicationsAppcast.bestItem(items, currentOS: "14.5.0")
        XCTAssertEqual(best?.shortVersion, "2.1")
        let withBetas = ApplicationsAppcast.bestItem(items, currentOS: "14.5.0", includePrereleases: true)
        XCTAssertEqual(withBetas?.shortVersion, "2.2b1")
        XCTAssertNil(ApplicationsAppcast.bestItem(items, currentOS: "11.0").flatMap { $0.shortVersion == "2.1" ? $0 : nil })
    }

    func testUnescapedHTMLDescriptionIsKept() {
        let xml = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <title>1.1</title><description><ul><li>One</li><li>Two</li></ul></description>
        <enclosure url="https://e.com/a.dmg" sparkle:version="11" sparkle:shortVersionString="1.1"/>
        </item></channel></rss>
        """
        let items = ApplicationsAppcast.parse(Data(xml.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(ApplicationsHTMLText.plainText(items[0].descriptionText ?? ""), "• One\n• Two")
    }

    func testUpdateFromAppcast() {
        let items = ApplicationsAppcast.parse(Data(feed.utf8))
        let best = ApplicationsAppcast.bestItem(items, currentOS: "14.5.0")!
        let app = ApplicationsAppInfo(path: "/Applications/Foo.app", name: "Foo", bundleID: "com.example.foo",
                                      version: "2.0", build: "200", sparkleFeedURL: "https://example.com/appcast.xml")
        let update = ApplicationsUpdate.fromAppcast(best, app: app, feedURL: nil)
        XCTAssertEqual(update?.availableVersion, "2.1")
        XCTAssertEqual(update?.installedVersion, "2.0")
        XCTAssertEqual(update?.source, .sparkle)
        XCTAssertEqual(update?.downloadURL?.absoluteString, "https://example.com/Foo-2.1.zip")
        XCTAssertEqual(update?.releaseNotes, "New\n\n• Faster sync\n• Fixed & improved")
        XCTAssertFalse(update?.isMajor ?? true)

        let current = ApplicationsAppInfo(path: "/Applications/Foo.app", name: "Foo", bundleID: "com.example.foo",
                                          version: "2.1", build: "210")
        XCTAssertNil(ApplicationsUpdate.fromAppcast(best, app: current, feedURL: nil))
    }

    func testDates() {
        XCTAssertNotNil(ApplicationsAppcast.parseDate("Tue, 10 Sep 2024 14:03:00 +0000"))
        XCTAssertNotNil(ApplicationsAppcast.parseDate("Wed, 2 Oct 2024 09:00:00 -0700"))
        XCTAssertNil(ApplicationsAppcast.parseDate("not a date"))
    }
}
