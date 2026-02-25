import Foundation

public protocol ReadingSession {
    var document: BookDocument { get }
}

public protocol ReaderEngine {
    var supportedFormats: Set<BookFormat> { get }
    func open(document: BookDocument) throws -> any ReadingSession
}
