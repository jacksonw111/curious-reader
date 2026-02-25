import Foundation
import ReaderCore
import ReaderLibrary
import XCTest

final class BookLibraryStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("sample.pdf")
        try Data("%PDF-1.7".utf8).write(to: fileURL)

        let storageURL = root.appendingPathComponent("state.json")
        let store = BookLibraryStore(storageFileURL: storageURL)

        let state = BookReadingState(
            lastOpenedAt: Date(),
            lastLocation: .pdf(pageIndex: 12),
            bookmarks: [ReadingBookmark(location: .pdf(pageIndex: 5))]
        )
        let record = LibraryBookRecord(
            document: BookDocument(
                id: UUID(uuidString: "0E70E742-7C27-4B5C-B585-E21462DCE93B")!,
                fileURL: fileURL,
                title: "Sample",
                format: .pdf
            ),
            securityScopedBookmarkData: nil,
            readingState: state
        )

        try await store.save(records: [record])
        let loaded = try await store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].document.id, record.document.id)
        XCTAssertEqual(loaded[0].document.title, "Sample")
        XCTAssertEqual(loaded[0].readingState.lastLocation, .pdf(pageIndex: 12))
        XCTAssertEqual(loaded[0].readingState.bookmarks.count, 1)
    }
}
