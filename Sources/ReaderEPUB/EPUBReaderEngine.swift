import Foundation
import os
import ReaderCore
import ZIPFoundation

public struct EPUBTOCItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let resourcePath: String
    public let level: Int

    public init(
        id: UUID = UUID(),
        title: String,
        resourcePath: String,
        level: Int = 0
    ) {
        self.id = id
        self.title = title
        self.resourcePath = resourcePath
        self.level = level
    }
}

public struct EPUBReadingSession: ReadingSession {
    public let document: BookDocument
    public let extractedRootURL: URL
    public let startDocumentURL: URL
    public let tableOfContents: [EPUBTOCItem]
    public let readingOrderResourcePaths: [String]

    public init(
        document: BookDocument,
        extractedRootURL: URL,
        startDocumentURL: URL,
        tableOfContents: [EPUBTOCItem],
        readingOrderResourcePaths: [String] = []
    ) {
        self.document = document
        self.extractedRootURL = extractedRootURL
        self.startDocumentURL = startDocumentURL
        self.tableOfContents = tableOfContents
        self.readingOrderResourcePaths = readingOrderResourcePaths
    }
}

public protocol EPUBLoading {
    func load(document: BookDocument) throws -> EPUBLoadedPublication
}

public struct EPUBLoadedPublication {
    public let extractedRootURL: URL
    public let startDocumentURL: URL
    public let title: String?
    public let tableOfContents: [EPUBTOCItem]
    public let readingOrderResourcePaths: [String]

    public init(
        extractedRootURL: URL,
        startDocumentURL: URL,
        title: String?,
        tableOfContents: [EPUBTOCItem],
        readingOrderResourcePaths: [String] = []
    ) {
        self.extractedRootURL = extractedRootURL
        self.startDocumentURL = startDocumentURL
        self.title = title
        self.tableOfContents = tableOfContents
        self.readingOrderResourcePaths = readingOrderResourcePaths
    }
}

public struct EPUBReaderEngine: ReaderEngine {
    public let supportedFormats: Set<BookFormat> = [.epub]

    private let loader: any EPUBLoading

    public init(loader: any EPUBLoading = EPUBArchiveLoader()) {
        self.loader = loader
    }

    public func open(document: BookDocument) throws -> any ReadingSession {
        guard document.format == .epub else {
            throw ReaderError.formatUnsupported(document.fileURL)
        }

        let publication = try loader.load(document: document)
        let resolvedDocument = BookDocument(
            id: document.id,
            fileURL: document.fileURL,
            title: publication.title ?? document.title,
            format: .epub
        )
        return EPUBReadingSession(
            document: resolvedDocument,
            extractedRootURL: publication.extractedRootURL,
            startDocumentURL: publication.startDocumentURL,
            tableOfContents: publication.tableOfContents,
            readingOrderResourcePaths: publication.readingOrderResourcePaths
        )
    }
}

public struct EPUBArchiveLoader: EPUBLoading {
    private let fileManager: FileManager
    private let extractionRoot: URL
    private let signpostLog = OSLog(subsystem: "com.curious-reader.epub", category: "Pipeline")

    public init(
        fileManager: FileManager = .default,
        extractionRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CuriousReader", isDirectory: true)
            .appendingPathComponent("EPUBCache", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.extractionRoot = extractionRoot
    }

    public func load(document: BookDocument) throws -> EPUBLoadedPublication {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(
            .begin,
            log: signpostLog,
            name: "LoadEPUB",
            signpostID: signpostID,
            "%{public}s",
            document.fileURL.lastPathComponent
        )
        defer {
            os_signpost(.end, log: signpostLog, name: "LoadEPUB", signpostID: signpostID)
        }

        let archive: Archive
        do {
            archive = try Archive(url: document.fileURL, accessMode: .read)
        } catch {
            throw ReaderError.parseFailed(document.fileURL)
        }

        let extractedRootURL = extractionRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: extractedRootURL,
            withIntermediateDirectories: true
        )

        do {
            for entry in archive {
                let destination = sanitize(entryPath: entry.path, under: extractedRootURL)
                switch entry.type {
                case .directory:
                    try fileManager.createDirectory(
                        at: destination,
                        withIntermediateDirectories: true
                    )
                case .file:
                    let parent = destination.deletingLastPathComponent()
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: destination)
                default:
                    continue
                }
            }
        } catch {
            throw ReaderError.parseFailed(document.fileURL)
        }

        let containerURL = extractedRootURL
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        let containerParser = EPUBContainerParser()
        let rootFilePath = try containerParser.parse(containerURL: containerURL)

        let packageURL = extractedRootURL.appendingPathComponent(rootFilePath)
        let packageParser = EPUBPackageParser()
        let packageInfo = try packageParser.parse(packageURL: packageURL)
        let packageRootURL = packageURL.deletingLastPathComponent()
        guard let startDocumentURL = resolveStartDocumentURL(
            packageInfo: packageInfo,
            packageRootURL: packageRootURL,
            extractedRootURL: extractedRootURL
        ) else {
            throw ReaderError.parseFailed(document.fileURL)
        }

