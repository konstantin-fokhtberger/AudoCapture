@preconcurrency import AVFoundation
import Foundation

/// Serializes buffer conversion and closing. It never queues an unbounded copy of audio.
final class CaptureBufferWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.codex.AudoCapture.capture-writer")
    private let writer: PCMFileWriter
    private let targetFormat: AVAudioFormat
    private let timelineStart: Double?
    private var nextInputTime: Double?
    private var segmentStartFrame: Int64 = 0
    private var segmentProducedFrames: Int64 = 0
    private var writtenFrames: Int64 = 0
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var accepting = false
    private var muted = false

    func setMuted(_ value: Bool) {
        var errorMessage: String?
        queue.sync {
            guard muted != value else { return }
            do {
                if let converter {
                    try AVAudioPCMBuffer.drain(converter, targetFormat: targetFormat) { try writeConverted($0) }
                    self.converter = nil
                }
                muted = value
            } catch { errorMessage = error.localizedDescription }
        }
        if let errorMessage { fail(errorMessage) }
    }
    private var failure: String?
    private var failureHandler: (@Sendable (String) -> Void)?

    init(writer: PCMFileWriter, targetFormat: AVAudioFormat, timelineStart: Double? = nil) {
        self.timelineStart = timelineStart
        self.writer = writer
        self.targetFormat = targetFormat
    }

    func setFailureHandler(_ handler: @escaping @Sendable (String) -> Void) {
        queue.sync { failureHandler = handler }
    }

    func prepare() throws {
        try queue.sync {
            try writer.prepare()
            converter = nil
            nextInputTime = nil
            segmentStartFrame = 0
            segmentProducedFrames = 0
            writtenFrames = 0
            sourceFormat = nil
            failure = nil
            accepting = true
        }
    }

    func append(_ buffer: AVAudioPCMBuffer, at hostTime: Double? = nil) {
        var notification: ((@Sendable (String) -> Void), String)?
        queue.sync {
            guard accepting, failure == nil else { return }
            do {
                if let sourceFormat, sourceFormat != buffer.format {
                    throw RecordingError.incompatibleAudioFormat("Audio format changed. Start a new recording.")
                }
                try alignInput(buffer, hostTime: hostTime)
                sourceFormat = buffer.format
                if buffer.format == targetFormat {
                    try writeConverted(buffer)
                } else {
                    if converter == nil {
                        converter = AVAudioConverter(from: buffer.format, to: targetFormat)
                    }
                    guard let converter else {
                        throw RecordingError.incompatibleAudioFormat("Could not create audio converter.")
                    }
                    let output = try AVAudioPCMBuffer.makeCopy(from: buffer, using: converter, targetFormat: targetFormat)
                    if output.frameLength > 0 { try writeConverted(output) }
                }
            } catch {
                failure = error.localizedDescription
                if let failureHandler { notification = (failureHandler, error.localizedDescription) }
            }
        }
        if let (handler, message) = notification { handler(message) }
    }

    private func alignInput(_ buffer: AVAudioPCMBuffer, hostTime: Double?) throws {
        guard let timelineStart else { return }
        guard let hostTime, hostTime.isFinite, timelineStart.isFinite,
              abs(hostTime - timelineStart) < 86_400, buffer.format.sampleRate > 0 else {
            throw RecordingError.incompatibleAudioFormat("Invalid audio timestamp.")
        }
        // Ignore sub-5 ms clock jitter. Larger discontinuities start a new segment;
        // placement below preserves silence and trims overlaps without a DSP engine.
        if nextInputTime == nil || abs(hostTime - nextInputTime!) > 0.005 {
            if let converter {
                try AVAudioPCMBuffer.drain(converter, targetFormat: targetFormat) { try writeConverted($0) }
                self.converter = nil
            }
            segmentStartFrame = Int64(((hostTime - timelineStart) * targetFormat.sampleRate).rounded())
            segmentProducedFrames = 0
            nextInputTime = hostTime
        }
        nextInputTime! += Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private func writeConverted(_ buffer: AVAudioPCMBuffer) throws {
        let desired = timelineStart == nil ? writtenFrames : segmentStartFrame + segmentProducedFrames
        segmentProducedFrames += Int64(buffer.frameLength)
        if desired > writtenFrames {
            guard let silence = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4_096) else {
                throw RecordingError.failedToCreateFile("Could not allocate silence buffer.")
            }
            while writtenFrames < desired {
                silence.frameLength = AVAudioFrameCount(min(4_096, desired - writtenFrames))
                for item in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                    if let data = item.mData { memset(data, 0, Int(item.mDataByteSize)) }
                }
                try writer.append(silence)
                writtenFrames += Int64(silence.frameLength)
            }
        }
        let skip = min(Int64(buffer.frameLength), max(0, writtenFrames - desired))
        guard skip < Int64(buffer.frameLength) else { return }
        let output: AVAudioPCMBuffer
        if skip == 0 {
            output = buffer
        } else {
            let length = AVAudioFrameCount(Int64(buffer.frameLength) - skip)
            guard let trimmed = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: length) else {
                throw RecordingError.failedToCreateFile("Could not allocate overlap buffer.")
            }
            trimmed.frameLength = length
            let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(trimmed.mutableAudioBufferList)
            for index in destination.indices {
                guard let from = source[index].mData, let to = destination[index].mData else { continue }
                memcpy(to, from.advanced(by: Int(skip) * bytesPerFrame), Int(length) * bytesPerFrame)
            }
            output = trimmed
        }
        if muted {
            guard let silence = AVAudioPCMBuffer(pcmFormat: output.format, frameCapacity: output.frameLength) else {
                throw RecordingError.failedToCreateFile("Could not allocate muted audio buffer.")
            }
            silence.frameLength = output.frameLength
            for part in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                if let data = part.mData { memset(data, 0, Int(part.mDataByteSize)) }
            }
            try writer.append(silence)
        } else {
            try writer.append(output)
        }
        writtenFrames += Int64(output.frameLength)
    }

    /// Freeze valid audio on an environment change; unlike an I/O failure it remains exportable.
    func interrupt(_ message: String) {
        let handler: (@Sendable (String) -> Void)? = queue.sync {
            guard accepting, failure == nil else { return nil }
            accepting = false
            return failureHandler
        }
        handler?(message)
    }

    func fail(_ message: String) {
        let handler: (@Sendable (String) -> Void)? = queue.sync {
            guard accepting, failure == nil else { return nil }
            failure = message
            return failureHandler
        }
        handler?(message)
    }

    func finish() throws -> AVAudioFramePosition {
        try queue.sync {
            accepting = false
            defer { converter = nil }
            if failure == nil, let converter {
                do {
                    try AVAudioPCMBuffer.drain(converter, targetFormat: targetFormat) { try writeConverted($0) }
                } catch {
                    failure = error.localizedDescription
                }
            }
            // Always close the file, including after conversion or disk errors.
            let frames = writer.finalize()
            if let failure { throw RecordingError.failedToStopCapture(failure) }
            return frames
        }
    }
}
