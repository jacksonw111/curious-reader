import Foundation
import ReaderCore
import ReaderLibrary
import XCTest

final class BookLibraryStoreRegressionTests: XCTestCase {
    func testLoadSkipsInvalidOrMissingEntries() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let validFile = root.appendingPathComponent("valid.pdf")
        try Data("%PDF-1.7".utf8).write(to: validFile)
        let missingFile = root.appendingPathComponent("missing.pdf")

        let stateURL = root.appendingPathComponent("library-state.json")
        let validID = UUID()
        let invalidFormatID = UUID()
        let missingFileID = UUID()

        let payload = """
        {
          "books": [
            {
              "id": "\(validID.uuidString)",
              "title": "Valid",
              "format": "pdf",
              "filePath": "\(validFile.path)",
              "securityScopedBookmarkData": null,
              "readingState": {
                "lastOpenedAt": null,
                "lastLocation": { "kind": "pdf", "pageIndex": 3 },
                "bookmarks": []
              }
            },
            {
              "id": "\(invalidFormatID.uuidString)",
              "title": "Invalid Format",
              "format": "docx",
              "filePath": "\(validFile.path)",
              "securityScopedBookmarkData": null,
              "readingState": { "lastOpenedAt": null, "lastLocation": null, "bookmarks": [] }
            },
            {
              "id": "\(missingFileID.uuidString)",
              "title": "Missing File",
              "format": "pdf",
              "filePath": "\(missingFile.path)",
              "securityScopedBookmarkData": null,
              "readingState": { "lastOpenedAt": null, "lastLocation": null, "bookmarks": [] }
            }
          ]
        }
        """
        try Data(payload.utf8).write(to: stateURL)

        let store = BookLibraryStore(storageFileURL: stateURL)
        let loaded = try await store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].document.id, validID)
        XCTAssertEqual(loaded[0].document.fileURL.path, validFile.path)
        XCTAssertEqual(loaded[0].readingState.lastLocation, .pdf(pageIndex: 3))
    }
}
