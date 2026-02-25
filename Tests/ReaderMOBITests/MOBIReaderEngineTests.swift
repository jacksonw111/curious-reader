import Foundation
import ReaderCore
import ReaderEPUB
import ReaderMOBI
import XCTest

final class MOBIReaderEngineTests: XCTestCase {
    func testMOBIIsConvertedAndOpenedAsEPUB() throws {
        let converter = StubMOBIConverter(
            outputURL: URL(fileURLWithPath: "/tmp/converted.epub")
        )
        let epubOpener = StubEPUBOpener()
        let engine = MOBIReaderEngine(converter: converter, epubEngine: epubOpener)
        let input = BookDocument(
            fileURL: URL(fileURLWithPath: "/tmp/source.mobi"),
            title: "Sample Book",
            format: .mobi
        )

        _ = try engine.open(document: input)
        XCTAssertEqual(epubOpener.lastOpenedDocument?.title, "Sample Book")
        XCTAssertEqual(epubOpener.lastOpenedDocument?.format, .epub)
        XCTAssertEqual(epubOpener.lastOpenedDocument?.fileURL.path, "/tmp/converted.epub")
    }
}

private struct StubMOBIConverter: MOBIConverting {
    let outputURL: URL

    func convertToEPUB(mobiURL: URL) throws -> URL {
        outputURL
    }
}

private final class StubEPUBOpener: EPUBOpening {
    var lastOpenedDocument: BookDocument?

    func open(document: BookDocument) throws -> any ReadingSession {
        lastOpenedDocument = document
        return StubReadingSession(document: document)
    }
}

private struct StubReadingSession: ReadingSession {
    let document: BookDocument
}
