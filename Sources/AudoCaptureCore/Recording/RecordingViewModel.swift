import Combine
import Foundation
import CoreMedia

@MainActor
public final class RecordingViewModel: ObservableObject {
    @Published public private(set) var status: RecordingStatus = .idle
    @Published public var environmentWarning: String?
    @Published public var errorMessage: String?
    @Published public var noticeMessage: String?
    @Published public var lastOutputDirectory: String?
    @Published public private(set) var lastOutputFile: String?
    @Published public private(set) var lastRecordingStart: String?
    @Published public private(set) var canRetryExport = false
    @Published public var permissionSummary: String = ""
    @Published public private(set) var availableMicrophones: [MicrophoneDevice] = []
    @Published public var selectedMicrophoneID: UInt32?

    @Published public private(set) var activeTracks: [TrackKind] = []
    @Published public private(set) var elapsedSeconds: Double = 0
    private var hostStartedAt: Double?
    private let hostTime: () -> Double
    private let manager: any RecordingControlling
    private var operation: Task<Void, Never>?
    private var terminating = false
    private var captureFailure: String?
    private var recordingID = UUID()

    public init(manager: any RecordingControlling = RecordingManager(), hostTime: @escaping () -> Double = { CMClockGetTime(CMClockGetHostTimeClock()).seconds }) {
        self.hostTime = hostTime
        self.manager = manager
    }

    public func refreshPermissions() {
        let snapshot = manager.permissionSnapshot()
        permissionSummary = "Microphone: \(snapshot.microphoneGranted ? "granted" : "missing") | Screen Recording: \(snapshot.screenCaptureGranted ? "granted" : "missing")"
    }

    public func refreshMicrophones() {
        let devices = manager.availableMicrophones()
        availableMicrophones = devices
        if devices.contains(where: { $0.id == selectedMicrophoneID }) == false {
            selectedMicrophoneID = devices.first(where: { $0.isDefault })?.id ?? devices.first?.id
        }
    }

    public var isMicrophonePermissionMissing: Bool {
        manager.permissionSnapshot().microphoneGranted == false
    }

    public var isScreenRecordingPermissionMissing: Bool {
        manager.permissionSnapshot().screenCaptureGranted == false
    }

    public func startRecording() {
        guard !terminating, status == .idle || status == .completed || status == .partial || status == .failed else { return }
        errorMessage = nil
        noticeMessage = nil
        captureFailure = nil
        canRetryExport = false
        activeTracks = []
        elapsedSeconds = 0
        hostStartedAt = nil
        status = .starting
        recordingID = UUID()
        let id = recordingID

        operation = Task {
            await manager.setFailureHandler { [weak self] message in
                Task { @MainActor in
                    guard let self, self.recordingID == id, self.status == .starting || self.status == .recording else { return }
                    self.captureFailure = message
                    self.errorMessage = message
                    if self.status == .recording { self.stopRecording() }
                }
            }
            do {
                let report = try await manager.startRecording(preferredMicrophoneDeviceID: selectedMicrophoneID)
                activeTracks = report.activeTracks
                hostStartedAt = report.hostStartedAt ?? hostTime()
                updateElapsedTime()
                status = .recording
                noticeMessage = report.warnings.isEmpty ? nil : report.warnings.joined(separator: "\n")
                refreshPermissions()
                if captureFailure != nil { stopRecording() }
            } catch is CancellationError {
                status = .idle
                noticeMessage = captureFailure ?? "Запуск записи отменён."
            } catch {
                status = .failed
                errorMessage = error.localizedDescription
                refreshPermissions()
            }
        }
    }

    public func updateElapsedTime() {
        guard let hostStartedAt, status == .starting || status == .recording else { return }
        elapsedSeconds = max(0, hostTime() - hostStartedAt)
    }

    public var elapsedText: String {
        let seconds = Int(max(0, elapsedSeconds))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    public func refreshEnvironment() {
        refreshPermissions()
        if !shouldDelayTermination { refreshMicrophones() }
    }

    public func interruptRecording(_ reason: String) {
        guard status == .starting || status == .recording else { return }
        captureFailure = captureFailure ?? reason
        errorMessage = captureFailure
        if status == .starting { operation?.cancel() }
        else { beginStop(openFolder: false) }
    }

    public func stopRecording() {
        beginStop(openFolder: !terminating)
    }

    private func beginStop(openFolder: Bool) {
        guard status == .recording else { return }
        updateElapsedTime()
        status = .processing
        errorMessage = captureFailure

        operation = Task {
            do {
                if let captureFailure { await manager.noteInterruption(captureFailure) }
                let result = try await manager.stopRecording(openFolder: openFolder, bitrate: 192)
                applyStopResult(result)
            } catch {
                status = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    public func retryExport() {
        guard canRetryExport, !shouldDelayTermination, !terminating else { return }
        status = .processing
        errorMessage = nil
        operation = Task {
            do { applyStopResult(try await manager.retryExport(openFolder: true)) }
            catch { status = .failed; errorMessage = error.localizedDescription }
        }
    }

    public var shouldDelayTermination: Bool {
        switch status {
        case .starting, .recording, .processing:
            return true
        case .idle, .completed, .partial, .failed:
            return false
        }
    }

    @discardableResult
    public func prepareForTermination() async -> Bool {
        terminating = true
        defer { terminating = false }
        if status == .starting { operation?.cancel() }
        await operation?.value
        if status == .recording { beginStop(openFolder: false) }
        await operation?.value
        return !shouldDelayTermination
    }

    public func openMicrophoneSettings() {
        manager.openMicrophoneSettings()
    }

    public func openScreenRecordingSettings() {
        manager.openScreenRecordingSettings()
    }

    public var selectedMicrophoneName: String {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.name ?? "Default"
    }

    private func applyStopResult(_ result: RecordingSessionResult) {
        lastOutputDirectory = result.directoryURL.path
        lastOutputFile = result.metadata.artifacts.m4a
        // Preserve the start timezone already captured in the published filename.
        if let path = lastOutputFile {
            let date = String(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.prefix(16))
            lastRecordingStart = String(date.prefix(13)) + ":" + String(date.suffix(2))
        } else { lastRecordingStart = nil }
        canRetryExport = result.canRetryExport
        errorMessage = captureFailure
        noticeMessage = nil
        elapsedSeconds = result.metadata.durationSeconds
        if result.metadata.warnings.isEmpty == false {
            noticeMessage = result.metadata.warnings.joined(separator: "\n")
        }
        if result.metadata.errors.isEmpty == false {
            errorMessage = result.metadata.errors.joined(separator: "\n")
        }

        switch result.metadata.postProcessingStatus {
        case .completed:
            status = result.metadata.captureStatus == .failed ? .failed
                : (captureFailure != nil || result.metadata.captureStatus == .partial || !result.metadata.errors.isEmpty || !result.metadata.warnings.isEmpty ? .partial : .completed)
        case .partialFailure:
            status = .partial
        case .pending, .failed:
            status = .failed
        }
    }
}
