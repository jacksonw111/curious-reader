import Foundation
@testable import CuriousReaderApp
import XCTest

final class ReaderAIAndPreferencesTests: XCTestCase {
    func testPreferencesStoreReturnsDefaultWhenFileMissing() async throws {
        let fileURL = makeTempFileURL(name: "preferences.json")
        let store = ReaderPreferencesStore(storageFileURL: fileURL)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, .default)
    }

    func testPreferencesStoreSaveAndLoadRoundTrip() async throws {
        let fileURL = makeTempFileURL(name: "preferences.json")
        let store = ReaderPreferencesStore(storageFileURL: fileURL)
        let expected = ReaderPreferences(epubFontStyle: .pingFangSC, epubFontSize: 24)

        try await store.save(expected)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, expected)
    }

    func testPreferencesStoreBackfillsMissingKeys() async throws {
        let fileURL = makeTempFileURL(name: "preferences.json")
        try Data("{}".utf8).write(to: fileURL)
        let store = ReaderPreferencesStore(storageFileURL: fileURL)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, .default)
    }

    func testTranslationMemoryStoreSaveAndLoadRoundTrip() async throws {
        let fileURL = makeTempFileURL(name: "translation-memory.json")
        let store = TranslationMemoryStore(storageFileURL: fileURL)
        let id = UUID()
        let expected = [id: ["hello world": "你好，世界"]]

        try await store.save(expected)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, expected)
    }

    func testTranslationMemoryStoreIgnoresInvalidBookID() async throws {
        let fileURL = makeTempFileURL(name: "translation-memory.json")
        let validID = UUID()
        let payload = """
        {
          "INVALID-ID": { "hello": "你好" },
          "\(validID.uuidString)": { "world": "世界" }
        }
        """
        try Data(payload.utf8).write(to: fileURL)
        let store = TranslationMemoryStore(storageFileURL: fileURL)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[validID], ["world": "世界"])
    }

    func testOpenRouterClientStreamsTranslationAndUsesFreeModel() async throws {
        let session = makeStubbedSession()
        let bodyBox = ThreadSafeDataBox()
        URLProtocolStub.configure { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/models" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data("""
                    {
                      "data": [
                        { "id": "z-paid", "pricing": { "prompt": "0.001", "completion": "0.001" } },
                        { "id": "a-free-model:free", "pricing": { "prompt": "0", "completion": "0" } }
                      ]
                    }
                    """.utf8)
                )
            }
            if path == "/api/v1/chat/completions" {
                bodyBox.set(Self.requestBodyData(from: request))
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!,
                    Data("""
                    data: {"choices":[{"delta":{"content":"你好"}}]}
                    data: {"choices":[{"delta":{"content":"，世界"}}]}
                    data: [DONE]

                    """.utf8)
                )
            }
            throw URLError(.badURL)
        }

        let client = OpenRouterClient(session: session)
        let tokenCollector = TokenCollector()
        let output = try await client.streamTranslation(
            text: "hello world",
            apiKey: "sk-test"
        ) { token in
            await tokenCollector.append(token)
        }
        let streamed = await tokenCollector.tokens

        XCTAssertEqual(output, "你好，世界")
        XCTAssertEqual(streamed.joined(), "你好，世界")
        let requests = URLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/models" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/chat/completions" }.count, 1)
        let body = try XCTUnwrap(bodyBox.get())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "a-free-model:free")
    }

    func testOpenRouterClientCachesResolvedModel() async throws {
        let session = makeStubbedSession()
        URLProtocolStub.configure { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/models" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("""
                    { "data": [ { "id": "cached-free:free", "pricing": { "prompt": "0", "completion": "0" } } ] }
                    """.utf8)
                )
            }
            if path == "/api/v1/chat/completions" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("""
                    data: {"choices":[{"delta":{"content":"A"}}]}
                    data: [DONE]

                    """.utf8)
                )
            }
            throw URLError(.badServerResponse)
        }

        let client = OpenRouterClient(session: session)
        _ = try await client.streamTranslation(text: "first", apiKey: "sk-test") { _ in }
        _ = try await client.streamTranslation(text: "second", apiKey: "sk-test") { _ in }

        let requests = URLProtocolStub.capturedRequests()
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/models" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/api/v1/chat/completions" }.count, 2)
    }

    func testOpenRouterClientFailsWhenNoFreeModelExists() async throws {
        let session = makeStubbedSession()
        URLProtocolStub.configure { request in
            if request.url?.path == "/api/v1/models" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("""
                    { "data": [ { "id": "paid-model", "pricing": { "prompt": "0.001", "completion": "0.001" } } ] }
                    """.utf8)
                )
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = OpenRouterClient(session: session)
        do {
            _ = try await client.streamTranslation(text: "hello", apiKey: "sk-test") { _ in }
            XCTFail("Expected missing free-model error")
        } catch let error as TranslationServiceError {
            guard case .remoteError(let message) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(message.contains("No free OpenRouter model"))
        }
    }

    private func makeTempFileURL(name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(name)
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var collected = Data()
        let chunkSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: chunkSize)
            if read > 0 {
                collected.append(buffer, count: read)
            } else {
                break
            }
        }
        return collected.isEmpty ? nil : collected
    }
}

private final class URLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func configure(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        self.requests = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        let value = requests
        lock.unlock()
        return value
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor TokenCollector {
    private(set) var tokens: [String] = []

    func append(_ token: String) {
        tokens.append(token)
    }
}

private final class ThreadSafeDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func set(_ data: Data?) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }
}
