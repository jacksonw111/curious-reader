import Foundation
import os
import PDFKit
import ReaderCore
import ReaderEPUB
import ReaderLibrary
import ReaderMOBI
import ReaderPDF
import SwiftUI

struct DocumentSearchResult: Identifiable, Equatable, Sendable {
    enum Location: Equatable, Sendable {
        case pdf(pageIndex: Int)
        case epub(resourcePath: String, query: String, occurrence: Int)
    }

    let id: UUID
    let location: Location
    let snippet: String

    init(id: UUID = UUID(), location: Location, snippet: String) {
        self.id = id
        self.location = location
        self.snippet = snippet
    }
}

struct EPUBFindRequest: Equatable, Sendable {
    let id: UUID
    let query: String
    let occurrence: Int

    init(id: UUID = UUID(), query: String, occurrence: Int) {
        self.id = id
        self.query = query
        self.occurrence = occurrence
    }
}

struct ReaderTOCItem: Identifiable, Equatable, Sendable {
    enum Location: Equatable, Sendable {
        case pdf(pageIndex: Int)
        case epub(resourcePath: String)
    }

    let id: UUID
    let title: String
    let level: Int
    let location: Location

    init(
        id: UUID = UUID(),
        title: String,
        level: Int,
        location: Location
    ) {
        self.id = id
        self.title = title
        self.level = level
        self.location = location
    }
}

struct ImportedBookSource: Sendable {
    let fileURL: URL
    let securityScopedBookmarkData: Data?
}

enum ActiveSession {
    case pdf(PDFReadingSession)
    case epub(EPUBReadingSession)
    case placeholder(title: String, message: String)

    var document: BookDocument {
        switch self {
        case .pdf(let session):
            return session.document
        case .epub(let session):
            return session.document
        case .placeholder(let title, _):
            return BookDocument(
                fileURL: URL(fileURLWithPath: "/dev/null"),
                title: title,
                format: .unknown
            )
        }
    }

    static func from(session: any ReadingSession) -> ActiveSession {
        if let pdfSession = session as? PDFReadingSession {
            return .pdf(pdfSession)
        }
        if let epubSession = session as? EPUBReadingSession {
            return .epub(epubSession)
        }
        return .placeholder(
            title: session.document.title,
            message: "Unsupported session type: \(type(of: session))"
        )
    }
}

