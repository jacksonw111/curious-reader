import Foundation
@testable import ReaderEPUB
import XCTest

final class EPUBParsingTests: XCTestCase {
    func testContainerParserExtractsRootFilePath() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let url = try writeTempFile(named: "container.xml", content: xml)

        let parser = EPUBContainerParser()
        let path = try parser.parse(containerURL: url)
        XCTAssertEqual(path, "OEBPS/content.opf")
    }

    func testPackageParserExtractsTitleAndFirstSpineHref() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Sample EPUB Title</dc:title>
          </metadata>
          <manifest>
            <item id="chap1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="chap2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chap2"/>
            <itemref idref="chap1"/>
          </spine>
        </package>
        """
        let url = try writeTempFile(named: "content.opf", content: opf)

        let parser = EPUBPackageParser()
        let info = try parser.parse(packageURL: url)
        XCTAssertEqual(info.title, "Sample EPUB Title")
        XCTAssertEqual(info.firstSpineHref, "text/chapter2.xhtml")
    }

    func testPackageParserExtractsNavNcxAndCoverHints() throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Sample EPUB Title</dc:title>
            <meta name="cover" content="cover-image"/>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            <item id="chapter" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine toc="ncx">
            <itemref idref="chapter"/>
          </spine>
          <guide>
            <reference type="cover" title="Cover" href="text/cover.xhtml"/>
          </guide>
        </package>
        """
        let url = try writeTempFile(named: "content.opf", content: opf)

        let parser = EPUBPackageParser()
        let info = try parser.parse(packageURL: url)
        XCTAssertEqual(info.navHref, "nav.xhtml")
        XCTAssertEqual(info.ncxHref, "toc.ncx")
        XCTAssertEqual(info.coverHref, "text/cover.xhtml")
    }

    func testNavParserExtractsOriginalTitlesAndLevels() throws {
        let root = try makeTempDirectory()
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        let navURL = oebps.appendingPathComponent("nav.xhtml")
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
          <body>
            <nav epub:type="toc">
              <ol>
                <li><a href="text/cover.xhtml">封面</a></li>
                <li>
                  <a href="text/chapter1.xhtml#part-1">第一章 起点</a>
                  <ol>
                    <li><a href="text/chapter1.xhtml#part-2">第一章 第二节</a></li>
                  </ol>
                </li>
              </ol>
            </nav>
          </body>
        </html>
        """
        guard let navData = nav.data(using: .utf8) else {
            XCTFail("Cannot encode nav.xhtml")
            return
        }
        try navData.write(to: navURL)

        let resolver = EPUBNavigationResolver(extractedRootURL: root)
        let items = try EPUBNavTOCParser().parse(navURL: navURL, resolver: resolver)

        XCTAssertEqual(items.map(\.title), ["封面", "第一章 起点", "第一章 第二节"])
        XCTAssertEqual(items.map(\.level), [0, 0, 1])
        XCTAssertEqual(items.map(\.resourcePath), [
            "OEBPS/text/cover.xhtml",
            "OEBPS/text/chapter1.xhtml#part-1",
            "OEBPS/text/chapter1.xhtml#part-2",
        ])
    }

    func testNCXParserExtractsOriginalTitlesAndLevels() throws {
        let root = try makeTempDirectory()
        let oebps = root.appendingPathComponent("OEBPS", isDirectory: true)
        try FileManager.default.createDirectory(at: oebps, withIntermediateDirectories: true)
        let ncxURL = oebps.appendingPathComponent("toc.ncx")
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
          <navMap>
            <navPoint id="navpoint-1" playOrder="1">
              <navLabel><text>封面</text></navLabel>
              <content src="text/cover.xhtml"/>
            </navPoint>
            <navPoint id="navpoint-2" playOrder="2">
              <navLabel><text>第二章</text></navLabel>
              <content src="text/chapter2.xhtml"/>
              <navPoint id="navpoint-2-1" playOrder="3">
                <navLabel><text>第二章 第一节</text></navLabel>
                <content src="text/chapter2.xhtml#section-1"/>
              </navPoint>
            </navPoint>
          </navMap>
        </ncx>
        """
        guard let ncxData = ncx.data(using: .utf8) else {
            XCTFail("Cannot encode toc.ncx")
            return
        }
        try ncxData.write(to: ncxURL)

        let resolver = EPUBNavigationResolver(extractedRootURL: root)
        let items = try EPUBNCXTOCParser().parse(ncxURL: ncxURL, resolver: resolver)

        XCTAssertEqual(items.map(\.title), ["封面", "第二章", "第二章 第一节"])
        XCTAssertEqual(items.map(\.level), [0, 0, 1])
        XCTAssertEqual(items.map(\.resourcePath), [
            "OEBPS/text/cover.xhtml",
            "OEBPS/text/chapter2.xhtml",
            "OEBPS/text/chapter2.xhtml#section-1",
        ])
    }

    private func writeTempFile(named name: String, content: String) throws -> URL {
        let dir = try makeTempDirectory()
        let fileURL = dir.appendingPathComponent(name)
        guard let data = content.data(using: .utf8) else {
            XCTFail("Cannot encode XML string as UTF-8")
            return fileURL
        }
        try data.write(to: fileURL)
        return fileURL
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