        let tocItems = buildTOCItems(
            packageInfo: packageInfo,
            packageRootURL: packageRootURL,
            extractedRootURL: extractedRootURL
        )
        let readingOrderResourcePaths = buildReadingOrderResourcePaths(
            packageInfo: packageInfo,
            packageRootURL: packageRootURL,
            extractedRootURL: extractedRootURL
        )

        return EPUBLoadedPublication(
            extractedRootURL: extractedRootURL,
            startDocumentURL: startDocumentURL,
            title: packageInfo.title,
            tableOfContents: tocItems,
            readingOrderResourcePaths: readingOrderResourcePaths
        )
    }

    private func sanitize(entryPath: String, under rootURL: URL) -> URL {
        let components = entryPath
            .split(separator: "/")
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }
        return components.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
    }

    private func resolveStartDocumentURL(
        packageInfo: EPUBPackageInfo,
        packageRootURL: URL,
        extractedRootURL: URL
    ) -> URL? {
        let resolver = EPUBNavigationResolver(extractedRootURL: extractedRootURL)
        if let coverHref = packageInfo.coverHref,
           let coverURL = resolver.resolveContentURL(href: coverHref, relativeTo: packageRootURL),
           fileManager.fileExists(atPath: coverURL.path) {
            return coverURL
        }
        if let firstSpineURL = resolver.resolveContentURL(
            href: packageInfo.firstSpineHref,
            relativeTo: packageRootURL
        ),
        fileManager.fileExists(atPath: firstSpineURL.path) {
            return firstSpineURL
        }
        return nil
    }

    private func buildTOCItems(
        packageInfo: EPUBPackageInfo,
        packageRootURL: URL,
        extractedRootURL: URL
    ) -> [EPUBTOCItem] {
        let resolver = EPUBNavigationResolver(extractedRootURL: extractedRootURL)
        if let navHref = packageInfo.navHref,
           let navURL = resolver.resolveContentURL(href: navHref, relativeTo: packageRootURL),
           let navItems = try? EPUBNavTOCParser().parse(navURL: navURL, resolver: resolver),
           !navItems.isEmpty {
            return navItems
        }
        if let ncxHref = packageInfo.ncxHref,
           let ncxURL = resolver.resolveContentURL(href: ncxHref, relativeTo: packageRootURL),
           let ncxItems = try? EPUBNCXTOCParser().parse(ncxURL: ncxURL, resolver: resolver),
           !ncxItems.isEmpty {
            return ncxItems
        }

        var seenResourcePath: Set<String> = []
        var items: [EPUBTOCItem] = []

        for (index, href) in packageInfo.spineHrefs.enumerated() {
            guard let resourcePath = resolver.resolveResourcePath(href: href, relativeTo: packageRootURL) else {
                continue
            }
            let dedupeKey = resourcePath.components(separatedBy: "#").first ?? resourcePath
            guard !seenResourcePath.contains(dedupeKey) else {
                continue
            }
            seenResourcePath.insert(dedupeKey)

            items.append(
                EPUBTOCItem(
                    title: humanizeChapterTitle(from: resourcePath, index: index),
                    resourcePath: resourcePath,
                    level: 0
                )
            )
        }
        return items
    }

    private func humanizeChapterTitle(from resourcePath: String, index: Int) -> String {
        let fileName = URL(fileURLWithPath: resourcePath)
            .deletingPathExtension()
            .lastPathComponent
        let cleaned = fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "Chapter \(index + 1)"
        }
        return cleaned
    }

    private func buildReadingOrderResourcePaths(
        packageInfo: EPUBPackageInfo,
        packageRootURL: URL,
        extractedRootURL: URL
    ) -> [String] {
        let resolver = EPUBNavigationResolver(extractedRootURL: extractedRootURL)
        var seenPaths: Set<String> = []
        var paths: [String] = []
        for href in packageInfo.spineHrefs {
            guard let resolvedPath = resolver.resolveResourcePath(href: href, relativeTo: packageRootURL) else {
                continue
            }
            let dedupeKey = resolvedPath.components(separatedBy: "#").first ?? resolvedPath
            guard !seenPaths.contains(dedupeKey) else {
                continue
            }
            seenPaths.insert(dedupeKey)
            paths.append(dedupeKey)
        }
        return paths
    }
}

struct EPUBContainerParser {
    func parse(containerURL: URL) throws -> String {
        guard let data = try? Data(contentsOf: containerURL) else {
            throw ReaderError.parseFailed(containerURL)
        }
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.rootFilePath, !path.isEmpty else {
            throw ReaderError.parseFailed(containerURL)
        }
        return path
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var rootFilePath: String?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName.lowercased() == "rootfile" {
                rootFilePath = attributeDict["full-path"]
            }
        }
    }
}

