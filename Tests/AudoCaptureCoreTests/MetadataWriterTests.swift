import Foundation
import Testing
@testable import AudoCaptureCore

struct MetadataWriterTests {
    @Test
    func writeCreatesJSONFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudoCaptureMetadataTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let url = root.appendingPathComponent("metadata.json")
        let metadata = RecordingSessionMetadata(
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 6),
            durationSeconds: 5,
            devices: SessionDeviceInfo(microphoneDevice: "Mic", systemAudioSource: "Display"),
            tracks: [
                AudioTrackConfiguration(kind: .microphone, sampleRate: 48_000, channels: 1),
                AudioTrackConfiguration(kind: .system, sampleRate: 48_000, channels: 2)
            ],
            artifacts: RecordingArtifacts(
                directory: root.path,
                micPCM: root.appendingPathComponent("mic.wav").path,
                systemPCM: root.appendingPathComponent("system.wav").path,
                micMP3: root.appendingPathComponent("mic.mp3").path,
                systemMP3: root.appendingPathComponent("system.mp3").path
            ),
            trackMetrics: [
                TrackCaptureMetrics(kind: .microphone, frameCount: 240_000, estimatedDurationSeconds: 5, sampleRate: 48_000, channels: 1),
                TrackCaptureMetrics(kind: .system, frameCount: 240_000, estimatedDurationSeconds: 5, sampleRate: 48_000, channels: 2)
            ],
            syncDiagnostics: SyncDiagnostics(longestTrackDurationSeconds: 5, microphoneDurationSeconds: 5, systemDurationSeconds: 5, absoluteDurationDeltaSeconds: 0),
            warnings: [],
            postProcessingStatus: .completed,
            errors: []
        )

        try MetadataWriter().write(metadata, to: url)

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecordingSessionMetadata.self, from: data)
        #expect(decoded.durationSeconds == 5)
        #expect(decoded.tracks.count == 2)
        #expect(decoded.trackMetrics.count == 2)
        #expect(decoded.warnings.isEmpty)
        #expect(decoded.postProcessingStatus == .completed)
    }
}
