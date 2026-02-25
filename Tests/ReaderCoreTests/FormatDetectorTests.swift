import Foundation
import ReaderCore
import XCTest

final class FormatDetectorTests: XCTestCase {
    private var detector: FormatDetector!

    override func setUp() {
        detector = FormatDetector()
    }

    func testDetectsPDFByHeader() throws {
        let url = try writeTempFile(
            name: "sample.bin",
            data: Data("%PDF-1.7".utf8)
        )
        let format = try detector.detect(url: url)
        XCTAssertEqual(format, .pdf)
    }

    func testDetectsEPUBByExtension() throws {
        let url = try writeTempFile(name: "book.epub", data: Data("anything".utf8))
        let format = try detector.detect(url: url)
        XCTAssertEqual(format, .epub)
    }

    func testDetectsMOBIByExtension() throws {
        let url = try writeTempFile(name: "book.mobi", data: Data("anything".utf8))
        let format = try detector.detect(url: url)
        XCTAssertEqual(format, .mobi)
    }

    func testDetectsMOBIBySignature() throws {
        var payload = Data(repeating: 0, count: 128)
        payload.replaceSubrange(60..<68, with: Data("BOOKMOBI".utf8))
        let url = try writeTempFile(name: "book.bin", data: payload)
        let format = try detector.detect(url: url)
        XCTAssertEqual(format, .mobi)
    }

    func testDetectsUnknown() throws {
        let url = try writeTempFile(name: "book.txt", data: Data("text".utf8))
        let format = try detector.detect(url: url)
        XCTAssertEqual(format, .unknown)
    }

    private func writeTempFile(name: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }
}
