import Foundation
import ReaderLibrary
import XCTest

final class LibraryModelsTests: XCTestCase {
    func testReadingLocationRoundTripForPDF() throws {
        let location = ReadingLocation.pdf(pageIndex: 27)
        let data = try JSONEncoder().encode(location)
        let decoded = try JSONDecoder().decode(ReadingLocation.self, from: data)
        XCTAssertEqual(decoded, location)
    }

    func testReadingLocationRoundTripForEPUB() throws {
        let location = ReadingLocation.epub(resourcePath: "OEBPS/chapter.xhtml#p10")
        let data = try JSONEncoder().encode(location)
        let decoded = try JSONDecoder().decode(ReadingLocation.self, from: data)
        XCTAssertEqual(decoded, location)
    }
}
