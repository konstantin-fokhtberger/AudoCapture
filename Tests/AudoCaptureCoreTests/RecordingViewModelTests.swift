import Foundation
import Testing
@testable import AudoCaptureCore

@MainActor
struct RecordingViewModelTests {
    @Test
    func startRecordingMovesThroughStartingIntoRecording() async throws {
        let manager = TestRecordingController()
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()
        #expect(viewModel.status == .starting)

        await manager.finishStart()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == .recording
        }
    }

    @Test
    func stopRecordingMovesThroughProcessingIntoCompleted() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()
        await manager.finishStart()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.recording
        }

        viewModel.stopRecording()
        #expect(viewModel.status == RecordingStatus.processing)

        await manager.finishStop()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.completed
        }
    }

    @Test
    func stopRecordingSurfacesPostProcessingFailure() async throws {
        let metadata = TestRecordingController.metadata(
            postProcessingStatus: .failed,
            errors: ["Audio export failed"]
        )
        let manager = TestRecordingController(startMode: .success(), stopMode: .success(metadata))
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()
        await manager.finishStart()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.recording
        }

        viewModel.stopRecording()

        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.failed
        }
        #expect(viewModel.errorMessage?.contains("Audio export failed") == true)
        #expect(viewModel.lastOutputDirectory == "/tmp/AudoCapture")
    }

    @Test
    func startRecordingSetsFailedStateWhenManagerThrows() async throws {
        let manager = TestRecordingController(startMode: .failure(RecordingError.microphonePermissionDenied))
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()

        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.failed
        }
        #expect(viewModel.errorMessage?.contains("Microphone access is not granted") == true)
    }

    @Test
    func refreshMicrophonesSelectsDefaultDevice() async throws {
        let manager = TestRecordingController()
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.refreshMicrophones()

        #expect(viewModel.availableMicrophones.count == 2)
        #expect(viewModel.selectedMicrophoneID == 101)
        #expect(viewModel.selectedMicrophoneName == "Built-in Microphone")
    }

    @Test
    func startRecordingSurfacesDegradedStartupWarning() async throws {
        let manager = TestRecordingController(startMode: .success(RecordingStartupReport(activeTracks: [.system], warnings: ["Microphone capture did not start"])))
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()

        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == .recording
        }
        #expect(viewModel.noticeMessage?.contains("Microphone capture did not start") == true)
    }

    @Test
    func prepareForTerminationStopsAnActiveRecordingWithoutOpeningFolder() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let viewModel = RecordingViewModel(manager: manager)

        viewModel.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.recording
        }

        let terminationTask = Task { @MainActor in
            await viewModel.prepareForTermination()
        }

        try await waitUntil(timeoutNanoseconds: 1_000_000_000) {
            viewModel.status == RecordingStatus.processing
        }
        await manager.finishStop()
        #expect(await terminationTask.value)

        #expect(viewModel.status == RecordingStatus.completed)
        let stopArguments = await manager.lastStopArguments()
        #expect(stopArguments?.openFolder == false)
        #expect(stopArguments?.bitrate == 192)
    }
}

