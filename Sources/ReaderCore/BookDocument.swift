import Foundation

public struct BookDocument: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let title: String
    public let format: BookFormat

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        title: String? = nil,
        format: BookFormat
    ) {
        self.id = id
        self.fileURL = fileURL
        self.title = title ?? fileURL.deletingPathExtension().lastPathComponent
        self.format = format
    }
}
