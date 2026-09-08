@preconcurrency import AVFoundation
import Foundation
import ScreenCaptureKit

public final class SystemAudioCaptureService: NSObject, @unchecked Sendable {
    private let bufferWriter: CaptureBufferWriter
    private let logger: AppLogger
    private let targetFormat: AVAudioFormat
    private var stream: SCStream?
    private let streamQueue = DispatchQueue(label: "com.codex.AudoCapture.system-audio")
    private let displaySelector: DisplaySelectionPolicy
    private(set) public var sourceName: String?

    public init(writer: PCMFileWriter, targetFormat: AVAudioFormat, logger: AppLogger = .shared, displaySelector: DisplaySelectionPolicy = .mainDisplayPreferred, timelineStart: Double? = nil) {
        self.bufferWriter = CaptureBufferWriter(writer: writer, targetFormat: targetFormat, timelineStart: timelineStart)
        self.targetFormat = targetFormat
        self.logger = logger
        self.displaySelector = displaySelector
        super.init()
    }

    public func start() async throws {
        try bufferWriter.prepare()

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = displaySelector.selectDisplay(from: content.displays) else {
            throw RecordingError.failedToStartCapture("No display is available for ScreenCaptureKit.")
        }

        sourceName = displaySelector.describe(display: display)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.queueDepth = 8
        config.sampleRate = Int(targetFormat.sampleRate)
        config.channelCount = Int(targetFormat.channelCount)
        config.width = 2
        config.height = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: streamQueue)
            try await stream.startCapture()
            await logger.info("System audio capture started.")
        } catch {
            throw RecordingError.failedToStartCapture(error.localizedDescription)
        }
    }

    public func stop() async throws -> AVAudioFramePosition {
        var stopError: Error?
        if let stream {
            do { try await stream.stopCapture() }
            catch { stopError = error }
            // Detach before closing even if ScreenCaptureKit reports a stop error.
            try? stream.removeStreamOutput(self, type: .audio)
        }
        stream = nil
        let frames = try streamQueue.sync { try bufferWriter.finish() }
        if let stopError { throw RecordingError.failedToStopCapture(stopError.localizedDescription) }
        await logger.info("System audio capture stopped.")
        return frames
    }

    public func setMuted(_ muted: Bool) { bufferWriter.setMuted(muted) }

    public func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {
        bufferWriter.setFailureHandler(handler)
    }

    private func handle(sampleBuffer: CMSampleBuffer, stream: SCStream) {
        do {
            guard let clock = stream.synchronizationClock else {
                throw RecordingError.incompatibleAudioFormat("System audio clock is unavailable.")
            }
            let time = CMSyncConvertTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), from: clock, to: CMClockGetHostTimeClock())
            guard time.isNumeric else {
                throw RecordingError.incompatibleAudioFormat("System audio timestamp is unavailable.")
            }
            bufferWriter.append(try AVAudioPCMBuffer.make(from: sampleBuffer), at: time.seconds)
        }
        catch { bufferWriter.fail(error.localizedDescription) }
    }

}

extension SystemAudioCaptureService: SCStreamOutput, SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        bufferWriter.fail("System audio stopped: \(error.localizedDescription)")
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio else { return }
        handle(sampleBuffer: sampleBuffer, stream: stream)
    }
}

extension SystemAudioCaptureService: RecordingCaptureService {
    public var sourceDescription: String? { sourceName }
}

public struct DisplaySelectionPolicy: Sendable {
    public static let mainDisplayPreferred = DisplaySelectionPolicy()

    public init() {}

    public func selectDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        guard displays.isEmpty == false else { return nil }
        let mainDisplayID = CGMainDisplayID()
        return displays.first(where: { $0.displayID == mainDisplayID }) ?? displays.first
    }

    public func describe(display: SCDisplay) -> String {
        let mainLabel = display.displayID == CGMainDisplayID() ? "Main Display" : "Display"
        return "\(mainLabel) \(display.displayID)"
    }
}
