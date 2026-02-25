import Foundation
import os
import ReaderCore
import ReaderEPUB

public protocol MOBIConverting {
    func convertToEPUB(mobiURL: URL) throws -> URL
}

public protocol EPUBOpening {
    func open(document: BookDocument) throws -> any ReadingSession
}

extension EPUBReaderEngine: EPUBOpening {}

public protocol ShellCommandRunning {
    func run(executable: String, arguments: [String]) throws -> ShellCommandResult
}

public struct ShellCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct ProcessCommandRunner: ShellCommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) throws -> ShellCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ReaderError.parseFailed(URL(fileURLWithPath: arguments.first ?? executable))
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return ShellCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

public protocol MOBIConverterBinaryResolving {
    func resolveBinaryPath() -> String?
}

public struct CalibreBinaryResolver: MOBIConverterBinaryResolving {
    private let fileManager: FileManager
    private let commandRunner: any ShellCommandRunning

    public init(
        fileManager: FileManager = .default,
        commandRunner: any ShellCommandRunning = ProcessCommandRunner()
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    public func resolveBinaryPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["CALIBRE_EBOOK_CONVERT_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        let bundledPath = "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        if fileManager.isExecutableFile(atPath: bundledPath) {
            return bundledPath
        }

        if let result = try? commandRunner.run(executable: "/usr/bin/which", arguments: ["ebook-convert"]),
           result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

public struct CalibreMOBIConverter: MOBIConverting {
    private let fileManager: FileManager
    private let cacheRootURL: URL
    private let commandRunner: any ShellCommandRunning
    private let binaryResolver: any MOBIConverterBinaryResolving
    private let signpostLog = OSLog(subsystem: "com.curious-reader.mobi", category: "Pipeline")

    public init(
        fileManager: FileManager = .default,
        cacheRootURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CuriousReader", isDirectory: true)
            .appendingPathComponent("MOBICache", isDirectory: true),
        commandRunner: any ShellCommandRunning = ProcessCommandRunner(),
        binaryResolver: (any MOBIConverterBinaryResolving)? = nil
    ) {
        self.fileManager = fileManager
        self.cacheRootURL = cacheRootURL
        self.commandRunner = commandRunner
        self.binaryResolver = binaryResolver ?? CalibreBinaryResolver(
            fileManager: fileManager,
            commandRunner: commandRunner
        )
    }

    public func convertToEPUB(mobiURL: URL) throws -> URL {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(
            .begin,
            log: signpostLog,
            name: "ConvertMOBI",
            signpostID: signpostID,
            "%{public}s",
            mobiURL.lastPathComponent
        )
        defer {
            os_signpost(.end, log: signpostLog, name: "ConvertMOBI", signpostID: signpostID)
        }

        let outputURL = try cachedOutputURL(for: mobiURL)
        if fileManager.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        guard let executable = binaryResolver.resolveBinaryPath() else {
            throw ReaderError.conversionUnavailable(mobiURL)
        }

        try fileManager.createDirectory(
            at: cacheRootURL,
            withIntermediateDirectories: true
        )

        let result = try commandRunner.run(
            executable: executable,
            arguments: [mobiURL.path, outputURL.path]
        )
        guard result.exitCode == 0, fileManager.fileExists(atPath: outputURL.path) else {
            throw ReaderError.parseFailed(mobiURL)
        }
        return outputURL
    }

    func cachedOutputURL(for mobiURL: URL) throws -> URL {
        let attributes = try fileManager.attributesOfItem(atPath: mobiURL.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let baseName = sanitizeBaseName(mobiURL.deletingPathExtension().lastPathComponent)
        let pathFingerprint = stablePathHash(mobiURL.path)
        let fileName = "\(baseName)-\(size)-\(Int(modifiedAt))-\(pathFingerprint).epub"
        return cacheRootURL.appendingPathComponent(fileName)
    }

    private func sanitizeBaseName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let candidate = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return candidate.isEmpty ? "book" : candidate
    }

    private func stablePathHash(_ text: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct UnconfiguredMOBIConverter: MOBIConverting {
    public init() {}

    public func convertToEPUB(mobiURL: URL) throws -> URL {
        throw ReaderError.conversionUnavailable(mobiURL)
    }
}

public struct MOBIReaderEngine: ReaderEngine {
    public let supportedFormats: Set<BookFormat> = [.mobi]

    private let converter: any MOBIConverting
    private let epubEngine: any EPUBOpening

    public init(
        converter: any MOBIConverting = CalibreMOBIConverter(),
        epubEngine: any EPUBOpening = EPUBReaderEngine()
    ) {
        self.converter = converter
        self.epubEngine = epubEngine
    }

    public func open(document: BookDocument) throws -> any ReadingSession {
        guard document.format == .mobi else {
            throw ReaderError.formatUnsupported(document.fileURL)
        }

        let convertedURL = try converter.convertToEPUB(mobiURL: document.fileURL)
        let convertedDocument = BookDocument(
            id: document.id,
            fileURL: convertedURL,
            title: document.title,
            format: .epub
        )
        return try epubEngine.open(document: convertedDocument)
    }
}
