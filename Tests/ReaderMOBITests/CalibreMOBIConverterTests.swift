import Foundation
import ReaderCore
@testable import ReaderMOBI
import XCTest

final class CalibreMOBIConverterTests: XCTestCase {
    func testThrowsWhenBinaryIsUnavailable() throws {
        let fixture = try makeTempMOBIFile()
        let converter = CalibreMOBIConverter(
            cacheRootURL: fixture.dir.appendingPathComponent("cache", isDirectory: true),
            commandRunner: StubCommandRunner(),
            binaryResolver: StubBinaryResolver(path: nil)
        )

        XCTAssertThrowsError(try converter.convertToEPUB(mobiURL: fixture.fileURL)) { error in
            XCTAssertEqual(error as? ReaderError, .conversionUnavailable(fixture.fileURL))
        }
    }

    func testReturnsCachedResultWithoutRunningCommand() throws {
        let fixture = try makeTempMOBIFile()
        let runner = StubCommandRunner()
        let converter = CalibreMOBIConverter(
            cacheRootURL: fixture.dir.appendingPathComponent("cache", isDirectory: true),
            commandRunner: runner,
            binaryResolver: StubBinaryResolver(path: "/usr/local/bin/ebook-convert")
        )

        let cachedURL = try converter.cachedOutputURL(for: fixture.fileURL)
        try FileManager.default.createDirectory(
            at: cachedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cached epub".utf8).write(to: cachedURL)

        let result = try converter.convertToEPUB(mobiURL: fixture.fileURL)
        XCTAssertEqual(result.path, cachedURL.path)
        XCTAssertEqual(runner.invocations, 0)
    }

    func testRunsConversionCommandAndWritesOutput() throws {
        let fixture = try makeTempMOBIFile()
        let runner = StubCommandRunner { _, arguments in
            let output = URL(fileURLWithPath: arguments[1])
            try Data("converted epub".utf8).write(to: output)
            return ShellCommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        let converter = CalibreMOBIConverter(
            cacheRootURL: fixture.dir.appendingPathComponent("cache", isDirectory: true),
            commandRunner: runner,
            binaryResolver: StubBinaryResolver(path: "/usr/local/bin/ebook-convert")
        )

        let output = try converter.convertToEPUB(mobiURL: fixture.fileURL)
        XCTAssertEqual(runner.invocations, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeTempMOBIFile() throws -> (dir: URL, fileURL: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("sample.mobi")
        try Data("mobi bytes".utf8).write(to: fileURL)
        return (dir, fileURL)
    }
}

private struct StubBinaryResolver: MOBIConverterBinaryResolving {
    let path: String?

    func resolveBinaryPath() -> String? {
        path
    }
}

private final class StubCommandRunner: ShellCommandRunning {
    typealias Handler = (_ executable: String, _ arguments: [String]) throws -> ShellCommandResult

    private let handler: Handler
    private(set) var invocations = 0

    init(handler: @escaping Handler = { _, _ in
        ShellCommandResult(exitCode: 1, stdout: "", stderr: "not configured")
    }) {
        self.handler = handler
    }

    func run(executable: String, arguments: [String]) throws -> ShellCommandResult {
        invocations += 1
        return try handler(executable, arguments)
    }
}
