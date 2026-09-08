import AudoCaptureCore
import Foundation

let smokeRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("AudoCaptureSmokeChecks", isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)

do {
    let directoryManager = RecordingDirectoryManager(recordingsRootOverride: smokeRoot)
    let layout = try directoryManager.createSessionDirectory(at: Date(timeIntervalSince1970: 0))
    defer {
        try? FileManager.default.removeItem(at: smokeRoot)
    }

    guard layout.micPCM.lastPathComponent == "mic.wav",
          layout.systemPCM.lastPathComponent == "system.wav",
          layout.outputM4A.pathExtension == "m4a" else {
        fatalError("Directory layout check failed.")
    }
    guard layout.root.path.hasPrefix(smokeRoot.path) else {
        fatalError("Smoke check wrote outside of its temporary directory.")
    }

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
            directory: layout.root.path,
            micPCM: layout.micPCM.path,
            systemPCM: layout.systemPCM.path,
            m4a: layout.outputM4A.path
        ),
        trackMetrics: [
            TrackCaptureMetrics(kind: .microphone, frameCount: 48_000, estimatedDurationSeconds: 1, sampleRate: 48_000, channels: 1),
            TrackCaptureMetrics(kind: .system, frameCount: 48_000, estimatedDurationSeconds: 1, sampleRate: 48_000, channels: 2)
        ],
        syncDiagnostics: SyncDiagnostics(longestTrackDurationSeconds: 1, microphoneDurationSeconds: 1, systemDurationSeconds: 1, absoluteDurationDeltaSeconds: 0),
        warnings: [],
        postProcessingStatus: .pending,
        errors: []
    )

    try MetadataWriter().write(metadata, to: layout.metadata)
    guard FileManager.default.fileExists(atPath: layout.metadata.path) else {
        fatalError("Metadata check failed.")
    }

    print("Smoke checks passed.")
} catch {
    fputs("Smoke checks failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
