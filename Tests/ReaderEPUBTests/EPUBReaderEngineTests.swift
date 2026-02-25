import Foundation
@testable import ReaderEPUB
import ReaderCore
import XCTest
import ZIPFoundation

final class EPUBReaderEngineTests: XCTestCase {
    func testEngineUsesLoaderAndResolvesTitle() throws {
        let root = try makeTempDirectory()
        let startURL = root.appendingPathComponent("start.xhtml")
        try Data("<html></html>".utf8).write(to: startURL)

        let loader = StubEPUBLoader(
            publication: EPUBLoadedPublication(
                extractedRootURL: root,
                startDocumentURL: startURL,
                title: "Loaded Title",
                tableOfContents: [EPUBTOCItem(title: "Intro", resourcePath: "start.xhtml")],
                readingOrderResourcePaths: ["start.xhtml", "chapter-2.xhtml"]
            )
        )
        let engine = EPUBReaderEngine(loader: loader)
        let input = BookDocument(
            fileURL: root.appendingPathComponent("book.epub"),
            title: "Input Title",
            format: .epub
        )

        let session = try engine.open(document: input)
        guard let epubSession = session as? EPUBReadingSession else {
            XCTFail("Expected EPUBReadingSession")
            return
        }
        XCTAssertEqual(epubSession.document.title, "Loaded Title")
        XCTAssertEqual(epubSession.tableOfContents.map(\.title), ["Intro"])
        XCTAssertEqual(epubSession.readingOrderResourcePaths, ["start.xhtml", "chapter-2.xhtml"])
    }

    func testEngineRejectsUnsupportedFormat() {
        let engine = EPUBReaderEngine(loader: StubEPUBLoader())
        let input = BookDocument(
            fileURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
            title: "PDF",
            format: .pdf
        )

        XCTAssertThrowsError(try engine.open(document: input)) { error in
            XCTAssertEqual(error as? ReaderError, .formatUnsupported(input.fileURL))
        }
    }

    func testArchiveLoaderPrefersCoverAndParsesNavTOC() throws {
        let root = try makeTempDirectory()
        let epubURL = root.appendingPathComponent("sample.epub")
        try createEPUB(at: epubURL, entries: [
            "META-INF/container.xml": """
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" /></rootfiles>
            </container>
            """,
            "OEBPS/content.opf": """
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Archive EPUB</dc:title>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover" href="text/cover.xhtml" media-type="application/xhtml+xml"/>
                <item id="ch1" href="text/chapter-1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="ch1"/>
              </spine>
              <guide>
                <reference type="cover" href="text/cover.xhtml"/>
              </guide>
            </package>
            """,
            "OEBPS/nav.xhtml": """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
              <body>
                <nav epub:type="toc">
                  <ol>
                    <li><a href="text/cover.xhtml">封面</a></li>
                    <li><a href="text/chapter-1.xhtml">第一章</a></li>
                  </ol>
                </nav>
              </body>
            </html>
            """,
            "OEBPS/text/cover.xhtml": "<html><body>Cover</body></html>",
            "OEBPS/text/chapter-1.xhtml": "<html><body>Chapter 1</body></html>",
        ])

        let document = BookDocument(fileURL: epubURL, title: "Input", format: .epub)
        let extraction = root.appendingPathComponent("extract", isDirectory: true)
        let loader = EPUBArchiveLoader(extractionRoot: extraction)
        let publication = try loader.load(document: document)

        XCTAssertEqual(publication.title, "Archive EPUB")
        XCTAssertEqual(publication.startDocumentURL.lastPathComponent, "cover.xhtml")
        XCTAssertEqual(publication.tableOfContents.map(\.title), ["封面", "第一章"])
        XCTAssertEqual(publication.readingOrderResourcePaths, ["OEBPS/text/chapter-1.xhtml"])
    }

    func testArchiveLoaderFallsBackToSpineWhenNoNavOrNCX() throws {
        let root = try makeTempDirectory()
        let epubURL = root.appendingPathComponent("fallback.epub")
        try createEPUB(at: epubURL, entries: [
            "META-INF/container.xml": """
            <?xml version="1.0"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OPS/content.opf" /></rootfiles>
            </container>
            """,
            "OPS/content.opf": """
            <?xml version="1.0" encoding="UTF-8"?>
            <package version="3.0" xmlns="http://www.idpf.org/2007/opf">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Fallback</dc:title>
              </metadata>
              <manifest>
                <item id="chap1" href="text/chapter-1.xhtml" media-type="application/xhtml+xml"/>
                <item id="chap2" href="text/chapter_2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="chap1"/>
                <itemref idref="chap2"/>
              </spine>
            </package>
            """,
            "OPS/text/chapter-1.xhtml": "<html><body>One</body></html>",
            "OPS/text/chapter_2.xhtml": "<html><body>Two</body></html>",
        ])

        let document = BookDocument(fileURL: epubURL, title: "Input", format: .epub)
        let loader = EPUBArchiveLoader(extractionRoot: root.appendingPathComponent("extract", isDirectory: true))
        let publication = try loader.load(document: document)

        XCTAssertEqual(publication.startDocumentURL.lastPathComponent, "chapter-1.xhtml")
        XCTAssertEqual(publication.tableOfContents.count, 2)
        XCTAssertEqual(publication.tableOfContents.map(\.resourcePath), [
            "OPS/text/chapter-1.xhtml",
            "OPS/text/chapter_2.xhtml",
        ])
        XCTAssertEqual(publication.readingOrderResourcePaths, [
            "OPS/text/chapter-1.xhtml",
            "OPS/text/chapter_2.xhtml",
        ])
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createEPUB(at url: URL, entries: [String: String]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, content) in entries {
            let data = Data(content.utf8)
            let size = Int64(data.count)
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: size,
                compressionMethod: .deflate,
                provider: { position, requestedSize in
                    let start = Int(position)
                    let end = min(start + requestedSize, data.count)
                    return data.subdata(in: start..<end)
                }
            )
        }
    }
}

private struct StubEPUBLoader: EPUBLoading {
    var publication: EPUBLoadedPublication?

    func load(document: BookDocument) throws -> EPUBLoadedPublication {
        if let publication {
            return publication
        }
        throw ReaderError.parseFailed(document.fileURL)
    }
}
