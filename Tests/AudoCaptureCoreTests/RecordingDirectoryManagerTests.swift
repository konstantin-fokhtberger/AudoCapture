import Foundation
import Testing
@testable import AudoCaptureCore

struct RecordingDirectoryManagerTests {
    @Test
    func createSessionDirectoryUsesOverrideRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudoCaptureTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = RecordingDirectoryManager(recordingsRootOverride: root, timeZone: TimeZone(secondsFromGMT: 0)!)

        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let layout = try manager.createSessionDirectory(at: Date(timeIntervalSince1970: 0))

        #expect(layout.root.path.hasPrefix(root.path))
        #expect(layout.micPCM.lastPathComponent == "mic.wav")
        #expect(layout.systemPCM.lastPathComponent == "system.wav")
        #expect(layout.outputM4A.lastPathComponent == "01-01-1970 00-00.m4a")
        #expect(FileManager.default.fileExists(atPath: layout.root.path))
    }
}

extension RecordingDirectoryManagerTests {
    @Test func sameStartTimeCreatesIndependentSessions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingDirectoryManager(recordingsRootOverride: root)
        let date = Date(timeIntervalSince1970: 100)
        let first = try manager.createSessionDirectory(at: date)
        try Data("first recording".utf8).write(to: first.micPCM)
        let second = try manager.createSessionDirectory(at: date)
        #expect(first.root != second.root)
        manager.removeSessionDirectory(at: second.root)
        #expect(try String(contentsOf: first.micPCM, encoding: .utf8) == "first recording")
    }
}

extension RecordingDirectoryManagerTests {
    @Test func filenameUsesLocalStartDateIncludingMidnightRollover() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let utc = try #require(ISO8601DateFormatter().date(from: "2026-09-07T22:04:59Z"))
        let manager = RecordingDirectoryManager(recordingsRootOverride: root, timeZone: TimeZone(secondsFromGMT: 5 * 3600))
        let layout = try manager.createSessionDirectory(at: utc)
        #expect(layout.outputM4A.lastPathComponent == "08-09-2026 03-04.m4a")
        #expect(layout.outputM4A.deletingLastPathComponent().path == root.path)
    }
}
