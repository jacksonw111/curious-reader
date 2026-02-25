import Foundation
import ReaderCore

public actor BookLibraryStore {
    private let fileManager: FileManager
    private let storageFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        storageFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let storageFileURL {
            self.storageFileURL = storageFileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
            self.storageFileURL = appSupport
                .appendingPathComponent("CuriousReader", isDirectory: true)
                .appendingPathComponent("library-state.json")
        }

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func load() throws -> [LibraryBookRecord] {
        guard fileManager.fileExists(atPath: storageFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: storageFileURL)
        let payload = try decoder.decode(PersistedLibraryPayload.self, from: data)
        return payload.books.compactMap { mapPersistedEntry($0) }
    }

    public func save(records: [LibraryBookRecord]) throws {
        let parent = storageFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let books = records.map { record in
            PersistedLibraryBook(
                id: record.document.id,
                title: record.document.title,
                format: record.document.format.rawValue,
                filePath: record.document.fileURL.path,
                securityScopedBookmarkData: record.securityScopedBookmarkData,
                readingState: record.readingState
            )
        }
        let payload = PersistedLibraryPayload(books: books)
        let data = try encoder.encode(payload)
        try data.write(to: storageFileURL, options: .atomic)
    }

    private func mapPersistedEntry(_ entry: PersistedLibraryBook) -> LibraryBookRecord? {
        guard let format = BookFormat(rawValue: entry.format) else {
            return nil
        }

        let resolvedURL = resolveURL(filePath: entry.filePath, bookmarkData: entry.securityScopedBookmarkData)
        guard let fileURL = resolvedURL else {
            return nil
        }

        return LibraryBookRecord(
            document: BookDocument(
                id: entry.id,
                fileURL: fileURL,
                title: entry.title,
                format: format
            ),
            securityScopedBookmarkData: entry.securityScopedBookmarkData,
            readingState: entry.readingState
        )
    }

    private func resolveURL(filePath: String, bookmarkData: Data?) -> URL? {
        if let bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if fileManager.fileExists(atPath: resolved.path) {
                    return resolved
                }
            }
        }

        let fallback = URL(fileURLWithPath: filePath)
        return fileManager.fileExists(atPath: fallback.path) ? fallback : nil
    }
}

private struct PersistedLibraryPayload: Codable {
    var books: [PersistedLibraryBook]
}

private struct PersistedLibraryBook: Codable {
    var id: UUID
    var title: String
    var format: String
    var filePath: String
    var securityScopedBookmarkData: Data?
    var readingState: BookReadingState
}
