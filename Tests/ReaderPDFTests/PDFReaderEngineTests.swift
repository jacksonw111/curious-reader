import AppKit
import Foundation
import PDFKit
import ReaderCore
import ReaderPDF
import XCTest

final class PDFReaderEngineTests: XCTestCase {
    private let engine = PDFReaderEngine()

    func testOpenThrowsUnsupportedFormat() {
        let document = BookDocument(
            fileURL: URL(fileURLWithPath: "/tmp/demo.epub"),
            title: "Demo",
            format: .epub
        )

        XCTAssertThrowsError(try engine.open(document: document)) { error in
            XCTAssertEqual(error as? ReaderError, .formatUnsupported(document.fileURL))
        }
    }

    func testOpenThrowsForCorruptedPDF() throws {
        let fileURL = try writeTempFile(name: "broken.pdf", data: Data("not a real pdf".utf8))
        let document = BookDocument(fileURL: fileURL, title: "Broken", format: .pdf)

        XCTAssertThrowsError(try engine.open(document: document)) { error in
            XCTAssertEqual(error as? ReaderError, .parseFailed(fileURL))
        }
    }

    func testOpenValidPDFSession() throws {
        let fileURL = try writeSimplePDF()
        let document = BookDocument(fileURL: fileURL, title: "Sample", format: .pdf)

        let session = try engine.open(document: document)
        guard let pdfSession = session as? PDFReadingSession else {
            XCTFail("Expected PDFReadingSession")
            return
        }
        XCTAssertEqual(pdfSession.document.title, "Sample")
        XCTAssertEqual(pdfSession.pdfDocument.pageCount, 1)
    }

    private func writeTempFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }

    private func writeSimplePDF() throws -> URL {
        let image = NSImage(size: NSSize(width: 420, height: 595))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 420, height: 595)).fill()
        let text = "Curious Reader PDF Test"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        text.draw(at: NSPoint(x: 24, y: 300), withAttributes: attributes)
        image.unlockFocus()

        guard let page = PDFPage(image: image) else {
            throw NSError(domain: "PDFReaderEngineTests", code: 1)
        }
        let pdf = PDFDocument()
        pdf.insert(page, at: 0)

        let url = try writeTempFile(name: "sample.pdf", data: Data())
        guard pdf.write(to: url) else {
            throw NSError(domain: "PDFReaderEngineTests", code: 2)
        }
        return url
    }
}
