import Foundation
import Security

enum ReaderFontStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemSans
    case roundedSans
    case pingFangSC
    case helveticaNeue

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemSans:
            return "SF Pro"
        case .roundedSans:
            return "SF Rounded"
        case .pingFangSC:
            return "PingFang SC"
        case .helveticaNeue:
            return "Helvetica Neue"
        }
    }

    var cssFamily: String {
        switch self {
        case .systemSans:
            return "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case .roundedSans:
            return "\"SF Pro Rounded\", -apple-system, \"Helvetica Neue\", sans-serif"
        case .pingFangSC:
            return "\"PingFang SC\", -apple-system, \"Helvetica Neue\", sans-serif"
        case .helveticaNeue:
            return "\"Helvetica Neue\", -apple-system, sans-serif"
        }
    }
}

struct ReaderPreferences: Codable, Equatable, Sendable {
    struct AutoImportDirectory: Codable, Equatable, Sendable, Identifiable {
        var path: String
        var bookmarkData: Data?

        var id: String { path }
    }

    var epubFontStyle: ReaderFontStyle
    var epubFontSize: Double
    var autoImportDirectories: [AutoImportDirectory]

    static let `default` = ReaderPreferences(
        epubFontStyle: .systemSans,
        epubFontSize: 19,
        autoImportDirectories: []
    )

    private enum CodingKeys: String, CodingKey {
        case epubFontStyle
        case epubFontSize
        case autoImportDirectories
        // Legacy single-directory keys (kept for backward compatibility).
        case autoImportDirectoryPath
        case autoImportDirectoryBookmarkData
    }

