@preconcurrency import AVFoundation
import AudioToolbox
import Foundation
import CoreMedia

public final class MicrophoneCaptureService: @unchecked Sendable {
    private var configurationObserver: NSObjectProtocol?
    private let engine = AVAudioEngine()
    private let bufferWriter: CaptureBufferWriter
    private let logger: AppLogger
    private let preferredDeviceID: AudioDeviceID?
    private(set) public var deviceName: String?

    public init(writer: PCMFileWriter, targetFormat: AVAudioFormat, preferredDeviceID: AudioDeviceID? = nil, logger: AppLogger = .shared, timelineStart: Double? = nil) {
        self.bufferWriter = CaptureBufferWriter(writer: writer, targetFormat: targetFormat, timelineStart: timelineStart)
        self.preferredDeviceID = preferredDeviceID
        self.logger = logger
    }

    public func start() async throws {
        try configurePreferredInputDevice()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        deviceName = AVAudioSessionDeviceResolver.currentInputName(preferredDeviceID: preferredDeviceID)

        try bufferWriter.prepare()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            guard time.isHostTimeValid else {
                self.bufferWriter.fail("Microphone timestamp is unavailable.")
                return
            }
            self.bufferWriter.append(buffer, at: CMClockMakeHostTimeFromSystemUnits(time.hostTime).seconds)
        }

        do {
            try engine.start()
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { [weak self] _ in
                self?.bufferWriter.interrupt("Конфигурация микрофона изменилась. Проверьте устройство и начните новую запись.")
            }
            await logger.info("Microphone capture started.")
        } catch {
            throw RecordingError.failedToStartCapture(error.localizedDescription)
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    public func stop() async throws -> AVAudioFramePosition {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let frames = try bufferWriter.finish()
        await logger.info("Microphone capture stopped.")
        return frames
    }

    public func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {
        bufferWriter.setFailureHandler(handler)
    }

    private func configurePreferredInputDevice() throws {
        guard let preferredDeviceID else { return }
        let catalog = MicrophoneDeviceCatalog()
        let defaultDeviceID = catalog.defaultInputDeviceID()
        if preferredDeviceID == defaultDeviceID {
            return
        }

        guard let audioUnit = engine.inputNode.audioUnit else {
            throw RecordingError.deviceUnavailable("AVAudioEngine input audio unit is unavailable for microphone selection.")
        }

        var deviceID = preferredDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw RecordingError.deviceUnavailable(
                "Could not select the requested microphone device. On macOS, AVAudioEngine input-device selection is best effort and may require the device to be available through the engine's I/O configuration."
            )
        }
    }
}

extension MicrophoneCaptureService: RecordingCaptureService {
    public var sourceDescription: String? { deviceName }
}

enum AVAudioSessionDeviceResolver {
    static func currentInputName(preferredDeviceID: AudioDeviceID?) -> String? {
        if let preferredDeviceID {
            return MicrophoneDeviceCatalog().availableMicrophones().first(where: { $0.id == preferredDeviceID })?.name
        }
        return AVCaptureDevice.default(for: .audio)?.localizedName
    }
}
