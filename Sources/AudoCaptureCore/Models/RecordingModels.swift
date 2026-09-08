import Foundation

public enum RecordingStatus: String, Codable, Sendable {
    case idle
    case starting
    case recording
    case processing
    case completed
    case partial
    case failed
}

public enum TrackKind: String, Codable, Sendable {
    case microphone = "mic"
    case system = "system"
}

public enum CaptureStatus: String, Codable, Sendable {
    case completed, partial, failed
}

public enum PostProcessingStatus: String, Codable, Sendable {
    case pending
    case completed
    case partialFailure
    case failed
}

public struct AudioTrackConfiguration: Codable, Hashable, Sendable {
    public let kind: TrackKind
    public let sampleRate: Double
    public let channels: UInt32
    public let bitDepth: UInt32

    public init(kind: TrackKind, sampleRate: Double, channels: UInt32, bitDepth: UInt32 = 16) {
        self.kind = kind
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

public struct RecordingArtifacts: Codable, Sendable {
    public let directory: String
    public let micPCM: String?
    public let systemPCM: String?
    public let m4a: String?
    public let micMP3: String?
    public let systemMP3: String?

    public init(directory: String, micPCM: String?, systemPCM: String?, micMP3: String? = nil, systemMP3: String? = nil, m4a: String? = nil) {
        self.directory = directory
        self.m4a = m4a
        self.micPCM = micPCM
        self.systemPCM = systemPCM
        self.micMP3 = micMP3
        self.systemMP3 = systemMP3
    }
}

public struct SessionDeviceInfo: Codable, Sendable {
    public let microphoneDevice: String?
    public let systemAudioSource: String?

    public init(microphoneDevice: String?, systemAudioSource: String?) {
        self.microphoneDevice = microphoneDevice
        self.systemAudioSource = systemAudioSource
    }
}

public struct RecordingSessionMetadata: Codable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let durationSeconds: Double
    public let devices: SessionDeviceInfo
    public let tracks: [AudioTrackConfiguration]
    public let artifacts: RecordingArtifacts
    public let trackMetrics: [TrackCaptureMetrics]
    public let syncDiagnostics: SyncDiagnostics
    public let warnings: [String]
    public let postProcessingStatus: PostProcessingStatus
    public let errors: [String]
    public let captureStatus: CaptureStatus?

    public init(
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double,
        devices: SessionDeviceInfo,
        tracks: [AudioTrackConfiguration],
        artifacts: RecordingArtifacts,
        trackMetrics: [TrackCaptureMetrics],
        syncDiagnostics: SyncDiagnostics,
        warnings: [String],
        postProcessingStatus: PostProcessingStatus,
        errors: [String],
        captureStatus: CaptureStatus? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.devices = devices
        self.tracks = tracks
        self.artifacts = artifacts
        self.trackMetrics = trackMetrics
        self.syncDiagnostics = syncDiagnostics
        self.warnings = warnings
        self.postProcessingStatus = postProcessingStatus
        self.errors = errors
        self.captureStatus = captureStatus
    }
}

public struct TrackCaptureMetrics: Codable, Sendable {
    public let kind: TrackKind
    public let frameCount: Int64?
    public let estimatedDurationSeconds: Double?
    public let sampleRate: Double
    public let channels: UInt32

    public init(kind: TrackKind, frameCount: Int64?, estimatedDurationSeconds: Double?, sampleRate: Double, channels: UInt32) {
        self.kind = kind
        self.frameCount = frameCount
        self.estimatedDurationSeconds = estimatedDurationSeconds
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

public struct SyncDiagnostics: Codable, Sendable {
    public let longestTrackDurationSeconds: Double?
    public let microphoneDurationSeconds: Double?
    public let systemDurationSeconds: Double?
    public let absoluteDurationDeltaSeconds: Double?

    public init(longestTrackDurationSeconds: Double?, microphoneDurationSeconds: Double?, systemDurationSeconds: Double?, absoluteDurationDeltaSeconds: Double?) {
        self.longestTrackDurationSeconds = longestTrackDurationSeconds
        self.microphoneDurationSeconds = microphoneDurationSeconds
        self.systemDurationSeconds = systemDurationSeconds
        self.absoluteDurationDeltaSeconds = absoluteDurationDeltaSeconds
    }
}

public struct RecordingSessionResult: Sendable {
    public let metadata: RecordingSessionMetadata
    public let directoryURL: URL
    public let canRetryExport: Bool
    public init(metadata: RecordingSessionMetadata, directoryURL: URL, canRetryExport: Bool = false) {
        self.metadata = metadata
        self.directoryURL = directoryURL
        self.canRetryExport = canRetryExport
    }
}

public struct RecordingStartupReport: Sendable {
    public let activeTracks: [TrackKind]
    public let hostStartedAt: Double?
    public let warnings: [String]

    public init(activeTracks: [TrackKind], warnings: [String], hostStartedAt: Double? = nil) {
        self.hostStartedAt = hostStartedAt
        self.activeTracks = activeTracks
        self.warnings = warnings
    }
}

public enum RecordingError: LocalizedError, Sendable {
    case microphonePermissionDenied
    case screenCapturePermissionDenied
    case alreadyRecording
    case notRecording
    case failedToCreateDirectory(String)
    case failedToCreateFile(String)
    case failedToStartCapture(String)
    case failedToStopCapture(String)
    case incompatibleAudioFormat(String)
    case encoderUnavailable(String)
    case encoderFailed(String)
    case deviceUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is not granted. Enable it in System Settings > Privacy & Security > Microphone."
        case .screenCapturePermissionDenied:
            return "Screen Recording access is not granted. Enable it in System Settings > Privacy & Security > Screen Recording."
        case .alreadyRecording:
            return "A recording session is already running."
        case .notRecording:
            return "There is no active recording session."
        case .failedToCreateDirectory(let message):
            return "Failed to create recording directory: \(message)"
        case .failedToCreateFile(let message):
            return "Failed to create audio file: \(message)"
        case .failedToStartCapture(let message):
            return "Failed to start audio capture: \(message)"
        case .failedToStopCapture(let message):
            return "Failed to stop audio capture: \(message)"
        case .incompatibleAudioFormat(let message):
            return "Unsupported or mismatched audio format: \(message)"
        case .encoderUnavailable(let message):
            return "Audio exporter is unavailable: \(message)"
        case .encoderFailed(let message):
            return "Audio export failed: \(message)"
        case .deviceUnavailable(let message):
            return "Audio device is unavailable: \(message)"
        }
    }
}
