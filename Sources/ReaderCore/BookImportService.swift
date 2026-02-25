import Foundation

public struct BookImportService {
    private let detector: FormatDetector

    public init(detector: FormatDetector = .init()) {
        self.detector = detector
    }

    public func `import`(url: URL) throws -> BookDocument {
        let format = try detector.detect(url: url)
        guard format != .unknown else {
            throw ReaderError.formatUnsupported(url)
        }
        return BookDocument(fileURL: url, format: format)
    }
}
