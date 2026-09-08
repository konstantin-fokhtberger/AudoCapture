import AVFoundation
import Foundation
import Testing
@testable import AudoCaptureCore

struct RecordingLifecycleTests {
    @Test func secondStartIsRejectedWhileFirstAwaitsPermissions() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleGate()
        let mic = LifecycleCapture()
        let system = LifecycleCapture()
        let manager = makeManager(root: root, mic: mic, system: system, permissions: LifecyclePermissions(gate: gate))
        let starting = Task { try await manager.startRecording() }
        try await gate.waitUntilEntered()
        await #expect(throws: RecordingError.self) { try await manager.startRecording() }
        await gate.open()
        _ = try await starting.value
        #expect(await mic.starts == 1)
        #expect(await system.starts == 1)
        _ = try await manager.stopRecording(openFolder: false)
    }

    @Test func startDuringStopIsRejected() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleGate()
        let mic = LifecycleCapture(stopGate: gate)
        let manager = makeManager(root: root, mic: mic, system: LifecycleCapture())
        _ = try await manager.startRecording()
        let stopping = Task { try await manager.stopRecording(openFolder: false) }
        try await gate.waitUntilEntered()
        await #expect(throws: RecordingError.self) { try await manager.startRecording() }
        await #expect(throws: RecordingError.self) { try await manager.stopRecording(openFolder: false) }
        await gate.open()
        _ = try await stopping.value
        _ = try await manager.startRecording()
        _ = try await manager.stopRecording(openFolder: false)
        #expect(await mic.starts == 2)
        #expect(await mic.stops == 2)
    }

    @Test func cancelledPermissionWaitNeverStartsCaptureAndCanRetry() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleGate()
        let mic = LifecycleCapture()
        let manager = makeManager(root: root, mic: mic, system: LifecycleCapture(), permissions: LifecyclePermissions(gate: gate))
        let starting = Task { try await manager.startRecording() }
        try await gate.waitUntilEntered()
        starting.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(await mic.starts == 0)
        _ = try await manager.startRecording()
        _ = try await manager.stopRecording(openFolder: false)
        #expect(await mic.starts == 1)
    }

    @Test func runtimeFailureReachesObserverAndMetadata() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let mic = LifecycleCapture()
        let system = LifecycleCapture()
        let manager = makeManager(root: root, mic: mic, system: system)
        let failures = FailureCollector()
        await manager.setFailureHandler { failures.append($0) }
        _ = try await manager.startRecording()
        mic.emitFailure("device disconnected")
        for _ in 0..<100 {
            if !failures.messages.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(failures.messages == ["mic: device disconnected"])
        let result = try await manager.stopRecording(openFolder: false)
        #expect(result.metadata.captureStatus == .partial)
        #expect(result.metadata.errors.contains("mic: device disconnected"))
    }

    @Test func stopFailureKeepsUnknownMetricsAndSkipsUnsafeExport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let encoder = LifecycleEncoder()
        let manager = makeManager(root: root, mic: LifecycleCapture(),
            system: LifecycleCapture(stopError: .failedToStopCapture("not finalized")), encoder: encoder)
        _ = try await manager.startRecording()
        let result = try await manager.stopRecording(openFolder: false)
        #expect(result.metadata.captureStatus == .partial)
        #expect(result.metadata.trackMetrics.first { $0.kind == .system }?.frameCount == nil)
        #expect(result.metadata.syncDiagnostics.absoluteDurationDeltaSeconds == nil)
        #expect(await encoder.outputs == ["mic"])
        #expect(FileManager.default.fileExists(atPath: try #require(result.metadata.artifacts.systemPCM)))
    }

    @Test func cancellationDuringCaptureStartStopsBothSources() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleGate()
        let mic = LifecycleCapture(startGate: gate)
        let system = LifecycleCapture()
        let manager = makeManager(root: root, mic: mic, system: system)
        let starting = Task { try await manager.startRecording() }
        try await gate.waitUntilEntered()
        starting.cancel()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(await mic.stops == 1)
        #expect(await system.stops == 1)
        _ = try await manager.startRecording()
        _ = try await manager.stopRecording(openFolder: false)
    }

    @Test func failedExportCanRetryWithoutRecapturingAndOnlyThenDeletesSources() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let mic = LifecycleCapture()
        let system = LifecycleCapture()
        let manager = makeManager(root: root, mic: mic, system: system, encoder: LifecycleEncoder(failuresRemaining: 1))
        _ = try await manager.startRecording()
        let failed = try await manager.stopRecording(openFolder: false)
        #expect(failed.canRetryExport)
        #expect(failed.metadata.postProcessingStatus == .failed)
        let micPath = try #require(failed.metadata.artifacts.micPCM)
        let systemPath = try #require(failed.metadata.artifacts.systemPCM)
        #expect(FileManager.default.fileExists(atPath: micPath))
        #expect(FileManager.default.fileExists(atPath: systemPath))
        let success = try await manager.retryExport(openFolder: false)
        #expect(success.metadata.postProcessingStatus == .completed)
        #expect(success.metadata.errors.isEmpty)
        #expect(!success.canRetryExport)
        #expect(success.metadata.startedAt == failed.metadata.startedAt)
        #expect(FileManager.default.fileExists(atPath: try #require(success.metadata.artifacts.m4a)))
        #expect(!FileManager.default.fileExists(atPath: micPath))
        #expect(!FileManager.default.fileExists(atPath: systemPath))
        #expect(await mic.stops == 1)
        #expect(await system.stops == 1)
    }

    @Test func environmentInterruptionPersistsPartialCaptureWithValidExport() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeManager(root: root, mic: LifecycleCapture(), system: LifecycleCapture())
        _ = try await manager.startRecording()
        await manager.noteInterruption("Mac sleeping")
        let result = try await manager.stopRecording(openFolder: false)
        #expect(result.metadata.captureStatus == .partial)
        #expect(result.metadata.postProcessingStatus == .completed)
        #expect(result.metadata.errors == ["Mac sleeping"])
        #expect(result.metadata.artifacts.m4a != nil)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func makeManager(root: URL, mic: LifecycleCapture, system: LifecycleCapture,
        permissions: LifecyclePermissions = .init(), encoder: LifecycleEncoder = .init()) -> RecordingManager {
        RecordingManager(permissionsManager: permissions,
            directoryManager: RecordingDirectoryManager(recordingsRootOverride: root),
            exporter: encoder, logger: .disabled, captureFactory: LifecycleFactory(mic: mic, system: system),
            folderOpener: LifecycleFolder(), microphoneCatalog: LifecycleCatalog())
    }
}

