import AVFoundation
import Foundation
import Testing
@testable import AudoCaptureCore

struct RecordingManagerTests {
    @Test
    func startRecordingCleansUpSessionDirectoryWhenBothCapturePipelinesFail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directoryManager = RecordingDirectoryManager(recordingsRootOverride: root)
        let captureFactory = TestCaptureFactory(
            microphone: TestCaptureService(sourceDescription: "Mic", fileURL: nil, startError: RecordingError.failedToStartCapture("mic boom")),
            system: TestCaptureService(sourceDescription: "System", fileURL: nil, startError: RecordingError.failedToStartCapture("system boom"))
        )
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: directoryManager,
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: captureFactory,
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        do {
            _ = try await manager.startRecording()
            Issue.record("Expected startup to fail.")
        } catch let error as RecordingError {
            #expect(error.localizedDescription.contains("mic boom"))
            #expect(error.localizedDescription.contains("system boom"))
        }

        let contents = try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(".sessions"), includingPropertiesForKeys: nil)
        #expect(contents?.isEmpty ?? true)
    }

    @Test
    func startRecordingStopsBeforeDirectoryCreationWhenPermissionsAreDenied() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(
                requestError: RecordingError.microphonePermissionDenied,
                snapshot: PermissionsSnapshot(microphoneGranted: false, screenCaptureGranted: false)
            ),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURL: nil),
                system: TestCaptureService(sourceDescription: "System", fileURL: nil)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        do {
            _ = try await manager.startRecording()
            Issue.record("Expected permission request to fail.")
        } catch let error as RecordingError {
            #expect(error.localizedDescription.contains("Microphone access is not granted"))
        }

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }

    @Test
    func startRecordingFallsBackToMicrophoneOnlyWhenScreenPermissionIsDenied() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(
                requestError: RecordingError.screenCapturePermissionDenied,
                snapshot: PermissionsSnapshot(microphoneGranted: true, screenCaptureGranted: false)
            ),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, stopFrameCount: 48_000),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopFrameCount: 48_000)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let report = try await manager.startRecording()
        #expect(report.activeTracks == [.microphone])
        #expect(report.warnings.contains(where: { $0.contains("Screen Recording access is not granted") }))

        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)
        #expect(result.metadata.artifacts.m4a != nil)
        #expect(result.metadata.artifacts.systemPCM == nil)
        #expect(FileManager.default.fileExists(atPath: result.directoryURL.appendingPathComponent("system.wav").path) == false)
        #expect(result.metadata.postProcessingStatus == .completed)
    }

    @Test
    func startRecordingFallsBackToSystemOnlyWhenMicrophonePermissionIsDeniedAndScreenIsGranted() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(
                requestError: RecordingError.microphonePermissionDenied,
                snapshot: PermissionsSnapshot(microphoneGranted: false, screenCaptureGranted: true)
            ),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, stopFrameCount: 48_000),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopFrameCount: 48_000)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let report = try await manager.startRecording()
        #expect(report.activeTracks == [.system])
        #expect(report.warnings.contains(where: { $0.contains("Microphone access is not granted") }))

        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)
        #expect(result.metadata.artifacts.micPCM == nil)
        #expect(result.metadata.artifacts.m4a != nil)
        #expect(FileManager.default.fileExists(atPath: result.directoryURL.appendingPathComponent("mic.wav").path) == false)
        #expect(result.metadata.postProcessingStatus == .completed)
    }

    @Test
    func stopRecordingPreservesSourcesWhenExportFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directoryManager = RecordingDirectoryManager(recordingsRootOverride: root)
        let captureFactory = TestCaptureFactory(
            microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, stopFrameCount: 96_000),
            system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopFrameCount: 95_520)
        )
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: directoryManager,
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(shouldFail: true),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: captureFactory,
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let report = try await manager.startRecording()
        #expect(report.warnings.isEmpty)
        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)

        #expect(result.metadata.postProcessingStatus == .failed)
        #expect(result.metadata.errors.count == 1)
        #expect(result.metadata.warnings.isEmpty)
        #expect(result.metadata.trackMetrics.count == 2)
        #expect((result.metadata.syncDiagnostics.absoluteDurationDeltaSeconds ?? 0) > 0)
        #expect(FileManager.default.fileExists(atPath: result.directoryURL.appendingPathComponent("metadata.json").path))
    }

    @Test
    func stopRecordingCollectsRuntimeStopFailuresAsErrors() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, stopFrameCount: 48_000),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopError: RecordingError.deviceUnavailable("Bluetooth headset disconnected"))
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        _ = try await manager.startRecording()
        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)

        #expect(result.metadata.errors.contains(where: { $0.contains("Bluetooth headset disconnected") }))
    }

    @Test
    func startRecordingFallsBackToSystemOnlyWhenMicrophoneFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, startError: RecordingError.failedToStartCapture("Mic offline")),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopFrameCount: 96_000)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let report = try await manager.startRecording()
        #expect(report.activeTracks == [.system])
        #expect(report.warnings.count == 1)

        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)
        #expect(result.metadata.devices.microphoneDevice == nil)
        #expect(result.metadata.devices.systemAudioSource == "Main Display")
        #expect(result.metadata.artifacts.micPCM == nil)
        #expect(result.metadata.artifacts.m4a != nil)
        #expect(result.metadata.warnings.count == 1)
        #expect(result.metadata.trackMetrics.count == 1)
        #expect(result.metadata.trackMetrics.first?.kind == .system)
        #expect(result.metadata.postProcessingStatus == .completed)
    }

    @Test
    func startRecordingFallsBackToMicrophoneOnlyWhenSystemFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "USB Microphone", fileURLProvider: { $0.micPCM }, stopFrameCount: 96_000),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, startError: RecordingError.failedToStartCapture("System offline"))
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let report = try await manager.startRecording()
        #expect(report.activeTracks == [.microphone])
        #expect(report.warnings.count == 1)

        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)
        #expect(result.metadata.devices.microphoneDevice == "USB Microphone")
        #expect(result.metadata.devices.systemAudioSource == nil)
        #expect(result.metadata.artifacts.m4a != nil)
        #expect(result.metadata.artifacts.systemPCM == nil)
        #expect(result.metadata.trackMetrics.count == 1)
        #expect(result.metadata.trackMetrics.first?.kind == .microphone)
        #expect(result.metadata.postProcessingStatus == .completed)
    }

    @Test
    func oneTrackEncodeFailureMarksSingleTrackSessionAsFailed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(shouldFail: true),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, startError: RecordingError.failedToStartCapture("Mic offline")),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, stopFrameCount: 96_000)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        _ = try await manager.startRecording()
        let result = try await manager.stopRecording(openFolder: false, bitrate: 192)

        #expect(result.metadata.trackMetrics.count == 1)
        #expect(result.metadata.postProcessingStatus == .failed)
        #expect(result.metadata.errors.count == 1)
    }

    @Test
    func startRecordingStartsPermittedCapturesConcurrently() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let barrier = CaptureStartBarrier()
        let manager = RecordingManager(
            permissionsManager: TestPermissionsProvider(),
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            metadataWriter: MetadataWriter(),
            exporter: TestExporter(),
            logger: .disabled,
            syncCoordinator: AudioSyncCoordinator(),
            captureFactory: TestCaptureFactory(
                microphone: TestCaptureService(sourceDescription: "Mic", fileURLProvider: { $0.micPCM }, startGate: barrier),
                system: TestCaptureService(sourceDescription: "Main Display", fileURLProvider: { $0.systemPCM }, startGate: barrier)
            ),
            folderOpener: NoopFolderOpener(),
            microphoneCatalog: TestMicrophoneCatalog()
        )

        let starting = Task { try await manager.startRecording() }
        let deadline = ContinuousClock.now + .seconds(5)
        while await barrier.arrivals < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        // Both sources must enter before either is allowed to finish startup.
        #expect(await barrier.arrivals == 2)
        await barrier.release()
        _ = try await starting.value
        _ = try await manager.stopRecording(openFolder: false, bitrate: 192)

    }
}

