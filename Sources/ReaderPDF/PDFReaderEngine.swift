import Foundation
import PDFKit
import ReaderCore

public struct PDFTOCItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let pageIndex: Int
    public let level: Int

    public init(
        id: UUID = UUID(),
        title: String,
        pageIndex: Int,
        level: Int
    ) {
        self.id = id
        self.title = title
        self.pageIndex = pageIndex
        self.level = level
    }
}

public struct PDFReadingSession: ReadingSession {
    public let document: BookDocument
    public let pdfDocument: PDFDocument
    public let tableOfContents: [PDFTOCItem]

    public init(
        document: BookDocument,
        pdfDocument: PDFDocument,
        tableOfContents: [PDFTOCItem]
    ) {
        self.document = document
        self.pdfDocument = pdfDocument
        self.tableOfContents = tableOfContents
    }
}

public struct PDFReaderEngine: ReaderEngine {
    public let supportedFormats: Set<BookFormat> = [.pdf]

    public init() {}

    public func open(document: BookDocument) throws -> any ReadingSession {
        guard document.format == .pdf else {
            throw ReaderError.formatUnsupported(document.fileURL)
        }
        guard let pdfDocument = PDFDocument(url: document.fileURL) else {
            throw ReaderError.parseFailed(document.fileURL)
        }
        let toc = buildTOCItems(for: pdfDocument)
        return PDFReadingSession(document: document, pdfDocument: pdfDocument, tableOfContents: toc)
    }

    private func buildTOCItems(for document: PDFDocument) -> [PDFTOCItem] {
        guard let root = document.outlineRoot else {
            return []
        }

        var items: [PDFTOCItem] = []
        for idx in 0..<root.numberOfChildren {
            guard let child = root.child(at: idx) else {
                continue
            }
            collectOutline(
                from: child,
                in: document,
                level: 0,
                output: &items
            )
        }
        return items
    }

    private func collectOutline(
        from outline: PDFOutline,
        in document: PDFDocument,
        level: Int,
        output: inout [PDFTOCItem]
    ) {
        if let pageIndex = resolvePageIndex(for: outline, in: document) {
            output.append(
                PDFTOCItem(
                    title: outline.label?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Section",
                    pageIndex: pageIndex,
                    level: level
                )
            )
        }

        for idx in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: idx) else {
                continue
            }
            collectOutline(from: child, in: document, level: level + 1, output: &output)
        }
    }

    private func resolvePageIndex(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        if let page = outline.destination?.page {
            let index = document.index(for: page)
            return index >= 0 ? index : nil
        }

        if let action = outline.action as? PDFActionGoTo,
           let page = action.destination.page {
            let index = document.index(for: page)
            return index >= 0 ? index : nil
        }

        return nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
