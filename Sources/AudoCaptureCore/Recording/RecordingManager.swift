import AppKit
import AVFoundation
import Foundation
import CoreMedia

public actor RecordingManager {
    private let permissionsManager: any PermissionsProviding
    private let directoryManager: RecordingDirectoryManager
    private let metadataWriter: MetadataWriter
    private let exporter: any RecordingExporting
    private let logger: AppLogger
    private let syncCoordinator: AudioSyncCoordinator
    private let captureFactory: any RecordingCaptureFactory
    private let folderOpener: any RecordingsFolderOpening
    private let microphoneCatalog: any MicrophoneDeviceProviding

    private enum Lifecycle { case idle, starting, recording, stopping }
    private var lifecycle: Lifecycle = .idle
    private var microphoneMuted = false
    private var systemMuted = false

    public func setMuted(microphone: Bool, system: Bool) async {
        microphoneMuted = microphone
        systemMuted = system
        session?.microphone?.setMuted(microphone)
        session?.system?.setMuted(system)
    }

    private var session: ActiveSession?
    private var sessionID: UUID?
    private var interruptionReason: String?
    private var runtimeErrors: [TrackKind: String] = [:]
    private var failureHandler: (@Sendable (String) -> Void)?

    public func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) async {
        failureHandler = handler
    }

    private func captureFailed(_ kind: TrackKind, message: String, sessionID: UUID) {
        guard self.sessionID == sessionID, lifecycle != .idle, runtimeErrors[kind] == nil else { return }
        let description = "\(kind.rawValue): \(message)"
        runtimeErrors[kind] = description
        failureHandler?(description)
    }

    public init(
        permissionsManager: any PermissionsProviding = PermissionsManager(),
        directoryManager: RecordingDirectoryManager = .init(),
        metadataWriter: MetadataWriter = .init(),
        exporter: any RecordingExporting = NativeM4AExporter(),
        logger: AppLogger = .shared,
        syncCoordinator: AudioSyncCoordinator = .init(),
        captureFactory: any RecordingCaptureFactory = DefaultRecordingCaptureFactory(),
        folderOpener: any RecordingsFolderOpening = DefaultRecordingsFolderOpener(),
        microphoneCatalog: any MicrophoneDeviceProviding = MicrophoneDeviceCatalog()
    ) {
        self.permissionsManager = permissionsManager
        self.directoryManager = directoryManager
        self.metadataWriter = metadataWriter
        self.exporter = exporter
        self.logger = logger
        self.syncCoordinator = syncCoordinator
        self.captureFactory = captureFactory
        self.folderOpener = folderOpener
        self.microphoneCatalog = microphoneCatalog
    }

    public func startRecording(preferredMicrophoneDeviceID: UInt32? = nil) async throws -> RecordingStartupReport {
        guard lifecycle == .idle else {
            throw RecordingError.alreadyRecording
        }

        lifecycle = .starting
        let id = UUID()
        sessionID = id
        runtimeErrors = [:]
        interruptionReason = nil
        defer {
            if lifecycle == .starting {
                lifecycle = .idle
                sessionID = nil
            }
        }
        try Task.checkCancellation()
        do {
            try await permissionsManager.requestRequiredPermissions()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await logger.error("Permission request completed with degraded availability: \(error.localizedDescription)")
        }

        try Task.checkCancellation()
        let permissions = permissionsManager.currentStatus()
        guard permissions.microphoneGranted || permissions.screenCaptureGranted else {
            let messages = [
                permissions.microphoneGranted ? nil : RecordingError.microphonePermissionDenied.localizedDescription,
                permissions.screenCaptureGranted ? nil : RecordingError.screenCapturePermissionDenied.localizedDescription
            ].compactMap { $0 }
            throw RecordingError.failedToStartCapture(messages.joined(separator: " | "))
        }

        let plan = try syncCoordinator.makeSessionPlan()
        let layout = try directoryManager.createSessionDirectory(at: plan.startedAt)
        let captures = captureFactory.makeCapturePair(
            layout: layout,
            plan: plan,
            logger: logger,
            preferredMicrophoneDeviceID: preferredMicrophoneDeviceID
        )

        captures.microphone.setMuted(microphoneMuted)
        captures.system.setMuted(systemMuted)

        captures.microphone.setFailureHandler { [weak self] message in
            Task { await self?.captureFailed(.microphone, message: message, sessionID: id) }
        }
        captures.system.setFailureHandler { [weak self] message in
            Task { await self?.captureFailed(.system, message: message, sessionID: id) }
        }
        let startResult = await Self.startCaptures(captures, permissions: permissions)
        let microphoneStartError = startResult.microphoneError
        let systemStartError = startResult.systemError
        let microphoneStarted = microphoneStartError == nil
        let systemStarted = systemStartError == nil

        var warnings = [String]()
        if let microphoneStartError {
            warnings.append("Microphone capture did not start: \(microphoneStartError.localizedDescription)")
            await logger.error("Microphone capture startup warning: \(microphoneStartError.localizedDescription)")
        }
        if let systemStartError {
            warnings.append("System audio capture did not start: \(systemStartError.localizedDescription)")
            await logger.error("System audio capture startup warning: \(systemStartError.localizedDescription)")
        }

        if microphoneStarted == false {
            await Self.cleanupInactiveCapture(captures.microphone, pcmURL: layout.micPCM, stopPreparedCapture: permissions.microphoneGranted)
        }
        if systemStarted == false {
            await Self.cleanupInactiveCapture(captures.system, pcmURL: layout.systemPCM, stopPreparedCapture: permissions.screenCaptureGranted)
        }

        if Task.isCancelled {
            if microphoneStarted { _ = try? await captures.microphone.stop() }
            if systemStarted { _ = try? await captures.system.stop() }
            // Keep any captured material; only stop resources owned by this startup.
            throw CancellationError()
        }

        guard microphoneStarted || systemStarted else {
            directoryManager.removeSessionDirectory(at: layout.root)
            await logger.error("Recording startup failed, cleaned up session directory: \(layout.root.path)")
            throw RecordingError.failedToStartCapture(warnings.joined(separator: " | "))
        }

        session = ActiveSession(
            startedAt: plan.startedAt,
            hostStartedAt: plan.hostStartedAt,
            layout: layout,
            microphone: microphoneStarted ? captures.microphone : nil,
            system: systemStarted ? captures.system : nil,
            tracks: [microphoneStarted ? plan.micConfig : nil, systemStarted ? plan.systemConfig : nil].compactMap { $0 },
            startupWarnings: warnings
        )
        lifecycle = .recording
        await logger.info("Recording session created at \(layout.root.path)")
        return RecordingStartupReport(activeTracks: [microphoneStarted ? TrackKind.microphone : nil, systemStarted ? TrackKind.system : nil].compactMap { $0 }, warnings: warnings, hostStartedAt: plan.hostStartedAt)
    }

    public func noteInterruption(_ reason: String) async {
        guard lifecycle == .recording || lifecycle == .starting else { return }
        interruptionReason = interruptionReason ?? reason
    }

    public func stopRecording(openFolder: Bool = true, bitrate: Int = 192) async throws -> RecordingSessionResult {
        guard lifecycle == .recording, let session else {
            throw RecordingError.notRecording
        }
        lifecycle = .stopping
        defer {
            self.session = nil
            lifecycle = .idle
            sessionID = nil
        }

        let endedAt = Date()
        let duration = max(0, CMClockGetTime(CMClockGetHostTimeClock()).seconds - session.hostStartedAt)
        var errors = [String]()
        var microphoneFrameCount: AVAudioFramePosition?
        var systemFrameCount: AVAudioFramePosition?

        if let microphone = session.microphone {
            do {
                microphoneFrameCount = try await microphone.stop()
            } catch {
                errors.append(error.localizedDescription)
                await logger.error("Microphone stop failed: \(error.localizedDescription)")
            }
        }

        if let system = session.system {
            do {
                systemFrameCount = try await system.stop()
            } catch {
                errors.append(error.localizedDescription)
                await logger.error("System audio stop failed: \(error.localizedDescription)")
            }
        }

        let inputs = [
            (microphoneFrameCount ?? 0) > 0 ? AudioExportInput(kind: .microphone, url: session.layout.micPCM) : nil,
            (systemFrameCount ?? 0) > 0 ? AudioExportInput(kind: .system, url: session.layout.systemPCM) : nil
        ].compactMap { $0 }
        let devices = SessionDeviceInfo(
            microphoneDevice: session.microphone?.sourceDescription,
            systemAudioSource: session.system?.sourceDescription
        )
        let artifacts = RecordingArtifacts(directory: session.layout.root.path,
            micPCM: session.microphone != nil ? session.layout.micPCM.path : nil,
            systemPCM: session.system != nil ? session.layout.systemPCM.path : nil)
        let trackMetrics = makeTrackMetrics(
            tracks: session.tracks,
            microphoneFrameCount: microphoneFrameCount,
            systemFrameCount: systemFrameCount
        )
        let syncDiagnostics = makeSyncDiagnostics(from: trackMetrics)

        let captureErrors = Set(Array(runtimeErrors.values) + [interruptionReason].compactMap { $0 }).sorted()
        errors.append(contentsOf: captureErrors.filter { !errors.contains($0) })
        let finalizedCount = [microphoneFrameCount, systemFrameCount].compactMap { $0 }.filter { $0 > 0 }.count
        let captureStatus: CaptureStatus = finalizedCount == 0 ? .failed
            : (finalizedCount == 2 && captureErrors.isEmpty ? .completed : .partial)
        let metadata = RecordingSessionMetadata(
            startedAt: session.startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            devices: devices,
            tracks: session.tracks,
            artifacts: artifacts,
            trackMetrics: trackMetrics,
            syncDiagnostics: syncDiagnostics,
            warnings: session.startupWarnings,
            postProcessingStatus: .pending,
            errors: errors,
            captureStatus: captureStatus
        )

        pendingExport = PendingExport(layout: session.layout, inputs: inputs, metadata: metadata, bitrate: bitrate)
        return try await finishExport(openFolder: openFolder)
    }

    private struct PendingExport {
        let layout: RecordingDirectoryLayout
        let inputs: [AudioExportInput]
        let metadata: RecordingSessionMetadata
        let bitrate: Int
        var publishedURL: URL?
    }
    private var pendingExport: PendingExport?

    public func retryExport(openFolder: Bool = true) async throws -> RecordingSessionResult {
        guard lifecycle == .idle, pendingExport != nil else { throw RecordingError.notRecording }
        lifecycle = .stopping
        defer { lifecycle = .idle }
        return try await finishExport(openFolder: openFolder)
    }

    private func finishExport(openFolder: Bool) async throws -> RecordingSessionResult {
        guard var job = pendingExport else { throw RecordingError.notRecording }
        let base = job.metadata
        func metadata(status: PostProcessingStatus, extraErrors: [String] = [], warnings: [String] = []) -> RecordingSessionMetadata {
            RecordingSessionMetadata(startedAt: base.startedAt, endedAt: base.endedAt,
                durationSeconds: base.durationSeconds, devices: base.devices, tracks: base.tracks,
                artifacts: RecordingArtifacts(directory: job.layout.root.path,
                    micPCM: FileManager.default.fileExists(atPath: job.layout.micPCM.path) ? job.layout.micPCM.path : nil,
                    systemPCM: FileManager.default.fileExists(atPath: job.layout.systemPCM.path) ? job.layout.systemPCM.path : nil,
                    m4a: job.publishedURL?.path),
                trackMetrics: base.trackMetrics, syncDiagnostics: base.syncDiagnostics,
                warnings: base.warnings + warnings, postProcessingStatus: status,
                errors: base.errors + extraErrors, captureStatus: base.captureStatus)
        }
        do {
            try metadataWriter.write(metadata(status: .pending), to: job.layout.metadata)
            guard !job.inputs.isEmpty else { throw RecordingError.encoderFailed("No finalized audio tracks. Original files retained.") }
            if job.publishedURL == nil || !FileManager.default.fileExists(atPath: job.publishedURL!.path) {
                job.publishedURL = try await exporter.export(inputs: job.inputs, to: job.layout.outputM4A,
                    minimumDuration: base.durationSeconds, bitrate: job.bitrate)
                pendingExport = job
            } else if let published = job.publishedURL {
                // Retry can happen much later: re-check audio before source deletion.
                try await exporter.validate(published, expectedDuration: max(base.durationSeconds,
                    base.trackMetrics.compactMap(\.estimatedDurationSeconds).max() ?? 0))
            }
            // Persist the verified output before removing any source audio.
            try metadataWriter.write(metadata(status: .completed), to: job.layout.metadata)
        } catch {
            let failed = metadata(status: .failed, extraErrors: [error.localizedDescription])
            try? metadataWriter.write(failed, to: job.layout.metadata)
            if openFolder { await folderOpener.open(directoryURL: job.layout.root) }
            return RecordingSessionResult(metadata: failed, directoryURL: job.layout.root, canRetryExport: !job.inputs.isEmpty)
        }
        var warnings: [String] = []
        for input in job.inputs {
            do { try FileManager.default.removeItem(at: input.url) }
            catch { warnings.append("Could not remove temporary audio: \(error.localizedDescription)") }
        }
        var completed = metadata(status: .completed, warnings: warnings)
        do { try metadataWriter.write(completed, to: job.layout.metadata) }
        catch { completed = metadata(status: .completed, warnings: warnings + ["Metadata update failed: \(error.localizedDescription)"]) }
        pendingExport = nil
        let directory = job.layout.outputM4A.deletingLastPathComponent()
        if openFolder { await folderOpener.open(directoryURL: directory) }
        return RecordingSessionResult(metadata: completed, directoryURL: directory)
    }

    public nonisolated func permissionSnapshot() -> PermissionsSnapshot {
        permissionsManager.currentStatus()
    }

    public nonisolated func availableMicrophones() -> [MicrophoneDevice] {
        microphoneCatalog.availableMicrophones()
    }

    public nonisolated func openMicrophoneSettings() {
        permissionsManager.openSystemSettingsForMicrophone()
    }

    public nonisolated func openScreenRecordingSettings() {
        permissionsManager.openSystemSettingsForScreenCapture()
    }

    private struct ActiveSession {
        let startedAt: Date
        let hostStartedAt: Double
        let layout: RecordingDirectoryLayout
        let microphone: (any RecordingCaptureService)?
        let system: (any RecordingCaptureService)?
        let tracks: [AudioTrackConfiguration]
        let startupWarnings: [String]
    }

    private func makeTrackMetrics(
        tracks: [AudioTrackConfiguration],
        microphoneFrameCount: AVAudioFramePosition?,
        systemFrameCount: AVAudioFramePosition?
    ) -> [TrackCaptureMetrics] {
        tracks.map { track in
            let frameCount = track.kind == .microphone ? microphoneFrameCount : systemFrameCount
            return TrackCaptureMetrics(
                kind: track.kind,
                frameCount: frameCount,
                estimatedDurationSeconds: frameCount.flatMap { track.sampleRate > 0 ? Double($0) / track.sampleRate : nil },
                sampleRate: track.sampleRate,
                channels: track.channels
            )
        }
    }

    private func makeSyncDiagnostics(from trackMetrics: [TrackCaptureMetrics]) -> SyncDiagnostics {
        let microphoneDuration = trackMetrics.first(where: { $0.kind == .microphone })?.estimatedDurationSeconds
        let systemDuration = trackMetrics.first(where: { $0.kind == .system })?.estimatedDurationSeconds
        let longest = [microphoneDuration, systemDuration].compactMap { $0 }.max()
        return SyncDiagnostics(
            longestTrackDurationSeconds: longest,
            microphoneDurationSeconds: microphoneDuration,
            systemDurationSeconds: systemDuration,
            absoluteDurationDeltaSeconds: microphoneDuration.flatMap { mic in systemDuration.map { abs(mic - $0) } }
        )
    }

    private static func startCapture(_ capture: any RecordingCaptureService) async -> Error? {
        do {
            try await capture.start()
            return nil
        } catch {
            return error
        }
    }

    private static func startCaptures(
        _ captures: RecordingCapturePair,
        permissions: PermissionsSnapshot
    ) async -> (microphoneError: Error?, systemError: Error?) {
        async let microphoneError = startCaptureIfPermitted(
            captures.microphone,
            permitted: permissions.microphoneGranted,
            deniedError: RecordingError.microphonePermissionDenied
        )
        async let systemError = startCaptureIfPermitted(
            captures.system,
            permitted: permissions.screenCaptureGranted,
            deniedError: RecordingError.screenCapturePermissionDenied
        )
        return await (microphoneError, systemError)
    }

    private static func startCaptureIfPermitted(
        _ capture: any RecordingCaptureService,
        permitted: Bool,
        deniedError: RecordingError
    ) async -> Error? {
        guard permitted else { return deniedError }
        return await startCapture(capture)
    }

    private static func cleanupInactiveCapture(
        _ capture: any RecordingCaptureService,
        pcmURL: URL,
        stopPreparedCapture: Bool
    ) async {
        if stopPreparedCapture {
            _ = try? await capture.stop()
        }
        try? FileManager.default.removeItem(at: pcmURL)
    }
}

extension RecordingManager: RecordingControlling {}