private struct TestPermissionsProvider: PermissionsProviding {
    var requestError: RecordingError? = nil
    var snapshot = PermissionsSnapshot(microphoneGranted: true, screenCaptureGranted: true)

    func currentStatus() -> PermissionsSnapshot { snapshot }

    func requestRequiredPermissions() async throws {
        if let requestError { throw requestError }
    }

    func openSystemSettingsForMicrophone() {}

    func openSystemSettingsForScreenCapture() {}
}

private final class TestCaptureService: RecordingCaptureService, @unchecked Sendable {
    let sourceDescription: String?
    let fileURL: URL?
    let fileURLProvider: ((RecordingDirectoryLayout) -> URL)?
    let startError: RecordingError?
    let stopError: RecordingError?
    let stopFrameCount: Int64
    let startGate: CaptureStartBarrier?

    init(
        sourceDescription: String?,
        fileURL: URL?,
        startError: RecordingError? = nil,
        stopError: RecordingError? = nil,
        stopFrameCount: Int64 = 48_000,
        startGate: CaptureStartBarrier? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.fileURL = fileURL
        self.fileURLProvider = nil
        self.startError = startError
        self.stopError = stopError
        self.stopFrameCount = stopFrameCount
        self.startGate = startGate
    }

    init(
        sourceDescription: String?,
        fileURLProvider: @escaping (RecordingDirectoryLayout) -> URL,
        startError: RecordingError? = nil,
        stopError: RecordingError? = nil,
        stopFrameCount: Int64 = 48_000,
        startGate: CaptureStartBarrier? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.fileURL = nil
        self.fileURLProvider = fileURLProvider
        self.startError = startError
        self.stopError = stopError
        self.stopFrameCount = stopFrameCount
        self.startGate = startGate
    }

