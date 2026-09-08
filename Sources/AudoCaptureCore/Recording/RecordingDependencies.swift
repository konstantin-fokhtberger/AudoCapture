import AppKit
import AVFoundation
import Foundation

public protocol PermissionsProviding: Sendable {
    func currentStatus() -> PermissionsSnapshot
    func requestRequiredPermissions() async throws
    func openSystemSettingsForMicrophone()
    func openSystemSettingsForScreenCapture()
}

extension PermissionsManager: PermissionsProviding {}

public protocol RecordingControlling: Sendable {
    func setMuted(microphone: Bool, system: Bool) async
    func startRecording(preferredMicrophoneDeviceID: UInt32?) async throws -> RecordingStartupReport
    func stopRecording(openFolder: Bool, bitrate: Int) async throws -> RecordingSessionResult
    func noteInterruption(_ reason: String) async
    func retryExport(openFolder: Bool) async throws -> RecordingSessionResult
    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) async
    func permissionSnapshot() -> PermissionsSnapshot
    func availableMicrophones() -> [MicrophoneDevice]
    func openMicrophoneSettings()
    func openScreenRecordingSettings()
}

public protocol RecordingCaptureService: Sendable {
    func setMuted(_ muted: Bool)
    var sourceDescription: String? { get }
    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void)
    func start() async throws
    func stop() async throws -> AVAudioFramePosition
}

public struct RecordingCapturePair: Sendable {
    public let microphone: any RecordingCaptureService
    public let system: any RecordingCaptureService

    public init(microphone: any RecordingCaptureService, system: any RecordingCaptureService) {
        self.microphone = microphone
        self.system = system
    }
}

public protocol RecordingCaptureFactory: Sendable {
    func makeCapturePair(
        layout: RecordingDirectoryLayout,
        plan: AudioSessionPlan,
        logger: AppLogger,
        preferredMicrophoneDeviceID: UInt32?
    ) -> RecordingCapturePair
}

public struct DefaultRecordingCaptureFactory: RecordingCaptureFactory {
    public init() {}

    public func makeCapturePair(
        layout: RecordingDirectoryLayout,
        plan: AudioSessionPlan,
        logger: AppLogger,
        preferredMicrophoneDeviceID: UInt32?
    ) -> RecordingCapturePair {
        let micWriter = PCMFileWriter(url: layout.micPCM, format: plan.micFormat)
        let systemWriter = PCMFileWriter(url: layout.systemPCM, format: plan.systemFormat)
        return RecordingCapturePair(
            microphone: MicrophoneCaptureService(writer: micWriter, targetFormat: plan.micFormat, preferredDeviceID: preferredMicrophoneDeviceID, logger: logger, timelineStart: plan.hostStartedAt),
            system: SystemAudioCaptureService(writer: systemWriter, targetFormat: plan.systemFormat, logger: logger, timelineStart: plan.hostStartedAt),
        )
    }
}

public protocol RecordingsFolderOpening: Sendable {
    func open(directoryURL: URL) async
}

public struct DefaultRecordingsFolderOpener: RecordingsFolderOpening {
    public init() {}

    public func open(directoryURL: URL) async {
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
        }
    }
}

// Optional for lightweight test doubles and clients without a UI observer.
extension RecordingCaptureService {
    public func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {}
}
