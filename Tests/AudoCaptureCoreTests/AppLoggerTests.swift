import Foundation
import Testing
@testable import AudoCaptureCore

struct AppLoggerTests {
    @Test func disabledLoggerDoesNotCreateDirectoryOrFiles() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logger = AppLogger(enabled: false, logDirectory: directory)
        await logger.info("disabled info")
        await logger.error("disabled error")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func explicitTestDirectoryReceivesBothMessages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = AppLogger(logDirectory: directory)
        await logger.info("first test event")
        await logger.error("second test event")
        let contents = try String(contentsOf: directory.appendingPathComponent("app.log"), encoding: .utf8)
        #expect(contents.contains("[INFO] first test event"))
        #expect(contents.contains("[ERROR] second test event"))
        #expect(contents.split(separator: "\n").count == 2)
    }
}
