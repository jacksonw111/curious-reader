import Foundation
import ReaderCore
import XCTest

final class BookImportServiceTests: XCTestCase {
    private let service = BookImportService()

    func testImportDetectsKnownFormat() throws {
        let url = try writeTempFile(name: "sample.pdf", data: Data("%PDF-1.7".utf8))
        let document = try service.import(url: url)

        XCTAssertEqual(document.fileURL, url)
        XCTAssertEqual(document.format, .pdf)
        XCTAssertEqual(document.title, "sample")
    }

    func testImportThrowsForUnsupportedFormat() throws {
        let url = try writeTempFile(name: "sample.txt", data: Data("plain text".utf8))

        XCTAssertThrowsError(try service.import(url: url)) { error in
            XCTAssertEqual(error as? ReaderError, .formatUnsupported(url))
        }
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