private actor LifecycleGate {
    private var entered = false
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        if !opened { await withCheckedContinuation { waiters.append($0) } }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
    func waitUntilEntered() async throws {
        for _ in 0..<100 {
            if entered { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        open()
        throw RecordingError.failedToStartCapture("Test gate was not entered")
    }
}

private struct LifecyclePermissions: PermissionsProviding {
    var gate: LifecycleGate?
    func currentStatus() -> PermissionsSnapshot { .init(microphoneGranted: true, screenCaptureGranted: true) }
    func requestRequiredPermissions() async throws { await gate?.wait() }
    func openSystemSettingsForMicrophone() {}
    func openSystemSettingsForScreenCapture() {}
}

private actor LifecycleCapture: RecordingCaptureService {
    nonisolated let sourceDescription: String? = "test source"
    private nonisolated let callback = LifecycleFailureCallback()
    private let startGate: LifecycleGate?
    private let stopGate: LifecycleGate?
    private let stopError: RecordingError?
    private(set) var starts = 0
    private(set) var stops = 0
    init(startGate: LifecycleGate? = nil, stopGate: LifecycleGate? = nil, stopError: RecordingError? = nil) {
        self.startGate = startGate
        self.stopGate = stopGate
        self.stopError = stopError
    }
    nonisolated func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) { callback.install(handler) }
    nonisolated func emitFailure(_ message: String) { callback.emit(message) }
    func start() async throws { starts += 1; await startGate?.wait() }
    func stop() async throws -> AVAudioFramePosition {
        stops += 1
        await stopGate?.wait()
        if let stopError { throw stopError }
        return 48_000
    }
}

private final class LifecycleFailureCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (String) -> Void)?
    func install(_ handler: @escaping @Sendable (String) -> Void) { lock.lock(); self.handler = handler; lock.unlock() }
    func emit(_ message: String) { lock.lock(); let current = handler; lock.unlock(); current?(message) }
}

private struct LifecycleFactory: RecordingCaptureFactory {
    let mic: LifecycleCapture
    let system: LifecycleCapture
    func makeCapturePair(layout: RecordingDirectoryLayout, plan: AudioSessionPlan, logger: AppLogger, preferredMicrophoneDeviceID: UInt32?) -> RecordingCapturePair {
        FileManager.default.createFile(atPath: layout.micPCM.path, contents: Data())
        FileManager.default.createFile(atPath: layout.systemPCM.path, contents: Data())
        return .init(microphone: mic, system: system)
    }
}

private actor LifecycleEncoder: RecordingExporting {
    func validate(_ url: URL, expectedDuration: Double) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingError.encoderFailed("Missing output") }
    }
    var failuresRemaining: Int
    init(failuresRemaining: Int = 0) { self.failuresRemaining = failuresRemaining }
    private(set) var outputs: [String] = []
    func export(inputs: [AudioExportInput], to outputURL: URL, minimumDuration: Double, bitrate: Int) async throws -> URL {
        if failuresRemaining > 0 { failuresRemaining -= 1; throw RecordingError.encoderFailed("Simulated failure") }
        outputs.append(contentsOf: inputs.map { $0.kind.rawValue })
        try Data("encoded".utf8).write(to: outputURL)
        return outputURL
    }
}
private struct LifecycleFolder: RecordingsFolderOpening { func open(directoryURL: URL) async {} }
private struct LifecycleCatalog: MicrophoneDeviceProviding { func availableMicrophones() -> [MicrophoneDevice] { [] } }
