import Foundation

public struct FormatDetector {
    public init() {}

    public func detect(url: URL) throws -> BookFormat {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ext == "epub" { return .epub }
        if ["mobi", "prc", "azw", "azw3", "kf8"].contains(ext) { return .mobi }

        let header = try readHeader(url: url, length: 128)
        if header.starts(with: Data("%PDF-".utf8)) {
            return .pdf
        }
        if hasMOBISignature(header) {
            return .mobi
        }
        return .unknown
    }

    private func readHeader(url: URL, length: Int) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ReaderError.permissionDenied(url)
        }
        defer {
            try? handle.close()
        }

        do {
            guard let data = try handle.read(upToCount: length) else {
                throw ReaderError.corruptedFile(url)
            }
            return data
        } catch let readerError as ReaderError {
            throw readerError
        } catch {
            throw ReaderError.parseFailed(url)
        }
    }

    private func hasMOBISignature(_ data: Data) -> Bool {
        let signatureOffset = 60
        let signature = Data("BOOKMOBI".utf8)
        guard data.count >= signatureOffset + signature.count else {
            return false
        }
        return data[signatureOffset..<(signatureOffset + signature.count)] == signature
    }
}