private actor TestRecordingController: RecordingControlling {
    private(set) var interruptionReason: String?
    func noteInterruption(_ reason: String) async { interruptionReason = reason }
    func retryExport(openFolder: Bool) async throws -> RecordingSessionResult { try await stopRecording(openFolder: openFolder, bitrate: 192) }
    enum StartMode {
        case pending
        case success(RecordingStartupReport = RecordingStartupReport(activeTracks: [.microphone, .system], warnings: []))
        case failure(Error)
    }

    enum StopMode {
        case pending
        case success(RecordingSessionMetadata = TestRecordingController.metadata())
        case failure(Error)
    }

    private var failureHandler: (@Sendable (String) -> Void)?
    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) async { failureHandler = handler }
    func emitFailure(_ message: String) { failureHandler?(message) }

    private var startMode: StartMode
    private var stopMode: StopMode
    private var startContinuation: CheckedContinuation<RecordingStartupReport, Error>?
    private var stopContinuation: CheckedContinuation<RecordingSessionResult, Error>?
    private(set) var stopCount = 0
    private var recordedStopArguments: (openFolder: Bool, bitrate: Int)?

    init(startMode: StartMode = .pending, stopMode: StopMode = .success()) {
        self.startMode = startMode
        self.stopMode = stopMode
    }

    nonisolated func permissionSnapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(microphoneGranted: true, screenCaptureGranted: true)
    }

    nonisolated func availableMicrophones() -> [MicrophoneDevice] {
        [
            MicrophoneDevice(id: 101, name: "Built-in Microphone", isDefault: true),
            MicrophoneDevice(id: 202, name: "USB Microphone", isDefault: false)
        ]
    }

    nonisolated func openMicrophoneSettings() {}

    nonisolated func openScreenRecordingSettings() {}

    func startRecording(preferredMicrophoneDeviceID: UInt32?) async throws -> RecordingStartupReport {
        switch startMode {
        case .success(let report):
            return report
        case .failure(let error):
            throw error
        case .pending:
            return try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func stopRecording(openFolder: Bool, bitrate: Int) async throws -> RecordingSessionResult {
        stopCount += 1
        recordedStopArguments = (openFolder, bitrate)
        switch stopMode {
        case .success(let metadata):
            return .init(metadata: metadata, directoryURL: URL(fileURLWithPath: "/tmp/AudoCapture"))
        case .failure(let error):
            throw error
        case .pending:
            return try await withCheckedThrowingContinuation { continuation in
                stopContinuation = continuation
            }
        }
    }

    func finishStart() {
        startMode = .success()
        startContinuation?.resume(returning: RecordingStartupReport(activeTracks: [.microphone, .system], warnings: []))
        startContinuation = nil
    }

    func finishStop() {
        let metadata = Self.metadata()
        stopMode = .success(metadata)
        stopContinuation?.resume(returning: .init(metadata: metadata, directoryURL: URL(fileURLWithPath: "/tmp/AudoCapture")))
        stopContinuation = nil
    }

    func lastStopArguments() -> (openFolder: Bool, bitrate: Int)? {
        recordedStopArguments
    }

    static func metadata(
        postProcessingStatus: PostProcessingStatus = .completed,
        errors: [String] = []
    ) -> RecordingSessionMetadata {
        RecordingSessionMetadata(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            durationSeconds: 1,
            devices: SessionDeviceInfo(microphoneDevice: "Mic", systemAudioSource: "Display"),
            tracks: [
                AudioTrackConfiguration(kind: .microphone, sampleRate: 48_000, channels: 1),
                AudioTrackConfiguration(kind: .system, sampleRate: 48_000, channels: 2)
            ],
            artifacts: RecordingArtifacts(directory: "/tmp/AudoCapture", micPCM: "mic.wav", systemPCM: "system.wav", micMP3: "mic.mp3", systemMP3: "system.mp3"),
            trackMetrics: [
                TrackCaptureMetrics(kind: .microphone, frameCount: 48_000, estimatedDurationSeconds: 1, sampleRate: 48_000, channels: 1),
                TrackCaptureMetrics(kind: .system, frameCount: 48_000, estimatedDurationSeconds: 1, sampleRate: 48_000, channels: 2)
            ],
            syncDiagnostics: SyncDiagnostics(longestTrackDurationSeconds: 1, microphoneDurationSeconds: 1, systemDurationSeconds: 1, absoluteDurationDeltaSeconds: 0),
            warnings: [],
            postProcessingStatus: postProcessingStatus,
            errors: errors
        )
    }
}

private func waitUntil(timeoutNanoseconds: UInt64, condition: @escaping @MainActor () -> Bool) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while await condition() == false {
        if DispatchTime.now().uptimeNanoseconds > deadline {
            throw RecordingError.failedToStartCapture("Timed out waiting for expected view-model state.")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}


extension RecordingViewModelTests {
    @Test func quitWaitsForProcessingBeyondOldFiveSecondTimeout() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let model = RecordingViewModel(manager: manager)
        model.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .recording }
        model.stopRecording()
        var returned = false
        let quit = Task { @MainActor in
            let ready = await model.prepareForTermination()
            returned = true
            return ready
        }
        try await Task.sleep(nanoseconds: 5_200_000_000)
        #expect(!returned)
        #expect(model.status == .processing)
        await manager.finishStop()
        #expect(await quit.value)
        #expect(model.status == .completed)
    }

    @Test func runtimeFailureAutomaticallyStopsRecording() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let model = RecordingViewModel(manager: manager)
        model.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .recording }
        await manager.emitFailure("microphone disconnected")
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .processing }
        #expect(model.errorMessage == "microphone disconnected")
        await manager.finishStop()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .partial }
    }

    @Test func partialExportIsNotShownAsComplete() async throws {
        let metadata = TestRecordingController.metadata(postProcessingStatus: .partialFailure, errors: ["system export failed"])
        let manager = TestRecordingController(startMode: .success(), stopMode: .success(metadata))
        let model = RecordingViewModel(manager: manager)
        model.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .recording }
        model.stopRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .partial }
        #expect(model.errorMessage == "system export failed")
    }
}

extension RecordingViewModelTests {
    @Test func timerUsesCaptureStartAndFreezesWhileSaving() async throws {
        var now = 103.0
        let manager = TestRecordingController(startMode: .success(.init(activeTracks: [.system], warnings: ["Microphone unavailable"], hostStartedAt: 100)), stopMode: .pending)
        let model = RecordingViewModel(manager: manager, hostTime: { now })
        model.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .recording }
        #expect(model.activeTracks == [.system])
        #expect(model.elapsedText == "00:00:03")
        now = 3_761
        model.updateElapsedTime()
        #expect(model.elapsedText == "01:01:01")
        model.stopRecording()
        now = 4_000
        model.updateElapsedTime()
        #expect(model.elapsedText == "01:01:01")
        await manager.finishStop()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .completed }
    }

    @Test func repeatedEnvironmentInterruptionsStopOnceAndStayPartial() async throws {
        let manager = TestRecordingController(startMode: .success(), stopMode: .pending)
        let model = RecordingViewModel(manager: manager)
        model.startRecording()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .recording }
        model.interruptRecording("Device changed")
        model.interruptRecording("Mac sleeping")
        #expect(model.status == .processing)
        await manager.finishStop()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .partial }
        #expect(await manager.interruptionReason == "Device changed")
        #expect(await manager.stopCount == 1)
        #expect(await manager.lastStopArguments()?.openFolder == false)
        #expect(model.errorMessage == "Device changed")
        model.interruptRecording("Late notification")
        #expect(model.status == .partial)
    }

    @Test func interruptionDuringStartupStopsAfterUncooperativeStartupReturns() async throws {
        let manager = TestRecordingController(startMode: .pending)
        let model = RecordingViewModel(manager: manager)
        model.startRecording()
        model.interruptRecording("Mac sleeping")
        await manager.finishStart()
        try await waitUntil(timeoutNanoseconds: 1_000_000_000) { model.status == .partial }
        #expect(await manager.stopCount == 1)
        #expect(await manager.interruptionReason == "Mac sleeping")
    }
}
