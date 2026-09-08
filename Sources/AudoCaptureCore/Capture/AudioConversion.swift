@preconcurrency import AVFoundation
import CoreMedia
import Foundation

enum AudioConversionError: Error {
    case missingFormatDescription
    case missingASBD
    case failedToCopyPCM(OSStatus)
}

private final class ConversionConsumptionState: @unchecked Sendable {
    var consumed = false
}

extension AVAudioPCMBuffer {
    static func drain(
        _ converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        append: (AVAudioPCMBuffer) throws -> Void
    ) throws {
        // A bounded loop detects a converter that fails to reach end-of-stream.
        for _ in 0..<32 {
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4_096) else {
                throw RecordingError.incompatibleAudioFormat("Could not allocate converter tail buffer.")
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                inputStatus.pointee = .endOfStream
                return nil
            }
            if let error { throw error }
            guard status != .error else {
                throw RecordingError.incompatibleAudioFormat("Could not finish audio conversion.")
            }
            if output.frameLength > 0 { try append(output) }
            if status == .endOfStream { return }
        }
        throw RecordingError.incompatibleAudioFormat("Audio converter did not finish.")
    }

    static func makeCopy(
        from sourceBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let ratio = targetFormat.sampleRate / sourceBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw RecordingError.incompatibleAudioFormat("Could not allocate conversion buffer.")
        }

        var error: NSError?
        let state = ConversionConsumptionState()
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if state.consumed == false {
                state.consumed = true
                outStatus.pointee = .haveData
                return sourceBuffer
            } else {
                // This buffer is exhausted, but the capture stream continues.
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        if let error {
            throw error
        }
        guard status != .error else {
            throw RecordingError.incompatibleAudioFormat("Audio conversion failed.")
        }
        return converted
    }

    static func make(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw AudioConversionError.missingFormatDescription
        }
        guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioConversionError.missingASBD
        }

        var asbd = asbdPointer.pointee
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw RecordingError.incompatibleAudioFormat("Could not build AVAudioFormat from system audio sample.")
        }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw RecordingError.incompatibleAudioFormat("Could not allocate system audio PCM buffer.")
        }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw AudioConversionError.failedToCopyPCM(status)
        }

        return buffer
    }
}

extension AVAudioFormat {
    static func recordingFormat(sampleRate: Double, channels: AVAudioChannelCount) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true) else {
            throw RecordingError.incompatibleAudioFormat("Failed to create PCM recording format.")
        }
        return format
    }
}
