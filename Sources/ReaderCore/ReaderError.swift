import Foundation

public enum ReaderError: LocalizedError, Equatable {
    case formatUnsupported(URL)
    case parseFailed(URL)
    case permissionDenied(URL)
    case corruptedFile(URL)
    case conversionUnavailable(URL)

    public var errorDescription: String? {
        switch self {
        case .formatUnsupported(let url):
            return "Unsupported format: \(url.lastPathComponent)"
        case .parseFailed(let url):
            return "Cannot parse file: \(url.lastPathComponent)"
        case .permissionDenied(let url):
            return "Permission denied: \(url.lastPathComponent)"
        case .corruptedFile(let url):
            return "File is corrupted: \(url.lastPathComponent)"
        case .conversionUnavailable(let url):
            return "MOBI conversion is not configured: \(url.lastPathComponent)"
        }
    }
}