@MainActor
final class ReaderWorkspaceModel: ObservableObject {
    @Published private(set) var books: [BookDocument] = []
    @Published var activeSession: ActiveSession?
    @Published var lastError: String?
    @Published var pdfNavigationTargetPageIndex: Int?
    @Published var pdfNavigationCommandID: UUID?
    @Published var epubNavigationTargetURL: URL?
    @Published var epubNavigationCommandID: UUID?
    @Published var epubFindRequest: EPUBFindRequest?
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [DocumentSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var tableOfContents: [ReaderTOCItem] = []
    @Published private(set) var activeTOCItemID: UUID?
    @Published private(set) var preferences = ReaderPreferences.default
    @Published private(set) var hasOpenRouterAPIKey = false
    @Published private(set) var translationPanel: TranslationPanelState?
    @Published private(set) var activeTranslationHints: [String: String] = [:]
    @Published private(set) var activeTranslationHintsRevision: Int = 0
    @Published private(set) var activeEPUBReadingOrder: [URL] = []
    @Published private(set) var activeEPUBReadingOrderRevision: Int = 0
    @Published private(set) var pendingSelectionText: String?
    @Published private(set) var isOpeningBook = false
    @Published private(set) var openingBookTitle: String?

    private let importService = BookImportService()
    private let pdfEngine = PDFReaderEngine()
    private let epubEngine = EPUBReaderEngine()
    private let mobiEngine = MOBIReaderEngine()
    private let libraryStore = BookLibraryStore()
    private let preferencesStore = ReaderPreferencesStore()
    private let translationMemoryStore = TranslationMemoryStore()
    private let openRouterClient = OpenRouterClient()
    private let signpostLog = OSLog(subsystem: "com.curious-reader.app", category: "ReaderFlow")

    private var sessionCache: [URL: ActiveSession] = [:]
    private var readingStatesByBookID: [UUID: BookReadingState] = [:]
    private var bookmarkDataByBookID: [UUID: Data] = [:]
    private var translationMemoryByBookID: [UUID: [String: String]] = [:]
    private var securityScopedAccessedPaths: Set<String> = []
    private var activeBookID: UUID?
    private var searchTask: Task<Void, Never>?
    private var translationTask: Task<Void, Never>?

    init() {
        Task {
            await bootstrap()
        }
    }

    private func bootstrap() async {
        await loadPreferences()
        await loadTranslationMemory()
        await restoreLibrary()
    }

    private func loadPreferences() async {
        do {
            preferences = try await preferencesStore.load()
        } catch {
            preferences = .default
            lastError = "Failed to load preferences: \(error.localizedDescription)"
        }
        hasOpenRouterAPIKey = OpenRouterKeychainStore.load() != nil
    }

    private func loadTranslationMemory() async {
        do {
            translationMemoryByBookID = try await translationMemoryStore.load()
        } catch {
            translationMemoryByBookID = [:]
            lastError = "Failed to load translation memory: \(error.localizedDescription)"
        }
    }

    func updateEPUBFontStyle(_ fontStyle: ReaderFontStyle) {
        guard preferences.epubFontStyle != fontStyle else {
            return
        }
        preferences.epubFontStyle = fontStyle
        persistPreferencesAsync()
    }

    func updateEPUBFontSize(_ fontSize: Double) {
        let clamped = max(14, min(fontSize, 30))
        guard abs(preferences.epubFontSize - clamped) > 0.01 else {
            return
        }
        preferences.epubFontSize = clamped
        persistPreferencesAsync()
    }

    func saveOpenRouterAPIKey(_ apiKey: String) {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }
        if OpenRouterKeychainStore.save(normalized) {
            hasOpenRouterAPIKey = true
        } else {
            lastError = "Failed to store API key in Keychain."
        }
    }

    func removeOpenRouterAPIKey() {
        OpenRouterKeychainStore.delete()
        hasOpenRouterAPIKey = false
    }

