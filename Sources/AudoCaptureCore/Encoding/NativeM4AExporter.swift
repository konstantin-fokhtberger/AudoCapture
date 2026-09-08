@preconcurrency import AVFoundation
import Foundation

public struct AudioExportInput: Sendable {
    public let kind: TrackKind
    public let url: URL

    public init(kind: TrackKind, url: URL) { self.kind = kind; self.url = url }
}

public protocol RecordingExporting: Sendable {
    func validate(_ url: URL, expectedDuration: Double) async throws
    /// Returns the actual published URL, including a collision suffix if necessary.
    func export(inputs: [AudioExportInput], to outputURL: URL, minimumDuration: Double, bitrate: Int) async throws -> URL
}

public struct NativeM4AExporter: RecordingExporting {
    public init() {}

    public func validate(_ url: URL, expectedDuration: Double) async throws {
        guard expectedDuration.isFinite, (0...86_400).contains(expectedDuration) else {
            throw RecordingError.encoderFailed("Invalid expected duration.")
        }
        let work = Task.detached(priority: .utility) {
            try autoreleasepool { try Self.verify(url, expectedFrames: Int64((expectedDuration * 48_000).rounded())) }
        }
        try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    public func export(inputs: [AudioExportInput], to outputURL: URL, minimumDuration: Double, bitrate: Int) async throws -> URL {
        let work = Task.detached(priority: .utility) {
            try Self.exportFile(inputs: inputs, outputURL: outputURL, minimumDuration: minimumDuration, bitrate: bitrate)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    private static func exportFile(inputs: [AudioExportInput], outputURL: URL, minimumDuration: Double, bitrate: Int) throws -> URL {
        try Task.checkCancellation()
        guard !inputs.isEmpty, inputs.count <= 2, Set(inputs.map(\.kind)).count == inputs.count,
              minimumDuration.isFinite, (0...86_400).contains(minimumDuration),
              (64...320).contains(bitrate), outputURL.pathExtension.lowercased() == "m4a" else {
            throw RecordingError.encoderFailed("Invalid M4A export parameters.")
        }
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Releasing AVAudioFile closes the AAC container on macOS 14 as well as newer OS versions.
        let frames = try autoreleasepool {
            try writeMix(inputs: inputs, to: temporary, minimumDuration: minimumDuration, bitrate: bitrate)
        }
        try autoreleasepool { try verify(temporary, expectedFrames: frames) }
        try Task.checkCancellation()
        // A same-directory hard link publishes a fully verified file atomically without replacing
        // an existing name. The temporary link is removed by defer.
        for suffix in 1...10_000 {
            let candidate = suffix == 1 ? outputURL : directory.appendingPathComponent(
                "\(outputURL.deletingPathExtension().lastPathComponent) (\(suffix)).m4a")
            do {
                try FileManager.default.linkItem(at: temporary, to: candidate)
                return candidate
            } catch {
                guard FileManager.default.fileExists(atPath: candidate.path) else { throw error }
            }
        }
        throw RecordingError.encoderFailed("Could not select an unused recording filename.")
    }

    private static func writeMix(inputs: [AudioExportInput], to url: URL, minimumDuration: Double, bitrate: Int) throws -> Int64 {
        let files = try inputs.map { try AVAudioFile(forReading: $0.url) }
        guard files.allSatisfy({ $0.processingFormat.sampleRate == 48_000 && (1...2).contains($0.processingFormat.channelCount) }),
              files.allSatisfy({ $0.length >= 0 && $0.length <= 48_000 * 86_400 }),
              files.contains(where: { $0.length > 0 }) else {
            throw RecordingError.encoderFailed("Expected normalized 48 kHz mono/stereo PCM sources.")
        }
        let totalFrames = max(Int64((minimumDuration * 48_000).rounded()), files.map(\.length).max() ?? 0)
        guard totalFrames > 0 else { throw RecordingError.encoderFailed("The recording contains no audio frames.") }
        let output = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: bitrate * 1_000
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let readers = try files.map { file -> AVAudioPCMBuffer in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096) else {
                throw RecordingError.encoderFailed("Could not allocate input buffer.")
            }
            return buffer
        }
        guard let mix = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: 4_096),
              let mixed = mix.floatChannelData else {
            throw RecordingError.encoderFailed("Could not allocate mixing buffer.")
        }
        let gain = Float(0.9 / Double(files.count))
        var position: Int64 = 0
        while position < totalFrames {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(4_096, totalFrames - position))
            mix.frameLength = count
            for channel in 0..<2 { mixed[channel].update(repeating: 0, count: Int(count)) }
            for (index, file) in files.enumerated() {
                let input = readers[index]
                input.frameLength = 0
                let remaining = file.length - file.framePosition
                if remaining > 0 {
                    try file.read(into: input, frameCount: AVAudioFrameCount(min(Int64(count), remaining)))
                    guard input.frameLength > 0 else { throw RecordingError.encoderFailed("Unexpected end of PCM source.") }
                }
                guard let samples = input.floatChannelData else { throw RecordingError.encoderFailed("Unsupported source processing format.") }
                for channel in 0..<2 {
                    let source = samples[min(channel, Int(input.format.channelCount) - 1)]
                    for frame in 0..<Int(input.frameLength) {
                        guard source[frame].isFinite else { throw RecordingError.encoderFailed("Invalid PCM sample.") }
                        mixed[channel][frame] += max(-1, min(1, source[frame])) * gain
                    }
                }
            }
            try output.write(from: mix)
            position += Int64(count)
        }
        return totalFrames
    }

    private static func verify(_ url: URL, expectedFrames: Int64) throws {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC,
              file.processingFormat.channelCount == 2, file.processingFormat.sampleRate == 48_000,
              abs(file.length - expectedFrames) <= 2_048,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096) else {
            throw RecordingError.encoderFailed("M4A format or duration verification failed.")
        }
        var decoded: Int64 = 0
        while decoded < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 4_096)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw RecordingError.encoderFailed("M4A decoding stopped before the end of the recording.")
            }
            for channel in 0..<2 {
                for frame in 0..<Int(buffer.frameLength) where !channels[channel][frame].isFinite {
                    throw RecordingError.encoderFailed("Invalid decoded M4A sample.")
                }
            }
            decoded += Int64(buffer.frameLength)
        }
    }
}
