import Foundation
import ReaderCore
import XCTest

final class ReaderErrorTests: XCTestCase {
    func testLocalizedDescriptionsContainFileName() {
        let url = URL(fileURLWithPath: "/tmp/WarAndPeace.epub")

        XCTAssertEqual(ReaderError.formatUnsupported(url).errorDescription, "Unsupported format: WarAndPeace.epub")
        XCTAssertEqual(ReaderError.parseFailed(url).errorDescription, "Cannot parse file: WarAndPeace.epub")
        XCTAssertEqual(ReaderError.permissionDenied(url).errorDescription, "Permission denied: WarAndPeace.epub")
        XCTAssertEqual(ReaderError.corruptedFile(url).errorDescription, "File is corrupted: WarAndPeace.epub")
        XCTAssertEqual(ReaderError.conversionUnavailable(url).errorDescription, "MOBI conversion is not configured: WarAndPeace.epub")
    }
}
