import Foundation
import ReaderCore

public enum ReadingLocation: Codable, Equatable, Sendable {
    case pdf(pageIndex: Int)
    case epub(resourcePath: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case pageIndex
        case resourcePath
    }

    private enum Kind: String, Codable {
        case pdf
        case epub
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .pdf:
            self = .pdf(pageIndex: try container.decode(Int.self, forKey: .pageIndex))
        case .epub:
            self = .epub(resourcePath: try container.decode(String.self, forKey: .resourcePath))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pdf(let pageIndex):
            try container.encode(Kind.pdf, forKey: .kind)
            try container.encode(pageIndex, forKey: .pageIndex)
        case .epub(let resourcePath):
            try container.encode(Kind.epub, forKey: .kind)
            try container.encode(resourcePath, forKey: .resourcePath)
        }
    }
}

public struct ReadingBookmark: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var note: String?
    public var location: ReadingLocation

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        note: String? = nil,
        location: ReadingLocation
    ) {
        self.id = id
        self.createdAt = createdAt
        self.note = note
        self.location = location
    }
}

public struct BookReadingState: Codable, Equatable, Sendable {
    public var lastOpenedAt: Date?
    public var lastLocation: ReadingLocation?
    public var bookmarks: [ReadingBookmark]

    public init(
        lastOpenedAt: Date? = nil,
        lastLocation: ReadingLocation? = nil,
        bookmarks: [ReadingBookmark] = []
    ) {
        self.lastOpenedAt = lastOpenedAt
        self.lastLocation = lastLocation
        self.bookmarks = bookmarks
    }
}

public struct LibraryBookRecord: Equatable, Sendable {
    public var document: BookDocument
    public var securityScopedBookmarkData: Data?
    public var readingState: BookReadingState

    public init(
        document: BookDocument,
        securityScopedBookmarkData: Data?,
        readingState: BookReadingState
    ) {
        self.document = document
        self.securityScopedBookmarkData = securityScopedBookmarkData
        self.readingState = readingState
    }
}
