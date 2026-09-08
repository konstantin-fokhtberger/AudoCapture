import Foundation
import Testing
@testable import AudoCaptureCore

struct RecordingLocationTests {
    @Test func selectionPersistsAndLayoutsStayInSelectedDirectory() throws {
        let suite = "AudoCapture-location-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        RecordingLocation.set(root, defaults: defaults)
        let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
        let restored = try #require(RecordingLocation.selectedURL(defaults: reopenedDefaults))
        #expect(restored.standardizedFileURL.path == root.standardizedFileURL.path)
        let manager = RecordingDirectoryManager(selectedRoot: { restored })
        let layout = try manager.createSessionDirectory(at: Date())
        #expect(layout.outputM4A.deletingLastPathComponent().path == restored.path)
        #expect(layout.root.deletingLastPathComponent().lastPathComponent == ".sessions")
        #expect(FileManager.default.fileExists(atPath: layout.root.path))
    }

    @Test func missingSelectedFolderFailsWithoutRecreatingOrFallingBack() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = RecordingDirectoryManager(selectedRoot: { missing })
        #expect(throws: RecordingError.self) { try manager.createSessionDirectory(at: Date()) }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }
}