    func start() async throws {
        await startGate?.arrive()
        if let startError { throw startError }
        if let fileURL {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
    }

    func stop() async throws -> AVAudioFramePosition {
        if let stopError { throw stopError }
        return AVAudioFramePosition(stopFrameCount)
    }
}

private struct TestCaptureFactory: RecordingCaptureFactory {
    let microphone: TestCaptureService
    let system: TestCaptureService

    func makeCapturePair(layout: RecordingDirectoryLayout, plan: AudioSessionPlan, logger: AppLogger, preferredMicrophoneDeviceID: UInt32?) -> RecordingCapturePair {
        if let fileURLProvider = microphone.fileURLProvider {
            FileManager.default.createFile(atPath: fileURLProvider(layout).path, contents: Data())
        }
        if let fileURLProvider = system.fileURLProvider {
            FileManager.default.createFile(atPath: fileURLProvider(layout).path, contents: Data())
        }
        return RecordingCapturePair(microphone: microphone, system: system)
    }
}

private struct TestExporter: RecordingExporting {
    func validate(_ url: URL, expectedDuration: Double) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingError.encoderFailed("Missing output") }
    }
    var shouldFail = false
    func export(inputs: [AudioExportInput], to outputURL: URL, minimumDuration: Double, bitrate: Int) async throws -> URL {
        if shouldFail { throw RecordingError.encoderFailed("Simulated export failure") }
        try Data("m4a".utf8).write(to: outputURL)
        return outputURL
    }
}

private struct NoopFolderOpener: RecordingsFolderOpening {
    func open(directoryURL: URL) async {}
}

private struct TestMicrophoneCatalog: MicrophoneDeviceProviding {
    func availableMicrophones() -> [MicrophoneDevice] {
        [
            MicrophoneDevice(id: 101, name: "Built-in Microphone", isDefault: true),
            MicrophoneDevice(id: 202, name: "USB Microphone", isDefault: false)
        ]
    }
}

private actor CaptureStartBarrier {
    private(set) var arrivals = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func arrive() async {
        arrivals += 1
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
