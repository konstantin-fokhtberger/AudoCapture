import Foundation
import OSLog

public actor AppLogger {
    public static let shared = AppLogger()
    public static let disabled = AppLogger(enabled: false)

    private let logger = Logger(subsystem: "com.codex.AudoCapture", category: "app")
    private let fileURL: URL?
    private let formatter = ISO8601DateFormatter()

    public init(fileManager: FileManager = .default, enabled: Bool = true, logDirectory: URL? = nil) {
        guard enabled else { fileURL = nil; return }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = logDirectory ?? base.appendingPathComponent("AudoCapture/logs", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("app.log")
    }

    public func info(_ message: String) {
        guard fileURL != nil else { return }
        logger.info("\(message, privacy: .public)")
        append(level: "INFO", message: message)
    }

    public func error(_ message: String) {
        guard fileURL != nil else { return }
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", message: message)
    }

    private func append(level: String, message: String) {
        guard let fileURL else { return }
        let line = "\(formatter.string(from: Date())) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) == false {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.error("Failed to append to log file: \(error.localizedDescription, privacy: .public)")
        }
    }
}
