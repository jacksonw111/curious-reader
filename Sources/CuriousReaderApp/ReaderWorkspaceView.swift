import AppKit
import PDFKit
import QuickLookThumbnailing
import ReaderCore
import ReaderLibrary
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum ReaderPalette {
    static let accent = Color(red: 0.43, green: 0.30, blue: 0.18)
    static let surface = Color(red: 0.98, green: 0.96, blue: 0.91)
    static let canvasTop = Color(red: 0.99, green: 0.97, blue: 0.92)
    static let canvasBottom = Color(red: 0.95, green: 0.91, blue: 0.83)
}

private extension BookFormat {
    var libraryFallbackIconName: String {
        switch self {
        case .pdf:
            return "doc.richtext"
        case .epub:
            return "book.pages"
        case .mobi:
            return "books.vertical"
        case .unknown:
            return "doc"
        }
    }

    var libraryFallbackColor: Color {
        switch self {
        case .pdf:
            return .red
        case .epub:
            return .blue
        case .mobi:
            return .orange
        case .unknown:
            return .gray
        }
    }
}

private extension URL {
    func removingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        components.fragment = nil
        return components.url ?? self
    }
}

struct ReaderWorkspaceView: View {
    @ObservedObject var model: ReaderWorkspaceModel
    @State private var isImporterPresented = false
    @State private var isSearchPresented = false

    private var importTypes: [UTType] {
        [
            .pdf,
            UTType(filenameExtension: "epub"),
            UTType(filenameExtension: "mobi"),
            UTType(filenameExtension: "prc"),
            UTType(filenameExtension: "azw"),
        ].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            if model.activeSession == nil {
                LibraryShelfView(
                    books: model.books,
                    recentlyReadBooks: model.recentlyReadBooks(limit: 5),
                    lastOpenedAt: { model.lastOpenedDate(for: $0) },
                    onImport: { isImporterPresented = true },
                    onOpen: { book in
                        model.openWithLoading(document: book)
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.985)),
                        removal: .opacity
                    )
                )
            } else {
                ReaderModeView(model: model)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.995)),
                            removal: .opacity
                        )
                    )
            }

            if model.isOpeningBook {
                KindleOpeningOverlay(title: model.openingBookTitle ?? "Opening Book")
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.08), value: model.activeSession == nil)
        .animation(.easeInOut(duration: 0.2), value: model.isOpeningBook)
        .toolbar {
            ToolbarItemGroup {
                if model.activeSession == nil {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("o", modifiers: [.command])
                } else {
                    Button {
                        model.closeReaderSession()
                    } label: {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .labelStyle(.iconOnly)
                    .help("Back to Library")
                    .keyboardShortcut("l", modifiers: [.command])

                    Button {
                        isSearchPresented = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .help("Search")
                    .keyboardShortcut("f", modifiers: [.command])

                    Button {
                        model.addBookmarkForActiveBook()
                    } label: {
                        Label("Bookmark", systemImage: "bookmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Add Bookmark")
                    .keyboardShortcut("d", modifiers: [.command])
                }
            }
        }
        .sheet(isPresented: $isSearchPresented) {
            ReaderSearchSheet(
                model: model,
                onSelect: {
                    isSearchPresented = false
                }
            )
            .frame(minWidth: 620, minHeight: 520)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var sources: [ImportedBookSource] = []
                var accessedURLs: [URL] = []
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        accessedURLs.append(url)
                    }
                    let bookmarkData = try? url.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    sources.append(
                        ImportedBookSource(
                            fileURL: url,
                            securityScopedBookmarkData: bookmarkData
                        )
                    )
                }
                model.importBooks(from: sources, openFirstImportedBook: false)
                accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            case .failure(let error):
                model.lastError = error.localizedDescription
            }
        }
        .alert(
            "Open Failed",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { if !$0 { model.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.lastError = nil
            }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}

private struct KindleOpeningOverlay: View {
    let title: String
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.11))
                    Text("Opening")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.09))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.08))
                        .frame(height: 5)
                    Capsule()
                        .fill(Color(red: 0.22, green: 0.24, blue: 0.27))
                        .frame(width: animate ? 220 : 70, height: 5)
                        .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: animate)
                }

                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color(red: 0.2, green: 0.21, blue: 0.23))
                            .frame(width: 6, height: 6)
                            .scaleEffect(animate ? 1 : 0.45)
                            .opacity(animate ? 1 : 0.45)
                            .animation(
                                .easeInOut(duration: 0.55)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.13),
                                value: animate
                            )
                    }
                }
            }
            .padding(18)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(red: 0.96, green: 0.93, blue: 0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 12)
            )
        }
        .onAppear {
            animate = true
        }
    }
}

private struct LibraryShelfView: View {
    private enum DisplayMode: String, Identifiable {
        case cards
        case list

        var id: String { rawValue }
    }