    init(
        epubFontStyle: ReaderFontStyle,
        epubFontSize: Double,
        autoImportDirectories: [AutoImportDirectory] = []
    ) {
        self.epubFontStyle = epubFontStyle
        self.epubFontSize = epubFontSize
        self.autoImportDirectories = autoImportDirectories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        epubFontStyle = try container.decodeIfPresent(ReaderFontStyle.self, forKey: .epubFontStyle) ?? .systemSans
        epubFontSize = try container.decodeIfPresent(Double.self, forKey: .epubFontSize) ?? 19
        if let directories = try container.decodeIfPresent([AutoImportDirectory].self, forKey: .autoImportDirectories) {
            autoImportDirectories = directories
        } else {
            let legacyPath = try container.decodeIfPresent(String.self, forKey: .autoImportDirectoryPath)
            let legacyBookmark = try container.decodeIfPresent(Data.self, forKey: .autoImportDirectoryBookmarkData)
            if let legacyPath, !legacyPath.isEmpty {
                autoImportDirectories = [
                    AutoImportDirectory(path: legacyPath, bookmarkData: legacyBookmark),
                ]
            } else {
                autoImportDirectories = []
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(epubFontStyle, forKey: .epubFontStyle)
        try container.encode(epubFontSize, forKey: .epubFontSize)
        try container.encode(autoImportDirectories, forKey: .autoImportDirectories)
    }
}

struct TranslationPanelState: Equatable, Sendable {
    let sourceText: String
    var translatedText: String
    var isStreaming: Bool
    var isCached: Bool
    var errorMessage: String?
}

actor ReaderPreferencesStore {
    private let fileManager: FileManager
    private let storageFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        storageFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let storageFileURL {
            self.storageFileURL = storageFileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
            self.storageFileURL = appSupport
                .appendingPathComponent("CuriousReader", isDirectory: true)
                .appendingPathComponent("preferences.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> ReaderPreferences {
        guard fileManager.fileExists(atPath: storageFileURL.path) else {
            return .default
        }
        let data = try Data(contentsOf: storageFileURL)
        return try decoder.decode(ReaderPreferences.self, from: data)
    }

    func save(_ preferences: ReaderPreferences) throws {
        let parent = storageFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(preferences)
        try data.write(to: storageFileURL, options: .atomic)
    }
}

actor TranslationMemoryStore {
    private let fileManager: FileManager
    private let storageFileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        storageFileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let storageFileURL {
            self.storageFileURL = storageFileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.homeDirectoryForCurrentUser
            self.storageFileURL = appSupport
                .appendingPathComponent("CuriousReader", isDirectory: true)
                .appendingPathComponent("translation-memory.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> [UUID: [String: String]] {
        guard fileManager.fileExists(atPath: storageFileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: storageFileURL)
        let payload = try decoder.decode([String: [String: String]].self, from: data)
        var resolved: [UUID: [String: String]] = [:]
        for (bookIDString, map) in payload {
            guard let bookID = UUID(uuidString: bookIDString) else { continue }
            resolved[bookID] = map
        }
        return resolved
    }

    func save(_ memory: [UUID: [String: String]]) throws {
        let parent = storageFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        var payload: [String: [String: String]] = [:]
        for (bookID, map) in memory {
            payload[bookID.uuidString] = map
        }
        let data = try encoder.encode(payload)
        try data.write(to: storageFileURL, options: .atomic)
    }
}

actor OpenRouterClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")
    private let modelsEndpoint = URL(string: "https://openrouter.ai/api/v1/models")
    private var cachedFreeModelID: String?
    private var cacheResolvedAt: Date?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamTranslation(
        text: String,
        apiKey: String,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws -> String {
        guard let endpoint else {
            throw TranslationServiceError.invalidConfiguration
        }
        let model = try await resolveFreeModel(apiKey: apiKey)
        let requestBody = OpenRouterRequest(
            model: model,
            stream: true,
            max_tokens: 4096,
            messages: [
                .init(
                    role: "system",
                    content: "You are a precise translator. Translate the full user text into Simplified Chinese. Do not omit any sentence. Preserve paragraph structure."
                ),
                .init(role: "user", content: text),
            ]
        )
        let encodedBody = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = encodedBody
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CuriousReader", forHTTPHeaderField: "X-Title")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.remoteError(
                "OpenRouter request failed with status \(httpResponse.statusCode)."
            )
        }

        var finalText = ""
        for try await rawLine in bytes.lines {
            guard rawLine.hasPrefix("data:") else { continue }
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { continue }
            if payload == "[DONE]" {
                break
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: data),
                  let token = chunk.choices.first?.delta.content,
                  !token.isEmpty else {
                continue
            }
            finalText += token
            await onToken(token)
        }
        return finalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveFreeModel(apiKey: String) async throws -> String {
        if let cachedFreeModelID,
           let cacheResolvedAt,
           abs(cacheResolvedAt.timeIntervalSinceNow) < 3600 {
            return cachedFreeModelID
        }
        guard let modelsEndpoint else {
            throw TranslationServiceError.invalidConfiguration
        }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CuriousReader", forHTTPHeaderField: "X-Title")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TranslationServiceError.remoteError("Failed to load OpenRouter model list.")
        }

        let payload = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        let freeCandidates = payload.data
            .filter { model in
                let normalizedID = model.id.lowercased()
                if normalizedID.contains(":free") {
                    return true
                }
                if let prompt = model.pricing?.prompt, let completion = model.pricing?.completion {
                    return isZeroCost(prompt) && isZeroCost(completion)
                }
                return false
            }
            .map(\.id)
            .sorted()

        guard let selected = freeCandidates.first else {
            throw TranslationServiceError.remoteError("No free OpenRouter model available for this key.")
        }
        cachedFreeModelID = selected
        cacheResolvedAt = Date()
        return selected
    }

    private func isZeroCost(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: normalized) else {
            return false
        }
        return decimal == 0
    }
}

enum TranslationServiceError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case remoteError(String)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "OpenRouter configuration is invalid."
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .remoteError(let message):
            return message
        case .missingAPIKey:
            return "Please set your OpenRouter API key in Settings."
        }
    }
}

struct OpenRouterKeychainStore {
    private static let service = "com.curious-reader.openrouter"
    private static let account = "api-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let apiKey = String(data: data, encoding: .utf8),
              !apiKey.isEmpty else {
            return nil
        }
        return apiKey
    }

    static func save(_ apiKey: String) -> Bool {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct OpenRouterRequest: Codable {
    let model: String
    let stream: Bool
    let max_tokens: Int
    let messages: [OpenRouterMessage]
}

private struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

private struct OpenRouterStreamChunk: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
    }

    struct Delta: Codable {
        let content: String?
    }
}

private struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Codable {
    let id: String
    let pricing: OpenRouterModelPricing?
}

private struct OpenRouterModelPricing: Codable {
    let prompt: String?
    let completion: String?
}
