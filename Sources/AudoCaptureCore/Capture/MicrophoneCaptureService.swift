@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

/// One explicitly selected input, with no playback graph or system-default mutation.
public final class MicrophoneCaptureService: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.codex.AudoCapture.microphone")
    private let bufferWriter: CaptureBufferWriter
    private let logger: AppLogger
    private let preferredDeviceID: AudioDeviceID?
    private var clock: CMClock?
    private var observers: [NSObjectProtocol] = []
    private(set) public var deviceName: String?

    public init(writer: PCMFileWriter, targetFormat: AVAudioFormat, preferredDeviceID: AudioDeviceID? = nil,
                logger: AppLogger = .shared, timelineStart: Double? = nil) {
        bufferWriter = CaptureBufferWriter(writer: writer, targetFormat: targetFormat, timelineStart: timelineStart)
        self.preferredDeviceID = preferredDeviceID
        self.logger = logger
        super.init()
    }

    public func start() async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.startOnQueue()
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        await logger.info("Microphone capture started (AVCaptureSession).")
    }

    private func startOnQueue() throws {
        let device: AVCaptureDevice?
        if let preferredDeviceID {
            guard let uid = Self.deviceUID(preferredDeviceID) else {
                throw RecordingError.deviceUnavailable("Selected microphone UID is unavailable.")
            }
            device = AVCaptureDevice(uniqueID: uid)
        } else {
            device = AVCaptureDevice.default(for: .audio)
        }
        guard let device, device.hasMediaType(.audio) else {
            throw RecordingError.deviceUnavailable("Selected microphone is unavailable to AVFoundation.")
        }
        let input = try AVCaptureDeviceInput(device: device)
        deviceName = device.localizedName
        try bufferWriter.prepare()
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw RecordingError.failedToStartCapture("Cannot add microphone input.")
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw RecordingError.failedToStartCapture("Cannot add microphone output.")
        }
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.bufferWriter.interrupt("Microphone capture failed: \(error?.localizedDescription ?? "unknown session error")")
        })
        observers.append(center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: device, queue: nil) { [weak self] _ in
            self?.bufferWriter.interrupt("Микрофон отключён. Доступная запись сохранена.")
        })
        session.startRunning()
        guard session.isRunning, let clock = session.synchronizationClock else {
            throw RecordingError.failedToStartCapture("Microphone session or clock did not start.")
        }
        self.clock = clock
    }

    public func stop() async throws -> AVAudioFramePosition {
        let frames: AVAudioFramePosition = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
                self.observers.removeAll()
                self.session.stopRunning()
                self.output.setSampleBufferDelegate(nil, queue: nil)
                // Finalize behind callbacks already queued during stopRunning, preserving the tail.
                self.queue.async {
                    self.clock = nil
                    do { continuation.resume(returning: try self.bufferWriter.finish()) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
        await logger.info("Microphone capture stopped.")
        return frames
    }

    public func setMuted(_ muted: Bool) { bufferWriter.setMuted(muted) }

    public func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {
        bufferWriter.setFailureHandler(handler)
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private static func deviceUID(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

extension MicrophoneCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard let clock else { return }
        do {
            let time = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                       from: clock, to: CMClockGetHostTimeClock())
            guard time.isNumeric else {
                throw RecordingError.incompatibleAudioFormat("Microphone timestamp is unavailable.")
            }
            bufferWriter.append(try AVAudioPCMBuffer.make(from: sampleBuffer), at: time.seconds)
        } catch { bufferWriter.fail(error.localizedDescription) }
    }
}

extension MicrophoneCaptureService: RecordingCaptureService {
    public var sourceDescription: String? { deviceName }
}
