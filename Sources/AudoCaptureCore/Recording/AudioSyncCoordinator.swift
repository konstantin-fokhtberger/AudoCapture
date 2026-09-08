import AVFoundation
import Foundation
import CoreMedia

public struct AudioSessionPlan: Sendable {
    public let startedAt: Date
    public let hostStartedAt: Double
    public let micFormat: AVAudioFormat
    public let systemFormat: AVAudioFormat
    public let micConfig: AudioTrackConfiguration
    public let systemConfig: AudioTrackConfiguration
}

public struct AudioSyncCoordinator: Sendable {
    public let sampleRate: Double

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
    }

    public func makeSessionPlan(startedAt: Date = Date()) throws -> AudioSessionPlan {
        let micFormat = try AVAudioFormat.recordingFormat(sampleRate: sampleRate, channels: 1)
        let systemFormat = try AVAudioFormat.recordingFormat(sampleRate: sampleRate, channels: 2)

        return AudioSessionPlan(
            startedAt: startedAt,
            hostStartedAt: CMClockGetTime(CMClockGetHostTimeClock()).seconds,
            micFormat: micFormat,
            systemFormat: systemFormat,
            micConfig: AudioTrackConfiguration(kind: .microphone, sampleRate: sampleRate, channels: 1),
            systemConfig: AudioTrackConfiguration(kind: .system, sampleRate: sampleRate, channels: 2)
        )
    }
}