struct EPUBPackageInfo {
    let title: String?
    let firstSpineHref: String
    let spineHrefs: [String]
    let navHref: String?
    let ncxHref: String?
    let coverHref: String?
}

struct EPUBPackageParser {
    func parse(packageURL: URL) throws -> EPUBPackageInfo {
        guard let data = try? Data(contentsOf: packageURL) else {
            throw ReaderError.parseFailed(packageURL)
        }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ReaderError.parseFailed(packageURL)
        }

        let firstHref = delegate.resolveFirstSpineHref()
        guard !firstHref.isEmpty else {
            throw ReaderError.parseFailed(packageURL)
        }
        return EPUBPackageInfo(
            title: delegate.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            firstSpineHref: firstHref,
            spineHrefs: delegate.resolveSpineHrefs(),
            navHref: delegate.resolveNavHref(),
            ncxHref: delegate.resolveNCXHref(),
            coverHref: delegate.resolveCoverHref()
        )
    }

    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String?
        let properties: Set<String>
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var title: String?
        private var isInsideMetadata = false
        private var captureTitle = false
        private var titleBuffer = ""
        private var manifest: [String: ManifestItem] = [:]
        private var spineIDRefs: [String] = []
        private var firstManifestHref: String?
        private var spineTOCIDRef: String?
        private var coverManifestID: String?
        private var guideCoverHref: String?

        func resolveFirstSpineHref() -> String {
            if let first = resolveSpineHrefs().first {
                return first
            }
            if let href = firstManifestHref {
                return href
            }
            return ""
        }

        func resolveSpineHrefs() -> [String] {
            let fromSpine = spineIDRefs.compactMap { manifest[$0]?.href }
            if !fromSpine.isEmpty {
                return fromSpine
            }
            if let href = firstManifestHref {
                return [href]
            }
            return []
        }

        func resolveNavHref() -> String? {
            manifest.values.first(where: { $0.properties.contains("nav") })?.href
        }

        func resolveNCXHref() -> String? {
            if let tocID = spineTOCIDRef, let href = manifest[tocID]?.href {
                return href
            }
            return manifest.values.first(where: {
                $0.mediaType?.lowercased() == "application/x-dtbncx+xml"
            })?.href
        }

        func resolveCoverHref() -> String? {
            if let guideCoverHref {
                return guideCoverHref
            }
            if let coverManifestID, let href = manifest[coverManifestID]?.href {
                return href
            }
            if let coverPage = manifest.values.first(where: { item in
                let hint = item.id.lowercased().contains("cover") || item.href.lowercased().contains("cover")
                let isReadablePage = item.mediaType?.lowercased().contains("html") ?? false
                return hint && isReadablePage
            }) {
                return coverPage.href
            }
            if let coverImage = manifest.values.first(where: { $0.properties.contains("cover-image") }) {
                return coverImage.href
            }
            return nil
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let normalized = normalizedName(elementName)
            if normalized == "metadata" {
                isInsideMetadata = true
                return
            }
            if normalized == "item" {
                if let id = attributeDict["id"], let href = attributeDict["href"] {
                    let mediaType = attributeDict["media-type"]
                    let properties = Set(
                        (attributeDict["properties"] ?? "")
                            .lowercased()
                            .split(whereSeparator: \.isWhitespace)
                            .map(String.init)
                    )
                    manifest[id] = ManifestItem(
                        id: id,
                        href: href,
                        mediaType: mediaType,
                        properties: properties
                    )
                    if firstManifestHref == nil {
                        firstManifestHref = href
                    }
                }
                return
            }
            if normalized == "itemref", let idref = attributeDict["idref"] {
                spineIDRefs.append(idref)
                return
            }
            if normalized == "spine" {
                spineTOCIDRef = attributeDict["toc"]
                return
            }
            if normalized == "reference",
               let href = attributeDict["href"],
               let type = attributeDict["type"]?.lowercased(),
               type.contains("cover") {
                guideCoverHref = href
                return
            }
            if normalized == "meta" {
                let name = attributeDict["name"]?.lowercased()
                if name == "cover", let content = attributeDict["content"], !content.isEmpty {
                    coverManifestID = content
                }
                return
            }
            if isInsideMetadata && normalized == "title" {
                captureTitle = true
                titleBuffer = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if captureTitle {
                titleBuffer += string
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let normalized = normalizedName(elementName)
            if normalized == "metadata" {
                isInsideMetadata = false
                return
            }
            if normalized == "title" && captureTitle {
                title = titleBuffer
                captureTitle = false
            }
        }

        private func normalizedName(_ raw: String) -> String {
            raw.split(separator: ":").last.map(String.init)?.lowercased() ?? raw.lowercased()
        }
    }
}