    func importBooks(from sources: [ImportedBookSource], openFirstImportedBook: Bool = false) {
        guard !sources.isEmpty else {
            return
        }

        var firstImported: BookDocument?
        for source in sources {
            let signpostID = OSSignpostID(log: signpostLog)
            os_signpost(.begin, log: signpostLog, name: "ImportBook", signpostID: signpostID, "%{public}s", source.fileURL.lastPathComponent)
            defer {
                os_signpost(.end, log: signpostLog, name: "ImportBook", signpostID: signpostID)
            }

            do {
                let importedDocument = try importService.import(url: source.fileURL)
                let document = mergeOrInsertImportedDocument(importedDocument)
                if firstImported == nil {
                    firstImported = document
                }
                if let bookmark = source.securityScopedBookmarkData {
                    bookmarkDataByBookID[document.id] = bookmark
                }
            } catch {
                lastError = error.localizedDescription
            }
        }

        persistLibraryAsync()

        if openFirstImportedBook, let firstImported {
            do {
                try open(document: firstImported)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func openWithLoading(document: BookDocument) {
        guard !isOpeningBook else {
            return
        }
        openingBookTitle = document.title
        withAnimation(.easeInOut(duration: 0.18)) {
            isOpeningBook = true
        }
        Task { @MainActor in
            defer {
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.isOpeningBook = false
                }
                self.openingBookTitle = nil
            }
            do {
                try await Task.sleep(for: .milliseconds(140))
                try self.open(document: document)
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func open(document: BookDocument) throws {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(
            .begin,
            log: signpostLog,
            name: "OpenDocument",
            signpostID: signpostID,
            "format=%{public}s",
            document.format.rawValue
        )
        defer {
            os_signpost(.end, log: signpostLog, name: "OpenDocument", signpostID: signpostID)
        }

        let openingDocument = resolveDocumentForOpen(document)
        ensureSecurityScopeAccess(for: openingDocument.fileURL)
        activeBookID = openingDocument.id

        let active = try openSessionWithCache(document: openingDocument)
        activeSession = active
        tableOfContents = makeTableOfContents(from: active)
        searchTask?.cancel()
        searchResults = []
        searchQuery = ""
        epubFindRequest = nil
        pdfNavigationCommandID = nil
        epubNavigationCommandID = nil
        translationTask?.cancel()
        translationPanel = nil
        setActiveTranslationHints(translationMemoryByBookID[openingDocument.id] ?? [:])
        updateActiveEPUBReadingOrder(for: active)
        pendingSelectionText = nil

        var state = readingStatesByBookID[openingDocument.id] ?? BookReadingState()
        state.lastOpenedAt = Date()
        readingStatesByBookID[openingDocument.id] = state

        applyLastLocation(state.lastLocation, for: active)
        if state.lastLocation == nil {
            activeTOCItemID = findMatchingTOCItemID(for: defaultLocationForActiveSession())
        }
        persistLibraryAsync()
    }

    func closeReaderSession() {
        searchTask?.cancel()
        activeSession = nil
        activeBookID = nil
        tableOfContents = []
        searchQuery = ""
        searchResults = []
        isSearching = false
        pdfNavigationTargetPageIndex = nil
        epubNavigationTargetURL = nil
        pdfNavigationCommandID = nil
        epubNavigationCommandID = nil
        epubFindRequest = nil
        activeTOCItemID = nil
        translationTask?.cancel()
        translationPanel = nil
        setActiveTranslationHints([:])
        setActiveEPUBReadingOrder([])
        pendingSelectionText = nil
    }

    func openTOCItem(_ item: ReaderTOCItem) {
        guard let bookID = activeBookID else {
            return
        }
        switch item.location {
        case .pdf(let pageIndex):
            issuePDFNavigationCommand(pageIndex: pageIndex)
            epubFindRequest = nil
            activeTOCItemID = item.id
            updateLocation(for: bookID, location: .pdf(pageIndex: pageIndex))
        case .epub(let resourcePath):
            guard case .epub(let session) = activeSession else {
                return
            }
            issueEPUBNavigationCommand(url: resolveEPUBURL(
                rootURL: session.extractedRootURL,
                resourcePath: resourcePath
            ))
            epubFindRequest = nil
            activeTOCItemID = item.id
            updateLocation(for: bookID, location: .epub(resourcePath: resourcePath))
        }
    }

    func updatePDFLocation(pageIndex: Int) {
        guard let bookID = activeBookID else {
            return
        }
        activeTOCItemID = findMatchingTOCItemID(for: .pdf(pageIndex: pageIndex))
        updateLocation(for: bookID, location: .pdf(pageIndex: pageIndex))
    }

    func updateEPUBLocation(url: URL) {
        guard let bookID = activeBookID,
              case .epub(let session) = activeSession else {
            return
        }
        let root = session.extractedRootURL.standardizedFileURL.path
        let current = url.standardizedFileURL.path
        guard current == root || current.hasPrefix(root + "/") else {
            return
        }
        let relative = String(current.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else {
            return
        }
        var location = relative
        if let fragment = url.fragment, !fragment.isEmpty {
            location += "#\(fragment)"
        }
        activeTOCItemID = findMatchingTOCItemID(for: .epub(resourcePath: location))
        updateLocation(for: bookID, location: .epub(resourcePath: location))
    }

    func addBookmarkForActiveBook() {
        guard let bookID = activeBookID else {
            return
        }
        let state = readingStatesByBookID[bookID] ?? BookReadingState()
        let location: ReadingLocation
        if let last = state.lastLocation {
            location = last
        } else {
            location = defaultLocationForActiveSession()
        }

        var updated = state
        let bookmark = ReadingBookmark(location: location)
        updated.bookmarks.insert(bookmark, at: 0)
        readingStatesByBookID[bookID] = updated
        persistLibraryAsync()
    }

    func removeBookmark(_ bookmarkID: UUID) {
        guard let bookID = activeBookID,
              var state = readingStatesByBookID[bookID] else {
            return
        }
        state.bookmarks.removeAll { $0.id == bookmarkID }
        readingStatesByBookID[bookID] = state
        persistLibraryAsync()
    }

    func jumpToBookmark(_ bookmark: ReadingBookmark) {
        applyLastLocation(bookmark.location, for: activeSession)
        guard let bookID = activeBookID else {
            return
        }
        updateLocation(for: bookID, location: bookmark.location)
    }

    func activeBookmarks() -> [ReadingBookmark] {
        guard let bookID = activeBookID else {
            return []
        }
        return readingStatesByBookID[bookID]?.bookmarks ?? []
    }

    func recentlyReadBooks(limit: Int = 5) -> [BookDocument] {
        guard limit > 0 else {
            return []
        }
        let ranked = books.compactMap { book -> (BookDocument, Date)? in
            guard let openedAt = readingStatesByBookID[book.id]?.lastOpenedAt else {
                return nil
            }
            return (book, openedAt)
        }
        .sorted { $0.1 > $1.1 }
        return ranked.prefix(limit).map(\.0)
    }

    func lastOpenedDate(for bookID: UUID) -> Date? {
        readingStatesByBookID[bookID]?.lastOpenedAt
    }

    func hideTranslationPanel() {
        translationTask?.cancel()
        translationPanel = nil
    }

    func dismissTranslationPanelIfIdle() {
        guard let panel = translationPanel else {
            return
        }
        guard !panel.isStreaming else {
            return
        }
        hideTranslationPanel()
    }

    func updatePendingSelectionText(_ rawText: String) {
        let sourceText = normalizedTranslationSourceText(rawText)
        guard !sourceText.isEmpty else {
            pendingSelectionText = nil
            return
        }
        if sourceText != pendingSelectionText,
           translationPanel?.sourceText != sourceText {
            translationTask?.cancel()
            translationPanel = nil
        }
        pendingSelectionText = sourceText
    }

    func clearPendingSelectionText() {
        pendingSelectionText = nil
    }

    func translatePendingSelectionText() {
        guard let pendingSelectionText else {
            return
        }
        translateSelectedText(pendingSelectionText)
    }

    func translateSelectedText(_ rawText: String) {
        guard let bookID = activeBookID else {
            return
        }
        let sourceText = normalizedTranslationSourceText(rawText)
        guard !sourceText.isEmpty else {
            return
        }
        pendingSelectionText = sourceText

        let lookupKey = normalizedTranslationKey(sourceText)
        if let cached = translationMemoryByBookID[bookID]?[lookupKey] {
            translationTask?.cancel()
            translationPanel = TranslationPanelState(
                sourceText: sourceText,
                translatedText: cached,
                isStreaming: false,
                isCached: true,
                errorMessage: nil
            )
            return
        }

        guard let apiKey = OpenRouterKeychainStore.load(), !apiKey.isEmpty else {
            translationPanel = TranslationPanelState(
                sourceText: sourceText,
                translatedText: "",
                isStreaming: false,
                isCached: false,
                errorMessage: TranslationServiceError.missingAPIKey.localizedDescription
            )
            hasOpenRouterAPIKey = false
            return
        }

        hasOpenRouterAPIKey = true
        translationTask?.cancel()
        translationPanel = TranslationPanelState(
            sourceText: sourceText,
            translatedText: "",
            isStreaming: true,
            isCached: false,
            errorMessage: nil
        )
        translationTask = Task {
            var streamedText = ""
            do {
                let finalText = try await openRouterClient.streamTranslation(
                    text: sourceText,
                    apiKey: apiKey
                ) { token in
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        streamedText += token
                        guard var panel = self.translationPanel else {
                            return
                        }
                        panel.translatedText = streamedText
                        panel.isStreaming = true
                        panel.errorMessage = nil
                        self.translationPanel = panel
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let resolved = finalText.isEmpty ? streamedText : finalText
                    if resolved.isEmpty {
                        self.translationPanel = TranslationPanelState(
                            sourceText: sourceText,
                            translatedText: "",
                            isStreaming: false,
                            isCached: false,
                            errorMessage: "Model returned empty output."
                        )
                        return
                    }
                    self.storeTranslation(resolved, for: bookID, key: lookupKey)
                    self.translationPanel = TranslationPanelState(
                        sourceText: sourceText,
                        translatedText: resolved,
                        isStreaming: false,
                        isCached: false,
                        errorMessage: nil
                    )
                    self.pendingSelectionText = sourceText
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.translationPanel = TranslationPanelState(
                        sourceText: sourceText,
                        translatedText: streamedText,
                        isStreaming: false,
                        isCached: false,
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    private func makeTableOfContents(from session: ActiveSession) -> [ReaderTOCItem] {
        switch session {
        case .pdf(let pdfSession):
            return pdfSession.tableOfContents.map {
                ReaderTOCItem(
                    id: $0.id,
                    title: $0.title,
                    level: $0.level,
                    location: .pdf(pageIndex: $0.pageIndex)
                )
            }
        case .epub(let epubSession):
            return epubSession.tableOfContents.map {
                ReaderTOCItem(
                    id: $0.id,
                    title: $0.title,
                    level: $0.level,
                    location: .epub(resourcePath: $0.resourcePath)
                )
            }
        case .placeholder:
            return []
        }
    }

    private func updateActiveEPUBReadingOrder(for session: ActiveSession) {
        guard case .epub(let epubSession) = session else {
            setActiveEPUBReadingOrder([])
            return
        }

        var orderedURLs: [URL] = []
        var seenPaths: Set<String> = []
        let rootURL = epubSession.extractedRootURL

        func appendIfNeeded(_ url: URL) {
            let normalized = normalizedEPUBNavigationURL(url)
            let pathKey = normalized.standardizedFileURL.path
            guard !pathKey.isEmpty else {
                return
            }
            guard !seenPaths.contains(pathKey) else {
                return
            }
            seenPaths.insert(pathKey)
            orderedURLs.append(normalized)
        }

        appendIfNeeded(epubSession.startDocumentURL)
        for path in epubSession.readingOrderResourcePaths {
            appendIfNeeded(resolveEPUBURL(rootURL: rootURL, resourcePath: path))
        }
        for toc in epubSession.tableOfContents {
            appendIfNeeded(resolveEPUBURL(rootURL: rootURL, resourcePath: toc.resourcePath))
        }

        setActiveEPUBReadingOrder(orderedURLs)
    }

    private func setActiveEPUBReadingOrder(_ urls: [URL]) {
        activeEPUBReadingOrder = urls
        activeEPUBReadingOrderRevision += 1
    }

    func searchActiveBook() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let session = activeSession else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask?.cancel()
        isSearching = true

        switch session {
        case .pdf(let pdfSession):
            let fileURL = pdfSession.document.fileURL
            searchTask = Task {
                let results = await Self.performBackgroundSearch {
                    Self.searchPDF(fileURL: fileURL, query: query)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query {
                        self.searchResults = results
                        self.isSearching = false
                    }
                }
            }
        case .epub(let epubSession):
            let rootURL = epubSession.extractedRootURL
            searchTask = Task {
                let results = await Self.performBackgroundSearch {
                    Self.searchEPUB(rootURL: rootURL, query: query)
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query {
                        self.searchResults = results
                        self.isSearching = false
                    }
                }
            }
        case .placeholder:
            searchResults = []
            isSearching = false
        }
    }

    func openSearchResult(_ result: DocumentSearchResult) {
        guard let bookID = activeBookID else {
            return
        }
        switch result.location {
        case .pdf(let pageIndex):
            issuePDFNavigationCommand(pageIndex: pageIndex)
            epubFindRequest = nil
            activeTOCItemID = findMatchingTOCItemID(for: .pdf(pageIndex: pageIndex))
            updateLocation(for: bookID, location: .pdf(pageIndex: pageIndex))
        case .epub(let resourcePath, let query, let occurrence):
            guard case .epub(let session) = activeSession else {
                return
            }
            issueEPUBNavigationCommand(url: resolveEPUBURL(
                rootURL: session.extractedRootURL,
                resourcePath: resourcePath
            ))
            epubFindRequest = EPUBFindRequest(query: query, occurrence: occurrence)
            activeTOCItemID = findMatchingTOCItemID(for: .epub(resourcePath: resourcePath))
            updateLocation(for: bookID, location: .epub(resourcePath: resourcePath))
        }
    }

    private func restoreLibrary() async {
        do {
            let records = try await libraryStore.load()
            books = records.map(\.document)
            readingStatesByBookID = Dictionary(
                uniqueKeysWithValues: records.map { ($0.document.id, $0.readingState) }
            )
            bookmarkDataByBookID = Dictionary(
                uniqueKeysWithValues: records.compactMap { record in
                    guard let data = record.securityScopedBookmarkData else {
                        return nil
                    }
                    return (record.document.id, data)
                }
            )
            if let resumeRecord = records
                .sorted(by: { ($0.readingState.lastOpenedAt ?? .distantPast) > ($1.readingState.lastOpenedAt ?? .distantPast) })
                .first,
               resumeRecord.readingState.lastOpenedAt != nil {
                try? open(document: resumeRecord.document)
            }
        } catch {
            lastError = "Failed to restore library: \(error.localizedDescription)"
        }
    }

    private func openSessionWithCache(document: BookDocument) throws -> ActiveSession {
        if let cached = sessionCache[document.fileURL] {
            return cached
        }

        let session: any ReadingSession
        switch document.format {
        case .pdf:
            session = try pdfEngine.open(document: document)
        case .epub:
            session = try epubEngine.open(document: document)
        case .mobi:
            session = try mobiEngine.open(document: document)
        case .unknown:
            throw ReaderError.formatUnsupported(document.fileURL)
        }

        let active = ActiveSession.from(session: session)
        syncBookMetadata(with: session.document)
        sessionCache[document.fileURL] = active
        return active
    }

    private func syncBookMetadata(with openedDocument: BookDocument) {
        guard let index = books.firstIndex(where: { $0.id == openedDocument.id }) else {
            return
        }
        let existing = books[index]
        if existing.title == openedDocument.title && existing.format == openedDocument.format {
            return
        }
        books[index] = BookDocument(
            id: existing.id,
            fileURL: existing.fileURL,
            title: openedDocument.title,
            format: existing.format
        )
    }

    private func mergeOrInsertImportedDocument(_ document: BookDocument) -> BookDocument {
        if let existingIndex = books.firstIndex(where: { sameFile($0.fileURL, document.fileURL) }) {
            let existing = books[existingIndex]
            books[existingIndex] = BookDocument(
                id: existing.id,
                fileURL: document.fileURL,
                title: document.title,
                format: document.format
            )
            return books[existingIndex]
        }

        books.insert(document, at: 0)
        return document
    }

    private func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func resolveDocumentForOpen(_ document: BookDocument) -> BookDocument {
        guard let bookmarkData = bookmarkDataByBookID[document.id] else {
            return document
        }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return document
        }

        if isStale, let refreshed = try? resolved.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmarkDataByBookID[document.id] = refreshed
        }

        return BookDocument(
            id: document.id,
            fileURL: resolved,
            title: document.title,
            format: document.format
        )
    }

    private func resolveEPUBURL(rootURL: URL, resourcePath: String) -> URL {
        if let relative = URL(string: resourcePath, relativeTo: rootURL)?.absoluteURL {
            return relative
        }
        return rootURL.appendingPathComponent(resourcePath).standardizedFileURL
    }

    private func normalizedEPUBNavigationURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url.standardizedFileURL, resolvingAgainstBaseURL: false) else {
            return url.standardizedFileURL
        }
        components.fragment = nil
        return components.url?.standardizedFileURL ?? url.standardizedFileURL
    }

    private func applyLastLocation(_ location: ReadingLocation?, for session: ActiveSession?) {
        switch (session, location) {
        case (.pdf, .pdf(let pageIndex)):
            issuePDFNavigationCommand(pageIndex: pageIndex)
            epubFindRequest = nil
            activeTOCItemID = findMatchingTOCItemID(for: .pdf(pageIndex: pageIndex))
        case (.epub(let epubSession), .epub(let resourcePath)):
            issueEPUBNavigationCommand(url: resolveEPUBURL(
                rootURL: epubSession.extractedRootURL,
                resourcePath: resourcePath
            ))
            epubFindRequest = nil
            activeTOCItemID = findMatchingTOCItemID(for: .epub(resourcePath: resourcePath))
        default:
            pdfNavigationTargetPageIndex = nil
            epubNavigationTargetURL = nil
            pdfNavigationCommandID = nil
            epubNavigationCommandID = nil
            epubFindRequest = nil
            activeTOCItemID = nil
        }
    }

    private func issuePDFNavigationCommand(pageIndex: Int) {
        pdfNavigationTargetPageIndex = max(0, pageIndex)
        pdfNavigationCommandID = UUID()
    }

    private func issueEPUBNavigationCommand(url: URL) {
        epubNavigationTargetURL = url
        epubNavigationCommandID = UUID()
    }

    private func defaultLocationForActiveSession() -> ReadingLocation {
        switch activeSession {
        case .pdf:
            return .pdf(pageIndex: pdfNavigationTargetPageIndex ?? 0)
        case .epub(let session):
            let root = session.extractedRootURL.standardizedFileURL.path
            let start = session.startDocumentURL.standardizedFileURL.path
            let relative = String(start.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else {
                return .pdf(pageIndex: 0)
            }
            if let fragment = session.startDocumentURL.fragment, !fragment.isEmpty {
                return .epub(resourcePath: "\(relative)#\(fragment)")
            }
            return .epub(resourcePath: relative)
        default:
            return .pdf(pageIndex: 0)
        }
    }

    private func updateLocation(for bookID: UUID, location: ReadingLocation) {
        var state = readingStatesByBookID[bookID] ?? BookReadingState()
        state.lastLocation = location
        readingStatesByBookID[bookID] = state
        if bookID == activeBookID {
            activeTOCItemID = findMatchingTOCItemID(for: location)
        }
        persistLibraryAsync()
    }

    private func findMatchingTOCItemID(for location: ReadingLocation) -> UUID? {
        guard !tableOfContents.isEmpty else {
            return nil
        }
        switch location {
        case .pdf(let pageIndex):
            let pdfItems = tableOfContents.compactMap { item -> (UUID, Int)? in
                if case .pdf(let tocPage) = item.location {
                    return (item.id, tocPage)
                }
                return nil
            }
            if let exact = pdfItems.first(where: { $0.1 == pageIndex }) {
                return exact.0
            }
            return pdfItems
                .filter { $0.1 <= pageIndex }
                .max(by: { $0.1 < $1.1 })?
                .0
        case .epub(let resourcePath):
            let normalized = normalizeEPUBResourcePath(resourcePath)
            for item in tableOfContents {
                guard case .epub(let tocPath) = item.location else { continue }
                if tocPath == resourcePath {
                    return item.id
                }
            }
            for item in tableOfContents {
                guard case .epub(let tocPath) = item.location else { continue }
                if normalizeEPUBResourcePath(tocPath) == normalized {
                    return item.id
                }
            }
            return nil
        }
    }

    private func normalizeEPUBResourcePath(_ path: String) -> String {
        path.components(separatedBy: "#").first ?? path
    }

    private func ensureSecurityScopeAccess(for url: URL) {
        let path = url.standardizedFileURL.path
        guard !securityScopedAccessedPaths.contains(path) else {
            return
        }
        if url.startAccessingSecurityScopedResource() {
            securityScopedAccessedPaths.insert(path)
        }
    }

    private func persistLibraryAsync() {
        let records = books.map { book in
            LibraryBookRecord(
                document: book,
                securityScopedBookmarkData: bookmarkDataByBookID[book.id],
                readingState: readingStatesByBookID[book.id] ?? BookReadingState()
            )
        }
        Task {
            do {
                try await libraryStore.save(records: records)
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to persist library: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistPreferencesAsync() {
        let snapshot = preferences
        Task {
            do {
                try await preferencesStore.save(snapshot)
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to save preferences: \(error.localizedDescription)"
                }
            }
        }
    }

    private func persistTranslationMemoryAsync() {
        let snapshot = translationMemoryByBookID
        Task {
            do {
                try await translationMemoryStore.save(snapshot)
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to save translation memory: \(error.localizedDescription)"
                }
            }
        }
    }

    private func storeTranslation(_ translatedText: String, for bookID: UUID, key: String) {
        let cleaned = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }
        var map = translationMemoryByBookID[bookID] ?? [:]
        map[key] = cleaned
        translationMemoryByBookID[bookID] = map
        if activeBookID == bookID {
            setActiveTranslationHints(map)
        }
        persistTranslationMemoryAsync()
    }

    private func setActiveTranslationHints(_ hints: [String: String]) {
        guard activeTranslationHints != hints else {
            return
        }
        activeTranslationHints = hints
        activeTranslationHintsRevision &+= 1
    }

    private func normalizedTranslationSourceText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTranslationKey(_ sourceText: String) -> String {
        sourceText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated private static func performBackgroundSearch(
        operation: @escaping @Sendable () -> [DocumentSearchResult]
    ) async -> [DocumentSearchResult] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: operation())
            }
        }
    }

    nonisolated private static func searchPDF(fileURL: URL, query: String) -> [DocumentSearchResult] {
        guard let document = PDFDocument(url: fileURL) else {
            return []
        }

        var results: [DocumentSearchResult] = []
        let maxResults = 200
        for pageIndex in 0..<document.pageCount {
            guard results.count < maxResults else { break }
            guard let page = document.page(at: pageIndex), let text = page.string else {
                continue
            }
            if let snippet = firstSnippet(text: text, query: query) {
                results.append(
                    DocumentSearchResult(location: .pdf(pageIndex: pageIndex), snippet: snippet)
                )
            }
        }
        return results
    }

    nonisolated private static func searchEPUB(rootURL: URL, query: String) -> [DocumentSearchResult] {
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let allowedExtensions = Set(["html", "htm", "xhtml", "xml"])
        var results: [DocumentSearchResult] = []
        let maxResults = 200
        let rootPath = rootURL.standardizedFileURL.path

        for case let fileURL as URL in enumerator {
            guard results.count < maxResults else { break }
            guard allowedExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            guard let content = readText(fileURL: fileURL) else {
                continue
            }
            let plainText = stripHTML(from: content)
            let snippets = snippets(text: plainText, query: query, maxCount: maxResults - results.count)
            guard !snippets.isEmpty else {
                continue
            }
            let fullPath = fileURL.standardizedFileURL.path
            guard fullPath.hasPrefix(rootPath) else {
                continue
            }
            let relativePath = String(fullPath.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            for (index, snippet) in snippets.enumerated() {
                results.append(
                    DocumentSearchResult(
                        location: .epub(
                            resourcePath: relativePath,
                            query: query,
                            occurrence: index + 1
                        ),
                        snippet: snippet
                    )
                )
                guard results.count < maxResults else { break }
            }
        }
        return results
    }

    nonisolated private static func readText(fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return nil
    }

    nonisolated private static func stripHTML(from html: String) -> String {
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: (html as NSString).length)
            let stripped = regex.stringByReplacingMatches(
                in: html,
                options: [],
                range: range,
                withTemplate: " "
            )
            return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        return html
    }

    nonisolated private static func firstSnippet(text: String, query: String) -> String? {
        snippets(text: text, query: query, maxCount: 1).first
    }

    nonisolated private static func snippets(
        text: String,
        query: String,
        maxCount: Int
    ) -> [String] {
        guard maxCount > 0 else {
            return []
        }
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        var results: [String] = []
        var searchStart = normalized.startIndex

        while searchStart < normalized.endIndex, results.count < maxCount {
            guard let range = normalized.range(
                of: query,
                options: .caseInsensitive,
                range: searchStart..<normalized.endIndex
            ) else {
                break
            }
            let lowerBound = normalized.distance(from: normalized.startIndex, to: range.lowerBound)
            let upperBound = normalized.distance(from: normalized.startIndex, to: range.upperBound)
            let start = max(0, lowerBound - 50)
            let end = min(normalized.count, upperBound + 70)
            let startIndex = normalized.index(normalized.startIndex, offsetBy: start)
            let endIndex = normalized.index(normalized.startIndex, offsetBy: end)
            let snippet = String(normalized[startIndex..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
                results.append(snippet)
            }
            searchStart = range.upperBound
        }

        return results
    }
}