    let books: [BookDocument]
    let recentlyReadBooks: [BookDocument]
    let lastOpenedAt: (UUID) -> Date?
    let onImport: () -> Void
    let onOpen: (BookDocument) -> Void
    @State private var searchQuery = ""
    @State private var displayMode: DisplayMode = .cards
    @State private var currentPage = 1

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 252, maximum: 252), spacing: 24, alignment: .top)]
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredBooks: [BookDocument] {
        guard !normalizedSearchQuery.isEmpty else {
            return books
        }
        return books.filter { book in
            let titleMatches = book.title.lowercased().contains(normalizedSearchQuery)
            let fileMatches = book.fileURL.lastPathComponent.lowercased().contains(normalizedSearchQuery)
            return titleMatches || fileMatches
        }
    }

    private var pageSize: Int {
        switch displayMode {
        case .cards:
            return 12
        case .list:
            return 18
        }
    }

    private var totalPages: Int {
        guard !filteredBooks.isEmpty else {
            return 1
        }
        return max(1, Int(ceil(Double(filteredBooks.count) / Double(pageSize))))
    }

    private var safePage: Int {
        min(max(1, currentPage), totalPages)
    }

    private var paginatedBooks: [BookDocument] {
        guard !filteredBooks.isEmpty else {
            return []
        }
        let startIndex = (safePage - 1) * pageSize
        guard startIndex < filteredBooks.count else {
            return []
        }
        let endIndex = min(startIndex + pageSize, filteredBooks.count)
        return Array(filteredBooks[startIndex..<endIndex])
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ReaderPalette.canvasTop, ReaderPalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Curious Library")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .tracking(-0.9)
                        Text("A focused shelf for PDF, EPUB, and MOBI.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("\(books.count) books")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReaderPalette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(ReaderPalette.accent.opacity(0.13))
                        )
                    Button {
                        onImport()
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ReaderPalette.accent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 30)
                .padding(.top, 26)

                Group {
                    if books.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(ReaderPalette.accent)
                            Text("No Books Yet")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                            Text("Import PDF, EPUB, or MOBI files to build your shelf.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Button("Import Your First Book") {
                                onImport()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ReaderPalette.accent)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 28) {
                                if !recentlyReadBooks.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Text("Continue Reading")
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .textCase(.uppercase)
                                                .tracking(1.0)
                                            Text("\(recentlyReadBooks.count)")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(.white.opacity(0.5)))
                                        }
                                        ScrollView(.horizontal) {
                                            LazyHStack(spacing: 14) {
                                                ForEach(recentlyReadBooks) { book in
                                                    Button {
                                                        onOpen(book)
                                                    } label: {
                                                        RecentReadingCard(
                                                            book: book,
                                                            lastOpenedAt: lastOpenedAt(book.id)
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.vertical, 2)
                                        }
                                        .scrollIndicators(.hidden)
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(.white.opacity(0.45))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                                            )
                                            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 6)
                                    )
                                }

                                Divider()
                                    .overlay(ReaderPalette.accent.opacity(0.2))
                                    .padding(.horizontal, 2)

                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        Text("Library")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                            .tracking(1.0)
                                        Spacer(minLength: 0)
                                        Text("\(filteredBooks.count)")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(.white.opacity(0.52)))
                                    }

                                    HStack(spacing: 10) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                            TextField("Search title or file name", text: $searchQuery)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(height: 38)
                                        .background(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .fill(ReaderPalette.surface.opacity(0.95))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                        .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                                                )
                                                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                                        )

                                        Spacer(minLength: 0)

                                        Picker("View Mode", selection: $displayMode) {
                                            Image(systemName: "square.grid.2x2")
                                                .tag(DisplayMode.cards)
                                            Image(systemName: "list.bullet")
                                                .tag(DisplayMode.list)
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .frame(width: 106)
                                        .accessibilityLabel("Library View Mode")
                                    }

                                    if filteredBooks.isEmpty {
                                        ContentUnavailableView(
                                            "No Matching Books",
                                            systemImage: "doc.text.magnifyingglass",
                                            description: Text("Try another keyword.")
                                        )
                                        .frame(maxWidth: .infinity, minHeight: 220)
                                    } else if displayMode == .cards {
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                                            ForEach(paginatedBooks) { book in
                                                Button {
                                                    onOpen(book)
                                                } label: {
                                                    BookCard(book: book)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    } else {
                                        LazyVStack(alignment: .leading, spacing: 10) {
                                            ForEach(paginatedBooks) { book in
                                                Button {
                                                    onOpen(book)
                                                } label: {
                                                    LibraryListRow(
                                                        book: book,
                                                        lastOpenedAt: lastOpenedAt(book.id)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }

                                HStack {
                                    Button {
                                        currentPage = max(1, safePage - 1)
                                    } label: {
                                        Label("Previous Page", systemImage: "chevron.left")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(safePage <= 1)

                                    Spacer(minLength: 0)

                                    Text("Page \(safePage) / \(totalPages)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)

                                    Spacer(minLength: 0)

                                    Button {
                                        currentPage = min(totalPages, safePage + 1)
                                    } label: {
                                        Label("Next Page", systemImage: "chevron.right")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(safePage >= totalPages)
                                }
                                .padding(.top, 6)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.55), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 10)
                )
                .padding(.horizontal, 30)
                .padding(.bottom, 26)
            }
            .frame(maxWidth: 1480)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: searchQuery) { _, _ in
            currentPage = 1
        }
        .onChange(of: displayMode) { _, _ in
            currentPage = 1
        }
        .onChange(of: filteredBooks.count) { _, _ in
            currentPage = min(currentPage, totalPages)
        }
    }
}

private struct RecentReadingCard: View {
    private static let coverAspectRatio: CGFloat = 3.0 / 4.0

    let book: BookDocument
    let lastOpenedAt: Date?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            BookCoverThumbnail(
                book: book,
                fallbackColor: book.format.libraryFallbackColor,
                fallbackIcon: book.format.libraryFallbackIconName
            )
            .frame(width: 62, height: 82)
            .aspectRatio(Self.coverAspectRatio, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(book.format.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReaderPalette.accent)
                    if let lastOpenedAt {
                        Text(lastOpenedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 238, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ReaderPalette.surface.opacity(isHovering ? 0.98 : 0.93))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.68), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 5)
        )
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.spring(duration: 0.22, bounce: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct BookCard: View {
    private static let cardWidth: CGFloat = 252
    private static let coverWidth: CGFloat = 224
    private static let coverAspectRatio: CGFloat = 3.0 / 4.0

    let book: BookDocument
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookCoverThumbnail(
                book: book,
                fallbackColor: book.format.libraryFallbackColor,
                fallbackIcon: book.format.libraryFallbackIconName
            )
                .frame(width: Self.coverWidth)
                .aspectRatio(Self.coverAspectRatio, contentMode: .fit)
            Text(book.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 62, alignment: .topLeading)
            HStack(spacing: 9) {
                Text(formatText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ReaderPalette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(ReaderPalette.accent.opacity(0.12))
                    )
                Text(book.fileURL.lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: 20, alignment: .leading)
        }
        .padding(14)
        .frame(width: Self.cardWidth, height: 428)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ReaderPalette.surface.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 7)
        )
        .scaleEffect(isHovering ? 1.018 : 1)
        .offset(y: isHovering ? -1 : 0)
        .animation(.spring(duration: 0.24, bounce: 0.14), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var formatText: String {
        book.format.rawValue.uppercased()
    }
}

private struct LibraryListRow: View {
    private static let coverAspectRatio: CGFloat = 3.0 / 4.0

    let book: BookDocument
    let lastOpenedAt: Date?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            BookCoverThumbnail(
                book: book,
                fallbackColor: book.format.libraryFallbackColor,
                fallbackIcon: book.format.libraryFallbackIconName
            )
                .frame(width: 54, height: 72)
                .aspectRatio(Self.coverAspectRatio, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(formatText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ReaderPalette.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(ReaderPalette.accent.opacity(0.12))
                        )
                    Text(book.fileURL.lastPathComponent)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let lastOpenedAt {
                Text(lastOpenedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ReaderPalette.surface.opacity(isHovering ? 0.99 : 0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(isHovering ? 1.005 : 1)
        .animation(.spring(duration: 0.2, bounce: 0.1), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var formatText: String {
        book.format.rawValue.uppercased()
    }
}

private struct ReaderModeView: View {
    @ObservedObject var model: ReaderWorkspaceModel

    var body: some View {
        NavigationSplitView {
            TOCSidebar(
                items: model.tableOfContents,
                selectedItemID: model.activeTOCItemID,
                onSelect: { model.openTOCItem($0) }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } detail: {
            SessionDetailView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .background(
            LinearGradient(
                colors: [ReaderPalette.canvasTop, ReaderPalette.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct TOCSidebar: View {
    private struct TOCTreeNode: Identifiable {
        let item: ReaderTOCItem
        let children: [TOCTreeNode]

        var id: UUID { item.id }
        var hasChildren: Bool { !children.isEmpty }
    }

    private struct VisibleTOCRow: Identifiable {
        let item: ReaderTOCItem
        let depth: Int
        let hasChildren: Bool

        var id: UUID { item.id }
    }

    let items: [ReaderTOCItem]
    let selectedItemID: UUID?
    let onSelect: (ReaderTOCItem) -> Void
    @State private var collapsedNodeIDs: Set<UUID> = []
    @State private var tocTree: [TOCTreeNode] = []
    @State private var visibleRows: [VisibleTOCRow] = []

    var body: some View {
        List {
            Section {
                ForEach(visibleRows) { row in
                    HStack(spacing: 6) {
                        if row.hasChildren {
                            Button {
                                toggleCollapse(for: row.id)
                            } label: {
                                Image(systemName: collapsedNodeIDs.contains(row.id) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 14, height: 14)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear
                                .frame(width: 14, height: 14)
                        }

                        Button {
                            onSelect(row.item)
                        } label: {
                            HStack {
                                Text(row.item.title)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        row.id == selectedItemID
                                        ? ReaderPalette.accent.opacity(0.17)
                                        : .clear
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, CGFloat(row.depth) * 14)
                }
            } header: {
                HStack {
                    Text("Contents")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(visibleRows.count)/\(items.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Table of Contents",
                    systemImage: "list.bullet.rectangle",
                    description: Text("This file does not expose an outline.")
                )
            }
        }
        .onAppear {
            rebuildTOCState()
        }
        .onChange(of: items) { _, _ in
            rebuildTOCState()
        }
    }

    private func toggleCollapse(for id: UUID) {
        if collapsedNodeIDs.contains(id) {
            collapsedNodeIDs.remove(id)
        } else {
            collapsedNodeIDs.insert(id)
        }
        rebuildVisibleRows()
    }

    private func buildChildren(baseLevel: Int, cursor: inout Int) -> [TOCTreeNode] {
        var nodes: [TOCTreeNode] = []
        while cursor < items.count {
            let item = items[cursor]
            if item.level <= baseLevel {
                break
            }
            cursor += 1
            let children = buildChildren(baseLevel: item.level, cursor: &cursor)
            nodes.append(TOCTreeNode(item: item, children: children))
        }
        return nodes
    }

    private func rebuildTOCState() {
        var cursor = 0
        let tree = buildChildren(baseLevel: -1, cursor: &cursor)
        tocTree = tree
        syncCollapsedNodesWithCurrentTree(tree)
        rebuildVisibleRows()
    }

    private func rebuildVisibleRows() {
        var rows: [VisibleTOCRow] = []
        appendVisibleRows(nodes: tocTree, depth: 0, rows: &rows)
        visibleRows = rows
    }

    private func appendVisibleRows(nodes: [TOCTreeNode], depth: Int, rows: inout [VisibleTOCRow]) {
        for node in nodes {
            rows.append(
                VisibleTOCRow(
                    item: node.item,
                    depth: depth,
                    hasChildren: node.hasChildren
                )
            )
            guard node.hasChildren, !collapsedNodeIDs.contains(node.id) else {
                continue
            }
            appendVisibleRows(nodes: node.children, depth: depth + 1, rows: &rows)
        }
    }

    private func syncCollapsedNodesWithCurrentTree(_ nodes: [TOCTreeNode]) {
        var parentNodeIDs: Set<UUID> = []
        collectParentNodeIDs(nodes: nodes, into: &parentNodeIDs)
        collapsedNodeIDs = collapsedNodeIDs.intersection(parentNodeIDs)
    }

    private func collectParentNodeIDs(nodes: [TOCTreeNode], into parentNodeIDs: inout Set<UUID>) {
        for node in nodes {
            guard node.hasChildren else {
                continue
            }
            parentNodeIDs.insert(node.id)
            collectParentNodeIDs(nodes: node.children, into: &parentNodeIDs)
        }
    }
}

private struct SessionDetailView: View {
    @ObservedObject var model: ReaderWorkspaceModel
    @State private var screenshotPreview: NSImage?
    @State private var pdfSelectionSnapshotCommandID: UUID?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                switch model.activeSession {
                case .none:
                    ContentUnavailableView(
                        "Select a Book",
                        systemImage: "text.book.closed",
                        description: Text("Your reading session will open here.")
                    )
                case .pdf(let pdfSession):
                    PDFDocumentView(
                        pdfDocument: pdfSession.pdfDocument,
                        targetPageIndex: model.pdfNavigationTargetPageIndex,
                        targetPageCommandID: model.pdfNavigationCommandID,
                        requestSelectionSnapshotCommandID: pdfSelectionSnapshotCommandID,
                        onPageChanged: { model.updatePDFLocation(pageIndex: $0) },
                        onTextSelected: { model.updatePendingSelectionText($0) },
                        onSelectionSnapshotCaptured: { screenshotPreview = $0 },
                        onPageTapped: { model.dismissTranslationPanelIfIdle() }
                    )
                    .navigationTitle(pdfSession.document.title)
                case .epub(let epubSession):
                    EPUBDocumentView(
                        startDocumentURL: epubSession.startDocumentURL,
                        targetURL: model.epubNavigationTargetURL,
                        targetCommandID: model.epubNavigationCommandID,
                        allowedRootURL: epubSession.extractedRootURL,
                        findRequest: model.epubFindRequest,
                        fontStyle: model.preferences.epubFontStyle,
                        fontSize: model.preferences.epubFontSize,
                        translationHints: model.activeTranslationHints,
                        translationHintsRevision: model.activeTranslationHintsRevision,
                        readingOrderURLs: model.activeEPUBReadingOrder,
                        readingOrderRevision: model.activeEPUBReadingOrderRevision,
                        onLocationChanged: { model.updateEPUBLocation(url: $0) },
                        onTextSelected: { model.updatePendingSelectionText($0) },
                        onTranslateRequested: { model.translateSelectedText($0) },
                        onScreenshotCaptured: { screenshotPreview = $0 },
                        onPageTapped: { model.dismissTranslationPanelIfIdle() }
                    )
                    .navigationTitle(epubSession.document.title)
                case .placeholder(let title, let message):
                    VStack(spacing: 12) {
                        Text(title)
                            .font(.title2.weight(.semibold))
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
            .padding(12)

            VStack(alignment: .trailing, spacing: 12) {
                if let panel = model.translationPanel {
                    TranslationPanelView(state: panel) {
                        model.hideTranslationPanel()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let screenshotPreview {
                    SelectionScreenshotPreview(
                        image: screenshotPreview,
                        onSave: { saveScreenshot(screenshotPreview) },
                        onClose: { self.screenshotPreview = nil }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if shouldShowPDFSelectionTranslateTip {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("翻译") {
                            model.translatePendingSelectionText()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ReaderPalette.accent)
                        .controlSize(.small)

                        Button("截图") {
                            pdfSelectionSnapshotCommandID = UUID()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(24)
        }
        .animation(.spring(duration: 0.28, bounce: 0.1), value: model.translationPanel)
        .animation(.spring(duration: 0.22, bounce: 0.06), value: model.pendingSelectionText)
        .animation(.spring(duration: 0.26, bounce: 0.08), value: screenshotPreview != nil)
    }

    private var shouldShowPDFSelectionTranslateTip: Bool {
        guard case .pdf = model.activeSession else {
            return false
        }
        guard let pending = model.pendingSelectionText else {
            return false
        }
        return !pending.isEmpty
    }

    private func saveScreenshot(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            model.lastError = "Failed to encode screenshot as PNG."
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "selection-\(timestamp).png"
        panel.title = "保存截图"
        panel.prompt = "保存"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            try pngData.write(to: url, options: [.atomic])
        } catch {
            model.lastError = "Failed to save screenshot: \(error.localizedDescription)"
        }
    }
}

private struct SelectionScreenshotPreview: View {
    let image: NSImage
    let onSave: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("截图预览")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 260, height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

            HStack {
                Spacer(minLength: 0)
                Button("保存到本地") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(ReaderPalette.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
    }
}

private struct ReaderSearchSheet: View {
    @ObservedObject var model: ReaderWorkspaceModel
    let onSelect: () -> Void
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Search")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                Spacer()
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Search in current book", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .onSubmit {
                    model.searchActiveBook()
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))

            List {
                if model.searchResults.isEmpty {
                    Text(model.searchQuery.isEmpty ? "No query yet." : "No matches.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.searchResults) { result in
                        Button {
                            model.openSearchResult(result)
                            onSelect()
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [ReaderPalette.canvasTop, ReaderPalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            isQueryFocused = true
            if !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.searchActiveBook()
            }
        }
    }
}

private struct SearchResultRow: View {
    let result: DocumentSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(locationLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(result.snippet)
                .font(.callout)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    private var locationLabel: String {
        switch result.location {
        case .pdf(let pageIndex):
            return "PDF Page \(pageIndex + 1)"
        case .epub(let path, _, let occurrence):
            let pagePath = path.components(separatedBy: "#").first ?? path
            return "\(pagePath) · Match \(occurrence)"
        }
    }
}

private struct BookCoverThumbnail: View {
    let book: BookDocument
    let fallbackColor: Color
    let fallbackIcon: String

    @State private var thumbnail: NSImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(fallbackColor)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .task(id: book.fileURL.path) {
            loadTask?.cancel()
            loadTask = Task {
                let image = await BookCoverThumbnailStore.shared.thumbnail(for: book.fileURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    thumbnail = image
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }
}

private actor BookCoverThumbnailStore {
    static let shared = BookCoverThumbnailStore()

    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for fileURL: URL) async -> NSImage? {
        let cacheKey = fileURL.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        let requestedSize = CGSize(width: 480, height: 720)
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: requestedSize,
            scale: 2,
            representationTypes: .thumbnail
        )
        let image: NSImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
        if let image {
            cache.setObject(image, forKey: cacheKey)
        }
        return image
    }
}

private struct EPUBFindExecutor {
    static func makeScript(query: String, occurrence: Int) -> String {
        let safeQuery = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let normalizedOccurrence = max(1, occurrence)
        return """
        (() => {
          const query = "\(safeQuery)";
          const occurrence = \(normalizedOccurrence);
          if (!query) { return false; }
          const selection = window.getSelection();
          if (selection) { selection.removeAllRanges(); }
          let found = false;
          for (let index = 0; index < occurrence; index += 1) {
            found = window.find(query, false, false, true, false, false, false);
            if (!found) { break; }
          }
          if (!found) { return false; }
          const current = window.getSelection();
          if (!current || current.rangeCount === 0) { return true; }
          const range = current.getRangeAt(0);
          const node = range.startContainer.nodeType === 1
            ? range.startContainer
            : range.startContainer.parentElement;
          if (node && node.scrollIntoView) {
            node.scrollIntoView({ block: "center", inline: "nearest", behavior: "instant" });
          }
          return true;
        })();
        """
    }
}

private struct PDFDocumentView: NSViewRepresentable {
    let pdfDocument: PDFDocument
    let targetPageIndex: Int?
    let targetPageCommandID: UUID?
    let requestSelectionSnapshotCommandID: UUID?
    let onPageChanged: (Int) -> Void
    let onTextSelected: (String) -> Void
    let onSelectionSnapshotCaptured: (NSImage) -> Void
    let onPageTapped: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPageChanged: onPageChanged,
            onTextSelected: onTextSelected,
            onSelectionSnapshotCaptured: onSelectionSnapshotCaptured
        )
    }

    func makeNSView(context: Context) -> PDFView {
        let view = TappablePDFView(frame: .zero)
        view.displayMode = .singlePageContinuous
        view.displaysAsBook = false
        view.autoScales = true
        view.displaysPageBreaks = true
        view.document = pdfDocument
        view.onTap = onPageTapped
        context.coordinator.bind(view: view)
        context.coordinator.updateCallback(onPageChanged)
        context.coordinator.updateTextSelectionCallback(onTextSelected)
        context.coordinator.updateSelectionSnapshotCapturedCallback(onSelectionSnapshotCaptured)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = pdfDocument
        if let tappableView = nsView as? TappablePDFView {
            tappableView.onTap = onPageTapped
        }
        context.coordinator.updateCallback(onPageChanged)
        context.coordinator.updateTextSelectionCallback(onTextSelected)
        context.coordinator.updateSelectionSnapshotCapturedCallback(onSelectionSnapshotCaptured)
        if let targetPageCommandID,
           context.coordinator.lastHandledPageCommandID != targetPageCommandID {
            context.coordinator.lastHandledPageCommandID = targetPageCommandID
            if let targetPageIndex,
               context.coordinator.lastKnownPageIndex != targetPageIndex,
               let page = pdfDocument.page(at: targetPageIndex) {
                nsView.go(to: page)
            }
        }
        context.coordinator.captureSelectionSnapshotIfNeeded(
            commandID: requestSelectionSnapshotCommandID
        )
    }

    private final class TappablePDFView: PDFView {
        var onTap: (() -> Void)?

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            onTap?()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var view: PDFView?
        private var onPageChanged: (Int) -> Void
        private var onTextSelected: (String) -> Void
        private var onSelectionSnapshotCaptured: (NSImage) -> Void
        fileprivate var lastKnownPageIndex: Int?
        fileprivate var lastHandledPageCommandID: UUID?
        fileprivate var lastHandledSelectionSnapshotCommandID: UUID?
        private var pendingSelectionTask: Task<Void, Never>?

        init(
            onPageChanged: @escaping (Int) -> Void,
            onTextSelected: @escaping (String) -> Void,
            onSelectionSnapshotCaptured: @escaping (NSImage) -> Void
        ) {
            self.onPageChanged = onPageChanged
            self.onTextSelected = onTextSelected
            self.onSelectionSnapshotCaptured = onSelectionSnapshotCaptured
        }

        deinit {
            pendingSelectionTask?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        func bind(view: PDFView) {
            self.view = view
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handlePageChanged(_:)),
                name: Notification.Name.PDFViewPageChanged,
                object: view
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleSelectionChanged(_:)),
                name: Notification.Name.PDFViewSelectionChanged,
                object: view
            )
        }

        func updateCallback(_ callback: @escaping (Int) -> Void) {
            onPageChanged = callback
        }

        func updateTextSelectionCallback(_ callback: @escaping (String) -> Void) {
            onTextSelected = callback
        }

        func updateSelectionSnapshotCapturedCallback(_ callback: @escaping (NSImage) -> Void) {
            onSelectionSnapshotCaptured = callback
        }

        func captureSelectionSnapshotIfNeeded(commandID: UUID?) {
            guard let commandID else {
                return
            }
            guard lastHandledSelectionSnapshotCommandID != commandID else {
                return
            }
            lastHandledSelectionSnapshotCommandID = commandID
            captureSelectionSnapshot()
        }

        @objc
        private func handlePageChanged(_ notification: Notification) {
            guard let view = self.view, let page = view.currentPage else {
                return
            }
            let pageIndex = view.document?.index(for: page) ?? 0
            lastKnownPageIndex = pageIndex
            onPageChanged(pageIndex)
        }

        @objc
        private func handleSelectionChanged(_ notification: Notification) {
            guard let selection = view?.currentSelection?.string else {
                onTextSelected("")
                return
            }
            let expectedText = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !expectedText.isEmpty else {
                onTextSelected("")
                return
            }
            pendingSelectionTask?.cancel()
            pendingSelectionTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self else { return }
                guard let stableRawSelection = self.view?.currentSelection?.string else {
                    self.onTextSelected("")
                    return
                }
                let stableSelection = stableRawSelection.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stableSelection.isEmpty else {
                    self.onTextSelected("")
                    return
                }
                guard stableSelection == expectedText else {
                    return
                }
                self.onTextSelected(stableSelection)
            }
        }

        private func captureSelectionSnapshot() {
            guard let view,
                  let selection = view.currentSelection,
                  let page = selection.pages.first else {
                return
            }
            var selectionRect = selection.bounds(for: page)
            guard !selectionRect.isNull, selectionRect.width > 1, selectionRect.height > 1 else {
                return
            }
            selectionRect = selectionRect.insetBy(dx: -8, dy: -8)
            let pageBounds = page.bounds(for: .cropBox)
            selectionRect = selectionRect.intersection(pageBounds)
            guard !selectionRect.isNull, selectionRect.width > 1, selectionRect.height > 1 else {
                return
            }
            let renderScale = max(2, view.window?.backingScaleFactor ?? 2)
            let thumbnailSize = CGSize(
                width: pageBounds.width * renderScale,
                height: pageBounds.height * renderScale
            )
            let fullPageImage = page.thumbnail(of: thumbnailSize, for: .cropBox)
            guard let tiffData = fullPageImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let cgImage = bitmap.cgImage else {
                return
            }

            let pixelX = (selectionRect.minX - pageBounds.minX) * renderScale
            let pixelHeight = selectionRect.height * renderScale
            let pixelYFromBottom = (selectionRect.minY - pageBounds.minY) * renderScale
            let pixelY = thumbnailSize.height - pixelYFromBottom - pixelHeight
            var cropRect = CGRect(
                x: pixelX,
                y: pixelY,
                width: selectionRect.width * renderScale,
                height: pixelHeight
            ).integral
            cropRect = cropRect.intersection(
                CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height))
            )
            guard !cropRect.isNull, cropRect.width > 1, cropRect.height > 1,
                  let cropped = cgImage.cropping(to: cropRect) else {
                return
            }
            let image = NSImage(
                cgImage: cropped,
                size: CGSize(width: cropRect.width / renderScale, height: cropRect.height / renderScale)
            )
            onSelectionSnapshotCaptured(image)
        }
    }
}

private struct EPUBDocumentView: NSViewRepresentable {
    let startDocumentURL: URL
    let targetURL: URL?
    let targetCommandID: UUID?
    let allowedRootURL: URL
    let findRequest: EPUBFindRequest?
    let fontStyle: ReaderFontStyle
    let fontSize: Double
    let translationHints: [String: String]
    let translationHintsRevision: Int
    let readingOrderURLs: [URL]
    let readingOrderRevision: Int
    let onLocationChanged: (URL) -> Void
    let onTextSelected: (String) -> Void
    let onTranslateRequested: (String) -> Void
    let onScreenshotCaptured: (NSImage) -> Void
    let onPageTapped: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLocationChanged: onLocationChanged,
            onTextSelected: onTextSelected,
            onTranslateRequested: onTranslateRequested,
            onScreenshotCaptured: onScreenshotCaptured,
            onPageTapped: onPageTapped
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.bind(
            webView: webView,
            userContentController: userContentController
        )
        context.coordinator.updateCallback(onLocationChanged)
        context.coordinator.updateTextSelectionCallback(onTextSelected)
        context.coordinator.updateTranslateRequestCallback(onTranslateRequested)
        context.coordinator.updateScreenshotCapturedCallback(onScreenshotCaptured)
        context.coordinator.updatePageTapCallback(onPageTapped)
        context.coordinator.updateFindRequest(findRequest)
        context.coordinator.updateFont(style: fontStyle, size: fontSize)
        context.coordinator.updateTranslationHints(revision: translationHintsRevision, hints: translationHints)
        context.coordinator.updateReadingOrder(revision: readingOrderRevision, urls: readingOrderURLs)
        let initialURL = targetURL ?? startDocumentURL
        webView.loadFileURL(initialURL, allowingReadAccessTo: allowedRootURL)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateCallback(onLocationChanged)
        context.coordinator.updateTextSelectionCallback(onTextSelected)
        context.coordinator.updateTranslateRequestCallback(onTranslateRequested)
        context.coordinator.updateScreenshotCapturedCallback(onScreenshotCaptured)
        context.coordinator.updatePageTapCallback(onPageTapped)
        context.coordinator.updateFindRequest(findRequest)
        context.coordinator.updateFont(style: fontStyle, size: fontSize)
        context.coordinator.updateTranslationHints(revision: translationHintsRevision, hints: translationHints)
        context.coordinator.updateReadingOrder(revision: readingOrderRevision, urls: readingOrderURLs)
        if let targetURL,
           let targetCommandID,
           context.coordinator.lastHandledNavigationCommandID != targetCommandID {
            context.coordinator.lastHandledNavigationCommandID = targetCommandID
            if !isSameNavigationTarget(lhs: nsView.url, rhs: targetURL) {
                nsView.loadFileURL(targetURL, allowingReadAccessTo: allowedRootURL)
                return
            }
        }
        guard let currentURL = nsView.url else {
            nsView.loadFileURL(startDocumentURL, allowingReadAccessTo: allowedRootURL)
            return
        }
        context.coordinator.applyFindRequestIfNeeded(currentURL: currentURL)
    }

    private func isSameNavigationTarget(lhs: URL?, rhs: URL) -> Bool {
        guard let lhs else { return false }
        let lhsPath = lhs.standardizedFileURL.path
        let rhsPath = rhs.standardizedFileURL.path
        if lhsPath != rhsPath {
            return false
        }
        return lhs.fragment == rhs.fragment
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let scriptMessageName = "curiousReaderSelection"

        private weak var webView: WKWebView?
        private weak var userContentController: WKUserContentController?
        private var onLocationChanged: (URL) -> Void
        private var onTextSelected: (String) -> Void
        private var onTranslateRequested: (String) -> Void
        private var onScreenshotCaptured: (NSImage) -> Void
        private var onPageTapped: () -> Void
        private var findRequest: EPUBFindRequest?
        private var lastAppliedFindRequestID: UUID?
        private var currentFontStyle: ReaderFontStyle = .systemSans
        private var currentFontSize: Double = 19
        private var currentTranslationHints: [String: String] = [:]
        private var lastAppliedHintsRevision = -1
        private var pendingHintsJSON: String?
        private var areHintsDirty = false
        private var currentReadingOrderURLs: [URL] = []
        private var lastAppliedReadingOrderRevision = -1
        private var pendingReadingOrderJSON: String?
        private var isReadingOrderDirty = false
        private var lastAppliedFontStyle: ReaderFontStyle?
        private var lastAppliedFontSize: Double?
        fileprivate var lastHandledNavigationCommandID: UUID?

        init(
            onLocationChanged: @escaping (URL) -> Void,
            onTextSelected: @escaping (String) -> Void,
            onTranslateRequested: @escaping (String) -> Void,
            onScreenshotCaptured: @escaping (NSImage) -> Void,
            onPageTapped: @escaping () -> Void
        ) {
            self.onLocationChanged = onLocationChanged
            self.onTextSelected = onTextSelected
            self.onTranslateRequested = onTranslateRequested
            self.onScreenshotCaptured = onScreenshotCaptured
            self.onPageTapped = onPageTapped
        }

        func bind(webView: WKWebView, userContentController: WKUserContentController) {
            self.webView = webView
            self.userContentController = userContentController
            userContentController.removeScriptMessageHandler(forName: scriptMessageName)
            userContentController.add(self, name: scriptMessageName)
        }

        func updateCallback(_ callback: @escaping (URL) -> Void) {
            onLocationChanged = callback
        }

        func updateTextSelectionCallback(_ callback: @escaping (String) -> Void) {
            onTextSelected = callback
        }

        func updateTranslateRequestCallback(_ callback: @escaping (String) -> Void) {
            onTranslateRequested = callback
        }

        func updateScreenshotCapturedCallback(_ callback: @escaping (NSImage) -> Void) {
            onScreenshotCaptured = callback
        }

        func updatePageTapCallback(_ callback: @escaping () -> Void) {
            onPageTapped = callback
        }

        func updateFindRequest(_ findRequest: EPUBFindRequest?) {
            self.findRequest = findRequest
        }

        func updateFont(style: ReaderFontStyle, size: Double) {
            let clampedSize = max(14, min(size, 30))
            guard currentFontStyle != style || abs(currentFontSize - clampedSize) > 0.01 else {
                return
            }
            currentFontStyle = style
            currentFontSize = clampedSize
            applyFontIfPossible()
        }

        func updateTranslationHints(revision: Int, hints: [String: String]) {
            guard lastAppliedHintsRevision != revision else {
                return
            }
            lastAppliedHintsRevision = revision
            let normalized = normalizedHintMap(hints)
            currentTranslationHints = normalized
            pendingHintsJSON = makeHintsJSON(normalized)
            areHintsDirty = true
            applyHintsIfPossible(force: false)
        }

        func updateReadingOrder(revision: Int, urls: [URL]) {
            guard lastAppliedReadingOrderRevision != revision else {
                return
            }
            lastAppliedReadingOrderRevision = revision
            currentReadingOrderURLs = normalizedReadingOrderURLs(urls)
            pendingReadingOrderJSON = makeReadingOrderJSON(currentReadingOrderURLs)
            isReadingOrderDirty = true
            applyReadingOrderIfPossible(force: false)
        }

        func applyFindRequestIfNeeded(currentURL: URL) {
            guard let webView, let findRequest else {
                return
            }
            guard lastAppliedFindRequestID != findRequest.id else {
                return
            }
            let script = EPUBFindExecutor.makeScript(
                query: findRequest.query,
                occurrence: findRequest.occurrence
            )
            webView.evaluateJavaScript(script, completionHandler: nil)
            lastAppliedFindRequestID = findRequest.id
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == scriptMessageName else {
                return
            }
            guard let payload = message.body as? [String: Any] else {
                return
            }
            let action = (payload["action"] as? String) ?? "selection"
            let text = (payload["text"] as? String) ?? ""
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if action == "translate" {
                guard !cleaned.isEmpty else {
                    return
                }
                onTranslateRequested(cleaned)
            } else if action == "screenshot" {
                guard let rectPayload = payload["rect"] as? [String: Any],
                      let rect = makeSnapshotRect(from: rectPayload) else {
                    return
                }
                captureScreenshot(rect: rect)
            } else if action == "pageTap" {
                onPageTapped()
            } else {
                onTextSelected(cleaned)
            }
        }

        private func makeSnapshotRect(from payload: [String: Any]) -> CGRect? {
            guard let x = numericValue(payload["x"]),
                  let y = numericValue(payload["y"]),
                  let width = numericValue(payload["width"]),
                  let height = numericValue(payload["height"]) else {
                return nil
            }
            let safeWidth = max(1, width)
            let safeHeight = max(1, height)
            return CGRect(x: x, y: y, width: safeWidth, height: safeHeight)
        }

        private func numericValue(_ value: Any?) -> Double? {
            switch value {
            case let number as NSNumber:
                return number.doubleValue
            case let value as Double:
                return value
            case let value as Int:
                return Double(value)
            default:
                return nil
            }
        }

        private func captureScreenshot(rect: CGRect) {
            guard let webView else {
                return
            }
            // Clear active text selection before snapshot so highlighted selection color is not captured.
            let clearSelectionScript = """
            (() => {
              const selection = window.getSelection();
              if (selection) {
                selection.removeAllRanges();
              }
              return true;
            })();
            """
            webView.evaluateJavaScript(clearSelectionScript) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    let validBounds = webView.bounds.insetBy(dx: 1, dy: 1)
                    var clipped = rect.intersection(validBounds)
                    guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else {
                        return
                    }
                    clipped = clipped.integral
                    let configuration = WKSnapshotConfiguration()
                    configuration.rect = clipped
                    webView.takeSnapshot(with: configuration) { image, _ in
                        guard let image else {
                            return
                        }
                        Task { @MainActor in
                            self.onScreenshotCaptured(image)
                        }
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else {
                return
            }
            lastAppliedFontStyle = nil
            lastAppliedFontSize = nil
            areHintsDirty = true
            isReadingOrderDirty = true
            installBridgeScriptIfNeeded()
            applyFontIfPossible()
            applyHintsIfPossible(force: true)
            applyReadingOrderIfPossible(force: true)
            onLocationChanged(url)
            applyFindRequestIfNeeded(currentURL: url)
        }

        private func installBridgeScriptIfNeeded() {
            guard let webView else { return }
            // WKWebView creates a new JS context on navigation. Re-inject on every page finish.
            webView.evaluateJavaScript(Self.bridgeScript, completionHandler: nil)
        }

        private func applyFontIfPossible() {
            guard let webView else { return }
            if lastAppliedFontStyle == currentFontStyle,
               let lastAppliedFontSize,
               abs(lastAppliedFontSize - currentFontSize) < 0.01 {
                return
            }
            let script = Self.makeApplyFontScript(
                cssFontFamily: currentFontStyle.cssFamily,
                fontSize: Int(currentFontSize.rounded())
            )
            webView.evaluateJavaScript(script, completionHandler: nil)
            lastAppliedFontStyle = currentFontStyle
            lastAppliedFontSize = currentFontSize
        }

        private func applyHintsIfPossible(force: Bool) {
            guard let webView else { return }
            if !force, !areHintsDirty {
                return
            }
            guard let json = pendingHintsJSON ?? makeHintsJSON(currentTranslationHints) else {
                return
            }
            let script = "window.curiousReaderUpdateTranslations(\(json));"
            webView.evaluateJavaScript(script, completionHandler: nil)
            pendingHintsJSON = json
            areHintsDirty = false
        }

        private func applyReadingOrderIfPossible(force: Bool) {
            guard let webView else { return }
            if !force, !isReadingOrderDirty {
                return
            }
            guard let json = pendingReadingOrderJSON ?? makeReadingOrderJSON(currentReadingOrderURLs) else {
                return
            }
            let script = "window.curiousReaderSetReadingOrder(\(json));"
            webView.evaluateJavaScript(script, completionHandler: nil)
            pendingReadingOrderJSON = json
            isReadingOrderDirty = false
        }

        private func normalizedHintMap(_ hints: [String: String]) -> [String: String] {
            var map: [String: String] = [:]
            for (key, value) in hints {
                let normalized = key
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !normalized.isEmpty else {
                    continue
                }
                map[normalized] = value
            }
            return map
        }

        private func makeHintsJSON(_ hints: [String: String]) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: hints),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }

        private func normalizedReadingOrderURLs(_ urls: [URL]) -> [URL] {
            var result: [URL] = []
            var seenPaths: Set<String> = []
            for url in urls {
                let normalized = url.standardizedFileURL.removingFragment()
                let path = normalized.path
                guard !path.isEmpty else {
                    continue
                }
                guard !seenPaths.contains(path) else {
                    continue
                }
                seenPaths.insert(path)
                result.append(normalized)
            }
            return result
        }

        private func makeReadingOrderJSON(_ urls: [URL]) -> String? {
            let list = urls.map(\.absoluteString)
            guard let data = try? JSONSerialization.data(withJSONObject: list),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }

        private static func makeApplyFontScript(cssFontFamily: String, fontSize: Int) -> String {
            let safeFamily = cssFontFamily
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            window.curiousReaderApplyFont("\(safeFamily)", \(fontSize));
            """
        }

        private static let bridgeScript = """
        (() => {
          if (window.__curiousReaderBridgeInstalled) { return; }
          window.__curiousReaderBridgeInstalled = true;

          const normalize = (value) => (value || "")
            .normalize("NFD")
            .replace(/[\\u0300-\\u036f]/g, "")
            .replace(/\\s+/g, " ")
            .trim()
            .toLowerCase();

          window.__curiousReaderTranslations = {};
          window.__curiousReaderTranslationEntries = [];
          window.__curiousReaderReadingOrder = [];
          window.curiousReaderUpdateTranslations = (map) => {
            window.__curiousReaderTranslations = map || {};
            window.__curiousReaderTranslationEntries = Object.entries(window.__curiousReaderTranslations)
              .map(([key, translation]) => ({ key: normalize(key), translation }))
              .filter((entry) => entry.key.length > 1 && !!entry.translation)
              .sort((lhs, rhs) => rhs.key.length - lhs.key.length);
          };
          const normalizeURLWithoutHash = (value) => {
            try {
              const resolved = new URL(value, window.location.href);
              resolved.hash = "";
              return resolved.href;
            } catch (_) {
              return "";
            }
          };
          window.curiousReaderSetReadingOrder = (items) => {
            const list = Array.isArray(items) ? items : [];
            const unique = [];
            const seen = new Set();
            for (const item of list) {
              const normalizedURL = normalizeURLWithoutHash(item);
              if (!normalizedURL || seen.has(normalizedURL)) {
                continue;
              }
              seen.add(normalizedURL);
              unique.push(normalizedURL);
            }
            window.__curiousReaderReadingOrder = unique;
          };

          window.curiousReaderApplyFont = (fontFamily, fontSize) => {
            const styleID = "curious-reader-font-style";
            let styleElement = document.getElementById(styleID);
            if (!styleElement) {
              styleElement = document.createElement("style");
              styleElement.id = styleID;
              document.head.appendChild(styleElement);
            }
            styleElement.textContent = `
              html, body {
                font-family: ${fontFamily} !important;
                font-size: ${fontSize}px !important;
                line-height: 1.75 !important;
                color: #2f291f !important;
                background: #f8f3e8 !important;
              }
              body {
                max-width: 78ch !important;
                margin: 0 auto !important;
                padding: clamp(20px, 4vw, 44px) !important;
                box-sizing: border-box !important;
              }
              img, svg, video, canvas, table, pre {
                max-width: 100% !important;
              }
            `;
          };

          let tooltip;
          let highlightLayer;
          let selectionActionTip;
          let selectionTranslateButton;
          let selectionScreenshotButton;
          let selectionActionState = { text: "" };
          const blockPayloadCache = new WeakMap();
          const hoverState = { signature: "", translation: "" };
          const selectionDispatchState = { lastText: null };
          const autoAdvanceState = {
            lastIntentAt: 0,
            lastTriggerAt: 0,
            lastTriggeredFromURL: ""
          };
          let lastScrollY = window.scrollY || document.documentElement.scrollTop || 0;
          const registerAdvanceIntent = () => {
            autoAdvanceState.lastIntentAt = performance.now();
          };
          const currentLocationURL = () => normalizeURLWithoutHash(window.location.href);
          const findReadingOrderIndex = () => {
            const readingOrder = window.__curiousReaderReadingOrder || [];
            if (!readingOrder.length) {
              return -1;
            }
            const current = currentLocationURL();
            let index = readingOrder.indexOf(current);
            if (index >= 0) {
              return index;
            }
            let currentPath = "";
            try {
              currentPath = new URL(current).pathname;
            } catch (_) {
              currentPath = "";
            }
            if (!currentPath) {
              return -1;
            }
            index = readingOrder.findIndex((item) => {
              try {
                return new URL(item).pathname === currentPath;
              } catch (_) {
                return false;
              }
            });
            return index;
          };
          const maybeAutoAdvanceToNextChapter = () => {
            const now = performance.now();
            if (now - autoAdvanceState.lastIntentAt > 900) {
              return;
            }
            if (now - autoAdvanceState.lastTriggerAt < 1200) {
              return;
            }
            const scrollingElement = document.scrollingElement || document.documentElement || document.body;
            if (!scrollingElement) {
              return;
            }
            const scrollTop = scrollingElement.scrollTop || window.scrollY || 0;
            const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
            const documentHeight = Math.max(
              scrollingElement.scrollHeight || 0,
              document.body?.scrollHeight || 0,
              document.documentElement?.scrollHeight || 0
            );
            if (documentHeight <= 0 || viewportHeight <= 0) {
              return;
            }
            const threshold = Math.max(88, Math.round(viewportHeight * 0.06));
            const nearBottom = scrollTop + viewportHeight >= documentHeight - threshold;
            if (!nearBottom) {
              return;
            }
            const index = findReadingOrderIndex();
            if (index < 0) {
              return;
            }
            const readingOrder = window.__curiousReaderReadingOrder || [];
            const nextURL = readingOrder[index + 1];
            if (!nextURL) {
              return;
            }
            const current = currentLocationURL();
            if (autoAdvanceState.lastTriggeredFromURL === current && now - autoAdvanceState.lastTriggerAt < 5000) {
              return;
            }
            autoAdvanceState.lastTriggeredFromURL = current;
            autoAdvanceState.lastTriggerAt = now;
            window.location.href = nextURL;
          };
          const ensureTooltip = () => {
            if (tooltip) { return tooltip; }
            tooltip = document.createElement("div");
            tooltip.style.position = "absolute";
            tooltip.style.display = "none";
            tooltip.style.maxWidth = "320px";
            tooltip.style.padding = "8px 10px";
            tooltip.style.borderRadius = "9px";
            tooltip.style.border = "1px solid rgba(0,0,0,0.14)";
            tooltip.style.background = "rgba(255,255,255,0.98)";
            tooltip.style.color = "rgba(18,18,18,0.95)";
            tooltip.style.fontSize = "12px";
            tooltip.style.lineHeight = "1.35";
            tooltip.style.zIndex = "2147483000";
            tooltip.style.pointerEvents = "none";
            document.body.appendChild(tooltip);
            return tooltip;
          };

          const ensureHighlightLayer = () => {
            if (highlightLayer) { return highlightLayer; }
            highlightLayer = document.createElement("div");
            highlightLayer.style.position = "absolute";
            highlightLayer.style.left = "0";
            highlightLayer.style.top = "0";
            highlightLayer.style.width = "0";
            highlightLayer.style.height = "0";
            highlightLayer.style.pointerEvents = "none";
            highlightLayer.style.zIndex = "2147482999";
            document.body.appendChild(highlightLayer);
            return highlightLayer;
          };

          const ensureSelectionActionTip = () => {
            if (selectionActionTip) { return selectionActionTip; }
            selectionActionTip = document.createElement("div");
            selectionActionTip.style.position = "absolute";
            selectionActionTip.style.display = "none";
            selectionActionTip.style.zIndex = "2147483001";
            selectionActionTip.style.pointerEvents = "auto";
            selectionActionTip.style.padding = "4px";
            selectionActionTip.style.borderRadius = "10px";
            selectionActionTip.style.background = "rgba(255,255,255,0.96)";
            selectionActionTip.style.border = "1px solid rgba(0,0,0,0.14)";
            selectionActionTip.style.boxShadow = "0 6px 18px rgba(0,0,0,0.18)";
            const buttonStack = document.createElement("div");
            buttonStack.style.display = "flex";
            buttonStack.style.flexDirection = "column";
            buttonStack.style.gap = "4px";
            selectionTranslateButton = document.createElement("button");
            selectionTranslateButton.type = "button";
            selectionTranslateButton.textContent = "翻译";
            selectionTranslateButton.style.border = "none";
            selectionTranslateButton.style.background = "rgba(0,122,255,0.13)";
            selectionTranslateButton.style.color = "rgba(0,122,255,0.98)";
            selectionTranslateButton.style.borderRadius = "8px";
            selectionTranslateButton.style.padding = "4px 10px";
            selectionTranslateButton.style.fontSize = "12px";
            selectionTranslateButton.style.fontWeight = "600";
            selectionTranslateButton.style.cursor = "pointer";
            selectionScreenshotButton = document.createElement("button");
            selectionScreenshotButton.type = "button";
            selectionScreenshotButton.textContent = "截图";
            selectionScreenshotButton.style.border = "none";
            selectionScreenshotButton.style.background = "rgba(120,82,34,0.12)";
            selectionScreenshotButton.style.color = "rgba(91,63,29,0.96)";
            selectionScreenshotButton.style.borderRadius = "8px";
            selectionScreenshotButton.style.padding = "4px 10px";
            selectionScreenshotButton.style.fontSize = "12px";
            selectionScreenshotButton.style.fontWeight = "600";
            selectionScreenshotButton.style.cursor = "pointer";

            const currentSelectionSnapshotRect = () => {
              const selection = window.getSelection();
              if (!selection || selection.rangeCount === 0) {
                return null;
              }
              const rect = selection.getRangeAt(0).getBoundingClientRect();
              if (!rect || rect.width <= 0 || rect.height <= 0) {
                return null;
              }
              return {
                x: rect.left - 8,
                y: rect.top - 8,
                width: rect.width + 16,
                height: rect.height + 16
              };
            };
            const triggerTranslateFromActionTip = () => {
              const text = (selectionActionState.text || "")
                .replace(/\\s+/g, " ")
                .trim();
              if (!text) { return; }
              window.webkit.messageHandlers.curiousReaderSelection.postMessage({
                action: "translate",
                text
              });
              hideSelectionActionTip();
            };
            const triggerScreenshotFromActionTip = () => {
              const rect = currentSelectionSnapshotRect();
              if (!rect) {
                return;
              }
              hideSelectionActionTip();
              const selection = window.getSelection();
              if (selection) {
                selection.removeAllRanges();
              }
              window.setTimeout(() => {
                window.webkit.messageHandlers.curiousReaderSelection.postMessage({
                  action: "screenshot",
                  rect
                });
              }, 24);
            };
            selectionTranslateButton.addEventListener("mousedown", (event) => {
              event.preventDefault();
              event.stopPropagation();
            });
            selectionTranslateButton.addEventListener("mouseup", (event) => {
              event.preventDefault();
              event.stopPropagation();
              triggerTranslateFromActionTip();
            });
            selectionTranslateButton.addEventListener("click", (event) => {
              event.preventDefault();
              event.stopPropagation();
              triggerTranslateFromActionTip();
            });
            selectionScreenshotButton.addEventListener("mousedown", (event) => {
              event.preventDefault();
              event.stopPropagation();
            });
            selectionScreenshotButton.addEventListener("mouseup", (event) => {
              event.preventDefault();
              event.stopPropagation();
              triggerScreenshotFromActionTip();
            });
            selectionScreenshotButton.addEventListener("click", (event) => {
              event.preventDefault();
              event.stopPropagation();
              triggerScreenshotFromActionTip();
            });
            buttonStack.appendChild(selectionTranslateButton);
            buttonStack.appendChild(selectionScreenshotButton);
            selectionActionTip.appendChild(buttonStack);
            document.body.appendChild(selectionActionTip);
            return selectionActionTip;
          };

          const hideSelectionActionTip = () => {
            selectionActionState.text = "";
            if (selectionActionTip) {
              selectionActionTip.style.display = "none";
            }
          };

          const showSelectionActionTip = () => {
            const selectedText = (window.getSelection()?.toString() || "")
              .replace(/\\s+/g, " ")
              .trim();
            if (!selectedText || selectedText.length > 50000) {
              hideSelectionActionTip();
              return;
            }
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) {
              hideSelectionActionTip();
              return;
            }
            const rect = selection.getRangeAt(0).getBoundingClientRect();
            if (!rect || (rect.width <= 0 && rect.height <= 0)) {
              hideSelectionActionTip();
              return;
            }
            selectionActionState.text = selectedText;
            const tip = ensureSelectionActionTip();
            tip.style.display = "block";
            const viewportMargin = 12;
            const gap = 8;
            const minLeft = window.scrollX + viewportMargin;
            const maxLeft = window.scrollX + window.innerWidth - tip.offsetWidth - viewportMargin;
            const preferredLeft = rect.right + window.scrollX + gap;
            let resolvedLeft = Math.min(Math.max(preferredLeft, minLeft), Math.max(minLeft, maxLeft));
            const minTop = window.scrollY + viewportMargin;
            const maxTop = window.scrollY + window.innerHeight - tip.offsetHeight - viewportMargin;
            const belowTop = rect.bottom + window.scrollY + 6;
            const aboveTop = rect.top + window.scrollY - tip.offsetHeight - 6;
            let resolvedTop = belowTop;
            if (resolvedTop > maxTop && aboveTop >= minTop) {
              resolvedTop = aboveTop;
            }
            resolvedTop = Math.min(Math.max(resolvedTop, minTop), Math.max(minTop, maxTop));
            tip.style.left = `${resolvedLeft}px`;
            tip.style.top = `${resolvedTop}px`;
            tip.style.display = "block";
          };

          const notifySelectionToNative = (text) => {
            const normalizedText = (text || "").replace(/\\s+/g, " ").trim();
            if (selectionDispatchState.lastText === normalizedText) {
              return;
            }
            selectionDispatchState.lastText = normalizedText;
            window.webkit.messageHandlers.curiousReaderSelection.postMessage({
              action: "selection",
              text: normalizedText
            });
          };

          const clearHighlight = () => {
            if (!highlightLayer) { return; }
            highlightLayer.replaceChildren();
          };

          const hideTooltip = () => {
            if (tooltip) {
              tooltip.style.display = "none";
            }
            hoverState.signature = "";
            hoverState.translation = "";
            clearHighlight();
          };

          const rangeAtPoint = (x, y) => {
            let caretRange = null;
            if (document.caretRangeFromPoint) {
              caretRange = document.caretRangeFromPoint(x, y);
            } else if (document.caretPositionFromPoint) {
              const position = document.caretPositionFromPoint(x, y);
              if (position) {
                caretRange = document.createRange();
                caretRange.setStart(position.offsetNode, position.offset);
                caretRange.setEnd(position.offsetNode, position.offset);
              }
            }
            return caretRange;
          };

          const findReadableBlock = (node) => {
            const readableTags = new Set(["P", "LI", "DIV", "SECTION", "ARTICLE", "TD", "TH", "BLOCKQUOTE", "DD", "DT", "H1", "H2", "H3", "H4", "H5", "H6"]);
            let current = node && node.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
            while (current && current !== document.body) {
              if (readableTags.has(current.tagName)) {
                return current;
              }
              current = current.parentElement;
            }
            return null;
          };

          const collectTextNodes = (root) => {
            const walker = document.createTreeWalker(
              root,
              NodeFilter.SHOW_TEXT,
              {
                acceptNode(node) {
                  if (!node.nodeValue || !node.nodeValue.trim()) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  const parent = node.parentElement;
                  if (!parent) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  if (["SCRIPT", "STYLE", "NOSCRIPT"].includes(parent.tagName)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return NodeFilter.FILTER_ACCEPT;
                }
              }
            );
            const nodes = [];
            while (true) {
              const next = walker.nextNode();
              if (!next) { break; }
              nodes.push(next);
            }
            return nodes;
          };

          const normalizeWithMap = (rawText) => {
            let normalized = "";
            const map = [];
            let previousWasSpace = true;
            for (let index = 0; index < rawText.length; index += 1) {
              const char = rawText[index];
              if (/\\s/.test(char)) {
                if (previousWasSpace) {
                  continue;
                }
                normalized += " ";
                map.push(index);
                previousWasSpace = true;
                continue;
              }
              const folded = char.normalize("NFD").replace(/[\\u0300-\\u036f]/g, "");
              const lowered = folded.toLowerCase();
              for (const codeUnit of lowered) {
                normalized += codeUnit;
                map.push(index);
              }
              previousWasSpace = false;
            }
            while (normalized.endsWith(" ")) {
              normalized = normalized.slice(0, -1);
              map.pop();
            }
            return { normalized, map };
          };

          const payloadForBlock = (block) => {
            const cached = blockPayloadCache.get(block);
            if (cached) {
              return cached;
            }
            const textNodes = collectTextNodes(block);
            if (!textNodes.length) {
              return null;
            }
            const rawText = textNodes.map((node) => node.nodeValue || "").join("");
            if (!rawText.trim()) {
              return null;
            }
            const normalizedPayload = normalizeWithMap(rawText);
            if (!normalizedPayload.normalized || !normalizedPayload.map.length) {
              return null;
            }
            const payload = { textNodes, normalizedPayload };
            blockPayloadCache.set(block, payload);
            return payload;
          };

          const locateOffsetInNodes = (nodes, targetOffset) => {
            let remaining = Math.max(0, targetOffset);
            for (const node of nodes) {
              const length = (node.nodeValue || "").length;
              if (remaining <= length) {
                return { node, offset: remaining };
              }
              remaining -= length;
            }
            const fallback = nodes[nodes.length - 1];
            if (!fallback) { return null; }
            return { node: fallback, offset: (fallback.nodeValue || "").length };
          };

          const rawOffsetToNormalizedOffset = (rawOffset, map) => {
            let normalizedOffset = 0;
            while (normalizedOffset < map.length && map[normalizedOffset] < rawOffset) {
              normalizedOffset += 1;
            }
            return normalizedOffset;
          };

          const isPointInRangeRects = (range, x, y, tolerance = 2) => {
            const rects = Array.from(range.getClientRects());
            if (!rects.length) {
              return false;
            }
            return rects.some((rect) =>
              x >= rect.left - tolerance &&
              x <= rect.right + tolerance &&
              y >= rect.top - tolerance &&
              y <= rect.bottom + tolerance
            );
          };

          const matchTranslationAtPoint = (x, y) => {
            if (!window.__curiousReaderTranslationEntries.length) {
              return null;
            }
            const hoveredElement = document.elementFromPoint(x, y);
            if (!hoveredElement) {
              return null;
            }
            const block = findReadableBlock(hoveredElement);
            if (!block) {
              return null;
            }
            const normalizedBlockText = normalize(block.innerText || block.textContent || "");
            if (normalizedBlockText.length > 1) {
              const exactBlockMatch = window.__curiousReaderTranslationEntries.find(
                (entry) => entry.key === normalizedBlockText
              );
              if (exactBlockMatch) {
                const fullRange = document.createRange();
                fullRange.selectNodeContents(block);
                if (!isPointInRangeRects(fullRange, x, y)) {
                  return null;
                }
                return {
                  range: fullRange,
                  translation: exactBlockMatch.translation,
                  signature: `block:${exactBlockMatch.key}`
                };
              }
            }
            const caretRange = rangeAtPoint(x, y);
            if (!caretRange || !caretRange.startContainer || !block.contains(caretRange.startContainer)) {
              return null;
            }
            const payload = payloadForBlock(block);
            if (!payload) {
              return null;
            }
            const { textNodes, normalizedPayload } = payload;

            let caretRawOffset = 0;
            try {
              const progressRange = document.createRange();
              progressRange.setStart(block, 0);
              progressRange.setEnd(caretRange.startContainer, caretRange.startOffset);
              caretRawOffset = progressRange.toString().length;
            } catch (_) {
              return null;
            }

            const caretNormalizedOffset = rawOffsetToNormalizedOffset(caretRawOffset, normalizedPayload.map);
            let bestMatch = null;
            for (const entry of window.__curiousReaderTranslationEntries) {
              let searchFrom = 0;
              while (searchFrom < normalizedPayload.normalized.length) {
                const foundAt = normalizedPayload.normalized.indexOf(entry.key, searchFrom);
                if (foundAt < 0) {
                  break;
                }
                const foundEnd = foundAt + entry.key.length;
                if (caretNormalizedOffset >= foundAt && caretNormalizedOffset <= foundEnd) {
                  if (!bestMatch || entry.key.length > bestMatch.key.length) {
                    bestMatch = {
                      key: entry.key,
                      translation: entry.translation,
                      normalizedStart: foundAt,
                      normalizedEnd: foundEnd
                    };
                  }
                }
                searchFrom = foundAt + 1;
              }
            }

            if (!bestMatch) {
              return null;
            }
            const rawStart = normalizedPayload.map[bestMatch.normalizedStart];
            const rawEnd = (normalizedPayload.map[bestMatch.normalizedEnd - 1] ?? rawStart) + 1;
            if (rawStart == null || rawEnd <= rawStart) {
              return null;
            }

            const startLocation = locateOffsetInNodes(textNodes, rawStart);
            const endLocation = locateOffsetInNodes(textNodes, rawEnd);
            if (!startLocation || !endLocation) {
              return null;
            }

            const range = document.createRange();
            range.setStart(startLocation.node, startLocation.offset);
            range.setEnd(endLocation.node, endLocation.offset);
            if (!isPointInRangeRects(range, x, y)) {
              return null;
            }
            return {
              range,
              translation: bestMatch.translation,
              signature: `${bestMatch.key}:${rawStart}:${rawEnd}`
            };
          };

          const renderHighlight = (range) => {
            clearHighlight();
            const layer = ensureHighlightLayer();
            for (const rect of range.getClientRects()) {
              if (rect.width < 1 || rect.height < 1) {
                continue;
              }
              const marker = document.createElement("div");
              marker.style.position = "absolute";
              marker.style.left = `${rect.left + window.scrollX}px`;
              marker.style.top = `${rect.top + window.scrollY}px`;
              marker.style.width = `${rect.width}px`;
              marker.style.height = `${rect.height}px`;
              marker.style.borderRadius = "4px";
              marker.style.background = "rgba(255, 214, 10, 0.28)";
              marker.style.boxShadow = "inset 0 0 0 1px rgba(255, 171, 0, 0.35)";
              layer.appendChild(marker);
            }
          };

          const positionTooltipForRange = (panel, range) => {
            const anchorRect = range.getBoundingClientRect();
            if (!anchorRect) {
              return;
            }
            panel.style.display = "block";
            const viewportMargin = 12;
            const gap = 8;
            const minLeft = window.scrollX + viewportMargin;
            const maxLeft = window.scrollX + window.innerWidth - panel.offsetWidth - viewportMargin;
            const preferredLeft = anchorRect.left + window.scrollX;
            let resolvedLeft = Math.min(Math.max(preferredLeft, minLeft), Math.max(minLeft, maxLeft));

            const minTop = window.scrollY + viewportMargin;
            const maxTop = window.scrollY + window.innerHeight - panel.offsetHeight - viewportMargin;
            const belowTop = anchorRect.bottom + window.scrollY + gap;
            const aboveTop = anchorRect.top + window.scrollY - panel.offsetHeight - gap;
            let resolvedTop = belowTop;
            if (resolvedTop > maxTop && aboveTop >= minTop) {
              resolvedTop = aboveTop;
            }
            resolvedTop = Math.min(Math.max(resolvedTop, minTop), Math.max(minTop, maxTop));

            panel.style.left = `${resolvedLeft}px`;
            panel.style.top = `${resolvedTop}px`;
          };

          document.addEventListener("mouseup", (event) => {
            if (
              selectionActionTip &&
              event &&
              event.target instanceof Node &&
              selectionActionTip.contains(event.target)
            ) {
              return;
            }
            const selected = (window.getSelection()?.toString() || "")
              .replace(/\\s+/g, " ")
              .trim();
            if (!selected || selected.length > 50000) {
              notifySelectionToNative("");
              return;
            }
            showSelectionActionTip();
            notifySelectionToNative(selected);
          });

          let hoverFrame = null;
          document.addEventListener("mousemove", (event) => {
            if (hoverFrame) {
              cancelAnimationFrame(hoverFrame);
            }
            const { clientX, clientY } = event;
            hoverFrame = requestAnimationFrame(() => {
              const match = matchTranslationAtPoint(clientX, clientY);
              if (!match) {
                hideTooltip();
                return;
              }
              const panel = ensureTooltip();
              if (hoverState.signature !== match.signature) {
                renderHighlight(match.range);
                hoverState.signature = match.signature;
              }
              if (hoverState.translation !== match.translation) {
                panel.textContent = match.translation;
                hoverState.translation = match.translation;
              }
              positionTooltipForRange(panel, match.range);
            });
          });

          const dismissHover = () => {
            if (hoverFrame) {
              cancelAnimationFrame(hoverFrame);
              hoverFrame = null;
            }
            hideTooltip();
          };

          document.addEventListener("selectionchange", () => {
            const selected = (window.getSelection()?.toString() || "")
              .replace(/\\s+/g, " ")
              .trim();
            if (!selected) {
              notifySelectionToNative("");
              return;
            }
            selectionActionState.text = selected;
            showSelectionActionTip();
          });

          document.addEventListener("mousedown", (event) => {
            if (
              selectionActionTip &&
              event &&
              event.target instanceof Node &&
              selectionActionTip.contains(event.target)
            ) {
              return;
            }
            window.webkit.messageHandlers.curiousReaderSelection.postMessage({
              action: "pageTap"
            });
            const selected = (window.getSelection()?.toString() || "")
              .replace(/\\s+/g, " ")
              .trim();
            if (!selected) {
              hideSelectionActionTip();
            }
          }, true);

          document.addEventListener("wheel", (event) => {
            if ((event.deltaY || 0) > 0) {
              registerAdvanceIntent();
            }
          }, { passive: true });
          document.addEventListener("keydown", (event) => {
            if (["ArrowDown", "PageDown", " ", "Spacebar"].includes(event.key)) {
              registerAdvanceIntent();
            }
          }, true);

          let autoAdvanceFrame = null;
          const onScroll = () => {
            const currentY = window.scrollY || document.documentElement.scrollTop || 0;
            if (currentY > lastScrollY + 0.5) {
              registerAdvanceIntent();
            }
            lastScrollY = currentY;
            dismissHover();
            if (autoAdvanceFrame) {
              cancelAnimationFrame(autoAdvanceFrame);
            }
            autoAdvanceFrame = requestAnimationFrame(() => {
              autoAdvanceFrame = null;
              maybeAutoAdvanceToNextChapter();
            });
          };

          document.addEventListener("mouseleave", dismissHover, true);
          document.addEventListener("scroll", onScroll, true);
          window.addEventListener("blur", dismissHover);
          window.addEventListener("resize", dismissHover);
        })();
        """
    }
}
